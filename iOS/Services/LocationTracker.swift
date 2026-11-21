import Foundation
import CoreLocation

// MARK: - Recorded walking tracks (one JSON file per day)

struct TrackPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var t: TimeInterval

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
    var date: Date { Date(timeIntervalSince1970: t) }
}

struct WalkSummary: Identifiable, Hashable {
    var id: TimeInterval { start.timeIntervalSince1970 }
    var start: Date
    var end: Date
    var meters: Double
    var points: [TrackPoint]
}

@MainActor
final class TrackStore: ObservableObject {
    static let shared = TrackStore()

    /// Segments for today (a new segment starts after a gap or a jump).
    @Published private(set) var today: [[TrackPoint]] = []
    private var todayKey = TrackStore.key(for: .now)
    private var dirty = false

    private let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    init() { today = load(todayKey) }

    private func file(_ key: String) -> URL { dir.appendingPathComponent("\(key).json") }

    func load(_ key: String) -> [[TrackPoint]] {
        guard let data = try? Data(contentsOf: file(key)),
              let segs = try? JSONDecoder().decode([[TrackPoint]].self, from: data) else { return [] }
        return segs
    }

    func segments(for date: Date) -> [[TrackPoint]] {
        let k = Self.key(for: date)
        return k == todayKey ? today : load(k)
    }

    var daysWithTracks: [Date] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return files.compactMap { f.date(from: String($0.dropLast(5))) }.sorted(by: >)
    }

    func append(_ loc: CLLocation) {
        let k = Self.key(for: loc.timestamp)
        if k != todayKey { flush(); todayKey = k; today = load(k) }
        let p = TrackPoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, t: loc.timestamp.timeIntervalSince1970)
        if let last = today.last?.last {
            let gap = p.t - last.t
            let jump = loc.distance(from: last.location)
            if jump < 8 { return }                                  // not moved enough
            if gap > 300 || jump > 150 { today.append([p]) } else { today[today.count - 1].append(p) }
        } else {
            today.append([p])
        }
        dirty = true
        if (today.last?.count ?? 0) % 10 == 0 { flush() }
    }

    /// Every recorded day, for save export.
    func allDays() -> [String: [[TrackPoint]]] {
        flush()
        var out: [String: [[TrackPoint]]] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasSuffix(".json") {
            let key = String(f.dropLast(5))
            out[key] = load(key)
        }
        return out
    }

    /// Replace/merge recorded days from an imported save.
    func importDays(_ days: [String: [[TrackPoint]]]) {
        for (key, segs) in days {
            if let data = try? JSONEncoder().encode(segs) { try? data.write(to: file(key), options: .atomic) }
        }
        today = load(todayKey)
    }

    func flush() {
        guard dirty, let data = try? JSONEncoder().encode(today) else { return }
        try? data.write(to: file(todayKey), options: .atomic)
        dirty = false
    }

    static func meters(_ seg: [TrackPoint]) -> Double {
        zip(seg, seg.dropFirst()).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
    }

    func meters(on date: Date) -> Double { segments(for: date).reduce(0) { $0 + Self.meters($1) } }

    /// Segments of at least 150 m count as a "walk" in the journal.
    func walks(on date: Date) -> [WalkSummary] {
        segments(for: date).compactMap { seg in
            guard let a = seg.first, let b = seg.last else { return nil }
            let m = Self.meters(seg)
            return m >= 150 ? WalkSummary(start: a.date, end: b.date, meters: m, points: seg) : nil
        }
    }
}

// MARK: - Location tracking

/// Uses iOS 17's live updates + background activity session: it keeps running in the background,
/// pauses itself when you're stationary and resumes when you move — ideal for all-day walking.
@MainActor
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var isRunning = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published var walkStartedAt: Date?

    var onMovement: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var updatesTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private let walkKey = "walkStartedAt"

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
        if let t = UserDefaults.standard.object(forKey: walkKey) as? Date { walkStartedAt = t }
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
        }
    }

    /// Call on launch and whenever the mode changes.
    func apply(mode: TrackingMode) {
        let shouldRun = mode == .always || (mode == .walks && walkStartedAt != nil)
        shouldRun ? start() : stop()
    }

    func startWalk() {
        walkStartedAt = .now
        UserDefaults.standard.set(walkStartedAt, forKey: walkKey)
        start()
    }

    func endWalk(mode: TrackingMode) {
        walkStartedAt = nil
        UserDefaults.standard.removeObject(forKey: walkKey)
        TrackStore.shared.flush()
        if mode != .always { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        requestPermission()
        isRunning = true
        // The background session is what puts the blue location arrow in the status bar / Dynamic Island.
        // With "Always" permission iOS keeps delivering walk updates without it, so skip it then.
        if manager.authorizationStatus != .authorizedAlways { backgroundSession = CLBackgroundActivitySession() }
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, let loc = update.location else { continue }
                    self.handle(loc)
                }
            } catch {
                await MainActor.run { self?.isRunning = false }
            }
        }
    }

    private func stop() {
        updatesTask?.cancel(); updatesTask = nil
        backgroundSession?.invalidate(); backgroundSession = nil
        isRunning = false
        TrackStore.shared.flush()
    }

    private func handle(_ loc: CLLocation) {
        lastLocation = loc
        WeatherService.shared.update(for: loc)
        // Keep walking-speed fixes with decent accuracy; ignore driving and GPS noise.
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 35 else { return }
        if loc.speed > 4.5 { return }
        if WalkingDetector.shared.isDriving { return }           // in a vehicle: don't draw it as a walk
        TrackStore.shared.append(loc)
        onMovement?(loc)
    }

    /// One-off fix (for the map / encounter location when tracking is off).
    func currentLocation() -> CLLocation? { lastLocation ?? manager.location }
}
