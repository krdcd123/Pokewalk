import Foundation
import WatchConnectivity
import UIKit

/// Sends the party snapshot (and sprite PNGs) to the Watch, and answers sync requests from it.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var pending: WatchSnapshot?
    private let sentSpritesKey = "sentIconsToWatch"
    private var lastPushedParty = ""

    /// Priority watch updates left today (Apple allows about 50), for Settings.
    var priorityUpdatesLeft: Int? {
        guard let session, session.activationState == .activated, session.isPaired else { return nil }
        return session.isComplicationEnabled ? session.remainingComplicationUserInfoTransfers : nil
    }

    // Watch status for the Settings screen
    var isWatchPaired: Bool { session?.isPaired ?? false }
    var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }
    var isComplicationOnFace: Bool { session?.isComplicationEnabled ?? false }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    private var lastSentData: Data?

    func send(_ snapshot: WatchSnapshot) {
        guard let session else { return }
        guard session.activationState == .activated else { pending = snapshot; return }
        guard session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        // nothing changed since the last one: don't wake the watch for it
        if data == lastSentData { return }
        lastSentData = data
        let payload: [String: Any] = ["snapshot": data]
        try? session.updateApplicationContext(payload)

        // Watch app open (or reachable): send it straight away instead of waiting for iOS to deliver the context.
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        // Priority pushes (silent, ~50 a day) are only for changes to what your complications show:
        // who's in the party and in what order, evolutions, names and the walking buddy.
        // Level-ups, items, encounters etc. come through as normal notifications instead — and the watch
        // works out levels itself from its own steps, so the complications keep counting up anyway.
        let party = snapshot.party.map { "\($0.id):\($0.speciesID):\($0.name):\($0.isBuddy)" }.joined(separator: ",")
        if party != lastPushedParty {
            if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
                session.transferCurrentComplicationUserInfo(payload)
            } else {
                session.transferUserInfo(payload)
            }
            lastPushedParty = party
        }

        sendIcons(for: snapshot.party.map { ($0.speciesID, $0.isShiny) } + snapshot.wild.map { ($0.speciesID, $0.isShiny) })
    }

    /// The Watch shows each party member's box icon (yours from Sprites/icons, else PokeSprite's), shiny ones too.
    private func sendIcons(for species: [(Int, Bool)]) {
        guard let session else { return }
        var sent = Set(UserDefaults.standard.array(forKey: sentSpritesKey) as? [String] ?? [])
        for (id, shiny) in species {
            let key = shiny ? "\(id)s" : "\(id)"
            guard !sent.contains(key) else { continue }
            sent.insert(key)
            Task {
                guard let file = await SpriteStore.shared.ensureSharedIcon(id, shiny: shiny) else { return }
                session.transferFile(file, metadata: ["iconID": id, "shiny": shiny])
            }
        }
        UserDefaults.standard.set(Array(sent), forKey: sentSpritesKey)
    }

    /// Call if the watch app gets reinstalled (or you import new icons) so icons are re-sent.
    func resetSentSprites() { UserDefaults.standard.removeObject(forKey: sentSpritesKey) }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            if let snap = self.pending { self.pending = nil; self.send(snap) }
            else { self.send(GameStore.shared.snapshot) }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if !session.isWatchAppInstalled { resetSentSprites() }
    }

    /// The watch asked for a sync ("Sync" button on the watch).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["request"] as? String {
        case "buddy":
            Task { @MainActor in
                let name = await Self.applyBuddy(message)
                replyHandler(["snapshot": (try? JSONEncoder().encode(GameStore.shared.snapshot)) ?? Data(),
                              "message": name.isEmpty ? "Couldn't change your buddy." : "\(name) is your walking buddy!"])
            }
            return
        case "take":
            Task { @MainActor in
                let taken = UUID(uuidString: message["id"] as? String ?? "").map { GameStore.shared.takeHeldItems($0) } ?? []
                let names = taken.map { Dex.itemName($0) }.joined(separator: ", ")
                replyHandler(["snapshot": (try? JSONEncoder().encode(GameStore.shared.snapshot)) ?? Data(),
                              "message": taken.isEmpty ? "Nothing to take." : "Put \(names) in the Bag."])
            }
            return
        case "battle":
            Task { @MainActor in replyHandler(WatchBattles.handle(message)) }
            return
        case "ranchShift", "collectEgg":
            Task { @MainActor in
                let store = GameStore.shared
                var text = ""
                if message["request"] as? String == "collectEgg" {
                    text = store.collectEgg() ? "Egg picked up! Walk to hatch it." : "No room — you're carrying 6 Eggs."
                } else if store.ranchShiftDone, let h = store.collectRanchShift() {
                    text = "Haul: " + RanchMaterial.allCases.compactMap { m in h.materials[m].flatMap { $0 > 0 ? "\($0) \(m.name)" : nil } }.joined(separator: ", ")
                    if h.money > 0 { text += ", ₽\(h.money)" }
                } else if !store.ranchShiftRunning, let b = store.ranchBuilding {
                    text = "Everyone's building the \(b.name) — no shifts until it's done."
                } else if !store.ranchShiftRunning, !store.ranchWorkers.isEmpty {
                    store.startRanchShift()
                    text = "Shift started!"
                } else {
                    text = store.ranchWorkers.isEmpty ? "Add ranchers on your iPhone first." : "Still on shift."
                }
                replyHandler(["snapshot": (try? JSONEncoder().encode(store.snapshot)) ?? Data(), "message": text])
            }
            return
        case "gardenPlant", "gardenPick":
            Task { @MainActor in
                let store = GameStore.shared
                let plot = message["plot"] as? Int ?? -1
                var text = ""
                if message["request"] as? String == "gardenPlant", let berry = message["berry"] as? String {
                    text = store.plant(berry, in: plot) ? "\(Dex.itemName(berry)) planted!" : "Couldn't plant that."
                } else if let r = store.harvest(plot) {
                    text = "Picked \(r.count) \(Dex.itemName(r.berry))\(r.count == 1 ? "" : "s")!"
                    if let bonus = r.bonus { text += " +1 \(Dex.itemName(bonus))" }
                    if r.replanted { text += " (replanted)" }
                } else {
                    text = "Not ready yet."
                }
                replyHandler(["snapshot": (try? JSONEncoder().encode(store.snapshot)) ?? Data(), "message": text])
            }
            return
        case "sync": break
        default: replyHandler([:]); return
        }
        Task { @MainActor in
            await GameStore.shared.tick()
            let data = (try? JSONEncoder().encode(GameStore.shared.snapshot)) ?? Data()
            replyHandler(["snapshot": data])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if Self.takeWatchSleep(message) { return }
        if Self.takeWorkoutLive(message) { return }
        if Self.takeWatchSteps(message) { return }
        if message["request"] as? String == "resendSprites" {
            resetSentSprites()
            Task { @MainActor in self.send(GameStore.shared.snapshot) }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["request"] as? String == "buddy" {
            Task { @MainActor in _ = await Self.applyBuddy(userInfo) }
            return
        }
        if Self.takeWatchSleep(userInfo) { return }
        if Self.takeWorkoutLive(userInfo) { return }
        _ = Self.takeWatchSteps(userInfo)
    }

    /// A buddy change from the watch. iOS only wakes the app for a few seconds, so ask for extra time
    /// until the Live Activity / Dynamic Island shows the new buddy.
    @MainActor static func applyBuddy(_ m: [String: Any]) async -> String {
        guard let id = UUID(uuidString: m["id"] as? String ?? ""), let mon = GameStore.shared.state.mon(id) else { return "" }
        let task = UIApplication.shared.beginBackgroundTask(withName: "buddy")
        await GameStore.shared.setBuddy(id)
        await LiveActivityManager.shared.updateNow(with: GameStore.shared)
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        return mon.name
    }

    /// Sleep sent straight from the watch: saved, then the morning popup / Journal update right away.
    static func takeWatchSleep(_ m: [String: Any]) -> Bool {
        guard let data = m["watchSleep"] as? Data else { return false }
        if let list = try? JSONDecoder().decode([WatchSleepSample].self, from: data) {
            Task { @MainActor in
                WatchSleepStore.save(list)
                await GameStore.shared.sleepArrived()
            }
        }
        return true
    }

    /// Live workout numbers from the watch (a workout started on the watch shows on the map straight away).
    static func takeWorkoutLive(_ m: [String: Any]) -> Bool {
        guard let data = m["workoutLive"] as? Data else { return false }
        if let u = try? JSONDecoder().decode(WorkoutLive.self, from: data) {
            Task { @MainActor in PhoneWorkout.shared.takeWatchLive(u) }
        }
        return true
    }

    /// The watch's own step count for today. Apple Health can't be read while the iPhone is locked,
    /// so without this, steps from your watch (and the encounters/notifications they cause) would
    /// wait until you unlocked the phone.
    static func takeWatchSteps(_ m: [String: Any]) -> Bool {
        guard let steps = m["watchSteps"] as? Int, let day = m["day"] as? String else { return false }
        if m["cycling"] as? Bool == true { Task { @MainActor in CyclingDetector.watchSawCyclingAt = .now } }
        StepEngine.reportWatchSteps(steps, day: day)
        Task { @MainActor in GameStore.shared.requestTick(minInterval: 0) }
        return true
    }
}


