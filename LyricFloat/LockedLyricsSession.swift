import BackgroundTasks
import Combine
import Foundation

@MainActor
final class LockedLyricsSession: ObservableObject {
    private static let duration: TimeInterval = 15 * 60
    private static let playbackGracePeriod: TimeInterval = 30

    @Published private(set) var isActive = false
    @Published private(set) var message: String?

    private struct Run {
        let identifier: String
        let startedAt: TimeInterval
        var lastPlayingAt: TimeInterval
        var elapsedSeconds: Int64 = 0
    }

    private var run: Run?
    private var task: BGTask?

    @available(iOS 26.0, *)
    func start(at now: TimeInterval) {
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
            message = "iOS couldn’t register the background session."
            return
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Lyric Float", subtitle: "Syncing Lock Screen lyrics")
        request.strategy = .fail
        run = Run(identifier: identifier, startedAt: now, lastPlayingAt: now)
        do {
            try scheduler.submit(request)
            message = "Lock Screen sync is active for up to 15 minutes."
            isActive = true
        } catch {
            run = nil
            message = "iOS couldn’t start background sync (\((error as NSError).code))."
        }
    }

    func update(playing: Bool, at now: TimeInterval) {
        guard var run else { return }
        let elapsed = now - run.startedAt
        if elapsed >= Self.duration {
            finish(success: true, message: "The 15-minute Lock Screen sync session ended.")
            return
        }
        if playing {
            run.lastPlayingAt = now
        } else if now - run.lastPlayingAt >= Self.playbackGracePeriod {
            finish(success: false, message: "Lock Screen sync ended after a pause or Spotify connection loss.")
            return
        }

        let elapsedSeconds = Int64(elapsed.rounded(.down))
        let progressChanged = run.elapsedSeconds != elapsedSeconds
        run.elapsedSeconds = elapsedSeconds
        self.run = run
        if progressChanged, #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = elapsedSeconds
        }
    }

    func stop() {
        message = nil
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
                self.finish(success: false, message: "iOS ended background sync.")
            }
        }
        task.progress.totalUnitCount = Int64(Self.duration)
        task.progress.completedUnitCount = run.elapsedSeconds
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
