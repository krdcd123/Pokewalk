import Foundation
import ActivityKit

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<WalkActivityAttributes>?
    private var lastState: WalkActivityAttributes.ContentState?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "liveActivityEnabled")
            if !newValue { end() }
        }
    }

    private func content(_ store: GameStore) -> WalkActivityAttributes.ContentState? {
        guard let buddy = store.state.buddy else { return nil }
        return .init(buddyName: buddy.name, speciesID: buddy.speciesID, level: buddy.level,
                     progress: buddy.levelProgress, stepsToday: store.stepsToday,
                     stepsToEncounter: store.state.counters.stepsToEncounter, balls: store.state.totalBalls,
                     pendingEncounters: store.state.pending.count, kmToday: store.metersToday / 1000,
                     latestWildName: store.state.pending.last?.species.name)
    }

    /// Activities can only be started while the app is in the foreground.
    func startIfNeeded(with store: GameStore) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let state = content(store) else { return }
        activity = activity ?? Activity<WalkActivityAttributes>.activities.first
        if let activity, activity.activityState == .active { update(with: store); return }
        Task { await SpriteStore.shared.ensureSharedIcon(state.speciesID) }
        activity = try? Activity.request(attributes: WalkActivityAttributes(trainerName: store.state.trainer.name),
                                         content: .init(state: state, staleDate: nil))
        lastState = state
    }

    func update(with store: GameStore) {
        guard let activity, activity.activityState == .active, let state = content(store), state != lastState else { return }
        lastState = state
        Task {
            await SpriteStore.shared.ensureSharedIcon(state.speciesID)
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(3 * 3600)))
        }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
