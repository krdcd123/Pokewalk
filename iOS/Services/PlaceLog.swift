import Foundation
import CoreLocation
import MapKit

/// A place you stayed for a while (10+ minutes), for the Journal's "Places" timeline.
struct Stay: Codable, Identifiable, Hashable {
    var id = UUID()
    var lat: Double
    var lon: Double
    var arrived: Date
    var left: Date?                 // nil = you're still there
    var name: String?
    var options: [String]?          // other places it could have been (most likely first), for "Where was this?"
    var userNamed: Bool?            // you picked / typed the name: never change it

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
    func duration(now: Date = .now) -> TimeInterval { (left ?? now).timeIntervalSince(arrived) }

    /// What the Journal calls it: "Home" / "Work" if it's at a place set in Settings, otherwise its place name.
    var shownName: String? {
        if HomeLocation.contains(location) { return "Home" }
        if WorkLocation.contains(location) { return "Work" }
        return name
    }
}

/// A place you set in Settings (home, work). Stays within ~120 m of it show under its name in the Journal.
struct SavedSpot {
    let key: String
    let radius: CLLocationDistance = 120
    private var d: UserDefaults { .standard }

    var isSet: Bool { d.bool(forKey: "\(key)Set") }

    var location: CLLocation? {
        guard isSet else { return nil }
        return CLLocation(latitude: d.double(forKey: "\(key)Lat"), longitude: d.double(forKey: "\(key)Lon"))
    }

    func set(_ loc: CLLocation?) {
        if let loc {
            d.set(loc.coordinate.latitude, forKey: "\(key)Lat")
            d.set(loc.coordinate.longitude, forKey: "\(key)Lon")
            d.set(true, forKey: "\(key)Set")
        } else {
            d.set(false, forKey: "\(key)Set")
        }
    }

    func contains(_ loc: CLLocation) -> Bool {
        guard let spot = location else { return false }
        return spot.distance(from: loc) <= radius
    }
}

let HomeLocation = SavedSpot(key: "home")
let WorkLocation = SavedSpot(key: "work")

/// Notices when you stop somewhere for a while and names the place (shop, park, street…).
/// Works from the location updates PokéWalk already gets; with "Always" location it also uses iOS's
/// visit detection, which catches stays even while the app is asleep.
@MainActor
final class PlaceLog: ObservableObject {
    static let shared = PlaceLog()

    static let minStay: TimeInterval = 15 * 60      // counts as a place after 15 minutes
    static let radius: CLLocationDistance = 100      // wandering within this still counts as "there"

    @Published private(set) var revision = 0
    private var anchor: (loc: CLLocation, since: Date)?
    /// While at an anchor: how many fixes came in, and how many while you were walking. Pacing up and down a
    /// street (or walking round at work) isn't "stopping somewhere".
    private var fixesHere = 0
    private var walkingHere = 0
    /// Precise fixes while there, to find the middle of where you actually were (the first fix is usually the
    /// doorway you walked in through — or the place next door).
    private var hereFixes: [CLLocation] = []

    private static func centre(_ fixes: [CLLocation]) -> CLLocation? {
        let good = fixes.filter { $0.horizontalAccuracy <= 40 }
        let use = good.count >= 3 ? good : fixes
        guard !use.isEmpty else { return nil }
        var lat = 0.0, lon = 0.0, wsum = 0.0
        for f in use {
            let w = 1 / max(5, f.horizontalAccuracy)
            lat += f.coordinate.latitude * w; lon += f.coordinate.longitude * w; wsum += w
        }
        return CLLocation(latitude: lat / wsum, longitude: lon / wsum)
    }

    /// Any fix at all (rough ones too, even on a train): if you're clearly somewhere else, the stay has ended.
    /// Without this a stay could carry on for hours after you'd left on a train.
    func noteFix(_ loc: CLLocation) {
        guard var s = open, loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 2_000 else { return }
        if loc.distance(from: s.location) - loc.horizontalAccuracy > Self.radius * 1.5 {
            s.left = loc.timestamp
            open = nil
            anchor = nil
            finish(s)
        }
    }
    private var open: Stay?

    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Places", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func file(_ day: Date) -> URL { dir.appendingPathComponent("\(TrackStore.key(for: day)).json") }

    func stays(on day: Date) -> [Stay] {
        guard let data = try? Data(contentsOf: file(day)),
              let list = try? JSONDecoder().decode([Stay].self, from: data) else { return [] }
        return list.sorted { $0.arrived < $1.arrived }
    }

