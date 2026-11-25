import Foundation

// MARK: - Balls & locations

enum BallKind: String, Codable, CaseIterable, Identifiable {
    case poke, great, ultra
    // Rare balls: only found as items while walking (Gen 3 set)
    case net, dive, nest, repeatBall = "repeat", timer, luxury, premier, safari, master
    var id: String { rawValue }

    /// Earned every 100 steps; everything else is a rare find.
    var isStepBall: Bool { self == .poke || self == .great || self == .ultra }

    var name: String {
        switch self {
        case .poke: return "Poké Ball"
        case .great: return "Great Ball"
        case .ultra: return "Ultra Ball"
        case .net: return "Net Ball"
        case .dive: return "Dive Ball"
        case .nest: return "Nest Ball"
        case .repeatBall: return "Repeat Ball"
        case .timer: return "Timer Ball"
        case .luxury: return "Luxury Ball"
        case .premier: return "Premier Ball"
        case .safari: return "Safari Ball"
        case .master: return "Master Ball"
        }
    }

    /// Base catch-rate multiplier (the main-series values; conditional balls use `bonus(...)`).
    var bonus: Double {
        switch self {
        case .poke, .premier, .luxury: return 1
        case .great, .safari: return 1.5
        case .ultra: return 2
        case .net, .dive, .nest, .repeatBall, .timer: return 1
        case .master: return 255
        }
    }

    /// Gen 3 rules for the conditional balls.
    func bonus(species: Species, level: Int, turn: Int, caughtBefore: Bool, nearWater: Bool) -> Double {
        switch self {
        case .net: return species.types.contains(.water) || species.types.contains(.bug) ? 3 : 1
        case .dive: return species.types.contains(.water) || nearWater ? 3.5 : 1
        case .nest: return max(1, Double(40 - level) / 10)
        case .repeatBall: return caughtBefore ? 3 : 1
        case .timer: return min(4, Double(turn + 10) / 10)
        default: return bonus
        }
    }

    /// One line for the Bag.
    var effect: String {
        switch self {
        case .poke: return "Catch bonus ×1"
        case .great: return "Catch bonus ×1.5"
        case .ultra: return "Catch bonus ×2"
        case .net: return "×3 on Water and Bug Pokémon"
        case .dive: return "×3.5 on Water Pokémon or near water"
        case .nest: return "Better the lower the Pokémon's level"
        case .repeatBall: return "×3 on species you've caught before"
        case .timer: return "Gets better each throw (up to ×4)"
        case .luxury: return "Pokémon caught in it grow friendly faster"
        case .premier: return "A rare commemorative ball"
        case .safari: return "Catch bonus ×1.5"
        case .master: return "Catches any Pokémon without fail"
        }
    }

    /// File name used for user-supplied / PokeAPI item sprites.
    var itemKey: String { self == .poke ? "poke-ball" : "\(rawValue)-ball" }

    /// Two-tone colours for the built-in ball drawing (used when no sprite is supplied).
    var topHex: UInt32 {
        switch self {
        case .poke: return 0xE04A3F
        case .great: return 0x3D7BE0
        case .ultra: return 0x2D2D2D
        case .net: return 0x3FB8C9
        case .dive: return 0x3A6FD8
        case .nest: return 0x8DBF3F
        case .repeatBall: return 0xE8902A
        case .timer: return 0xE04A3F
        case .luxury: return 0x2D2D2D
        case .premier: return 0xF4F7F6
        case .safari: return 0x6E8B3D
        case .master: return 0x7A3FB8
        }
    }
}

/// Exp. Candies your buddy picks up while walking.
enum ExpCandy {
    static let all: [(key: String, exp: Int, weight: Double)] = [
        ("exp-candy-xs", 50, 40), ("exp-candy-s", 250, 30), ("exp-candy-m", 800, 18),
        ("exp-candy-l", 2_500, 9), ("exp-candy-xl", 6_000, 3),
    ]
    static func exp(_ key: String) -> Int? { all.first { $0.key == key }?.exp }
    /// A Pokémon holds one item at a time; it won't pick up another until you take it.
    static let carryLimit = 1
}

struct MetLocation: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var placeName: String?

    var displayName: String { placeName ?? String(format: "%.4f, %.4f", latitude, longitude) }
}

// MARK: - Trainer

struct Trainer: Codable, Hashable {
    var name: String
    var trainerID: Int          // the 5-digit "ID No." shown on summaries
    var secretID: Int           // used for shiny checks, like the games
    var startedOn: Date
    var appearance: String = "brendan"   // TrainerStyle id

