import Foundation

/// Fishing: buy a Fishing Rod at the Poké Mart (Key Items), mix berries into bait, and cast — once every
/// 20 minutes. The more berries in the bait, the better the odds of a bite and of something rarer.
enum Fishing {
    static let rodKey = "super-rod"
    static let rodName = "Fishing Rod"
    static let rodPrice = 3_000            // ~300,000 steps at ₽0.01 a step — or sell a few valuables
    static let cooldown: TimeInterval = 20 * 60
    static let maxBerries = 10

    // Keys: "bait-<berries>" (mixed flavours) or "bait-<berries>-<flavour>", same for "lure-…".
    static func baitKey(berries n: Int, flavor: Flavor? = nil) -> String { "bait-\(n)" + (flavor.map { "-" + $0.rawValue } ?? "") }
    static func baitBerries(_ key: String) -> Int? { count(key, prefix: "bait") }
    static func isBait(_ key: String) -> Bool { baitBerries(key) != nil }
    private static func count(_ key: String, prefix: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, parts[0] == prefix else { return nil }
        return Int(parts[1])
    }
    /// The flavour a bait or lure was made with (nil = mixed).
    static func flavor(_ key: String) -> Flavor? {
        let parts = key.split(separator: "-")
        guard parts.count >= 3 else { return nil }
        return Flavor(rawValue: String(parts[2]))
    }
    /// Bag icon: bait is a pot of Honey; a lure is an incense that matches its flavour.
    static func iconKey(_ key: String) -> String? {
        if isBait(key) { return "honey" }
        guard isLure(key) else { return nil }
        switch flavor(key) {
        case .spicy: return "full-incense"
        case .dry: return "odd-incense"
        case .sweet: return "rose-incense"
        case .bitter: return "pure-incense"
        case .sour: return "wave-incense"
        case nil: return "lax-incense"
        }
    }
    static func name(_ key: String) -> String? {
        if let n = baitBerries(key) { return baitName(berries: n, flavor: flavor(key)) }
        if let n = lureBerries(key) { return lureName(berries: n, flavor: flavor(key)) }
        return nil
    }

    /// Berry flavours (Gen 3 Pokéblock flavours). A bait or lure takes the flavour most of its berries have,
    /// and that nudges what it attracts.
    enum Flavor: String, CaseIterable, Codable {
        case spicy, dry, sweet, bitter, sour
        var name: String { rawValue.capitalized }

        static func of(berry key: String) -> Flavor? {
            switch key {
            case "pomeg-berry", "tamato-berry", "cheri-berry", "figy-berry", "razz-berry", "spelon-berry": return .spicy
            case "kelpsy-berry", "chesto-berry", "wiki-berry", "bluk-berry", "cornn-berry", "pamtre-berry": return .dry
            case "qualot-berry", "pecha-berry", "mago-berry", "nanab-berry", "magost-berry", "watmel-berry": return .sweet
            case "hondew-berry", "rawst-berry", "aguav-berry", "wepear-berry", "rabuta-berry", "durin-berry": return .bitter
            case "grepa-berry", "aspear-berry", "iapapa-berry", "pinap-berry", "nomel-berry", "belue-berry": return .sour
            default: return nil
            }
        }
        /// The flavour with the most berries; a tie means it's mixed (nil).
        static func dominant(_ picks: [String: Int]) -> Flavor? {
            var tally: [Flavor: Int] = [:]
            for (k, n) in picks where n > 0 { if let f = of(berry: k) { tally[f, default: 0] += n } }
            guard let top = tally.max(by: { $0.value < $1.value }) else { return nil }
            return tally.values.filter { $0 == top.value }.count > 1 ? nil : top.key
        }

