import Foundation

// MARK: - Gen 3 battle engine
//
// Moves, learnsets and effects as in Pokémon Emerald (data rolled back to Emerald values from PokéAPI:
// Shared/Resources/moves.json, made by tools/gen_moves.py). Damage uses the Gen 3 formula, with the
// physical/special split decided by the move's type, stat stages, critical hits (×2), status conditions,
// confusion, flinching, multi-hit, draining, recoil, charging and recharging moves.

struct MoveInfo: Codable, Hashable {
    let id: Int
    let key: String
    let name: String
    let type: PokeType
    let power: Int?
    let pp: Int
    let accuracy: Int?
    let priority: Int
    let target: Int
    let status: Bool
    let effect: Int
    let chance: Int
    let cat: Int            // PokéAPI meta category (0 damage, 1 ailment, 2 stats, 3 heal, 4 damage+ailment, …)
    let ailment: Int        // 1 par, 2 slp, 3 frz, 4 brn, 5 psn, 6 confusion, 18 leech seed
    let minHits: Int?
    let maxHits: Int?
    let drain: Int          // % of damage: + heals the user, − is recoil
    let healing: Int
    let crit: Int
    let ailmentChance: Int
    let flinch: Int
    let statChance: Int
    let stats: [[Int]]      // [stat id, change] — 1 hp 2 atk 3 def 4 spa 5 spd 6 spe 7 acc 8 eva
    let sound: String?

    /// Gen 3: physical or special depends only on the type.
    var physical: Bool { MoveData.physicalTypes.contains(type) }
    var targetsUser: Bool { target == 7 }
}

enum MoveData {
    private struct File: Codable {
        let moves: [MoveInfo]
        let learnsets: [String: [[Int]]]
        let gen3Types: [String: [PokeType]]
    }

    static let physicalTypes: Set<PokeType> = [.normal, .fighting, .flying, .poison, .ground, .rock, .bug, .ghost, .steel]

    private static let file: File? = {
        let url = Bundle.main.url(forResource: "moves", withExtension: "json")
            ?? Bundle.allBundles.lazy.compactMap { $0.url(forResource: "moves", withExtension: "json") }.first
        guard let url, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: d)
    }()
    private static let byID: [Int: MoveInfo] = Dictionary(uniqueKeysWithValues: (file?.moves ?? []).map { ($0.id, $0) })

    static func info(_ id: Int) -> MoveInfo? { byID[id] }
    static let struggle = MoveInfo(id: 165, key: "struggle", name: "Struggle", type: .normal, power: 50, pp: 1, accuracy: nil,
                                   priority: 0, target: 10, status: false, effect: 0, chance: 0, cat: 0, ailment: 0,
                                   minHits: nil, maxHits: nil, drain: -25, healing: 0, crit: 0, ailmentChance: 0, flinch: 0,
                                   statChance: 0, stats: [], sound: "033-0_tackle.wav")

    /// Level-up moves in Emerald: (level, move id).
    static func learnset(_ species: Int) -> [(Int, Int)] {
        (file?.learnsets[String(species)] ?? []).map { ($0[0], $0[1]) }
    }

    /// Types as they were in Gen 3 (no Fairy type yet).
    static func types(_ species: Int) -> [PokeType] {
        file?.gen3Types[String(species)] ?? Dex.species(species).types
    }

    /// Four random moves from everything it could have learned by levelling up to `level` (at least one that does damage).
    static func randomSet<R: RandomNumberGenerator>(species: Int, level: Int, using rng: inout R) -> [Int] {
        let pool = Array(Set(learnset(species).filter { $0.0 <= level }.map(\.1))).sorted()
        guard !pool.isEmpty else { return [33] }       // Tackle
        var picks = Array(pool.shuffled(using: &rng).prefix(4))
        let damaging = pool.filter { (info($0)?.power ?? 0) > 0 || fixedDamage.contains(info($0)?.key ?? "") }
        if !picks.contains(where: { damaging.contains($0) }), let d = damaging.randomElement(using: &rng) {
            picks[picks.count - 1] = d
        }
        return picks
    }

    /// The last four moves learned by `level` (what a wild Pokémon knows in the games).
    static func latestSet(species: Int, level: Int) -> [Int] {
        var seen: [Int] = []
        for (_, m) in learnset(species).filter({ $0.0 <= level }).reversed() where !seen.contains(m) {
            seen.append(m)
            if seen.count == 4 { break }
        }
        return seen.isEmpty ? [33] : seen.reversed()
    }

    static let fixedDamage: Set<String> = ["sonic-boom", "dragon-rage", "night-shade", "seismic-toss", "super-fang", "psywave", "endeavor"]

    /// The Pokémon GO move sound for this move (one of the same type when GO doesn't have it).
    static func soundURL(_ m: MoveInfo) -> URL? {
        guard let f = m.sound, let e = f.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/PokeMiners/pogo_assets/master/Sounds/Pokemon%20Moves/" + e)
    }
}

