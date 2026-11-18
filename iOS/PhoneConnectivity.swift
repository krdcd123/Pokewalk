import Foundation
import WatchConnectivity

/// Sends the party snapshot (and sprite PNGs) to the Watch, and answers sync requests from it.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var pending: WatchSnapshot?
    private let sentSpritesKey = "sentIconsToWatch"

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

        // Complication pushes get priority wake-ups on the watch (limited daily budget).
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(payload)
        }

        sendIcons(for: snapshot.party.map(\.speciesID))
    }

    /// The Watch shows each party member's box icon (yours from Sprites/icons, else PokeAPI's).
    private func sendIcons(for species: [Int]) {
        guard let session else { return }
        var sent = Set(UserDefaults.standard.array(forKey: sentSpritesKey) as? [Int] ?? [])
        for id in Set(species) where !sent.contains(id) {
            sent.insert(id)
            Task {
                guard let file = await SpriteStore.shared.ensureSharedIcon(id) else { return }
                session.transferFile(file, metadata: ["iconID": id])
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
        guard message["request"] as? String == "sync" else { replyHandler([:]); return }
        Task { @MainActor in
            await GameStore.shared.tick()
            let data = (try? JSONEncoder().encode(GameStore.shared.snapshot)) ?? Data()
            replyHandler(["snapshot": data])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "resendSprites" {
            resetSentSprites()
            Task { @MainActor in self.send(GameStore.shared.snapshot) }
        }
    }
}
