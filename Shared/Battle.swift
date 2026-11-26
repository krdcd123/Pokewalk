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

// MARK: - Gym Challenge & Battle Frontier
//
// The Gym Challenge: five battles a day — four trainers, then the next Gym Leader of your region (in order).
// With all eight badges, the day's run is the Pokémon League: the Elite Four, then the Champion. Become Champion
// and you can build the Battle Frontier: Frontier trainers and a Frontier Brain every day. Both pay BP.
// You can lose three times a day; after that, come back tomorrow.

struct Frontier: Codable, Equatable, Hashable {
    // Gym Challenge (today)
    var day = ""                      // day key of today's run
    var won = 0                       // battles won today (0–5)
    var losses = 0                    // battles lost today (3 = done)
    var lost = false                  // out of tries today: come back tomorrow
    var week = 0
    var leadersBeaten: [String] = []
    var badges: [String] = []         // every leader ever beaten
    var symbols: [String] = []        // Champions / Frontier Brains beaten
    var champions: [String] = []      // regions whose Pokémon League you've won
    var totalWins = 0
    var bp = 0                        // Battle Points to spend at the Poké Mart's BP counter
    var bpEarned = 0
    // The Battle Frontier (built after becoming Champion)
    var built = 0
    var building: RanchBuild?
    var fDay = ""
    var fWon = 0
    var fLosses = 0
    var fLost = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        day = v(.day, ""); won = v(.won, 0); losses = v(.losses, 0); lost = v(.lost, false)
        week = v(.week, 0); leadersBeaten = v(.leadersBeaten, []); badges = v(.badges, []); symbols = v(.symbols, [])
        champions = v(.champions, []); totalWins = v(.totalWins, 0); bp = v(.bp, 0); bpEarned = v(.bpEarned, 0)
        built = v(.built, 0); building = try? c.decodeIfPresent(RanchBuild.self, forKey: .building)
        fDay = v(.fDay, ""); fWon = v(.fWon, 0); fLosses = v(.fLosses, 0); fLost = v(.fLost, false)
        // old saves: a loss used to end the day straight away
        if lost && losses == 0 { losses = FrontierRules.maxLosses }
    }

    func has(_ p: Int) -> Bool { built > p }
    var open: Bool { has(0) }
    var nextProject: RanchProject? { FrontierRules.projects.first { $0.id == built } }

    // per mode
    func won(_ m: FrontierRules.Mode) -> Int { m == .gym ? won : fWon }
    func losses(_ m: FrontierRules.Mode) -> Int { m == .gym ? losses : fLosses }
    func done(_ m: FrontierRules.Mode) -> Bool { m == .gym ? lost : fLost }
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
    var isElite = false
    var isBrain = false
}

enum FrontierRules {
    struct Leader { let key: String; let name: String; let badge: String; let type: PokeType; let team: [Int] }

    /// Your trainer's games decide which region's Gym Leaders (and Champion) you face.
    enum Region: String { case kanto, johto, hoenn }
    static func region(_ s: GameState) -> Region { region(appearance: s.trainer.appearance) }
    static func region(appearance: String) -> Region {
        switch appearance {
        case "red1", "red", "leaf": return .kanto
        case "gold", "kris": return .johto
        default: return .hoenn
        }
    }

