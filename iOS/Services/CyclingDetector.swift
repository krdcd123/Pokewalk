import Foundation
import CoreMotion

/// Spots cycling *while it happens*, so step rewards pause during a ride (Apple Health only records the
/// workout once it's finished, which is too late — your arms would already have levelled your Pokémon).
/// Uses the iPhone's motion chip, plus the watch's own one (it reports when it sees cycling).
@MainActor
enum CyclingDetector {
    private static let manager = CMMotionActivityManager()
    /// Last time the watch said you were cycling.
    static var watchSawCyclingAt: Date?

    static func cycling(since: Date) async -> Bool {
        if let w = watchSawCyclingAt, Date().timeIntervalSince(w) < 4 * 60 { return true }
        guard CMMotionActivityManager.isActivityAvailable() else { return false }
        // Only the last few minutes (the first check after launch used to ask from the year 1, which Core
        // Motion never answered — that froze the whole step check, so steps showed 0 and nothing was earned).
        let now = Date()
        let from = max(now.addingTimeInterval(-10 * 60), min(since, now.addingTimeInterval(-3 * 60)))
        let list: [CMMotionActivity] = await withCheckedContinuation { cont in
            var done = false
            let finish: ([CMMotionActivity]) -> Void = { a in
                guard !done else { return }
                done = true
                cont.resume(returning: a)
            }
            manager.queryActivityStarting(from: from, to: now, to: .main) { a, _ in finish(a ?? []) }
            // never wait more than 5 s for an answer
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish([]) }
        }
        return list.contains { $0.cycling && $0.confidence != .low }
    }
}
