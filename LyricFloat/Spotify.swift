import Foundation
import Security
import SpotifyiOS

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
final class Spotify: NSObject, @preconcurrency SPTAppRemoteDelegate {
    static let callbackScheme = "app.lyricfloat.remote.oauth"
    static let redirectURL = URL(string: "\(callbackScheme)://callback")!

    enum Failure: LocalizedError {
        case notConfigured
        case openSpotify
        case authorizationRejected(String?)
        case authorizationTimedOut
        case savedConnectionUnavailable
        case connectionFailed(Int?)
        case keychain
        case reconnecting
        case playbackUnavailable
        case playbackTimedOut

        var errorDescription: String? {
            switch self {
            case .notConfigured: "App Remote is unavailable in this build."
            case .openSpotify: "Install Spotify and start a song, then try again."
            case .authorizationRejected(let code):
                code.map { "Spotify rejected App Remote access (\($0))." } ?? "Spotify rejected App Remote access."
            case .authorizationTimedOut: "Spotify didn’t finish connecting. Check that a song is playing and try again."
            case .savedConnectionUnavailable: "Start a song in Spotify. Tap Connect Spotify if it needs permission again."
            case .connectionFailed(let code):
                code.map { "App Remote couldn’t connect (\($0)). Start a song and try again." } ??
                    "App Remote couldn’t connect. Start a song and try again."
            case .reconnecting: "App Remote disconnected. Reconnecting…"
            case .keychain: "Lyric Float couldn’t remove the saved Spotify connection."
            case .playbackUnavailable: "App Remote couldn’t read playback."
            case .playbackTimedOut: "App Remote stopped responding."
            }
        }
    }

    private let remote: SPTAppRemote?
    private let clientID: String?
    private var savedToken: String?
    var isConfigured: Bool { remote != nil }
    var hasSavedConnection: Bool { savedToken != nil }

    private var foreground = false
    private var retryConnectionAfter = Date.distantPast
    private var connection: (continuation: CheckedContinuation<Void, Error>, restoring: Bool)?
    private var connectionTimeout: Task<Void, Never>?
    private var playbackRequest: (id: UUID, continuation: CheckedContinuation<SpotifyPlayback?, Error>)?
    private var playbackTimeout: Task<Void, Never>?

    override init() {
        let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String
        let id = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if id.isEmpty || id.hasPrefix("$(") {
            clientID = nil
            remote = nil
        } else {
            clientID = id
            let configuration = SPTConfiguration(clientID: id, redirectURL: Self.redirectURL)
            remote = SPTAppRemote(configuration: configuration, logLevel: .none)
            savedToken = RemoteAuthorizationStore.read(clientID: id)
        }
        super.init()
        remote?.delegate = self
    }

