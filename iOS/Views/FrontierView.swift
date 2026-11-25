import SwiftUI

/// Party › Battle Frontier: five battles a day, each tougher (and better paid) than the last. The fifth is a
/// Gym Leader — a different one each day, Monday to Saturday. Beat all six in a week and Sunday's fifth battle
/// is the Champion or a legendary Frontier Brain.
struct FrontierView: View {
    @EnvironmentObject private var store: GameStore
    @State private var battling: Fight?
    @State private var result: String?

    struct Fight: Identifiable { let id = UUID(); let number: Int; let trainer: FrontierTrainer }

    var body: some View {
        let f = store.state.frontier
        ScrollView {
            VStack(spacing: 16) {
                statusCard(f)
                ladder(f)
                weekCard(f)
                if !f.badges.isEmpty || !f.symbols.isEmpty { badgeCard(f) }
            }
            .padding()
        }
        .onAppear { store.refreshFrontier() }
        .fullScreenCover(item: $battling) { fight in
            BattleView(number: fight.number, trainer: fight.trainer) { won in
                if let r = store.finishFrontierBattle(fight.number, trainer: fight.trainer, won: won) {
                    result = "You won! " + FrontierRules.rewardText(r)
                } else if !won {
                    result = "You lost to \(fight.trainer.title) \(fight.trainer.name). Rest up and come back tomorrow!"
                }
                battling = nil
            }
        }
    }

