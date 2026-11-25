import Foundation

// MARK: - The Ranch: a long-term project
//
// You start with a patch of overgrown grassland. Box Pokémon work shifts gathering materials (what they
// gather depends on their type, how much on their level, friendship and nature). Materials, Pokédollars and
// time build the ranch up one project at a time — clearing the land, a well, a fence, a barn, and finally a
// house you can furnish with Secret Base decorations. Big milestones hand out Hoenn's event tickets, each of
// which calls a legendary Pokémon.

enum RanchMaterial: String, Codable, CaseIterable, Identifiable {
    case wood, stone, clay, fibre
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .wood: return "tree.fill"
        case .stone: return "mountain.2.fill"
        case .clay: return "drop.fill"
        case .fibre: return "wind"
        }
    }
    var hex: UInt32 {
        switch self {
        case .wood: return 0xB8864B
        case .stone: return 0x9AA5B1
        case .clay: return 0xD9774B
        case .fibre: return 0xA8D86E
        }
    }
}

/// What a Pokémon does on the ranch (from its first type).
enum RanchJob: String, CaseIterable {
    case lumberjack, quarrier, potter, weaver, scavenger

    var name: String {
        switch self {
        case .lumberjack: return "Lumberjack"
        case .quarrier: return "Quarrier"
        case .potter: return "Potter"
        case .weaver: return "Weaver"
        case .scavenger: return "Scavenger"
        }
    }
    var symbol: String {
        switch self {
        case .lumberjack: return "tree.fill"
        case .quarrier: return "hammer.fill"
        case .potter: return "drop.fill"
        case .weaver: return "wind"
        case .scavenger: return "magnifyingglass"
        }
    }
    var material: RanchMaterial? {
        switch self {
        case .lumberjack: return .wood
        case .quarrier: return .stone
        case .potter: return .clay
        case .weaver: return .fibre
        case .scavenger: return nil
        }
    }
    var text: String {
        switch self {
        case .lumberjack: return "Gathers Wood"
        case .quarrier: return "Gathers Stone"
        case .potter: return "Gathers Clay"
        case .weaver: return "Gathers Fibre"
        case .scavenger: return "A bit of everything, and sometimes something rare"
        }
    }

    static func of(_ type: PokeType) -> RanchJob {
        switch type {
        case .grass, .bug, .fighting: return .lumberjack
        case .rock, .ground, .steel: return .quarrier
        case .water, .ice, .poison: return .potter
        case .normal, .flying, .fairy, .psychic: return .weaver
        case .fire, .electric, .dragon, .ghost, .dark: return .scavenger
        }
    }
}

/// A Pokémon's working attribute, from the stat its nature raises.
enum RanchAttribute: String, CaseIterable {
    case strong, sturdy, swift, clever, lucky, steady

    var name: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .strong: return "dumbbell.fill"
        case .sturdy: return "shield.fill"
        case .swift: return "hare.fill"
        case .clever: return "lightbulb.fill"
        case .lucky: return "sparkles"
        case .steady: return "equal.circle.fill"
        }
    }
    var text: String {
        switch self {
        case .strong: return "+25% materials"
        case .sturdy: return "Double friendship from work"
        case .swift: return "Shifts 30 min shorter (up to 2h)"
        case .clever: return "15% chance of a bonus material each shift"
        case .lucky: return "Better odds of rare finds"
        case .steady: return "+10% materials"
        }
    }

    /// Natures in order: every 5 raise Attack, Defence, Speed, Sp. Atk, Sp. Def; Hardy/Docile/Serious/Bashful/Quirky raise nothing.
    static func of(nature: String) -> RanchAttribute {
        guard let i = Dex.natures.firstIndex(of: nature) else { return .steady }
        if i / 5 == i % 5 { return .steady }
        return [.strong, .sturdy, .swift, .clever, .lucky][i / 5]
    }
}

/// One step of building up the ranch.
struct RanchProject: Identifiable {
    let id: Int
    let name: String
    let symbol: String
    let text: String
    let cost: [RanchMaterial: Int]
    let money: Int
    let hours: Double
    let reward: String
    let ticket: String?       // event ticket handed out on completion

