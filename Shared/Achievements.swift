import Foundation

// MARK: - Achievements
//
// Goals across everything in PokéWalk, from a first walk to a complete Hoenn Pokédex. Each has a tier
// (Bronze → Diamond) that sets its reward; a few of the hardest have something special on top.

struct AchievementReward {
    var money = 0
    var balls: [BallKind: Int] = [:]
    var items: [String: Int] = [:]

    var lines: [String] {
        var out: [String] = []
        if money > 0 { out.append("₽\(money.formatted())") }
        for (b, n) in balls.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { out.append("\(n) \(b.name)\(n == 1 ? "" : "s")") }
        for (k, n) in items.sorted(by: { $0.key < $1.key }) { out.append(n == 1 ? Dex.itemName(k) : "\(n) \(Dex.itemName(k))") }
        return out
    }
}

struct Achievement: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case walking = "Walking", catching = "Catching", pokemon = "Your Pokémon", items = "Items & fishing"
        case daily = "Daily life", garden = "Garden", ranch = "Ranch", master = "Mastery"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .walking: return "figure.walk"
            case .catching: return "circle.circle.fill"
            case .pokemon: return "heart.fill"
            case .items: return "bag.fill"
            case .daily: return "calendar"
            case .garden: return "leaf.fill"
            case .ranch: return "house.lodge.fill"
            case .master: return "crown.fill"
            }
        }
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tier: Int                 // 1 Bronze … 5 Diamond
    let category: Category
    let target: Int
    let value: (GameState) -> Int
    var special: [String: Int] = [:]

    func progress(_ s: GameState) -> Int { min(target, value(s)) }
    func done(_ s: GameState) -> Bool { value(s) >= target }

    var tierName: String { ["", "Bronze", "Silver", "Gold", "Platinum", "Diamond"][tier] }
    var tierHex: UInt32 { [0, 0xCD7F32, 0xC0C7D0, 0xF5C542, 0x8FE3E0, 0xB9F2FF][tier] }

    var reward: AchievementReward {
        var r: AchievementReward
        switch tier {
        case 1: r = .init(money: 500, balls: [.poke: 3])
        case 2: r = .init(money: 2_500, balls: [.great: 3], items: ["honey": 1])
        case 3: r = .init(money: 10_000, balls: [.ultra: 3], items: ["rare-candy": 3])
        case 4: r = .init(money: 40_000, balls: [.ultra: 5], items: ["rare-candy": 10, "ability-capsule": 1])
        default: r = .init(money: 150_000, balls: [.master: 1], items: ["rare-candy": 25])
        }
        for (k, n) in special { r.items[k, default: 0] += n }
        return r
    }
}

enum Achievements {
    static let shinyCharm = "shiny-charm"

    private static func caught(_ s: GameState, _ range: ClosedRange<Int>) -> Int { s.dexCaught.filter { range.contains($0) }.count }
    private static func stat(_ k: String) -> (GameState) -> Int { { $0.stats[k] ?? 0 } }

