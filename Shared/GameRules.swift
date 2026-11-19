import Foundation

/// Where/when steps happened, so encounters fit the surroundings.
struct EncounterContext {
    var habitats: Set<Habitat> = [.urban, .grassland]
    var isNight: Bool = false
    var location: MetLocation?
}

struct StepOutcome {
    var steps = 0
    var expGained = 0
    var oldLevel = 0
    var newLevel = 0
    var ballsEarned: [BallKind: Int] = [:]
    var itemsFound: [String] = []
    var newEncounters: [PendingEncounter] = []
    var evolutionReady: (id: UUID, into: Int)?
    var partyLevelUps: [(id: UUID, level: Int)] = []

    var isEmpty: Bool { steps == 0 }
}

enum GameRules {

    // MARK: Creating Pokémon

    static func makePokemon(species id: Int, level: Int, ball: BallKind, trainer: Trainer, settings: GameSettings,
                            location: MetLocation?, note: String? = nil, date: Date = .now) -> OwnedPokemon {
        let sp = Dex.species(id)
        let personality = UInt32.random(in: 0...UInt32.max)
        return OwnedPokemon(
            speciesID: id, nickname: nil,
            exp: sp.growth.exp(forLevel: level),
            gender: rollGender(sp),
            isShiny: Int.random(in: 0..<max(1, settings.shinyOdds)) == 0,
            nature: Dex.natures.randomElement()!, personality: personality,
            friendship: sp.baseFriendship,
            ball: ball, metDate: date, metLevel: level, metLocation: location, metNote: note,
            otName: trainer.name, otID: trainer.trainerID)
    }

    static func rollGender(_ sp: Species) -> Gender {
        if sp.genderRate < 0 { return .genderless }
        return Int.random(in: 0..<8) < sp.genderRate ? .female : .male
    }

    static func newGame(trainerName: String, appearance: String = "brendan", starter: Int, nickname: String?,
                        location: MetLocation?) -> GameState {
        var s = GameState()
        s.trainer = Trainer.new(named: trainerName.isEmpty ? "Trainer" : trainerName)
        s.trainer.appearance = appearance
        var mon = makePokemon(species: starter, level: 5, ball: .poke, trainer: s.trainer, settings: s.settings,
                              location: location, note: "Received as a starter")
        mon.nickname = nickname
        store(mon, in: &s)
        s.buddyID = mon.id
        s.balls = [.poke: 10, .great: 2]
        s.counters.nextEncounterAt = rollEncounterGap(s.settings)
        return s
    }

    /// Puts a Pokémon in the party, or the first free PC slot (adding boxes as needed).
    @discardableResult
    static func store(_ mon: OwnedPokemon, in s: inout GameState) -> PCSlot {
        s.pokemon.append(mon)
        s.dexSeen.insert(mon.speciesID)
        s.dexCaught.insert(mon.speciesID)
        if s.partyIDs.count < GameState.maxParty {
            s.partyIDs.append(mon.id)
            return .party(s.partyIDs.count - 1)
        }
        for b in s.boxes.indices {
            if let i = s.boxes[b].slots.firstIndex(where: { $0 == nil }) {
                s.boxes[b].slots[i] = mon.id
                return .box(b, i)
            }
        }
        s.boxes.append(PCBox(name: "Box \(s.boxes.count + 1)", wallpaper: s.boxes.count % 8))
        s.boxes[s.boxes.count - 1].slots[0] = mon.id
        return .box(s.boxes.count - 1, 0)
    }

    // MARK: Steps → rewards

    static func rollEncounterGap(_ settings: GameSettings) -> Int {
        let base = max(50, settings.encounterSteps)
        return Int.random(in: (base * 8 / 10)...(base * 12 / 10))
    }

