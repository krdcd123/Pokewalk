import Foundation

// MARK: - Items with effects out in the world
//
// Herbs, Repels, flutes, Lucky Eggs… Used from the Bag, they give a boost for a number of steps or hours
// (bitter herbs cost your buddy some friendship). Vitamins, Mints and the Ability Capsule are used on a
// Pokémon. Revive brings back a wild Pokémon that got away.

struct ActiveEffect: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case encounters, items, repel, exp, friendship, money, calm }
    var id = UUID()
    var kind: Kind
    var strength: Double                // multiplier (encounters 1.5 = 50% more often)
    var stepsLeft: Int?
    var endsAt: Date?
    var source: String                  // the item that started it

    func active(at date: Date) -> Bool {
        if let s = stepsLeft, s <= 0 { return false }
        if let e = endsAt, e <= date { return false }
        return true
    }
}

enum FieldItems {
    struct Def {
        let key: String
        let effects: [(ActiveEffect.Kind, Double)]
        let steps: Int?
        let hours: Double?
        let friendshipCost: Int
        let text: String
        let sell: Int
    }

    /// Items used straight from the Bag.
    static let field: [Def] = [
        .init(key: "energy-powder", effects: [(.items, 1.25)], steps: 2_000, hours: nil, friendshipCost: 5,
              text: "Bitter! Items turn up 25% more often for 2,000 steps. Your buddy's friendship −5.", sell: 250),
        .init(key: "energy-root", effects: [(.items, 1.5)], steps: 3_000, hours: nil, friendshipCost: 10,
              text: "Very bitter! Items turn up 50% more often for 3,000 steps. Your buddy's friendship −10.", sell: 400),
        .init(key: "heal-powder", effects: [(.encounters, 1.25)], steps: 2_000, hours: nil, friendshipCost: 5,
              text: "Bitter! Wild Pokémon appear 25% more often for 2,000 steps. Your buddy's friendship −5.", sell: 250),
        .init(key: "revival-herb", effects: [(.encounters, 1.5), (.items, 1.5)], steps: 4_000, hours: nil, friendshipCost: 15,
              text: "Horribly bitter! Wild Pokémon and items 50% more often for 4,000 steps. Your buddy's friendship −15.", sell: 800),
        .init(key: "repel", effects: [(.repel, 1)], steps: nil, hours: 1, friendshipCost: 0,
              text: "No wild Pokémon for 1 hour (steps still count for everything else).", sell: 175),
        .init(key: "super-repel", effects: [(.repel, 1)], steps: nil, hours: 3, friendshipCost: 0,
              text: "No wild Pokémon for 3 hours.", sell: 300),
        .init(key: "max-repel", effects: [(.repel, 1)], steps: nil, hours: 8, friendshipCost: 0,
              text: "No wild Pokémon for 8 hours — handy for a work day.", sell: 400),
        .init(key: "white-flute", effects: [(.encounters, 1.5)], steps: nil, hours: 2, friendshipCost: 0,
              text: "Wild Pokémon appear 50% more often for 2 hours.", sell: 250),
        .init(key: "black-flute", effects: [(.encounters, 0.5), (.items, 1.5)], steps: nil, hours: 2, friendshipCost: 0,
              text: "Fewer wild Pokémon but items 50% more often, for 2 hours.", sell: 250),
        .init(key: "lucky-egg", effects: [(.exp, 1.5)], steps: nil, hours: 24, friendshipCost: 0,
              text: "Your Pokémon get 50% more Exp from walking for 24 hours.", sell: 1_500),
        .init(key: "soothe-bell", effects: [(.friendship, 2)], steps: nil, hours: 24, friendshipCost: 0,
              text: "Its soothing chime: friendship grows twice as fast for 24 hours.", sell: 1_000),
        .init(key: "amulet-coin", effects: [(.money, 2)], steps: nil, hours: 24, friendshipCost: 0,
              text: "Double Pokédollars from selling, the Ranch and workouts for 24 hours.", sell: 1_500),
        .init(key: "smoke-ball", effects: [(.calm, 0.5)], steps: nil, hours: 1, friendshipCost: 0,
              text: "For an hour, wild Pokémon are half as likely to flee.", sell: 200),
        .init(key: "honey", effects: [], steps: nil, hours: nil, friendshipCost: 0,
              text: "Its sweet scent draws a wild Pokémon to you right now.", sell: 150),
        .init(key: "revive", effects: [], steps: nil, hours: nil, friendshipCost: 0,
              text: "Brings back the last wild Pokémon that fled or left, for 30 minutes.", sell: 750),
        .init(key: "max-revive", effects: [(.calm, 0.5)], steps: nil, hours: 0.5, friendshipCost: 0,
              text: "Brings back the last wild Pokémon that got away for an hour — and it's calmer.", sell: 2_000),
    ]
    static func fieldDef(_ key: String) -> Def? { field.first { $0.key == key } }
    static func isField(_ key: String) -> Bool { fieldDef(key) != nil }

    /// Vitamins: a big chunk of Exp (Pokémon quite like them).
    static let vitamins = ["hp-up", "protein", "iron", "calcium", "zinc", "carbos"]
    static let vitaminExp = 2_500
    static let mints: [String] = Dex.natures.filter { n in
        let i = Dex.natures.firstIndex(of: n)!
        return i / 5 != i % 5 || n == "Serious"
    }.map { $0.lowercased() + "-mint" }
    static func mintNature(_ key: String) -> String? {
        guard mints.contains(key) else { return nil }
        let n = key.replacingOccurrences(of: "-mint", with: "")
        return Dex.natures.first { $0.lowercased() == n }
    }
    static let abilityCapsule = "ability-capsule"