    var style: TrainerStyle { TrainerStyle.style(appearance) }

    var idString: String { String(format: "%05d", trainerID) }

    static func new(named name: String) -> Trainer {
        Trainer(name: name, trainerID: Int.random(in: 0...65535), secretID: Int.random(in: 0...65535), startedOn: .now)
    }
}

// MARK: - Owned Pokémon

struct OwnedPokemon: Codable, Identifiable, Hashable {
    var id = UUID()
    var speciesID: Int
    var nickname: String?
    var exp: Int
    var gender: Gender
    var isShiny: Bool
    var nature: String
    var personality: UInt32
    var friendship: Int
    var stepsWalked: Int = 0
    var friendshipStepRemainder: Int = 0
    var expRemainder: Double = 0        // fractional Exp carried between syncs
    var metersWalked: Double = 0        // distance walked as your buddy

    // Origin ("trainer memo")
    var ball: BallKind
    var metDate: Date
    var metLevel: Int
    var metLocation: MetLocation?
    var metNote: String?            // e.g. "Starter", "Hatched" – shown when there's no map location
    var otName: String
    var otID: Int

    var evolutionDeclinedAtLevel: Int?
    var evolvedOn: Date?
    var abilitySwapped = false      // Ability Capsule: uses its other ability
    var heldItems: [String] = []    // Exp. Candies picked up on walks, until you take them
    var pickupSteps = 0             // its own pickup timer (counts while in the party, empty-handed)
    var nextPickupAt = 1_500

    var species: Species { Dex.species(speciesID) }
    var name: String { (nickname?.isEmpty == false) ? nickname! : species.name }
    var level: Int { species.growth.level(forExp: exp) }
    var levelProgress: Double { species.growth.progress(exp: exp) }
    var expToNext: Int { species.growth.expToNext(exp: exp) }
    var otIDString: String { String(format: "%05d", otID) }

    /// The flavour line games show under the nature.
    var characteristic: String {
        let lines = ["Loves to eat", "Proud of its power", "Sturdy body", "Likes to run", "Highly curious",
                     "Strong willed", "Often dozes off", "Likes to thrash about", "Capable of taking hits",
                     "Alert to sounds", "Mischievous", "Somewhat vain"]
        return lines[Int(personality % UInt32(lines.count))]
    }
}

// MARK: - PC

struct PCBox: Codable, Identifiable, Hashable {
    static let capacity = 30
    var id = UUID()
    var name: String
    var wallpaper: Int = 0
    var slots: [UUID?] = Array(repeating: nil, count: PCBox.capacity)

    var count: Int { slots.compactMap { $0 }.count }
    var isFull: Bool { count == PCBox.capacity }
}

enum PCSlot: Hashable {
    case party(Int)
    case box(Int, Int)      // box index, slot index
}

// MARK: - Encounters

/// A wild Pokémon you met and what happened, shown in the Journal.
struct EncounterLogEntry: Codable, Identifiable, Hashable {
    enum Outcome: String, Codable { case caught, fled, ranAway, waiting, left }
    var id: UUID                 // same as the encounter's id
    var speciesID: Int
    var level: Int
    var isShiny: Bool
    var date: Date
    var location: MetLocation?
    var outcome: Outcome
    var caughtID: UUID?          // the Pokémon you got, if caught
    var ball: BallKind?
    var seen: Bool? = nil        // false: it left before you ever opened it (shown as a silhouette)

    var outcomeText: String {
        switch outcome {
        case .left: return "Left"
        case .caught: return "Caught"
        case .fled: return "Fled"
        case .ranAway: return "You ran"
        case .waiting: return "Waiting"
        }
    }
}

struct PendingEncounter: Codable, Identifiable, Hashable {
    var id = UUID()
    var speciesID: Int
    var level: Int
    var gender: Gender
    var isShiny: Bool
    var nature: String
    var personality: UInt32
    var appearedAt: Date
    var expiresAt: Date
    var location: MetLocation?
    var habitat: Habitat?

    var species: Species { Dex.species(speciesID) }
}

// MARK: - Settings & counters

enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    case off, walks, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .walks: return "Only during walks"
        case .always: return "Always (Adventure mode)"
        }
    }
}