    /// Monday → Saturday, then the two Sunday leaders (they take turns, week by week).
    static let kanto: [Leader] = [
        .init(key: "brock", name: "Brock", badge: "Boulder Badge", type: .rock, team: [74, 138, 140, 111, 95]),
        .init(key: "misty", name: "Misty", badge: "Cascade Badge", type: .water, team: [118, 54, 86, 116, 121]),
        .init(key: "lt_surge", name: "Lt. Surge", badge: "Thunder Badge", type: .electric, team: [100, 81, 125, 25, 26]),
        .init(key: "erika", name: "Erika", badge: "Rainbow Badge", type: .grass, team: [114, 70, 102, 44, 45]),
        .init(key: "koga", name: "Koga", badge: "Soul Badge", type: .poison, team: [109, 88, 48, 42, 110]),
        .init(key: "sabrina", name: "Sabrina", badge: "Marsh Badge", type: .psychic, team: [122, 49, 97, 124, 65]),
        .init(key: "blaine", name: "Blaine", badge: "Volcano Badge", type: .fire, team: [58, 77, 37, 126, 59]),
        .init(key: "giovanni", name: "Giovanni", badge: "Earth Badge", type: .ground, team: [111, 51, 31, 34, 112]),
    ]
    static let johto: [Leader] = [
        .init(key: "falkner", name: "Falkner", badge: "Zephyr Badge", type: .flying, team: [16, 21, 163, 83, 17]),
        .init(key: "bugsy", name: "Bugsy", badge: "Hive Badge", type: .bug, team: [165, 167, 48, 193, 123]),
        .init(key: "whitney", name: "Whitney", badge: "Plain Badge", type: .normal, team: [35, 39, 161, 206, 241]),
        .init(key: "morty", name: "Morty", badge: "Fog Badge", type: .ghost, team: [92, 200, 93, 200, 94]),
        .init(key: "chuck", name: "Chuck", badge: "Storm Badge", type: .fighting, team: [56, 66, 237, 57, 62]),
        .init(key: "jasmine", name: "Jasmine", badge: "Mineral Badge", type: .steel, team: [81, 205, 227, 82, 208]),
        .init(key: "pryce", name: "Pryce", badge: "Glacier Badge", type: .ice, team: [86, 220, 124, 87, 221]),
        .init(key: "clair", name: "Clair", badge: "Rising Badge", type: .dragon, team: [147, 116, 148, 117, 230]),
    ]
    static let hoenn: [Leader] = [
        .init(key: "roxanne", name: "Roxanne", badge: "Stone Badge", type: .rock, team: [74, 299, 95, 345, 347]),
        .init(key: "brawly", name: "Brawly", badge: "Knuckle Badge", type: .fighting, team: [66, 296, 307, 56, 214]),
        .init(key: "wattson", name: "Wattson", badge: "Dynamo Badge", type: .electric, team: [81, 309, 100, 25, 311]),
        .init(key: "flannery", name: "Flannery", badge: "Heat Badge", type: .fire, team: [218, 322, 324, 58, 77]),
        .init(key: "norman", name: "Norman", badge: "Balance Badge", type: .normal, team: [287, 327, 263, 300, 241]),
        .init(key: "winona", name: "Winona", badge: "Feather Badge", type: .flying, team: [333, 276, 278, 227, 357]),
        .init(key: "tate_and_liza", name: "Tate & Liza", badge: "Mind Badge", type: .psychic, team: [337, 338, 343, 177, 280]),
        .init(key: "juan", name: "Juan", badge: "Rain Badge", type: .water, team: [370, 340, 364, 342, 230]),
    ]
    /// All eight of a region's leaders.
    static func allLeaders(_ r: Region) -> [Leader] { r == .kanto ? kanto : r == .johto ? johto : hoenn }
    /// Monday → Saturday.
    static func leaders(_ r: Region) -> [Leader] { Array(allLeaders(r).prefix(6)) }
    /// Sunday's leader if all six weren't beaten this week (the region's last two take turns).
    static func sundayLeader(_ r: Region, date: Date = .now) -> Leader { allLeaders(r)[6 + Swarm.week(date) % 2] }
    static var everyLeader: [Leader] { kanto + johto + hoenn }
    static func leaderToday(_ r: Region, date: Date = .now) -> Leader {
        let d = weekday(date)
        return d == 7 ? sundayLeader(r, date: date) : leaders(r)[d - 1]
    }