    /// Adds fractional Exp, carrying the remainder so slow rates (e.g. 0.25/step) still add up exactly.
    @discardableResult
    static func grantExp(_ amount: Double, to mon: inout OwnedPokemon) -> Int {
        let total = mon.expRemainder + amount
        let whole = Int(total.rounded(.down))
        mon.expRemainder = total - Double(whole)
        let before = mon.exp
        mon.exp = min(mon.exp + whole, mon.species.growth.maxExp)
        return mon.exp - before
    }

    static func apply(steps: Int, meters: Double = 0, to s: inout GameState, context: EncounterContext,
                      at date: Date = .now) -> StepOutcome {
        var out = StepOutcome()
        s.lastSyncDate = date
        guard steps > 0 else { return out }
        out.steps = steps
        s.lifetimeSteps += steps

        // Buddy: Exp, friendship, steps & distance together
        let buddyExp = Double(steps) * max(0, s.settings.expPerStep)
        if let id = s.buddyID, let i = s.index(of: id) {
            var mon = s.pokemon[i]
            out.oldLevel = mon.level
            let gained = grantExp(buddyExp, to: &mon)
            mon.stepsWalked += steps
            mon.metersWalked += max(0, meters)
            let f = mon.friendshipStepRemainder + steps
            mon.friendship = min(255, mon.friendship + f / 100)
            mon.friendshipStepRemainder = f % 100
            s.pokemon[i] = mon
            out.expGained = gained
            out.newLevel = mon.level
            if let into = pendingEvolution(for: mon, at: date) { out.evolutionReady = (id, into) }
        }

        // Exp Share: the rest of the party (not the PC) gets a fraction of the buddy's Exp
        for pid in s.partyIDs where pid != s.buddyID {
            guard let i = s.index(of: pid) else { continue }
            var mon = s.pokemon[i]
            let before = mon.level
            grantExp(buddyExp * max(0, s.settings.partyShare), to: &mon)
            s.pokemon[i] = mon
            if mon.level > before { out.partyLevelUps.append((pid, mon.level)) }
            if out.evolutionReady == nil, let into = pendingEvolution(for: mon, at: date) { out.evolutionReady = (pid, into) }
        }

        // Balls
        s.counters.ballProgress += steps
        while s.counters.ballProgress >= s.settings.ballSteps {
            s.counters.ballProgress -= s.settings.ballSteps
            s.counters.ballsEarnedTotal += 1
            var kind = BallKind.poke
            if s.counters.ballsEarnedTotal % 50 == 0 { kind = .ultra }
            else if s.counters.ballsEarnedTotal % 10 == 0 { kind = .great }
            s.balls[kind, default: 0] += 1
            out.ballsEarned[kind, default: 0] += 1
        }

        // Items
        s.counters.itemProgress += steps
        while s.counters.itemProgress >= s.settings.itemSteps {
            s.counters.itemProgress -= s.settings.itemSteps
            let item = rollItem()
            s.bag[item, default: 0] += 1
            out.itemsFound.append(item)
        }

        // Encounters
        s.pending.removeAll { $0.expiresAt < date }
        s.counters.encounterProgress += steps
        while s.counters.encounterProgress >= s.counters.nextEncounterAt {
            s.counters.encounterProgress -= s.counters.nextEncounterAt
            s.counters.nextEncounterAt = rollEncounterGap(s.settings)
            let enc = generateEncounter(context: context, lifetimeSteps: s.lifetimeSteps, settings: s.settings, at: date)
            if s.pending.count >= s.settings.maxPendingEncounters { s.pending.removeFirst() }
            s.pending.append(enc)
            s.dexSeen.insert(enc.speciesID)
            out.newEncounters.append(enc)
        }
        return out
    }

    // MARK: Wild encounters

    /// Chance that any single encounter is a legendary or mythical Pokémon (0.01%).
    static let legendaryChance = 0.0001

