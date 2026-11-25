import Foundation

// MARK: - Seasons and swarms
//
// Each season (UK months) brings out certain types more often. Every week a swarm of one species gathers:
// for that week it makes up a big share of wild Pokémon — a rare chance to catch something you've been missing.

enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    static func at(_ date: Date = .now) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    var name: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .spring: return "camera.macro"
        case .summer: return "sun.max.fill"
        case .autumn: return "leaf.fill"
        case .winter: return "snowflake"
        }
    }
    var hex: UInt32 {
        switch self {
        case .spring: return 0xF4A6C8
        case .summer: return 0xF5C542
        case .autumn: return 0xE07A3C
        case .winter: return 0x9FD4F5
        }
    }
    /// Types that appear more often this season.
    var types: [PokeType] {
        switch self {
        case .spring: return [.grass, .bug, .fairy, .flying]
        case .summer: return [.fire, .water, .electric, .ground]
        case .autumn: return [.ghost, .dark, .normal, .poison]
        case .winter: return [.ice, .steel, .psychic, .dragon]
        }
    }
    static let boost = 1.6
}

enum Swarm {
    /// Share of wild Pokémon that are the swarm species during its week.
    static let share = 0.2

    /// Monday-based week number since 2024 (the swarm changes every Monday).
    static func week(_ date: Date = .now) -> Int {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let start = cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        return max(0, cal.dateComponents([.weekOfYear], from: start, to: date).weekOfYear ?? 0)
    }

    /// This week's swarm: a non-legendary species from Gens 1–4 that fits the season, picked the same way for everyone.
    static func species(_ date: Date = .now) -> Species {
        let season = Season.at(date)
        let pool = Dex.all.filter {
            !$0.isLegendary && !$0.isMythical && !$0.isBaby && $0.generation <= 4 && $0.evolvesFrom == nil
                && $0.types.contains(where: season.types.contains)
        }
        guard !pool.isEmpty else { return Dex.species(25) }
        var x = UInt64(week(date)) &* 2_654_435_761 &+ 97
        x ^= x >> 13
        return pool[Int(x % UInt64(pool.count))]
    }

    /// When this week's swarm ends (next Monday).
    static func ends(_ date: Date = .now) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: date)?.end ?? date.addingTimeInterval(7 * 86_400)
        return startOfWeek
    }
}