struct BattleMove: Hashable {
    let id: Int
    var pp: Int
    let maxPP: Int

    init(id: Int) {
        self.id = id
        let p = MoveData.info(id)?.pp ?? 10
        pp = p; maxPP = p
    }

    var info: MoveInfo { MoveData.info(id) ?? MoveData.struggle }
    var name: String { info.name }
    var type: PokeType { info.type }
}

enum StatusCondition: Hashable {
    case none, paralysis, sleep(Int), freeze, burn, poison, toxic(Int)
    var short: String {
        switch self {
        case .none: return ""
        case .paralysis: return "PAR"
        case .sleep: return "SLP"
        case .freeze: return "FRZ"
        case .burn: return "BRN"
        case .poison, .toxic: return "PSN"
        }
    }
}

struct BattleMon: Identifiable, Hashable {
    let id = UUID()
    let ownedID: UUID?
    let speciesID: Int
    let name: String
    let level: Int
    let isShiny: Bool
    let gender: Gender
    let types: [PokeType]
    let stats: [Int]          // hp, atk, def, spa, spd, spe
    var hp: Int
    var moves: [BattleMove]
    var friendship = 70
    var status: StatusCondition = .none

    // Volatile (reset when it switches out)
    var stages = [Int](repeating: 0, count: 9)      // index = stat id (2 atk … 8 eva)
    var confused = 0
    var flinched = false
    var charging: Int?                              // move id being charged (Solar Beam, Fly…)
    var invulnerable = false                        // in the air / underground / underwater
    var mustRecharge = false
    var protected = false
    var protectCount = 0
    var seeded = false
    var focused = false
    var yawn = 0

    var maxHP: Int { stats[0] }
    var fainted: Bool { hp <= 0 }

    init(speciesID: Int, level: Int, nature: String, isShiny: Bool = false, name: String? = nil, gender: Gender? = nil,
         ownedID: UUID? = nil, friendship: Int = 70) {
        var rng = SystemRandomNumberGenerator()
        self.init(speciesID: speciesID, level: level, nature: nature, isShiny: isShiny, name: name, gender: gender,
                  ownedID: ownedID, friendship: friendship, rng: &rng)
    }

