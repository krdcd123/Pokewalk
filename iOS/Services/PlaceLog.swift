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

    static let minStay: TimeInterval = 10 * 60      // counts as a place after 10 minutes
    static let radius: CLLocationDistance = 120      // wandering within this still counts as "there"

    @Published private(set) var revision = 0
    private var anchor: (loc: CLLocation, since: Date)?
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
        guard let a = anchor else { anchor = (loc, now); return }

        if loc.distance(from: a.loc) <= Self.radius {
            // Still here. Long enough to count?
            if open == nil, now.timeIntervalSince(a.since) >= Self.minStay {
                var stay = Stay(lat: a.loc.coordinate.latitude, lon: a.loc.coordinate.longitude, arrived: a.since)
                if let merged = mergeWithLast(stay) { stay = merged } else { closeOpenStays(before: stay) }
                open = stay
                save(stay)
                name(stay)
            }
        } else if loc.distance(from: a.loc) > Self.radius * 1.25 {
            // Left
            if var s = open {
                s.left = now
                save(s)
                open = nil
            }
            anchor = (loc, now)
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
        s.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
        save(s)
    }

    /// Prefer a named place nearby (shop, café, park…); otherwise the street / area.
    private func name(_ stay: Stay) {
        guard stay.name == nil else { return }
        Task {
            var found: String?
            let req = MKLocalPointsOfInterestRequest(center: stay.coordinate, radius: 60)
            if let resp = try? await MKLocalSearch(request: req).start() {
                found = resp.mapItems
                    .sorted { ($0.placemark.location?.distance(from: stay.location) ?? 999) < ($1.placemark.location?.distance(from: stay.location) ?? 999) }
                    .first?.name
            }
            if found == nil { found = await PlaceService.shared.placeName(for: stay.location) }
            guard let found else { return }
            // re-read so we don't overwrite times that changed meanwhile
            if var s = stays(on: stay.arrived).first(where: { $0.id == stay.id }), s.name == nil {
                s.name = found
                save(s)
                if open?.id == s.id { open = s }
            }
        }
    }
}
