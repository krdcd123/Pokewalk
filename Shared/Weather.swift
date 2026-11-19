import Foundation

enum WeatherCondition: String, Codable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunder

    /// WMO weather codes.
    init(wmo code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunder
        default: self = .cloudy
        }
    }

    var name: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Foggy"
        case .drizzle: return "Drizzle"
        case .rain: return "Raining"
        case .snow: return "Snowing"
        case .thunder: return "Thunderstorm"
        }
    }

    /// Types that are a little more likely to appear in this weather (like the games' weather boosts).
    var boostedTypes: Set<PokeType> {
        switch self {
        case .clear: return [.fire, .grass, .ground]
        case .partlyCloudy: return [.normal, .flying]
        case .cloudy: return [.fighting, .poison]
        case .fog: return [.ghost, .psychic, .dark]
        case .drizzle, .rain: return [.water, .bug, .electric]
        case .snow: return [.ice, .steel]
        case .thunder: return [.electric, .water, .dragon]
        }
    }
}
