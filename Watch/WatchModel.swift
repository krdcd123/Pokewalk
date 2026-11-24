import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit
import HealthKit

/// Watch-side state: the latest party snapshot from the phone plus live steps from the watch's own HealthKit.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    static let shared = WatchModel()

    @Published var snapshot: WatchSnapshot = SharedStore.loadSnapshot() ?? .empty
    @Published var stepsSinceSync = 0
    @Published var stepsToday = 0
    @Published var syncStatus: String?
    @Published var spriteVersion = 0
    @Published var path: [WatchRoute] = []      // navigation (notifications can jump straight to a screen)

    private var recommendationsRefreshed = false
    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var contentPendingObservation: NSKeyValueObservation?

    var hasData: Bool { !snapshot.party.isEmpty }

    func live(_ member: WatchSnapshot.Member) -> LiveMember {
        LiveMember(member, in: snapshot, stepsSinceSync: stepsSinceSync)
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
        startStepObserver()
    }

    // MARK: Keeping up with the phone

    private var liveTimer: Timer?
    private var observerStarted = false
    private var lastComplicationReload = Date.distantPast

    /// While the watch app is on screen: re-read steps every few seconds and get a fresh snapshot from the phone.
    func becameActive() {
        Task { await refreshSteps() }
        quietSync()
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in await WatchModel.shared.refreshSteps(reloadComplications: false) }
        }
    }

    func resignedActive() {
        liveTimer?.invalidate(); liveTimer = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Asks the phone for the latest snapshot without showing a status message.
    func quietSync() {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "sync"], replyHandler: { reply in
            Task { @MainActor in self.ingest(reply["snapshot"] as? Data) }
        }, errorHandler: nil)
    }

    /// New steps on the watch (even in the background) → update the numbers and the complications.
    private func startStepObserver() {
        guard !observerStarted, StepCounter.shared.isAvailable else { return }
        observerStarted = true
        let hk = StepCounter.shared
        let q = HKObserverQuery(sampleType: hk.stepType, predicate: nil) { _, completion, _ in
            Task { @MainActor in
                await WatchModel.shared.refreshSteps()
                completion()
            }
        }
        hk.store.execute(q)
        hk.store.enableBackgroundDelivery(for: hk.stepType, frequency: .immediate) { _, _ in }
    }

    /// Query HealthKit on the watch and cache the result for the complications.
    func refreshSteps(reloadComplications: Bool = true) async {
        let sync = snapshot.syncDate
        if let s = try? await StepCounter.shared.steps(from: sync) {
            stepsSinceSync = s
            SharedStore.saveLiveSteps(s, forSync: sync)
        }
        if let t = try? await StepCounter.shared.stepsToday() {
            stepsToday = t
            sendStepsToPhone(t)
        }
        // watchOS limits complication reloads, so don't spend them more than once a minute
        if reloadComplications, Date().timeIntervalSince(lastComplicationReload) > 60 {
            lastComplicationReload = .now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var lastStepsSent = 0
    private var lastStepsSentAt = Date.distantPast

    /// Tells the phone today's watch steps directly. The phone can't read Apple Health while it's
    /// locked, so this keeps encounters and notifications coming while it's in your pocket.
    private func sendStepsToPhone(_ steps: Int) {
        let s = WCSession.default
        guard s.activationState == .activated, steps > lastStepsSent,
              Date().timeIntervalSince(lastStepsSentAt) > 30 || steps - lastStepsSent >= 100 else { return }
        lastStepsSent = steps
        lastStepsSentAt = .now
        let c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let msg: [String: Any] = ["watchSteps": steps,
                                  "day": String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)]
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) }
        } else {
            s.transferUserInfo(msg)       // queued; delivered as soon as the phone can take it
        }
    }

    // MARK: Snapshot intake

    private func ingest(_ data: Data?) {
        guard let data, let snap = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        let partyChanged = snap.party.map(\.id) != snapshot.party.map(\.id)
            || snap.party.map(\.speciesID) != snapshot.party.map(\.speciesID)
        let buddyChanged = snap.buddy?.id != snapshot.buddy?.id
        snapshot = snap
        SharedStore.saveSnapshot(snap)
        if partyChanged || !recommendationsRefreshed {
            recommendationsRefreshed = true
            WidgetCenter.shared.invalidateConfigurationRecommendations()
            WidgetCenter.shared.reloadAllTimelines()
        } else if buddyChanged {
            // Walking Buddy / Party (not buddy) complications swap who they show straight away
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task {
            await refreshSteps()
            completeConnectivityTasksIfDone()
            await fetchSprites(for: snap)
        }
    }

    /// Fallback downloads (the phone also sends icons): box icons, shiny ones too, and item icons.
    private func fetchSprites(for snap: WatchSnapshot) async {
        var got = false
        let mons = snap.party.map { ($0.speciesID, $0.isShiny) } + snap.wild.map { ($0.speciesID, $0.isShiny) }
        for (id, shiny) in mons where !SharedStore.hasIcon(id, shiny: shiny) {
            if await SharedStore.fetchIcon(id, shiny: shiny) != nil { got = true }
        }
        for line in snap.bag where !FileManager.default.fileExists(atPath: SharedStore.itemFile(line.key).path) {
            if await SharedStore.fetch(SharedStore.remoteItemURL(line.key), to: SharedStore.itemFile(line.key)) != nil { got = true }
        }
        if got {
            spriteVersion += 1
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Actions on the phone (it wakes up in the background to answer)

    private func ask(_ message: [String: Any]) async -> [String: Any]? {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return nil }
        return await withCheckedContinuation { cont in
            WCSession.default.sendMessage(message, replyHandler: { reply in cont.resume(returning: reply) },
                                          errorHandler: { _ in cont.resume(returning: nil) })
        }
    }

    /// Makes a party Pokémon your walking buddy (on the phone too). Returns a message to show.
    func makeBuddy(_ member: WatchSnapshot.Member) async -> String {
        guard let reply = await ask(["request": "buddy", "id": member.id]) else { return "Couldn't reach your iPhone." }
        ingest(reply["snapshot"] as? Data)
        WidgetCenter.shared.reloadAllTimelines()
        WKInterfaceDevice.current().play(.success)
        return reply["message"] as? String ?? ""
    }

    /// Opens a Pokémon's summary (from tapping its complication).
    func open(_ url: URL) {
        guard url.scheme == "pokewalk", url.host == "summary", let id = url.pathComponents.dropFirst().first else { return }
        path = [.party, .summary(id)]
    }

    /// Moves a party Pokémon's held items into the Bag. Returns a message to show.
    func takeItem(from member: WatchSnapshot.Member) async -> String {
        guard let reply = await ask(["request": "take", "id": member.id]) else { return "Couldn't reach your iPhone." }
        ingest(reply["snapshot"] as? Data)
        WKInterfaceDevice.current().play(.success)
        return reply["message"] as? String ?? ""
    }

    struct BattleReply {
        var message: String
        var shakes = 0
        var caught = false
        var ended = false
        var unreachable = false
    }

    /// One battle action ("start", "ball", "berry", "run") against a wild Pokémon.
    func battle(_ wildID: String, action: String, ball: BallKind? = nil) async -> BattleReply {
        var msg: [String: Any] = ["request": "battle", "wild": wildID, "action": action]
        if let ball { msg["ball"] = ball.rawValue }
        guard let r = await ask(msg) else {
            return BattleReply(message: "Couldn't reach your iPhone. Keep it nearby.", ended: false, unreachable: true)
        }
        ingest(r["snapshot"] as? Data)
        return BattleReply(message: r["message"] as? String ?? "", shakes: r["shakes"] as? Int ?? 0,
                           caught: r["caught"] as? Bool ?? false, ended: r["ended"] as? Bool ?? false)
    }

    func ballCount(_ kind: BallKind) -> Int { snapshot.bag.first { $0.key == kind.itemKey }?.count ?? 0 }
    var berryCount: Int { snapshot.bag.filter { $0.pocket == "Berries" }.reduce(0) { $0 + $1.count } }

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

    /// Snapshots received but not yet saved + complications not yet reloaded.
    private var ingestsInFlight = 0

    private func completeConnectivityTasksIfDone() {
        guard WCSession.default.activationState == .activated, !WCSession.default.hasContentPending,
              ingestsInFlight == 0, !pendingConnectivityTasks.isEmpty else { return }
        let tasks = pendingConnectivityTasks
        pendingConnectivityTasks.removeAll()
        // Give WidgetKit a moment to pick up the reload before watchOS suspends us again
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        }
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
        Task { @MainActor in self.ingestFromPhone(data) }
    }

    /// Saves a snapshot from the phone and reloads the complications *before* letting watchOS
    /// put the app back to sleep (otherwise a buddy change could wait until you opened the app).
    func ingestFromPhone(_ data: Data?) {
        ingestsInFlight += 1
        ingest(data)
        WidgetCenter.shared.reloadAllTimelines()
        ingestsInFlight -= 1
        completeConnectivityTasksIfDone()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["snapshot"] as? Data
        Task { @MainActor in self.ingest(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let data = userInfo["snapshot"] as? Data
        Task { @MainActor in self.ingestFromPhone(data) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let id = file.metadata?["iconID"] as? Int else { return }
        let dest = SharedStore.iconFile(id, shiny: file.metadata?["shiny"] as? Bool ?? false)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: file.fileURL, to: dest) // must copy before returning
        Task { @MainActor in
            WidgetCenter.shared.reloadAllTimelines()
            self.spriteVersion += 1
        }
    }
}
