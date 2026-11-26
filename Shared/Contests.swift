import Foundation

// MARK: - Pokémon Contests
//
// Blend berries from the Garden into Pokéblocks, feed them to raise a Pokémon's condition (Cool, Beauty, Cute,
// Smart, Tough — each Pokémon can only eat so many before its sheen is full), then enter a contest: an
// introduction judged on condition, then three appeals using its moves. Win to earn a ribbon and move up a
// rank: Normal → Super → Hyper → Master.

enum ContestCategory: String, CaseIterable, Codable, Identifiable {
    case cool, beauty, cute, smart, tough
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .cool: return "flame.fill"
        case .beauty: return "sparkles"
        case .cute: return "heart.fill"
        case .smart: return "lightbulb.fill"
        case .tough: return "shield.fill"
        }
    }
    var hex: UInt32 {
        switch self {
        case .cool: return 0xE8504A
        case .beauty: return 0x4A90E2
        case .cute: return 0xF48FB1
        case .smart: return 0x6CC24A
        case .tough: return 0xF5C542
        }
    }
    var blockName: String {
        switch self {
        case .cool: return "Red Pokéblock"
        case .beauty: return "Blue Pokéblock"
        case .cute: return "Pink Pokéblock"
        case .smart: return "Green Pokéblock"
        case .tough: return "Yellow Pokéblock"
        }
    }
    /// The berry that makes this colour of block.
    var berry: String {
        switch self {
        case .cool: return "pomeg-berry"
        case .beauty: return "kelpsy-berry"
        case .cute: return "qualot-berry"
        case .smart: return "hondew-berry"
        case .tough: return "grepa-berry"
        }
    }
    /// Contest category of a move, from its type.
    static func of(_ t: PokeType) -> ContestCategory {
        switch t {
        case .fire, .electric, .flying, .dragon: return .cool
        case .water, .ice, .fairy: return .beauty
        case .normal, .grass: return .cute
        case .psychic, .ghost, .dark, .bug, .poison: return .smart
        case .fighting, .rock, .ground, .steel: return .tough
        }
    }
    /// Gen 3 style: categories next to each other go together (Cool–Beauty–Cute–Smart–Tough–Cool).
    func hearts(for move: ContestCategory) -> Int {
        if move == self { return 3 }
        let all = Self.allCases
        let a = all.firstIndex(of: self)!, b = all.firstIndex(of: move)!
        return (abs(a - b) == 1 || abs(a - b) == 4) ? 2 : 1
    }
}

enum ContestRank: Int, CaseIterable, Codable, Identifiable {
    case normal, superRank, hyper, master
    var id: Int { rawValue }
    var name: String { ["Normal", "Super", "Hyper", "Master"][rawValue] }
    /// How good the rivals are.
    var rivalIntro: ClosedRange<Double> { [8...25, 18...35, 28...46, 38...56][rawValue] }
    var rivalHearts: ClosedRange<Int> { [1...3, 1...3, 2...4, 2...4][rawValue] }
    var prize: Int { [1_000, 3_000, 8_000, 20_000][rawValue] }
}

struct ContestRecord: Codable, Equatable, Hashable {
    var blocks: [String: Int] = [:]           // category → Pokéblocks owned ("rainbow" too)
    var conditions: [String: [Int]] = [:]     // Pokémon id → [cool, beauty, cute, smart, tough]
    var sheen: [String: Int] = [:]
    var ribbons: [String: [String]] = [:]     // Pokémon id → ["cool-0", …]
    var wins = 0
    var entered = 0
    var built = 0                             // Contest Hall projects finished
    var building: RanchBuild?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = (try? c.decodeIfPresent([String: Int].self, forKey: .blocks)) ?? [:]
        conditions = (try? c.decodeIfPresent([String: [Int]].self, forKey: .conditions)) ?? [:]
        sheen = (try? c.decodeIfPresent([String: Int].self, forKey: .sheen)) ?? [:]
        ribbons = (try? c.decodeIfPresent([String: [String]].self, forKey: .ribbons)) ?? [:]
        wins = (try? c.decodeIfPresent(Int.self, forKey: .wins)) ?? 0
        entered = (try? c.decodeIfPresent(Int.self, forKey: .entered)) ?? 0
        built = (try? c.decodeIfPresent(Int.self, forKey: .built)) ?? 0
        building = try? c.decodeIfPresent(RanchBuild.self, forKey: .building)
        // already entered contests before the hall had to be built: it's standing
        if built == 0 && entered > 0 { built = 1 }
    }

    func has(_ p: Int) -> Bool { built > p }
    var open: Bool { has(0) }
    var nextProject: RanchProject? { ContestRules.projects.first { $0.id == built } }

    func condition(_ id: UUID) -> [Int] { conditions[id.uuidString] ?? [0, 0, 0, 0, 0] }
    func ribbons(_ id: UUID) -> [String] { ribbons[id.uuidString] ?? [] }
    func hasRibbon(_ id: UUID, _ c: ContestCategory, _ r: ContestRank) -> Bool { ribbons(id).contains("\(c.rawValue)-\(r.rawValue)") }
    /// The highest rank this Pokémon may enter (one above its best ribbon).
    func unlockedRank(_ id: UUID, _ c: ContestCategory) -> ContestRank {
        var r = ContestRank.normal
        for rank in ContestRank.allCases where hasRibbon(id, c, rank) { r = ContestRank(rawValue: min(3, rank.rawValue + 1))! }
        return r
    }
}

