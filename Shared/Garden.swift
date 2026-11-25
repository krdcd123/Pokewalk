import Foundation

// MARK: - The Berry Garden (like the Berry Master's garden on Route 123)

/// One patch of soft soil.
struct GardenPlot: Codable, Equatable, Identifiable, Hashable {
    var id: Int
    var berry: String?          // item key, e.g. "pomeg-berry"
    var plantedAt: Date?
}

struct Garden: Codable, Equatable, Hashable {
    var plots: [GardenPlot] = (0..<Garden.basePlots).map { GardenPlot(id: $0) }
    var workers: [UUID] = []            // box Pokémon working in the garden
    var lastGiftDay = ""                // the Aroma Lady's daily berry
    var harvests = 0                    // lifetime harvests (just for fun)

    static let basePlots = 8
    static let maxPlots = 12
    static let maxWorkers = 6
    static let growHours: Double = 24

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Garden()
        plots = c.value(.plots, d.plots)
        workers = c.value(.workers, [])
        lastGiftDay = c.value(.lastGiftDay, "")
        harvests = c.value(.harvests, 0)
    }
}

/// Growth stage of a plot, matching Emerald's berry tree sprites.
enum BerryStage: Int, Comparable {
    case planted, sprout, taller, flowering, berries
    static func < (a: BerryStage, b: BerryStage) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .planted: return "Planted"
        case .sprout: return "Sprouted"
        case .taller: return "Growing taller"
        case .flowering: return "Flowering"
        case .berries: return "Ready to pick!"
        }
    }

    static func at(progress p: Double) -> BerryStage {
        switch p {
        case ..<0.12: return .planted
        case ..<0.35: return .sprout
        case ..<0.62: return .taller
        case ..<1: return .flowering
        default: return .berries
        }
    }
}

// MARK: - Worker traits (team synergies, like TFT)

/// Every working Pokémon brings the trait(s) of its type(s). Enough of one trait working together unlocks a
/// bonus; more unlocks a bigger one. Pokémon from the same evolution family also work better together.
enum GardenTrait: String, CaseIterable, Identifiable, Codable {
    case greenThumb, rainmakers, tillers, sunshine, pollinators, helpers
    var id: String { rawValue }

    var name: String {
        switch self {
        case .greenThumb: return "Green Thumb"
        case .rainmakers: return "Rainmakers"
        case .tillers: return "Tillers"
        case .sunshine: return "Sunshine"
        case .pollinators: return "Pollinators"
        case .helpers: return "Helping Hand"
        }
    }

    var symbol: String {
        switch self {
        case .greenThumb: return "leaf.fill"
        case .rainmakers: return "cloud.rain.fill"
        case .tillers: return "square.grid.3x2.fill"
        case .sunshine: return "sun.max.fill"
        case .pollinators: return "ladybug.fill"
        case .helpers: return "heart.fill"
        }
    }

    var hex: UInt32 {
        switch self {
        case .greenThumb: return 0x6CC24A
        case .rainmakers: return 0x4A90E2
        case .tillers: return 0xB8864B
        case .sunshine: return 0xF5A623
        case .pollinators: return 0xE86FB0
        case .helpers: return 0xE0E0E0
        }
    }

    var types: [PokeType] {
        switch self {
        case .greenThumb: return [.grass, .bug]
        case .rainmakers: return [.water, .ice]
        case .tillers: return [.ground, .rock, .steel, .fighting]
        case .sunshine: return [.fire, .electric, .dragon]
        case .pollinators: return [.flying, .fairy, .psychic]
        case .helpers: return [.normal, .dark, .ghost, .poison]
        }
    }

    /// Workers needed for each level of the bonus.
    var tiers: [Int] {
        switch self {
        case .tillers: return [2, 4]
        case .helpers: return [2, 4]
        default: return [2, 4, 6]
        }
    }

