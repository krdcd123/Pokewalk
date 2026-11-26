import Foundation

// MARK: - Battles (Battle Frontier)
//
// Gen 3 battles: the engine is in BattleEngine.swift (real Emerald moves, learnsets and effects).

enum TypeChart {
    private static let se: [PokeType: [PokeType]] = [
        .fire: [.grass, .ice, .bug, .steel], .water: [.fire, .ground, .rock], .grass: [.water, .ground, .rock],
        .electric: [.water, .flying], .ice: [.grass, .ground, .flying, .dragon],
        .fighting: [.normal, .ice, .rock, .dark, .steel], .poison: [.grass, .fairy], .ground: [.fire, .electric, .poison, .rock, .steel],
        .flying: [.grass, .fighting, .bug], .psychic: [.fighting, .poison], .bug: [.grass, .psychic, .dark],
        .rock: [.fire, .ice, .flying, .bug], .ghost: [.psychic, .ghost], .dragon: [.dragon], .dark: [.psychic, .ghost],
        .steel: [.ice, .rock, .fairy], .fairy: [.fighting, .dragon, .dark],
    ]
    private static let nve: [PokeType: [PokeType]] = [
        .normal: [.rock, .steel], .fire: [.fire, .water, .rock, .dragon], .water: [.water, .grass, .dragon],
        .grass: [.fire, .grass, .poison, .flying, .bug, .dragon, .steel], .electric: [.electric, .grass, .dragon],
        .ice: [.fire, .water, .ice, .steel], .fighting: [.poison, .flying, .psychic, .bug, .fairy],
        .poison: [.poison, .ground, .rock, .ghost], .ground: [.grass, .bug], .flying: [.electric, .rock, .steel],
        .psychic: [.psychic, .steel], .bug: [.fire, .fighting, .poison, .flying, .ghost, .steel, .fairy],
        .rock: [.fighting, .ground, .steel], .ghost: [.dark, .steel], .dragon: [.steel], .dark: [.fighting, .dark, .fairy, .steel],
        .steel: [.fire, .water, .electric, .steel], .fairy: [.fire, .poison, .steel],
    ]
    private static let immune: [PokeType: [PokeType]] = [
        .normal: [.ghost], .electric: [.ground], .fighting: [.ghost], .poison: [.steel], .ground: [.flying],
        .psychic: [.dark], .ghost: [.normal], .dragon: [.fairy],
    ]

    static func multiplier(_ move: PokeType, against types: [PokeType]) -> Double {
        types.reduce(1.0) { m, t in
            if immune[move]?.contains(t) == true { return 0 }
            if se[move]?.contains(t) == true { return m * 2 }
            if nve[move]?.contains(t) == true { return m * 0.5 }
            return m
        }
    }
}

// MARK: - The Battle Frontier

struct Frontier: Codable, Equatable, Hashable {
    var day = ""                      // day key of today's run
    var won = 0                       // battles won today (0–5)
    var lost = false                  // lost today: come back tomorrow
    var week = 0                      // Monday-based week of the gym leaders beaten below
    var leadersBeaten: [String] = []  // this week
    var badges: [String] = []         // every leader ever beaten
    var symbols: [String] = []        // Champion / Frontier Brains beaten
    var totalWins = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
        won = (try? c.decodeIfPresent(Int.self, forKey: .won)) ?? 0
        lost = (try? c.decodeIfPresent(Bool.self, forKey: .lost)) ?? false
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? 0
        leadersBeaten = (try? c.decodeIfPresent([String].self, forKey: .leadersBeaten)) ?? []
        badges = (try? c.decodeIfPresent([String].self, forKey: .badges)) ?? []
        symbols = (try? c.decodeIfPresent([String].self, forKey: .symbols)) ?? []
        totalWins = (try? c.decodeIfPresent(Int.self, forKey: .totalWins)) ?? 0
    }
}

struct FrontierTrainer {
    let name: String
    let title: String
    let pic: String                    // pret trainer front pic file name
    let team: [BattleMon]
    let isLeader: Bool
    let isChampion: Bool
    let badge: String?
    let intro: String
}

enum FrontierRules {
    struct Leader { let key: String; let name: String; let badge: String; let type: PokeType; let team: [Int] }

    /// Monday → Saturday.
    static let leaders: [Leader] = [
        .init(key: "roxanne", name: "Roxanne", badge: "Stone Badge", type: .rock, team: [74, 299, 95, 345, 347]),
        .init(key: "brawly", name: "Brawly", badge: "Knuckle Badge", type: .fighting, team: [66, 296, 307, 56, 214]),
        .init(key: "wattson", name: "Wattson", badge: "Dynamo Badge", type: .electric, team: [81, 309, 100, 25, 311]),
        .init(key: "flannery", name: "Flannery", badge: "Heat Badge", type: .fire, team: [218, 322, 324, 58, 77]),
        .init(key: "norman", name: "Norman", badge: "Balance Badge", type: .normal, team: [287, 327, 263, 300, 241]),
        .init(key: "winona", name: "Winona", badge: "Feather Badge", type: .flying, team: [333, 276, 278, 227, 357]),
    ]
    /// Sunday if all six weren't beaten this week.
    static let sundayLeader = Leader(key: "tate_and_liza", name: "Tate & Liza", badge: "Mind Badge", type: .psychic,
                                     team: [337, 338, 343, 177, 280])

