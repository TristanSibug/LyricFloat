import BackgroundTasks
import Combine
import Foundation

@MainActor
final class LockedSongTest: ObservableObject {
    private static let cardTitle = "Lyric Float"

    @Published private(set) var isActive = false
    @Published private(set) var message: String?

    private struct SongRun {
        let identifier: String
        let track: SpotifyTrack
        var line: String
        var position: TimeInterval
    }

    private var run: SongRun?
    private var task: BGTask?

    @available(iOS 26.0, *)
    func start(track: SpotifyTrack, line: String, position: TimeInterval) {
        guard run == nil else { return }
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        guard let pattern = identifiers?.first(where: { $0.hasSuffix(".locked-song.*") }) else {
            message = "This build is missing the locked-lyrics task configuration."
            return
        }

        let identifier = String(pattern.dropLast()) + UUID().uuidString
        let scheduler = BGTaskScheduler.shared
        guard scheduler.register(forTaskWithIdentifier: identifier, using: .main, launchHandler: { [weak self] task in
            Task { @MainActor in
                guard let self, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.attach(task, identifier: identifier)
            }
        }) else {
            message = "iOS couldn’t register the locked-lyrics test."
            return
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: Self.cardTitle, subtitle: line)
        request.strategy = .fail
        run = SongRun(identifier: identifier, track: track, line: line, position: position)
        do {
            try scheduler.submit(request)
            message = "Lock your iPhone to see whether the lyrics follow this song."
            isActive = true
        } catch {
            run = nil
            message = "iOS couldn’t start the test (\((error as NSError).code))."
        }
    }

    func update(trackID: String?, position: TimeInterval, playing: Bool, line: String, lastPlaybackSample: Date?) {
        guard var run else { return }
        guard trackID == run.track.id else {
            finish(success: false, message: "Test ended when the song changed.")
            return
        }
        if position >= run.track.duration {
            finish(success: true, message: "Locked-lyrics test completed.")
            return
        }
        guard playing, let lastPlaybackSample, Date().timeIntervalSince(lastPlaybackSample) < 15 else {
            finish(success: false, message: "Test ended when playback paused or sync was interrupted.")
            return
        }

        let lineChanged = run.line != line
        run.line = line
        run.position = position
        self.run = run
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            let elapsed = Int64(max(0, position.rounded(.down)))
            if task.progress.completedUnitCount != elapsed {
                task.progress.completedUnitCount = elapsed
            }
            if lineChanged { task.updateTitle(Self.cardTitle, subtitle: line) }
        }
    }

    func stop() {
        finish(success: false, message: nil)
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask, identifier: String) {
        guard let run, run.identifier == identifier else {
            task.setTaskCompleted(success: false)
            return
        }
        self.task = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.run?.identifier == identifier else { return }
                self.finish(success: false, message: "iOS ended the locked-lyrics test.")
            }
        }
        task.progress.totalUnitCount = Int64(ceil(run.track.duration))
        task.progress.completedUnitCount = Int64(max(0, run.position.rounded(.down)))
        task.updateTitle(Self.cardTitle, subtitle: run.line)
    }

    private func finish(success: Bool, message: String?) {
        guard let run else { return }
        self.run = nil
        isActive = false
        self.message = message
        if let task {
            task.expirationHandler = nil
            if #available(iOS 26.0, *), success, let continued = task as? BGContinuedProcessingTask {
                continued.progress.completedUnitCount = continued.progress.totalUnitCount
            }
            task.setTaskCompleted(success: success)
            self.task = nil
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: run.identifier)
        }
    }
}