    func connect(restoring: Bool = false) async throws {
        guard let remote else { throw Failure.notConfigured }
        guard connection == nil else { return }
        guard !remote.isConnected else { return }
        if restoring {
            guard let savedToken else { throw Failure.savedConnectionUnavailable }
            remote.connectionParameters.accessToken = savedToken
        } else {
            remote.connectionParameters.accessToken = nil
        }

        try await withCheckedThrowingContinuation { continuation in
            connection = (continuation, restoring)
            retryConnectionAfter = .distantPast
            connectionTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(restoring ? 8 : 60)) } catch { return }
                self?.completeConnection(.failure(restoring ? Failure.savedConnectionUnavailable : Failure.authorizationTimedOut))
            }
            if restoring {
                requestConnection()
            } else {
                remote.authorizeAndPlayURI("") { [weak self] opened in
                    if !opened { self?.completeConnection(.failure(Failure.openSpotify)) }
                }
            }
        }
    }

    func handleCallback(_ url: URL) {
        guard connection?.restoring == false, let remote,
              url.scheme?.lowercased() == Self.callbackScheme,
              url.host?.lowercased() == "callback",
              url.path.isEmpty || url.path == "/",
              url.user == nil, url.password == nil, url.port == nil,
              remote.connectionParameters.accessToken == nil else { return }

        let parameters = remote.authorizationParameters(from: url)
        guard let token = parameters?[SPTAppRemoteAccessTokenKey], !token.isEmpty else {
            let rawCode = parameters?[SPTAppRemoteErrorKey]
            let code = rawCode?.range(of: #"^[a-zA-Z0-9_]{1,48}$"#, options: .regularExpression) == nil
                ? nil : rawCode
            completeConnection(.failure(Failure.authorizationRejected(code)))
            return
        }
        remote.connectionParameters.accessToken = token
        if foreground { requestConnection() }
    }

    func setActivity(foreground: Bool, showingLyrics: Bool) {
        self.foreground = foreground
        if foreground {
            requestConnection()
        } else if !foreground, !showingLyrics, connection == nil {
            suspend()
        }
    }

    func disconnect() throws {
        if let clientID, !RemoteAuthorizationStore.remove(clientID: clientID) { throw Failure.keychain }
        savedToken = nil
        remote?.connectionParameters.accessToken = nil
        suspend()
    }

    func playback() async throws -> SpotifyPlayback? {
        guard let remote else { throw Failure.notConfigured }
        guard remote.isConnected, let player = remote.playerAPI else {
            requestConnection()
            throw Failure.reconnecting
        }
        guard playbackRequest == nil else { throw Failure.playbackUnavailable }

        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            playbackRequest = (id, continuation)
            playbackTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                self?.completePlayback(id: id, result: .failure(Failure.playbackTimedOut))
            }
            player.getPlayerState { [weak self] value, error in
                guard let self else { return }
                guard error == nil, let state = value as? SPTAppRemotePlayerState else {
                    self.completePlayback(id: id, result: .failure(Failure.playbackUnavailable))
                    return
                }

                let track = state.track
                guard !track.isEpisode, !track.isAdvertisement, track.duration > 0, !track.uri.isEmpty else {
                    self.completePlayback(id: id, result: .success(nil))
                    return
                }
                let song = SpotifyTrack(id: track.uri, title: track.name, artist: track.artist.name,
                                        album: track.album.name, duration: Double(track.duration) / 1_000)
                let playback = SpotifyPlayback(track: song, position: Double(state.playbackPosition) / 1_000,
                                               isPlaying: !state.isPaused)
                self.completePlayback(id: id, result: .success(playback))
            }
        }
    }

    private func requestConnection() {
        guard let remote, !remote.isConnected, remote.connectionParameters.accessToken != nil,
              Date() >= retryConnectionAfter else { return }
        retryConnectionAfter = Date().addingTimeInterval(8)
        remote.connect()
    }

    private func suspend() {
        retryConnectionAfter = .distantPast
        if let id = playbackRequest?.id {
            completePlayback(id: id, result: .failure(Failure.reconnecting))
        }
        remote?.disconnect()
    }

    private func completeConnection(_ result: Result<Void, Error>) {
        guard let pending = connection else { return }
        connection = nil
        connectionTimeout?.cancel()
        connectionTimeout = nil
        if case .failure = result {
            remote?.connectionParameters.accessToken = nil
            suspend()
        } else if !pending.restoring, let clientID, let token = remote?.connectionParameters.accessToken {
            if RemoteAuthorizationStore.save(token, clientID: clientID) { savedToken = token }
        }
        pending.continuation.resume(with: result)
    }

    private func completePlayback(id: UUID, result: Result<SpotifyPlayback?, Error>) {
        guard let request = playbackRequest, request.id == id else { return }
        playbackRequest = nil
        playbackTimeout?.cancel()
        playbackTimeout = nil
        request.continuation.resume(with: result)
    }

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        completeConnection(.success(()))
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let failure = connection?.restoring == true
            ? Failure.savedConnectionUnavailable
            : Failure.connectionFailed(error.map { ($0 as NSError).code })
        completeConnection(.failure(failure))
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        if let id = playbackRequest?.id {
            completePlayback(id: id, result: .failure(Failure.reconnecting))
        }
    }
}

private enum RemoteAuthorizationStore {
    private static func query(clientID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.lyricfloat.spotify.app-remote",
            kSecAttrAccount as String: clientID
        ]
    }

    static func read(clientID: String) -> String? {
        var attributes = query(clientID: clientID)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    static func save(_ token: String, clientID: String) -> Bool {
        let query = query(clientID: clientID)
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func remove(clientID: String) -> Bool {
        let status = SecItemDelete(query(clientID: clientID) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
