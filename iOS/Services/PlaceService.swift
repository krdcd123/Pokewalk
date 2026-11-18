import Foundation
import CoreLocation
import MapKit

/// Turns a location into (a) a place name for "Met at …" and (b) habitats that shape wild encounters.
@MainActor
final class PlaceService {
    static let shared = PlaceService()

    private var habitatCache: (CLLocation, Date, Set<Habitat>)?
    private var nameCache: [String: String] = [:]
    private let geocoder = CLGeocoder()

    private func cacheKey(_ loc: CLLocation) -> String {
        String(format: "%.3f,%.3f", loc.coordinate.latitude, loc.coordinate.longitude)   // ~100 m grid
    }

    func placeName(for loc: CLLocation) async -> String? {
        let key = cacheKey(loc)
        if let hit = nameCache[key] { return hit }
        guard let mark = try? await geocoder.reverseGeocodeLocation(loc).first else { return nil }
        let primary = mark.areasOfInterest?.first ?? mark.subLocality ?? mark.thoroughfare ?? mark.name
        let name = [primary, mark.locality].compactMap { $0 }.removingDuplicates().joined(separator: ", ")
        nameCache[key] = name
        return name.isEmpty ? nil : name
    }

    func habitats(near loc: CLLocation?) async -> Set<Habitat> {
        guard let loc else { return [.urban, .grassland] }
        if let c = habitatCache, c.0.distance(from: loc) < 250, Date().timeIntervalSince(c.1) < 600 { return c.2 }

        var result: Set<Habitat> = []
        let request = MKLocalPointsOfInterestRequest(center: loc.coordinate, radius: 350)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .park, .nationalPark, .campground, .beach, .marina, .zoo, .museum, .university, .stadium,
            .amusementPark, .airport, .publicTransport, .store, .restaurant
        ])
        if let response = try? await MKLocalSearch(request: request).start() {
            for item in response.mapItems {
                switch item.pointOfInterestCategory {
                case .park?, .nationalPark?, .campground?: result.formUnion([.forest, .grassland])
                case .beach?, .marina?: result.formUnion([.sea, .watersEdge])
                case .zoo?: result.formUnion([.grassland, .rare])
                case .museum?: result.formUnion([.cave, .rare])
                case .airport?: result.formUnion([.mountain, .grassland])
                case .university?, .stadium?, .amusementPark?, .publicTransport?, .store?, .restaurant?:
                    result.insert(.urban)
                default: break
                }
            }
        }
        if loc.altitude > 300 { result.formUnion([.mountain, .roughTerrain]) }
        if result.isEmpty { result = [.urban, .grassland] }
        habitatCache = (loc, .now, result)
        return result
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