        /// Lures: wild Pokémon of these types are twice as likely to be the one attracted.
        var lureTypes: Set<PokeType> {
            switch self {
            case .spicy: return [.fire, .fighting, .dragon]
            case .dry: return [.flying, .psychic, .ground, .rock]
            case .sweet: return [.normal, .fairy, .grass, .bug]
            case .bitter: return [.poison, .dark, .ghost, .steel]
            case .sour: return [.electric, .ice, .water]
            }
        }
        /// Bait: these fish bite more often.
        var fish: Set<Int> {
            switch self {
            case .spicy: return [129, 130, 98, 99, 341, 342, 147, 148]          // Magikarp/Gyarados, Krabby, Corphish, Dratini
            case .dry: return [120, 121, 339, 340, 369, 222]                    // Staryu, Barboach, Relicanth, Corsola
            case .sweet: return [118, 119, 370, 349, 320, 60, 61]               // Goldeen, Luvdisc, Feebas, Wailmer, Poliwag
            case .bitter: return [72, 73, 211, 318, 319, 90, 91]                // Tentacool, Qwilfish, Carvanha, Shellder
            case .sour: return [170, 171, 223, 224, 116, 117]                   // Chinchou, Remoraid, Horsea
            }
        }
        var lureHint: String {
            switch self {
            case .spicy: return "Fire, Fighting and Dragon types"
            case .dry: return "Flying, Psychic, Ground and Rock types"
            case .sweet: return "Normal, Fairy, Grass and Bug types"
            case .bitter: return "Poison, Dark, Ghost and Steel types"
            case .sour: return "Electric, Ice and Water types"
            }
        }
        var baitHint: String {
            switch self {
            case .spicy: return "Magikarp, Krabby, Corphish and Dratini"
            case .dry: return "Staryu, Barboach, Corsola and Relicanth"
            case .sweet: return "Goldeen, Luvdisc, Feebas, Wailmer and Poliwag"
            case .bitter: return "Tentacool, Qwilfish, Carvanha and Shellder"
            case .sour: return "Chinchou, Remoraid and Horsea"
            }
        }
    }
    /// How much more likely matching Pokémon are.
    static let flavorBoost = 2.0

    // MARK: Lures — set one going and after 30 minutes it attracts a wild Pokémon (better lure, rarer Pokémon)

    static let lureDuration: TimeInterval = 30 * 60
    static func lureKey(berries n: Int, flavor: Flavor? = nil) -> String { "lure-\(n)" + (flavor.map { "-" + $0.rawValue } ?? "") }
    static func lureBerries(_ key: String) -> Int? { count(key, prefix: "lure") }
    static func isLure(_ key: String) -> Bool { lureBerries(key) != nil }
    static func lureName(berries n: Int, flavor: Flavor? = nil) -> String {
        let tier = n <= 2 ? "Plain" : n <= 4 ? "Fine" : n <= 7 ? "Rich" : "Deluxe"
        return "\(tier) \(flavor.map { $0.name + " " } ?? "")Lure (\(n) \(n == 1 ? "berry" : "berries"))"
    }
    /// How many Pokémon the lure "considers" — it brings the rarest of them, a few levels higher.
    static func lurePicks(berries n: Int) -> Int { 1 + n / 2 }
    static func lureLevelBonus(berries n: Int) -> Int { n / 3 }

    /// Shop prices (a berry sells for ₽20, so buying ready-made costs a fair bit more than making your own).
    static let shopSizes = [2, 4, 6, 10]
    static func price(_ key: String) -> Int? {
        if let n = baitBerries(key) { return n * 60 }
        if let n = lureBerries(key) { return n * 90 }
        return nil
    }

    static func baitName(berries n: Int, flavor: Flavor? = nil) -> String {
        let tier = n <= 2 ? "Plain" : n <= 4 ? "Fine" : n <= 7 ? "Rich" : "Deluxe"
        return "\(tier) \(flavor.map { $0.name + " " } ?? "")Bait (\(n) \(n == 1 ? "berry" : "berries"))"
    }

    /// The Pokémon you can fish up, from the rod tables of Red/Blue, Gold/Silver and Ruby/Sapphire/Emerald.
    static let common = [129, 72, 118, 60]                                  // Magikarp, Tentacool, Goldeen, Poliwag
    static let uncommon = [116, 98, 120, 90, 170, 223, 222, 211, 318, 320, 339, 341, 119, 61, 370]
    static let rare = [130, 73, 117, 99, 147, 148, 349, 319, 340, 342, 171, 224, 369, 121, 91]

    /// Chance something bites: 73% with one berry, up to 100% with ten.
    static func biteChance(berries n: Int) -> Double { min(1, 0.7 + 0.03 * Double(n)) }

    /// How likely each group is (common, uncommon, rare) for bait made from `n` berries.
    static func tierWeights(berries n: Int) -> [Double] {
        let q = Double(max(1, min(maxBerries, n)))
        return [max(10, 70 - 6 * q), 25 + 2 * q, 5 + 4 * q]
    }

