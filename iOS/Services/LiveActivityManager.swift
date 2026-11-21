import Foundation
import ActivityKit

/// Keeps one Lock Screen Live Activity running. iOS ends any Live Activity after 8 hours,
/// so PokéWalk starts a fresh one whenever you open the app and the current one is over 4 hours old.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<WalkActivityAttributes>?
    private var startedAt: Date?
    private var lastState: WalkActivityAttributes.ContentState?
    private var spriteCache: (key: String, data: Data?, icon: Data?)?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "liveActivityEnabled")
            if !newValue { end() }
        }
    }

    private func content(_ store: GameStore) async -> WalkActivityAttributes.ContentState? {
        guard let buddy = store.state.buddy else { return nil }
        let key = "\(buddy.speciesID)-\(buddy.isShiny)"
        if spriteCache?.key != key || spriteCache?.icon == nil {
            spriteCache = (key, await SpriteStore.shared.liveActivityImage(speciesID: buddy.speciesID, shiny: buddy.isShiny),
                           await SpriteStore.shared.liveActivityIcon(speciesID: buddy.speciesID, shiny: buddy.isShiny))
        }
        return .init(buddyName: buddy.name, speciesID: buddy.speciesID, level: buddy.level,
                     progress: buddy.levelProgress, expToNext: buddy.expToNext, stepsToday: store.stepsToday,
                     stepsToEncounter: store.state.counters.stepsToEncounter,
                     pendingEncounters: store.state.pending.count, kmToday: store.metersToday / 1000,
                     spritePNG: spriteCache?.data, iconPNG: spriteCache?.icon,
                     tintHex: buddy.species.primaryType.hex)
    }

    /// Activities can only be started while the app is in the foreground.
    func startIfNeeded(with store: GameStore) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            if activity == nil { activity = Activity<WalkActivityAttributes>.activities.first }
            let tooOld = (startedAt.map { Date().timeIntervalSince($0) > 4 * 3600 } ?? true)
            if let current = activity, current.activityState == .active, !tooOld {
                update(with: store)
                return
            }
            guard let state = await content(store) else { return }
            for old in Activity<WalkActivityAttributes>.activities { await old.end(nil, dismissalPolicy: .immediate) }
            activity = try? Activity.request(attributes: WalkActivityAttributes(trainerName: store.state.trainer.name),
                                             content: .init(state: state, staleDate: Date().addingTimeInterval(8 * 3600)))
            startedAt = .now
            lastState = state
        }
    }

    func update(with store: GameStore) {
        guard let activity, activity.activityState == .active else { return }
        Task {
            guard var state = await content(store) else { return }
            state.hop = lastState?.hop ?? false
            guard state != lastState else { return }
            lastState = state
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(8 * 3600)))
        }
    }

    private var lastHop = Date.distantPast

    /// Called on each step while you're walking: bobs the buddy's icon (at most every 1.5 s).
    func hop() {
        guard let activity, activity.activityState == .active, var state = lastState,
              Date().timeIntervalSince(lastHop) >= 1.5 else { return }
        lastHop = .now
        state.hop.toggle()
        lastState = state
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(8 * 3600))) }
    }

    func end() {
        Task { for a in Activity<WalkActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
        activity = nil
    }
}