    private func statusCard(_ f: Frontier) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flag.2.crossed.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's run: \(f.won)/5").font(.rounded(22, .black)).foregroundStyle(.white)
                    Text(f.lost ? "Defeated — the Frontier reopens tomorrow." : f.won == 5 ? "Cleared! Come back tomorrow for more." : "Your party battles in order; win to move on.")
                        .font(.rounded(13, .bold)).foregroundStyle(f.lost ? .orange : Theme.inkSoft)
                }
                Spacer()
            }
            if let result {
                Text(result).font(.rounded(13, .heavy)).foregroundStyle(.yellow)
            }
            Text("Your Pokémon's levels set the trainers' levels, so it's always a fair fight. \(f.totalWins) wins in total.")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .glassCard(22)
    }

    private func ladder(_ f: Frontier) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(1...5, id: \.self) { n in
                let t = FrontierRules.trainer(for: n, in: store.state)
                let isNext = n == f.won + 1 && !f.lost
                let won = n <= f.won
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(won ? Color.green : isNext ? Color.orange : Color.white.opacity(0.08)).frame(width: 40, height: 40)
                        if won { Image(systemName: "checkmark").font(.system(size: 16, weight: .black)).foregroundStyle(.white) }
                        else { Text("\(n)").font(.rounded(17, .black)).foregroundStyle(.white) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(won || isNext || n == 5 ? "\(t.title) \(t.name)" : "???").font(.rounded(15, .heavy)).foregroundStyle(.white)
                        Text(won || isNext ? "\(t.team.count) Pokémon · Lv. \(t.team.map(\.level).max() ?? 0)" + (t.intro.isEmpty ? "" : " · \(t.intro)")
                             : n == 5 ? t.intro : "A tougher trainer")
                            .font(.rounded(11, .semibold)).foregroundStyle(Theme.inkSoft)
                        Text(FrontierRules.rewardText(FrontierRules.reward(for: n, champion: t.isChampion)))
                            .font(.rounded(11, .bold)).foregroundStyle(Color(hex: 0xF5C542))
                    }
                    Spacer()
                    if isNext && f.won < 5 {
                        Button {
                            SoundKit.shared.play(.menuOpen)
                            result = nil
                            battling = Fight(number: n, trainer: t)
                        } label: {
                            Text("Battle!").font(.rounded(14, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .glassCapsule(tint: .orange, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }

    private func weekCard(_ f: Frontier) -> some View {
        let beaten = f.week == Swarm.week() ? Set(f.leadersBeaten) : []
        return VStack(alignment: .leading, spacing: 8) {
            Text("This week's Gym Leaders").font(.rounded(16, .heavy)).foregroundStyle(.white)
            HStack(spacing: 6) {
                ForEach(Array(FrontierRules.leaders.enumerated()), id: \.offset) { i, l in
                    VStack(spacing: 2) {
                        Image(systemName: beaten.contains(l.key) ? "shield.lefthalf.filled" : "shield")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(beaten.contains(l.key) ? Color(hex: l.type.hex) : Theme.inkSoft)
                        Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][i]).font(.rounded(10, .heavy)).foregroundStyle(.white)
                        Text(l.name).font(.rounded(9, .bold)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(beaten.count >= 6 ? "All six beaten! Sunday's 5th battle is the Champion or a Frontier Brain."
                 : "Beat all six this week (\(beaten.count)/6) and Sunday's 5th battle is the Champion or a legendary Frontier Brain.")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .glassCard(22)
    }

    private func badgeCard(_ f: Frontier) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badges & symbols").font(.rounded(16, .heavy)).foregroundStyle(.white)
            let all = FrontierRules.leaders + [FrontierRules.sundayLeader]
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(all, id: \.key) { l in
                        VStack(spacing: 2) {
                            Image(systemName: "seal.fill").font(.system(size: 24))
                                .foregroundStyle(f.badges.contains(l.key) ? Color(hex: l.type.hex) : .white.opacity(0.12))
                            Text(l.badge).font(.rounded(9, .bold)).foregroundStyle(f.badges.contains(l.key) ? .white : Theme.inkSoft)
                        }
                    }
                    ForEach(f.symbols, id: \.self) { s in
                        VStack(spacing: 2) {
                            Image(systemName: "star.circle.fill").font(.system(size: 24)).foregroundStyle(.yellow)
                            Text(s).font(.rounded(9, .bold)).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }
}

// MARK: - The battle

struct BattleView: View {
    let number: Int
    let trainer: FrontierTrainer
    let done: (Bool) -> Void
    @EnvironmentObject private var store: GameStore

    @State private var mine: [BattleMon] = []
    @State private var foes: [BattleMon] = []
    @State private var me = 0
    @State private var foe = 0
    @State private var text = ""
    @State private var busy = true
    @State private var choosingSwitch = false
    @State private var forcedSwitch = false
    @State private var outcome: Bool?
    @State private var trainerPic: UIImage?
    @State private var showTrainer = true
    @State private var foeFlash = false
    @State private var meFlash = false
    @State private var confetti: Date?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2E5E4E), Color(hex: 0x16302A), .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    // foe
                    HStack(alignment: .top) {
                        if foes.indices.contains(foe) { infoBox(foes[foe], showHP: false) }
                        Spacer()
                        ZStack {
                            if showTrainer, let trainerPic {
                                PixelImageView(image: trainerPic).frame(width: 128, height: 128).transition(.move(edge: .trailing).combined(with: .opacity))
                            } else if foes.indices.contains(foe) {
                                AnimatedSprite(speciesID: foes[foe].speciesID, shiny: foes[foe].isShiny)
                                    .frame(width: 130, height: 130)
                                    .opacity(foes[foe].fainted ? 0 : (foeFlash ? 0.3 : 1))
                                    .offset(y: foes[foe].fainted ? 40 : 0)
                            }
                        }
                        .frame(width: 140, height: 140)
                    }
                    Spacer(minLength: 0)
                    // you
                    HStack(alignment: .bottom) {
                        if mine.indices.contains(me) {
                            AnimatedSprite(speciesID: mine[me].speciesID, shiny: mine[me].isShiny, kind: mine[me].isShiny ? .backShiny : .back)
                                .frame(width: 150, height: 150)
                                .opacity(mine[me].fainted ? 0 : (meFlash ? 0.3 : 1))
                                .offset(y: mine[me].fainted ? 40 : 0)
                        }
                        Spacer()
                        if mine.indices.contains(me) { infoBox(mine[me], showHP: true) }
                    }
                    // text
                    Text(text).font(.rounded(16, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .padding(14)
                        .glassCard(18)
                    controls
                }
                .padding()
                .frame(width: geo.size.width, height: geo.size.height)
                ConfettiRain(start: confetti).allowsHitTesting(false).ignoresSafeArea()
            }
        }
        .task { await begin() }
        .sheet(isPresented: $choosingSwitch) { switchSheet.presentationDetents([.medium]).interactiveDismissDisabled(forcedSwitch) }
    }

    private func infoBox(_ m: BattleMon, showHP: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(m.name).font(.rounded(15, .heavy)).foregroundStyle(.white)
                Spacer()
                Text("Lv\(m.level)").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
            }
            let frac = Double(max(0, m.hp)) / Double(max(1, m.maxHP))
            ProgressView(value: frac).tint(frac > 0.5 ? .green : frac > 0.2 ? .yellow : .red)
                .animation(.easeInOut(duration: 0.5), value: m.hp)
            if showHP {
                Text("\(max(0, m.hp)) / \(m.maxHP)").font(.rounded(12, .heavy)).monospacedDigit().foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(10)
        .frame(width: 170)
        .glassCard(16)
    }

    @ViewBuilder private var controls: some View {
        if let outcome {
            Button { done(outcome) } label: {
                Text(outcome ? "Collect your reward" : "Leave").font(.rounded(17, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .glassCapsule(tint: outcome ? Color(hex: 0xF5A623) : nil, interactive: true)
            }
            .buttonStyle(.plain)
        } else if mine.indices.contains(me), foes.indices.contains(foe) {
            let my = mine[me], their = foes[foe]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(my.moves, id: \.self) { m in
                    let eff = TypeChart.multiplier(m.type, against: their.types)
                    Button { Task { await turn(m) } } label: {
                        VStack(spacing: 1) {
                            Text(m.name).font(.rounded(15, .heavy))
                            Text("\(m.type.displayName) · \(m.power) \(m.special ? "Sp" : "Phys")" + (eff >= 2 ? " · Super!" : eff == 0 ? " · No effect" : eff < 1 ? " · Weak" : ""))
                                .font(.rounded(10, .bold)).opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .glassCapsule(tint: Color(hex: m.type.hex), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
            HStack(spacing: 10) {
                Button { forcedSwitch = false; choosingSwitch = true } label: {
                    Label("Switch", systemImage: "arrow.left.arrow.right").font(.rounded(14, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40).glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(busy || mine.filter { !$0.fainted }.count < 2)
                Button { Task { await forfeit() } } label: {
                    Label("Give up", systemImage: "flag.fill").font(.rounded(14, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40).glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private var switchSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(mine.enumerated()), id: \.element.id) { i, m in
                    Button {
                        choosingSwitch = false
                        Task { await switchTo(i) }
                    } label: {
                        HStack {
                            LocalIcon(speciesID: m.speciesID, shiny: m.isShiny).frame(width: 36, height: 36)
                            Text("\(m.name) Lv. \(m.level)").font(.rounded(15, .heavy))
                            Spacer()
                            Text(m.fainted ? "Fainted" : "\(m.hp)/\(m.maxHP)").font(.rounded(13, .bold)).foregroundStyle(m.fainted ? .red : .secondary)
                        }
                    }
                    .disabled(m.fainted || i == me)
                }
            }
            .navigationTitle(forcedSwitch ? "Who's next?" : "Switch Pokémon")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Flow

    private func say(_ t: String, _ ms: Int = 1_100) async {
        text = t
        try? await Task.sleep(for: .milliseconds(ms))
    }

    private func begin() async {
        guard mine.isEmpty else { return }
        mine = store.state.party.map(BattleMon.init(owned:))
        foes = trainer.team
        trainerPic = await PretFiles.sprite("graphics/trainers/front_pics/\(trainer.pic).png")
        await say("\(trainer.title) \(trainer.name) would like to battle!", 1_500)
        if !trainer.intro.isEmpty { await say(trainer.intro, 1_400) }
        withAnimation(.easeOut(duration: 0.4)) { showTrainer = false }
        CryPlayer.shared.play(foes[0].speciesID)
        await say("\(trainer.name) sent out \(foes[0].name)!")
        await say("Go! \(mine[0].name)!")
        busy = false
        text = "What will \(mine[me].name) do?"
    }

    private func turn(_ move: BattleMove) async {
        busy = true
        let foeMove = BattleMath.aiMove(foes[foe], vs: mine[me])
        let meFirst = mine[me].stats[5] > foes[foe].stats[5] || (mine[me].stats[5] == foes[foe].stats[5] && Bool.random())
        if meFirst {
            await attack(mineAttacks: true, move)
            if foes[foe].fainted { await foeFainted(); return }
            await attack(mineAttacks: false, foeMove)
            if mine[me].fainted { await myFainted(); return }
        } else {
            await attack(mineAttacks: false, foeMove)
            if mine[me].fainted { await myFainted(); return }
            await attack(mineAttacks: true, move)
            if foes[foe].fainted { await foeFainted(); return }
        }
        text = "What will \(mine[me].name) do?"
        busy = false
    }

    private func attack(mineAttacks: Bool, _ move: BattleMove) async {
        let a = mineAttacks ? mine[me] : foes[foe]
        let d = mineAttacks ? foes[foe] : mine[me]
        await say("\(mineAttacks ? "" : "The foe's ")\(a.name) used \(move.name)!", 700)
        let hit = BattleMath.hit(move, from: a, to: d)
        for _ in 0..<2 {
            if mineAttacks { foeFlash.toggle() } else { meFlash.toggle() }
            try? await Task.sleep(for: .milliseconds(90))
            if mineAttacks { foeFlash.toggle() } else { meFlash.toggle() }
            try? await Task.sleep(for: .milliseconds(90))
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            if mineAttacks { foes[foe].hp = max(0, foes[foe].hp - hit.damage) } else { mine[me].hp = max(0, mine[me].hp - hit.damage) }
        }
        Haptics.tap()
        try? await Task.sleep(for: .milliseconds(550))
        if hit.crit { await say("A critical hit!", 800) }
        if hit.effectiveness == 0 { await say("It doesn't affect \(d.name)…", 900) }
        else if hit.effectiveness >= 2 { await say("It's super effective!", 900) }
        else if hit.effectiveness < 1 { await say("It's not very effective…", 900) }
    }

    private func foeFainted() async {
        CryPlayer.shared.play(foes[foe].speciesID)
        await say("The foe's \(foes[foe].name) fainted!")
        if let next = foes.indices.first(where: { !foes[$0].fainted }) {
            foe = next
            CryPlayer.shared.play(foes[foe].speciesID)
            await say("\(trainer.name) sent out \(foes[foe].name)!")
            text = "What will \(mine[me].name) do?"
            busy = false
        } else {
            withAnimation { showTrainer = true }
            await say("You defeated \(trainer.title) \(trainer.name)!", 1_400)
            if let badge = trainer.badge { await say("You received the \(badge)!", 1_400) }
            if trainer.isChampion { await say("A legendary victory!", 1_400) }
            confetti = .now
            SoundKit.shared.play(.useItem)
            Haptics.hold()
            outcome = true
        }
    }

    private func myFainted() async {
        await say("\(mine[me].name) fainted!")
        if mine.contains(where: { !$0.fainted }) {
            forcedSwitch = true
            choosingSwitch = true
            text = "Choose your next Pokémon."
        } else {
            await say("You're out of usable Pokémon…", 1_200)
            withAnimation { showTrainer = true }
            await say("You lost to \(trainer.title) \(trainer.name).", 1_400)
            outcome = false
        }
    }

    private func switchTo(_ i: Int) async {
        busy = true
        let wasForced = forcedSwitch
        forcedSwitch = false
        if !wasForced { await say("Come back, \(mine[me].name)!", 800) }
        me = i
        await say("Go! \(mine[me].name)!", 900)
        if !wasForced {
            // switching uses your turn
            await attack(mineAttacks: false, BattleMath.aiMove(foes[foe], vs: mine[me]))
            if mine[me].fainted { await myFainted(); return }
        }
        text = "What will \(mine[me].name) do?"
        busy = false
    }

    private func forfeit() async {
        busy = true
        await say("You gave up the battle.", 1_000)
        outcome = false
    }
}