struct GameSettings: Codable, Hashable {
    var expPerStep: Double = 0.25       // buddy Exp per step (1.0 = original Pokéwalker)
    var partyShare: Double = 0.2        // the rest of the party gets this fraction of the buddy's Exp
    var encounterSteps = 500        // average steps between wild encounters
    var ballSteps = 1_000           // steps per Poké Ball
    var itemSteps = 1_500           // steps per found item
    var berrySteps = 400            // steps per berry found (on top of items)
    var shinyOdds = 512           // each Pokémon has a 1-in-N random chance (not a guaranteed every-Nth)
    var maxPendingEncounters = 5
    var encounterLifetimeHours = 4
    var notifyEncounters = true
    var trackingMode: TrackingMode = .always
}

struct StepCounters: Codable, Hashable {
    var encounterProgress = 0
    var nextEncounterAt = 500
    var ballProgress = 0
    var ballsEarnedTotal = 0
    var itemProgress = 0
    var pickupProgress = 0
    var nextPickupAt = 1_500
    var moneyProgress = 0            // ₽0.01 per step → ₽1 every 100 steps
    var berryProgress = 0

    var stepsToEncounter: Int { max(0, nextEncounterAt - encounterProgress) }
}

// MARK: - Save game

/// A lure that's been set: after `endsAt`, it brings a wild Pokémon.
struct ActiveLure: Codable, Equatable {
    var berries: Int
    var startedAt: Date
    var endsAt: Date
}

struct GameState: Codable {
    var version = 2
    var trainer = Trainer.new(named: "Trainer")
    var pokemon: [OwnedPokemon] = []
    var partyIDs: [UUID] = []
    var boxes: [PCBox] = (1...8).map { PCBox(name: "Box \($0)", wallpaper: ($0 - 1) % 8) }
    var buddyID: UUID?
    var bag: [String: Int] = [:]
    var money = 0                    // Pokédollars from selling valuables
    var balls: [BallKind: Int] = [.poke: 10]
    var lifetimeSteps = 0
    var counters = StepCounters()
    var pending: [PendingEncounter] = []
    var encounterLog: [EncounterLogEntry] = []     // every wild Pokémon you met, for the Journal
    var dexSeen: Set<Int> = []
    var dexCaught: Set<Int> = []
    var stepLedger: [String: Int] = [:]     // "yyyy-MM-dd" -> steps already turned into rewards
    var distanceLedger: [String: Double] = [:]  // "yyyy-MM-dd" -> metres already credited to the buddy
    var settings = GameSettings()
    var lastSyncDate = Date()
    var lastFishedAt: Date?          // fishing cooldown (20 minutes)
    var stampDays: [String] = []     // "yyyy-MM-dd" days stamped on the trainer card
    var stampGot: [String: String] = [:]  // day → what its present held ("iconKey|badge")
    var caloriesDay = ""              // day the calorie total below is for
    var caloriesPaid: Double = 0      // today's active calories already turned into money
    var lifetimeCalories: Double = 0
    var activeLure: ActiveLure?
    var openedEncounters: [UUID] = []
    var cyclingSkipped: [String: Int] = [:]   // day → steps left out because you were cycling at the time         // wild Pokémon you opened (saw up close) — the Journal shows the rest as silhouettes
    var workouts: [WorkoutRecord] = []        // finished workouts and what they earned (Journal)
    var unseenWorkouts: [String] = []         // workout ids whose "Workout complete!" popup hasn't shown yet
    var garden = Garden()                     // the berry garden (Menu › Garden)
    var ranch = Ranch()                       // the ranch (Menu › Ranch)
    var effects: [ActiveEffect] = []          // items in effect (Repel, Energy Root, Lucky Egg…)
    var stats: [String: Int] = [:]            // running totals for achievements
    var achievementsClaimed: [String] = []

    static let maxParty = 6

    var buddy: OwnedPokemon? { pokemon.first { $0.id == buddyID } }
    var party: [OwnedPokemon] { partyIDs.compactMap { id in pokemon.first { $0.id == id } } }
    var totalBalls: Int { balls.values.reduce(0, +) }

    func index(of id: UUID) -> Int? { pokemon.firstIndex { $0.id == id } }
    func mon(_ id: UUID?) -> OwnedPokemon? { id.flatMap { id in pokemon.first { $0.id == id } } }

    /// Where a Pokémon lives right now.
    func slot(of id: UUID) -> PCSlot? {
        if let i = partyIDs.firstIndex(of: id) { return .party(i) }
        for (b, box) in boxes.enumerated() {
            if let s = box.slots.firstIndex(of: id) { return .box(b, s) }
        }
        return nil
    }

