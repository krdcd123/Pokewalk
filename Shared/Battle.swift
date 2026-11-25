import Foundation

// MARK: - Battles (Battle Frontier)
//
// A compact Gen 3-style battle: real base stats, levels and natures, type matchups, STAB, critical hits.
// Each Pokémon gets moves from its types (stronger ones at higher levels) plus a Normal-type move.

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
        .rock: [.fighting, .ground, .steel], .ghost: [.dark], .dragon: [.steel], .dark: [.fighting, .dark, .fairy],
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

struct BattleMove: Hashable {
    let name: String
    let type: PokeType
    let power: Int
    let special: Bool

    /// Three strengths per type and category: early, mid and late game.
    private static let names: [PokeType: (phys: [String], spec: [String])] = [
        .normal: (["Tackle", "Body Slam", "Double-Edge"], ["Swift", "Hyper Voice", "Hyper Beam"]),
        .fire: (["Fire Fang", "Fire Punch", "Flare Blitz"], ["Ember", "Flamethrower", "Fire Blast"]),
        .water: (["Aqua Jet", "Waterfall", "Aqua Tail"], ["Water Gun", "Surf", "Hydro Pump"]),
        .grass: (["Vine Whip", "Razor Leaf", "Leaf Blade"], ["Absorb", "Giga Drain", "Solar Beam"]),
        .electric: (["Spark", "Thunder Punch", "Wild Charge"], ["Thunder Shock", "Thunderbolt", "Thunder"]),
        .ice: (["Ice Shard", "Ice Punch", "Icicle Crash"], ["Powder Snow", "Ice Beam", "Blizzard"]),
        .fighting: (["Karate Chop", "Brick Break", "Close Combat"], ["Vacuum Wave", "Aura Sphere", "Focus Blast"]),
        .poison: (["Poison Sting", "Poison Jab", "Gunk Shot"], ["Acid", "Sludge Bomb", "Sludge Wave"]),
        .ground: (["Mud-Slap", "Dig", "Earthquake"], ["Mud Shot", "Earth Power", "Earth Power"]),
        .flying: (["Peck", "Aerial Ace", "Brave Bird"], ["Gust", "Air Slash", "Hurricane"]),
        .psychic: (["Confusion", "Zen Headbutt", "Psycho Cut"], ["Confusion", "Psychic", "Psystrike"]),
        .bug: (["Bug Bite", "X-Scissor", "Megahorn"], ["Struggle Bug", "Signal Beam", "Bug Buzz"]),
        .rock: (["Rock Throw", "Rock Slide", "Stone Edge"], ["Rock Throw", "Power Gem", "Power Gem"]),
        .ghost: (["Lick", "Shadow Claw", "Shadow Claw"], ["Astonish", "Shadow Ball", "Shadow Ball"]),
        .dragon: (["Dragon Tail", "Dragon Claw", "Outrage"], ["Twister", "Dragon Pulse", "Draco Meteor"]),
        .dark: (["Bite", "Crunch", "Night Slash"], ["Snarl", "Dark Pulse", "Dark Pulse"]),
        .steel: (["Metal Claw", "Iron Head", "Iron Tail"], ["Mirror Shot", "Flash Cannon", "Flash Cannon"]),
        .fairy: (["Fairy Wind", "Play Rough", "Play Rough"], ["Disarming Voice", "Dazzling Gleam", "Moonblast"]),
    ]
    private static let powers = [[40, 75, 100], [40, 80, 110]]   // normal-type moves are a bit weaker per tier

    static func make(_ type: PokeType, level: Int, special: Bool) -> BattleMove {
        let tier = level < 22 ? 0 : level < 42 ? 1 : 2
        let n = names[type]!
        let power = type == .normal ? [40, 70, 90][tier] : powers[1][tier]
        return BattleMove(name: (special ? n.spec : n.phys)[tier], type: type, power: power, special: special)
    }
}

struct BattleMon: Identifiable, Hashable {
    let id = UUID()
    let ownedID: UUID?
    let speciesID: Int
    let name: String
    let level: Int
    let isShiny: Bool
    let types: [PokeType]
    let stats: [Int]          // hp, atk, def, spa, spd, spe
    var hp: Int
    let moves: [BattleMove]
    var friendship = 70

    var maxHP: Int { stats[0] }
    var fainted: Bool { hp <= 0 }