    init<R: RandomNumberGenerator>(speciesID: Int, level: Int, nature: String, isShiny: Bool = false, name: String? = nil,
                                   gender: Gender? = nil, ownedID: UUID? = nil, friendship: Int = 70, rng: inout R) {
        let sp = Dex.species(speciesID)
        let base = SpeciesData.stats(speciesID)
        let ni = Dex.natures.firstIndex(of: nature) ?? 0
        let up = ni / 5 + 1, down = ni % 5 + 1
        let map = [1, 2, 5, 3, 4]       // nature order Atk, Def, Spe, SpA, SpD → stat indices
        var st: [Int] = []
        for i in 0..<6 {
            if i == 0 {
                st.append(speciesID == 292 ? 1 : (2 * base[0] + 15) * level / 100 + level + 10)     // Shedinja: 1 HP
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
        self.gender = gender ?? GameRules.rollGender(sp)
        self.types = MoveData.types(speciesID)
        self.stats = st
        self.hp = st[0]
        self.friendship = friendship
        self.moves = MoveData.randomSet(species: speciesID, level: level, using: &rng).map { BattleMove(id: $0) }
    }

    init(owned m: OwnedPokemon) {
        self.init(speciesID: m.speciesID, level: m.level, nature: m.nature, isShiny: m.isShiny, name: m.name,
                  gender: m.gender, ownedID: m.id, friendship: m.friendship)
    }

    /// Clears everything that goes away when it's switched out.
    mutating func switchedOut() {
        stages = [Int](repeating: 0, count: 9)
        confused = 0; flinched = false; charging = nil; invulnerable = false; mustRecharge = false
        protected = false; protectCount = 0; seeded = false; focused = false; yawn = 0
        if case .toxic = status { status = .toxic(1) }
    }

    var hasUsableMove: Bool { moves.contains { $0.pp > 0 } }
}

enum BattleSide { case mine, foe }

/// What happened, in order, for the battle screen to show and sound out.
enum BattleEvent {
    case say(String)
    case uses(BattleSide, MoveInfo)                       // play the move's sound
    case hp(BattleSide, Int, effectiveness: Double?)      // new HP; effectiveness set when it was hit by a move
    case stat(BattleSide, up: Bool)
    case status(BattleSide)
}

enum BattleEngine {
    // MARK: Numbers

    static func stageMultiplier(_ s: Int) -> Double {
        s >= 0 ? Double(2 + s) / 2 : 2 / Double(2 - s)
    }

    static func stat(_ m: BattleMon, _ i: Int, ignoreUp: Bool = false, ignoreDown: Bool = false) -> Double {
        var st = m.stages[i + 1]
        if ignoreUp { st = min(0, st) }
        if ignoreDown { st = max(0, st) }
        var v = Double(m.stats[i]) * stageMultiplier(st)
        if i == 5, m.status == .paralysis { v /= 4 }
        return v
    }

    static func speed(_ m: BattleMon) -> Double { stat(m, 5) }

    /// Gen 3 accuracy/evasion table (−6…+6).
    static func accuracyMultiplier(_ s: Int) -> Double {
        let t: [Double] = [33, 36, 43, 50, 60, 75, 100, 133, 166, 200, 250, 266, 300]
        return t[max(-6, min(6, s)) + 6] / 100
    }

    static func critChance(_ stage: Int) -> Double { [1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 3, 1.0 / 2][min(4, max(0, stage))] }

    struct Damage { var amount: Int; var effectiveness: Double; var crit: Bool }

    /// The Gen 3 damage formula.
    static func damage(_ move: MoveInfo, power: Int, from a: BattleMon, to d: BattleMon, crit: Bool, random: Bool = true) -> Damage {
        let eff = TypeChart.multiplier(move.type, against: d.types)
        if eff == 0 { return Damage(amount: 0, effectiveness: 0, crit: false) }
        let physical = move.physical
        let atk = stat(a, physical ? 1 : 3, ignoreDown: crit)
        var def = stat(d, physical ? 2 : 4, ignoreUp: crit)
        if move.key == "self-destruct" || move.key == "explosion" { def /= 2 }
        var base = floor(floor(floor(2 * Double(a.level) / 5 + 2) * Double(power) * atk / max(1, def)) / 50)
        if physical, a.status == .burn { base = floor(base / 2) }
        base += 2
        if crit { base *= 2 }
        if a.types.contains(move.type) { base = floor(base * 1.5) }
        base = floor(base * eff)
        let roll = random ? Double(Int.random(in: 85...100)) / 100 : 0.92
        return Damage(amount: max(1, Int(base * roll)), effectiveness: eff, crit: crit)
    }

    // MARK: A turn

    /// Plays a whole turn: who goes first, both moves, then end-of-turn damage. `myMove`/`foeMove` are indices
    /// into each Pokémon's moves (nil = it's switching in, so it doesn't move; -1 = Struggle).
    static func turn(mine: inout BattleMon, foe: inout BattleMon, myMove: Int?, foeMove: Int?) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        mine.protected = false; foe.protected = false
        let mi = myMove.map { pick($0, of: mine) }, fi = foeMove.map { pick($0, of: foe) }
        let mp = mi?.priority ?? 0, fp = fi?.priority ?? 0
        let meFirst: Bool
        if mp != fp { meFirst = mp > fp }
        else { let a = speed(mine), b = speed(foe); meFirst = a != b ? a > b : Bool.random() }

        func act(_ side: BattleSide) {
            if side == .mine, let i = myMove, !mine.fainted, !foe.fainted || (mi?.targetsUser ?? false) {
                ev += use(i, by: &mine, side: .mine, on: &foe, movedFirst: meFirst)
            } else if side == .foe, let i = foeMove, !foe.fainted, !mine.fainted || (fi?.targetsUser ?? false) {
                ev += use(i, by: &foe, side: .foe, on: &mine, movedFirst: !meFirst)
            }
        }
        if meFirst { act(.mine); act(.foe) } else { act(.foe); act(.mine) }
        mine.flinched = false; foe.flinched = false

        // End of turn: burn, poison, Leech Seed, Yawn
        ev += endOfTurn(&mine, side: .mine, other: &foe)
        ev += endOfTurn(&foe, side: .foe, other: &mine)
        return ev
    }

    private static func pick(_ i: Int, of m: BattleMon) -> MoveInfo {
        if let c = m.charging { return MoveData.info(c) ?? MoveData.struggle }
        return i >= 0 && i < m.moves.count ? m.moves[i].info : MoveData.struggle
    }

    private static func prefix(_ side: BattleSide) -> String { side == .foe ? "The foe's " : "" }

    private static func endOfTurn(_ m: inout BattleMon, side: BattleSide, other: inout BattleMon) -> [BattleEvent] {
        guard !m.fainted else { return [] }
        var ev: [BattleEvent] = []
        let p = prefix(side)
        switch m.status {
        case .burn:
            m.hp = max(0, m.hp - max(1, m.maxHP / 8))
            ev += [.say("\(p)\(m.name) is hurt by its burn!"), .hp(side, m.hp, effectiveness: nil)]
        case .poison:
            m.hp = max(0, m.hp - max(1, m.maxHP / 8))
            ev += [.say("\(p)\(m.name) is hurt by poison!"), .hp(side, m.hp, effectiveness: nil)]
        case .toxic(let n):
            m.hp = max(0, m.hp - max(1, m.maxHP * n / 16))
            m.status = .toxic(min(15, n + 1))
            ev += [.say("\(p)\(m.name) is hurt by poison!"), .hp(side, m.hp, effectiveness: nil)]
        default: break
        }
        if m.seeded, !m.fainted, !other.fainted {
            let drain = min(m.hp, max(1, m.maxHP / 8))
            m.hp -= drain
            other.hp = min(other.maxHP, other.hp + drain)
            ev += [.say("\(p)\(m.name)'s health is sapped by Leech Seed!"), .hp(side, m.hp, effectiveness: nil),
                   .hp(side == .mine ? .foe : .mine, other.hp, effectiveness: nil)]
        }
        if m.yawn > 0 {
            m.yawn -= 1
            if m.yawn == 0, m.status == .none {
                m.status = .sleep(Int.random(in: 2...5))
                ev += [.say("\(p)\(m.name) fell asleep!"), .status(side)]
            }
        }
        return ev
    }

    // MARK: Using a move

    private static func use(_ index: Int, by a: inout BattleMon, side: BattleSide, on d: inout BattleMon, movedFirst: Bool) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side), dp = prefix(side == .mine ? .foe : .mine)
        let dSide: BattleSide = side == .mine ? .foe : .mine

