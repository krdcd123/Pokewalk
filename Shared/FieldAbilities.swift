import Foundation

// MARK: - Abilities outside battle
//
// A Pokémon's ability comes from its species (one of its regular abilities, picked by its personality value,
// as in Gen 3). Your walking buddy's ability works out in the world, like the overworld effects in the games
// (Illuminate draws wild Pokémon, Suction Cups lets you fish…) plus a few PokéWalk-only ones.

enum FieldAbility: Equatable {
    case moreEncounters(Double)      // encounter steps count this much extra
    case moreItems(Double)           // item-find steps count this much extra
    case synchronize                 // wild Pokémon often share the buddy's nature
    case cuteCharm                   // wild Pokémon are more often the opposite gender
    case attractsType(PokeType)      // more wild Pokémon of this type
    case higherLevels(Int)           // wild Pokémon are a few levels higher
    case fishWithoutBait             // Suction Cups
    case betterBites                 // Sticky Hold: bites more likely
    case betterPickup                // Pickup: +10% pickup chance for the buddy
    case honeyGather                 // finds berries more often when it picks things up
    case warmth                      // Flame Body etc.: +15% Exp for the buddy
    case friendly                    // Serene Grace etc.: twice the friendship from walking
    case calmWild                    // Run Away: wild Pokémon flee half as often
    case ballFetch                   // a missed ball is sometimes fetched back

    var text: String {
        switch self {
        case .moreEncounters(let x): return "Wild Pokémon appear more often (\(Int((1 - 1 / x) * 100))% fewer steps)"
        case .moreItems(let x): return "Finds items more often (\(Int((1 - 1 / x) * 100))% fewer steps)"
        case .synchronize: return "Wild Pokémon often share its nature"
        case .cuteCharm: return "Wild Pokémon are more often the opposite gender"
        case .attractsType(let t): return "Draws in more \(t.displayName)-type Pokémon"
        case .higherLevels(let n): return "Wild Pokémon are up to \(n) levels higher"
        case .fishWithoutBait: return "Lets you fish without bait"
        case .betterBites: return "Fish bite more often"
        case .betterPickup: return "Picks up items more often (+10%)"
        case .honeyGather: return "Finds berries more often"
        case .warmth: return "Gains 15% more Exp from walking"
        case .friendly: return "Grows friendly twice as fast"
        case .calmWild: return "Wild Pokémon flee half as often"
        case .ballFetch: return "Sometimes fetches a ball that missed"
        }
    }

    static func of(_ ability: String) -> FieldAbility? {
        switch ability {
        case "Illuminate", "Arena Trap", "No Guard": return .moreEncounters(1.4)
        case "Swarm", "Hustle", "Pressure", "Vital Spirit": return .higherLevels(4)
        case "Keen Eye", "Intimidate": return .higherLevels(3)
        case "Compound Eyes", "Super Luck", "Frisk": return .moreItems(1.3)
        case "Synchronize": return .synchronize
        case "Cute Charm": return .cuteCharm
        case "Magnet Pull": return .attractsType(.steel)
        case "Static", "Lightning Rod": return .attractsType(.electric)
        case "Flash Fire": return .attractsType(.fire)
        case "Storm Drain": return .attractsType(.water)
        case "Harvest": return .attractsType(.grass)
        case "Suction Cups": return .fishWithoutBait
        case "Sticky Hold": return .betterBites
        case "Pickup": return .betterPickup
        case "Honey Gather", "Gluttony", "Cheek Pouch": return .honeyGather
        case "Flame Body", "Magma Armor", "Steam Engine": return .warmth
        case "Serene Grace", "Friend Guard", "Healer": return .friendly
        case "Run Away": return .calmWild
        case "Ball Fetch": return .ballFetch
        default: return nil
        }
    }
}

extension OwnedPokemon {
    /// Its ability (Gen 3 style: the personality value picks between the species' two abilities).
    var abilityName: String? {
        let list = speciesID >= 1 && speciesID <= AbilityData.species.count ? AbilityData.species[speciesID - 1] : []
        guard !list.isEmpty else { return nil }
        return AbilityData.names[list[Int(personality % 2) % list.count]]
    }
    var fieldAbility: FieldAbility? { abilityName.flatMap(FieldAbility.of) }
}

extension GameState {
    /// The walking buddy's out-of-battle ability, if it has one.
    var buddyAbility: FieldAbility? { buddy?.fieldAbility }
}
