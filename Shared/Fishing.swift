import Foundation

/// Fishing: buy a Fishing Rod at the Poké Mart (Key Items), mix berries into bait, and cast — once every
/// 20 minutes. The more berries in the bait, the better the odds of a bite and of something rarer.
enum Fishing {
    static let rodKey = "super-rod"
    static let rodName = "Fishing Rod"
    static let rodPrice = 3_000            // ~300,000 steps at ₽0.01 a step — or sell a few valuables
    static let cooldown: TimeInterval = 20 * 60
    static let maxBerries = 10

    static func baitKey(berries n: Int) -> String { "bait-\(n)" }
    static func baitBerries(_ key: String) -> Int? {
        guard key.hasPrefix("bait-") else { return nil }
        return Int(key.dropFirst(5))
    }
    static func isBait(_ key: String) -> Bool { baitBerries(key) != nil }

    static func baitName(berries n: Int) -> String {
        let tier = n <= 2 ? "Plain" : n <= 4 ? "Sweet" : n <= 7 ? "Rich" : "Deluxe"
        return "\(tier) Bait (\(n) \(n == 1 ? "berry" : "berries"))"
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

    /// Mixes `n` berries (taking the ones you have most of first) into one bait.
    @discardableResult
    static func makeBait(berries n: Int, in s: inout GameState) -> Bool {
        let have = ItemCatalog.berries.reduce(0) { $0 + (s.bag[$1] ?? 0) }
        guard n >= 1, n <= maxBerries, have >= n else { return false }
        var left = n
        while left > 0 {
            guard let k = ItemCatalog.berries.max(by: { (s.bag[$0] ?? 0) < (s.bag[$1] ?? 0) }),
                  (s.bag[k] ?? 0) > 0 else { return false }
            s.bag[k, default: 0] -= 1
            if s.bag[k] == 0 { s.bag[k] = nil }
            left -= 1
        }
        s.bag[baitKey(berries: n), default: 0] += 1
        return true
    }

    enum Result { case bite(PendingEncounter), nothing, notReady }

    /// Casts with a bait: uses it up and starts the 20-minute cooldown, then maybe hooks something.
    static func cast(bait key: String, in s: inout GameState, location: MetLocation?, now: Date = .now) -> Result {
        guard (s.bag[rodKey] ?? 0) > 0, let n = baitBerries(key), (s.bag[key] ?? 0) > 0,
              cooldownLeft(s, now: now) == 0 else { return .notReady }
        s.bag[key, default: 0] -= 1
        if s.bag[key] == 0 { s.bag[key] = nil }
        s.lastFishedAt = now
        // No nibble: the bait's gone, but you can cast again straight away
        guard Double.random(in: 0..<1) < biteChance(berries: n) else { s.lastFishedAt = nil; return .nothing }

        let tiers = [common, uncommon, rare].map { $0.filter { $0 <= Dex.count } }
        let tier = GameRules.weightedPick(Array(zip([0, 1, 2], tierWeights(berries: n))).filter { !tiers[$0.0].isEmpty })
        let sp = GameRules.weightedPick(tiers[tier].map { (Dex.species($0), GameRules.rarityWeight(Dex.species($0))) })
        var level = min(55, 3 + s.lifetimeSteps / 6_000) + tier * 4 + n / 3 + Int.random(in: -2...2)
        level = max(1, min(100, max(level, sp.minimumWildLevel)))
        return .bite(PendingEncounter(speciesID: sp.id, level: level, gender: GameRules.rollGender(sp),
                                      isShiny: Int.random(in: 0..<max(1, s.settings.shinyOdds)) == 0,
                                      nature: Dex.natures.randomElement()!, personality: .random(in: 0...UInt32.max),
                                      appearedAt: now, expiresAt: now.addingTimeInterval(30 * 60),
                                      location: location, habitat: .watersEdge))
    }
}
