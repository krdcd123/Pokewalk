import Foundation

// MARK: - Daycare & Eggs
//
// Built up on the ranch like everything else. Leave two compatible Pokémon and, as you walk, they may find an
// Egg. Carry up to six Eggs; they hatch after enough steps (bigger, rarer Pokémon take much longer). Eggs are
// more likely to be shiny than wild Pokémon.

struct Egg: Codable, Identifiable, Hashable {
    var id = UUID()
    var speciesID: Int
    var stepsLeft: Int
    var total: Int
    var isShiny: Bool
    var nature: String
    var personality: UInt32
    var gender: Gender
    var foundAt: Date
}

struct Daycare: Codable, Equatable, Hashable {
    var built = 0
    var building: RanchBuild?
    var parents: [UUID] = []
    var eggProgress = 0
    var waiting: Egg?                 // found, waiting to be picked up
    var basket: [Egg] = []            // carried, counting down
    var hatched = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        built = (try? c.decodeIfPresent(Int.self, forKey: .built)) ?? 0
        building = try? c.decodeIfPresent(RanchBuild.self, forKey: .building)
        parents = (try? c.decodeIfPresent([UUID].self, forKey: .parents)) ?? []
        eggProgress = (try? c.decodeIfPresent(Int.self, forKey: .eggProgress)) ?? 0
        waiting = try? c.decodeIfPresent(Egg.self, forKey: .waiting)
        basket = (try? c.decodeIfPresent([Egg].self, forKey: .basket)) ?? []
        hatched = (try? c.decodeIfPresent(Int.self, forKey: .hatched)) ?? 0
    }

    func has(_ p: Int) -> Bool { built > p }
    var open: Bool { has(0) }
    static let basketSize = 6
    var nextProject: RanchProject? { DaycareRules.projects.first { $0.id == built } }
}

enum DaycareRules {
    /// Built with ranch materials (the Fence & Gate must be up first).
    static let projects: [RanchProject] = [
        .init(id: 0, name: "Daycare Hut", symbol: "house.fill", text: "A cosy hut where two Pokémon can stay together.",
              cost: [.wood: 140, .stone: 90, .fibre: 60], money: 8_000, hours: 36, reward: "Leave two Pokémon · Eggs", ticket: nil),
        .init(id: 1, name: "Nursery", symbol: "bed.double.fill", text: "Soft bedding — the pair get along better.",
              cost: [.clay: 180, .fibre: 180], money: 15_000, hours: 48, reward: "Eggs found 50% more often", ticket: nil),
        .init(id: 2, name: "Incubator", symbol: "heater.vertical.fill", text: "Keeps Eggs snug and warm.",
              cost: [.stone: 300, .clay: 300], money: 30_000, hours: 72, reward: "Eggs hatch 25% faster", ticket: nil),
        .init(id: 3, name: "Oval Garden", symbol: "oval.portrait.fill", text: "A walled garden the pair love — and an Oval Charm.",
              cost: [.wood: 450, .fibre: 350, .clay: 250], money: 60_000, hours: 120, reward: "Eggs found twice as often · Oval Charm", ticket: nil),
    ]
    static func canStart(_ s: GameState) -> Bool { s.ranch.has(2) }

    static let stepsPerCheck = 1_000

    /// Chance of an Egg per 1,000 steps (0 = they can't breed).
    static func compatibility(_ a: OwnedPokemon, _ b: OwnedPokemon) -> Double {
        let ga = SpeciesData.eggGroups(a.speciesID), gb = SpeciesData.eggGroups(b.speciesID)
        if ga.contains(15) || gb.contains(15) { return 0 }
        let dittoA = ga.contains(13), dittoB = gb.contains(13)
        if dittoA && dittoB { return 0 }
        if dittoA || dittoB { return 0.2 }
        guard (a.gender == .male && b.gender == .female) || (a.gender == .female && b.gender == .male) else { return 0 }
        guard !Set(ga).isDisjoint(with: gb) else { return 0 }
        return GardenRules.familyRoot(a.speciesID) == GardenRules.familyRoot(b.speciesID) ? 0.5 : 0.35
    }

