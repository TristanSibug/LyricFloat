import Foundation

enum SpotifyAuthorizationResponse {
    static let callbackScheme = "app.lyricfloat.oauth"
    static let redirectURI = "app.lyricfloat.oauth://callback"

    enum Failure: LocalizedError, Equatable {
        case unexpectedAddress
        case missingState
        case mismatchedState
        case declined
        case appConfiguration
        case playbackPermission
        case spotifyUnavailable
        case authorizationFailed
        case missingCode

        var errorDescription: String? {
            switch self {
            case .unexpectedAddress: "Spotify returned to an unexpected address. Try Connect Spotify again."
            case .missingState: "Spotify returned without sign-in verification. Try Connect Spotify again."
            case .mismatchedState: "The Spotify reply didn’t match this sign-in attempt. Try Connect Spotify again."
            case .declined: "Spotify access wasn’t granted. Tap Connect Spotify and choose Agree."
            case .appConfiguration: "Spotify rejected Lyric Float’s app settings. Check its redirect URI and Web API access."
            case .playbackPermission: "Spotify rejected the requested playback permission."
            case .spotifyUnavailable: "Spotify sign-in is temporarily unavailable. Try again shortly."
            case .authorizationFailed: "Spotify couldn’t complete authorization. Try Connect Spotify again."
            case .missingCode: "Spotify returned without an authorization code. Try Connect Spotify again."
            }
        }
    }

    static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        // Keep the registered URI exact for Spotify. The browser can normalize the empty path to "/".
        guard let callback = URLComponents(url: url, resolvingAgainstBaseURL: false),
              callback.scheme?.lowercased() == callbackScheme,
              callback.host?.lowercased() == "callback",
              callback.percentEncodedPath.isEmpty || callback.percentEncodedPath == "/",
              callback.port == nil, callback.user == nil, callback.password == nil
        else { throw Failure.unexpectedAddress }

        let items = callback.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard !states.isEmpty else { throw Failure.missingState }
        guard states.count == 1, states[0].value == expectedState else { throw Failure.mismatchedState }

        let errors = items.filter { $0.name == "error" }
        let codes = items.filter { $0.name == "code" }
        if !errors.isEmpty {
            guard errors.count == 1, codes.isEmpty else { throw Failure.authorizationFailed }
            switch errors[0].value {
            case "access_denied": throw Failure.declined
            case "invalid_client", "unauthorized_client", "invalid_redirect_uri": throw Failure.appConfiguration
            case "invalid_scope": throw Failure.playbackPermission
            case "temporarily_unavailable", "server_error": throw Failure.spotifyUnavailable
            default: throw Failure.authorizationFailed
            }
        }

        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else { throw Failure.missingCode }
        return code
    }
}
