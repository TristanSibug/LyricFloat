import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor LyricsCatalog {
    struct Song: Identifiable, Sendable {
        let id: Int
        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval
        let lyrics: Lyrics
    }

    private struct Record: Decodable {
        let id: Int
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: TimeInterval
        let instrumental: Bool
        let syncedLyrics: String?
    }

    private let session: URLSession
    private var retryAfter = Date.distantPast

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(title: String, artist: String) async throws -> [Song] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }
        var parameters = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            parameters.append(URLQueryItem(name: "artist_name", value: artist))
        }
        guard let data = try await request(path: "/api/search", parameters: parameters) else { return [] }
        return try JSONDecoder().decode([Record].self, from: data).compactMap(Self.song)
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
        guard let data = try await request(path: "/api/get", parameters: parameters) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard abs(record.duration - duration) <= 2 else { return nil }
        return Self.song(record)?.lyrics
    }

    private func request(path: String, parameters: [URLQueryItem]) async throws -> Data? {
        guard retryAfter <= Date() else { throw Failure.rateLimited }
        var url = URLComponents(string: "https://lrclib.net")!
        url.path = path
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

    private static func song(_ record: Record) -> Song? {
        guard !record.instrumental, record.duration > 0, Int(exactly: record.duration.rounded(.down)) != nil,
              let lrc = record.syncedLyrics, lrc.utf8.count <= 1_000_000,
              let lyrics = try? Lyrics.parse(lrc, fallbackTitle: record.trackName)
        else { return nil }

        return Song(id: record.id, title: record.trackName, artist: record.artistName,
                    album: record.albumName, duration: record.duration, lyrics: lyrics)
    }

    private enum Failure: LocalizedError {
        case rateLimited
        case unavailable

        var errorDescription: String? {
            switch self {
            case .rateLimited: "The lyrics service is busy. Try again in a moment."
            case .unavailable: "The lyrics service couldn’t complete the search."
            }
        }
    }
}
