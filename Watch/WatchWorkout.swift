import Foundation
import HealthKit
import WatchKit
import WatchConnectivity

/// Records a workout on the watch (like Apple's Workout app): heart rate, calories, distance, saved to
/// Apple Health. Mirrors to the iPhone so PokéWalk there shows the live numbers and pauses step rewards.
@MainActor
final class WatchWorkout: NSObject, ObservableObject {
    static let shared = WatchWorkout()
    private let store = StepCounter.shared.store

    @Published private(set) var kind: WorkoutKind?
    @Published private(set) var paused = false
    @Published private(set) var start: Date?
    @Published private(set) var heartRate: Double?
    @Published private(set) var kcal: Double = 0
    @Published private(set) var meters: Double = 0
    @Published var summary: String?

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastSent = Date.distantPast

    var isActive: Bool { kind != nil }
    var elapsed: TimeInterval { builder?.elapsedTime ?? 0 }

    func start(_ kind: WorkoutKind) async {
        guard session == nil else { return }
        try? await store.requestAuthorization(toShare: WorkoutKind.shareTypes, read: WorkoutKind.readTypes)
        let config = kind.configuration
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.kind = kind
            heartRate = nil; kcal = 0; meters = 0; paused = false
            let now = Date()
            start = now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            try? await session.startMirroringToCompanionDevice()     // the iPhone shows it live
            WKInterfaceDevice.current().play(.start)
            sendLive(force: true)
        } catch {
            summary = "Couldn't start the workout."
            reset()
        }
    }

    func togglePause() {
        guard let session else { return }
        paused ? session.resume() : session.pause()
    }

    func end() {
        session?.end()
    }

    /// Pause / resume / end sent from the iPhone over WatchConnectivity (backup for the mirrored session).
    /// Ignored if it's old or was sent before this workout started.
    func remote(_ cmd: String, sentAt: Date) {
        guard isActive, let start, sentAt >= start, Date().timeIntervalSince(sentAt) < 120 else { return }
        switch cmd {
        case "end": end()
        case "pause": if !paused { togglePause() }
        case "resume": if paused { togglePause() }
        default: break
        }
    }

    private func finish(at date: Date) async {
        guard let builder else { reset(); return }
        try? await builder.endCollection(at: date)
        let workout = try? await builder.finishWorkout()             // saved to Apple Health
        let k = kind
        var live = currentLive()
        live.ended = true
        if let data = try? JSONEncoder().encode(live) {
            try? await session?.sendToRemoteWorkoutSession(data: data)
            tellPhone(data, important: true)
        }
        WKInterfaceDevice.current().play(.stop)
        if let k {
            let mins = Int(((workout?.duration ?? elapsed) / 60).rounded())
            summary = "\(k.name) saved: \(mins) min · \(Int(kcal)) kcal"
        }
        reset()
    }

    private func reset() {
        session = nil; builder = nil; kind = nil; start = nil; paused = false
    }

    private func currentLive() -> WorkoutLive {
        WorkoutLive(kindID: kind?.id ?? "other", start: start ?? .now, elapsed: elapsed, paused: paused,
                    kcal: kcal, meters: meters, heartRate: heartRate)
    }

    /// Numbers to the phone every few seconds (or on pause/resume).
    private func sendLive(force: Bool = false) {
        guard let session, force || Date().timeIntervalSince(lastSent) > 3,
              let data = try? JSONEncoder().encode(currentLive()) else { return }
        lastSent = .now
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
        tellPhone(data, important: force)
    }

    /// Also over WatchConnectivity, so the iPhone's map switches to the workout tracker even when the
    /// mirrored session doesn't connect (it can't always wake the iPhone app).
    private var lastPhoneSend = Date.distantPast
    private func tellPhone(_ data: Data, important: Bool) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        let msg: [String: Any] = ["workoutLive": data]
        if s.isReachable {
            guard important || Date().timeIntervalSince(lastPhoneSend) > 5 else { return }
            lastPhoneSend = .now
            s.sendMessage(msg, replyHandler: nil) { _ in if important { s.transferUserInfo(msg) } }
        } else if important {
            s.transferUserInfo(msg)
        }
    }
}

extension WatchWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .paused: self.paused = true; self.sendLive(force: true)
            case .running: self.paused = false; self.sendLive(force: true)
            case .ended: await self.finish(at: date)
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.summary = "The workout stopped unexpectedly."; self.reset() }
    }

    /// Pause / resume / end pressed on the iPhone.
    nonisolated func workoutSession(_ s: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let commands = data.compactMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in
            for c in commands {
                switch c {
                case "end": self.end()
                case "pause": if !self.paused { self.togglePause() }
                case "resume": if self.paused { self.togglePause() }
                default: break
                }
            }
        }
    }
}

extension WatchWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let kcal { self.kcal = kcal }
            if let dt = self.kind?.distanceType,
               let m = workoutBuilder.statistics(for: dt)?.sumQuantity()?.doubleValue(for: .meter()) {
                self.meters = m
            }
            self.sendLive()
        }
    }
}
