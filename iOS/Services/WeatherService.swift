import Foundation
import CoreLocation

/// Current weather where you are (Open-Meteo: free, no key, no Apple entitlement needed).
/// Refreshes every 15 minutes while the app is open, and nudges which Pokémon appear.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var condition: WeatherCondition?
    @Published private(set) var temperature: Double?
    @Published private(set) var isDay = true
    private var lastFetch = Date.distantPast
    private var lastSpot: CLLocation?

    /// Call often (e.g. on each location update); it only hits the network every 15 min or after moving ~5 km.
    func update(for location: CLLocation?) {
        guard let location else { return }
        let moved = lastSpot.map { $0.distance(from: location) > 5_000 } ?? true
        guard moved || Date().timeIntervalSince(lastFetch) > 900 else { return }
        lastFetch = .now
        lastSpot = location
        Task { await fetch(location.coordinate) }
    }

    private func fetch(_ c: CLLocationCoordinate2D) async {
        let s = String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=weather_code,is_day,temperature_2m", c.latitude, c.longitude)
        guard let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.mirroredData(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let code = cur["weather_code"] as? Int else { lastFetch = .distantPast; return }
        isDay = (cur["is_day"] as? Int ?? 1) == 1
        temperature = cur["temperature_2m"] as? Double
        condition = WeatherCondition(wmo: code)
        GameRules.currentWeather = condition
    }
}

