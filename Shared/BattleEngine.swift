import Foundation

// MARK: - Gen 3 battle engine
//
// Moves, learnsets and effects as in Pokémon Emerald (data rolled back to Emerald values from PokéAPI:
// Shared/Resources/moves.json, made by tools/gen_moves.py). Damage uses the Gen 3 formula with the physical/special
// split decided by the move's type, stat stages, critical hits (×2), weather, Reflect/Light Screen, abilities,
// status conditions, confusion, flinching, multi-hit, draining, recoil, charging, recharging, locked-in moves and
// the "unique" moves (Substitute, Encore, Disable, Metronome, Transform, Future Sight…).

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
    let ailment: Int        // 1 par, 2 slp, 3 frz, 4 brn, 5 psn, 6 confusion, 7 infatuation, 8 trap, 18 leech seed…
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
    var contact = false
    var soundMove = false

    /// Gen 3: physical or special depends only on the type.
    var physical: Bool { MoveData.physicalTypes.contains(type) }
    var targetsUser: Bool { target == 7 }

    init(id: Int, key: String, name: String, type: PokeType, power: Int?, pp: Int, accuracy: Int?, priority: Int, target: Int,
         status: Bool, effect: Int, chance: Int, cat: Int, ailment: Int, minHits: Int?, maxHits: Int?, drain: Int, healing: Int,
         crit: Int, ailmentChance: Int, flinch: Int, statChance: Int, stats: [[Int]], sound: String?, contact: Bool = false, soundMove: Bool = false) {
        self.id = id; self.key = key; self.name = name; self.type = type; self.power = power; self.pp = pp
        self.accuracy = accuracy; self.priority = priority; self.target = target; self.status = status; self.effect = effect
        self.chance = chance; self.cat = cat; self.ailment = ailment; self.minHits = minHits; self.maxHits = maxHits
        self.drain = drain; self.healing = healing; self.crit = crit; self.ailmentChance = ailmentChance; self.flinch = flinch
        self.statChance = statChance; self.stats = stats; self.sound = sound; self.contact = contact; self.soundMove = soundMove
    }

    /// A copy with another type and power (Hidden Power, Weather Ball).
    func with(type t: PokeType, power p: Int) -> MoveInfo {
        MoveInfo(id: id, key: key, name: name, type: t, power: p, pp: pp, accuracy: accuracy, priority: priority, target: target,
                 status: false, effect: effect, chance: 0, cat: 0, ailment: 0, minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 crit: 0, ailmentChance: 0, flinch: 0, statChance: 0, stats: [], sound: sound, contact: contact, soundMove: soundMove)
    }

    /// Tolerant decoding: an unknown type (like Curse's "???") becomes Ghost rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        type = PokeType(rawValue: (try? c.decode(String.self, forKey: .type)) ?? "") ?? .ghost
        power = try? c.decodeIfPresent(Int.self, forKey: .power)
        pp = (try? c.decode(Int.self, forKey: .pp)) ?? 10
        accuracy = try? c.decodeIfPresent(Int.self, forKey: .accuracy)
        priority = (try? c.decode(Int.self, forKey: .priority)) ?? 0
        target = (try? c.decode(Int.self, forKey: .target)) ?? 10
        status = (try? c.decode(Bool.self, forKey: .status)) ?? false
        effect = (try? c.decode(Int.self, forKey: .effect)) ?? 0
        chance = (try? c.decode(Int.self, forKey: .chance)) ?? 0
        cat = (try? c.decode(Int.self, forKey: .cat)) ?? 0
        ailment = (try? c.decode(Int.self, forKey: .ailment)) ?? 0
        minHits = try? c.decodeIfPresent(Int.self, forKey: .minHits)
        maxHits = try? c.decodeIfPresent(Int.self, forKey: .maxHits)
        drain = (try? c.decode(Int.self, forKey: .drain)) ?? 0
        healing = (try? c.decode(Int.self, forKey: .healing)) ?? 0
        crit = (try? c.decode(Int.self, forKey: .crit)) ?? 0
        ailmentChance = (try? c.decode(Int.self, forKey: .ailmentChance)) ?? 0
        flinch = (try? c.decode(Int.self, forKey: .flinch)) ?? 0
        statChance = (try? c.decode(Int.self, forKey: .statChance)) ?? 0
        stats = (try? c.decode([[Int]].self, forKey: .stats)) ?? []
        sound = try? c.decodeIfPresent(String.self, forKey: .sound)
        contact = (try? c.decode(Bool.self, forKey: .contact)) ?? false
        soundMove = (try? c.decode(Bool.self, forKey: .soundMove)) ?? false
    }
}

enum MoveData {
    private struct File: Codable {
        let moves: [MoveInfo]
        let learnsets: [String: [[Int]]]
        let gen3Types: [String: [String]]
        let weights: [String: Int]?
    }

    static let physicalTypes: Set<PokeType> = [.normal, .fighting, .flying, .poison, .ground, .rock, .bug, .ghost, .steel]