    static let all: [Achievement] = {
        typealias A = Achievement
        var a: [A] = [
            // Walking
            A(id: "steps1k", title: "First Steps", detail: "Walk 1,000 steps", symbol: "shoeprints.fill", tier: 1, category: .walking, target: 1_000) { $0.lifetimeSteps },
            A(id: "steps10k", title: "Out and About", detail: "Walk 10,000 steps", symbol: "figure.walk", tier: 1, category: .walking, target: 10_000) { $0.lifetimeSteps },
            A(id: "steps50k", title: "Rambler", detail: "Walk 50,000 steps", symbol: "figure.walk", tier: 2, category: .walking, target: 50_000) { $0.lifetimeSteps },
            A(id: "steps100k", title: "Trailblazer", detail: "Walk 100,000 steps", symbol: "figure.hiking", tier: 2, category: .walking, target: 100_000) { $0.lifetimeSteps },
            A(id: "steps250k", title: "Route Runner", detail: "Walk 250,000 steps", symbol: "figure.hiking", tier: 3, category: .walking, target: 250_000) { $0.lifetimeSteps },
            A(id: "steps500k", title: "Hoenn on Foot", detail: "Walk 500,000 steps", symbol: "map.fill", tier: 3, category: .walking, target: 500_000) { $0.lifetimeSteps },
            A(id: "steps1m", title: "Million Stepper", detail: "Walk 1,000,000 steps", symbol: "medal.fill", tier: 4, category: .walking, target: 1_000_000) { $0.lifetimeSteps },
            A(id: "steps2500k", title: "Walking Legend", detail: "Walk 2,500,000 steps", symbol: "crown.fill", tier: 5, category: .walking, target: 2_500_000) { $0.lifetimeSteps },
            A(id: "day10k", title: "Ten Thousand Club", detail: "Walk 10,000 steps in a day", symbol: "sun.max.fill", tier: 1, category: .walking, target: 10_000) { $0.stepLedger.values.max() ?? 0 },
            A(id: "day20k", title: "Big Day Out", detail: "Walk 20,000 steps in a day", symbol: "sun.max.fill", tier: 2, category: .walking, target: 20_000) { $0.stepLedger.values.max() ?? 0 },
            A(id: "day30k", title: "Marathon Day", detail: "Walk 30,000 steps in a day", symbol: "flame.fill", tier: 3, category: .walking, target: 30_000) { $0.stepLedger.values.max() ?? 0 },
            A(id: "day50k", title: "Unstoppable", detail: "Walk 50,000 steps in a day", symbol: "bolt.fill", tier: 4, category: .walking, target: 50_000) { $0.stepLedger.values.max() ?? 0 },
            A(id: "buddy10k", title: "Best Buds", detail: "Walk 10,000 steps with one buddy", symbol: "pawprint.fill", tier: 1, category: .walking, target: 10_000) { $0.pokemon.map(\.stepsWalked).max() ?? 0 },
            A(id: "buddy100k", title: "Inseparable", detail: "Walk 100,000 steps with one buddy", symbol: "pawprint.fill", tier: 3, category: .walking, target: 100_000) { $0.pokemon.map(\.stepsWalked).max() ?? 0 },

            // Catching
            A(id: "dex1", title: "Gotcha!", detail: "Catch your first wild Pokémon species", symbol: "circle.circle.fill", tier: 1, category: .catching, target: 2) { $0.dexCaught.count },
            A(id: "dex10", title: "Collector", detail: "Catch 10 species", symbol: "book.closed.fill", tier: 1, category: .catching, target: 10) { $0.dexCaught.count },
            A(id: "dex25", title: "Researcher", detail: "Catch 25 species", symbol: "book.closed.fill", tier: 2, category: .catching, target: 25) { $0.dexCaught.count },
            A(id: "dex50", title: "Field Expert", detail: "Catch 50 species", symbol: "book.fill", tier: 2, category: .catching, target: 50) { $0.dexCaught.count },
            A(id: "dex100", title: "Professor's Pride", detail: "Catch 100 species", symbol: "book.fill", tier: 3, category: .catching, target: 100) { $0.dexCaught.count },
            A(id: "dex200", title: "Living Encyclopedia", detail: "Catch 200 species", symbol: "books.vertical.fill", tier: 4, category: .catching, target: 200) { $0.dexCaught.count },
            A(id: "dex386", title: "Pokédex Master", detail: "Catch 386 species", symbol: "sparkles", tier: 5, category: .catching, target: 386,
              value: { $0.dexCaught.count }, special: [shinyCharm: 1]),
            A(id: "kanto", title: "Kanto Complete", detail: "Catch all 151 Kanto species", symbol: "1.circle.fill", tier: 4, category: .catching, target: 151) { caught($0, 1...151) },
            A(id: "hoenn", title: "Hoenn Complete", detail: "Catch all 135 Hoenn species", symbol: "3.circle.fill", tier: 4, category: .catching, target: 135) { caught($0, 252...386) },
            A(id: "caught50", title: "Ball Thrower", detail: "Catch 50 Pokémon", symbol: "tray.full.fill", tier: 2, category: .catching, target: 50) { $0.pokemon.count },
            A(id: "caught250", title: "Full Boxes", detail: "Catch 250 Pokémon", symbol: "tray.full.fill", tier: 3, category: .catching, target: 250) { $0.pokemon.count },
            A(id: "caught1000", title: "Bill's Best Customer", detail: "Catch 1,000 Pokémon", symbol: "server.rack", tier: 4, category: .catching, target: 1_000) { $0.pokemon.count },
            A(id: "shiny1", title: "Something Sparkly", detail: "Catch a shiny Pokémon", symbol: "sparkle", tier: 3, category: .catching, target: 1) { $0.pokemon.filter(\.isShiny).count },
            A(id: "shiny5", title: "Shiny Hunter", detail: "Own 5 shiny Pokémon", symbol: "sparkles", tier: 4, category: .catching, target: 5) { $0.pokemon.filter(\.isShiny).count },
            A(id: "shiny20", title: "Living Shiny Dex", detail: "Own 20 shiny Pokémon", symbol: "sparkles", tier: 5, category: .catching, target: 20) { $0.pokemon.filter(\.isShiny).count },
            A(id: "legend1", title: "Legendary Encounter", detail: "Catch a legendary or mythical Pokémon", symbol: "star.fill", tier: 3, category: .catching, target: 1) { $0.pokemon.filter { $0.species.isLegendary || $0.species.isMythical }.count },
            A(id: "legend5", title: "Myth Collector", detail: "Catch 5 legendary or mythical Pokémon", symbol: "star.circle.fill", tier: 4, category: .catching, target: 5) { $0.pokemon.filter { $0.species.isLegendary || $0.species.isMythical }.count },
            A(id: "met100", title: "People Person", detail: "Meet 100 wild Pokémon", symbol: "eye.fill", tier: 1, category: .catching, target: 100) { $0.encounterLog.count },
            A(id: "met1000", title: "Wild at Heart", detail: "Meet 1,000 wild Pokémon", symbol: "eye.fill", tier: 3, category: .catching, target: 1_000) { $0.encounterLog.count },
            A(id: "balls50", title: "Warm-up", detail: "Throw 50 balls", symbol: "baseball.fill", tier: 1, category: .catching, target: 50, value: stat("ballsThrown")),
            A(id: "balls500", title: "Pitcher", detail: "Throw 500 balls", symbol: "baseball.fill", tier: 2, category: .catching, target: 500, value: stat("ballsThrown")),
            A(id: "balls2500", title: "Golden Arm", detail: "Throw 2,500 balls", symbol: "baseball.fill", tier: 3, category: .catching, target: 2_500, value: stat("ballsThrown")),

            // Your Pokémon
            A(id: "party", title: "Full Team", detail: "Have 6 Pokémon in your party", symbol: "person.3.fill", tier: 1, category: .pokemon, target: 6) { $0.partyIDs.count },
            A(id: "lv25", title: "Growing Up", detail: "Raise a Pokémon to Lv. 25", symbol: "arrow.up.circle.fill", tier: 1, category: .pokemon, target: 25) { $0.pokemon.map(\.level).max() ?? 0 },
            A(id: "lv50", title: "Seasoned", detail: "Raise a Pokémon to Lv. 50", symbol: "arrow.up.circle.fill", tier: 2, category: .pokemon, target: 50) { $0.pokemon.map(\.level).max() ?? 0 },
            A(id: "lv75", title: "Veteran", detail: "Raise a Pokémon to Lv. 75", symbol: "arrow.up.circle.fill", tier: 3, category: .pokemon, target: 75) { $0.pokemon.map(\.level).max() ?? 0 },
            A(id: "lv100", title: "Level 100", detail: "Raise a Pokémon to Lv. 100", symbol: "100.circle.fill", tier: 4, category: .pokemon, target: 100) { $0.pokemon.map(\.level).max() ?? 0 },
            A(id: "friend1", title: "Best Friends", detail: "Max out a Pokémon's friendship", symbol: "heart.fill", tier: 2, category: .pokemon, target: 255) { $0.pokemon.map(\.friendship).max() ?? 0 },
            A(id: "friend5", title: "Beloved Trainer", detail: "Max out 5 Pokémon's friendship", symbol: "heart.circle.fill", tier: 3, category: .pokemon, target: 5) { $0.pokemon.filter { $0.friendship >= 255 }.count },
            A(id: "evo1", title: "What's Happening?", detail: "Evolve a Pokémon", symbol: "arrow.triangle.2.circlepath", tier: 1, category: .pokemon, target: 1, value: stat("evolutions")),
            A(id: "evo10", title: "Metamorphosis", detail: "Evolve 10 Pokémon", symbol: "arrow.triangle.2.circlepath", tier: 2, category: .pokemon, target: 10, value: stat("evolutions")),
            A(id: "evo50", title: "Evolution Expert", detail: "Evolve 50 Pokémon", symbol: "arrow.triangle.2.circlepath.circle.fill", tier: 3, category: .pokemon, target: 50, value: stat("evolutions")),
            A(id: "evo150", title: "Natural Selection", detail: "Evolve 150 Pokémon", symbol: "arrow.triangle.2.circlepath.circle.fill", tier: 4, category: .pokemon, target: 150, value: stat("evolutions")),

            // Items & fishing
            A(id: "found25", title: "Keen Eye", detail: "Find 25 items on walks", symbol: "magnifyingglass", tier: 1, category: .items, target: 25, value: stat("itemsFound")),
            A(id: "found250", title: "Treasure Hunter", detail: "Find 250 items on walks", symbol: "magnifyingglass.circle.fill", tier: 2, category: .items, target: 250, value: stat("itemsFound")),
            A(id: "found1000", title: "Dowsing Machine", detail: "Find 1,000 items on walks", symbol: "dot.radiowaves.left.and.right", tier: 3, category: .items, target: 1_000, value: stat("itemsFound")),
            A(id: "pickup10", title: "Little Helpers", detail: "Your party picks up 10 items", symbol: "hand.raised.fill", tier: 1, category: .items, target: 10, value: stat("pickups")),
            A(id: "pickup100", title: "Pickup Pros", detail: "Your party picks up 100 items", symbol: "hand.raised.fill", tier: 3, category: .items, target: 100, value: stat("pickups")),
            A(id: "sold50", title: "Shopkeeper", detail: "Sell 50 items", symbol: "yensign.circle.fill", tier: 2, category: .items, target: 50, value: stat("itemsSold")),
            A(id: "used25", title: "Well Stocked", detail: "Use 25 items", symbol: "bag.fill", tier: 1, category: .items, target: 25, value: stat("itemsUsed")),
            A(id: "used250", title: "Quartermaster", detail: "Use 250 items", symbol: "bag.fill", tier: 3, category: .items, target: 250, value: stat("itemsUsed")),
            A(id: "fish1", title: "Old Rod", detail: "Get a bite while fishing", symbol: "fish.fill", tier: 1, category: .items, target: 1, value: stat("fishHooked")),
            A(id: "fish50", title: "Angler", detail: "Get 50 bites while fishing", symbol: "fish.fill", tier: 3, category: .items, target: 50, value: stat("fishHooked")),
            A(id: "rich", title: "Saving Up", detail: "Have ₽50,000 at once", symbol: "banknote.fill", tier: 2, category: .items, target: 50_000) { $0.money },
            A(id: "richer", title: "Tycoon", detail: "Have ₽500,000 at once", symbol: "banknote.fill", tier: 4, category: .items, target: 500_000) { $0.money },

            // Daily life
            A(id: "stamp7", title: "A Week of Walks", detail: "Collect 7 daily stamps", symbol: "seal.fill", tier: 1, category: .daily, target: 7) { $0.stampDays.count },
            A(id: "stamp30", title: "Creature of Habit", detail: "Collect 30 daily stamps", symbol: "seal.fill", tier: 2, category: .daily, target: 30) { $0.stampDays.count },
            A(id: "stamp100", title: "Century", detail: "Collect 100 daily stamps", symbol: "checkmark.seal.fill", tier: 3, category: .daily, target: 100) { $0.stampDays.count },
            A(id: "stamp365", title: "A Year Together", detail: "Collect 365 daily stamps", symbol: "checkmark.seal.fill", tier: 5, category: .daily, target: 365,
              value: { $0.stampDays.count }, special: ["lucky-egg": 3, "soothe-bell": 3]),
            A(id: "workout1", title: "Warm Up", detail: "Finish a workout", symbol: "figure.run", tier: 1, category: .daily, target: 1) { $0.workouts.count },
            A(id: "workout25", title: "Regular", detail: "Finish 25 workouts", symbol: "figure.run", tier: 2, category: .daily, target: 25) { $0.workouts.count },
            A(id: "workout100", title: "Athlete", detail: "Finish 100 workouts", symbol: "figure.strengthtraining.traditional", tier: 3, category: .daily, target: 100) { $0.workouts.count },
            A(id: "kcal10k", title: "Burner", detail: "Burn 10,000 active kcal", symbol: "flame.fill", tier: 2, category: .daily, target: 10_000) { Int($0.lifetimeCalories) },
            A(id: "kcal100k", title: "Furnace", detail: "Burn 100,000 active kcal", symbol: "flame.circle.fill", tier: 4, category: .daily, target: 100_000) { Int($0.lifetimeCalories) },

            // Garden
            A(id: "plant1", title: "Green Shoots", detail: "Plant a berry", symbol: "leaf.fill", tier: 1, category: .garden, target: 1, value: stat("berriesPlanted")),
            A(id: "harvest100", title: "Good Harvest", detail: "Pick 100 berries", symbol: "basket.fill", tier: 2, category: .garden, target: 100, value: stat("berriesHarvested")),
            A(id: "harvest1000", title: "Berry Master", detail: "Pick 1,000 berries", symbol: "basket.fill", tier: 4, category: .garden, target: 1_000, value: stat("berriesHarvested")),
            A(id: "workers6", title: "Garden Crew", detail: "Have 6 Pokémon working in the Garden", symbol: "person.3.fill", tier: 2, category: .garden, target: 6) { $0.garden.workers.count },
            A(id: "gardens3", title: "Landowner", detail: "Own 3 gardens", symbol: "square.grid.3x1.below.line.grid.1x2", tier: 4, category: .garden, target: 3) { $0.garden.fields },

            // Ranch
            A(id: "shift1", title: "Clocking In", detail: "Finish a ranch shift", symbol: "clock.fill", tier: 1, category: .ranch, target: 1) { $0.ranch.shiftCount },
            A(id: "shift50", title: "Hard Workers", detail: "Finish 50 ranch shifts", symbol: "clock.fill", tier: 3, category: .ranch, target: 50) { $0.ranch.shiftCount },
            A(id: "shift250", title: "Ranch Hands", detail: "Finish 250 ranch shifts", symbol: "clock.badge.checkmark.fill", tier: 4, category: .ranch, target: 250) { $0.ranch.shiftCount },
            A(id: "fence", title: "Good Fences", detail: "Build the Fence & Gate", symbol: "square.dashed", tier: 2, category: .ranch, target: 3) { $0.ranch.built },
            A(id: "house", title: "Home Sweet Home", detail: "Finish your ranch house", symbol: "house.fill", tier: 3, category: .ranch, target: 7) { $0.ranch.built },
            A(id: "ranchDone", title: "Ranch Tycoon", detail: "Build everything on the ranch", symbol: "building.2.fill", tier: 5, category: .ranch, target: RanchProject.all.count) { $0.ranch.built },
            A(id: "decor25", title: "Interior Designer", detail: "Have 25 decorations in your house", symbol: "sofa.fill", tier: 3, category: .ranch, target: 25) { $0.ranch.placed.count },
            A(id: "styles", title: "Redecorator", detail: "Own every room style", symbol: "paintpalette.fill", tier: 4, category: .ranch, target: 6) { $0.ranch.styles.count },

            // Seasons, eggs, Frontier and contests
            A(id: "swarm1", title: "Swarm Spotter", detail: "Catch a swarm Pokémon", symbol: "ant.fill", tier: 1, category: .catching, target: 1, value: stat("swarmCaught")),
            A(id: "swarm25", title: "Swarm Chaser", detail: "Catch 25 swarm Pokémon", symbol: "ant.circle.fill", tier: 3, category: .catching, target: 25, value: stat("swarmCaught")),
            A(id: "daycare", title: "Daycare Open", detail: "Build the Daycare Hut", symbol: "house.fill", tier: 2, category: .ranch, target: 1) { $0.daycare.built },
            A(id: "daycareDone", title: "Breeding Grounds", detail: "Build everything at the Daycare", symbol: "oval.portrait.fill", tier: 4, category: .ranch, target: DaycareRules.projects.count) { $0.daycare.built },
            A(id: "egg1", title: "It's Hatching!", detail: "Hatch an Egg", symbol: "oval.portrait.fill", tier: 1, category: .pokemon, target: 1, value: stat("eggsHatched")),
            A(id: "egg50", title: "Breeder", detail: "Hatch 50 Eggs", symbol: "oval.portrait.fill", tier: 3, category: .pokemon, target: 50, value: stat("eggsHatched")),
            A(id: "egg250", title: "Master Breeder", detail: "Hatch 250 Eggs", symbol: "oval.portrait.fill", tier: 4, category: .pokemon, target: 250, value: stat("eggsHatched")),
            A(id: "frontier1", title: "Frontier Debut", detail: "Win a Battle Frontier battle", symbol: "flag.2.crossed.fill", tier: 1, category: .master, target: 1, value: stat("frontierWins")),
            A(id: "frontier100", title: "Frontier Regular", detail: "Win 100 Battle Frontier battles", symbol: "flag.2.crossed.fill", tier: 3, category: .master, target: 100, value: stat("frontierWins")),
            A(id: "frontier500", title: "Frontier Legend", detail: "Win 500 Battle Frontier battles", symbol: "flag.checkered", tier: 4, category: .master, target: 500, value: stat("frontierWins")),
            A(id: "badges", title: "Badge Collector", detail: "Earn 8 Gym badges", symbol: "seal.fill", tier: 3, category: .master, target: 8) { $0.frontier.badges.count },
            A(id: "champion", title: "Hoenn Champion", detail: "Beat the Champion or a Frontier Brain", symbol: "crown.fill", tier: 4, category: .master, target: 1, value: stat("championWins")),
            A(id: "brains", title: "Frontier Brain Buster", detail: "Beat 5 different Champions and Frontier Brains", symbol: "star.square.fill", tier: 5, category: .master, target: 5) { $0.frontier.symbols.count },
            A(id: "contest1", title: "Showtime", detail: "Win a contest", symbol: "rosette", tier: 1, category: .pokemon, target: 1, value: stat("contestWins")),
            A(id: "contest25", title: "Star Performer", detail: "Win 25 contests", symbol: "rosette", tier: 3, category: .pokemon, target: 25, value: stat("contestWins")),
            A(id: "masterRibbon", title: "Master Rank", detail: "Win a Master Rank contest", symbol: "medal.fill", tier: 4, category: .pokemon, target: 1) { s in
                s.contests.ribbons.values.flatMap { $0 }.filter { $0.hasSuffix("-3") }.count
            },
            A(id: "allMaster", title: "Ribbon Master", detail: "Win Master Rank in all 5 categories", symbol: "medal.star.fill", tier: 5, category: .pokemon, target: 5) { s in
                Set(s.contests.ribbons.values.flatMap { $0 }.filter { $0.hasSuffix("-3") }).count
            },

            // Mastery
            A(id: "ticket", title: "Ticket to Adventure", detail: "Use an event ticket", symbol: "ticket.fill", tier: 3, category: .master, target: 1, value: stat("ticketsUsed")),
            A(id: "legends", title: "Hoenn's Legends", detail: "Catch Mew, Latias or Latios, Deoxys, and Lugia or Ho-Oh", symbol: "star.square.on.square.fill", tier: 5, category: .master, target: 4) { s in
                [s.dexCaught.contains(151), s.dexCaught.contains(380) || s.dexCaught.contains(381),
                 s.dexCaught.contains(386), s.dexCaught.contains(249) || s.dexCaught.contains(250)].filter { $0 }.count
            },
        ]
        a.append(A(id: "ach25", title: "Overachiever", detail: "Claim 25 achievements", symbol: "trophy.fill", tier: 3, category: .master, target: 25) { $0.achievementsClaimed.count })
        let others = a.count
        a.append(A(id: "achAll", title: "Champion", detail: "Claim every other achievement", symbol: "trophy.circle.fill", tier: 5, category: .master, target: others,
                   value: { $0.achievementsClaimed.filter { $0 != "achAll" }.count }, special: ["mystic-ticket": 1, "aurora-ticket": 1]))
        return a
    }()

    static func ready(_ s: GameState) -> [Achievement] { all.filter { !s.achievementsClaimed.contains($0.id) && $0.done(s) } }

    /// Grants the reward and marks it claimed.
    static func claim(_ a: Achievement, in s: inout GameState) -> Bool {
        guard a.done(s), !s.achievementsClaimed.contains(a.id) else { return false }
        let r = a.reward
        s.money += r.money
        for (b, n) in r.balls { s.balls[b, default: 0] += n }
        for (k, n) in r.items { s.bag[k, default: 0] += n }
        s.achievementsClaimed.append(a.id)
        return true
    }

    /// Shiny Charm: shinies three times as likely.
    static func hasShinyCharm(_ s: GameState) -> Bool { (s.bag[shinyCharm] ?? 0) > 0 }
}