/// Wild battles played from the watch. The phone keeps the battle state (so the rules, balls and berries
/// are exactly the phone's), the watch just sends button presses.
@MainActor
enum WatchBattles {
    private static var active: [UUID: SafariEncounter] = [:]

    static func handle(_ m: [String: Any]) -> [String: Any] {
        let store = GameStore.shared
        func reply(_ text: String, shakes: Int = 0, caught: Bool = false, ended: Bool) -> [String: Any] {
            ["message": text, "shakes": shakes, "caught": caught, "ended": ended,
             "snapshot": (try? JSONEncoder().encode(store.snapshot)) ?? Data()]
        }
        guard let id = UUID(uuidString: m["wild"] as? String ?? ""),
              let wild = store.state.pending.first(where: { $0.id == id }), wild.expiresAt > .now else {
            return reply("It's gone…", ended: true)
        }
        store.markOpened(id)              // opened on the watch counts as seen
        var s = active[id] ?? {
            var e = SafariEncounter(wild: wild)
            e.caughtBefore = store.state.dexCaught.contains(wild.speciesID)
            e.calmerBuddy = store.state.buddyAbility == .calmWild || FieldItems.multiplier(.calm, in: store.state) < 1
            return e
        }()
        var shakes = 0, caught = false
        var text: String?
        switch m["action"] as? String {
        case "ball":
            let kind = BallKind(rawValue: m["ball"] as? String ?? "") ?? .poke
            guard store.useBall(kind) else { return reply("No \(kind.name)s left!", ended: false) }
            let r = s.throwBall(kind)
            if !r.caught { store.ballFetch(kind) }
            shakes = r.shakes; caught = r.caught
        case "berry":
            let owned = ItemCatalog.berries.filter { (store.state.bag[$0] ?? 0) > 0 }
                .sorted { (store.state.bag[$0] ?? 0) > (store.state.bag[$1] ?? 0) }
            let key = (m["berry"] as? String).flatMap { owned.contains($0) ? $0 : nil } ?? owned.first
            guard let key, store.consume(key) else { return reply("You don't have any berries.", ended: false) }
            s.giveBerry(Dex.itemName(key))
        case "run":
            s.run()
        default:
            text = "A wild \(wild.species.name) appeared!"
        }
        var ended = true
        if case .active = s.phase { ended = false }
        if ended { store.finish(s); active[id] = nil } else { active[id] = s }
        return reply(text ?? s.log.last ?? "", shakes: shakes, caught: caught, ended: ended)
    }
}
