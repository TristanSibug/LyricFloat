import Foundation
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
        case connectionFailed(Int?)
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
            case .connectionFailed(let code):
                code.map { "App Remote couldn’t connect (\($0)). Start a song and try again." } ??
                    "App Remote couldn’t connect. Start a song and try again."
            case .reconnecting: "App Remote disconnected. Reconnecting…"
            case .playbackUnavailable: "App Remote couldn’t read playback."
            case .playbackTimedOut: "App Remote stopped responding."
            }
        }
    }

    private let remote: SPTAppRemote?
    var isConfigured: Bool { remote != nil }

    private var foreground = false
    private var retryConnectionAfter = Date.distantPast
    private var connection: CheckedContinuation<Void, Error>?
    private var connectionTimeout: Task<Void, Never>?
    private var playbackRequest: (id: UUID, continuation: CheckedContinuation<SpotifyPlayback?, Error>)?
    private var playbackTimeout: Task<Void, Never>?

    override init() {
        let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String
        let id = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if id.isEmpty || id.hasPrefix("$(") {
            remote = nil
        } else {
            let configuration = SPTConfiguration(clientID: id, redirectURL: Self.redirectURL)
            remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        }
        super.init()
        remote?.delegate = self
    }

    func connect() async throws {
        guard let remote else { throw Failure.notConfigured }
        guard connection == nil else { return }

        try await withCheckedThrowingContinuation { continuation in
            connection = continuation
            connectionTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.completeConnection(.failure(Failure.authorizationTimedOut))
            }
            remote.authorizeAndPlayURI("") { [weak self] opened in
                if !opened { self?.completeConnection(.failure(Failure.openSpotify)) }
            }
        }
    }

    func handleCallback(_ url: URL) {
        guard connection != nil, let remote,
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
        if foreground, connection != nil {
            requestConnection()
        } else if !foreground, !showingLyrics, connection == nil {
            suspend()
        }
    }

    func disconnect() {
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
        guard let continuation = connection else { return }
        connection = nil
        connectionTimeout?.cancel()
        connectionTimeout = nil
        if case .failure = result { disconnect() }
        continuation.resume(with: result)
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
        completeConnection(.failure(Failure.connectionFailed(error.map { ($0 as NSError).code })))
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        if let id = playbackRequest?.id {
            completePlayback(id: id, result: .failure(Failure.reconnecting))
        }
    }
}
