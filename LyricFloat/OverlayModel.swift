import AuthenticationServices
import Combine
import Foundation
import QuartzCore
import UIKit

@MainActor
final class OverlayModel: ObservableObject {
    let player = FloatingPlayer()
    private let catalog = LyricsCatalog()
    private let spotify = Spotify()

    @Published private var lyrics: Lyrics?
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var currentLine = "Connect Spotify to see lyrics"
    @Published private(set) var adjustment: TimeInterval = 0

    @Published private(set) var isSpotifyConnected = false
    @Published private(set) var isConnectingSpotify = false
    @Published private(set) var spotifyStatus: String?

    var canConnectSpotify: Bool { spotify.clientID != nil }
    var hasLyrics: Bool { lyrics != nil }

    private var foreground = false
    private var pictureInPictureObservation: AnyCancellable?
    private var spotifyPoll: Task<Void, Never>?
    private var lyricsLookup: Task<Void, Never>?
    private var spotifyTrack: SpotifyTrack?
    private var spotifyDisplayMessage = "Looking for Spotify playback…"
    private var nextLyricsAttempt: Date?
    private var spotifyRetryAfter = Date.distantPast
    private var theme = LyricTheme.defaultTheme

    private var timer: Timer?
    private var clockPosition: TimeInterval = 0
    private var startedAt: TimeInterval?
    private var displayedFrame: (current: String, next: String?)?
    private var lastRenderedAt: TimeInterval = 0