    func locationText(of id: UUID) -> String {
        switch slot(of: id) {
        case .party(let i): return "Party · slot \(i + 1)"
        case .box(let b, let s): return "\(boxes[b].name) · slot \(s + 1)"
        case nil:
            if garden.workers.contains(id) { return "Working in the Garden" }
            if ranch.ranchers.contains(id) { return "Working at the Ranch" }
            return "—"
        }
    }

    /// Pokémon sitting in a PC box (not the party, not away working).
    var boxedIDs: Set<UUID> { Set(boxes.flatMap { $0.slots.compactMap { $0 } }) }
}


// MARK: - Backwards-compatible decoding
// Saves from earlier versions are missing newer fields; fall back to defaults instead of failing.

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
}

extension Trainer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "Trainer")
        trainerID = c.value(.trainerID, Int.random(in: 0...65535))
        secretID = c.value(.secretID, Int.random(in: 0...65535))
        startedOn = c.value(.startedOn, Date())
        appearance = c.value(.appearance, "brendan")
    }
}

extension OwnedPokemon {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        nickname = c.value(.nickname, nil)
        exp = c.value(.exp, 0)
        gender = c.value(.gender, .genderless)
        isShiny = c.value(.isShiny, false)
        nature = c.value(.nature, "Hardy")
        personality = c.value(.personality, 0)
        friendship = c.value(.friendship, 70)
        stepsWalked = c.value(.stepsWalked, 0)
        friendshipStepRemainder = c.value(.friendshipStepRemainder, 0)
        expRemainder = c.value(.expRemainder, 0)
        metersWalked = c.value(.metersWalked, 0)
        ball = c.value(.ball, .poke)
        metDate = c.value(.metDate, Date())
        metLevel = c.value(.metLevel, 5)
        metLocation = c.value(.metLocation, nil)
        metNote = c.value(.metNote, nil)
        otName = c.value(.otName, "Trainer")
        otID = c.value(.otID, 0)
        evolutionDeclinedAtLevel = c.value(.evolutionDeclinedAtLevel, nil)
        evolvedOn = c.value(.evolvedOn, nil)
        abilitySwapped = c.value(.abilitySwapped, false)
        heldItems = c.value(.heldItems, [])
        pickupSteps = c.value(.pickupSteps, 0)
        nextPickupAt = c.value(.nextPickupAt, 1_500)
    }
}

extension GameSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        expPerStep = c.value(.expPerStep, d.expPerStep)
        partyShare = c.value(.partyShare, d.partyShare)
        encounterSteps = c.value(.encounterSteps, d.encounterSteps)
        ballSteps = c.value(.ballSteps, d.ballSteps)
        itemSteps = c.value(.itemSteps, d.itemSteps)
        berrySteps = c.value(.berrySteps, d.berrySteps)
        shinyOdds = c.value(.shinyOdds, d.shinyOdds)
        maxPendingEncounters = c.value(.maxPendingEncounters, d.maxPendingEncounters)
        encounterLifetimeHours = c.value(.encounterLifetimeHours, d.encounterLifetimeHours)
        notifyEncounters = c.value(.notifyEncounters, d.notifyEncounters)
        trackingMode = c.value(.trackingMode, d.trackingMode)
    }
}

extension GameState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameState()
        version = c.value(.version, 2)
        trainer = c.value(.trainer, d.trainer)
        pokemon = c.value(.pokemon, [])
        partyIDs = c.value(.partyIDs, [])
        boxes = c.value(.boxes, d.boxes)
        buddyID = c.value(.buddyID, nil)
        bag = c.value(.bag, [:])
        money = c.value(.money, 0)
        balls = c.value(.balls, d.balls)
        lifetimeSteps = c.value(.lifetimeSteps, 0)
        counters = c.value(.counters, d.counters)
        pending = c.value(.pending, [])
        encounterLog = c.value(.encounterLog, [])
        dexSeen = c.value(.dexSeen, [])
        dexCaught = c.value(.dexCaught, [])
        stepLedger = c.value(.stepLedger, [:])
        distanceLedger = c.value(.distanceLedger, [:])
        settings = c.value(.settings, d.settings)
        lastSyncDate = c.value(.lastSyncDate, Date())
        lastFishedAt = c.value(.lastFishedAt, nil)
        stampDays = c.value(.stampDays, [])
        stampGot = c.value(.stampGot, [:])
        caloriesDay = c.value(.caloriesDay, "")
        caloriesPaid = c.value(.caloriesPaid, 0)
        lifetimeCalories = c.value(.lifetimeCalories, 0)
        activeLure = c.value(.activeLure, nil)
        workouts = c.value(.workouts, [])
        openedEncounters = c.value(.openedEncounters, [])
        cyclingSkipped = c.value(.cyclingSkipped, [:])
        unseenWorkouts = c.value(.unseenWorkouts, [])
        garden = c.value(.garden, Garden())
        ranch = c.value(.ranch, Ranch())
        effects = c.value(.effects, [])
        stats = c.value(.stats, [:])
        achievementsClaimed = c.value(.achievementsClaimed, [])
    }
}