        // Can it move at all?
        if a.mustRecharge {
            a.mustRecharge = false
            return [.say("\(p)\(a.name) must recharge!")]
        }
        switch a.status {
        case .sleep(let n):
            if n > 1 { a.status = .sleep(n - 1); return [.say("\(p)\(a.name) is fast asleep.")] }
            a.status = .none
            ev += [.say("\(p)\(a.name) woke up!"), .status(side)]
        case .freeze:
            if Int.random(in: 0..<5) == 0 { a.status = .none; ev += [.say("\(p)\(a.name) was defrosted!"), .status(side)] }
            else { return [.say("\(p)\(a.name) is frozen solid!")] }
        default: break
        }
        if a.flinched { a.flinched = false; return ev + [.say("\(p)\(a.name) flinched!")] }
        if a.confused > 0 {
            a.confused -= 1
            if a.confused == 0 {
                ev.append(.say("\(p)\(a.name) snapped out of confusion!"))
            } else {
                ev.append(.say("\(p)\(a.name) is confused!"))
                if Bool.random() {
                    // 40-power typeless physical hit on itself
                    let atk = stat(a, 1), def = stat(a, 2)
                    let dmg = max(1, Int((floor(floor(2 * Double(a.level) / 5 + 2) * 40 * atk / max(1, def)) / 50 + 2) * Double(Int.random(in: 85...100)) / 100))
                    a.hp = max(0, a.hp - dmg)
                    a.charging = nil; a.invulnerable = false
                    return ev + [.say("It hurt itself in its confusion!"), .hp(side, a.hp, effectiveness: 1)]
                }
            }
        }
        if a.status == .paralysis, Int.random(in: 0..<4) == 0 {
            a.charging = nil; a.invulnerable = false
            return ev + [.say("\(p)\(a.name) is paralyzed! It can't move!")]
        }

        // Which move (Struggle when out of PP; the second turn of a charging move)
        var move: MoveInfo
        if let c = a.charging, let m = MoveData.info(c) {
            move = m
            a.charging = nil; a.invulnerable = false
        } else if index >= 0, index < a.moves.count, a.moves[index].pp > 0 {
            move = a.moves[index].info
            a.moves[index].pp -= 1
            // Turn one of a two-turn move
            if let charge = chargeText[move.key] {
                a.charging = move.id
                a.invulnerable = ["fly", "dig", "dive", "bounce"].contains(move.key)
                if move.key == "skull-bash" { a.stages[3] = min(6, a.stages[3] + 1) }
                return ev + [.say("\(p)\(a.name) \(charge)")]
            }
        } else {
            move = MoveData.struggle
            ev.append(.say("\(p)\(a.name) has no moves left!"))
        }