    private func save(_ stay: Stay) {
        let day = stay.arrived
        var list = stays(on: day)
        if let i = list.firstIndex(where: { $0.id == stay.id }) { list[i] = stay } else { list.append(stay) }
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: file(day), options: .atomic) }
        revision += 1
    }

    /// Feed every location fix (moving or not).
    func feed(_ loc: CLLocation) {
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 100 else { return }
        let now = loc.timestamp
        // passing through on a train or in a car is never a stay (and ends one you were in)
        if LocationTracker.shared.onJourney || WalkingDetector.shared.isDriving {
            if var s = open { s.left = now; open = nil; finish(s) }
            anchor = nil
            return
        }
        guard let a = anchor else { anchor = (loc, now); fixesHere = 0; walkingHere = 0; hereFixes = [loc]; return }

        if loc.distance(from: a.loc) <= Self.radius {
            fixesHere += 1
            hereFixes.append(loc)
            if hereFixes.count > 400 { hereFixes.removeFirst(100) }
            if WalkingDetector.shared.isWalking { walkingHere += 1 }
            // Still here. Long enough to count — and mostly not walking about?
            let mostlyStill = fixesHere < 6 || Double(walkingHere) / Double(fixesHere) < 0.5
            if open == nil, mostlyStill, now.timeIntervalSince(a.since) >= Self.minStay {
                let mid = Self.centre(hereFixes) ?? a.loc
                var stay = Stay(lat: mid.coordinate.latitude, lon: mid.coordinate.longitude, arrived: a.since)
                if let merged = mergeWithLast(stay) { stay = merged } else { closeOpenStays(before: stay) }
                open = stay
                save(stay)
                name(stay)
            }
        } else if loc.distance(from: a.loc) > Self.radius * 1.25 {
            // Left: settle where it was and what it was, now we know how long you stayed
            if var s = open {
                s.left = now
                if let mid = Self.centre(hereFixes) { s.lat = mid.coordinate.latitude; s.lon = mid.coordinate.longitude }
                open = nil
                finish(s)
            }
            anchor = (loc, now)
            fixesHere = 0; walkingHere = 0; hereFixes = [loc]
        }
    }

    /// iOS visit detection ("Always" location): arrivals/departures even while the app sleeps.
    func addVisit(_ v: CLVisit) {
        guard v.horizontalAccuracy <= 200 else { return }
        let arrived = v.arrivalDate == .distantPast ? nil : v.arrivalDate
        let left = v.departureDate == .distantFuture ? nil : v.departureDate
        guard let arrived else { return }
        if let left, left.timeIntervalSince(arrived) < Self.minStay { return }
        let here = CLLocation(latitude: v.coordinate.latitude, longitude: v.coordinate.longitude)
        // Same place we already logged? Just fill in the times.
        if var s = stays(on: arrived).first(where: { $0.location.distance(from: here) < Self.radius * 1.5 &&
                                                   abs($0.arrived.timeIntervalSince(arrived)) < 45 * 60 }) {
            s.arrived = min(s.arrived, arrived)
            if let left { s.left = max(s.left ?? left, left); if open?.id == s.id { open = nil } }
            save(s)
            return
        }
        // iOS's visits can be rough: one that overlaps stays we've already logged somewhere else is ignored
        // (that made a "2 h" place that had three other places inside it)
        let end = left ?? .now
        let overlaps = stays(on: arrived).contains { o in
            let oEnd = o.left ?? .now
            return o.location.distance(from: here) >= Self.radius * 1.5 && o.arrived < end && oEnd > arrived
        }
        if overlaps { return }
        let s = Stay(lat: here.coordinate.latitude, lon: here.coordinate.longitude, arrived: arrived, left: left)
        save(s)
        name(s)
    }

    /// Popped out and came straight back (under 10 min)? Treat it as one stay.
    /// Also: still logged as "here" from before the app was closed? Carry on with that stay instead of
    /// starting another one at the same place.
    private func mergeWithLast(_ s: Stay) -> Stay? {
        guard var last = stays(on: s.arrived).last, last.location.distance(from: s.location) < Self.radius else { return nil }
        if let left = last.left, s.arrived.timeIntervalSince(left) >= 10 * 60 { return nil }
        last.left = nil
        return last
    }

    /// A new stay started somewhere else: anything still marked "here" has ended.
    private func closeOpenStays(before s: Stay) {
        for var old in stays(on: s.arrived) where old.id != s.id && old.left == nil && old.arrived < s.arrived {
            old.left = s.arrived
            save(old)
        }
    }

    func rename(_ stay: Stay, to name: String) {
        var s = stay
        let clean = name.trimmingCharacters(in: .whitespaces)
        s.name = clean.isEmpty ? nil : clean
        s.userNamed = clean.isEmpty ? nil : true
        if !clean.isEmpty { PlaceMemory.learn(clean, at: s.location) }
        save(s)
    }

    /// Older places (named before the smarter guessing) get a second look when you open their day,
    /// so they get the better name and "Where was this?" choices. Your own names are never touched.
    func refineNames(on day: Date) {
        for st in stays(on: day) where st.options == nil && st.userNamed != true && st.left != nil {
            name(st, force: true, keepUnknownName: true)
        }
    }

    /// A stay just ended: name it again with everything we now know (how long you stayed).
    private func finish(_ s: Stay) {
        save(s)
        if s.userNamed != true { name(s, force: true) }
    }

    /// Name it after a notable place right there (café, park, shop, station, museum…) — never a random office or
    /// business that happens to be nearest; otherwise the street / area.
    static var notable: [MKPointOfInterestCategory] { PlaceGuesser.notable }

    /// `keepUnknownName`: a name that isn't one of the nearby places was probably typed by you (before names
    /// were marked as yours) — keep it, just add the choices.
    private func name(_ stay: Stay, force: Bool = false, keepUnknownName: Bool = false) {
        guard force || stay.name == nil, stay.userNamed != true else { return }
        Task {
            let guess = await PlaceGuesser.guess(stay)
            var found = guess?.name
            if found == nil { found = await PlaceService.shared.placeName(for: stay.location) }
            guard let found else { return }
            // re-read so we don't overwrite times (or your own name) that changed meanwhile
            if var s = stays(on: stay.arrived).first(where: { $0.id == stay.id }), s.userNamed != true {
                let typed = keepUnknownName && s.name != nil && !(guess?.options.contains(s.name!) ?? false)
                    && s.name != (await PlaceService.shared.placeName(for: stay.location))
                if typed {
                    s.userNamed = true
                    s.options = guess?.options
                    save(s)
                    return
                }
                s.name = found
                s.options = guess?.options
                save(s)
                if open?.id == s.id { open = s }
            }
        }
    }
}