    struct Brain { let key: String; let name: String; let title: String; let pic: String; let team: [Int] }
    static func champion(_ r: Region) -> Brain {
        switch r {
        case .kanto: return Brain(key: "blue", name: "Blue", title: "Champion", pic: "champion_blue", team: [18, 65, 112, 103, 59, 9])
        case .johto: return Brain(key: "lance", name: "Lance", title: "Champion", pic: "champion_lance", team: [130, 142, 6, 148, 148, 149])
        case .hoenn: return Brain(key: "wallace", name: "Wallace", title: "Champion", pic: "champion_wallace", team: [321, 73, 272, 340, 130, 350])
        }
    }
    /// The Pokémon League: the region's Elite Four, in order.
    static func eliteFour(_ r: Region) -> [Brain] {
        switch r {
        case .kanto: return [
            .init(key: "lorelei", name: "Lorelei", title: "Elite Four", pic: "elite_four_lorelei", team: [87, 91, 80, 124, 131]),
            .init(key: "bruno", name: "Bruno", title: "Elite Four", pic: "elite_four_bruno", team: [95, 107, 106, 95, 68]),
            .init(key: "agatha", name: "Agatha", title: "Elite Four", pic: "elite_four_agatha", team: [94, 42, 93, 24, 94]),
            .init(key: "lance_e4", name: "Lance", title: "Elite Four", pic: "elite_four_lance", team: [130, 148, 148, 142, 149]),
        ]
        case .johto: return [
            .init(key: "will", name: "Will", title: "Elite Four", pic: "elite_four_will", team: [178, 124, 80, 103, 178]),
            .init(key: "koga_e4", name: "Koga", title: "Elite Four", pic: "elite_four_koga", team: [168, 49, 205, 89, 169]),
            .init(key: "bruno_j", name: "Bruno", title: "Elite Four", pic: "elite_four_bruno", team: [237, 107, 106, 95, 68]),
            .init(key: "karen", name: "Karen", title: "Elite Four", pic: "elite_four_karen", team: [197, 45, 94, 198, 229]),
        ]
        case .hoenn: return [
            .init(key: "sidney", name: "Sidney", title: "Elite Four", pic: "elite_four_sidney", team: [262, 275, 332, 342, 359]),
            .init(key: "phoebe", name: "Phoebe", title: "Elite Four", pic: "elite_four_phoebe", team: [356, 354, 302, 354, 356]),
            .init(key: "glacia", name: "Glacia", title: "Elite Four", pic: "elite_four_glacia", team: [364, 362, 364, 362, 365]),
            .init(key: "drake", name: "Drake", title: "Elite Four", pic: "elite_four_drake", team: [372, 230, 330, 334, 373]),
        ]
        }
    }

    enum Mode { case gym, frontier }
    static let maxLosses = 3
    static func maxLosses(_ m: Mode, _ s: GameState) -> Int { m == .frontier && s.frontier.has(2) ? 4 : maxLosses }

    /// The Gym Challenge goes through your region's leaders in order.
    static func nextLeader(_ s: GameState) -> Leader? {
        allLeaders(region(s)).first { !s.frontier.badges.contains($0.key) }
    }
    static func badgeCount(_ s: GameState) -> Int {
        allLeaders(region(s)).filter { s.frontier.badges.contains($0.key) }.count
    }
    static func isChampion(_ s: GameState) -> Bool { s.frontier.champions.contains(region(s).rawValue) }
    /// All eight badges: today's run is the Pokémon League (after you're Champion, a rematch on Sundays).
    static func isLeagueDay(_ s: GameState, date: Date = .now) -> Bool {
        nextLeader(s) == nil && (!isChampion(s) || weekday(date) == 7)
    }

    /// The Battle Frontier, built (like the Daycare) once you're Champion.
    static let projects: [RanchProject] = [
        .init(id: 0, name: "Battle Tower", symbol: "building.columns.fill",
              text: "The heart of the Battle Frontier: tough trainers every day, and a Frontier Brain at the top.",
              cost: [.wood: 300, .stone: 400, .clay: 200, .fibre: 150], money: 50_000, hours: 72,
              reward: "The Battle Frontier opens", ticket: nil),
        .init(id: 1, name: "Battle Factory", symbol: "gearshape.2.fill", text: "More facilities, bigger prizes.",
              cost: [.stone: 500, .clay: 400], money: 80_000, hours: 96, reward: "50% more BP at the Frontier", ticket: nil),
        .init(id: 2, name: "Battle Pyramid", symbol: "triangle.fill", text: "A place to rest between battles.",
              cost: [.wood: 500, .stone: 600, .fibre: 300], money: 120_000, hours: 120, reward: "4 tries a day at the Frontier", ticket: nil),
    ]
    static func canBuild(_ s: GameState) -> Bool { !s.frontier.champions.isEmpty }

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

    private static func team<R: RandomNumberGenerator>(_ ids: [Int], top: Int, plus: ClosedRange<Int>, ace: Int, battle: Int,
                                                       rng: inout R) -> [BattleMon] {
        ids.enumerated().map { i, id -> BattleMon in
            let lv = top + (i == ids.count - 1 ? ace : Int.random(in: plus, using: &rng))
            var sp = evolve(id, level: lv)
            if Dex.species(sp).isBaby, let next = Dex.species(sp).evolutions.first?.into { sp = evolve(next, level: lv) }
            return mon(sp, lv, battle: battle, rng: &rng)
        }
    }