        ev.append(.say("\(p)\(a.name) used \(move.name)!"))
        ev.append(.uses(side, move))

        // Protect, semi-invulnerable targets
        let hitsOpponent = !move.targetsUser && !(move.status && move.stats.allSatisfy { $0[1] > 0 } && move.cat == 2)
        if hitsOpponent, d.protected { return ev + [.say("\(dp)\(d.name) protected itself!")] }
        if hitsOpponent, d.invulnerable, !(move.key == "earthquake" || move.key == "magnitude" || move.key == "thunder" || move.key == "gust" || move.key == "surf") {
            return ev + [.say("\(p)\(a.name)'s attack missed!")]
        }

        // Accuracy
        if hitsOpponent, let acc = move.accuracy, move.cat != 9 {
            let chance = Double(acc) * accuracyMultiplier(a.stages[7] - d.stages[8])
            if Double.random(in: 0..<100) >= chance {
                if ["jump-kick", "hi-jump-kick"].contains(move.key) {
                    a.hp = max(0, a.hp - max(1, a.maxHP / 8))      // crashes (Gen 3: 1/8 of max HP)
                    return ev + [.say("\(p)\(a.name)'s attack missed!"), .say("\(p)\(a.name) kept going and crashed!"), .hp(side, a.hp, effectiveness: nil)]
                }
                return ev + [.say("\(p)\(a.name)'s attack missed!")]
            }
        }

