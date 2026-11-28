import UIKit
import Foundation
import CoreLocation

// MARK: - Recorded walking tracks (one JSON file per day)

struct TrackPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var t: TimeInterval
    var drive: Bool? = nil          // recorded in a vehicle (shown in red, never counts as walking)

    var isDrive: Bool { drive == true }
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

    var directory: URL { dir }
    /// Every day's track, read straight from disk (safe off the main thread).
    nonisolated static func readAllDays(in dir: URL) -> [String: [[TrackPoint]]] {
        var out: [String: [[TrackPoint]]] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasSuffix(".json") {
            if let data = try? Data(contentsOf: dir.appendingPathComponent(f)),
               let segs = try? JSONDecoder().decode([[TrackPoint]].self, from: data) { out[String(f.dropLast(5))] = segs }
        }
        return out
    }

    /// Today's lines ready for the map: built once per change (only the newest line is redone as you move),
    /// instead of every map redraw converting every point of the day.
    struct Line: Identifiable, Equatable {
        let id: Int
        let drive: Bool
        var coords: [CLLocationCoordinate2D]
        static func == (a: Line, b: Line) -> Bool { a.id == b.id && a.drive == b.drive && a.coords.count == b.coords.count }
    }
    @Published private(set) var lines: [Line] = []
    private func rebuildLines(onlyLast: Bool = false) {
        if onlyLast, !today.isEmpty, lines.count == today.count {
            let i = today.count - 1
            lines[i] = Line(id: i, drive: Self.isDrive(today[i]), coords: today[i].map(\.coordinate))
        } else {
            lines = today.enumerated().map { Line(id: $0.offset, drive: Self.isDrive($0.element), coords: $0.element.map(\.coordinate)) }
        }
    }

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

    private var dayTimer: Timer?

    init() {
        today = load(todayKey)
        rebuildLines()
        // Midnight: start a fresh trail even if you haven't moved (the app may stay open overnight)
        dayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDay() }
        }
    }

    /// Switches to a new day's (empty) trail once the date changes.
    func refreshDay() {
        let k = TrackStore.key(for: .now)
        guard k != todayKey else { return }
        flush()
        todayKey = k
        today = load(k)
        rebuildLines()
    }

    private func file(_ key: String) -> URL { dir.appendingPathComponent("\(key).json") }

    func load(_ key: String) -> [[TrackPoint]] {
        guard let data = try? Data(contentsOf: file(key)),
              let segs = try? JSONDecoder().decode([[TrackPoint]].self, from: data) else { return [] }
        return Self.withoutJitter(segs)
    }

    /// A "drive" that never got more than 300 m from where it started is GPS wandering while you sat still
    /// (indoors), not a journey: drop it.
    static func withoutJitter(_ segs: [[TrackPoint]]) -> [[TrackPoint]] {
        segs.filter { seg in
            guard isDrive(seg), let first = seg.first else { return true }
            return seg.contains { $0.location.distance(from: first.location) > 300 }
        }
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

    func append(_ loc: CLLocation, drive: Bool = false) {
        let k = Self.key(for: loc.timestamp)
        if k != todayKey { flush(); todayKey = k; today = load(k); rebuildLines() }
        let p = TrackPoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, t: loc.timestamp.timeIntervalSince1970,
                           drive: drive ? true : nil)
        let segmentsBefore = today.count, pointsBefore = today.last?.count ?? 0
        defer {
            // only when a point was actually added (most fixes are skipped as too close)
            if today.count != segmentsBefore || (today.last?.count ?? 0) != pointsBefore {
                rebuildLines(onlyLast: today.count == segmentsBefore)
            }
        }
        if let last = today.last?.last {
            let gap = p.t - last.t
            // two location feeds can both deliver the same moment: keep time going forwards
            if gap <= 0 { return }
            let jump = loc.distance(from: last.location)
            // not moved enough — and a move smaller than the fix's own error margin is just noise
            if jump < (drive ? 25 : max(8, loc.horizontalAccuracy * 0.8)) { return }
            // A new line when you switch between walking and driving, after a long gap, or a GPS jump
            // (a train going through a tunnel or a dead spot keeps one line: only an impossible speed breaks it)
            let newSegment = last.isDrive != drive
                || (drive ? (gap > 3 * 3_600 || jump / max(gap, 1) > 70) : (gap > 300 || jump > 150))
            if newSegment {
                // join the switch-over point so walk and drive lines touch
                if last.isDrive != drive, gap < 120, jump < 500 { today.append([TrackPoint(lat: last.lat, lon: last.lon, t: last.t, drive: drive ? true : nil), p]) }
                else { today.append([p]) }
            } else { today[today.count - 1].append(p) }
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
        rebuildLines()
    }

    func flush() {
        guard dirty, let data = try? JSONEncoder().encode(today) else { return }
        try? data.write(to: file(todayKey), options: .atomic)
        dirty = false
    }

    static func meters(_ seg: [TrackPoint]) -> Double {
        zip(seg, seg.dropFirst()).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
    }

    static func isDrive(_ seg: [TrackPoint]) -> Bool { seg.last?.isDrive ?? false }

    /// Walked distance only (drives are left out).
    func meters(on date: Date) -> Double { segments(for: date).filter { !Self.isDrive($0) }.reduce(0) { $0 + Self.meters($1) } }
    func drivenMeters(on date: Date) -> Double { segments(for: date).filter(Self.isDrive).reduce(0) { $0 + Self.meters($1) } }

    /// Segments of at least 150 m count as a "walk" in the journal.
    func walks(on date: Date) -> [WalkSummary] {
        segments(for: date).compactMap { seg in
            guard !Self.isDrive(seg), let a = seg.first, let b = seg.last else { return nil }
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

    /// Where you are, for the map. Only republished when you've moved a few metres (or every 15 s / 60 s in
    /// the background): every GPS fix redrawing the whole map screen made the app laggy.
    @Published private(set) var lastLocation: CLLocation?
    /// Every fix as it arrives (not published — for code that needs the very latest one).
    private(set) var latestFix: CLLocation?

    private func setFix(_ loc: CLLocation) {
        if let f = latestFix, loc.timestamp <= f.timestamp { return }
        latestFix = loc
        let gap: TimeInterval = UIApplication.shared.applicationState == .active ? 15 : 60
        if let shown = lastLocation, loc.distance(from: shown) < 3, loc.timestamp.timeIntervalSince(shown.timestamp) < gap { return }
        lastLocation = loc
    }
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
        keepAlive.delegate = self
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
            // iOS visit detection for the Journal's Places (needs "Always")
            if status == .authorizedAlways {
                self.updateKeepAlive()
                manager.startMonitoringVisits()
                // If iOS closes PokéWalk to free memory, a significant move (a few hundred metres)
                // relaunches it in the background, which restarts step and walk tracking.
                manager.startMonitoringSignificantLocationChanges()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let from = ObjectIdentifier(manager)
        Task { @MainActor in
            // Every fix (even rough phone-mast ones) helps tell that you're on a journey
            for loc in locations { self.noteForJourney(loc); PlaceLog.shared.noteFix(loc) }
            // On a train / in a car the stay-awake feed switches to GPS, and every fix is drawn on the red line:
            // the walking feed can pause when your feet aren't moving, which is what cut the line off before.
            if from == ObjectIdentifier(self.keepAlive), self.vehicleMode {
                for loc in locations { self.handle(loc) }
                return
            }
            // Only precise fixes move "where you are": rough phone-mast fixes (hundreds of metres off) made the
            // map's follow camera fly back and forth, which looked like it zooming in and out by itself.
            guard let loc = locations.last, loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 50 else { return }
            self.setFix(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in PlaceLog.shared.addVisit(visit) }
    }

    /// Call on launch and whenever the mode changes.
    func apply(mode: TrackingMode) {
        let shouldRun = mode == .always || (mode == .walks && walkStartedAt != nil)
        shouldRun ? start() : stop()
        keepAliveMode = mode
        updateKeepAlive()
    }

    // MARK: Staying awake in the background

    /// Walk tracking pauses when you're standing still, and then iOS suspends the app — so new steps
    /// (e.g. from your watch at work) and notifications would wait until you opened it. This very
    /// low-power location feed (phone masts / Wi-Fi, no GPS) never pauses, which keeps PokéWalk running.
    private let keepAlive = CLLocationManager()
    private var keepAliveMode: TrackingMode = .always
    private var keepAliveOn = false

    /// Settings › Walking: run the stay-awake feed at full accuracy (GPS + Wi-Fi + masts) all the time.
    static var fullAccuracyAlways: Bool {
        get { UserDefaults.standard.bool(forKey: "keepAliveFullAccuracy") }
        set { UserDefaults.standard.set(newValue, forKey: "keepAliveFullAccuracy") }
    }
    private var keepAliveBest = false

    func setFullAccuracyAlways(_ on: Bool) {
        Self.fullAccuracyAlways = on
        keepAliveOn = false                      // re-apply with the new accuracy
        keepAlive.stopUpdatingLocation()
        updateKeepAlive()
    }

    private func updateKeepAlive() {
        let want = keepAliveMode != .off && manager.authorizationStatus == .authorizedAlways
        guard want != keepAliveOn else { return }
        keepAliveOn = want
        if want {
            configureKeepAlive()
            keepAlive.pausesLocationUpdatesAutomatically = false
            keepAlive.allowsBackgroundLocationUpdates = true
            keepAlive.showsBackgroundLocationIndicator = false
            keepAlive.startUpdatingLocation()
        } else {
            keepAlive.stopUpdatingLocation()
        }
    }

    private func configureKeepAlive() {
        let best = Self.fullAccuracyAlways || vehicleMode
        keepAliveBest = best
        keepAlive.desiredAccuracy = vehicleMode ? kCLLocationAccuracyBestForNavigation
            : best ? kCLLocationAccuracyBest : kCLLocationAccuracyThreeKilometers
        keepAlive.distanceFilter = vehicleMode ? 20 : best ? kCLDistanceFilterNone : 500
        keepAlive.activityType = vehicleMode ? .otherNavigation : .other
    }

    // MARK: Trains, buses and cars

    /// In a vehicle: GPS stays on (from the stay-awake feed) so the red line keeps going — GPS works with no
    /// phone signal. Switches back to the low-power feed as soon as you're walking again.
    private(set) var vehicleMode = false
    private var vehicleTimer: Timer?

    private func startVehicleWatch() {
        guard vehicleTimer == nil else { return }
        vehicleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkVehicle() }
        }
    }

    // A smooth train often looks "stationary" to the motion chip, so a journey is also spotted from where you
    // are: well over a kilometre covered in a few minutes (beyond any GPS wander) can only be travelling.
    private var journeyFixes: [CLLocation] = []
    private var lastJourneyAt = Date.distantPast
    var onJourney: Bool { Date().timeIntervalSince(lastJourneyAt) < 180 }

    private func noteForJourney(_ loc: CLLocation) {
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 1_500 else { return }
        journeyFixes.append(loc)
        journeyFixes.removeAll { loc.timestamp.timeIntervalSince($0.timestamp) > 600 }
        for f in journeyFixes {
            let dt = loc.timestamp.timeIntervalSince(f.timestamp)
            guard dt >= 90 else { continue }
            let surely = loc.distance(from: f) - loc.horizontalAccuracy - f.horizontalAccuracy
            if surely > 1_500, surely / dt > 5 {
                lastJourneyAt = loc.timestamp
                if !vehicleMode { checkVehicle() }
                break
            }
        }
    }

    private func checkVehicle() {
        let d = WalkingDetector.shared
        let inVehicle = onJourney || ((d.isDriving || d.inVehicle) && !d.isWalking && !d.isStill)
        guard inVehicle != vehicleMode else { return }
        vehicleMode = inVehicle
        if keepAliveOn {
            configureKeepAlive()
            keepAlive.stopUpdatingLocation()
            keepAlive.startUpdatingLocation()
        }
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
        startVehicleWatch()
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
        setFix(loc)
        WeatherService.shared.update(for: loc)
        PlaceLog.shared.feed(loc)
        guard loc.horizontalAccuracy > 0 else { return }
        // Speed: GPS's own (when it's trustworthy), or worked out from the last point — with no phone signal
        // the GPS speed is often missing. Indoors the position wanders tens of metres, so a worked-out speed only
        // counts over a distance well beyond that wander.
        let d = WalkingDetector.shared
        let acc = loc.horizontalAccuracy
        var speed = loc.speed >= 0 && loc.speedAccuracy >= 0 && loc.speedAccuracy < 3 ? loc.speed : -1
        let last = TrackStore.shared.today.last?.last
        if speed < 0, let last {
            let dt = loc.timestamp.timeIntervalSince1970 - last.t
            let dist = loc.distance(from: last.location)
            if dt > 5, dist > max(60, acc * 2) { speed = dist / dt }
        }
        // In a vehicle: record it as a drive (red on the map) — tracked, but it never earns anything.
        // Never while the motion chip says you're sat still (that's GPS wandering at home, not a journey).
        // A confident GPS speed of 13+ mph, or a journey spotted from distance covered, counts even if the
        // motion chip says "still" (smooth trains fool it — that's what cut the line off).
        let trustedFast = loc.speed > 6 && loc.speedAccuracy >= 0 && loc.speedAccuracy < 2.5
        let inVehicle = trustedFast || onJourney || (!d.isStill && (speed > 4.5 || d.isDriving || (d.inVehicle && !d.isWalking)))
        if inVehicle {
            // inside a train carriage GPS is rougher, so rough fixes are fine once it's clearly a journey
            let goodEnough = acc <= 35 || (acc <= 150 && (d.inVehicle || onJourney || trustedFast))
            let moved = last.map { loc.distance(from: $0.location) >= max(25, acc) } ?? true
            if goodEnough && moved { TrackStore.shared.append(loc, drive: true) }
            if !vehicleMode { checkVehicle() }
            return
        }
        // Keep walking-speed fixes with decent accuracy; ignore GPS noise.
        guard loc.horizontalAccuracy <= 35 else { return }
        // Standing still: the GPS fix drifts around, so don't draw it as a walk
        guard WalkingDetector.shared.feetMoving else { return }
        TrackStore.shared.append(loc)
        onMovement?(loc)
    }

    /// One-off fix (for the map / encounter location when tracking is off).
    func currentLocation() -> CLLocation? { latestFix ?? lastLocation ?? manager.location }
}