    /// What each tier does.
    var tierText: [String] {
        switch self {
        case .greenThumb: return ["Berries grow 15% faster", "35% faster", "60% faster"]
        case .rainmakers: return ["50% chance of +1 berry", "+1 berry every harvest", "+2 berries every harvest"]
        case .tillers: return ["+2 patches of soil", "+4 patches of soil"]
        case .sunshine: return ["Berries grow 10% faster", "25% faster", "40% faster"]
        case .pollinators: return ["20% chance of a bonus different berry", "40% chance", "70% chance"]
        case .helpers: return ["Workers gain double friendship", "…and 50% chance to replant for free"]
        }
    }

    static func of(_ type: PokeType) -> GardenTrait { allCases.first { $0.types.contains(type) }! }
}

struct GardenBonuses: Equatable {
    var counts: [GardenTrait: Int] = [:]
    var families: [Int] = []           // base species of families with 2+ workers
    var growthSpeed: Double = 1        // multiplies how fast berries grow
    var extraBerryChance: Double = 0   // Rainmakers tier 1
    var extraBerries = 0               // Rainmakers tier 2–3
    var plots = Garden.basePlots
    var bonusBerryChance: Double = 0   // Pollinators
    var friendshipPerHarvest = 3
    var replantChance: Double = 0

    func tier(_ t: GardenTrait) -> Int { t.tiers.filter { (counts[t] ?? 0) >= $0 }.count }
}

enum GardenRules {
    /// Base species of an evolution family (Pichu, Pikachu and Raichu all → Pichu).
    static func familyRoot(_ speciesID: Int) -> Int {
        var id = speciesID, hops = 0
        while let from = Dex.species(id).evolvesFrom, hops < 5 { id = from; hops += 1 }
        return id
    }

    static func bonuses(workers: [OwnedPokemon]) -> GardenBonuses {
        var b = GardenBonuses()
        for mon in workers {
            for t in Set(mon.species.types.map(GardenTrait.of)) { b.counts[t, default: 0] += 1 }
        }
        var roots: [Int: Int] = [:]
        for mon in workers { roots[familyRoot(mon.speciesID), default: 0] += 1 }
        b.families = roots.filter { $0.value >= 2 }.map(\.key).sorted()

        let green = [0, 0.15, 0.35, 0.60][b.tier(.greenThumb)]
        let sun = [0, 0.10, 0.25, 0.40][b.tier(.sunshine)]
        let family = min(0.3, Double(b.families.count) * 0.10)
        b.growthSpeed = 1 + green + sun + family
        switch b.tier(.rainmakers) {
        case 1: b.extraBerryChance = 0.5
        case 2: b.extraBerries = 1
        case 3: b.extraBerries = 2
        default: break
        }
        b.plots = Garden.basePlots + [0, 2, 4][b.tier(.tillers)]
        b.bonusBerryChance = [0, 0.2, 0.4, 0.7][b.tier(.pollinators)]
        let h = b.tier(.helpers)
        b.friendshipPerHarvest = h >= 1 ? 6 : 3
        b.replantChance = h >= 2 ? 0.5 : 0
        // Families: each worker also gets +1 friendship per harvest for every family pair
        b.friendshipPerHarvest += b.families.count
        return b
    }

    static func hoursToGrow(_ b: GardenBonuses) -> Double { Garden.growHours / b.growthSpeed }

    static func progress(_ plot: GardenPlot, bonuses b: GardenBonuses, now: Date = .now) -> Double {
        guard let t = plot.plantedAt, plot.berry != nil else { return 0 }
        return now.timeIntervalSince(t) / (hoursToGrow(b) * 3600)
    }

    static func readyAt(_ plot: GardenPlot, bonuses b: GardenBonuses) -> Date? {
        guard let t = plot.plantedAt, plot.berry != nil else { return nil }
        return t.addingTimeInterval(hoursToGrow(b) * 3600)
    }

    /// 1–3 berries, plus the Rainmakers' extras.
    static func yield(_ b: GardenBonuses) -> Int {
        var n = Int.random(in: 1...3) + b.extraBerries
        if Double.random(in: 0..<1) < b.extraBerryChance { n += 1 }
        return n
    }
}