    struct Brain { let key: String; let name: String; let title: String; let pic: String; let team: [Int] }
    static let champion = Brain(key: "wallace", name: "Wallace", title: "Champion", pic: "champion_wallace",
                                team: [321, 73, 272, 340, 130, 350])
    static let brains: [Brain] = [
        .init(key: "anabel", name: "Anabel", title: "Salon Maiden", pic: "salon_maiden_anabel", team: [65, 244, 143]),
        .init(key: "tucker", name: "Tucker", title: "Dome Ace", pic: "dome_ace_tucker", team: [260, 373, 6]),
        .init(key: "spenser", name: "Spenser", title: "Palace Maven", pic: "palace_maven_spenser", team: [275, 169, 289]),
        .init(key: "greta", name: "Greta", title: "Arena Tycoon", pic: "arena_tycoon_greta", team: [214, 197, 248]),
        .init(key: "noland", name: "Noland", title: "Factory Head", pic: "factory_head_noland", team: [376, 230, 59]),
        .init(key: "lucy", name: "Lucy", title: "Pike Queen", pic: "pike_queen_lucy", team: [336, 213, 350]),
        .init(key: "brandon", name: "Brandon", title: "Pyramid King", pic: "pyramid_king_brandon", team: [377, 378, 379]),
        .init(key: "steven", name: "Steven", title: "Former Champion", pic: "steven", team: [227, 344, 306, 346, 348, 376]),
    ]

    static let classes: [(title: String, pic: String, names: [String])] = [
        ("Youngster", "youngster", ["Joey", "Calvin", "Ben", "Josh"]), ("Lass", "lass", ["Janice", "Haley", "Tiana"]),
        ("Hiker", "hiker", ["Clark", "Mike", "Devan"]), ("Bug Catcher", "bug_catcher", ["Rick", "Greg", "Doug"]),
        ("Swimmer", "swimmer_f", ["Nicole", "Laurel", "Grace"]), ("Black Belt", "black_belt", ["Koichi", "Nob", "Takao"]),
        ("Psychic", "psychic_m", ["Edward", "Preston", "Jacki"]), ("Beauty", "beauty", ["Jessica", "Thalia", "Olivia"]),
        ("Ace Trainer", "cooltrainer_m", ["Jonathan", "Albert", "Derek"]), ("Ace Trainer", "cooltrainer_f", ["Jennifer", "Alexa", "Mary"]),
        ("Expert", "expert_m", ["Timothy", "Shelby", "Fredrick"]), ("Dragon Tamer", "dragon_tamer", ["Aaron", "Nicolas"]),
    ]

    static func today(_ date: Date = .now) -> String { DailyStamps.key(date) }

