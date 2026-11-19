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
        ("exp-candy-xs", 100, 40), ("exp-candy-s", 800, 30), ("exp-candy-m", 3_000, 18),
        ("exp-candy-l", 10_000, 9), ("exp-candy-xl", 30_000, 3),
    ]
    static func exp(_ key: String) -> Int? { all.first { $0.key == key }?.exp }
    /// How many candies a Pokémon can carry before it stops picking more up.
    static let carryLimit = 5
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
    var heldItems: [String] = []    // Exp. Candies picked up on walks, until you take them

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
    var ballSteps = 100             // steps per Poké Ball
    var itemSteps = 1_500           // steps per found item
    var shinyOdds = 1_000           // each Pokémon has a 1-in-N random chance (not a guaranteed every-Nth)
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
    var nextPickupAt = 300

    var stepsToEncounter: Int { max(0, nextEncounterAt - encounterProgress) }
}

// MARK: - Save game

struct GameState: Codable {
    var version = 2
    var trainer = Trainer.new(named: "Trainer")
    var pokemon: [OwnedPokemon] = []
    var partyIDs: [UUID] = []
    var boxes: [PCBox] = (1...8).map { PCBox(name: "Box \($0)", wallpaper: ($0 - 1) % 8) }
    var buddyID: UUID?
    var bag: [String: Int] = [:]
    var balls: [BallKind: Int] = [.poke: 10]
    var lifetimeSteps = 0
    var counters = StepCounters()
    var pending: [PendingEncounter] = []
    var dexSeen: Set<Int> = []
    var dexCaught: Set<Int> = []
    var stepLedger: [String: Int] = [:]     // "yyyy-MM-dd" -> steps already turned into rewards
    var distanceLedger: [String: Double] = [:]  // "yyyy-MM-dd" -> metres already credited to the buddy
    var settings = GameSettings()
    var lastSyncDate = Date()

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
        case nil: return "—"
        }
    }
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
        heldItems = c.value(.heldItems, [])
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
        balls = c.value(.balls, d.balls)
        lifetimeSteps = c.value(.lifetimeSteps, 0)
        counters = c.value(.counters, d.counters)
        pending = c.value(.pending, [])
        dexSeen = c.value(.dexSeen, [])
        dexCaught = c.value(.dexCaught, [])
        stepLedger = c.value(.stepLedger, [:])
        distanceLedger = c.value(.distanceLedger, [:])
        settings = c.value(.settings, d.settings)
        lastSyncDate = c.value(.lastSyncDate, Date())
    }
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
    }
}