    static func trainer(for battle: Int, in s: GameState, mode: Mode = .gym, date: Date = .now) -> FrontierTrainer {
        let top = partyLevel(s)
        // seeded per day, mode and battle, so it's the same trainer if you leave and come back
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y: Int = c.year ?? 0
        let mo: Int = c.month ?? 0
        let d: Int = c.day ?? 0
        let daySeed = UInt64(y * 10_000 + mo * 100 + d)
        var rng = SeededRNG(seed: daySeed &* 31 &+ UInt64(battle) &+ (mode == .frontier ? 7_777 : 0))
        let r = region(s)

        if mode == .gym && isLeagueDay(s, date: date) {
            if battle <= 4 {
                let e = eliteFour(r)[battle - 1]
                let ids = e.team
                return FrontierTrainer(name: e.name, title: e.title, pic: e.pic,
                                       team: team(ids, top: top, plus: 2...3, ace: 4, battle: 5, rng: &rng),
                                       isLeader: false, isChampion: false, badge: nil,
                                       intro: battle == 1 ? "Welcome to the Pokémon League!" : "", isElite: true)
            }
            let champ = champion(r)
            return FrontierTrainer(name: champ.name, title: champ.title, pic: champ.pic,
                                   team: team(champ.team, top: top, plus: 3...5, ace: 6, battle: 6, rng: &rng),
                                   isLeader: false, isChampion: true, badge: nil,
                                   intro: isChampion(s) ? "The Champion wants a rematch!" : "Beat the Champion to become Champion yourself!")
        }

        if battle == 5 && mode == .frontier {
            let pick = brains.randomElement(using: &rng)!
            let lv = top + 6
            let t = pick.team.enumerated().map { i, id in
                mon(id, lv - (i == pick.team.count - 1 ? 0 : Int.random(in: 0...2, using: &rng)), battle: 6, rng: &rng)
            }
            return FrontierTrainer(name: pick.name, title: pick.title, pic: pick.pic, team: t, isLeader: false,
                                   isChampion: true, badge: nil, intro: "A Frontier Brain stands in your way!", isBrain: true)
        }

        if battle == 5 {
            // the next Gym Leader in order (after you're Champion, a different leader each day for a rematch)
            let all = allLeaders(r)
            let dayIndex = Int(daySeed % 8)
            let l = nextLeader(s) ?? all[dayIndex]
            let size = max(l.team.count, min(6, 4 + (s.party.count >= 5 ? 1 : 0) + (top >= 40 ? 1 : 0)))
            var ids = l.team
            while ids.count < size, let extra = l.team.dropLast().randomElement(using: &rng) { ids.insert(extra, at: 0) }
            let rematch = nextLeader(s) == nil
            return FrontierTrainer(name: l.name, title: "Gym Leader", pic: "leader_" + l.key,
                                   team: team(ids, top: top, plus: 1...2, ace: 3, battle: 5, rng: &rng),
                                   isLeader: true, isChampion: false, badge: l.badge,
                                   intro: (rematch ? "Rematch! " : "") + "\(l.name) uses \(l.type.displayName)-type Pokémon.")
        }

        // Battles 1–4: new random trainers every day, getting harder (the Frontier's are tougher still)
        let step = mode == .frontier ? min(4, battle + 1) : battle
        let cls = classes.randomElement(using: &rng)!
        let size = mode == .frontier ? [4, 5, 5, 6][battle - 1] : [3, 3, 4, 5][battle - 1]
        let spread: [ClosedRange<Int>] = [(-5)...(-3), (-3)...(-1), (-2)...0, (-1)...1]
        let ace = [-2, -1, 0, 1][step - 1] + (mode == .frontier ? 1 : 0)
        let all = Dex.all.filter { !$0.isLegendary && !$0.isMythical && $0.generation <= 3 && !$0.isBaby }
        let byPower = all.sorted { SpeciesData.stats($0.id).reduce(0, +) < SpeciesData.stats($1.id).reduce(0, +) }
        let from = [0.0, 0.25, 0.4, 0.55][step - 1]
        let pool = Array(byPower[Int(Double(byPower.count) * from)...])
        var t: [BattleMon] = []
        for i in 0..<size {
            let isAce = i == size - 1
            let lv = top + (isAce ? ace : Int.random(in: spread[step - 1], using: &rng))
            let sp = pool.randomElement(using: &rng)!
            var id = evolve(GardenRules.familyRoot(sp.id), level: lv)
            if Dex.species(id).isBaby, let next = Dex.species(id).evolutions.first?.into { id = evolve(next, level: lv) }
            t.append(mon(id, lv, battle: mode == .frontier ? 6 : battle, rng: &rng))
        }
        return FrontierTrainer(name: cls.names.randomElement(using: &rng)!, title: cls.title, pic: cls.pic, team: t,
                               isLeader: false, isChampion: false, badge: nil, intro: "")
    }

