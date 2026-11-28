import Foundation
import CoreLocation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Places you've named yourself: the next stay there gets that name straight away.
enum PlaceMemory {
    private struct Spot: Codable { let lat: Double; let lon: Double; let name: String }
    private static let key = "placeMemory"

    private static var spots: [Spot] {
        get { (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Spot].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.suffix(300))), forKey: key) }
    }

    static func learn(_ name: String, at loc: CLLocation) {
        var all = spots.filter { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: loc) > 40 }
        all.append(Spot(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, name: name))
        spots = all
    }

    static func name(near loc: CLLocation) -> String? {
        spots.map { ($0, CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: loc)) }
            .filter { $0.1 <= 60 }.min { $0.1 < $1.1 }?.0.name
    }
}

/// Works out which place you were actually at, rather than just the nearest pin on the map.
/// Clues: where you were for most of the stay (not the doorway), how long you stayed, the time of day,
/// places you've named before — and, on iPhones with Apple Intelligence, Apple's on-device model weighs
/// them up (nothing leaves your phone).
enum PlaceGuesser {
    struct Guess { let name: String; let options: [String] }
    static let notable: [MKPointOfInterestCategory] = [
        .airport, .amusementPark, .aquarium, .bakery, .beach, .brewery, .cafe, .campground, .fitnessCenter,
        .foodMarket, .hospital, .hotel, .library, .marina, .movieTheater, .museum, .nationalPark, .nightlife,
        .park, .publicTransport, .restaurant, .school, .stadium, .store, .theater, .university, .winery, .zoo,
    ]

    struct Candidate { let name: String; let category: MKPointOfInterestCategory?; let distance: Double; var score: Double }

    static func guess(_ stay: Stay) async -> Guess? {
        // 1. You named it before
        if let known = PlaceMemory.name(near: stay.location) { return Guess(name: known, options: []) }

        // 2. Notable places around where you were
        let req = MKLocalPointsOfInterestRequest(center: stay.coordinate, radius: 90)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: notable)
        guard let resp = try? await MKLocalSearch(request: req).start() else { return nil }
        var cands: [Candidate] = resp.mapItems.compactMap { item in
            guard let name = item.name, let l = item.placemark.location else { return nil }
            let d = l.distance(from: stay.location)
            guard d <= 90 else { return nil }
            return Candidate(name: name, category: item.pointOfInterestCategory, distance: d, score: 0)
        }
        guard !cands.isEmpty else { return nil }

        // 3. Score: closeness × how well the kind of place fits the time and how long you stayed
        let minutes = stay.duration() / 60
        let hour = Calendar.current.component(.hour, from: stay.arrived)
        for i in cands.indices {
            cands[i].score = exp(-cands[i].distance / 30) * fit(cands[i].category, minutes: minutes, hour: hour)
        }
        cands.sort { $0.score > $1.score }
        let top = Array(cands.prefix(6))
        var best = top[0].name

        // 4. Apple's on-device model, when this iPhone has it, makes the final call between the front-runners
        if top.count > 1, let ai = await askModel(top, minutes: minutes, arrived: stay.arrived) { best = ai }

        var options = top.map(\.name)
        options.removeAll { $0 == best }
        return Guess(name: best, options: [best] + options.removingDuplicates())
    }

    /// How well a kind of place fits the visit.
    static func fit(_ c: MKPointOfInterestCategory?, minutes: Double, hour: Int) -> Double {
        let meal = (11...14).contains(hour) || (17...22).contains(hour)
        let long = minutes >= 25
        switch c {
        case .restaurant?: return meal && long ? 3.0 : long ? 1.6 : 0.8
        case .cafe?, .bakery?: return minutes < 60 ? 1.6 : 1.0
        case .nightlife?, .brewery?, .winery?: return hour >= 18 || hour < 3 ? 1.8 : 0.5
        case .store?, .foodMarket?: return minutes < 45 ? 1.4 : 0.7
        case .publicTransport?: return minutes < 30 ? 1.5 : 0.6
        case .hotel?: return hour >= 21 || hour < 6 || minutes > 300 ? 2.5 : 0.6
        case .university?, .school?, .hospital?: return minutes > 120 ? 2.0 : 0.7
        case .movieTheater?, .theater?, .stadium?: return minutes > 90 ? 2.2 : 0.6
        case .museum?, .aquarium?, .zoo?, .amusementPark?: return minutes > 45 ? 1.8 : 0.8
        case .park?, .nationalPark?, .beach?: return 1.2
        case .fitnessCenter?: return minutes > 30 ? 1.6 : 0.8
        default: return 1.0
        }
    }

    private static func askModel(_ top: [Candidate], minutes: Double, arrived: Date) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let f = DateFormatter(); f.dateFormat = "EEEE HH:mm"
            let list = top.map { c in
                "- \(c.name) (\(c.category.map { String(describing: $0.rawValue).replacingOccurrences(of: "MKPOICategory", with: "") } ?? "place"), \(Int(c.distance)) m away)"
            }.joined(separator: "\n")
            let prompt = """
            Someone's phone stayed in one spot from \(f.string(from: arrived)) for \(Int(minutes)) minutes.
            Places within GPS range (distances are from the middle of where the phone was; GPS indoors can be 20–50 m out):
            \(list)
            Which one were they most likely in? Think about the kind of place, the time of day and how long they stayed \
            (e.g. a long evening stay is likely a meal at a restaurant, not a shop). Reply with only the exact name from the list.
            """
            do {
                let session = LanguageModelSession(instructions: "You pick the most likely place from a list. Answer with one exact name from the list, nothing else.")
                let answer = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
                return top.first { answer.localizedCaseInsensitiveContains($0.name) }?.name
            } catch { return nil }
        }
        #endif
        return nil
    }
}