    /// 1 = Monday … 7 = Sunday.
    static func weekday(_ date: Date = .now) -> Int {
        let w = Calendar.current.component(.weekday, from: date)       // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    /// Follows level evolutions so a Lv. 50 team isn't full of first stages.
    static func evolve(_ id: Int, level: Int) -> Int {
        var sp = Dex.species(id)
        for _ in 0..<3 {
            guard let rule = sp.evolutions.first(where: { r in
                switch r.kind {
                case .level: return level >= (r.level ?? 101)
                case .friendship, .item: return level >= 36
                }
            }) else { break }
            sp = Dex.species(rule.into)
        }
        return sp.id
    }

    /// Your strongest Pokémon sets the pace.
    static func partyLevel(_ s: GameState) -> Int {
        s.party.map(\.level).max() ?? 5
    }

    /// Frontier trainers raise their Pokémon properly: perfect IVs and effort that grows with each battle.
    private static func mon<R: RandomNumberGenerator>(_ id: Int, _ lv: Int, battle: Int, rng: inout R) -> BattleMon {
        BattleMon(speciesID: id, level: max(2, min(100, lv)), nature: Dex.natures.randomElement(using: &rng)!,
                  iv: 31, ev: [0, 40, 85, 128, 170, 252, 252][min(6, battle)], trainer: true, rng: &rng)
    }

    static func trainer(for battle: Int, in s: GameState, date: Date = .now) -> FrontierTrainer {
        let top = partyLevel(s)
        // seeded per day and battle, so it's the same trainer if you leave and come back
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y: Int = c.year ?? 0
        let mo: Int = c.month ?? 0
        let d: Int = c.day ?? 0
        let daySeed = UInt64(y * 10_000 + mo * 100 + d)
        var rng = SeededRNG(seed: daySeed &* 31 &+ UInt64(battle))
        if battle == 5 {
            let day = weekday(date)
            if day == 7 {
                let allSix = s.frontier.week == Swarm.week(date) && Set(s.frontier.leadersBeaten).isSuperset(of: leaders.map(\.key))
                if allSix {
                    let pick = Int.random(in: 0..<3, using: &rng) == 0 ? champion : brains.randomElement(using: &rng)!
                    let lv = top + (pick.key == "wallace" ? 5 : 6)
                    let team = pick.team.enumerated().map { i, id in mon(id, lv - (i == pick.team.count - 1 ? 0 : Int.random(in: 0...2, using: &rng)), battle: 6, rng: &rng) }
                    return FrontierTrainer(name: pick.name, title: pick.title, pic: pick.pic, team: team, isLeader: false,
                                           isChampion: true, badge: nil,
                                           intro: pick.key == "wallace" ? "You beat every Gym Leader this week. Now face the Champion!"
                                                                         : "A legendary trainer has heard of you…")
                }
            }
            // Gym Leaders: a full team above your best, with their ace last
            let l = day == 7 ? sundayLeader : leaders[day - 1]
            let size = max(l.team.count, min(6, 4 + (s.party.count >= 5 ? 1 : 0) + (top >= 40 ? 1 : 0)))
            var ids = l.team
            while ids.count < size, let extra = l.team.randomElement(using: &rng) { ids.insert(extra, at: 0) }
            let team = ids.enumerated().map { i, id -> BattleMon in
                let ace = i == ids.count - 1
                let lv = top + (ace ? 3 : Int.random(in: 1...2, using: &rng))
                return mon(evolve(id, level: lv), lv, battle: 5, rng: &rng)
            }
            return FrontierTrainer(name: l.name, title: "Gym Leader", pic: "leader_" + l.key, team: team, isLeader: true,
                                   isChampion: false, badge: l.badge, intro: "\(l.name) uses \(l.type.displayName)-type Pokémon.")
        }
        // Battles 1–4 get harder: battle 3 always has one at your best level, battle 4 one above it
        let cls = classes.randomElement(using: &rng)!
        let size = [3, 3, 4, 5][battle - 1]
        let spread: [ClosedRange<Int>] = [(-5)...(-3), (-3)...(-1), (-2)...0, (-1)...1]
        let ace = [-2, -1, 0, 1][battle - 1]
        // stronger species as the battles go on
        let all = Dex.all.filter { !$0.isLegendary && !$0.isMythical && $0.generation <= 3 && !$0.isBaby }
        let byPower = all.sorted { SpeciesData.stats($0.id).reduce(0, +) < SpeciesData.stats($1.id).reduce(0, +) }
        let from = [0.0, 0.25, 0.4, 0.55][battle - 1]
        let pool = Array(byPower[Int(Double(byPower.count) * from)...])
        var team: [BattleMon] = []
        for i in 0..<size {
            let isAce = i == size - 1
            let lv = top + (isAce ? ace : Int.random(in: spread[battle - 1], using: &rng))
            let sp = pool.randomElement(using: &rng)!
            var id = evolve(GardenRules.familyRoot(sp.id), level: lv)
            // no babies on a trainer's team: start from the next stage
            if Dex.species(id).isBaby, let next = Dex.species(id).evolutions.first?.into { id = evolve(next, level: lv) }
            team.append(mon(id, lv, battle: battle, rng: &rng))
        }
        return FrontierTrainer(name: cls.names.randomElement(using: &rng)!, title: cls.title, pic: cls.pic, team: team,
                               isLeader: false, isChampion: false, badge: nil, intro: "")
    }

    struct Reward { var money: Int; var balls: [BallKind: Int]; var items: [String: Int] }

    static func reward(for battle: Int, champion: Bool) -> Reward {
        if champion {
            return Reward(money: 60_000, balls: [.master: 1], items: ["lucky-egg": 1, "rare-candy": 10])
        }
        switch battle {
        case 1: return Reward(money: 600, balls: [.poke: 3], items: [:])
        case 2: return Reward(money: 1_200, balls: [.great: 3], items: [:])
        case 3: return Reward(money: 2_500, balls: [.ultra: 3], items: [FieldItems.vitamins.randomElement()!: 1])
        case 4: return Reward(money: 5_000, balls: [.ultra: 2], items: ["rare-candy": 2, ["repel", "honey", "revive"].randomElement()!: 1])
        default: return Reward(money: 12_000, balls: [.ultra: 5], items: ["rare-candy": 5, "ability-capsule": 1])
        }
    }

    static func rewardText(_ r: Reward) -> String {
        var parts = ["₽\(r.money.formatted())"]
        for (b, n) in r.balls { parts.append("\(n) \(b.name)\(n == 1 ? "" : "s")") }
        for (k, n) in r.items { parts.append(n == 1 ? Dex.itemName(k) : "\(n) \(Dex.itemName(k))") }
        return parts.joined(separator: " · ")
    }

    /// Resets the daily run (and the weekly leader list) when the day changes.
    static func refresh(_ s: inout GameState, date: Date = .now) {
        if s.frontier.day != today(date) {
            s.frontier.day = today(date)
            s.frontier.won = 0
            s.frontier.lost = false
        }
        if s.frontier.week != Swarm.week(date) {
            s.frontier.week = Swarm.week(date)
            s.frontier.leadersBeaten = []
        }
    }
}

/// Small deterministic RNG (SplitMix64) so a day's trainers stay the same.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