    init(speciesID: Int, level: Int, nature: String, isShiny: Bool = false, name: String? = nil,
         ownedID: UUID? = nil, friendship: Int = 70) {
        let sp = Dex.species(speciesID)
        let base = SpeciesData.stats(speciesID)
        let ni = Dex.natures.firstIndex(of: nature) ?? 0
        let up = ni / 5 + 1, down = ni % 5 + 1        // stat index raised / lowered (1 atk … 5 spe order differs below)
        // nature order: Atk, Def, Spe, SpA, SpD → our stat indices 1, 2, 5, 3, 4
        let map = [1, 2, 5, 3, 4]
        var st: [Int] = []
        for i in 0..<6 {
            if i == 0 {
                st.append((2 * base[0] + 15) * level / 100 + level + 10)
            } else {
                var v = Double((2 * base[i] + 15) * level / 100 + 5)
                if up != down {
                    if map[up - 1] == i { v *= 1.1 }
                    if map[down - 1] == i { v *= 0.9 }
                }
                st.append(Int(v))
            }
        }
        self.ownedID = ownedID
        self.speciesID = speciesID
        self.name = name ?? sp.name
        self.level = level
        self.isShiny = isShiny
        self.types = sp.types
        self.stats = st
        self.hp = st[0]
        self.friendship = friendship
        let special = base[3] > base[1]
        var moves = sp.types.map { BattleMove.make($0, level: level, special: special) }
        if !sp.types.contains(.normal) { moves.append(BattleMove.make(.normal, level: level, special: special)) }
        // a coverage move from a type that's good against what this Pokémon is weak to
        let coverage: [PokeType: PokeType] = [.fire: .ground, .water: .ice, .grass: .poison, .electric: .steel, .rock: .ground,
                                               .ground: .rock, .flying: .steel, .psychic: .fairy, .bug: .flying, .ghost: .dark,
                                               .dragon: .fire, .dark: .fighting, .steel: .ground, .fairy: .psychic,
                                               .ice: .water, .fighting: .rock, .poison: .ground, .normal: .fighting]
        if let c = coverage[sp.types[0]], !moves.contains(where: { $0.type == c }), level >= 15 {
            moves.append(BattleMove.make(c, level: max(1, level - 10), special: special))
        }
        self.moves = Array(moves.prefix(4))
    }

    init(owned m: OwnedPokemon) {
        self.init(speciesID: m.speciesID, level: m.level, nature: m.nature, isShiny: m.isShiny, name: m.name,
                  ownedID: m.id, friendship: m.friendship)
    }
}

enum BattleMath {
    struct Hit { var damage: Int; var effectiveness: Double; var crit: Bool }

    static func hit(_ move: BattleMove, from a: BattleMon, to d: BattleMon, random: Bool = true) -> Hit {
        let atk = Double(move.special ? a.stats[3] : a.stats[1])
        let def = Double(move.special ? d.stats[4] : d.stats[2])
        let eff = TypeChart.multiplier(move.type, against: d.types)
        let stab = a.types.contains(move.type) ? 1.5 : 1
        let crit = random && Int.random(in: 0..<16) == 0
        let roll = random ? Double.random(in: 0.85...1) : 0.92
        // Friendship: a well-loved Pokémon hits a little harder (up to +10%)
        let love = 1 + Double(max(0, a.friendship - 70)) / 1850
        var dmg = ((2 * Double(a.level) / 5 + 2) * Double(move.power) * atk / max(1, def)) / 50 + 2
        dmg *= stab * eff * roll * (crit ? 1.5 : 1) * love
        return Hit(damage: eff == 0 ? 0 : max(1, Int(dmg)), effectiveness: eff, crit: crit)
    }

    /// The trainer AI: usually the strongest hit, sometimes something else.
    static func aiMove(_ a: BattleMon, vs d: BattleMon) -> BattleMove {
        if Double.random(in: 0..<1) < 0.15 { return a.moves.randomElement()! }
        return a.moves.max { hit($0, from: a, to: d, random: false).damage < hit($1, from: a, to: d, random: false).damage }!
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

    /// Your strongest Pokémon set the pace.
    static func partyLevel(_ s: GameState) -> Int {
        let levels = s.party.map(\.level).sorted(by: >).prefix(6)
        guard !levels.isEmpty else { return 5 }
        return levels.reduce(0, +) / levels.count
    }

    static func trainer(for battle: Int, in s: GameState, date: Date = .now) -> FrontierTrainer {
        let base = partyLevel(s)
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
                    let lv = min(100, base + (pick.key == "wallace" ? 7 : 8))
                    let team = pick.team.map { BattleMon(speciesID: $0, level: lv, nature: Dex.natures.randomElement(using: &rng)!) }
                    return FrontierTrainer(name: pick.name, title: pick.title, pic: pick.pic, team: team, isLeader: false,
                                           isChampion: true, badge: nil,
                                           intro: pick.key == "wallace" ? "You beat every Gym Leader this week. Now face the Champion!"
                                                                         : "A legendary trainer has heard of you…")
                }
            }
            let l = day == 7 ? sundayLeader : leaders[day - 1]
            let lv = min(100, base + 4)
            let team = l.team.map { BattleMon(speciesID: evolve($0, level: lv), level: lv - Int.random(in: 0...2, using: &rng),
                                              nature: Dex.natures.randomElement(using: &rng)!) }
            return FrontierTrainer(name: l.name, title: "Gym Leader", pic: "leader_" + l.key, team: team, isLeader: true,
                                   isChampion: false, badge: l.badge, intro: "\(l.name) uses \(l.type.displayName)-type Pokémon.")
        }
        let cls = classes.randomElement(using: &rng)!
        let lv = max(3, min(100, base + [-5, -3, -1, 1][battle - 1]))
        let size = [2, 3, 3, 4][battle - 1]
        let pool = Dex.all.filter { !$0.isLegendary && !$0.isMythical && $0.generation <= 4 && !$0.isBaby }
        let team = (0..<size).map { _ -> BattleMon in
            let sp = pool.randomElement(using: &rng)!
            return BattleMon(speciesID: evolve(GardenRules.familyRoot(sp.id), level: lv), level: lv,
                             nature: Dex.natures.randomElement(using: &rng)!)
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