    /// Rarity tiers from each species' real catch rate: the harder to catch, the rarer it is to meet.
    static func rarityWeight(_ sp: Species) -> Double {
        switch sp.captureRate {
        case 190...: return 100        // Pidgey, Rattata, Zigzagoon…
        case 120..<190: return 45      // Pikachu, Oddish, Geodude…
        case 75..<120: return 18       // Growlithe, Abra's kin…
        case 45..<75: return 6         // starters, Eevee, Dratini, Larvitar…
        case 11..<45: return 1.5       // Chansey, Snorlax, Lapras…
        default: return 0.4            // Beldum and other ultra-rare non-legendaries
        }
    }

    static func encounterWeight(_ sp: Species, context: EncounterContext, lifetimeSteps: Int) -> Double {
        if sp.isLegendary || sp.isMythical { return 0 }     // handled separately (legendaryChance)
        var w = rarityWeight(sp)
        if sp.evolvesFrom != nil {
            let preEvolvesToo = Dex.species(sp.evolvesFrom!).evolvesFrom != nil
            w *= preEvolvesToo ? 0.05 : 0.2              // evolved forms are rarer, final stages rarest
        }
        if sp.isBaby { w *= 0.5 }
        if !context.habitats.isDisjoint(with: sp.habitats) { w *= 1.5 }   // a gentle nudge, still mostly random
        let spooky = sp.types.contains(.ghost) || sp.types.contains(.dark)
        if spooky { w *= context.isNight ? 1.5 : 0.8 }
        return w
    }

    static func pickSpecies(context: EncounterContext, lifetimeSteps: Int) -> Species {
        if Double.random(in: 0..<1) < legendaryChance {
            // Mythicals (Mew, Celebi, Jirachi, Deoxys) are a quarter as likely as legendaries
            let pool = Dex.all.filter { $0.isLegendary || $0.isMythical }.map { ($0, $0.isMythical ? 0.25 : 1.0) }
            return weightedPick(pool)
        }
        let options = Dex.all.map { ($0, encounterWeight($0, context: context, lifetimeSteps: lifetimeSteps)) }
        return weightedPick(options.filter { $0.1 > 0 })
    }

    static func generateEncounter(context: EncounterContext, lifetimeSteps: Int, settings: GameSettings,
                                  at date: Date = .now) -> PendingEncounter {
        let sp = pickSpecies(context: context, lifetimeSteps: lifetimeSteps)
        let base = min(55, 3 + lifetimeSteps / 6_000)
        var level = base + Int.random(in: -2...3)
        level = max(level, sp.minimumWildLevel)
        level = max(1, min(level, 100))
        let matched = context.habitats.intersection(sp.habitats).first
        return PendingEncounter(speciesID: sp.id, level: level, gender: rollGender(sp),
                                isShiny: Int.random(in: 0..<max(1, settings.shinyOdds)) == 0,
                                nature: Dex.natures.randomElement()!, personality: .random(in: 0...UInt32.max),
                                appearedAt: date,
                                expiresAt: date.addingTimeInterval(Double(settings.encounterLifetimeHours) * 3600),
                                location: context.location, habitat: matched)
    }

    static func rollItem() -> String {
        var table: [(String, Double)] = [("rare-candy", 12), ("exp-candy-s", 20), ("exp-candy-m", 6)]
        let common = ["fire-stone", "water-stone", "thunder-stone", "leaf-stone", "moon-stone"]
        let uncommon = ["sun-stone", "shiny-stone", "dusk-stone", "dawn-stone", "ice-stone", "linking-cord", "oval-stone"]
        let keys = Set(Dex.items.map(\.key))
        for k in common where keys.contains(k) { table.append((k, 5)) }
        for k in uncommon where keys.contains(k) { table.append((k, 2.5)) }
        let skip = Set(["rare-candy", "exp-candy-s", "exp-candy-m", "poke-ball", "great-ball", "ultra-ball"] + common + uncommon)
        for k in keys where !skip.contains(k) { table.append((k, 1.2)) }   // held/trade evolution items
        return weightedPick(table)
    }

