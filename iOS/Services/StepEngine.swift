import Foundation
import CoreMotion

/// Counts steps from two sources and takes the larger for each day:
///  • CMPedometer — the iPhone's own motion chip; works while the phone is locked, so encounters can
///    trigger live during a walk.
///  • HealthKit — includes Apple Watch steps (when you leave your phone behind); only readable while unlocked.
/// Rewards are applied from a per-day ledger, so late-arriving Watch steps are still counted once.
final class StepEngine {
    static let shared = StepEngine()

    private let pedometer = CMPedometer()
    private let health = StepCounter.shared

    var pedometerAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func pedometerSteps(from start: Date, to end: Date) async -> Int? {
        guard pedometerAvailable else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    func pedometerDistance(from start: Date, to end: Date) async -> Double? {
        guard CMPedometer.isDistanceAvailable() else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: data?.distance?.doubleValue)
            }
        }
    }

    /// Best available step total for a calendar day.
    func steps(onDay day: Date) async -> Int {
        let end = min(Date(), day.addingTimeInterval(86_400))
        async let hk = try? health.steps(from: day, to: end)
        async let pm = pedometerSteps(from: day, to: end)
        return max(await hk ?? 0, await pm ?? 0)
    }

    func distanceToday() async -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        async let hk = try? health.distance(from: start)
        async let pm = pedometerDistance(from: start, to: .now)
        return max(await hk ?? 0, await pm ?? 0)
    }

    /// Live pedometer callbacks while the app is running (foreground, or background with location on).
    func startLiveUpdates(_ onUpdate: @escaping () -> Void) {
        guard pedometerAvailable else { return }
        pedometer.startUpdates(from: Calendar.current.startOfDay(for: .now)) { _, _ in
            DispatchQueue.main.async(execute: onUpdate)
        }
    }

    func stopLiveUpdates() { pedometer.stopUpdates() }
}