    static let all: [RanchProject] = [
        .init(id: 0, name: "Clear the Land", symbol: "leaf.fill", text: "Cut back the tall grass so there's room to work.",
              cost: [.wood: 30, .fibre: 30], money: 0, hours: 12, reward: "+5% materials", ticket: nil),
        .init(id: 1, name: "Dig a Well", symbol: "drop.circle.fill", text: "Fresh water for thirsty workers.",
              cost: [.stone: 90, .clay: 60], money: 3_000, hours: 24, reward: "Shifts take 7h instead of 8h", ticket: nil),
        .init(id: 2, name: "Fence & Gate", symbol: "square.dashed", text: "A proper picket fence with a gate.",
              cost: [.wood: 160, .stone: 70], money: 6_000, hours: 36, reward: "A 4th rancher", ticket: nil),
        .init(id: 3, name: "Barn", symbol: "house.lodge.fill", text: "Somewhere for your Pokémon to rest between shifts.",
              cost: [.wood: 260, .stone: 150, .fibre: 90], money: 12_000, hours: 48,
              reward: "A 5th rancher · +10% materials", ticket: "old-sea-map"),
        .init(id: 4, name: "Foundations", symbol: "square.stack.3d.down.right.fill", text: "Level the ground and lay stone for a house.",
              cost: [.stone: 420, .clay: 220], money: 20_000, hours: 72, reward: "Ready for a frame", ticket: nil),
        .init(id: 5, name: "House Frame", symbol: "house", text: "Timber walls go up.",
              cost: [.wood: 520, .fibre: 220], money: 30_000, hours: 96, reward: "Ready for walls and a roof", ticket: nil),
        .init(id: 6, name: "Walls & Roof", symbol: "house.fill", text: "Finish the house — then make it yours.",
              cost: [.clay: 520, .stone: 320, .wood: 320], money: 50_000, hours: 120,
              reward: "Your house · the furniture shop opens", ticket: "eon-ticket"),
        .init(id: 7, name: "Workshop", symbol: "hammer.circle.fill", text: "Better tools for everyone.",
              cost: [.wood: 420, .stone: 320, .fibre: 320], money: 40_000, hours: 96,
              reward: "Shifts take 6h · new room styles", ticket: nil),
        .init(id: 8, name: "Pond", symbol: "water.waves", text: "A pond for Water types to splash in.",
              cost: [.stone: 650, .clay: 650], money: 60_000, hours: 120, reward: "A 6th rancher · +10% materials",
              ticket: "aurora-ticket"),
        .init(id: 9, name: "Grand Extension", symbol: "building.2.fill", text: "Knock through and double the house.",
              cost: [.wood: 1_000, .stone: 800, .clay: 800, .fibre: 650], money: 120_000, hours: 168,
              reward: "A much bigger room · a 7th rancher", ticket: "mystic-ticket"),
    ]
}

struct RanchBuild: Codable, Equatable, Hashable {
    var project: Int
    var startedAt: Date
    var endsAt: Date
}

/// A decoration placed in the house (top-left tile).
struct PlacedDecor: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var key: String
    var x: Int
    var y: Int
}

struct Ranch: Codable, Equatable, Hashable {
    var built = 0                       // projects finished (RanchProject.all[0..<built])
    var building: RanchBuild?
    var materials: [String: Int] = [:]
    var ranchers: [UUID] = []
    var shiftStart: Date?
    var shiftEnd: Date?
    var shiftCount = 0
    var decor: [String: Int] = [:]      // owned, not placed
    var placed: [PlacedDecor] = []
    var style = "tree"                  // room style (Secret Base tileset)
    var styles: [String] = ["tree"]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        built = (try? c.decodeIfPresent(Int.self, forKey: .built)) ?? 0
        building = try? c.decodeIfPresent(RanchBuild.self, forKey: .building)
        materials = (try? c.decodeIfPresent([String: Int].self, forKey: .materials)) ?? [:]
        ranchers = (try? c.decodeIfPresent([UUID].self, forKey: .ranchers)) ?? []
        shiftStart = try? c.decodeIfPresent(Date.self, forKey: .shiftStart)
        shiftEnd = try? c.decodeIfPresent(Date.self, forKey: .shiftEnd)
        shiftCount = (try? c.decodeIfPresent(Int.self, forKey: .shiftCount)) ?? 0
        decor = (try? c.decodeIfPresent([String: Int].self, forKey: .decor)) ?? [:]
        placed = (try? c.decodeIfPresent([PlacedDecor].self, forKey: .placed)) ?? []
        style = (try? c.decodeIfPresent(String.self, forKey: .style)) ?? "tree"
        styles = (try? c.decodeIfPresent([String].self, forKey: .styles)) ?? ["tree"]
    }

    func has(_ project: Int) -> Bool { built > project }
    var houseBuilt: Bool { has(6) }
    /// Ranchers you can send: 3 to start, more as the ranch grows (up to 7).
    var slots: Int { 3 + (has(2) ? 1 : 0) + (has(3) ? 1 : 0) + (has(8) ? 1 : 0) + (has(9) ? 1 : 0) }
    var shiftHours: Double { has(7) ? 6 : has(1) ? 7 : 8 }
    var materialBonus: Double { (has(0) ? 0.05 : 0) + (has(3) ? 0.1 : 0) + (has(8) ? 0.1 : 0) }
    func amount(_ m: RanchMaterial) -> Int { materials[m.rawValue] ?? 0 }
    var nextProject: RanchProject? { RanchProject.all.first { $0.id == built } }
    /// House room size in metatiles (walls included).
    var roomSize: (w: Int, h: Int) { has(9) ? (16, 11) : (12, 9) }
}

// MARK: - Rules

/// Team bonuses: several Pokémon with the same job work better together, and a varied crew helps everyone.
struct RanchTeam: Equatable {
    var jobs: [RanchJob: Int] = [:]
    var distinct = 0