    private static let file: File? = {
        let url = Bundle.main.url(forResource: "moves", withExtension: "json")
            ?? Bundle.allBundles.lazy.compactMap { $0.url(forResource: "moves", withExtension: "json") }.first
        guard let url, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: d)
    }()
    private static let byID: [Int: MoveInfo] = Dictionary(uniqueKeysWithValues: (file?.moves ?? []).map { ($0.id, $0) })
    private static let byKey: [String: MoveInfo] = Dictionary(uniqueKeysWithValues: (file?.moves ?? []).map { ($0.key, $0) })

    static var loaded: Bool { file != nil }
    static var all: [MoveInfo] { file?.moves ?? [] }
    static func info(_ id: Int) -> MoveInfo? { byID[id] }
    static func info(_ key: String) -> MoveInfo? { byKey[key] }
    static let struggle = MoveInfo(id: 165, key: "struggle", name: "Struggle", type: .normal, power: 50, pp: 1, accuracy: nil,
                                   priority: 0, target: 10, status: false, effect: 255, chance: 0, cat: 0, ailment: 0,
                                   minHits: nil, maxHits: nil, drain: -25, healing: 0, crit: 0, ailmentChance: 0, flinch: 0,
                                   statChance: 0, stats: [], sound: "033-0_tackle.wav", contact: true)

    /// Level-up moves in Emerald: (level, move id).
    static func learnset(_ species: Int) -> [(Int, Int)] {
        (file?.learnsets[String(species)] ?? []).map { ($0[0], $0[1]) }
    }

    /// Types as they were in Gen 3 (no Fairy type yet).
    static func types(_ species: Int) -> [PokeType] {
        file?.gen3Types[String(species)]?.compactMap(PokeType.init(rawValue:)) ?? Dex.species(species).types
    }

    /// Weight in kg (for Low Kick).
    static func weight(_ species: Int) -> Double { Double(file?.weights?[String(species)] ?? 300) / 10 }

    private static func pool(_ species: Int, _ level: Int) -> [Int] {
        Array(Set(learnset(species).filter { $0.0 <= level }.map(\.1))).sorted()
    }

    static func doesDamage(_ id: Int) -> Bool {
        guard let m = info(id) else { return false }
        return !m.status && ((m.power ?? 0) > 0 || fixedDamage.contains(m.key) || variablePower.contains(m.key))
    }

    /// Four random moves from everything it could have learned by levelling up to `level` (at least one that does damage).
    static func randomSet<R: RandomNumberGenerator>(species: Int, level: Int, using rng: inout R) -> [Int] {
        let pool = pool(species, level)
        guard !pool.isEmpty else { return [33] }       // Tackle
        var picks = Array(pool.shuffled(using: &rng).prefix(4))
        let damaging = pool.filter(doesDamage)
        if !picks.contains(where: { damaging.contains($0) }), let d = damaging.randomElement(using: &rng) {
            picks[picks.count - 1] = d
        }
        return picks
    }

    /// A trainer's set: its strongest attacks (one per type, so it has coverage) and something useful.
    static func trainerSet<R: RandomNumberGenerator>(species: Int, level: Int, types: [PokeType], using rng: inout R) -> [Int] {
        let pool = pool(species, level)
        guard !pool.isEmpty else { return [33] }
        let weak: Set<String> = ["hyper-beam", "blast-burn", "hydro-cannon", "frenzy-plant", "solar-beam", "sky-attack", "razor-wind",
                                 "skull-bash", "self-destruct", "explosion", "focus-punch", "dream-eater", "snore", "bide",
                                 "counter", "mirror-coat", "fake-out", "spit-up", "false-swipe", "rage"]
        func score(_ id: Int) -> Double {
            guard let m = info(id) else { return 0 }
            if fixedDamage.contains(m.key) { return Double(level) * 0.9 }
            var p = Double(m.power ?? 0)
            if variablePower.contains(m.key) { p = 60 }
            if types.contains(m.type) { p *= 1.5 }
            p *= Double(m.accuracy ?? 100) / 100
            if let lo = m.minHits, let hi = m.maxHits { p *= Double(lo + hi) / 2 * 0.9 }
            if weak.contains(m.key) { p *= 0.4 }
            return p
        }
        let attacks = pool.filter(doesDamage).sorted { score($0) > score($1) }
        var set: [Int] = []
        var typesSeen = Set<PokeType>()
        for id in attacks where set.count < 3 {
            if let t = info(id)?.type, !typesSeen.contains(t) { set.append(id); typesSeen.insert(t) }
        }
        let useful: Set<String> = ["swords-dance", "dragon-dance", "calm-mind", "bulk-up", "agility", "thunder-wave", "toxic",
                                   "will-o-wisp", "sleep-powder", "spore", "hypnosis", "recover", "soft-boiled", "milk-drink",
                                   "slack-off", "synthesis", "moonlight", "morning-sun", "protect", "leech-seed", "reflect",
                                   "light-screen", "stun-spore", "confuse-ray", "growth", "curse", "amnesia", "iron-defense",
                                   "rest", "substitute", "double-team", "minimize", "haze", "screech", "sing", "lovely-kiss",
                                   "glare", "sweet-kiss", "tail-glow", "cosmic-power", "belly-drum", "spikes", "wish"]
        if let s = pool.filter({ useful.contains(info($0)?.key ?? "") }).randomElement(using: &rng) { set.append(s) }
        for id in attacks where set.count < 4 && !set.contains(id) { set.append(id) }
        let pointless: Set<String> = ["teleport", "splash", "sweet-scent", "odor-sleuth", "foresight", "mud-sport", "water-sport",
                                      "helping-hand", "follow-me", "recycle", "snatch", "assist", "trick", "imprison", "grudge",
                                      "baton-pass", "conversion", "rage", "camouflage", "skill-swap", "role-play"]
        for id in pool.shuffled(using: &rng) where set.count < 4 && !set.contains(id) && !pointless.contains(info(id)?.key ?? "") { set.append(id) }
        return Array(set.prefix(4))
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
    static let variablePower: Set<String> = ["flail", "reversal", "return", "frustration", "low-kick", "magnitude",
                                             "present", "hidden-power", "eruption", "water-spout", "counter", "mirror-coat",
                                             "spit-up", "bide", "beat-up", "weather-ball"]

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

    init(id: Int, pp: Int? = nil) {
        self.id = id
        let p = MoveData.info(id)?.pp ?? 10
        self.pp = pp ?? p; maxPP = pp ?? p
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
    var isSleep: Bool { if case .sleep = self { return true }; return false }
    var isPoison: Bool { if case .toxic = self { return true }; return self == .poison }
}

struct BattleMon: Identifiable, Hashable {
    let id = UUID()
    let ownedID: UUID?
    var speciesID: Int
    let name: String
    let level: Int
    let isShiny: Bool
    let gender: Gender
    var types: [PokeType]
    var stats: [Int]          // hp, atk, def, spa, spd, spe
    var hp: Int
    var moves: [BattleMove]
    var ability: String?
    var friendship = 70
    var status: StatusCondition = .none
    var expFraction = 0.0       // how far into this level (for the Exp bar)

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
    var lastMove: Int?
    var locked: Int?                                // Thrash, Rollout, Uproar, Bide keep going by themselves
    var lockTurns = 0
    var lockCount = 0
    var furyCutter = 0
    var disabledMove: Int?
    var disabledTurns = 0
    var encoreMove: Int?
    var encoreTurns = 0
    var tauntTurns = 0
    var substitute = 0
    var trapped = false
    var lockOn = false
    var enduring = false
    var destinyBond = false
    var magicCoat = false
    var stockpile = 0
    var bideDamage = 0
    var hitThisTurn = 0
    var hitPhysical = false
    var turnsOut = 0
    var flashFire = false
    var cursed = false
    var nightmare = false
    var transformed = false
    var truantSkip = false
    var defenseCurl = false
    var minimized = false
    var charged = false
    var ingrained = false
    var infatuated = false
    var tormented = false
    var perish = 0

    var maxHP: Int { stats[0] }
    var fainted: Bool { hp <= 0 }

    init(speciesID: Int, level: Int, nature: String, isShiny: Bool = false, name: String? = nil, gender: Gender? = nil,
         ownedID: UUID? = nil, friendship: Int = 70, ability: String? = nil, iv: Int = 15, ev: Int = 0, trainer: Bool = false) {
        var rng = SystemRandomNumberGenerator()
        self.init(speciesID: speciesID, level: level, nature: nature, isShiny: isShiny, name: name, gender: gender,
                  ownedID: ownedID, friendship: friendship, ability: ability, iv: iv, ev: ev, trainer: trainer, rng: &rng)
    }

    init<R: RandomNumberGenerator>(speciesID: Int, level: Int, nature: String, isShiny: Bool = false, name: String? = nil,
                                   gender: Gender? = nil, ownedID: UUID? = nil, friendship: Int = 70, ability: String? = nil,
                                   iv: Int = 15, ev: Int = 0, trainer: Bool = false, rng: inout R) {
        let sp = Dex.species(speciesID)
        let base = SpeciesData.stats(speciesID)
        let ni = Dex.natures.firstIndex(of: nature) ?? 0
        let up = ni / 5 + 1, down = ni % 5 + 1
        let map = [1, 2, 5, 3, 4]       // nature order Atk, Def, Spe, SpA, SpD → stat indices
        let evTerm = min(252, ev) / 4
        var st: [Int] = []
        for i in 0..<6 {
            if i == 0 {
                st.append(speciesID == 292 ? 1 : (2 * base[0] + iv + evTerm) * level / 100 + level + 10)     // Shedinja: 1 HP
            } else {
                var v = Double((2 * base[i] + iv + evTerm) * level / 100 + 5)
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
        let t = MoveData.types(speciesID)
        self.types = t
        self.stats = st
        self.hp = st[0]
        self.friendship = friendship
        self.ability = ability ?? Self.gen3Ability(speciesID, using: &rng)
        self.moves = (trainer ? MoveData.trainerSet(species: speciesID, level: level, types: t, using: &rng)
                              : MoveData.randomSet(species: speciesID, level: level, using: &rng)).map { BattleMove(id: $0) }
    }

    init(owned m: OwnedPokemon) {
        self.init(speciesID: m.speciesID, level: m.level, nature: m.nature, isShiny: m.isShiny, name: m.name,
                  gender: m.gender, ownedID: m.id, friendship: m.friendship, ability: m.abilityName)
        expFraction = m.species.growth.progress(exp: m.exp)
    }

    /// One of the species' abilities that existed in Gen 3.
    static func gen3Ability<R: RandomNumberGenerator>(_ species: Int, using rng: inout R) -> String? {
        guard species >= 1, species <= AbilityData.species.count else { return nil }
        let list = AbilityData.species[species - 1]
        let old = list.filter { $0 <= 76 }
        return (old.isEmpty ? list : old).randomElement(using: &rng).flatMap { AbilityData.names[$0] }
    }

    /// Clears everything that goes away when it's switched out.
    mutating func switchedOut() {
        stages = [Int](repeating: 0, count: 9)
        confused = 0; flinched = false; charging = nil; invulnerable = false; mustRecharge = false
        protected = false; protectCount = 0; seeded = false; focused = false; yawn = 0
        lastMove = nil; locked = nil; lockTurns = 0; lockCount = 0; furyCutter = 0
        disabledMove = nil; disabledTurns = 0; encoreMove = nil; encoreTurns = 0; tauntTurns = 0
        substitute = 0; trapped = false; lockOn = false; enduring = false; destinyBond = false; magicCoat = false
        stockpile = 0; bideDamage = 0; hitThisTurn = 0; turnsOut = 0; flashFire = false; cursed = false; nightmare = false
        truantSkip = false; defenseCurl = false; minimized = false; charged = false; ingrained = false
        infatuated = false; tormented = false; perish = 0
        types = MoveData.types(speciesID)
        if case .toxic = status { status = .toxic(1) }
    }

    var hasUsableMove: Bool { moves.indices.contains { canSelect($0) } }

    /// Whether the move in slot i can be chosen this turn (PP, Disable, Taunt, Encore).
    func canSelect(_ i: Int) -> Bool {
        guard moves.indices.contains(i), moves[i].pp > 0 else { return false }
        let m = moves[i]
        if m.id == disabledMove { return false }
        if tauntTurns > 0, m.info.status { return false }
        if tormented, m.id == lastMove { return false }
        if let e = encoreMove, e != m.id, moves.contains(where: { $0.id == e && $0.pp > 0 }) { return false }
        return true
    }

    /// Something keeps it moving by itself (charging, recharging, Thrash, Rollout, Bide, Uproar).
    var actsAlone: Bool { charging != nil || mustRecharge || locked != nil }

    func has(_ ab: String) -> Bool { ability == ab }
}

enum BattleSide {
    case mine, foe
    var other: BattleSide { self == .mine ? .foe : .mine }
}

/// Weather, screens, Spikes, Future Sight, Wish.
struct BattleField: Hashable {
    enum Weather: Hashable { case none, rain, sun, sand, hail }
    struct Side: Hashable {
        var reflect = 0, lightScreen = 0, mist = 0, safeguard = 0, spikes = 0
        var futureTurns = 0, futureDamage = 0, wishTurns = 0, wishHP = 0
    }
    var weather: Weather = .none
    var weatherTurns = 0                // 0 = lasts until changed (abilities)
    var mine = Side()
    var foe = Side()
    var mudSport = false
    var waterSport = false

    subscript(side: BattleSide) -> Side {
        get { side == .mine ? mine : foe }
        set { if side == .mine { mine = newValue } else { foe = newValue } }
    }
}

/// What happened, in order, for the battle screen to show and sound out.
enum BattleEvent {
    case say(String)
    case uses(BattleSide, MoveInfo)                       // play the move's sound and animation
    case hp(BattleSide, Int, effectiveness: Double?)      // new HP; effectiveness set when it was hit by a move
    case stat(BattleSide, up: Bool)
    case status(BattleSide)
    case forceSwitch(BattleSide)                          // Roar / Whirlwind: drag out another Pokémon
    case transform(BattleSide, Int)                       // its sprite becomes this species
}

enum BattleEngine {
    // MARK: Numbers

    static func stageMultiplier(_ s: Int) -> Double {
        s >= 0 ? Double(2 + s) / 2 : 2 / Double(2 - s)
    }

    static func stat(_ m: BattleMon, _ i: Int, ignoreUp: Bool = false, ignoreDown: Bool = false, field: BattleField? = nil) -> Double {
        var st = m.stages[i + 1]
        if ignoreUp { st = min(0, st) }
        if ignoreDown { st = max(0, st) }
        var v = Double(m.stats[i]) * stageMultiplier(st)
        if i == 1, m.has("Huge Power") || m.has("Pure Power") { v *= 2 }
        if i == 1, m.has("Hustle") { v *= 1.5 }
        if i == 1, m.has("Guts"), m.status != .none { v *= 1.5 }
        if i == 2, m.has("Marvel Scale"), m.status != .none { v *= 1.5 }
        if i == 5 {
            if m.status == .paralysis { v /= 4 }
            if let f = field {
                if m.has("Swift Swim"), f.weather == .rain { v *= 2 }
                if m.has("Chlorophyll"), f.weather == .sun { v *= 2 }
            }
        }
        return v
    }

    static func speed(_ m: BattleMon, _ f: BattleField) -> Double { stat(m, 5, field: f) }

    /// Gen 3 accuracy/evasion table (−6…+6).
    static func accuracyMultiplier(_ s: Int) -> Double {
        let t: [Double] = [33, 36, 43, 50, 60, 75, 100, 133, 166, 200, 250, 266, 300]
        return t[max(-6, min(6, s)) + 6] / 100
    }

    static func critChance(_ stage: Int) -> Double { [1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 3, 1.0 / 2][min(4, max(0, stage))] }

    struct Damage { var amount: Int; var effectiveness: Double; var crit: Bool }

    static func effectiveness(_ move: MoveInfo, on d: BattleMon) -> Double {
        if ["struggle", "beat-up", "future-sight", "doom-desire"].contains(move.key) { return 1 }
        return TypeChart.multiplier(move.type, against: d.types)
    }

    /// The Gen 3 damage formula.
    static func damage(_ move: MoveInfo, power: Int, from a: BattleMon, to d: BattleMon, crit: Bool, field: BattleField,
                       defenderSide: BattleSide, random: Bool = true) -> Damage {
        let eff = effectiveness(move, on: d)
        if eff == 0 { return Damage(amount: 0, effectiveness: 0, crit: false) }
        let physical = move.physical
        var atk = stat(a, physical ? 1 : 3, ignoreDown: crit)
        var def = stat(d, physical ? 2 : 4, ignoreUp: crit)
        if d.has("Thick Fat"), move.type == .fire || move.type == .ice { atk /= 2 }
        if move.key == "self-destruct" || move.key == "explosion" { def /= 2 }
        var p = Double(power)
        let lowHP = a.hp * 3 <= a.maxHP
        let pinch = (a.has("Overgrow") && move.type == .grass) || (a.has("Blaze") && move.type == .fire)
            || (a.has("Torrent") && move.type == .water) || (a.has("Swarm") && move.type == .bug)
        if lowHP, pinch { p *= 1.5 }
        if a.flashFire, move.type == .fire { p *= 1.5 }
        if a.charged, move.type == .electric { p *= 2 }
        if field.mudSport, move.type == .electric { p /= 2 }
        if field.waterSport, move.type == .fire { p /= 2 }
        let lvTerm: Double = floor(2 * Double(a.level) / 5 + 2)
        let top: Double = floor(lvTerm * p * atk / max(1, def))
        var base: Double = floor(top / 50)
        if physical, a.status == .burn, !a.has("Guts") { base = floor(base / 2) }
        if !crit {
            if physical, field[defenderSide].reflect > 0 { base = floor(base / 2) }
            if !physical, field[defenderSide].lightScreen > 0 { base = floor(base / 2) }
        }
        switch field.weather {
        case .rain:
            if move.type == .water { base = floor(base * 1.5) }
            if move.type == .fire { base = floor(base / 2) }
        case .sun:
            if move.type == .fire { base = floor(base * 1.5) }
            if move.type == .water { base = floor(base / 2) }
        default: break
        }
        if move.key == "solar-beam", field.weather == .rain || field.weather == .sand || field.weather == .hail { base = floor(base / 2) }
        base += 2
        if crit { base *= 2 }
        if a.types.contains(move.type), move.key != "struggle", move.key != "beat-up" { base = floor(base * 1.5) }
        base = floor(base * eff)
        let roll = random ? Double(Int.random(in: 85...100)) / 100 : 0.92
        return Damage(amount: max(1, Int(base * roll)), effectiveness: eff, crit: crit)
    }

    // MARK: Switching in

    /// Spikes, Intimidate, Trace and weather abilities when a Pokémon comes out.
    static func switchIn(_ m: inout BattleMon, side: BattleSide, other: inout BattleMon, field: inout BattleField) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side)
        let layers = min(3, field[side].spikes)
        if layers > 0, !m.types.contains(.flying), !m.has("Levitate") {
            let dmg = max(1, m.maxHP / [1, 8, 6, 4][layers])
            m.hp = max(0, m.hp - dmg)
            ev += [.hp(side, m.hp, effectiveness: nil), .say("\(p)\(m.name) is hurt by spikes!")]
        }
        if m.has("Trace"), let ab = other.ability, !other.fainted {
            m.ability = ab
            ev.append(.say("\(p)\(m.name) traced \(prefix(side.other))\(other.name)'s \(ab)!"))
        }
        if m.has("Intimidate"), !other.fainted {
            if other.has("Clear Body") || other.has("White Smoke") || other.has("Hyper Cutter") || other.substitute > 0 {
                ev.append(.say("\(prefix(side.other))\(other.name)'s \(other.ability ?? "ability") prevents its Attack from being lowered!"))
            } else if other.stages[2] > -6 {
                other.stages[2] -= 1
                ev += [.stat(side.other, up: false), .say("\(p)\(m.name)'s Intimidate cut \(prefix(side.other))\(other.name)'s Attack!")]
            }
        }
        let weather: [String: (BattleField.Weather, String)] = [
            "Drizzle": (.rain, "made it rain"), "Drought": (.sun, "intensified the sun's rays"),
            "Sand Stream": (.sand, "whipped up a sandstorm"),
        ]
        if let ab = m.ability, let w = weather[ab] {
            field.weather = w.0; field.weatherTurns = 0
            ev.append(.say("\(p)\(m.name)'s \(ab) \(w.1)!"))
        }
        return ev
    }

    // MARK: A turn

    /// Plays a whole turn: who goes first, both moves, then end-of-turn effects. `myMove`/`foeMove` are indices
    /// into each Pokémon's moves (nil = it's switching in, so it doesn't move; -1 = Struggle).
    static func turn(mine: inout BattleMon, foe: inout BattleMon, field: inout BattleField, myMove: Int?, foeMove: Int?) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        mine.protected = false; foe.protected = false
        mine.enduring = false; foe.enduring = false
        mine.magicCoat = false; foe.magicCoat = false
        mine.hitThisTurn = 0; foe.hitThisTurn = 0
        mine.destinyBond = false; foe.destinyBond = false
        let mi = myMove.map { planned($0, of: mine) }, fi = foeMove.map { planned($0, of: foe) }
        let mp = mi?.priority ?? 0, fp = fi?.priority ?? 0
        let meFirst: Bool
        if myMove == nil { meFirst = false }
        else if foeMove == nil { meFirst = true }
        else if mp != fp { meFirst = mp > fp }
        else { let a = speed(mine, field), b = speed(foe, field); meFirst = a != b ? a > b : Bool.random() }

        // Focus Punch tightens its focus before anyone moves
        if mi?.key == "focus-punch", mine.locked == nil, mine.charging == nil { ev.append(.say("\(mine.name) is tightening its focus!")) }
        if fi?.key == "focus-punch", foe.locked == nil, foe.charging == nil { ev.append(.say("The foe's \(foe.name) is tightening its focus!")) }

        func act(_ side: BattleSide, first: Bool) {
            if side == .mine, let i = myMove, !mine.fainted {
                ev += use(i, by: &mine, side: .mine, on: &foe, field: &field, movedFirst: first)
            } else if side == .foe, let i = foeMove, !foe.fainted {
                ev += use(i, by: &foe, side: .foe, on: &mine, field: &field, movedFirst: first)
            }
        }
        if meFirst { act(.mine, first: true); act(.foe, first: false) } else { act(.foe, first: true); act(.mine, first: false) }
        mine.flinched = false; foe.flinched = false

        // Destiny Bond takes the attacker down too
        if mine.fainted, mine.destinyBond, !foe.fainted, mine.hitThisTurn > 0 {
            foe.hp = 0
            ev += [.say("\(mine.name) took its attacker down with it!"), .hp(.foe, 0, effectiveness: nil)]
        }
        if foe.fainted, foe.destinyBond, !mine.fainted, foe.hitThisTurn > 0 {
            mine.hp = 0
            ev += [.say("The foe's \(foe.name) took its attacker down with it!"), .hp(.mine, 0, effectiveness: nil)]
        }

        ev += endOfTurn(mine: &mine, foe: &foe, field: &field)
        return ev
    }

    /// The move it will use (for turn order): the charging/locked/encored move or the chosen one.
    private static func planned(_ i: Int, of m: BattleMon) -> MoveInfo {
        if let c = m.charging ?? m.locked { return MoveData.info(c) ?? MoveData.struggle }
        if let e = m.encoreMove, let x = MoveData.info(e) { return x }
        return i >= 0 && i < m.moves.count ? m.moves[i].info : MoveData.struggle
    }

    static func prefix(_ side: BattleSide) -> String { side == .foe ? "The foe's " : "" }

    private static func endOfTurn(mine: inout BattleMon, foe: inout BattleMon, field: inout BattleField) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        // Future Sight / Doom Desire land, Wish comes true, screens wear off
        for side in [BattleSide.mine, .foe] {
            var f = field[side]
            if f.futureTurns > 0 {
                f.futureTurns -= 1
                if f.futureTurns == 0 {
                    if side == .mine, !mine.fainted {
                        mine.hp = max(0, mine.hp - f.futureDamage)
                        ev += [.say("\(mine.name) took the attack!"), .hp(.mine, mine.hp, effectiveness: 1)]
                    } else if side == .foe, !foe.fainted {
                        foe.hp = max(0, foe.hp - f.futureDamage)
                        ev += [.say("The foe's \(foe.name) took the attack!"), .hp(.foe, foe.hp, effectiveness: 1)]
                    }
                }
            }
            if f.wishTurns > 0 {
                f.wishTurns -= 1
                if f.wishTurns == 0 {
                    if side == .mine, !mine.fainted, mine.hp < mine.maxHP {
                        mine.hp = min(mine.maxHP, mine.hp + f.wishHP)
                        ev += [.say("The wish came true!"), .hp(.mine, mine.hp, effectiveness: nil)]
                    } else if side == .foe, !foe.fainted, foe.hp < foe.maxHP {
                        foe.hp = min(foe.maxHP, foe.hp + f.wishHP)
                        ev += [.say("The foe's wish came true!"), .hp(.foe, foe.hp, effectiveness: nil)]
                    }
                }
            }
            let owner = side == .mine ? "Your team's" : "The foe's"
            if f.reflect > 0 { f.reflect -= 1; if f.reflect == 0 { ev.append(.say("\(owner) Reflect wore off!")) } }
            if f.lightScreen > 0 { f.lightScreen -= 1; if f.lightScreen == 0 { ev.append(.say("\(owner) Light Screen wore off!")) } }
            if f.mist > 0 { f.mist -= 1; if f.mist == 0 { ev.append(.say("\(owner) Mist wore off!")) } }
            if f.safeguard > 0 { f.safeguard -= 1; if f.safeguard == 0 { ev.append(.say("\(owner) Safeguard wore off!")) } }
            field[side] = f
        }
        // Weather
        if field.weather != .none {
            if field.weatherTurns > 0 {
                field.weatherTurns -= 1
                if field.weatherTurns == 0 {
                    let msg: [BattleField.Weather: String] = [.rain: "The rain stopped.", .sun: "The sunlight faded.",
                                                              .sand: "The sandstorm subsided.", .hail: "The hail stopped."]
                    ev.append(.say(msg[field.weather] ?? ""))
                    field.weather = .none
                }
            }
            if field.weather == .sand || field.weather == .hail {
                let immune: Set<PokeType> = field.weather == .sand ? [.rock, .ground, .steel] : [.ice]
                let what = field.weather == .sand ? "sandstorm" : "hail"
                if !mine.fainted, !mine.invulnerable, !mine.types.contains(where: immune.contains) {
                    mine.hp = max(0, mine.hp - max(1, mine.maxHP / 16))
                    ev += [.say("\(mine.name) is buffeted by the \(what)!"), .hp(.mine, mine.hp, effectiveness: nil)]
                }
                if !foe.fainted, !foe.invulnerable, !foe.types.contains(where: immune.contains) {
                    foe.hp = max(0, foe.hp - max(1, foe.maxHP / 16))
                    ev += [.say("The foe's \(foe.name) is buffeted by the \(what)!"), .hp(.foe, foe.hp, effectiveness: nil)]
                }
            }
        }
        ev += endOfTurn(&mine, side: .mine, other: &foe, field: field)
        ev += endOfTurn(&foe, side: .foe, other: &mine, field: field)
        return ev
    }

    private static func endOfTurn(_ m: inout BattleMon, side: BattleSide, other: inout BattleMon, field: BattleField) -> [BattleEvent] {
        guard !m.fainted else { return [] }
        var ev: [BattleEvent] = []
        let p = prefix(side)
        m.turnsOut += 1
        if m.ingrained, m.hp < m.maxHP {
            m.hp = min(m.maxHP, m.hp + max(1, m.maxHP / 16))
            ev += [.say("\(p)\(m.name) absorbed nutrients with its roots!"), .hp(side, m.hp, effectiveness: nil)]
        }
        if m.has("Rain Dish"), field.weather == .rain, m.hp < m.maxHP {
            m.hp = min(m.maxHP, m.hp + max(1, m.maxHP / 16))
            ev += [.say("\(p)\(m.name)'s Rain Dish restored its HP a little!"), .hp(side, m.hp, effectiveness: nil)]
        }
        if m.has("Shed Skin"), m.status != .none, Int.random(in: 0..<3) == 0 {
            m.status = .none
            ev += [.say("\(p)\(m.name)'s Shed Skin cured its status problem!"), .status(side)]
        }
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
            if m.has("Liquid Ooze") { other.hp = max(0, other.hp - drain) } else { other.hp = min(other.maxHP, other.hp + drain) }
            ev += [.say("\(p)\(m.name)'s health is sapped by Leech Seed!"), .hp(side, m.hp, effectiveness: nil),
                   .hp(side.other, other.hp, effectiveness: nil)]
        }
        if m.nightmare, m.status.isSleep, !m.fainted {
            m.hp = max(0, m.hp - max(1, m.maxHP / 4))
            ev += [.say("\(p)\(m.name) is locked in a nightmare!"), .hp(side, m.hp, effectiveness: nil)]
        }
        if m.cursed, !m.fainted {
            m.hp = max(0, m.hp - max(1, m.maxHP / 4))
            ev += [.say("\(p)\(m.name) is afflicted by the curse!"), .hp(side, m.hp, effectiveness: nil)]
        }
        if m.yawn > 0 {
            m.yawn -= 1
            if m.yawn == 0, m.status == .none, !m.fainted, !m.has("Insomnia"), !m.has("Vital Spirit") {
                m.status = .sleep(Int.random(in: 2...5))
                ev += [.say("\(p)\(m.name) fell asleep!"), .status(side)]
            }
        }
        if m.has("Speed Boost"), !m.fainted, m.turnsOut > 1, m.stages[6] < 6 {
            m.stages[6] += 1
            ev += [.stat(side, up: true), .say("\(p)\(m.name)'s Speed Boost raised its Speed!")]
        }
        if m.disabledTurns > 0 {
            m.disabledTurns -= 1
            if m.disabledTurns == 0 { m.disabledMove = nil; ev.append(.say("\(p)\(m.name) is no longer disabled!")) }
        }
        if m.encoreTurns > 0 {
            m.encoreTurns -= 1
            if m.encoreTurns == 0 { m.encoreMove = nil; ev.append(.say("\(p)\(m.name)'s encore ended!")) }
        }
        if m.tauntTurns > 0 { m.tauntTurns -= 1 }
        if m.perish > 0 {
            m.perish -= 1
            ev.append(.say("\(p)\(m.name)'s perish count fell to \(m.perish)!"))
            if m.perish == 0 { m.hp = 0; ev.append(.hp(side, 0, effectiveness: nil)) }
        }
        return ev
    }

    // MARK: Using a move

    private static let chargeText: [String: String] = [
        "solar-beam": "took in sunlight!", "razor-wind": "whipped up a whirlwind!", "skull-bash": "lowered its head!",
        "sky-attack": "is glowing!", "fly": "flew up high!", "dig": "dug a hole!", "dive": "hid underwater!", "bounce": "sprang up!",
    ]
    private static let rechargeMoves: Set<String> = ["hyper-beam", "blast-burn", "hydro-cannon", "frenzy-plant"]
    private static let rampage: Set<String> = ["thrash", "petal-dance", "outrage", "uproar"]
    /// Moves that only affect the user or the field, so they don't need to reach the target.
    private static let noTarget: Set<String> = [
        "haze", "sandstorm", "rain-dance", "sunny-day", "hail", "mud-sport", "water-sport", "mist", "light-screen",
        "reflect", "safeguard", "spikes", "wish", "stockpile", "swallow", "rest", "substitute", "protect", "detect",
        "endure", "focus-energy", "belly-drum", "ingrain", "charge", "camouflage", "conversion", "follow-me",
        "helping-hand", "magic-coat", "snatch", "recycle", "refresh", "heal-bell", "aromatherapy", "teleport",
        "destiny-bond", "grudge", "baton-pass", "minimize", "defense-curl", "imprison", "doom-desire", "future-sight",
        "splash", "bide", "stockpile", "perish-song", "metronome", "sleep-talk", "nature-power", "assist", "curse",
    ]

    private static func use(_ index: Int, by a: inout BattleMon, side: BattleSide, on d: inout BattleMon, field: inout BattleField,
                            movedFirst: Bool) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side)
        let dSide = side.other

        // Can it move at all?
        if a.mustRecharge {
            a.mustRecharge = false
            return [.say("\(p)\(a.name) must recharge!")]
        }
        if a.has("Truant") {
            if a.truantSkip { a.truantSkip = false; return [.say("\(p)\(a.name) is loafing around!")] }
            a.truantSkip = true
        }
        // The move it means to use
        var chosen: MoveInfo
        var slot: Int? = nil
        if let c = a.charging, let m = MoveData.info(c) { chosen = m }
        else if let l = a.locked, let m = MoveData.info(l) { chosen = m }
        else if let e = a.encoreMove, let s = a.moves.firstIndex(where: { $0.id == e && $0.pp > 0 }) { chosen = a.moves[s].info; slot = s }
        else if index >= 0, index < a.moves.count, a.moves[index].pp > 0 { chosen = a.moves[index].info; slot = index }
        else { chosen = MoveData.struggle }

        switch a.status {
        case .sleep(let n):
            let left = n - (a.has("Early Bird") ? 2 : 1)
            if left > 0 {
                a.status = .sleep(left)
                if chosen.key == "snore" || chosen.key == "sleep-talk" {
                    ev.append(.say("\(p)\(a.name) is fast asleep."))
                } else {
                    a.locked = nil; a.charging = nil; a.invulnerable = false
                    return [.say("\(p)\(a.name) is fast asleep.")]
                }
            } else {
                a.status = .none; a.nightmare = false
                ev += [.say("\(p)\(a.name) woke up!"), .status(side)]
            }
        case .freeze:
            if ["flame-wheel", "sacred-fire"].contains(chosen.key) || Int.random(in: 0..<5) == 0 {
                a.status = .none
                ev += [.say("\(p)\(a.name) was defrosted!"), .status(side)]
            } else { return [.say("\(p)\(a.name) is frozen solid!")] }
        default: break
        }
        if !a.status.isSleep, chosen.key == "snore" || chosen.key == "sleep-talk" {
            if let s = slot { a.moves[s].pp -= 1 }
            return ev + [.say("\(p)\(a.name) used \(chosen.name)!"), .say("But it failed!")]
        }
        if a.flinched { a.flinched = false; a.locked = nil; return ev + [.say("\(p)\(a.name) flinched!")] }
        if chosen.id == a.disabledMove { return ev + [.say("\(p)\(a.name)'s \(chosen.name) is disabled!")] }
        if a.tauntTurns > 0, chosen.status { return ev + [.say("\(p)\(a.name) can't use \(chosen.name) after the taunt!")] }
        if a.tormented, chosen.id == a.lastMove, a.locked == nil, a.charging == nil {
            return ev + [.say("\(p)\(a.name) can't use the same move twice in a row due to the torment!")]
        }
        if a.infatuated {
            ev.append(.say("\(p)\(a.name) is in love with the foe!"))
            if Bool.random() { a.locked = nil; a.charging = nil; a.invulnerable = false; return ev + [.say("\(p)\(a.name) is immobilized by love!")] }
        }
        if a.confused > 0 {
            a.confused -= 1
            if a.confused == 0 {
                ev.append(.say("\(p)\(a.name) snapped out of confusion!"))
            } else {
                ev.append(.say("\(p)\(a.name) is confused!"))
                if Bool.random() {
                    // 40-power typeless physical hit on itself
                    let atk = stat(a, 1), def = stat(a, 2)
                    let lv: Double = floor(2 * Double(a.level) / 5 + 2)
                    let raw: Double = floor(lv * 40 * atk / max(1, def)) / 50 + 2
                    let roll: Double = Double(Int.random(in: 85...100)) / 100
                    let dmg = max(1, Int(raw * roll))
                    a.hp = max(0, a.hp - dmg)
                    a.charging = nil; a.invulnerable = false; a.locked = nil
                    return ev + [.say("It hurt itself in its confusion!"), .hp(side, a.hp, effectiveness: 1)]
                }
            }
        }
        if a.status == .paralysis, Int.random(in: 0..<4) == 0 {
            a.charging = nil; a.invulnerable = false; a.locked = nil
            return ev + [.say("\(p)\(a.name) is paralyzed! It can't move!")]
        }

        // Pay the PP (Pressure takes 2); the first turn of a two-turn move
        var move = chosen
        if a.charging != nil {
            a.charging = nil; a.invulnerable = false
        } else if a.locked != nil {
            // carries on without PP
        } else if let s = slot {
            a.moves[s].pp = max(0, a.moves[s].pp - (d.has("Pressure") ? 2 : 1))
            if let charge = chargeText[move.key], !(move.key == "solar-beam" && field.weather == .sun) {
                a.charging = move.id
                a.invulnerable = ["fly", "dig", "dive", "bounce"].contains(move.key)
                if move.key == "skull-bash", a.stages[3] < 6 { a.stages[3] += 1 }
                a.lastMove = move.id
                return ev + [.uses(side, move), .say("\(p)\(a.name) \(charge)")]
            }
        } else {
            ev.append(.say("\(p)\(a.name) has no moves left!"))
        }

        if move.key == "focus-punch", a.hitThisTurn > 0 {
            return ev + [.say("\(p)\(a.name) lost its focus and couldn't move!")]
        }

        ev.append(.say("\(p)\(a.name) used \(move.name)!"))

        // Moves that call other moves
        switch move.key {
        case "metronome":
            let banned: Set<String> = ["metronome", "struggle", "sketch", "mimic", "counter", "mirror-coat", "protect", "detect",
                                       "endure", "destiny-bond", "sleep-talk", "thief", "covet", "trick", "follow-me", "focus-punch",
                                       "helping-hand", "snatch", "assist", "transform"]
            if let m = MoveData.all.filter({ !banned.contains($0.key) }).randomElement() {
                ev += [.uses(side, move), .say("Waggling a finger let it use \(m.name)!")]
                move = m
            }
        case "mirror-move":
            guard let l = d.lastMove, let m = MoveData.info(l), !["mirror-move", "struggle"].contains(m.key) else {
                return ev + [.uses(side, move), .say("But it failed!")]
            }
            move = m
            ev.append(.say("\(p)\(a.name) used \(m.name)!"))
        case "sleep-talk":
            let options = a.moves.map(\.info).filter { !["sleep-talk", "bide", "focus-punch", "uproar"].contains($0.key) && chargeText[$0.key] == nil }
            guard let m = options.randomElement() else { return ev + [.say("But it failed!")] }
            move = m
            ev.append(.say("\(p)\(a.name) used \(m.name)!"))
        case "nature-power":
            if let m = MoveData.info("swift") { move = m; ev.append(.say("Nature Power turned into Swift!")) }
        default: break
        }
        a.lastMove = move.id
        ev.append(.uses(side, move))
        if move.key != "fury-cutter" { a.furyCutter = 0 }

        // Whether it reaches the target
        let selfTargeted = move.targetsUser || noTarget.contains(move.key)
            || (move.status && move.cat == 2 && move.stats.allSatisfy { $0[1] > 0 })
        if !selfTargeted {
            if d.fainted { a.locked = nil; return ev + [.say("But there was no target…")] }
            if d.protected { a.locked = nil; return ev + [.say("\(prefix(dSide))\(d.name) protected itself!")] }
            // Magic Coat bounces status moves back
            if d.magicCoat, move.status, [1, 2, 5].contains(move.cat) {
                ev.append(.say("\(prefix(dSide))\(d.name) bounced the \(move.name) back!"))
                ev += statusMove(move, a: &d, side: dSide, d: &a, dSide: side, field: &field)
                return ev
            }
            let reaches: [String: Set<String>] = ["fly": ["gust", "twister", "thunder", "sky-uppercut"],
                                                  "bounce": ["gust", "twister", "thunder", "sky-uppercut"],
                                                  "dig": ["earthquake", "magnitude", "fissure"], "dive": ["surf", "whirlpool"]]
            if d.invulnerable, let c = d.charging, let ck = MoveData.info(c)?.key, !(reaches[ck]?.contains(move.key) ?? false), !a.lockOn {
                a.locked = nil
                return ev + [.say("\(p)\(a.name)'s attack missed!")]
            }
            // Accuracy
            if var acc = move.accuracy.map(Double.init), move.cat != 9, !a.lockOn {
                if move.key == "thunder" { if field.weather == .rain { acc = 1000 } else if field.weather == .sun { acc = 50 } }
                var chance = acc * accuracyMultiplier(a.stages[7] - d.stages[8])
                if a.has("Compound Eyes") { chance *= 1.3 }
                if a.has("Hustle"), move.physical, !move.status { chance *= 0.8 }
                if d.has("Sand Veil"), field.weather == .sand { chance *= 0.8 }
                if Double.random(in: 0..<100) >= chance {
                    a.locked = nil; a.lockCount = 0
                    if ["jump-kick", "hi-jump-kick", "high-jump-kick"].contains(move.key) {
                        // Gen 3: crashes for half the damage it would have done
                        let would = damage(move, power: move.power ?? 70, from: a, to: d, crit: false, field: field, defenderSide: dSide).amount
                        let crash = max(1, min(d.hp, would) / 2)
                        a.hp = max(0, a.hp - crash)
                        return ev + [.say("\(p)\(a.name)'s attack missed!"), .say("\(p)\(a.name) kept going and crashed!"), .hp(side, a.hp, effectiveness: nil)]
                    }
                    return ev + [.say("\(p)\(a.name)'s attack missed!")]
                }
            }
            a.lockOn = false
            // Abilities that block it
            if move.soundMove, d.has("Soundproof") { return ev + [.say("\(prefix(dSide))\(d.name)'s Soundproof blocks \(move.name)!")] }
            if !move.status || move.key == "thunder-wave" {
                if move.type == .ground, d.has("Levitate") {
                    a.locked = nil
                    return ev + [.say("\(prefix(dSide))\(d.name) makes Ground moves miss with Levitate!")]
                }
                if move.type == .electric, d.has("Volt Absorb") {
                    d.hp = min(d.maxHP, d.hp + max(1, d.maxHP / 4))
                    return ev + [.hp(dSide, d.hp, effectiveness: nil), .say("\(prefix(dSide))\(d.name)'s Volt Absorb restored its HP!")]
                }
                if move.type == .water, d.has("Water Absorb") {
                    d.hp = min(d.maxHP, d.hp + max(1, d.maxHP / 4))
                    return ev + [.hp(dSide, d.hp, effectiveness: nil), .say("\(prefix(dSide))\(d.name)'s Water Absorb restored its HP!")]
                }
                if move.type == .fire, d.has("Flash Fire"), d.status != .freeze {
                    d.flashFire = true
                    return ev + [.say("\(prefix(dSide))\(d.name)'s Flash Fire raised the power of its Fire moves!")]
                }
                if d.has("Wonder Guard"), !move.status, effectiveness(move, on: d) < 2,
                   !["struggle", "beat-up", "future-sight", "doom-desire"].contains(move.key) {
                    return ev + [.say("\(prefix(dSide))\(d.name)'s Wonder Guard evades the attack!")]
                }
            }
        }

        if move.status || (move.power == nil && !MoveData.fixedDamage.contains(move.key) && move.cat != 9 && !MoveData.variablePower.contains(move.key)) {
            ev += statusMove(move, a: &a, side: side, d: &d, dSide: dSide, field: &field)
            if !["protect", "detect", "endure"].contains(move.key) { a.protectCount = 0 }
            return ev
        }
        a.protectCount = 0
        ev += damagingMove(move, a: &a, side: side, d: &d, dSide: dSide, field: &field, movedFirst: movedFirst)
        return ev
    }

    // MARK: Damaging moves

    private static func damagingMove(_ move: MoveInfo, a: inout BattleMon, side: BattleSide, d: inout BattleMon, dSide: BattleSide,
                                     field: inout BattleField, movedFirst: Bool) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side), dp = prefix(dSide)
        var mv = move

        // OHKO moves
        if move.cat == 9 {
            if d.has("Sturdy") { return [.say("\(dp)\(d.name) was protected by Sturdy!")] }
            guard a.level >= d.level, Double.random(in: 0..<100) < Double(30 + a.level - d.level) else {
                return [.say("\(p)\(a.name)'s attack missed!")]
            }
            if effectiveness(move, on: d) == 0 { return [.say("It doesn't affect \(dp)\(d.name)…")] }
            if d.substitute > 0 { d.substitute = 0; return [.say("\(dp)\(d.name)'s substitute faded!")] }
            d.hp = 0
            return [.hp(dSide, 0, effectiveness: 1), .say("It's a one-hit KO!")]
        }
        if move.key == "dream-eater", !d.status.isSleep { return [.say("\(dp)\(d.name) wasn't affected!")] }
        if move.key == "fake-out", a.turnsOut > 0 { return [.say("But it failed!")] }
        if move.key == "explosion" || move.key == "self-destruct", d.has("Damp") || a.has("Damp") {
            return [.say("The Damp ability prevents \(move.name)!")]
        }

        // Fixed damage
        if MoveData.fixedDamage.contains(move.key) {
            if effectiveness(move, on: d) == 0 { return [.say("It doesn't affect \(dp)\(d.name)…")] }
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
            return hit(&d, side: dSide, amount: amount, effectiveness: 1, physical: move.physical, move: move)
        }
        // Counter / Mirror Coat: twice the damage taken this turn
        if move.key == "counter" || move.key == "mirror-coat" {
            let right = move.key == "counter" ? a.hitPhysical : !a.hitPhysical
            guard a.hitThisTurn > 0, right, effectiveness(move, on: d) > 0 else { return [.say("But it failed!")] }
            return hit(&d, side: dSide, amount: a.hitThisTurn * 2, effectiveness: 1, physical: move.physical, move: move)
        }
        // Bide: stores up damage for two turns, then hits back double
        if move.key == "bide" {
            if a.locked == nil { a.locked = move.id; a.lockTurns = 2; a.bideDamage = 0; return [.say("\(p)\(a.name) is storing energy!")] }
            a.lockTurns -= 1
            if a.lockTurns > 0 { return [.say("\(p)\(a.name) is storing energy!")] }
            a.locked = nil
            ev.append(.say("\(p)\(a.name) unleashed energy!"))
            guard a.bideDamage > 0, !d.fainted else { return ev + [.say("But it failed!")] }
            return ev + hit(&d, side: dSide, amount: a.bideDamage * 2, effectiveness: 1, physical: true, move: move)
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
        case "low-kick":
            let w = MoveData.weight(d.speciesID)
            power = w < 10 ? 20 : w < 25 ? 40 : w < 50 ? 60 : w < 100 ? 80 : w < 200 ? 100 : 120
        case "magnitude":
            let m = [(4, 10, 5), (5, 30, 10), (6, 50, 20), (7, 70, 30), (8, 90, 20), (9, 110, 10), (10, 150, 5)]
            var r = Int.random(in: 0..<100)
            var pick = m[0]
            for x in m { if r < x.2 { pick = x; break }; r -= x.2 }
            power = pick.1
            ev.append(.say("Magnitude \(pick.0)!"))
            if d.invulnerable, let c = d.charging, MoveData.info(c)?.key == "dig" { power *= 2 }
        case "present":
            let r = Int.random(in: 0..<10)
            if r < 2 {
                d.hp = min(d.maxHP, d.hp + d.maxHP / 4)
                return [.hp(dSide, d.hp, effectiveness: nil), .say("\(dp)\(d.name) regained health!")]
            }
            power = r < 6 ? 40 : r < 9 ? 80 : 120
        case "hidden-power":
            // With all IVs at 15, Hidden Power is Dark-type with 70 power
            power = 70
            mv = move.with(type: .dark, power: 70)
        case "weather-ball":
            let t: [BattleField.Weather: PokeType] = [.rain: .water, .sun: .fire, .sand: .rock, .hail: .ice]
            if let wt = t[field.weather] { power = 100; mv = move.with(type: wt, power: 100) } else { power = 50 }
        case "spit-up":
            guard a.stockpile > 0 else { return [.say("But it failed to spit up a thing!")] }
            power = 100 * a.stockpile
            a.stockpile = 0
        case "beat-up": power = 10
        case "facade": if a.status != .none { power *= 2 }
        case "smelling-salts": if d.status == .paralysis { power *= 2 }
        case "revenge": if a.hitThisTurn > 0 { power *= 2 }
        case "rollout", "ice-ball":
            if a.locked == nil { a.locked = move.id; a.lockCount = 0 }
            power = (move.power ?? 30) << a.lockCount
            if a.defenseCurl { power *= 2 }
            a.lockCount += 1
            if a.lockCount >= 5 { a.locked = nil; a.lockCount = 0 }
        case "fury-cutter":
            power = min(160, (move.power ?? 10) << min(4, a.furyCutter))
            a.furyCutter += 1
        case "stomp": if d.minimized { power *= 2 }
        case "gust", "twister":
            if d.invulnerable, let c = d.charging, ["fly", "bounce"].contains(MoveData.info(c)?.key ?? "") { power *= 2 }
        case "earthquake":
            if d.invulnerable, let c = d.charging, MoveData.info(c)?.key == "dig" { power *= 2 }
        case "surf":
            if d.invulnerable, let c = d.charging, MoveData.info(c)?.key == "dive" { power *= 2 }
        default: break
        }
        // Thrash, Petal Dance, Outrage, Uproar keep going for a few turns
        if rampage.contains(move.key), a.locked == nil {
            a.locked = move.id
            a.lockTurns = move.key == "uproar" ? Int.random(in: 2...5) : Int.random(in: 2...3)
        }

        // Hits
        var hits = 1
        if let lo = move.minHits, let hi = move.maxHits {
            if lo == hi { hits = lo }
            else { let r = Int.random(in: 0..<8); hits = r < 3 ? 2 : r < 6 ? 3 : r < 7 ? 4 : 5 }     // 3/8, 3/8, 1/8, 1/8
        }
        if move.key == "triple-kick" { hits = 3 }
        if move.key == "beat-up" { hits = Int.random(in: 2...4) }

        var total = 0
        var landed = 0
        var lastEff = 1.0
        let subBefore = d.substitute > 0
        for h in 0..<hits {
            guard !d.fainted, !a.fainted else { break }
            let critStage = (move.crit > 0 ? 1 : 0) + (a.focused ? 2 : 0)
            let crit = !d.has("Battle Armor") && !d.has("Shell Armor") && Double.random(in: 0..<1) < critChance(critStage)
            let pw = move.key == "triple-kick" ? 10 * (h + 1) : power
            let dmg = damage(mv, power: pw, from: a, to: d, crit: crit, field: field, defenderSide: dSide)
            lastEff = dmg.effectiveness
            if dmg.effectiveness == 0 { a.locked = nil; return ev + [.say("It doesn't affect \(dp)\(d.name)…")] }
            var amount = dmg.amount
            if move.key == "false-swipe" { amount = min(amount, max(0, d.hp - 1)) }
            let before = d.hp, subHP = d.substitute
            ev += hit(&d, side: dSide, amount: amount, effectiveness: dmg.effectiveness, physical: mv.physical, move: mv)
            total += max(0, before - d.hp) + max(0, subHP - d.substitute)
            landed += 1
            if crit { ev.append(.say("A critical hit!")) }
            if mv.contact, !a.fainted, !subBefore {
                ev += contactAbility(defender: d, dSide: dSide, attacker: &a, aSide: side)
            }
        }
        if lastEff >= 2 { ev.append(.say("It's super effective!")) }
        else if lastEff < 1 { ev.append(.say("It's not very effective…")) }
        if hits > 1 { ev.append(.say("Hit \(landed) time\(landed == 1 ? "" : "s")!")) }
        if d.status == .freeze, mv.type == .fire, !d.fainted { d.status = .none; ev += [.say("\(dp)\(d.name) was defrosted!"), .status(dSide)] }

        // Draining and recoil
        if move.drain > 0, total > 0 {
            let heal = max(1, total * move.drain / 100)
            if d.has("Liquid Ooze") {
                a.hp = max(0, a.hp - heal)
                ev += [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) sucked up the liquid ooze!")]
            } else if a.hp < a.maxHP {
                a.hp = min(a.maxHP, a.hp + heal)
                ev += [.hp(side, a.hp, effectiveness: nil), .say("\(dp)\(d.name) had its energy drained!")]
            }
        } else if move.drain < 0, total > 0, !a.has("Rock Head") || move.key == "struggle" {
            let recoil = max(1, total * -move.drain / 100)
            a.hp = max(0, a.hp - recoil)
            ev += [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) is hit with recoil!")]
        }
        if move.key == "self-destruct" || move.key == "explosion" { a.hp = 0; ev.append(.hp(side, 0, effectiveness: nil)) }
        if rechargeMoves.contains(move.key) { a.mustRecharge = true }
        if move.key == "rapid-spin", total > 0 { a.seeded = false; a.trapped = false; field[side].spikes = 0 }
        if move.key == "smelling-salts", d.status == .paralysis, !d.fainted, !subBefore {
            d.status = .none; ev += [.say("\(dp)\(d.name) was cured of paralysis!"), .status(dSide)]
        }
        if move.key == "brick-break", field[dSide].reflect > 0 || field[dSide].lightScreen > 0 {
            field[dSide].reflect = 0; field[dSide].lightScreen = 0
            ev.append(.say("It shattered the barrier!"))
        }
        if move.key == "pay-day" { ev.append(.say("Coins scattered everywhere!")) }
        if move.key == "knock-off", !subBefore, !d.fainted { ev.append(.say("\(p)\(a.name) knocked off \(dp)\(d.name)'s item!")) }

        // Rampage ends in confusion
        if rampage.contains(move.key), a.locked == move.id {
            a.lockTurns -= 1
            if a.lockTurns <= 0 {
                a.locked = nil
                if move.key == "uproar" { ev.append(.say("\(p)\(a.name) calmed down.")) }
                else if a.confused == 0, !a.has("Own Tempo") {
                    a.confused = Int.random(in: 2...5)
                    ev.append(.say("\(p)\(a.name) became confused due to fatigue!"))
                }
            }
        }

        // Secondary effects (only on a real hit, not on a substitute, and only if the target is still standing)
        guard !d.fainted, total > 0, !subBefore else { return ev }
        let serene = a.has("Serene Grace") ? 2 : 1
        let shielded = d.has("Shield Dust")
        if move.flinch > 0, movedFirst, !d.has("Inner Focus"), !shielded, Int.random(in: 0..<100) < move.flinch * serene { d.flinched = true }
        if move.key == "fake-out", movedFirst, !d.has("Inner Focus") { d.flinched = true }
        var ailment = move.ailment, chance = move.ailmentChance
        if move.key == "tri-attack" { ailment = [1, 3, 4].randomElement()!; chance = 20 }
        if move.key == "secret-power" { ailment = 1; chance = 30 }
        if ailment > 0, chance > 0, !shielded, Int.random(in: 0..<100) < chance * serene {
            ev += inflict(ailment, key: move.key, on: &d, side: dSide, quiet: true, field: field)
        }
        if !move.stats.isEmpty {
            let c = (move.statChance == 0 ? 100 : move.statChance) * serene
            if Int.random(in: 0..<100) < c {
                if move.cat == 7 {
                    ev += changeStats(move.stats, on: &a, side: side, field: field, byOpponent: false)
                } else if !shielded {
                    ev += changeStats(move.stats, on: &d, side: dSide, field: field, byOpponent: true)
                }
            }
        }
        return ev
    }

    /// Damage to `d` (through a Substitute or Endure), remembering it for Counter, Mirror Coat, Bide, Focus Punch.
    private static func hit(_ d: inout BattleMon, side: BattleSide, amount: Int, effectiveness: Double, physical: Bool,
                            move: MoveInfo) -> [BattleEvent] {
        if d.substitute > 0, !move.soundMove {
            d.substitute = max(0, d.substitute - amount)
            var ev: [BattleEvent] = [.say("The substitute took damage for \(prefix(side))\(d.name)!")]
            if d.substitute == 0 { ev.append(.say("\(prefix(side))\(d.name)'s substitute faded!")) }
            return ev
        }
        var dealt = min(d.hp, amount)
        var extra: [BattleEvent] = []
        if dealt >= d.hp, d.enduring {
            dealt = d.hp - 1
            extra.append(.say("\(prefix(side))\(d.name) endured the hit!"))
        }
        d.hp -= dealt
        d.hitThisTurn += dealt
        d.hitPhysical = physical
        if let l = d.locked, MoveData.info(l)?.key == "bide" { d.bideDamage += dealt }
        return [.hp(side, d.hp, effectiveness: effectiveness)] + extra
    }

    private static func contactAbility(defender d: BattleMon, dSide: BattleSide, attacker a: inout BattleMon, aSide: BattleSide) -> [BattleEvent] {
        let dp = prefix(dSide)
        guard let ab = d.ability else { return [] }
        if ab == "Rough Skin" {
            a.hp = max(0, a.hp - max(1, a.maxHP / 16))
            return [.say("\(prefix(aSide))\(a.name) was hurt by \(dp)\(d.name)'s Rough Skin!"), .hp(aSide, a.hp, effectiveness: nil)]
        }
        guard Int.random(in: 0..<100) < 30 else { return [] }
        let ailment: Int
        switch ab {
        case "Static": ailment = 1
        case "Flame Body": ailment = 4
        case "Poison Point": ailment = 5
        case "Cute Charm":
            guard a.gender != d.gender, a.gender != .genderless, d.gender != .genderless, !a.infatuated, !a.has("Oblivious") else { return [] }
            a.infatuated = true
            return [.say("\(dp)\(d.name)'s Cute Charm infatuated \(prefix(aSide))\(a.name)!")]
        case "Effect Spore":
            guard Int.random(in: 0..<3) == 0 else { return [] }           // 10% overall
            ailment = [1, 2, 5].randomElement()!
        default: return []
        }
        let ev = inflict(ailment, key: "", on: &a, side: aSide, quiet: true, field: nil)
        return ev.isEmpty ? [] : [.say("\(dp)\(d.name)'s \(ab)!")] + ev
    }

    // MARK: Status moves

    private static func statusMove(_ move: MoveInfo, a: inout BattleMon, side: BattleSide, d: inout BattleMon, dSide: BattleSide,
                                   field: inout BattleField) -> [BattleEvent] {
        let p = prefix(side), dp = prefix(dSide)
        let fail: [BattleEvent] = [.say("But it failed!")]
        // A substitute blocks most status moves aimed at it
        let aimedAtFoe = !(move.targetsUser || noTarget.contains(move.key) || (move.cat == 2 && move.stats.allSatisfy { $0[1] > 0 }))
        if aimedAtFoe, d.substitute > 0, [1, 2, 5].contains(move.cat) { return fail }
        switch move.key {
        case "protect", "detect", "endure":
            // Each use in a row is half as likely to work
            if Double.random(in: 0..<1) < pow(0.5, Double(a.protectCount)) {
                a.protectCount += 1
                if move.key == "endure" { a.enduring = true; return [.say("\(p)\(a.name) braced itself!")] }
                a.protected = true
                return [.say("\(p)\(a.name) protected itself!")]
            }
            a.protectCount = 0
            return fail
        case "rest":
            guard a.hp < a.maxHP, !a.has("Insomnia"), !a.has("Vital Spirit") else { return fail }
            a.status = .sleep(3); a.hp = a.maxHP
            return [.say("\(p)\(a.name) slept and became healthy!"), .hp(side, a.hp, effectiveness: nil), .status(side)]
        case "splash": return [.say("But nothing happened!")]
        case "teleport": return fail
        case "roar", "whirlwind":
            if d.has("Suction Cups") || d.ingrained { return [.say("\(dp)\(d.name) anchored itself!")] }
            return [.forceSwitch(dSide)]
        case "haze":
            a.stages = [Int](repeating: 0, count: 9); d.stages = [Int](repeating: 0, count: 9)
            return [.say("All stat changes were eliminated!")]
        case "focus-energy":
            guard !a.focused else { return fail }
            a.focused = true
            return [.say("\(p)\(a.name) is getting pumped!")]
        case "belly-drum":
            guard a.hp > a.maxHP / 2, a.stages[2] < 6 else { return fail }
            a.hp -= a.maxHP / 2; a.stages[2] = 6
            return [.hp(side, a.hp, effectiveness: nil), .stat(side, up: true), .say("\(p)\(a.name) cut its own HP and maximized Attack!")]
        case "yawn":
            guard d.status == .none, d.yawn == 0, field[dSide].safeguard == 0 else { return fail }
            d.yawn = 2
            return [.say("\(p)\(a.name) made \(dp)\(d.name) drowsy!")]
        case "pain-split":
            let avg = (a.hp + d.hp) / 2
            a.hp = min(a.maxHP, avg); d.hp = min(d.maxHP, avg)
            return [.hp(side, a.hp, effectiveness: nil), .hp(dSide, d.hp, effectiveness: nil), .say("The battlers shared their pain!")]
        case "refresh":
            guard a.status == .burn || a.status == .paralysis || a.status.isPoison else { return fail }
            a.status = .none
            return [.say("\(p)\(a.name)'s status returned to normal!"), .status(side)]
        case "heal-bell", "aromatherapy":
            a.status = .none
            return [.say(move.key == "heal-bell" ? "A bell chimed!" : "A soothing aroma wafted through the area!"), .status(side)]
        case "substitute":
            if a.substitute > 0 { return [.say("\(p)\(a.name) already has a substitute!")] }
            guard a.hp > a.maxHP / 4 else { return [.say("It was too weak to make a substitute!")] }
            a.hp -= a.maxHP / 4
            a.substitute = a.maxHP / 4 + 1
            return [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) made a substitute!")]
        case "disable":
            guard let l = d.lastMove, d.disabledMove == nil, d.moves.contains(where: { $0.id == l && $0.pp > 0 }) else { return fail }
            d.disabledMove = l; d.disabledTurns = Int.random(in: 2...5)
            return [.say("\(dp)\(d.name)'s \(MoveData.info(l)?.name ?? "move") was disabled!")]
        case "encore":
            guard let l = d.lastMove, d.encoreMove == nil, !["encore", "mirror-move", "transform", "struggle"].contains(MoveData.info(l)?.key ?? ""),
                  d.moves.contains(where: { $0.id == l && $0.pp > 0 }) else { return fail }
            d.encoreMove = l; d.encoreTurns = Int.random(in: 2...6)
            return [.say("\(dp)\(d.name) received an encore!")]
        case "taunt":
            guard d.tauntTurns == 0 else { return fail }
            d.tauntTurns = 2
            return [.say("\(dp)\(d.name) fell for the taunt!")]
        case "spite":
            guard let l = d.lastMove, let i = d.moves.firstIndex(where: { $0.id == l && $0.pp > 0 }) else { return fail }
            let n = min(d.moves[i].pp, Int.random(in: 2...5))
            d.moves[i].pp -= n
            return [.say("It reduced the PP of \(dp)\(d.name)'s \(d.moves[i].name) by \(n)!")]
        case "mimic", "sketch":
            guard let l = d.lastMove, let m = MoveData.info(l), !["mimic", "sketch", "struggle", "metronome", "transform"].contains(m.key),
                  !a.moves.contains(where: { $0.id == l }), let i = a.moves.firstIndex(where: { $0.id == move.id }) else { return fail }
            a.moves[i] = BattleMove(id: l, pp: move.key == "mimic" ? 5 : nil)
            return [.say("\(p)\(a.name) learned \(m.name)!")]
        case "transform":
            guard !d.transformed, !a.transformed, d.substitute == 0 else { return fail }
            a.transformed = true
            a.speciesID = d.speciesID
            a.types = d.types
            for i in 1..<6 { a.stats[i] = d.stats[i] }
            a.stages = d.stages
            a.ability = d.ability
            a.moves = d.moves.map { BattleMove(id: $0.id, pp: 5) }
            return [.transform(side, d.speciesID), .say("\(p)\(a.name) transformed into \(d.name)!")]
        case "conversion":
            let options = a.moves.map(\.type).filter { !a.types.contains($0) }
            guard let t = options.randomElement() else { return fail }
            a.types = [t]
            return [.say("\(p)\(a.name) transformed into the \(t.displayName) type!")]
        case "conversion-2":
            guard let l = d.lastMove, let m = MoveData.info(l) else { return fail }
            let resist = PokeType.allCases.filter { $0 != .fairy && TypeChart.multiplier(m.type, against: [$0]) < 1 }
            guard let t = resist.randomElement() else { return fail }
            a.types = [t]
            return [.say("\(p)\(a.name) transformed into the \(t.displayName) type!")]
        case "camouflage":
            a.types = [.normal]
            return [.say("\(p)\(a.name) transformed into the Normal type!")]
        case "spider-web", "mean-look", "block":
            guard !d.trapped else { return fail }
            d.trapped = true
            return [.say("\(dp)\(d.name) can no longer escape!")]
        case "mind-reader", "lock-on":
            a.lockOn = true
            return [.say("\(p)\(a.name) took aim at \(dp)\(d.name)!")]
        case "curse":
            if a.types.contains(.ghost) {
                guard !d.cursed, !d.fainted else { return fail }
                a.hp = max(0, a.hp - a.maxHP / 2)
                d.cursed = true
                return [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) cut its own HP and laid a curse on \(dp)\(d.name)!")]
            }
            return changeStats([[6, -1], [2, 1], [3, 1]], on: &a, side: side, field: field, byOpponent: false, loud: true)
        case "destiny-bond":
            a.destinyBond = true
            return [.say("\(p)\(a.name) is trying to take its foe down with it!")]
        case "psych-up":
            a.stages = d.stages
            return [.say("\(p)\(a.name) copied \(dp)\(d.name)'s stat changes!")]
        case "future-sight", "doom-desire":
            guard field[dSide].futureTurns == 0 else { return fail }
            let pw = move.key == "doom-desire" ? 120 : 80
            let dmg = damage(move.with(type: move.type, power: pw), power: pw, from: a, to: d, crit: false, field: field, defenderSide: dSide)
            field[dSide].futureTurns = 3
            field[dSide].futureDamage = dmg.amount
            return [.say(move.key == "future-sight" ? "\(p)\(a.name) foresaw an attack!" : "\(p)\(a.name) chose Doom Desire as its destiny!")]
        case "stockpile":
            guard a.stockpile < 3 else { return [.say("\(p)\(a.name) can't stockpile any more!")] }
            a.stockpile += 1
            return [.say("\(p)\(a.name) stockpiled \(a.stockpile)!")]
        case "swallow":
            guard a.stockpile > 0 else { return [.say("But it failed to swallow a thing!")] }
            let heal = a.maxHP * [0, 25, 50, 100][min(3, a.stockpile)] / 100
            a.stockpile = 0
            a.hp = min(a.maxHP, a.hp + heal)
            return [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) regained health!")]
        case "memento":
            a.hp = 0
            var ev: [BattleEvent] = [.hp(side, 0, effectiveness: nil)]
            ev += changeStats([[2, -2], [4, -2]], on: &d, side: dSide, field: field, byOpponent: true, loud: true)
            return ev
        case "wish":
            guard field[side].wishTurns == 0 else { return fail }
            field[side].wishTurns = 2; field[side].wishHP = a.maxHP / 2
            return [.say("\(p)\(a.name) made a wish!")]
        case "magic-coat":
            a.magicCoat = true
            return [.say("\(p)\(a.name) shrouded itself with Magic Coat!")]
        case "ingrain":
            guard !a.ingrained else { return fail }
            a.ingrained = true; a.trapped = true
            return [.say("\(p)\(a.name) planted its roots!")]
        case "charge":
            a.charged = true
            return [.say("\(p)\(a.name) began charging power!")]
        case "defense-curl":
            a.defenseCurl = true
            return changeStats(move.stats.isEmpty ? [[3, 1]] : move.stats, on: &a, side: side, field: field, byOpponent: false, loud: true)
        case "minimize":
            a.minimized = true
            return changeStats(move.stats.isEmpty ? [[8, 1]] : move.stats, on: &a, side: side, field: field, byOpponent: false, loud: true)
        case "nightmare":
            guard d.status.isSleep, !d.nightmare else { return fail }
            d.nightmare = true
            return [.say("\(dp)\(d.name) began having a nightmare!")]
        case "role-play":
            guard let ab = d.ability, ab != "Wonder Guard" else { return fail }
            a.ability = ab
            return [.say("\(p)\(a.name) copied \(dp)\(d.name)'s \(ab)!")]
        case "skill-swap":
            guard let x = a.ability, let y = d.ability, x != "Wonder Guard", y != "Wonder Guard" else { return fail }
            a.ability = y; d.ability = x
            return [.say("\(p)\(a.name) swapped abilities with its target!")]
        case "rain-dance", "sunny-day", "sandstorm", "hail":
            let w: BattleField.Weather = move.key == "rain-dance" ? .rain : move.key == "sunny-day" ? .sun : move.key == "sandstorm" ? .sand : .hail
            guard field.weather != w else { return fail }
            field.weather = w; field.weatherTurns = 5
            let msg: [BattleField.Weather: String] = [.rain: "It started to rain!", .sun: "The sunlight got bright!",
                                                      .sand: "A sandstorm brewed!", .hail: "It started to hail!"]
            return [.say(msg[w] ?? "")]
        case "mud-sport": field.mudSport = true; return [.say("Electricity's power was weakened!")]
        case "water-sport": field.waterSport = true; return [.say("Fire's power was weakened!")]
        case "reflect", "light-screen", "mist", "safeguard":
            var s = field[side]
            switch move.key {
            case "reflect": guard s.reflect == 0 else { return fail }; s.reflect = 5
            case "light-screen": guard s.lightScreen == 0 else { return fail }; s.lightScreen = 5
            case "mist": guard s.mist == 0 else { return fail }; s.mist = 5
            default: guard s.safeguard == 0 else { return fail }; s.safeguard = 5
            }
            field[side] = s
            let msg = ["reflect": "Reflect raised Defense!", "light-screen": "Light Screen raised Sp. Def!",
                       "mist": "\(p)\(a.name) became shrouded in mist!", "safeguard": "\(p)\(a.name) became cloaked in a mystical veil!"]
            return [.say(msg[move.key] ?? "")]
        case "spikes":
            guard field[dSide].spikes < 3 else { return fail }
            field[dSide].spikes += 1
            return [.say("Spikes were scattered all around \(dSide == .foe ? "the foe's" : "your") team!")]
        case "attract":
            guard d.gender != a.gender, d.gender != .genderless, a.gender != .genderless, !d.has("Oblivious"), !d.infatuated else { return fail }
            d.infatuated = true
            return [.say("\(dp)\(d.name) fell in love!")]
        case "torment":
            guard !d.tormented else { return fail }
            d.tormented = true
            return [.say("\(p)\(a.name) subjected \(dp)\(d.name) to torment!")]
        case "perish-song":
            guard a.perish == 0 || d.perish == 0 else { return fail }
            if a.perish == 0, !a.has("Soundproof") { a.perish = 4 }
            if d.perish == 0, !d.has("Soundproof") { d.perish = 4 }
            return [.say("All Pokémon hearing the song will faint in three turns!")]
        case "odor-sleuth", "foresight":
            return [.say("\(p)\(a.name) identified \(dp)\(d.name)!")]
        case "follow-me", "helping-hand", "trick", "assist", "recycle", "imprison", "grudge", "snatch", "baton-pass":
            return fail
        default: break
        }
        switch move.cat {
        case 1:                                     // causes a status condition
            if move.ailment == 18 {
                guard !d.seeded, !d.types.contains(.grass) else { return fail }
                d.seeded = true
                return [.say("\(dp)\(d.name) was seeded!")]
            }
            if move.key == "thunder-wave", TypeChart.multiplier(.electric, against: d.types) == 0 {
                return [.say("It doesn't affect \(dp)\(d.name)…")]
            }
            return inflict(move.ailment, key: move.key, on: &d, side: dSide, quiet: false, field: field)
        case 2:                                     // raises or lowers stats
            if move.targetsUser || move.stats.allSatisfy({ $0[1] > 0 }) {
                return changeStats(move.stats, on: &a, side: side, field: field, byOpponent: false, loud: true)
            }
            return changeStats(move.stats, on: &d, side: dSide, field: field, byOpponent: true, loud: true)
        case 3:                                     // heals
            guard a.hp < a.maxHP else { return [.say("\(p)\(a.name)'s HP is full!")] }
            var pct = max(1, move.healing)
            if ["morning-sun", "synthesis", "moonlight"].contains(move.key) {
                pct = field.weather == .sun ? 67 : field.weather == .none ? 50 : 25
            }
            a.hp = min(a.maxHP, a.hp + max(1, a.maxHP * pct / 100))
            return [.hp(side, a.hp, effectiveness: nil), .say("\(p)\(a.name) regained health!")]
        case 5:                                     // Swagger, Flatter
            var ev = changeStats(move.stats, on: &d, side: dSide, field: field, byOpponent: false, loud: true)
            ev += inflict(6, key: move.key, on: &d, side: dSide, quiet: false, field: field)
            return ev
        default:
            return fail
        }
    }

    private static func inflict(_ ailment: Int, key: String, on m: inout BattleMon, side: BattleSide, quiet: Bool, field: BattleField?) -> [BattleEvent] {
        let p = prefix(side)
        let blocked: [BattleEvent] = quiet ? [] : [.say("But it failed!")]
        if let f = field, f[side].safeguard > 0 {
            return quiet ? [] : [.say("\(p)\(m.name) is protected by Safeguard!")]
        }
        if ailment == 6 {
            guard m.confused == 0 else { return quiet ? [] : [.say("\(p)\(m.name) is already confused!")] }
            if m.has("Own Tempo") { return quiet ? [] : [.say("\(p)\(m.name)'s Own Tempo prevents confusion!")] }
            m.confused = Int.random(in: 2...5)
            return [.say("\(p)\(m.name) became confused!")]
        }
        if ailment == 7 { return quiet ? [] : [.say("\(p)\(m.name) fell in love!")] }
        if ailment == 8 {
            m.trapped = true
            return [.say("\(p)\(m.name) was trapped!")]
        }
        guard m.status == .none else {
            let what: String
            switch m.status {
            case .sleep: what = "asleep"
            case .paralysis: what = "paralyzed"
            case .burn: what = "burned"
            case .freeze: what = "frozen"
            default: what = "poisoned"
            }
            return quiet ? [] : [.say("\(p)\(m.name) is already \(what)!")]
        }
        switch ailment {
        case 1:
            if m.has("Limber") { return blocked }
            m.status = .paralysis
            return [.say("\(p)\(m.name) is paralyzed! It may be unable to move!"), .status(side)]
        case 2:
            if m.has("Insomnia") || m.has("Vital Spirit") { return blocked }
            m.status = .sleep(Int.random(in: 2...5))
            return [.say("\(p)\(m.name) fell asleep!"), .status(side)]
        case 3:
            guard !m.types.contains(.ice), !m.has("Magma Armor") else { return [] }
            m.status = .freeze
            return [.say("\(p)\(m.name) was frozen solid!"), .status(side)]
        case 4:
            guard !m.types.contains(.fire), !m.has("Water Veil") else { return quiet ? [] : [.say("It doesn't affect \(p)\(m.name)…")] }
            m.status = .burn
            return [.say("\(p)\(m.name) was burned!"), .status(side)]
        case 5:
            guard !m.types.contains(.poison), !m.types.contains(.steel), !m.has("Immunity") else { return quiet ? [] : [.say("It doesn't affect \(p)\(m.name)…")] }
            if key == "toxic" {
                m.status = .toxic(1)
                return [.say("\(p)\(m.name) was badly poisoned!"), .status(side)]
            }
            m.status = .poison
            return [.say("\(p)\(m.name) was poisoned!"), .status(side)]
        default:
            return blocked
        }
    }

    private static let statNames = [2: "Attack", 3: "Defense", 4: "Sp. Atk", 5: "Sp. Def", 6: "Speed", 7: "accuracy", 8: "evasiveness"]

    private static func changeStats(_ changes: [[Int]], on m: inout BattleMon, side: BattleSide, field: BattleField,
                                    byOpponent: Bool, loud: Bool = false) -> [BattleEvent] {
        var ev: [BattleEvent] = []
        let p = prefix(side)
        let lowering = changes.contains { $0[1] < 0 }
        if byOpponent, lowering {
            if field[side].mist > 0 { return loud ? [.say("\(p)\(m.name) is protected by Mist!")] : [] }
            if m.has("Clear Body") || m.has("White Smoke") { return loud ? [.say("\(p)\(m.name)'s \(m.ability ?? "ability") prevents stat loss!")] : [] }
        }
        for c in changes where (2...8).contains(c[0]) {
            let (i, n) = (c[0], c[1])
            if byOpponent, n < 0 {
                if i == 2, m.has("Hyper Cutter") { if loud { ev.append(.say("\(p)\(m.name)'s Hyper Cutter prevents Attack loss!")) }; continue }
                if i == 7, m.has("Keen Eye") { if loud { ev.append(.say("\(p)\(m.name)'s Keen Eye prevents accuracy loss!")) }; continue }
            }
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

    /// Picks a move like a smart Frontier trainer: the one that hurts most (finishing you off when it can),
    /// a status move when it helps, never a move that can't work.
    static func aiMove(_ a: BattleMon, vs d: BattleMon, field: BattleField = BattleField()) -> Int {
        let usable = a.moves.indices.filter { a.canSelect($0) }
        guard !usable.isEmpty else { return -1 }
        if a.actsAlone { return 0 }
        func score(_ i: Int) -> Double {
            let m = a.moves[i].info
            if !m.status {
                let eff = effectiveness(m, on: d)
                if eff == 0 { return -1 }
                if m.type == .ground, d.has("Levitate") { return -1 }
                if m.type == .electric, d.has("Volt Absorb") { return -1 }
                if m.type == .water, d.has("Water Absorb") { return -1 }
                if m.type == .fire, d.has("Flash Fire") { return -1 }
                if d.has("Wonder Guard"), eff < 2 { return -1 }
                if m.key == "dream-eater", !d.status.isSleep { return -1 }
                if m.key == "fake-out", a.turnsOut > 0 { return -1 }
                if m.key == "focus-punch" || m.key == "counter" || m.key == "mirror-coat" { return 3 }
                if m.key == "spit-up", a.stockpile == 0 { return -1 }
            }
            if MoveData.fixedDamage.contains(m.key) {
                let dmg = m.key == "super-fang" ? Double(d.hp / 2) : m.key == "endeavor" ? Double(max(0, d.hp - a.hp))
                    : m.key == "sonic-boom" ? 20 : m.key == "dragon-rage" ? 40 : Double(a.level)
                return dmg >= Double(d.hp) ? 10_000 : dmg
            }
            if let pw = m.power, pw > 0, !m.status {
                var s = Double(damage(m, power: pw, from: a, to: d, crit: false, field: field, defenderSide: .mine, random: false).amount)
                if let lo = m.minHits, let hi = m.maxHits { s *= Double(lo + hi) / 2 }
                if let acc = m.accuracy { s *= Double(acc) / 100 }
                if s >= Double(d.hp) { s = 10_000 + s }                           // it can finish you
                if rechargeMoves.contains(m.key), s < 10_000 { s *= 0.6 }
                if chargeText[m.key] != nil { s *= 0.55 }
                if m.key == "self-destruct" || m.key == "explosion" { s *= a.hp < a.maxHP / 3 ? 1 : 0.05 }
                if m.drain > 0, a.hp < a.maxHP / 2 { s *= 1.3 }
                return s
            }
            if MoveData.variablePower.contains(m.key) { return Double(a.level) }
            // status moves: worth it once
            switch m.cat {
            case 1:
                let useless = d.status != .none || d.substitute > 0 || (m.ailment == 6 && d.confused > 0)
                    || (m.ailment == 18 && (d.seeded || d.types.contains(.grass)))
                return useless ? -1 : Double(d.maxHP) * (a.hp > a.maxHP / 2 ? 0.35 : 0.1)
            case 3: return a.hp < a.maxHP / 2 ? Double(a.maxHP) * 0.6 : -1
            case 2:
                let selfBoost = m.targetsUser || m.stats.allSatisfy { $0[1] > 0 }
                if selfBoost { return m.stats.contains { a.stages[$0[0]] >= 2 } || a.hp < a.maxHP / 2 ? -1 : Double(d.maxHP) * 0.3 }
                return m.stats.contains { d.stages[$0[0]] <= -2 } ? -1 : Double(d.maxHP) * 0.1
            default:
                switch m.key {
                case "protect", "detect": return a.protectCount > 0 ? -1 : 2
                case "substitute": return a.substitute > 0 || a.hp <= a.maxHP / 2 ? -1 : Double(d.maxHP) * 0.2
                case "rest": return a.hp < a.maxHP / 3 ? Double(a.maxHP) * 0.5 : -1
                case "reflect": return field.foe.reflect > 0 ? -1 : Double(d.maxHP) * 0.15
                case "light-screen": return field.foe.lightScreen > 0 ? -1 : Double(d.maxHP) * 0.15
                case "spikes": return field.mine.spikes >= 3 ? -1 : Double(d.maxHP) * 0.1
                case "rain-dance", "sunny-day", "sandstorm", "hail": return field.weather == .none ? Double(d.maxHP) * 0.08 : -1
                default: return 0.5
                }
            }
        }
        if Double.random(in: 0..<1) < 0.04 { return usable.randomElement()! }
        return usable.max { score($0) < score($1) }!
    }
}