        if move.status || (move.power == nil && !MoveData.fixedDamage.contains(move.key) && move.cat != 9 && !variablePower.contains(move.key)) {
            ev += statusMove(move, a: &a, side: side, d: &d, dSide: dSide)
            if move.key != "protect", move.key != "detect", move.key != "endure" { a.protectCount = 0 }
            return ev
        }
        a.protectCount = 0
        ev += damagingMove(move, a: &a, side: side, d: &d, dSide: dSide, movedFirst: movedFirst)
        return ev
    }

    private static let chargeText: [String: String] = [
        "solar-beam": "took in sunlight!", "razor-wind": "whipped up a whirlwind!", "skull-bash": "lowered its head!",
        "sky-attack": "is glowing!", "fly": "flew up high!", "dig": "dug a hole!", "dive": "hid underwater!", "bounce": "sprang up!",
    ]
    private static let rechargeMoves: Set<String> = ["hyper-beam", "blast-burn", "hydro-cannon", "frenzy-plant"]
    private static let variablePower: Set<String> = ["flail", "reversal", "return", "frustration", "low-kick", "magnitude",
                                                     "present", "hidden-power", "eruption", "water-spout", "counter", "mirror-coat"]

    private static func damagingMove(_ move: MoveInfo, a: inout BattleMon, side: BattleSide, d: inout BattleMon, dSide: BattleSide,
                                     movedFirst: Bool) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side), dp = prefix(dSide)
        var mv = move

        // OHKO moves
        if move.cat == 9 {
            guard a.level >= d.level, Double.random(in: 0..<100) < Double(30 + a.level - d.level) else {
                return [.say("\(p)\(a.name)'s attack missed!")]
            }
            if TypeChart.multiplier(move.type, against: d.types) == 0 { return [.say("It doesn't affect \(dp)\(d.name)…")] }
            d.hp = 0
            return [.hp(dSide, 0, effectiveness: 1), .say("It's a one-hit KO!")]
        }
        if move.key == "dream-eater" {
            if case .sleep = d.status {} else { return [.say("\(dp)\(d.name) wasn't affected!")] }
        }

        // Fixed damage
        if MoveData.fixedDamage.contains(move.key) {
            if TypeChart.multiplier(move.type, against: d.types) == 0 { return [.say("It doesn't affect \(dp)\(d.name)…")] }
            var amount: Int
            switch move.key {
            case "sonic-boom": amount = 20
            case "dragon-rage": amount = 40
            case "night-shade", "seismic-toss": amount = a.level
            case "super-fang": amount = max(1, d.hp / 2)
            case "psywave": amount = max(1, a.level * Int.random(in: 5...15) / 10)
            default:
                guard d.hp > a.hp else { return [.say("But it failed!")] }
                amount = d.hp - a.hp          // Endeavor
            }
            d.hp = max(0, d.hp - amount)
            return [.hp(dSide, d.hp, effectiveness: 1)]
        }

        // Power
        var power = move.power ?? 0
        switch move.key {
        case "flail", "reversal":
            let x = 48 * a.hp / max(1, a.maxHP)
            power = x <= 1 ? 200 : x <= 4 ? 150 : x <= 9 ? 100 : x <= 16 ? 80 : x <= 32 ? 40 : 20
        case "return": power = max(1, a.friendship * 10 / 25)
        case "frustration": power = max(1, (255 - a.friendship) * 10 / 25)
        case "eruption", "water-spout": power = max(1, 150 * a.hp / max(1, a.maxHP))
        case "low-kick": power = 60
        case "magnitude":
            let m = [(4, 10, 5), (5, 30, 10), (6, 50, 20), (7, 70, 30), (8, 90, 20), (9, 110, 10), (10, 150, 5)]
            var r = Int.random(in: 0..<100)
            var pick = m[0]
            for x in m { if r < x.2 { pick = x; break }; r -= x.2 }
            power = pick.1
            ev.append(.say("Magnitude \(pick.0)!"))
        case "present":
            let r = Int.random(in: 0..<10)
            if r < 2 {
                d.hp = min(d.maxHP, d.hp + d.maxHP / 4)
                return [.hp(dSide, d.hp, effectiveness: nil), .say("\(dp)\(d.name) regained health!")]
            }
            power = r < 6 ? 40 : r < 9 ? 80 : 120
        case "hidden-power":
            // With all IVs at 15 (as PokéWalk uses), Hidden Power is Dark-type with 70 power
            power = 70
            mv = MoveInfo(id: move.id, key: move.key, name: move.name, type: .dark, power: 70, pp: move.pp, accuracy: move.accuracy,
                          priority: 0, target: move.target, status: false, effect: move.effect, chance: 0, cat: 0, ailment: 0,
                          minHits: nil, maxHits: nil, drain: 0, healing: 0, crit: 0, ailmentChance: 0, flinch: 0,
                          statChance: 0, stats: [], sound: move.sound)
        case "facade": if a.status != .none { power *= 2 }
        case "counter", "mirror-coat": return [.say("But it failed!")]
        default: break
        }
        if (move.key == "solar-beam") { power = move.power ?? 120 }

        // Hits
        var hits = 1
        if let lo = move.minHits, let hi = move.maxHits {
            if lo == hi { hits = lo }
            else { let r = Int.random(in: 0..<8); hits = r < 3 ? 2 : r < 6 ? 3 : r < 7 ? 4 : 5 }     // 3/8, 3/8, 1/8, 1/8
        }
        if move.key == "triple-kick" { hits = 3 }

        var total = 0
        var landed = 0
        var lastEff = 1.0
        for h in 0..<hits {
            guard !d.fainted, !a.fainted else { break }
            let critStage = (move.crit > 0 ? 1 : 0) + (a.focused ? 2 : 0)
            let crit = Double.random(in: 0..<1) < critChance(critStage)
            let pw = move.key == "triple-kick" ? 10 * (h + 1) : power
            let dmg = damage(mv, power: pw, from: a, to: d, crit: crit)
            lastEff = dmg.effectiveness
            if dmg.effectiveness == 0 { return ev + [.say("It doesn't affect \(dp)\(d.name)…")] }
            let dealt = min(d.hp, dmg.amount)
            d.hp -= dealt
            total += dealt
            landed += 1
            ev.append(.hp(dSide, d.hp, effectiveness: dmg.effectiveness))
            if crit { ev.append(.say("A critical hit!")) }
        }
        if lastEff >= 2 { ev.append(.say("It's super effective!")) }
        else if lastEff < 1 { ev.append(.say("It's not very effective…")) }
        if hits > 1 { ev.append(.say("Hit \(landed) time\(landed == 1 ? "" : "s")!")) }
        if d.status == .freeze, mv.type == .fire, !d.fainted { d.status = .none; ev += [.say("\(dp)\(d.name) was defrosted!"), .status(dSide)] }

        // Draining and recoil
        if move.drain > 0, total > 0 {
            let heal = max(1, total * move.drain / 100)
            a.hp = min(a.maxHP, a.hp + heal)
            ev += [.hp(side, a.hp, effectiveness: nil), .say("\(dp)\(d.name) had its energy drained!")]
        } else if move.drain < 0, total > 0 {
            let recoil = max(1, total * -move.drain / 100)
            a.hp = max(0, a.hp - recoil)
            ev += [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) is hit with recoil!")]
        }
        if move.key == "self-destruct" || move.key == "explosion" { a.hp = 0; ev.append(.hp(side, 0, effectiveness: nil)) }
        if rechargeMoves.contains(move.key) { a.mustRecharge = true }
        if move.key == "rapid-spin" { a.seeded = false }

        // Secondary effects (only if the target is still standing)
        guard !d.fainted else { return ev }
        if move.flinch > 0, movedFirst, Int.random(in: 0..<100) < move.flinch { d.flinched = true }
        if move.ailment > 0, move.ailmentChance > 0, Int.random(in: 0..<100) < move.ailmentChance {
            ev += inflict(move.ailment, key: move.key, on: &d, side: dSide, quiet: true)
        }
        if !move.stats.isEmpty {
            let chance = move.statChance == 0 ? 100 : move.statChance
            if Int.random(in: 0..<100) < chance {
                if move.cat == 7 || (move.cat == 6 && move.stats.allSatisfy { $0[1] > 0 }) {
                    ev += changeStats(move.stats, on: &a, side: side)
                } else {
                    ev += changeStats(move.stats, on: &d, side: dSide)
                }
            }
        }
        return ev
    }

    private static func statusMove(_ move: MoveInfo, a: inout BattleMon, side: BattleSide, d: inout BattleMon, dSide: BattleSide) -> [BattleEvent] {
        let p = prefix(side)
        switch move.key {
        case "protect", "detect":
            // Each use in a row is half as likely to work
            if Double.random(in: 0..<1) < pow(0.5, Double(a.protectCount)) {
                a.protected = true; a.protectCount += 1
                return [.say("\(p)\(a.name) protected itself!")]
            }
            a.protectCount = 0
            return [.say("But it failed!")]
        case "rest":
            guard a.hp < a.maxHP else { return [.say("But it failed!")] }
            a.status = .sleep(3); a.hp = a.maxHP
            return [.say("\(p)\(a.name) slept and became healthy!"), .hp(side, a.hp, effectiveness: nil), .status(side)]
        case "splash": return [.say("But nothing happened!")]
        case "haze":
            a.stages = [Int](repeating: 0, count: 9); d.stages = [Int](repeating: 0, count: 9)
            return [.say("All stat changes were eliminated!")]
        case "focus-energy":
            a.focused = true
            return [.say("\(p)\(a.name) is getting pumped!")]
        case "belly-drum":
            guard a.hp > a.maxHP / 2 else { return [.say("But it failed!")] }
            a.hp -= a.maxHP / 2; a.stages[2] = 6
            return [.hp(side, a.hp, effectiveness: nil), .stat(side, up: true), .say("\(p)\(a.name) cut its own HP and maximized Attack!")]
        case "yawn":
            guard d.status == .none, d.yawn == 0 else { return [.say("But it failed!")] }
            d.yawn = 2
            return [.say("\(p)\(a.name) made \(prefix(dSide))\(d.name) drowsy!")]
        case "pain-split":
            let avg = (a.hp + d.hp) / 2
            a.hp = min(a.maxHP, avg); d.hp = min(d.maxHP, avg)
            return [.hp(side, a.hp, effectiveness: nil), .hp(dSide, d.hp, effectiveness: nil), .say("The battlers shared their pain!")]
        case "refresh":
            guard [.burn, .paralysis, .poison].contains(a.status) || { if case .toxic = a.status { return true }; return false }()
            else { return [.say("But it failed!")] }
            a.status = .none
            return [.say("\(p)\(a.name)'s status returned to normal!"), .status(side)]
        default: break
        }
        switch move.cat {
        case 1:                                     // causes a status condition
            if move.ailment == 18 {
                guard !d.seeded, !d.types.contains(.grass) else { return [.say("But it failed!")] }
                d.seeded = true
                return [.say("\(prefix(dSide))\(d.name) was seeded!")]
            }
            if move.key == "thunder-wave", TypeChart.multiplier(.electric, against: d.types) == 0 {
                return [.say("It doesn't affect \(prefix(dSide))\(d.name)…")]
            }
            return inflict(move.ailment, key: move.key, on: &d, side: dSide, quiet: false)
        case 2:                                     // raises or lowers stats
            if move.targetsUser || move.stats.allSatisfy({ $0[1] > 0 }) { return changeStats(move.stats, on: &a, side: side, loud: true) }
            return changeStats(move.stats, on: &d, side: dSide, loud: true)
        case 3:                                     // heals
            guard a.hp < a.maxHP else { return [.say("\(p)\(a.name)'s HP is full!")] }
            a.hp = min(a.maxHP, a.hp + max(1, a.maxHP * max(1, move.healing) / 100))
            return [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) regained health!")]
        case 5:                                     // Swagger, Flatter
            var ev = changeStats(move.stats, on: &d, side: dSide, loud: true)
            ev += inflict(6, key: move.key, on: &d, side: dSide, quiet: false)
            return ev
        default:
            return [.say("But it failed!")]
        }
    }

    private static func inflict(_ ailment: Int, key: String, on m: inout BattleMon, side: BattleSide, quiet: Bool) -> [BattleEvent] {
        let p = prefix(side)
        if ailment == 6 {
            guard m.confused == 0 else { return quiet ? [] : [.say("\(p)\(m.name) is already confused!")] }
            m.confused = Int.random(in: 2...5)
            return [.say("\(p)\(m.name) became confused!")]
        }
        guard m.status == .none else { return quiet ? [] : [.say("But it failed!")] }
        switch ailment {
        case 1:
            m.status = .paralysis
            return [.say("\(p)\(m.name) is paralyzed! It may be unable to move!"), .status(side)]
        case 2:
            m.status = .sleep(Int.random(in: 2...5))
            return [.say("\(p)\(m.name) fell asleep!"), .status(side)]
        case 3:
            guard !m.types.contains(.ice) else { return [] }
            m.status = .freeze
            return [.say("\(p)\(m.name) was frozen solid!"), .status(side)]
        case 4:
            guard !m.types.contains(.fire) else { return quiet ? [] : [.say("It doesn't affect \(p)\(m.name)…")] }
            m.status = .burn
            return [.say("\(p)\(m.name) was burned!"), .status(side)]
        case 5:
            guard !m.types.contains(.poison), !m.types.contains(.steel) else { return quiet ? [] : [.say("It doesn't affect \(p)\(m.name)…")] }
            if key == "toxic" || key == "poison-fang" {
                m.status = .toxic(1)
                return [.say("\(p)\(m.name) was badly poisoned!"), .status(side)]
            }
            m.status = .poison
            return [.say("\(p)\(m.name) was poisoned!"), .status(side)]
        default:
            return quiet ? [] : [.say("But it failed!")]
        }
    }

    private static let statNames = [2: "Attack", 3: "Defense", 4: "Sp. Atk", 5: "Sp. Def", 6: "Speed", 7: "accuracy", 8: "evasiveness"]

    private static func changeStats(_ changes: [[Int]], on m: inout BattleMon, side: BattleSide, loud: Bool = false) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side)
        for c in changes where (2...8).contains(c[0]) {
            let (i, n) = (c[0], c[1])
            let name = statNames[i] ?? "stat"
            if (n > 0 && m.stages[i] >= 6) || (n < 0 && m.stages[i] <= -6) {
                if loud { ev.append(.say("\(p)\(m.name)'s \(name) won't go \(n > 0 ? "higher" : "lower")!")) }
                continue
            }
            m.stages[i] = max(-6, min(6, m.stages[i] + n))
            let how = n >= 2 ? "sharply rose" : n > 0 ? "rose" : n <= -2 ? "harshly fell" : "fell"
            ev += [.stat(side, up: n > 0), .say("\(p)\(m.name)'s \(name) \(how)!")]
        }
        return ev
    }

    // MARK: Trainer AI

    /// Picks a move: usually the one that hurts most, sometimes a useful status move or something random.
    static func aiMove(_ a: BattleMon, vs d: BattleMon) -> Int {
        let usable = a.moves.indices.filter { a.moves[$0].pp > 0 }
        guard !usable.isEmpty else { return -1 }
        if a.charging != nil { return 0 }
        func score(_ i: Int) -> Double {
            let m = a.moves[i].info
            if MoveData.fixedDamage.contains(m.key) { return m.key == "super-fang" ? Double(d.hp / 2) : Double(a.level) }
            if let p = m.power, p > 0 {
                var s = Double(damage(m, power: p, from: a, to: d, crit: false, random: false).amount)
                if let acc = m.accuracy { s *= Double(acc) / 100 }
                if rechargeMoves.contains(m.key) || chargeText[m.key] != nil { s *= 0.6 }
                if m.key == "self-destruct" || m.key == "explosion" { s *= a.hp < a.maxHP / 3 ? 1 : 0.1 }
                return s
            }
            // status moves: useful once
            if m.cat == 1 { return d.status == .none && d.confused == 0 ? Double(d.maxHP) * 0.15 : 0 }
            if m.cat == 3 { return a.hp < a.maxHP / 2 ? Double(a.maxHP) * 0.3 : 0 }
            if m.cat == 2 { return m.stats.contains { abs(a.stages[$0[0]]) >= 2 } ? 1 : Double(d.maxHP) * 0.08 }
            return 1
        }
        if Double.random(in: 0..<1) < 0.12 { return usable.randomElement()! }
        return usable.max { score($0) < score($1) }!
    }
}
