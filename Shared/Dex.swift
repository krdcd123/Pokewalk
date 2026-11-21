import Foundation

// MARK: - Basic enums

enum PokeType: String, Codable, CaseIterable {
    case normal, fire, water, grass, electric, ice, fighting, poison, ground
    case flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy

    var displayName: String { rawValue.capitalized }

    var hex: UInt32 {
        switch self {
        case .normal: return 0xA8A77A
        case .fire: return 0xEE8130
        case .water: return 0x6390F0
        case .grass: return 0x7AC74C
        case .electric: return 0xF7D02C
        case .ice: return 0x96D9D6
        case .fighting: return 0xC22E28
        case .poison: return 0xA33EA1
        case .ground: return 0xE2BF65
        case .flying: return 0xA98FF3
        case .psychic: return 0xF95587
        case .bug: return 0xA6B91A
        case .rock: return 0xB6A136
        case .ghost: return 0x735797
        case .dragon: return 0x6F35FC
        case .dark: return 0x705746
        case .steel: return 0xB7B7CE
        case .fairy: return 0xD685AD
        }
    }
}

enum Habitat: String, Codable, CaseIterable {
    case cave, forest, grassland, mountain, rare, roughTerrain, sea, urban, watersEdge

    var displayName: String {
        switch self {
        case .roughTerrain: return "Rough terrain"
        case .watersEdge: return "Water's edge"
        default: return rawValue.capitalized
        }
    }
}

enum Gender: String, Codable {
    case male, female, genderless
    var symbol: String { self == .male ? "♂" : self == .female ? "♀" : "" }
}

enum TimeOfDay: String, Codable {
    case day, night
    static func at(_ date: Date) -> TimeOfDay {
        let h = Calendar.current.component(.hour, from: date)
        return (6..<20).contains(h) ? .day : .night
    }
}

// MARK: - Growth rates (real Gen 3+ formulas)

enum GrowthRate: String, Codable {
    case slow, mediumFast, fast, mediumSlow, erratic, fluctuating

    static let maxLevel = 100

    private static var tables: [GrowthRate: [Int]] = {
        var t: [GrowthRate: [Int]] = [:]
        for g in [GrowthRate.slow, .mediumFast, .fast, .mediumSlow, .erratic, .fluctuating] {
            t[g] = (0...maxLevel).map { g.formula($0) }
        }
        return t
    }()

    private func formula(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        let n3 = n * n * n
        switch self {
        case .fast: return 4 * n3 / 5
        case .mediumFast: return n3
        case .mediumSlow: return max(0, 6 * n3 / 5 - 15 * n * n + 100 * n - 140)
        case .slow: return 5 * n3 / 4
        case .erratic:
            if n < 50 { return n3 * (100 - n) / 50 }
            if n < 68 { return n3 * (150 - n) / 100 }
            if n < 98 { return n3 * ((1911 - 10 * n) / 3) / 500 }
            return n3 * (160 - n) / 100
        case .fluctuating:
            if n < 15 { return n3 * ((n + 1) / 3 + 24) / 50 }
            if n < 36 { return n3 * (n + 14) / 50 }
            return n3 * (n / 2 + 32) / 50
        }
    }

    func exp(forLevel level: Int) -> Int {
        GrowthRate.tables[self]![max(0, min(level, GrowthRate.maxLevel))]
    }

    var maxExp: Int { exp(forLevel: GrowthRate.maxLevel) }