    static func weightedPick<T>(_ options: [(T, Double)]) -> T {
        let total = options.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<max(total, .leastNonzeroMagnitude))
        for (v, w) in options {
            if roll < w { return v }
            roll -= w
        }
        return options.last!.0
    }

    // MARK: Evolution

    /// Level / friendship evolutions that are ready now (item evolutions need the item).
    /// `ignoringDecline`: the Summary's Evolve button still works after you picked "Not now".
    static func pendingEvolution(for mon: OwnedPokemon, at date: Date = .now, ignoringDecline: Bool = false) -> Int? {
        if !ignoringDecline, let declined = mon.evolutionDeclinedAtLevel, declined >= mon.level { return nil }
        let tod = TimeOfDay.at(date)
        let ready = mon.species.evolutions.filter { rule in
            if let t = rule.time, t != tod { return false }
            if let g = rule.gender, g != mon.gender { return false }
            switch rule.kind {
            case .level: return mon.level >= (rule.level ?? 101)
            case .friendship: return mon.friendship >= (rule.value ?? 220)
            case .item: return false
            }
        }
        guard !ready.isEmpty else { return nil }
        // Branches like Wurmple/Tyrogue are decided by personality, as in the games.
        return ready[Int(mon.personality % UInt32(ready.count))].into
    }

    static func itemEvolution(for mon: OwnedPokemon, item: String, at date: Date = .now) -> Int? {
        let tod = TimeOfDay.at(date)
        return mon.species.evolutions.first { rule in
            rule.kind == .item && rule.item == item
                && (rule.time == nil || rule.time == tod)
                && (rule.gender == nil || rule.gender == mon.gender)
        }?.into
    }

    /// Returns the bonus Pokémon if the evolution produced one (Nincada → Shedinja).
    @discardableResult
    static func evolve(_ id: UUID, into newSpecies: Int, in s: inout GameState, at date: Date = .now) -> OwnedPokemon? {
        guard let i = s.index(of: id) else { return nil }
        let oldSpecies = s.pokemon[i].speciesID
        s.pokemon[i].speciesID = newSpecies
        s.pokemon[i].evolutionDeclinedAtLevel = nil
        s.pokemon[i].evolvedOn = date
        s.dexSeen.insert(newSpecies)
        s.dexCaught.insert(newSpecies)

        if oldSpecies == 290, newSpecies == 291, s.partyIDs.count < GameState.maxParty, s.balls[.poke, default: 0] > 0 {
            s.balls[.poke, default: 0] -= 1
            let source = s.pokemon[i]
            var shed = makePokemon(species: 292, level: source.level, ball: .poke, trainer: s.trainer,
                                   settings: s.settings, location: source.metLocation, note: "Appeared when Nincada evolved")
            shed.isShiny = source.isShiny
            store(shed, in: &s)
            return shed
        }
        return nil
    }

    static func declineEvolution(_ id: UUID, in s: inout GameState) {
        guard let i = s.index(of: id) else { return }
        s.pokemon[i].evolutionDeclinedAtLevel = s.pokemon[i].level
    }

    // MARK: Items

    enum ItemOutcome: Equatable { case leveled(Int), evolves(into: Int), noEffect }

    static func use(_ item: String, on id: UUID, in s: inout GameState, at date: Date = .now) -> ItemOutcome {
        guard let i = s.index(of: id), s.bag[item, default: 0] > 0 else { return .noEffect }
        var mon = s.pokemon[i]
        let growth = mon.species.growth
        let outcome: ItemOutcome
        switch item {
        case "rare-candy":
            guard mon.level < GrowthRate.maxLevel else { return .noEffect }
            mon.exp = growth.exp(forLevel: mon.level + 1)
            mon.friendship = min(255, mon.friendship + 3)
            outcome = .leveled(mon.level)
        case "exp-candy-s", "exp-candy-m":
            guard mon.level < GrowthRate.maxLevel else { return .noEffect }
            mon.exp = min(mon.exp + (item == "exp-candy-s" ? 800 : 3_000), growth.maxExp)
            outcome = .leveled(mon.level)
        default:
            guard let into = itemEvolution(for: mon, item: item, at: date) else { return .noEffect }
            outcome = .evolves(into: into)
        }
        s.pokemon[i] = mon
        s.bag[item, default: 0] -= 1
        if s.bag[item] == 0 { s.bag[item] = nil }
        return outcome
    }

    // MARK: PC

    static func move(from a: PCSlot, to b: PCSlot, in s: inout GameState) {
        func get(_ slot: PCSlot) -> UUID? {
            switch slot {
            case .party(let i): return i < s.partyIDs.count ? s.partyIDs[i] : nil
            case .box(let bx, let i): return s.boxes[bx].slots[i]
            }
        }
        let first = get(a), second = get(b)
        func put(_ id: UUID?, _ slot: PCSlot) {
            switch slot {
            case .party(let i):
                if let id {
                    if i < s.partyIDs.count { s.partyIDs[i] = id } else { s.partyIDs.append(id) }
                } else if i < s.partyIDs.count {
                    s.partyIDs.remove(at: i)
                }
            case .box(let bx, let i):
                s.boxes[bx].slots[i] = id
            }
        }
        // Never leave the party empty, and the buddy must stay in the party.
        if case .party = a, case .box = b, second == nil, s.partyIDs.count <= 1 { return }
        if case .party = a, case .box = b, first == s.buddyID { return }
        if case .party = b, case .box = a, second == s.buddyID { return }
        // Write the higher party index first so removals don't shift the other slot.
        if case .party(let ia) = a, case .party(let ib) = b {
            guard let first, let second else { return }
            s.partyIDs[ia] = second; s.partyIDs[ib] = first
            return
        }
        put(first, b)
        put(second, a)
    }

    static func release(_ id: UUID, in s: inout GameState) {
        guard s.buddyID != id else { return }
        if s.partyIDs.contains(id), s.partyIDs.count <= 1 { return }
        s.partyIDs.removeAll { $0 == id }
        for b in s.boxes.indices {
            if let i = s.boxes[b].slots.firstIndex(of: id) { s.boxes[b].slots[i] = nil }
        }
        s.pokemon.removeAll { $0.id == id }
    }

    static func setBuddy(_ id: UUID, in s: inout GameState) {
        guard s.index(of: id) != nil else { return }
        if !s.partyIDs.contains(id) {
            // Swap the new buddy into the party, sending the old buddy's slot partner to its box slot.
            if let slot = s.slot(of: id), case .box(let b, let i) = slot {
                if s.partyIDs.count < GameState.maxParty {
                    s.boxes[b].slots[i] = nil
                    s.partyIDs.insert(id, at: 0)
                } else {
                    let out = s.partyIDs.last { $0 != s.buddyID }!
                    let outIndex = s.partyIDs.firstIndex(of: out)!
                    s.partyIDs[outIndex] = id
                    s.boxes[b].slots[i] = out
                }
            }
        }
        s.buddyID = id
        // The buddy always leads the party.
        if let i = s.partyIDs.firstIndex(of: id), i != 0 {
            s.partyIDs.remove(at: i)
            s.partyIDs.insert(id, at: 0)
        }
    }
}

