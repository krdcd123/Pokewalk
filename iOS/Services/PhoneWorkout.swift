import Foundation
import HealthKit
import WatchConnectivity

/// Starts workouts from the iPhone. They're recorded on your Apple Watch (heart rate, calories, distance,
/// saved to Apple Health like Apple's Workout app) and mirrored back here, so the map shows the live
/// numbers and step rewards pause for anything that isn't walking. Without a watch, the iPhone records it.
@MainActor
final class PhoneWorkout: NSObject, ObservableObject {
    static let shared = PhoneWorkout()
    private let store = StepCounter.shared.store

    @Published private(set) var live: WorkoutLive? { didSet { liveAt = .now } }
    /// When the last numbers arrived (the timer counts on smoothly in between).
    private(set) var liveAt = Date()
    @Published private(set) var kind: WorkoutKind?
    @Published var message: String?

    private var mirrored: HKWorkoutSession?
    private var localSession: HKWorkoutSession?
    private var localBuilder: HKWorkoutBuilder?
    private var localStart: Date?

    var isActive: Bool { kind != nil }
    /// Step rewards pause during any workout that isn't walking / running / hiking.
    var pausesSteps: Bool { kind.map { !$0.countsSteps } ?? false }

    /// Call once at launch: picks up workouts started on the watch (or by this phone) as they mirror over.
    func setUp() {
        store.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in PhoneWorkout.shared.attach(session) }
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        mirrored = session
        session.delegate = self
        let k = WorkoutKind.kind(for: session.workoutConfiguration)
        kind = k
        if live == nil { live = WorkoutLive(kindID: k.id, start: session.startDate ?? .now, elapsed: 0, paused: false, kcal: 0, meters: 0) }
        GameStore.shared.requestTick(minInterval: 0)
    }

    /// Long-press your trainer → pick a workout.
    func start(_ k: WorkoutKind) async {
        guard !isActive else { return }
        try? await store.requestAuthorization(toShare: WorkoutKind.shareTypes, read: WorkoutKind.readTypes)
        let s = WCSession.isSupported() ? WCSession.default : nil
        if let s, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled {
            do {
                try await store.startWatchApp(toHandle: k.configuration)
                // Show it straight away; the watch's live numbers follow within a few seconds
                kind = k
                live = WorkoutLive(kindID: k.id, start: .now, elapsed: 0, paused: false, kcal: 0, meters: 0)
                message = "\(k.name) started on your Apple Watch."
                return
            } catch {
                message = "Couldn't reach your Apple Watch — recording on your iPhone instead."
            }
        }
        await startOnPhone(k)
    }

    /// No watch: the iPhone records the workout itself (calories are estimated, no heart rate).
    private func startOnPhone(_ k: WorkoutKind) async {
        let config = k.configuration
        if #available(iOS 26.0, *) {
            do {
                let session = try HKWorkoutSession(healthStore: store, configuration: config)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
                session.delegate = self
                localSession = session
                localBuilder = builder
                let now = Date()
                localStart = now
                session.startActivity(with: now)
                try await builder.beginCollection(at: now)
                kind = k
                live = WorkoutLive(kindID: k.id, start: now, elapsed: 0, paused: false, kcal: 0, meters: 0)
                pollLocal()
            } catch {
                message = "Couldn't start the workout."
            }
        } else {
            message = "Workouts need your Apple Watch (or iOS 26 on your iPhone)."
        }
    }

    /// iPhone-recorded workouts: refresh the numbers every few seconds.
    private func pollLocal() {
        Task { @MainActor in
            while let b = localBuilder, kind != nil {
                let kcal = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                let m = kind?.distanceType.flatMap { b.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) } ?? 0
                live?.kcal = kcal; live?.meters = m
                live?.elapsed = b.elapsedTime(at: .now)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func togglePause() {
        guard isActive else { return }
        let cmd = (live?.paused ?? false) ? "resume" : "pause"
        if let localSession {
            cmd == "pause" ? localSession.pause() : localSession.resume()
            return
        }
        // Both routes to the watch: the mirrored workout session, and a plain message in case mirroring dropped
        if let mirrored { Task { try? await mirrored.sendToRemoteWorkoutSession(data: Data(cmd.utf8)) } }
        tellWatch(cmd)
        live?.paused = (cmd == "pause")                  // show it straight away; the watch confirms
    }

    private var endTimeout: Task<Void, Never>?
    private var endedAt = Date.distantPast

    func end() {
        guard isActive else { return }
        if let localSession { localSession.end(); return }
        if let mirrored { Task { try? await mirrored.sendToRemoteWorkoutSession(data: Data("end".utf8)) } }
        tellWatch("end")
        // If the watch doesn't confirm within a few seconds, end it here anyway so the map never gets stuck
        // on the tracker (and step rewards never stay paused).
        endTimeout?.cancel()
        endTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self.isActive else { return }
            self.finished()
        }
    }

    /// Numbers from the watch, via the mirrored session or WatchConnectivity (whichever arrives).
    func takeWatchLive(_ u: WorkoutLive) {
        if u.ended {
            // only the workout it belongs to (a late "ended" mustn't stop a newer one)
            if isActive, abs((live?.start ?? u.start).timeIntervalSince(u.start)) < 90 { finished() }
            return
        }
        // late numbers from a workout that's just been ended: don't bring the tracker back
        if kind == nil && Date().timeIntervalSince(endedAt) < 20 { return }
        live = u
        if kind == nil {
            kind = WorkoutKind.kind(id: u.kindID)
            GameStore.shared.requestTick(minInterval: 0)
        }
        watchStale()
    }

    /// A watch workout we only hear about over WatchConnectivity: if the watch goes quiet for 2 minutes
    /// (it ended while out of reach), clear the tracker rather than leave it stuck.
    private var staleCheck: Task<Void, Never>?
    private func watchStale() {
        guard mirrored == nil, localSession == nil else { return }
        staleCheck?.cancel()
        staleCheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, self.isActive, self.mirrored == nil, self.localSession == nil,
                  Date().timeIntervalSince(self.liveAt) >= 110 else { return }
            self.finished()
        }
    }

    /// Sends pause / resume / end to the watch app over WatchConnectivity.
    private func tellWatch(_ cmd: String) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let msg: [String: Any] = ["workoutCommand": cmd, "at": Date().timeIntervalSince1970]
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) }
        } else {
            s.transferUserInfo(msg)                    // the watch ignores it if it arrives much later
        }
    }

    /// The workout's over (saved on the watch / phone): clear the tracker and show "Workout complete!".
    private func finished() {
        endTimeout?.cancel(); endTimeout = nil
        staleCheck?.cancel(); staleCheck = nil
        if isActive { endedAt = .now }
        kind = nil; live = nil; mirrored = nil; localSession = nil; localBuilder = nil
        Task { @MainActor in
            // Give Apple Health a moment to have the saved workout, then reward it and pop the card up
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(3))
                await GameStore.shared.processWorkouts()
                if GameStore.shared.workoutPopup != nil || !GameStore.shared.state.unseenWorkouts.isEmpty { break }
            }
            GameStore.shared.showWorkoutPopupIfNeeded()
            GameStore.shared.requestTick(minInterval: 0)
        }
    }

    private func finishLocal(at date: Date) async {
        guard let b = localBuilder else { finished(); return }
        try? await b.endCollection(at: date)
        _ = try? await b.finishWorkout()
        finished()
    }
}

extension PhoneWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .paused: self.live?.paused = true
            case .running: self.live?.paused = false
            case .ended, .stopped:
                if s === self.localSession { await self.finishLocal(at: date) } else { self.finished() }
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func workoutSession(_ s: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.finished() }
    }

    /// Live numbers from the watch.
    nonisolated func workoutSession(_ s: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let updates = data.compactMap { try? JSONDecoder().decode(WorkoutLive.self, from: $0) }
        Task { @MainActor in
            for u in updates { self.takeWatchLive(u) }
        }
    }
}
