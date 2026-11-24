import Foundation
import WatchConnectivity

/// Sends the party snapshot (and sprite PNGs) to the Watch, and answers sync requests from it.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var pending: WatchSnapshot?
    private let sentSpritesKey = "sentIconsToWatch"
    private var lastComplicationPush = Date.distantPast
    private var lastComplicationLevels = ""

    // Watch status for the Settings screen
    var isWatchPaired: Bool { session?.isPaired ?? false }
    var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }
    var isComplicationOnFace: Bool { session?.isComplicationEnabled ?? false }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ snapshot: WatchSnapshot) {
        guard let session else { return }
        guard session.activationState == .activated else { pending = snapshot; return }
        guard session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        let payload: [String: Any] = ["snapshot": data]
        try? session.updateApplicationContext(payload)

        // Watch app open (or reachable): send it straight away instead of waiting for iOS to deliver the context.
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        // Complication pushes wake the watch with priority, but there are only ~50 a day:
        // use them when a level changes, or at most every 15 minutes.
        // Anything you'd see change on the watch: who's in the party, their species (evolutions), level,
        // name, buddy and held items. Any change pushes to the watch with priority.
        let levels = snapshot.party.map {
            "\($0.id):\($0.speciesID):\($0.species.growth.level(forExp: $0.exp)):\($0.name):\($0.isBuddy):\($0.heldItem ?? "")"
        }.joined(separator: ",")
        let due = Date().timeIntervalSince(lastComplicationPush) > 15 * 60 || levels != lastComplicationLevels
        if due {
            if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
                session.transferCurrentComplicationUserInfo(payload)
            } else if levels != lastComplicationLevels {
                session.transferUserInfo(payload)        // out of priority pushes today: still queue it
            }
            lastComplicationPush = .now
            lastComplicationLevels = levels
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
                var name = ""
                if let id = UUID(uuidString: message["id"] as? String ?? ""), let mon = GameStore.shared.state.mon(id) {
                    await GameStore.shared.setBuddy(id)
                    name = mon.name
                }
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
        if Self.takeWatchSteps(message) { return }
        if message["request"] as? String == "resendSprites" {
            resetSentSprites()
            Task { @MainActor in self.send(GameStore.shared.snapshot) }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        _ = Self.takeWatchSteps(userInfo)
    }

    /// The watch's own step count for today. Apple Health can't be read while the iPhone is locked,
    /// so without this, steps from your watch (and the encounters/notifications they cause) would
    /// wait until you unlocked the phone.
    static func takeWatchSteps(_ m: [String: Any]) -> Bool {
        guard let steps = m["watchSteps"] as? Int, let day = m["day"] as? String else { return false }
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
        var s = active[id] ?? {
            var e = SafariEncounter(wild: wild)
            e.caughtBefore = store.state.dexCaught.contains(wild.speciesID)
            return e
        }()
        var shakes = 0, caught = false
        var text: String?
        switch m["action"] as? String {
        case "ball":
            let kind = BallKind(rawValue: m["ball"] as? String ?? "") ?? .poke
            guard store.useBall(kind) else { return reply("No \(kind.name)s left!", ended: false) }
            let r = s.throwBall(kind)
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