    /// Wins pay Battle Points, spent at the Poké Mart's BP counter.
    struct Reward { var bp: Int }

    static func reward(for battle: Int, trainer t: FrontierTrainer, mode: Mode, in s: GameState) -> Reward {
        if mode == .frontier {
            let base = t.isBrain ? 15 : [3, 4, 5, 6][max(0, min(3, battle - 1))]
            return Reward(bp: s.frontier.has(1) ? base * 3 / 2 : base)
        }
        if t.isChampion { return Reward(bp: 20) }
        if t.isElite { return Reward(bp: 6) }
        if t.isLeader { return Reward(bp: 8) }
        return Reward(bp: [1, 2, 3, 4][max(0, min(3, battle - 1))])
    }

    static func rewardText(_ r: Reward) -> String { "\(r.bp) BP" }

    /// Resets the daily run (and the weekly leader list) when the day changes.
    static func refresh(_ s: inout GameState, date: Date = .now) {
        if s.frontier.day != today(date) {
            s.frontier.day = today(date)
            s.frontier.won = 0
            s.frontier.losses = 0
            s.frontier.lost = false
        }
        if s.frontier.fDay != today(date) {
            s.frontier.fDay = today(date)
            s.frontier.fWon = 0
            s.frontier.fLosses = 0
            s.frontier.fLost = false
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

// MARK: - BP counter (Poké Mart)

/// Spend Battle Points from the Frontier on items and balls you can't buy with money.
enum BPShop {
    struct Entry: Identifiable, Hashable {
        let ball: BallKind?
        let item: String?
        let price: Int
        let note: String
        var id: String { ball?.rawValue ?? item ?? "" }
    }

    /// Balls the Poké Mart doesn't sell for money (plus Ultra Balls, as a BP bargain).
    static let balls: [Entry] = [
        .init(ball: .ultra, item: nil, price: 1, note: "2× catch rate."),
        .init(ball: .premier, item: nil, price: 1, note: "Same as a Poké Ball, but a handsome white."),
        .init(ball: .safari, item: nil, price: 2, note: "1.5× catch rate, the Safari Zone's own ball."),
        .init(ball: .master, item: nil, price: 200, note: "Catches any wild Pokémon without fail."),
    ]

    static let items: [Entry] = [
        .init(ball: nil, item: "rare-candy", price: 4, note: "Raises a Pokémon by one level."),
        .init(ball: nil, item: "hp-up", price: 2, note: ""), .init(ball: nil, item: "protein", price: 2, note: ""),
        .init(ball: nil, item: "iron", price: 2, note: ""), .init(ball: nil, item: "calcium", price: 2, note: ""),
        .init(ball: nil, item: "zinc", price: 2, note: ""), .init(ball: nil, item: "carbos", price: 2, note: ""),
        .init(ball: nil, item: "max-revive", price: 6, note: ""),
        .init(ball: nil, item: "smoke-ball", price: 6, note: ""),
        .init(ball: nil, item: "white-flute", price: 5, note: ""), .init(ball: nil, item: "black-flute", price: 5, note: ""),
        .init(ball: nil, item: "revival-herb", price: 5, note: ""),
        .init(ball: nil, item: "soothe-bell", price: 16, note: ""),
        .init(ball: nil, item: "lucky-egg", price: 24, note: ""),
        .init(ball: nil, item: "amulet-coin", price: 24, note: ""),
        .init(ball: nil, item: "ability-capsule", price: 32, note: ""),
    ]

    @discardableResult
    static func buy(_ e: Entry, count: Int = 1, in s: inout GameState) -> Bool {
        let total = e.price * count
        guard count > 0, s.frontier.bp >= total else { return false }
        s.frontier.bp -= total
        if let b = e.ball { s.balls[b, default: 0] += count }
        if let k = e.item { s.bag[k, default: 0] += count }
        return true
    }
}
