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
        return max(await hk ?? 0, await pm ?? 0, Self.watchSteps(day: DailyStampsKey.key(day)))
    }

    // MARK: Steps sent directly by the watch (readable even while the iPhone is locked)

    private static let watchKey = "watchReportedSteps"

    static func reportWatchSteps(_ steps: Int, day: String) {
        var d = UserDefaults.standard.dictionary(forKey: watchKey) as? [String: Int] ?? [:]
        guard steps > (d[day] ?? 0) else { return }
        d[day] = steps
        if d.count > 10 { for k in d.keys.sorted().dropLast(10) { d.removeValue(forKey: k) } }
        UserDefaults.standard.set(d, forKey: watchKey)
    }

    static func watchSteps(day: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: watchKey) as? [String: Int])?[day] ?? 0
    }

    func distanceToday() async -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        async let hk = try? health.distance(from: start)
        async let pm = pedometerDistance(from: start, to: .now)
        return max(await hk ?? 0, await pm ?? 0)
    }

    /// Every step and metre since a date (the trainer card's lifetime totals).
    /// HealthKit keeps your full history; the pedometer only covers the last 7 days.
    func totals(since start: Date) async -> (steps: Int, meters: Double) {
        async let hkSteps = try? health.steps(from: start)
        async let hkMeters = try? health.distance(from: start)
        async let pmSteps = pedometerSteps(from: max(start, Date().addingTimeInterval(-7 * 86_400)), to: .now)
        async let pmMeters = pedometerDistance(from: max(start, Date().addingTimeInterval(-7 * 86_400)), to: .now)
        return (max(await hkSteps ?? 0, await pmSteps ?? 0), max(await hkMeters ?? 0, await pmMeters ?? 0))
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


/// Knows whether you're walking right now, so the trainer only walks on the map when you do.
@MainActor
final class WalkingDetector: ObservableObject {
    static let shared = WalkingDetector()
    @Published private(set) var isWalking = false

    private let motion = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private var motionSaysMoving = false
    private var motionSaysStill = false
    /// The step counter is working and allowed, so it's the real test of whether your feet are moving.
    private var pedometerTrusted: Bool {
        CMPedometer.isStepCountingAvailable() && CMPedometer.authorizationStatus() == .authorized
    }
    /// iOS only reports *changes* in activity, so "walking" can linger for minutes after you stop. When the
    /// step counter works, "walking" from the motion chip only counts while steps are still coming in.
    private var motionWalkingNow: Bool {
        motionSaysMoving && (!pedometerTrusted || Date().timeIntervalSince(lastStepAt) < 15)
    }
    /// In a car, bus or train (or on a bike): the trainer stands still and the trail isn't recorded.
    @Published private(set) var isDriving = false
    private var motionSaysVehicle = false
    private var lastStepAt = Date.distantPast
    private var lastSteps = 0
    private var timer: Timer?

    private init() {
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] a in
                guard let self, let a else { return }
                Task { @MainActor in
                    self.motionSaysMoving = (a.walking || a.running) && a.confidence != .low
                    self.motionSaysStill = a.stationary && a.confidence != .low
                    self.motionSaysVehicle = (a.automotive || a.cycling) && a.confidence != .low
                    if a.stationary && a.confidence != .low { self.motionSaysMoving = false; self.lastStepAt = .distantPast }
                    self.refresh()
                }
            }
        }
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: .now) { [weak self] data, _ in
                guard let steps = data?.numberOfSteps.intValue else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if steps > self.lastSteps { self.lastSteps = steps; self.lastStepAt = .now }
                    self.refresh()
                    if self.isWalking { LiveActivityManager.shared.hop() }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private var lastFastAt = Date.distantPast

    /// Are your feet actually moving (steps in the last ~20 s, or iOS's motion chip says walking/running)?
    /// GPS alone isn't trusted: standing still, especially indoors, the fix wanders tens of metres.
    /// If motion data isn't available or allowed, we can't tell, so it says yes.
    var feetMoving: Bool {
        guard CMMotionActivityManager.authorizationStatus() == .authorized,
              CMPedometer.isStepCountingAvailable() || CMMotionActivityManager.isActivityAvailable() else { return true }
        return motionWalkingNow || Date().timeIntervalSince(lastStepAt) < 20
    }

    /// Driving needs real evidence: vehicle-speed GPS in the last minute or two. Taking steps (or iOS saying
    /// you're walking) always wins, so the bike never sticks after you get out of the car.
    private func refresh() {
        let now = Date()
        let recentSteps = now.timeIntervalSince(lastStepAt) < 8
        let fix = LocationTracker.shared.latestFix.flatMap { now.timeIntervalSince($0.timestamp) < 10 ? $0 : nil }
        if let fix, fix.speed > 4.5 { lastFastAt = fix.timestamp }             // faster than ~10 mph
        let sinceFast = now.timeIntervalSince(lastFastAt)
        let driving = !recentSteps && !motionWalkingNow &&
            (sinceFast < 45 || (motionSaysVehicle && sinceFast < 150))          // stuck in traffic still counts
        if driving != isDriving { isDriving = driving }
        // GPS speed drifts while you stand still (especially indoors), so it only counts when there's no step
        // counter to ask, the fix is precise, and the motion chip doesn't say you're still.
        let gpsWalking = !pedometerTrusted && !motionSaysStill &&
            (fix?.speed ?? 0) > 0.8 && (fix?.horizontalAccuracy ?? 999) <= 20
        let walking = !driving && (motionWalkingNow || recentSteps || gpsWalking)
        if walking != isWalking { isWalking = walking }
    }
}


/// "yyyy-MM-dd" for a calendar day (the same key the watch sends).
enum DailyStampsKey {
    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