enum ContestRules {
    static let maxSheen = 255
    static let blockSheen = 12           // about 21 Pokéblocks fill a Pokémon up
    static let blockBoost = 20
    static let rainbowBoost = 8

    /// 2 berries of one kind → a coloured block. One of each kind (5) → 2 Rainbow blocks.
    /// Built on the ranch, like the Daycare.
    static let projects: [RanchProject] = [
        .init(id: 0, name: "Contest Hall", symbol: "rosette", text: "A stage, seats and a Berry Blender.",
              cost: [.wood: 220, .stone: 120, .fibre: 120], money: 12_000, hours: 36, reward: "Pokéblocks & contests", ticket: nil),
        .init(id: 1, name: "Deluxe Blender", symbol: "tornado", text: "A faster blender that wastes nothing.",
              cost: [.stone: 200, .clay: 250], money: 25_000, hours: 48, reward: "Every blend makes an extra Pokéblock", ticket: nil),
        .init(id: 2, name: "Grand Stage", symbol: "sparkles", text: "Lights, curtains and a bigger crowd.",
              cost: [.wood: 400, .clay: 300, .fibre: 300], money: 50_000, hours: 96, reward: "Pokéblocks raise condition 50% more", ticket: nil),
    ]
    static func canStart(_ s: GameState) -> Bool { s.ranch.has(0) }

    static func blend(_ c: ContestCategory?, in s: inout GameState) -> Bool {
        guard s.contests.open else { return false }
        let extra = s.contests.has(1) ? 1 : 0
        if let c {
            guard (s.bag[c.berry] ?? 0) >= 2 else { return false }
            s.bag[c.berry, default: 0] -= 2
            if s.bag[c.berry] == 0 { s.bag[c.berry] = nil }
            s.contests.blocks[c.rawValue, default: 0] += 1 + extra
        } else {
            guard ContestCategory.allCases.allSatisfy({ (s.bag[$0.berry] ?? 0) >= 1 }) else { return false }
            for cat in ContestCategory.allCases {
                s.bag[cat.berry, default: 0] -= 1
                if s.bag[cat.berry] == 0 { s.bag[cat.berry] = nil }
            }
            s.contests.blocks["rainbow", default: 0] += 2 + extra
        }
        return true
    }

    static func feed(_ block: String, to id: UUID, in s: inout GameState) -> Bool {
        let key = id.uuidString
        guard (s.contests.blocks[block] ?? 0) > 0, (s.contests.sheen[key] ?? 0) < maxSheen else { return false }
        var cond = s.contests.condition(id)
        if let c = ContestCategory(rawValue: block), let i = ContestCategory.allCases.firstIndex(of: c) {
            cond[i] = min(255, cond[i] + blockBoost * (s.contests.has(2) ? 3 : 2) / 2)
        } else {
            let boost = rainbowBoost * (s.contests.has(2) ? 3 : 2) / 2
            cond = cond.map { min(255, $0 + boost) }
        }
        s.contests.conditions[key] = cond
        s.contests.sheen[key] = min(maxSheen, (s.contests.sheen[key] ?? 0) + blockSheen)
        s.contests.blocks[block, default: 0] -= 1
        if let i = s.index(of: id) { s.pokemon[i].friendship = min(255, s.pokemon[i].friendship + 2) }   // they love them
        return true
    }

    /// Introduction score (out of ~60): mostly the matching condition, a little friendship.
    static func intro(_ mon: OwnedPokemon, _ c: ContestCategory, in s: GameState) -> Double {
        let cond = s.contests.condition(mon.id)[ContestCategory.allCases.firstIndex(of: c)!]
        return Double(cond) / 255 * 50 + Double(mon.friendship) / 255 * 10
    }

    /// The prize for winning: Pokédollars, and the first Master rank win in each category gives a doll for the ranch house.
    static let masterPrizes: [ContestCategory: String] = [
        .cool: "charizard_doll", .beauty: "wailmer_doll", .cute: "pikachu_doll", .smart: "kecleon_doll", .tough: "rhydon_doll",
    ]
}
