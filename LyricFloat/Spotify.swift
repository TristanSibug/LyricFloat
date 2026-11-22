import AuthenticationServices
import CommonCrypto
import Foundation
import Security
import UIKit

struct SpotifyTrack: Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
}

struct SpotifyPlayback: Sendable {
    let track: SpotifyTrack
    let position: TimeInterval
    let isPlaying: Bool
}

@MainActor
final class Spotify: NSObject, ASWebAuthenticationPresentationContextProviding {
    private struct Tokens: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    private struct Player: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let name: String }

            let id: String?
            let type: String
            let name: String
            let artists: [Artist]?
            let album: Album?
            let durationMs: Int
        }

        let item: Item?
        let progressMs: Int?
        let isPlaying: Bool
    }

    enum Failure: LocalizedError {
        case configuration
        case signInFailed
        case reconnect
        case forbidden
        case rateLimited(TimeInterval)
        case keychain
        case response(Int)

        var errorDescription: String? {
            switch self {
            case .configuration: "Spotify sign-in is unavailable in this build."
            case .signInFailed: "Couldn’t open Spotify sign-in."
            case .reconnect: "Connect Spotify again to resume syncing."
            case .forbidden: "This Spotify account doesn’t have playback access for Lyric Float."
            case .rateLimited: "Spotify is busy. Sync will retry shortly."
            case .keychain: "Lyric Float couldn’t access its saved Spotify connection."
            case .response(let code): "Spotify returned an error (HTTP \(code))."
            }
        }
    }

    let clientID: String?
    private(set) var startupError: String?
    var isConnected: Bool { refreshToken != nil }

    private var accessToken: String?
    private var refreshToken: String?
    private var expiration = Date.distantPast
    private var authenticationSession: ASWebAuthenticationSession?
    private var presentationWindow: UIWindow?

    override init() {
        let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String
        let id = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clientID = id.isEmpty || id.hasPrefix("$(") ? nil : id
        super.init()
        if let clientID {
            do {
                refreshToken = try SpotifyKeychain.read(clientID: clientID)
            } catch {
                startupError = error.localizedDescription
            }
        }
    }

    func connect(window: UIWindow) async throws {
        guard let clientID else { throw Failure.configuration }
        let verifier = Self.base64URL(Self.randomBytes())
        let state = Self.base64URL(Self.randomBytes())
        let challenge = Self.base64URL(Self.sha256(Data(verifier.utf8)))

        var authorization = URLComponents(string: "https://accounts.spotify.com/authorize")!
        authorization.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyAuthorizationResponse.redirectURI),
            URLQueryItem(name: "scope", value: "user-read-currently-playing"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        presentationWindow = window
        defer {
            presentationWindow = nil
            authenticationSession = nil
        }
        let callback = try await authenticate(at: authorization.url!)
        let code = try SpotifyAuthorizationResponse.authorizationCode(from: callback, expectedState: state)

        let tokens = try await Self.requestTokens([
            ("grant_type", "authorization_code"), ("client_id", clientID), ("code", code),
            ("code_verifier", verifier), ("redirect_uri", SpotifyAuthorizationResponse.redirectURI)
        ])
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else { throw Failure.signInFailed }
        try Task.checkCancellation()
        try SpotifyKeychain.save(refreshToken, clientID: clientID)
        self.refreshToken = refreshToken
        install(tokens)
    }

    func disconnect() throws {
        if let clientID { try SpotifyKeychain.remove(clientID: clientID) }
        refreshToken = nil
        accessToken = nil
        expiration = .distantPast
    }

    func playback() async throws -> SpotifyPlayback? {
        let bearer = try await bearerToken()
        do {
            return try await fetchPlayback(bearer: bearer)
        } catch Failure.reconnect {
            let refreshed = try await bearerToken(forceRefresh: true)
            return try await fetchPlayback(bearer: refreshed)
        }
    }

    private func bearerToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let accessToken, expiration.timeIntervalSinceNow > 30 {
            return accessToken
        }
        guard let clientID, let refreshToken else { throw Failure.reconnect }

        let tokens = try await Self.requestTokens([
            ("grant_type", "refresh_token"), ("client_id", clientID), ("refresh_token", refreshToken)
        ])
        try Task.checkCancellation()
        guard self.refreshToken == refreshToken else { throw CancellationError() }
        if let rotated = tokens.refreshToken, !rotated.isEmpty, rotated != refreshToken {
            try SpotifyKeychain.save(rotated, clientID: clientID)
            self.refreshToken = rotated
        }
        install(tokens)
        return tokens.accessToken
    }

    private func install(_ tokens: Tokens) {
        accessToken = tokens.accessToken
        expiration = Date().addingTimeInterval(tokens.expiresIn)
    }

    private func fetchPlayback(bearer: String) async throws -> SpotifyPlayback? {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.timeoutInterval = 10
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        let http = try Self.check(response)
        if http.statusCode == 204 || data.isEmpty { return nil }
        let player = try Self.decoder.decode(Player.self, from: data)
        guard let item = player.item, item.type == "track", let id = item.id,
              let artist = item.artists?.first?.name, let progress = player.progressMs,
              item.durationMs > 0 else { return nil }
        let track = SpotifyTrack(id: id, title: item.name, artist: artist, album: item.album?.name,
                                 duration: Double(item.durationMs) / 1000)
        return SpotifyPlayback(track: track, position: Double(progress) / 1000, isPlaying: player.isPlaying)
    }

    private static func requestTokens(_ fields: [(String, String)]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: unreserved)! }
        request.httpBody = Data(fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 400,
           let payload = try? JSONDecoder().decode([String: String].self, from: data),
           payload["error"] == "invalid_grant" {
            throw Failure.reconnect
        }
        _ = try check(response)
        return try decoder.decode(Tokens.self, from: data)
    }

    private static func check(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw Failure.response(0) }
        switch http.statusCode {
        case 200..<300: return http
        case 401: throw Failure.reconnect
        case 403: throw Failure.forbidden
        case 429:
            let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let delay = seconds.flatMap { $0.isFinite ? max(1, $0) : nil } ?? 30
            throw Failure.rateLimited(delay)
        default: throw Failure.response(http.statusCode)
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyAuthorizationResponse.callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? Failure.signInFailed)
                }
            }
            authenticationSession = session
            session.presentationContextProvider = self
            if !session.start() { continuation.resume(throwing: Failure.signInFailed) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationWindow!
    }

    private static func randomBytes() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func sha256(_ input: Data) -> Data {
        var output = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        input.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(bytes.count), &output)
        }
        return Data(output)
    }

    private static func base64URL(_ input: Data) -> String {
        input.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private enum SpotifyKeychain {
    private static func query(clientID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.lyricfloat.spotify",
            kSecAttrAccount as String: clientID
        ]
    }

    static func read(clientID: String) throws -> String? {
        var attributes = query(clientID: clientID)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { throw Spotify.Failure.keychain }
        return token
    }

    static func save(_ token: String, clientID: String) throws {
        let query = query(clientID: clientID)
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Spotify.Failure.keychain }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw Spotify.Failure.keychain }
    }

    static func remove(clientID: String) throws {
        let status = SecItemDelete(query(clientID: clientID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Spotify.Failure.keychain }
    }
}