// MARK: - Safari-style catching

struct SafariEncounter {
    enum Phase: Equatable { case active, caught(BallKind), fled, ranAway }

    struct ThrowResult {
        var shakes: Int         // 0...3 wobbles before breaking free (3 + click = caught)
        var caught: Bool
        var fled: Bool
        var label: String?      // "Nice!", "Great!", "Excellent!"
    }

    let wild: PendingEncounter
    var phase: Phase = .active
    var baitTurns = 0
    var throwCount = 0
    var bestThrow: String?
    var log: [String] = []

    /// Flat bonus so Safari catching feels fair with limited balls (the Safari Ball was 1.5x).
    static let safariBonus = 1.5

    init(wild: PendingEncounter) {
        self.wild = wild
        log.append("A wild \(wild.species.name) appeared!")
    }

    var baseFleeChance: Double {
        let sp = wild.species
        if sp.isLegendary || sp.isMythical { return 0.35 }
        switch sp.captureRate {
        case 190...: return 0.08
        case 90..<190: return 0.14
        case 45..<90: return 0.22
        default: return 0.3
        }
    }

    var fleeChance: Double { baseFleeChance * (baitTurns > 0 ? 0.3 : 1) }

    /// Modified catch rate "a" from the Gen 3/4 formula at full HP.
    func modifiedRate(ball: BallKind, quality: Double?) -> Double {
        let throwBonus = 1 + 0.85 * (quality ?? 0)
        let bait = baitTurns > 0 ? 0.9 : 1
        return Double(wild.species.captureRate) * ball.bonus * throwBonus * bait * Self.safariBonus / 3
    }

