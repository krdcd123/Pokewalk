import SwiftUI

/// The Contest Hall: blend Pokéblocks from Garden berries, feed them to raise condition, enter contests for ribbons.
struct ContestHallView: View {
    @EnvironmentObject private var store: GameStore
    @State private var monID: UUID?
    @State private var category: ContestCategory = .cool
    @State private var rank: ContestRank = .normal
    @State private var staging: ContestEntry?
    @State private var says: String?
    @State private var host: UIImage?

    struct ContestEntry: Identifiable { let id = UUID(); let mon: OwnedPokemon; let category: ContestCategory; let rank: ContestRank }

    private var mon: OwnedPokemon? { monID.flatMap { store.state.mon($0) } ?? store.state.party.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hostCard
                blenderCard
                if let mon { conditionCard(mon); enterCard(mon) }
            }
            .padding()
        }
        .task { if host == nil { host = await PretFiles.sprite("graphics/trainers/front_pics/lady.png") } }
        .fullScreenCover(item: $staging) { e in
            ContestStage(entry: e) { place in
                let prize = store.finishContest(e.mon.id, e.category, e.rank, place: place)
                if let prize { says = "Congratulations! \(e.mon.name) won: \(prize)." }
                else { says = "\(e.mon.name) came \(["", "1st", "2nd", "3rd", "4th"][place]). Raise its \(e.category.name) condition and try again!" }
                staging = nil
            }
        }
    }

    private var hostCard: some View {
        HStack(spacing: 12) {
            Group { if let host { PixelImageView(image: host) } else { ProgressView() } }
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text("Contest Hall").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                Text(says ?? "Make Pokéblocks from your berries to bring out a Pokémon's best side, then show it off in a contest! \(store.state.contests.wins) wins so far.")
                    .font(.rounded(15, .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(22)
    }

    // MARK: Berry Blender

    private var blenderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Berry Blender").font(.rounded(17, .heavy)).foregroundStyle(.white)
            Text("2 berries of one kind make a coloured Pokéblock. One of each of five kinds makes 2 Rainbow Pokéblocks.")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
            ForEach(ContestCategory.allCases) { c in
                HStack(spacing: 10) {
                    ItemSprite(key: c.berry).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.blockName).font(.rounded(14, .heavy)).foregroundStyle(Color(hex: c.hex))
                        Text("\(c.name) +\(ContestRules.blockBoost) · have \(store.state.contests.blocks[c.rawValue] ?? 0) · berries \(store.state.bag[c.berry] ?? 0)")
                            .font(.rounded(11, .bold)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Button {
                        if store.blend(c) { SoundKit.shared.play(.useItem); Haptics.tap() } else { says = "You need 2 \(Dex.itemName(c.berry))s — grow them in the Garden." }
                    } label: {
                        Text("Blend").font(.rounded(13, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .glassCapsule(tint: (store.state.bag[c.berry] ?? 0) >= 2 ? Color(hex: c.hex) : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Image(systemName: "rainbow").foregroundStyle(.white).frame(width: 26)
                Text("Rainbow Pokéblock · all +\(ContestRules.rainbowBoost) · have \(store.state.contests.blocks["rainbow"] ?? 0)")
                    .font(.rounded(13, .heavy)).foregroundStyle(.white)
                Spacer()
                Button {
                    if store.blend(nil) { SoundKit.shared.play(.useItem); Haptics.tap() } else { says = "You need one each of Pomeg, Kelpsy, Qualot, Hondew and Grepa." }
                } label: {
                    Text("Blend").font(.rounded(13, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(22)
    }

    // MARK: Condition

    private func conditionCard(_ mon: OwnedPokemon) -> some View {
        let cond = store.state.contests.condition(mon.id)
        let sheen = store.state.contests.sheen[mon.id.uuidString] ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Condition").font(.rounded(17, .heavy)).foregroundStyle(.white)
                Spacer()
                Menu {
                    ForEach(store.state.party) { m in Button("\(m.name) Lv. \(m.level)") { monID = m.id } }
                } label: {
                    HStack(spacing: 6) {
                        LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 28, height: 28)
                        Text(mon.name).font(.rounded(14, .heavy))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).glassCapsule(interactive: true)
                }
            }
            ForEach(Array(ContestCategory.allCases.enumerated()), id: \.offset) { i, c in
                HStack(spacing: 8) {
                    Image(systemName: c.symbol).foregroundStyle(Color(hex: c.hex)).frame(width: 18)
                    Text(c.name).font(.rounded(13, .bold)).foregroundStyle(.white).frame(width: 52, alignment: .leading)
                    ProgressView(value: Double(cond[i]), total: 255).tint(Color(hex: c.hex))
                    Text("\(cond[i])").font(.rounded(12, .heavy)).monospacedDigit().foregroundStyle(Theme.inkSoft).frame(width: 30)
                    let block = c.rawValue
                    Button {
                        if store.feedBlock(block, to: mon.id) { SoundKit.shared.play(.useItem); Haptics.tap() }
                        else { says = sheen >= ContestRules.maxSheen ? "\(mon.name) can't eat any more Pokéblocks." : "No \(c.blockName)s — blend some first." }
                    } label: {
                        Image(systemName: "fork.knife").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).glassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feed a \(c.blockName)")
                }
            }
            HStack {
                Text("Sheen").font(.rounded(12, .bold)).foregroundStyle(Theme.inkSoft)
                ProgressView(value: Double(sheen), total: Double(ContestRules.maxSheen)).tint(.white)
                Button {
                    if store.feedBlock("rainbow", to: mon.id) { SoundKit.shared.play(.useItem) }
                    else { says = "No Rainbow Pokéblocks." }
                } label: {
                    Label("Rainbow", systemImage: "rainbow").font(.rounded(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5).glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }
            let ribbons = store.state.contests.ribbons(mon.id)
            if !ribbons.isEmpty {
                RibbonRow(ribbons: ribbons)
            }
        }
        .padding(14)
        .glassCard(22)
    }

    // MARK: Enter

    private func enterCard(_ mon: OwnedPokemon) -> some View {
        let top = store.state.contests.unlockedRank(mon.id, category)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Enter a contest").font(.rounded(17, .heavy)).foregroundStyle(.white)
            Picker("Category", selection: $category) {
                ForEach(ContestCategory.allCases) { c in Text(c.name).tag(c) }
            }
            .pickerStyle(.segmented)
            Picker("Rank", selection: $rank) {
                ForEach(ContestRank.allCases) { r in Text(r.name + (r.rawValue > top.rawValue ? " 🔒" : "")).tag(r) }
            }
            .pickerStyle(.segmented)
            Text(rank.rawValue > top.rawValue ? "Win the \(ContestRank(rawValue: rank.rawValue - 1)!.name) Rank \(category.name) Contest with \(mon.name) first."
                 : "Prize: ₽\(rank.prize.formatted()) and a \(category.name) Ribbon" + (rank == .master ? " (the first Master win in each category also gives a doll for your house)" : ""))
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
            Button {
                guard rank.rawValue <= top.rawValue else { Haptics.tap(); return }
                SoundKit.shared.play(.menuOpen)
                staging = ContestEntry(mon: mon, category: category, rank: rank)
            } label: {
                Text("Enter \(mon.name)").font(.rounded(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .glassCapsule(tint: rank.rawValue <= top.rawValue ? Color(hex: category.hex) : nil, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard(22)
    }
}

/// Ribbons as little coloured rosettes.
struct RibbonRow: View {
    let ribbons: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ribbons, id: \.self) { r in
                    let parts = r.split(separator: "-")
                    let c = ContestCategory(rawValue: String(parts.first ?? "")) ?? .cool
                    let rank = ContestRank(rawValue: Int(parts.last ?? "") ?? 0) ?? .normal
                    VStack(spacing: 1) {
                        Image(systemName: "rosette").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: c.hex))
                        Text(rank.name).font(.rounded(9, .heavy)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("\(c.name) Ribbon, \(rank.name) Rank")
                }
            }
        }
    }
}

// MARK: - On stage

private struct ContestStage: View {
    let entry: ContestHallView.ContestEntry
    let done: (Int) -> Void
    @EnvironmentObject private var store: GameStore

    struct Rival: Identifiable { let id = UUID(); let speciesID: Int; let name: String; var score: Double }
    @State private var rivals: [Rival] = []
    @State private var you: Double = 0
    @State private var round = 0           // 0 intro shown, 1…3 appeals, 4 results
    @State private var log: [String] = []
    @State private var lastMove: String?
    @State private var excitement = 0
    @State private var confetti: Date?
    @State private var place = 4

    private var moves: [BattleMove] { MoveData.latestSet(species: entry.mon.speciesID, level: entry.mon.level).map(BattleMove.init(id:)) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: entry.category.hex).opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("\(entry.rank.name) Rank \(entry.category.name) Contest").font(.rounded(20, .black)).foregroundStyle(.white)
                // excitement meter
                HStack(spacing: 4) {
                    Text("Excitement").font(.rounded(12, .heavy)).foregroundStyle(.white)
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < excitement ? "star.fill" : "star").foregroundStyle(.yellow)
                    }
                }
                AnimatedSprite(speciesID: entry.mon.speciesID, shiny: entry.mon.isShiny).frame(width: 140, height: 140)
                // scoreboard
                VStack(spacing: 6) {
                    scoreRow(icon: entry.mon.speciesID, name: entry.mon.name, score: you, me: true)
                    ForEach(rivals) { r in scoreRow(icon: r.speciesID, name: r.name, score: r.score, me: false) }
                }
                .padding(12)
                .glassCard(18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(log.suffix(5).enumerated()), id: \.offset) { _, l in
                            Text(l).font(.rounded(13, .bold)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 96)
                .padding(10)
                .glassCard(16)
                Spacer(minLength: 0)
                if round >= 1 && round <= 3 {
                    Text("Appeal \(round) of 3 — choose a move").font(.rounded(13, .heavy)).foregroundStyle(.white)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(moves, id: \.self) { m in
                            let cat = ContestCategory.of(m.type)
                            Button { appeal(m) } label: {
                                VStack(spacing: 2) {
                                    Text(m.name).font(.rounded(15, .heavy))
                                    HStack(spacing: 2) {
                                        Image(systemName: cat.symbol)
                                        Text(cat.name)
                                        Text(String(repeating: "♥", count: entry.category.hearts(for: cat)))
                                    }
                                    .font(.rounded(11, .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .glassCapsule(tint: Color(hex: cat.hex), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if round == 4 {
                    Text(place == 1 ? "🏆 \(entry.mon.name) wins!" : "\(entry.mon.name) placed \(["", "1st", "2nd", "3rd", "4th"][place]).")
                        .font(.rounded(20, .black)).foregroundStyle(.white)
                    Button { done(place) } label: {
                        Text("Done").font(.rounded(17, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 50).glassCapsule(tint: Theme.teal, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            ConfettiRain(start: confetti).allowsHitTesting(false).ignoresSafeArea()
        }
        .task { start() }
    }

    private func scoreRow(icon: Int, name: String, score: Double, me: Bool) -> some View {
        HStack(spacing: 8) {
            LocalIcon(speciesID: icon, shiny: me && entry.mon.isShiny).frame(width: 30, height: 30)
            Text(name).font(.rounded(14, me ? .black : .bold)).foregroundStyle(me ? .yellow : .white)
            Spacer()
            Text("\(Int(score))").font(.rounded(15, .heavy)).monospacedDigit().foregroundStyle(.white)
                .contentTransition(.numericText(value: score))
        }
    }

    private func start() {
        guard rivals.isEmpty else { return }
        let pool = Dex.all.filter { !$0.isLegendary && !$0.isMythical && $0.generation <= 3 }
        rivals = (0..<3).map { _ in
            let sp = pool.randomElement()!
            return Rival(speciesID: sp.id, name: sp.name, score: Double.random(in: entry.rank.rivalIntro).rounded())
        }
        you = ContestRules.intro(entry.mon, entry.category, in: store.state).rounded()
        log.append("Introduction: \(entry.mon.name)'s \(entry.category.name) condition earned \(Int(you)) points!")
        round = 1
    }

    private func appeal(_ m: BattleMove) {
        let cat = ContestCategory.of(m.type)
        var hearts = entry.category.hearts(for: cat)
        var line = "\(entry.mon.name) used \(m.name)! "
        if lastMove == m.name {
            hearts -= 1
            line += "The crowd is getting bored… "
        }
        if cat == entry.category {
            excitement += 1
            if excitement >= 5 {
                hearts += 5
                excitement = 0
                line += "The crowd went wild! "
                SoundKit.shared.play(.shiny)
            }
        }
        lastMove = m.name
        line += "\(max(0, hearts)) ♥"
        withAnimation { you += Double(max(0, hearts) * 10) }
        log.append(line)
        for i in rivals.indices {
            let h = Int.random(in: entry.rank.rivalHearts)
            withAnimation { rivals[i].score += Double(h * 10) }
        }
        Haptics.tap()
        SoundKit.shared.play(.select)
        if round == 3 { finish() } else { round += 1 }
    }

    private func finish() {
        let ahead = rivals.filter { $0.score > you }.count
        place = ahead + 1
        round = 4
        log.append(place == 1 ? "\(entry.mon.name) is the winner!" : "Results are in…")
        if place == 1 {
            confetti = .now
            SoundKit.shared.play(.useItem)
            Haptics.hold()
        }
    }
}
