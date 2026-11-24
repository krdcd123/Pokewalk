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
        let from = min(since, Date().addingTimeInterval(-3 * 60))
        let list: [CMMotionActivity] = await withCheckedContinuation { cont in
            manager.queryActivityStarting(from: from, to: .now, to: .main) { a, _ in cont.resume(returning: a ?? []) }
        }
        return list.contains { $0.cycling && $0.confidence != .low }
    }
}
