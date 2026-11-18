import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit

/// Watch-side state: the latest party snapshot from the phone plus live steps from the watch's own HealthKit.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    static let shared = WatchModel()

    @Published var snapshot: WatchSnapshot = SharedStore.loadSnapshot() ?? .empty
    @Published var stepsSinceSync = 0
    @Published var stepsToday = 0
    @Published var syncStatus: String?
    @Published var spriteVersion = 0

    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var contentPendingObservation: NSKeyValueObservation?

    var hasData: Bool { !snapshot.party.isEmpty }

    func live(_ member: WatchSnapshot.Member) -> LiveMember {
        LiveMember(member, stepsSinceSync: stepsSinceSync, multiplier: snapshot.expMultiplier)
    }

    var liveStepsToEncounter: Int { max(0, snapshot.stepsToEncounter - stepsSinceSync) }
    var liveBalls: Int {
        let earned = stepsSinceSync >= snapshot.stepsToBall ? 1 + (stepsSinceSync - snapshot.stepsToBall) / max(1, snapshot.ballSteps) : 0
        return snapshot.balls + earned
    }

    // MARK: Lifecycle

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestHealth() async {
        try? await StepCounter.shared.requestAuthorization()
        await refreshSteps()
    }

    /// Query HealthKit on the watch and cache the result for the complications.
    func refreshSteps(reloadComplications: Bool = true) async {
        let sync = snapshot.syncDate
        if let s = try? await StepCounter.shared.steps(from: sync) {
            stepsSinceSync = s
            SharedStore.saveLiveSteps(s, forSync: sync)
        }
        if let t = try? await StepCounter.shared.stepsToday() { stepsToday = t }
        if reloadComplications { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Snapshot intake

    private func ingest(_ data: Data?) {
        guard let data, let snap = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        let partyChanged = snap.party.map(\.id) != snapshot.party.map(\.id)
            || snap.party.map(\.speciesID) != snapshot.party.map(\.speciesID)
        snapshot = snap
        SharedStore.saveSnapshot(snap)
        if partyChanged { WidgetCenter.shared.invalidateConfigurationRecommendations() }
        Task {
            for id in Set(snap.party.map(\.speciesID)) where !SharedStore.hasIcon(id) {
                await SharedStore.fetchIcon(id)       // fallback if the phone's transfer hasn't arrived
                spriteVersion += 1
            }
            await refreshSteps()
            completeConnectivityTasksIfDone()
        }
    }

    /// "Sync" button on the watch: asks the iPhone app (woken in background) to sync now.
    func requestPhoneSync() {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            syncStatus = "iPhone not reachable — open PokéWalk on your phone to sync."
            return
        }
        syncStatus = "Syncing…"
        WCSession.default.sendMessage(["request": "sync"], replyHandler: { reply in
            Task { @MainActor in
                self.ingest(reply["snapshot"] as? Data)
                self.syncStatus = "Synced!"
            }
        }, errorHandler: { error in
            Task { @MainActor in self.syncStatus = "Sync failed: \(error.localizedDescription)" }
        })
    }

    // MARK: Background tasks

    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        pendingConnectivityTasks.append(task)
        activate()
        if contentPendingObservation == nil {
            contentPendingObservation = WCSession.default.observe(\.hasContentPending) { _, _ in
                Task { @MainActor in WatchModel.shared.completeConnectivityTasksIfDone() }
            }
        }
        completeConnectivityTasksIfDone()
    }

    private func completeConnectivityTasksIfDone() {
        guard WCSession.default.activationState == .activated, !WCSession.default.hasContentPending else { return }
        pendingConnectivityTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        pendingConnectivityTasks.removeAll()
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext["snapshot"] as? Data
        Task { @MainActor in
            self.ingest(context)
            self.completeConnectivityTasksIfDone()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        Task { @MainActor in self.ingest(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let data = userInfo["snapshot"] as? Data
        Task { @MainActor in self.ingest(data) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let id = file.metadata?["iconID"] as? Int else { return }
        let dest = SharedStore.iconFile(id)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: file.fileURL, to: dest) // must copy before returning
        Task { @MainActor in
            WidgetCenter.shared.reloadAllTimelines()
            self.spriteVersion += 1
        }
    }
}
