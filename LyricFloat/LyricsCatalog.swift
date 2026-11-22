import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor LyricsCatalog {
    private struct Record: Decodable {
        let trackName: String
        let duration: TimeInterval
        let instrumental: Bool
        let syncedLyrics: String?
    }

    private let session: URLSession
    private var retryAfter = Date.distantPast

    init(session: URLSession = .shared) {
        self.session = session
    }

    func match(title: String, artist: String, album: String?, duration: TimeInterval) async throws -> Lyrics? {
        guard (1...3600).contains(duration) else { return nil }
        var parameters = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(duration))
        ]
        if let album, !album.isEmpty {
            parameters.append(URLQueryItem(name: "album_name", value: album))
        }
        guard let data = try await requestLyrics(parameters: parameters) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard abs(record.duration - duration) <= 2, !record.instrumental,
              let lrc = record.syncedLyrics, lrc.utf8.count <= 1_000_000 else { return nil }
        return try? Lyrics.parse(lrc, fallbackTitle: record.trackName)
    }

    private func requestLyrics(parameters: [URLQueryItem]) async throws -> Data? {
        guard retryAfter <= Date() else { throw Failure.rateLimited }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = parameters
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = URLRequest(url: url.url!, timeoutInterval: 10)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3"
        request.setValue("LyricFloat/\(version) (https://github.com/TristanSibug/lyric-float)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }

        if response.statusCode == 429 || response.statusCode == 503 {
            let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let delay = seconds.flatMap { $0.isFinite ? max(1, $0) : nil } ?? 30
            retryAfter = max(retryAfter, Date().addingTimeInterval(delay))
            throw Failure.rateLimited
        }
        try Task.checkCancellation()
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw Failure.unavailable }
        return data
    }

    private enum Failure: LocalizedError {
        case rateLimited
        case unavailable

        var errorDescription: String? {
            switch self {
            case .rateLimited: "The lyrics service is busy. Try again in a moment."
            case .unavailable: "The lyrics service couldn’t look up this song."
            }
        }
    }
}