    /// Probability of passing one shake check.
    static func shakeProbability(a: Double) -> Double {
        if a >= 255 { return 1 }
        let b = 1_048_560 / (16_711_680 / max(a, 0.01)).squareRoot().squareRoot()
        return min(1, b / 65_536)
    }

    func catchChance(ball: BallKind, quality: Double? = nil) -> Double {
        pow(Self.shakeProbability(a: modifiedRate(ball: ball, quality: quality)), 4)
    }

    static func label(for quality: Double?) -> String? {
        guard let q = quality else { return nil }
        return q < 0.33 ? "Nice!" : q < 0.66 ? "Great!" : "Excellent!"
    }

    /// Throws a ball; the shake checks decide the outcome. `quality` is an optional throw bonus (0...1), unused by the tap-to-throw UI.
    mutating func throwBall(_ ball: BallKind, quality: Double? = nil) -> ThrowResult {
        guard phase == .active else { return ThrowResult(shakes: 0, caught: false, fled: false) }
        throwCount += 1
        let lbl = Self.label(for: quality)
        if let lbl { bestThrow = better(bestThrow, lbl) }
        let p = Self.shakeProbability(a: modifiedRate(ball: ball, quality: quality))
        var passes = 0
        while passes < 4 && Double.random(in: 0..<1) < p { passes += 1 }
        if passes == 4 {
            phase = .caught(ball)
            log.append("Gotcha! \(wild.species.name) was caught!")
            return ThrowResult(shakes: 3, caught: true, fled: false, label: lbl)
        }
        log.append(["Oh no! It broke free!", "Aww! It appeared to be caught!", "Aargh! Almost had it!", "Shoot! It was so close too!"][min(passes, 3)])
        let fled = turnEnds()
        return ThrowResult(shakes: min(passes, 3), caught: false, fled: fled, label: lbl)
    }

    mutating func giveBait() {
        guard phase == .active else { return }
        baitTurns = min(baitTurns + Int.random(in: 2...4), 6)
        log.append("\(wild.species.name) is eating!")
        _ = turnEnds()
    }

    mutating func run() {
        guard phase == .active else { return }
        phase = .ranAway
        log.append("Got away safely!")
    }

    private mutating func turnEnds() -> Bool {
        let fled = Double.random(in: 0..<1) < fleeChance
        if baitTurns > 0 { baitTurns -= 1 }
        if fled {
            phase = .fled
            log.append("Wild \(wild.species.name) fled!")
        }
        return fled
    }

    private func better(_ a: String?, _ b: String) -> String {
        let order = ["Nice!": 1, "Great!": 2, "Excellent!": 3]
        return (order[a ?? ""] ?? 0) >= (order[b] ?? 0) ? a! : b
    }
}
