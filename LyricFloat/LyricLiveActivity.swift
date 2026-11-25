import ActivityKit
import Combine
import Foundation

@MainActor
final class LyricLiveActivity: ObservableObject {
    typealias State = LyricActivityAttributes.ContentState
    private typealias Session = Activity<LyricActivityAttributes>

    @Published private(set) var isActive = false
    @Published private(set) var message: String?

    private var activity: Session?
    private var stateTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var lastContent: ActivityContent<State>?
    private var pendingContent: ActivityContent<State>?

    init() {
        if let existing = Session.activities.first(where: { $0.activityState == .active || $0.activityState == .stale }) {
            attach(existing)
        }
    }

    func start(_ state: State, lastPlaybackSample: Date?) {
        guard activity == nil else { return }
        message = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Turn on Live Activities for Lyric Float in Settings."
            return
        }

        let content = content(for: state, lastPlaybackSample: lastPlaybackSample)
        do {
            let newActivity = try Session.request(attributes: LyricActivityAttributes(), content: content)
            attach(newActivity)
            lastContent = content
        } catch {
            message = "Couldn’t start Lock Screen lyrics. Try again while Lyric Float is open."
        }
    }

    func stop() {
        guard let activity else { return }
        detach()
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    func publish(_ state: State, lastPlaybackSample: Date?) {
        guard let activity else { return }
        let content = content(for: state, lastPlaybackSample: lastPlaybackSample)
        if let lastContent, lastContent.state == state,
           let previousExpiry = lastContent.staleDate, let expiry = content.staleDate,
           expiry.timeIntervalSince(previousExpiry) >= 0, expiry.timeIntervalSince(previousExpiry) < 8 {
            return
        }

        lastContent = content
        pendingContent = content
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            while !Task.isCancelled, let content = self?.pendingContent {
                self?.pendingContent = nil
                await activity.update(content)
            }
            if !Task.isCancelled { self?.updateTask = nil }
        }
    }

    private func content(for state: State, lastPlaybackSample: Date?) -> ActivityContent<State> {
        ActivityContent(state: state, staleDate: lastPlaybackSample?.addingTimeInterval(15) ?? .distantPast)
    }

    private func attach(_ activity: Session) {
        self.activity = activity
        isActive = true
        stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, self.activity?.id == activity.id else { return }
                if state == .ended || state == .dismissed {
                    self.detach()
                    return
                }
            }
        }
    }

    private func detach() {
        activity = nil
        isActive = false
        stateTask?.cancel()
        stateTask = nil
        updateTask?.cancel()
        updateTask = nil
        pendingContent = nil
        lastContent = nil
    }
}