    init() {
        pictureInPictureObservation = player.$isActive.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.startPollingIfNeeded() }
        }
        isSpotifyConnected = spotify.isConnected
        spotifyStatus = spotify.startupError
        if isSpotifyConnected { prepareSpotifyTimeline() }
    }

    func setSceneActive(_ active: Bool) {
        foreground = active
        guard active else { return }
        update(forceFrame: true)
        startPollingIfNeeded()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.125, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applyTheme(_ theme: LyricTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        update(forceFrame: true)
    }

    func adjust(to time: TimeInterval) {
        adjustment = time
        update(forceFrame: true)
    }

    func connectSpotify() async {
        guard !isConnectingSpotify, !isSpotifyConnected, canConnectSpotify else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first(where: \.isKeyWindow)
        guard let window else {
            spotifyStatus = "Open Lyric Float to connect Spotify."
            return
        }

        isConnectingSpotify = true
        spotifyStatus = nil
        defer { isConnectingSpotify = false }
        do {
            try await spotify.connect(window: window)
            isSpotifyConnected = true
            prepareSpotifyTimeline()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            spotifyStatus = nil
        } catch {
            spotifyStatus = error.localizedDescription
        }
    }

    private func prepareSpotifyTimeline() {
        lyrics = nil
        title = nil
        artist = nil
        duration = 0
        adjustment = 0
        spotifyDisplayMessage = "Looking for Spotify playback…"
        spotifyStatus = nil
        setClock(position: 0, playing: false)
        startPollingIfNeeded()
    }

    func disconnectSpotify() {
        do {
            try spotify.disconnect()
            isSpotifyConnected = false
            spotifyPoll?.cancel()
            spotifyPoll = nil
            spotifyRetryAfter = .distantPast
            setSpotifyTrack(nil)
            setClock(position: 0, playing: false)
            spotifyStatus = nil
        } catch {
            spotifyStatus = error.localizedDescription
        }
    }

    private var shouldPoll: Bool {
        isSpotifyConnected && (foreground || player.isActive || player.isStarting)
    }

    private func startPollingIfNeeded() {
        guard shouldPoll, spotifyPoll == nil else { return }
        spotifyPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.pollSpotifyIfNeeded() else { break }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
            }
            if !Task.isCancelled { self?.spotifyPoll = nil }
        }
    }

    private func pollSpotifyIfNeeded() async -> TimeInterval? {
        guard shouldPoll else { return nil }
        let waitTime = spotifyRetryAfter.timeIntervalSinceNow
        if waitTime > 0 { return min(waitTime, 30) }

        do {
            let playback = try await spotify.playback()
            guard !Task.isCancelled, shouldPoll else { return nil }
            if let playback {
                if spotifyTrack?.id != playback.track.id {
                    setSpotifyTrack(playback.track)
                }
                loadTimedLyricsIfNeeded(for: playback.track)
                setClock(position: playback.position, playing: playback.isPlaying)
                spotifyStatus = nil
            } else {
                if spotifyTrack != nil { setSpotifyTrack(nil) }
                spotifyDisplayMessage = "Play a song in Spotify"
                setClock(position: 0, playing: false)
                spotifyStatus = nil
            }
            return 3
        } catch {
            guard !Task.isCancelled, shouldPoll else { return nil }
            setClock(position: currentPosition(), playing: false)
            spotifyStatus = error.localizedDescription
            if let failure = error as? Spotify.Failure {
                switch failure {
                case .reconnect:
                    disconnectSpotify()
                    if !isSpotifyConnected { spotifyStatus = failure.localizedDescription }
                    return isSpotifyConnected ? 15 : nil
                case .rateLimited(let delay):
                    spotifyRetryAfter = Date().addingTimeInterval(delay + Double.random(in: 0...1))
                    return min(delay, 30)
                case .forbidden:
                    return 30
                default:
                    break
                }
            }
            return 8
        }
    }

    private func setSpotifyTrack(_ track: SpotifyTrack?) {
        lyricsLookup?.cancel()
        lyricsLookup = nil
        spotifyTrack = track
        lyrics = nil
        title = track?.title
        artist = track?.artist
        duration = track?.duration ?? 0
        adjustment = 0
        nextLyricsAttempt = track == nil ? nil : .distantPast
        spotifyDisplayMessage = track == nil ? "Play a song in Spotify" : "Finding timed lyrics…"
    }

    private func loadTimedLyricsIfNeeded(for track: SpotifyTrack) {
        guard lyricsLookup == nil, let nextLyricsAttempt, nextLyricsAttempt <= Date() else { return }
        let catalog = self.catalog
        spotifyDisplayMessage = "Finding timed lyrics…"
        lyricsLookup = Task { [weak self] in
            do {
                let lyrics = try await catalog.match(title: track.title, artist: track.artist,
                                                     album: track.album, duration: track.duration)
                try Task.checkCancellation()
                guard let self, self.isSpotifyConnected, self.spotifyTrack?.id == track.id else { return }
                self.lyrics = lyrics
                self.spotifyDisplayMessage = lyrics == nil ? "No timed lyrics found" : ""
                self.nextLyricsAttempt = nil
                self.lyricsLookup = nil
                self.update(forceFrame: true)
            } catch {
                guard !Task.isCancelled, let self, self.isSpotifyConnected, self.spotifyTrack?.id == track.id else { return }
                self.spotifyDisplayMessage = "The lyrics service will retry shortly"
                self.nextLyricsAttempt = Date().addingTimeInterval(25)
                self.lyricsLookup = nil
                self.update(forceFrame: true)
            }
        }
    }

    private func currentPosition(at now: TimeInterval = CACurrentMediaTime()) -> TimeInterval {
        clockPosition + (startedAt.map { now - $0 } ?? 0)
    }

    private func setClock(position: TimeInterval, playing: Bool) {
        clockPosition = max(0, position)
        startedAt = playing ? CACurrentMediaTime() : nil
        update(forceFrame: true)
    }

    private func update(forceFrame: Bool = false) {
        let now = CACurrentMediaTime()
        let elapsed = currentPosition(at: now)
        if elapsed >= duration {
            clockPosition = duration
            startedAt = nil
        }
        let position = min(elapsed, duration)
        if self.position != position { self.position = position }
        player.setPaused(startedAt == nil)

        guard let lyrics else {
            let message = isSpotifyConnected ? spotifyDisplayMessage
                : (canConnectSpotify ? "Connect Spotify to see lyrics" : "Spotify is unavailable in this build")
            render(current: message, next: nil, at: now, forceFrame: forceFrame)
            return
        }

        let cueTime = elapsed + adjustment
        let index = lyrics.index(at: cueTime)
        let nextIndex = (index ?? -1) + 1
        let next = lyrics.cues.indices.contains(nextIndex) ? lyrics.cues[nextIndex].text : nil
        let line: String
        if elapsed >= duration || cueTime >= lyrics.duration {
            line = "End of lyrics"
        } else if let index {
            line = lyrics.cues[index].text.isEmpty ? "♪" : lyrics.cues[index].text
        } else {
            line = "♪"
        }

        render(current: line, next: next, at: now, forceFrame: forceFrame)
    }

    private func render(current: String, next: String?, at now: TimeInterval, forceFrame: Bool) {
        if currentLine != current { currentLine = current }
        let changed = displayedFrame?.current != current || displayedFrame?.next != next
        let refresh = now - lastRenderedAt >= 1 && (player.isActive || player.isStarting)
        if forceFrame || changed || refresh {
            player.render(current: current, next: next, theme: theme)
            displayedFrame = (current, next)
            lastRenderedAt = now
        }
    }
}