    func level(forExp exp: Int) -> Int {
        let table = GrowthRate.tables[self]!
        var lo = 1, hi = GrowthRate.maxLevel
        while lo < hi {               // highest level whose threshold <= exp
            let mid = (lo + hi + 1) / 2
            if table[mid] <= exp { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func progress(exp: Int) -> Double {
        let l = level(forExp: exp)
        guard l < GrowthRate.maxLevel else { return 1 }
        let lo = self.exp(forLevel: l), hi = self.exp(forLevel: l + 1)
        return hi > lo ? Double(exp - lo) / Double(hi - lo) : 1
    }

    func expToNext(exp: Int) -> Int {
        let l = level(forExp: exp)
        return l < GrowthRate.maxLevel ? self.exp(forLevel: l + 1) - exp : 0
    }
}

// MARK: - Species data (generated from PokeAPI's open data: Shared/Resources/dex.json)

struct EvolutionRule: Codable, Hashable {
    enum Kind: String, Codable { case level, item, friendship }
    let kind: Kind
    let into: Int
    var level: Int?
    var item: String?
    var value: Int?         // friendship threshold
    var time: TimeOfDay?
    var gender: Gender?

    var summary: String { summary(revealName: true) }

    /// `revealName: false` hides which Pokémon it becomes ("???") — until you've caught it.
    func summary(revealName: Bool) -> String {
        let name = revealName ? Dex.species(into).name : "???"
        var s: String
        switch kind {
        case .level: s = "\(name) at Lv. \(level ?? 0)"
        case .item: s = "\(name) with \(Dex.itemName(item ?? ""))"
        case .friendship: s = "\(name) with high friendship"
        }
        if let time { s += time == .day ? " (day)" : " (night)" }
        if let gender, gender != .genderless { s += " (\(gender.symbol))" }
        return s
    }
}

struct Species: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let key: String                 // e.g. "mr-mime"
    let types: [PokeType]
    let evolvesFrom: Int?
    let evolutions: [EvolutionRule]
    let captureRate: Int
    let baseFriendship: Int
    let genderRate: Int             // -1 genderless, else chance of female in eighths
    let growth: GrowthRate
    let isBaby: Bool
    let isLegendary: Bool
    let isMythical: Bool
    let habitats: [Habitat]
    let generation: Int

    var primaryType: PokeType { types[0] }
    var dexNumber: String { String(format: "No. %03d", id) }

    /// The level-up requirement of whatever evolves into this species (used to keep wild levels sensible).
    var minimumWildLevel: Int {
        guard let from = evolvesFrom,
              let rule = Dex.species(from).evolutions.first(where: { $0.into == id }),
              rule.kind == .level, let l = rule.level else { return 1 }
        return l
    }
}

struct ItemInfo: Codable, Hashable {
    let key: String
    let name: String
}

private struct DexFile: Codable {
    let species: [Species]
    let items: [ItemInfo]
}

enum Dex {
    /// Tests can point this at a dex.json on disk before first use.
    static var overrideURL: URL?

    private static let file: DexFile = {
        let url = overrideURL
            ?? Bundle.main.url(forResource: "dex", withExtension: "json")
            ?? Bundle.allBundles.lazy.compactMap { $0.url(forResource: "dex", withExtension: "json") }.first
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DexFile.self, from: data) else {
            fatalError("dex.json missing from the app bundle — check that Shared/Resources is in the target.")
        }
        return decoded
    }()

    static var all: [Species] { file.species }
    static var count: Int { file.species.count }
    static func species(_ id: Int) -> Species { file.species[max(1, min(id, count)) - 1] }

    private static let itemNames: [String: String] = Dictionary(uniqueKeysWithValues: file.items.map { ($0.key, $0.name) })
    static var items: [ItemInfo] { file.items }
    private static let extraNames: [String: String] = [
        "linking-cord": "Link Cable",
        "exp-candy-xs": "Exp. Candy XS", "exp-candy-s": "Exp. Candy S", "exp-candy-m": "Exp. Candy M",
        "exp-candy-l": "Exp. Candy L", "exp-candy-xl": "Exp. Candy XL",
    ]

    static func itemName(_ key: String) -> String {
        if let n = extraNames[key] { return n }
        if let b = BallKind.allCases.first(where: { $0.itemKey == key }) { return b.name }
        return itemNames[key] ?? key.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    static let starterChoices: [Int] = [1, 4, 7, 152, 155, 158, 252, 255, 258, 25, 133]

    static let natures = ["Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish",
                          "Lax", "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet",
                          "Bashful", "Rash", "Calm", "Gentle", "Sassy", "Careful", "Quirky"]
}