/// A workout from Apple Health and what it earned.
struct WorkoutRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var start: Date
    var end: Date
    var kcal: Int
    var meters: Double
    var countsSteps: Bool          // walking / running / hiking: its steps counted as usual
    var stepsNotCounted: Int       // steps during a non-walking workout, left out of step rewards
    var money: Int                 // ₽ from its calories
    var exp: Int                   // Exp given to your buddy (non-walking workouts)
    var expMonID: UUID?
    var levelUp: String?           // e.g. "Cori grew to Lv. 13!"

    var duration: TimeInterval { end.timeIntervalSince(start) }
}


extension StepCounters {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StepCounters()
        encounterProgress = c.value(.encounterProgress, d.encounterProgress)
        nextEncounterAt = c.value(.nextEncounterAt, d.nextEncounterAt)
        ballProgress = c.value(.ballProgress, d.ballProgress)
        ballsEarnedTotal = c.value(.ballsEarnedTotal, d.ballsEarnedTotal)
        itemProgress = c.value(.itemProgress, d.itemProgress)
        pickupProgress = c.value(.pickupProgress, d.pickupProgress)
        nextPickupAt = c.value(.nextPickupAt, d.nextPickupAt)
        moneyProgress = c.value(.moneyProgress, d.moneyProgress)
        berryProgress = c.value(.berryProgress, d.berryProgress)
    }
}


/// Walking finds that aren't evolution items: friendship berries, bitter herbs, and valuables to sell.
enum ItemCatalog {
    /// Gen 3 friendship berries (the EV-lowering berries — here they just make your Pokémon like you more).
    static let berries = ["pomeg-berry", "kelpsy-berry", "qualot-berry", "hondew-berry", "grepa-berry", "tamato-berry"]
    /// Bitter medicine: Pokémon dislike it, so it lowers friendship.
    static let herbs: [String: Int] = ["energy-powder": 5, "heal-powder": 5, "energy-root": 10, "revival-herb": 15]
    /// Valuables: no use on Pokémon, sell them for Pokédollars.
    static let sellPrice: [String: Int] = [
        "shoal-salt": 20, "shoal-shell": 20, "tiny-mushroom": 50, "heart-scale": 50, "pearl": 100,
        "stardust": 150, "big-mushroom": 250, "big-pearl": 400, "star-piece": 500, "nugget": 1_000,
    ]
    /// Shop prices — dearer than the games, since balls also come free every 100 steps.
    static let shop: [(ball: BallKind, price: Int)] = [
        (.poke, 400), (.great, 1_200), (.ultra, 2_400),
        (.net, 2_000), (.dive, 2_000), (.nest, 2_000), (.repeatBall, 2_000), (.timer, 2_000), (.luxury, 2_000),
    ]

    static func isBerry(_ k: String) -> Bool { berries.contains(k) }

    /// Berries sell too (not a walking-find valuable, so they're kept out of `sellPrice`'s find table).
    static let berrySellPrice = 20
    static func price(_ k: String) -> Int? {
        if let p = sellPrice[k] ?? FieldItems.sellPrice(k) { return p }
        if isBerry(k) { return berrySellPrice }
        if EvolutionShop.isEvolutionItem(k) { return EvolutionShop.price / 2 }      // ₽6,000
        return nil
    }

    /// Gen 3: bigger boost the less a Pokémon likes you.
    static func berryBoost(_ friendship: Int) -> Int { friendship < 100 ? 10 : friendship < 200 ? 5 : 2 }
}


/// Evolution items for sale (stones, trade items…), and a cheaper mystery one that's a random pick.
enum EvolutionShop {
    static let price = 12_000
    static let mysteryPrice = 8_000
    static let mysteryKey = "mystery-evolution-item"

    /// Every item that evolves something in PokéWalk.
    static let items: [String] = {
        var seen: [String] = []
        for sp in Dex.all { for r in sp.evolutions where r.kind == .item { if let i = r.item, !seen.contains(i) { seen.append(i) } } }
        return seen.sorted { Dex.itemName($0) < Dex.itemName($1) }
    }()

    static func isEvolutionItem(_ key: String) -> Bool { items.contains(key) }
}