    static func cooldownLeft(_ s: GameState, now: Date = .now) -> TimeInterval {
        guard let last = s.lastFishedAt else { return 0 }
        return max(0, cooldown - now.timeIntervalSince(last))
    }

    /// Mixes the berries you picked into one bait — or a lure.
    @discardableResult
    static func makeBait(using picks: [String: Int], lure: Bool, in s: inout GameState) -> Bool {
        let n = picks.values.reduce(0, +)
        guard n >= 1, n <= maxBerries,
              picks.allSatisfy({ ItemCatalog.isBerry($0.key) && $0.value >= 0 && (s.bag[$0.key] ?? 0) >= $0.value })
        else { return false }
        for (k, c) in picks where c > 0 {
            s.bag[k, default: 0] -= c
            if s.bag[k] == 0 { s.bag[k] = nil }
        }
        let f = Flavor.dominant(picks)
        s.bag[lure ? lureKey(berries: n, flavor: f) : baitKey(berries: n, flavor: f), default: 0] += 1
        return true
    }

    /// Mixes `n` berries (taking the ones you have most of first) into one bait — or a lure.
    @discardableResult
    static func makeBait(berries n: Int, lure: Bool = false, in s: inout GameState) -> Bool {
        let have = ItemCatalog.berries.reduce(0) { $0 + (s.bag[$1] ?? 0) }
        guard n >= 1, n <= maxBerries, have >= n else { return false }
        var left = n
        var used: [String: Int] = [:]
        while left > 0 {
            guard let k = ItemCatalog.berries.max(by: { (s.bag[$0] ?? 0) < (s.bag[$1] ?? 0) }),
                  (s.bag[k] ?? 0) > 0 else { return false }
            s.bag[k, default: 0] -= 1
            if s.bag[k] == 0 { s.bag[k] = nil }
            used[k, default: 0] += 1
            left -= 1
        }
        let f = Flavor.dominant(used)
        s.bag[lure ? lureKey(berries: n, flavor: f) : baitKey(berries: n, flavor: f), default: 0] += 1
        return true
    }

    enum Result { case bite(PendingEncounter), nothing, notReady }

    /// Casts with a bait: uses it up and starts the 20-minute cooldown, then maybe hooks something.
    static func cast(bait key: String, in s: inout GameState, location: MetLocation?, now: Date = .now) -> Result {
        // Suction Cups: cast with no bait at all (key "")
        let noBait = key.isEmpty && s.buddyAbility == .fishWithoutBait
        guard (s.bag[rodKey] ?? 0) > 0, cooldownLeft(s, now: now) == 0,
              noBait || ((s.bag[key] ?? 0) > 0 && baitBerries(key) != nil) else { return .notReady }
        let n = noBait ? 0 : baitBerries(key)!
        if !noBait {
            s.bag[key, default: 0] -= 1
            if s.bag[key] == 0 { s.bag[key] = nil }
        }
        s.lastFishedAt = now
        // No nibble: the bait's gone, but you can cast again straight away
        let bite = min(1, biteChance(berries: n) * (noBait ? 0.6 : 1) + (s.buddyAbility == .betterBites ? 0.15 : 0))
        guard Double.random(in: 0..<1) < bite else { s.lastFishedAt = nil; return .nothing }

        let tiers = [common, uncommon, rare].map { $0.filter { $0 <= Dex.count } }
        let tier = GameRules.weightedPick(Array(zip([0, 1, 2], tierWeights(berries: n))).filter { !tiers[$0.0].isEmpty })
        let liked = noBait ? [] : flavor(key)?.fish ?? []
        let sp = GameRules.weightedPick(tiers[tier].map { id in
            (Dex.species(id), GameRules.rarityWeight(Dex.species(id)) * (liked.contains(id) ? flavorBoost : 1))
        })
        var level = min(55, 3 + s.lifetimeSteps / 6_000) + tier * 4 + n / 3 + Int.random(in: -2...2)
        level = max(1, min(100, max(level, sp.minimumWildLevel)))
        return .bite(PendingEncounter(speciesID: sp.id, level: level, gender: GameRules.rollGender(sp),
                                      isShiny: Int.random(in: 0..<max(1, s.settings.shinyOdds)) == 0,
                                      nature: Dex.natures.randomElement()!, personality: .random(in: 0...UInt32.max),
                                      appearedAt: now, expiresAt: now.addingTimeInterval(30 * 60),
                                      location: location, habitat: .watersEdge))
    }
}