    static func sellPrice(_ key: String) -> Int? {
        if let d = fieldDef(key) { return d.sell }
        if vitamins.contains(key) { return 2_400 }
        if mints.contains(key) { return 5_000 }
        if key == abilityCapsule { return 10_000 }
        return nil
    }

    static func description(_ key: String) -> String? {
        if let d = fieldDef(key) { return d.text }
        if vitamins.contains(key) { return "A nutritious drink: gives a Pokémon \(vitaminExp.formatted()) Exp and it likes you a little more." }
        if let n = mintNature(key) {
            let a = RanchAttribute.of(nature: n)
            return "Changes a Pokémon's nature to \(n) (Ranch attribute: \(a.name))."
        }
        if key == abilityCapsule { return "Switches a Pokémon to its other ability." }
        return nil
    }

    /// Items found on walks (added to the walking finds).
    static let finds: [(String, Double)] = [
        ("energy-powder", 2.5), ("energy-root", 1.5), ("heal-powder", 2.5), ("revival-herb", 0.8),
        ("repel", 3), ("super-repel", 1.5), ("max-repel", 0.8), ("honey", 3), ("revive", 1.5), ("max-revive", 0.3),
        ("white-flute", 1), ("black-flute", 1), ("smoke-ball", 1.2), ("soothe-bell", 0.4), ("lucky-egg", 0.3),
        ("amulet-coin", 0.3), ("hp-up", 0.5), ("protein", 0.5), ("iron", 0.5), ("calcium", 0.5), ("zinc", 0.5),
        ("carbos", 0.5), ("ability-capsule", 0.12),
    ] + mints.map { ($0, 0.08) }

    /// Shop supplies (Poké Mart).
    static let shop: [(key: String, price: Int)] = [
        ("repel", 700), ("super-repel", 1_200), ("max-repel", 1_800), ("honey", 900), ("revive", 3_000),
        ("energy-powder", 1_000), ("heal-powder", 1_000),
    ]

    // MARK: Effect totals

    static func multiplier(_ kind: ActiveEffect.Kind, in s: GameState, at date: Date = .now) -> Double {
        s.effects.filter { $0.kind == kind && $0.active(at: date) }.reduce(1) { $0 * $1.strength }
    }
    static func repelled(_ s: GameState, at date: Date = .now) -> Bool {
        s.effects.contains { $0.kind == .repel && $0.active(at: date) }
    }

    /// Counts down step-based effects and drops finished ones.
    static func spend(steps: Int, in s: inout GameState, at date: Date) {
        for i in s.effects.indices { if let left = s.effects[i].stepsLeft { s.effects[i].stepsLeft = left - steps } }
        s.effects.removeAll { !$0.active(at: date) }
    }

    // MARK: Using

    enum UseResult: Equatable { case started(String), appeared(PendingEncounter), nothing(String) }

    static func use(_ key: String, in s: inout GameState, context: EncounterContext?, location: MetLocation?,
                    at date: Date = .now) -> UseResult {
        guard let d = fieldDef(key), s.bag[key, default: 0] > 0 else { return .nothing("You don't have one.") }
        var result: UseResult
        switch key {
        case "honey":
            guard let context else { return .nothing("No wild Pokémon around just now.") }
            var enc = GameRules.generateEncounter(context: context, lifetimeSteps: s.lifetimeSteps, settings: s.settings, at: date)
            GameRules.applyBuddyAbility(to: &enc, in: s, context: context, date: date)
            s.pending.append(enc)
            s.dexSeen.insert(enc.speciesID)
            result = .appeared(enc)
        case "revive", "max-revive":
            guard let last = s.encounterLog.last(where: { $0.outcome == .fled || $0.outcome == .left || $0.outcome == .ranAway }) else {
                return .nothing("No wild Pokémon has got away yet.")
            }
            let sp = Dex.species(last.speciesID)
            let enc = PendingEncounter(speciesID: last.speciesID, level: last.level, gender: GameRules.rollGender(sp),
                                       isShiny: last.isShiny, nature: Dex.natures.randomElement()!,
                                       personality: .random(in: 0...UInt32.max), appearedAt: date,
                                       expiresAt: date.addingTimeInterval(key == "max-revive" ? 3600 : 1800),
                                       location: last.location ?? location, habitat: nil)
            s.pending.append(enc)
            result = .appeared(enc)
        default:
            result = .started(d.text)
        }
        for (kind, strength) in d.effects {
            s.effects.append(ActiveEffect(kind: kind, strength: strength, stepsLeft: d.steps,
                                          endsAt: d.hours.map { date.addingTimeInterval($0 * 3600) }, source: key))
        }
        if d.friendshipCost > 0, let id = s.buddyID, let i = s.index(of: id) {
            s.pokemon[i].friendship = max(0, s.pokemon[i].friendship - d.friendshipCost)
        }
        s.bag[key, default: 0] -= 1
        if s.bag[key] == 0 { s.bag[key] = nil }
        s.stats["itemsUsed", default: 0] += 1
        return result
    }
}
