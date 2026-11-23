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
    var pickedUp: [(id: UUID, item: String)] = []   // what each party Pokémon picked up
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

    /// Starters on the "Choose your partner" page are each rolled at 1 in 8192 (the Gen 3 odds).
    static let starterShinyOdds = 8_192
    static func rollStarterGenders() -> [Int: Gender] {
        Dictionary(uniqueKeysWithValues: Dex.starterChoices.map { ($0, rollGender(Dex.species($0))) })
    }

    static func rollStarterShinies() -> Set<Int> {
        Set(Dex.starterChoices.filter { _ in Int.random(in: 0..<starterShinyOdds) == 0 })
    }

    static func newGame(trainerName: String, appearance: String = "brendan", starter: Int, nickname: String?,
                        location: MetLocation?, shiny: Bool = false, gender: Gender? = nil) -> GameState {
        var s = GameState()
        s.trainer = Trainer.new(named: trainerName.isEmpty ? "Trainer" : trainerName)
        s.trainer.appearance = appearance
        var mon = makePokemon(species: starter, level: 5, ball: .poke, trainer: s.trainer, settings: s.settings,
                              location: location, note: "Received as a starter")
        mon.nickname = nickname
        mon.isShiny = shiny                       // exactly what you saw on the picker
        if let gender { mon.gender = gender }
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
            let f = mon.friendshipStepRemainder + steps * (mon.ball == .luxury ? 2 : 1)   // Luxury Ball: twice as fast
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
            if let ball = BallKind.allCases.first(where: { $0.itemKey == item }) {
                s.balls[ball, default: 0] += 1
            } else {
                s.bag[item, default: 0] += 1
            }
            out.itemsFound.append(item)
        }

        // Berries: their own, more frequent find (Settings › Berry every N steps)
        s.counters.berryProgress += steps
        while s.counters.berryProgress >= max(50, s.settings.berrySteps) {
            s.counters.berryProgress -= max(50, s.settings.berrySteps)
            let berry = ItemCatalog.berries.randomElement()!
            s.bag[berry, default: 0] += 1
            out.itemsFound.append(berry)
        }

        // Pocket money: ₽0.01 per step
        s.counters.moneyProgress += steps
        s.money += s.counters.moneyProgress / 100
        s.counters.moneyProgress %= 100

        // Pickup: each party Pokémon has its own timer — every 1,500 of *its* steps (while it's in the party
        // with empty hands) it tries to find an Exp. Candy or a berry and holds it until you take it.
        // Sometimes it finds nothing; then it tries again 1,000 steps later.
        for pid in s.partyIDs {
            guard let i = s.index(of: pid), s.pokemon[i].heldItems.count < ExpCandy.carryLimit else { continue }
            if s.pokemon[i].nextPickupAt < Pickup.retryAfterMiss { s.pokemon[i].nextPickupAt = Pickup.every }  // old 300-step timers
            s.pokemon[i].pickupSteps += steps
            guard s.pokemon[i].pickupSteps >= s.pokemon[i].nextPickupAt else { continue }
            s.pokemon[i].pickupSteps = 0
            guard Double.random(in: 0..<1) >= Pickup.missChance else {
                s.pokemon[i].nextPickupAt = Pickup.retryAfterMiss
                continue
            }
            s.pokemon[i].nextPickupAt = Pickup.every
            let found = Bool.random() ? weightedPick(ExpCandy.all.map { ($0.key, $0.weight) })
                                      : ItemCatalog.berries.randomElement()!
            s.pokemon[i].heldItems.append(found)
            out.pickedUp.append((pid, found))
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

    /// Set by the app from live weather. Shared code can't see the weather service directly.
    nonisolated(unsafe) static var currentWeather: WeatherCondition?
    static let weatherBoost = 1.05

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
        // Weather where you are: matching types are ~5% more likely (rain → Water, sun → Fire…)
        if let weather = currentWeather, !weather.boostedTypes.isDisjoint(with: sp.types) { w *= weatherBoost }
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

    /// Items found while walking: evolution stones, Rare Candies, Link Cables and rare balls.
    static func rollItem() -> String {
        var table: [(String, Double)] = [
            ("rare-candy", 8),
            ("fire-stone", 4), ("water-stone", 4), ("thunder-stone", 4), ("leaf-stone", 4), ("moon-stone", 3.5), ("sun-stone", 2),
            ("linking-cord", 0.8),                                 // Link Cable: trade evolutions — rare
        ]
        // Friendship berries (common) and bitter herbs
        for k in ItemCatalog.berries { table.append((k, 6)) }
        for k in ItemCatalog.herbs.keys { table.append((k, 2.5)) }
        // Valuables to sell — the cheaper, the more common
        for (k, price) in ItemCatalog.sellPrice { table.append((k, price <= 50 ? 6 : price <= 250 ? 3.5 : price <= 500 ? 1.5 : 0.6)) }
        // Rare balls (Poké/Great/Ultra come every 100 steps instead)
        for b in BallKind.allCases where !b.isStepBall {
            table.append((b.itemKey, b == .master ? 0.08 : 2.5))
        }
        // Held items some trade evolutions need (Onix → Steelix, Seadra → Kingdra…) — very rare
        for k in ["kings-rock", "metal-coat", "dragon-scale", "up-grade", "deep-sea-tooth", "deep-sea-scale", "prism-scale"] {
            table.append((k, 0.12))
        }
        return weightedPick(table)
    }

    /// Sells valuables. Returns the Pokédollars earned.
    @discardableResult
    static func sell(_ item: String, count: Int, in s: inout GameState) -> Int {
        guard let price = ItemCatalog.price(item) else { return 0 }
        let n = min(count, s.bag[item, default: 0])
        guard n > 0 else { return 0 }
        s.bag[item, default: 0] -= n
        if s.bag[item] == 0 { s.bag[item] = nil }
        s.money += n * price
        return n * price
    }

    /// Buys balls. Like the games, every 10 Poké Balls at once comes with a free Premier Ball.
    static func buy(_ ball: BallKind, count: Int, in s: inout GameState) -> Bool {
        guard let price = ItemCatalog.shop.first(where: { $0.ball == ball })?.price, count > 0,
              s.money >= price * count else { return false }
        s.money -= price * count
        s.balls[ball, default: 0] += count
        if ball == .poke, count >= 10 { s.balls[.premier, default: 0] += count / 10 }
        return true
    }

    /// Takes everything your Pokémon is holding and puts it in the Bag.
    static func takeHeldItems(from id: UUID, in s: inout GameState) -> [String] {
        guard let i = s.index(of: id) else { return [] }
        let items = s.pokemon[i].heldItems
        for k in items { s.bag[k, default: 0] += 1 }
        s.pokemon[i].heldItems = []
        return items
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

    /// Whether using `item` on `mon` would do anything (the games' "ABLE / NOT ABLE").
    static func canUse(_ item: String, on mon: OwnedPokemon, at date: Date = .now) -> Bool {
        if item == "rare-candy" || ExpCandy.exp(item) != nil { return mon.level < GrowthRate.maxLevel }
        if ItemCatalog.isBerry(item) { return mon.friendship < 255 }
        if ItemCatalog.herbs[item] != nil { return mon.friendship > 0 }
        if ItemCatalog.sellPrice[item] != nil { return false }
        return itemEvolution(for: mon, item: item, at: date) != nil
    }

    /// One line for the Bag explaining what an item does in PokéWalk.
    static func itemDescription(_ item: String) -> String {
        if item == "rare-candy" { return "Raises a Pokémon by one level." }
        if let exp = ExpCandy.exp(item) { return "Gives a Pokémon \(exp.formatted()) Exp." }
        if ItemCatalog.isBerry(item) { return "Makes a Pokémon more friendly (more so if it doesn't like you much yet)." }
        if let drop = ItemCatalog.herbs[item] { return "Bitter medicine — lowers friendship by \(drop)." }
        if let price = ItemCatalog.sellPrice[item] { return "Can't be used on Pokémon. Sells for ₽\(price)." }
        var users: [String] = []
        for sp in Dex.all {
            for rule in sp.evolutions where rule.kind == .item && rule.item == item {
                let into = Dex.species(rule.into).name
                users.append("\(sp.name) → \(into)" + (rule.time.map { " (\($0.rawValue))" } ?? ""))
            }
        }
        guard !users.isEmpty else { return "No use in PokéWalk yet." }
        let how = item == "linking-cord" ? "Trade-evolves" : (item.hasSuffix("-stone") ? "Evolves" : "Trade-evolves (held item)")
        return "\(how): " + users.joined(separator: ", ")
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

    enum ItemOutcome: Equatable { case leveled(Int), evolves(into: Int), friendship(up: Bool), noEffect }

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
        case _ where ItemCatalog.isBerry(item):
            guard mon.friendship < 255 else { return .noEffect }
            mon.friendship = min(255, mon.friendship + ItemCatalog.berryBoost(mon.friendship))
            outcome = .friendship(up: true)
        case _ where ItemCatalog.herbs[item] != nil:
            guard mon.friendship > 0 else { return .noEffect }
            mon.friendship = max(0, mon.friendship - ItemCatalog.herbs[item]!)
            outcome = .friendship(up: false)
        case _ where ItemCatalog.sellPrice[item] != nil:
            return .noEffect
        case _ where ExpCandy.exp(item) != nil:
            guard mon.level < GrowthRate.maxLevel else { return .noEffect }
            mon.exp = min(mon.exp + ExpCandy.exp(item)!, growth.maxExp)
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

    /// Puts a Pokémon in the first free PC box slot (never the party), adding boxes as needed.
    @discardableResult
    static func storeInBox(_ mon: OwnedPokemon, in s: inout GameState) -> PCSlot {
        if s.index(of: mon.id) == nil { s.pokemon.append(mon) }
        s.dexSeen.insert(mon.speciesID)
        s.dexCaught.insert(mon.speciesID)
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

    static func release(_ id: UUID, in s: inout GameState) {
        guard s.buddyID != id else { return }
        if s.partyIDs.contains(id), s.partyIDs.count <= 1 { return }
        s.partyIDs.removeAll { $0 == id }
        for b in s.boxes.indices {
            if let i = s.boxes[b].slots.firstIndex(of: id) { s.boxes[b].slots[i] = nil }
        }
        s.pokemon.removeAll { $0.id == id }
    }

    /// Moves a party Pokémon to another slot; the buddy always stays in slot 1.
    static func reorderParty(_ id: UUID, to index: Int, in s: inout GameState) {
        guard id != s.buddyID, let from = s.partyIDs.firstIndex(of: id) else { return }
        s.partyIDs.remove(at: from)
        let minIndex = s.partyIDs.first == s.buddyID ? 1 : 0
        s.partyIDs.insert(id, at: min(max(index, minIndex), s.partyIDs.count))
    }

    enum Pickup {
        static let every = 2_500          // steps between pickups
        static let retryAfterMiss = 2_000 // found nothing: try again after this many steps
        static let missChance = 0.5       // half the time it finds nothing
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
    var caughtBefore = false        // for the Repeat Ball

    /// Flat bonus so Safari catching feels fair with limited balls (the Safari Ball was 1.5x).
    static let safariBonus = 1.5

    init(wild: PendingEncounter) {
        self.wild = wild
        log.append("A wild \(wild.species.name) appeared!")
    }

    /// Chance it runs after each missed ball (or berry): rarer and higher-level Pokémon are jumpier.
    var baseFleeChance: Double {
        let sp = wild.species
        let rarity: Double
        if sp.isLegendary || sp.isMythical { rarity = 0.30 }
        else {
            switch sp.captureRate {
            case 190...: rarity = 0.06
            case 120..<190: rarity = 0.09
            case 75..<120: rarity = 0.13
            case 45..<75: rarity = 0.18
            default: rarity = 0.24
            }
        }
        let levelBonus = Double(max(0, wild.level - 5)) * 0.002      // +1% every 5 levels
        return min(0.45, rarity + levelBonus)
    }

    /// While it's eating a berry it's much calmer.
    var fleeChance: Double { baseFleeChance * (baitTurns > 0 ? 0.35 : 1) }

    /// Modified catch rate "a" from the Gen 3/4 formula at full HP.
    func modifiedRate(ball: BallKind, quality: Double?) -> Double {
        let throwBonus = 1 + 0.85 * (quality ?? 0)
        let bait = 1.0       // berries don't make it harder to catch
        if ball == .master { return 255 }
        let ballBonus = ball.bonus(species: wild.species, level: wild.level, turn: throwCount,
                                   caughtBefore: caughtBefore,
                                   nearWater: wild.habitat == .sea || wild.habitat == .watersEdge)
        return Double(wild.species.captureRate) * ballBonus * throwBonus * bait * Self.safariBonus / 3
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

    /// Throw one of your berries: it stays calmer (much less likely to flee) for the next few turns.
    @discardableResult
    mutating func giveBerry(_ name: String) -> Bool {
        guard phase == .active else { return false }
        baitTurns = min(baitTurns + Int.random(in: 2...4), 6)
        log.append("\(wild.species.name) is eating the \(name)!")
        return turnEnds()
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