    static let tiers = [2, 3, 4]
    func tier(_ j: RanchJob) -> Int { (j == .scavenger ? [2, 3] : Self.tiers).filter { (jobs[j] ?? 0) >= $0 }.count }
    var varietyTier: Int { distinct >= 5 ? 2 : distinct >= 4 ? 1 : 0 }

    /// Extra share of a material from same-job teamwork, plus the variety bonus.
    func materialBonus(_ m: RanchMaterial) -> Double {
        let job = RanchJob.allCases.first { $0.material == m }!
        return [0, 0.15, 0.30, 0.50][tier(job)] + [0, 0.10, 0.20][varietyTier]
    }
    var rareMultiplier: Double { [1, 2, 3][tier(.scavenger)] }
    var moneyBonus: Double { [0, 0.25, 0.5][tier(.scavenger)] + [0, 0.10, 0.20][varietyTier] }

    static func of(_ workers: [OwnedPokemon]) -> RanchTeam {
        var t = RanchTeam()
        for m in workers { t.jobs[RanchJob.of(m.species.types[0]), default: 0] += 1 }
        t.distinct = t.jobs.count
        return t
    }

    static func tierText(_ j: RanchJob) -> [String] {
        if j == .scavenger { return ["Rare finds twice as likely, +25% ₽", "Three times as likely, +50% ₽"] }
        let m = j.material!.name
        return ["+15% \(m)", "+30% \(m)", "+50% \(m)"]
    }
    static let varietyText = ["4 different jobs: +10% of everything", "All 5 jobs: +20% of everything"]
}

enum RanchRules {
    struct Haul: Equatable {
        var materials: [RanchMaterial: Int] = [:]
        var money = 0
        var ticket: String?
        var friendship = 0
    }

    /// What one Pokémon brings back from a shift (on average — `random` adds the luck).
    static func haul(for mon: OwnedPokemon, ranch: Ranch, team: RanchTeam = RanchTeam(), random: Bool = true) -> Haul {
        var h = Haul()
        let job = RanchJob.of(mon.species.types[0])
        let attr = RanchAttribute.of(nature: mon.nature)
        var amount = 4.0 * (1 + Double(mon.level) / 40) * (1 + Double(mon.friendship) / 400)
        amount *= 1 + ranch.materialBonus + (attr == .strong ? 0.25 : attr == .steady ? 0.10 : 0)
        let roll = random ? Double.random(in: 0.8...1.2) : 1
        if let m = job.material {
            h.materials[m] = Int((amount * roll * (1 + team.materialBonus(m))).rounded())
        } else {
            // Scavengers: a little of each, some Pokédollars, and the odd rare find
            for m in RanchMaterial.allCases {
                h.materials[m] = Int((amount * 0.35 * roll * (1 + [0, 0.10, 0.20][team.varietyTier])).rounded())
            }
            h.money = Int((amount * 40 * roll * (1 + team.moneyBonus)).rounded())
        }
        if attr == .clever && (!random || Double.random(in: 0..<1) < 0.15),
           let bonus = RanchMaterial.allCases.filter({ $0 != job.material }).randomElement() {
            h.materials[bonus, default: 0] += max(2, Int(amount / 2))
        }
        // Very rare: an event ticket turns up (scavengers and lucky Pokémon find them more)
        if random {
            var chance = 0.002 * team.rareMultiplier
            if job == .scavenger { chance *= 2 }
            if attr == .lucky { chance *= 2 }
            if Double.random(in: 0..<1) < chance { h.ticket = RanchTickets.all.randomElement()!.key }
        }
        h.friendship = attr == .sturdy ? 6 : 3
        return h
    }

    static func shiftHours(ranch: Ranch, workers: [OwnedPokemon]) -> Double {
        let swift = workers.filter { RanchAttribute.of(nature: $0.nature) == .swift }.count
        return max(ranch.shiftHours - 2, ranch.shiftHours - 0.5 * Double(swift))
    }
}

// MARK: - Event tickets → legendary encounters

struct RanchTicket {
    let key: String
    let name: String
    let species: [Int]
    let text: String
}

enum RanchTickets {
    static let all: [RanchTicket] = [
        .init(key: "old-sea-map", name: "Old Sea Map", species: [151],
              text: "A faded map to a faraway island. Use it and something mythical appears."),
        .init(key: "eon-ticket", name: "Eon Ticket", species: [380, 381],
              text: "A ticket to the Southern Island. Use it to meet Latias or Latios."),
        .init(key: "aurora-ticket", name: "Aurora Ticket", species: [386],
              text: "A ticket to Birth Island. Use it to meet Deoxys."),
        .init(key: "mystic-ticket", name: "Mystic Ticket", species: [249, 250],
              text: "A ticket to Navel Rock. Use it to meet Lugia or Ho-Oh."),
    ]
    static func ticket(_ key: String) -> RanchTicket? { all.first { $0.key == key } }
    static func isTicket(_ key: String) -> Bool { ticket(key) != nil }
}