    static func compatibilityText(_ c: Double) -> String {
        switch c {
        case 0.45...: return "The two seem to get along very well!"
        case 0.3...: return "The two seem to get along."
        case 0.01...: return "The two don't seem to like each other much."
        default: return "The two prefer to play with other Pokémon than each other."
        }
    }

    static func multiplier(_ d: Daycare) -> Double { (d.has(1) ? 1.5 : 1) * (d.has(3) ? 2 : 1) }

    /// What hatches: the mother's (or the non-Ditto parent's) family's first stage.
    static func makeEgg(_ a: OwnedPokemon, _ b: OwnedPokemon, settings: GameSettings, shinyCharm: Bool, at date: Date) -> Egg {
        let aDitto = SpeciesData.eggGroups(a.speciesID).contains(13)
        let bDitto = SpeciesData.eggGroups(b.speciesID).contains(13)
        let mother = aDitto ? b : bDitto ? a : (a.gender == .female ? a : b)
        let species = GardenRules.familyRoot(mother.speciesID)
        let sp = Dex.species(species)
        // Eggs: twice the wild shiny chance, three times that with the Shiny Charm
        let odds = max(1, settings.shinyOdds / 2 / (shinyCharm ? 3 : 1))
        let steps = SpeciesData.hatchCycles(species) * 256
        return Egg(speciesID: species, stepsLeft: steps, total: steps, isShiny: Int.random(in: 0..<odds) == 0,
                   nature: Bool.random() ? mother.nature : Dex.natures.randomElement()!,
                   personality: .random(in: 0...UInt32.max), gender: GameRules.rollGender(sp), foundAt: date)
    }

    /// Steps through the Daycare: maybe find an Egg, count carried Eggs down. Returns hatched Pokémon.
    static func walk(_ steps: Int, in s: inout GameState, at date: Date) -> (found: Bool, hatched: [OwnedPokemon]) {
        var found = false
        var hatched: [OwnedPokemon] = []
        let d = s.daycare
        if d.open, d.waiting == nil, d.parents.count == 2,
           let a = s.mon(d.parents[0]), let b = s.mon(d.parents[1]) {
            let c = compatibility(a, b)
            if c > 0 {
                s.daycare.eggProgress += steps
                while s.daycare.eggProgress >= stepsPerCheck && s.daycare.waiting == nil {
                    s.daycare.eggProgress -= stepsPerCheck
                    if Double.random(in: 0..<1) < min(0.95, c * multiplier(d)) {
                        s.daycare.waiting = makeEgg(a, b, settings: s.settings, shinyCharm: Achievements.hasShinyCharm(s), at: date)
                        found = true
                    }
                }
            }
        }
        // Carried Eggs: the Incubator and a Flame Body buddy speed them up
        var rate = d.has(2) ? 1.25 : 1
        if s.buddyAbility == .warmth { rate *= 2 }
        let n = Int((Double(steps) * rate).rounded())
        for i in s.daycare.basket.indices { s.daycare.basket[i].stepsLeft -= n }
        for egg in s.daycare.basket where egg.stepsLeft <= 0 {
            var mon = GameRules.makePokemon(species: egg.speciesID, level: 1, ball: .poke, trainer: s.trainer,
                                            settings: s.settings, location: nil, note: "Hatched from an Egg", date: date)
            mon.isShiny = egg.isShiny; mon.nature = egg.nature; mon.personality = egg.personality; mon.gender = egg.gender
            mon.friendship = 120
            GameRules.store(mon, in: &s)
            s.dexSeen.insert(egg.speciesID)
            s.dexCaught.insert(egg.speciesID)
            s.daycare.hatched += 1
            s.stats["eggsHatched", default: 0] += 1
            hatched.append(mon)
        }
        s.daycare.basket.removeAll { $0.stepsLeft <= 0 }
        return (found, hatched)
    }
}

enum EggGroups {
    static func name(_ id: Int) -> String {
        ["", "Monster", "Water 1", "Bug", "Flying", "Field", "Fairy", "Grass", "Human-Like", "Water 3", "Mineral",
         "Amorphous", "Water 2", "Ditto", "Dragon", "Undiscovered"][min(15, max(0, id))]
    }
}
