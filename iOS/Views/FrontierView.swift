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

/// A Battle Frontier battle laid out like Emerald's: the Frontier background and platforms, the trainer's front
/// sprite and your back sprite sliding in, the party ball rows, then the foe sends out first and you throw your
/// ball after — with Liquid Glass health boxes, text box and move buttons.
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
    @State private var foeFlash = false
    @State private var meFlash = false
    @State private var confetti: Date?

    // scene
    @State private var scene: UIImage?
    @State private var trainerPic: UIImage?
    @State private var backFrames: [UIImage] = []
    @State private var backFrame = 0
    @State private var ballFrames: [UIImage] = []
    @State private var foeTrainerX: CGFloat = -260      // GBA pixels from its spot (0 = standing on the platform)
    @State private var playerX: CGFloat = 260
    @State private var ballRows = false
    @State private var foeShown = false
    @State private var meShown = false
    @State private var foeScale: CGFloat = 0.1
    @State private var meScale: CGFloat = 0.1
    @State private var meRecall = false
    @State private var foeBoxIn = false
    @State private var meBoxIn = false
    @State private var foeBounds = SpriteBounds.fallback
    @State private var meBounds = SpriteBounds.fallback
    @State private var flight: Flight?
    @State private var ballAt: CGPoint?
    @State private var ballOpen = false
    @State private var openFX: (start: Date, at: CGPoint)?
    @State private var flash: (CGPoint, Double) = (.zero, 0)

    private struct Flight { let from: CGPoint; let to: CGPoint; let arc: CGFloat; let start: Date; let duration: Double }

    private var style: TrainerStyle { store.state.trainer.style }

    // The scene is laid out on a 200 px wide "GBA" canvas as tall as the top half allows (vh), spread out like
    // Emerald's: foe box top left, foe on its platform to the right, you bottom left, your box bottom right.
    @State private var vh: CGFloat = 200
    @State private var wall: UIImage?
    @State private var platform: UIImage?
    private static let vw: CGFloat = 200
    private var foeFeet: CGPoint { CGPoint(x: Self.vw * 0.70, y: vh * 0.47) }
    private var myFeet: CGPoint { CGPoint(x: Self.vw * 0.27, y: vh - 6) }
    private var foeTrainerCentre: CGPoint { CGPoint(x: foeFeet.x, y: foeFeet.y - 26) }
    private var playerCentre: CGPoint { CGPoint(x: Self.vw * 0.29, y: vh - 33) }
    private var foeBoxCentre: CGPoint { CGPoint(x: Self.vw * 0.28, y: vh * 0.13) }
    private var myBoxCentre: CGPoint { CGPoint(x: Self.vw * 0.73, y: vh * 0.70) }

    var body: some View {
        GeometryReader { geo in
            let sceneW = geo.size.width - 20
            let sceneH = geo.size.height / 2 - 16
            let s = sceneW / Self.vw
            ZStack(alignment: .top) {
                VStack(spacing: 12) {
                    // Emerald's scene in a glass frame
                    ZStack(alignment: .topLeading) {
                        Color(hex: 0xF6F6FF)
                        if let wall {
                            // Emerald's Frontier wall, its stripes carried down the whole height
                            Image(uiImage: wall).interpolation(.none).resizable()
                                .frame(width: sceneW, height: wall.size.height * s)
                        }
                        battleScene(s)
                    }
                        .frame(width: sceneW, height: sceneH, alignment: .topLeading)
                        .task(id: "\(Int(sceneH / s))-\(scene != nil)") {
                            vh = sceneH / s
                            guard let scene else { return }
                            wall = BattleGfx.frontierWall(scene, height: Int(vh) + 4, width: Int(Self.vw))
                            platform = BattleGfx.frontierPlatform(scene)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(4)
                        .glassCard(26)
                        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .padding(.top, 6)
                    VStack(spacing: 10) {
                        Text(text).font(.rounded(17, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
                            .padding(14)
                            .glassCard(20, tint: Color(hex: 0x2E6F86).opacity(0.55))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color(hex: 0xE0703A).opacity(0.85), lineWidth: 3))
                            .animation(nil, value: text)
                        controls
                        Spacer(minLength: 0)
                        Text("Battle \(number) of 5").font(.rounded(12, .heavy)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                ConfettiRain(start: confetti).allowsHitTesting(false).ignoresSafeArea()
            }
        }
        .background { backdrop.ignoresSafeArea() }
        .task { await begin() }
        .task(id: foes.indices.contains(foe) ? foes[foe].speciesID : 0) {
            guard foes.indices.contains(foe) else { return }
            let m = foes[foe]
            foeBounds = await BattleGfx.bounds(m.speciesID, kind: m.isShiny ? .shiny : .front) ?? .fallback
        }
        .task(id: mine.indices.contains(me) ? mine[me].speciesID : 0) {
            guard mine.indices.contains(me) else { return }
            let m = mine[me]
            meBounds = await BattleGfx.bounds(m.speciesID, kind: m.isShiny ? .backShiny : .back) ?? .fallback
        }
        .onAppear { SoundKit.shared.setScene(.battle) }
        .onDisappear { SoundKit.shared.setScene(.map) }
        .sheet(isPresented: $choosingSwitch) { switchSheet.presentationDetents([.medium]).interactiveDismissDisabled(forcedSwitch) }
    }

    /// The whole screen behind the glass: Emerald's scene, blown up and blurred.
    private var backdrop: some View {
        // overlays don't change the size, so the stretched image can't push the layout wider than the screen
        // Where you are, low and blurred (like wild battles), tinted with the Frontier's teal and orange
        Color(hex: 0x24414A)
            .overlay { LocationBackdrop(fallback: nil) }
            .overlay {
                LinearGradient(colors: [Color(hex: 0x2E6F86).opacity(0.35), .clear, Color(hex: 0xE0703A).opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .overlay { LinearGradient(colors: [.clear, .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom) }
            .clipped()
    }

    // MARK: Scene

    private func battleScene(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Self.vw * s, height: vh * s)
            if let platform {
                // the same oval as in Emerald for both sides (yours bigger and half off the bottom, like the game)
                Image(uiImage: platform).interpolation(.none).resizable()
                    .frame(width: 128 * s, height: 32 * s)
                    .position(x: foeFeet.x * s, y: (foeFeet.y + 2) * s)
                Image(uiImage: platform).interpolation(.none).resizable()
                    .frame(width: 150 * s, height: 38 * s)
                    .position(x: myFeet.x * s, y: (myFeet.y + 6) * s)
            }
            foeMon(s)
            foeTrainer(s)
            myMon(s)
            playerTrainer(s)
            if ballRows {
                partyRow(foes, alignRight: true, s: s)
                    .position(x: foeBoxCentre.x * s, y: foeBoxCentre.y * s)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                partyRow(mine, alignRight: false, s: s)
                    .position(x: myBoxCentre.x * s, y: myBoxCentre.y * s)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            TimelineView(.animation(paused: flight == nil)) { tl in
                if let p = ballPoint(tl.date) {
                    Group {
                        if ballFrames.count >= 2 {
                            Image(uiImage: ballFrames[ballOpen ? 1 : 0]).interpolation(.none).resizable()
                        } else {
                            BallGlyph(kind: .poke)
                        }
                    }
                    .frame(width: 14 * s, height: 14 * s)
                    .rotationEffect(.degrees(flightSpin(tl.date)))
                    .position(x: p.x * s, y: p.y * s)
                }
            }
            Circle().fill(.white).frame(width: 70 * s, height: 70 * s).blur(radius: 12 * s)
                .opacity(flash.1).position(x: flash.0.x * s, y: flash.0.y * s).allowsHitTesting(false)
            if let fx = openFX {
                BallOpenFX(kind: .poke, gameBoy: false, start: fx.start, px: s)
                    .id(fx.start)
                    .position(x: fx.at.x * s, y: fx.at.y * s)
            }
            if foeBoxIn, foes.indices.contains(foe) {
                infoBox(foes[foe], mine: false)
                    .frame(width: Self.vw * 0.52 * s)
                    .position(x: foeBoxCentre.x * s, y: foeBoxCentre.y * s)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if meBoxIn, mine.indices.contains(me) {
                infoBox(mine[me], mine: true)
                    .frame(width: Self.vw * 0.52 * s)
                    .position(x: myBoxCentre.x * s, y: myBoxCentre.y * s)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: Self.vw * s, height: vh * s, alignment: .topLeading)
    }

    @ViewBuilder private func foeMon(_ s: CGFloat) -> some View {
        if foeShown, foes.indices.contains(foe) {
            let m = foes[foe], b = foeBounds, e = s * 0.8
            let lift = CGFloat(BattleElevation.pixels(m.speciesID)) * 1.5 * e
            let cy = foeFeet.y * s - (b.bottom - b.size.height / 2) * e - lift
            AnimatedSprite(speciesID: m.speciesID, shiny: m.isShiny)
                .frame(width: b.size.width * e, height: b.size.height * e)
                .scaleEffect(foeScale, anchor: .bottom)
                .opacity(m.fainted ? 0 : (foeFlash ? 0.25 : 1))
                .offset(y: m.fainted ? 40 * s : 0)
                .position(x: foeFeet.x * s, y: cy)
        }
    }

    @ViewBuilder private func myMon(_ s: CGFloat) -> some View {
        if meShown, mine.indices.contains(me) {
            let m = mine[me], b = meBounds, e = s * 0.95
            let cy = myFeet.y * s - (b.bottom - b.size.height / 2) * e
            AnimatedSprite(speciesID: m.speciesID, shiny: m.isShiny, kind: m.isShiny ? .backShiny : .back)
                .frame(width: b.size.width * e, height: b.size.height * e)
                .colorMultiply(meRecall ? Color(hex: 0xFF5A5A) : .white)
                .scaleEffect(meScale, anchor: .bottom)
                .opacity(m.fainted ? 0 : (meFlash ? 0.25 : 1))
                .offset(y: m.fainted ? 50 * s : 0)
                .position(x: myFeet.x * s, y: cy)
        }
    }

    @ViewBuilder private func foeTrainer(_ s: CGFloat) -> some View {
        if let trainerPic {
            Image(uiImage: trainerPic).interpolation(.none).resizable()
                .frame(width: 64 * s, height: 64 * s)
                .position(x: (foeTrainerCentre.x + foeTrainerX) * s, y: foeTrainerCentre.y * s)
        }
    }

    @ViewBuilder private func playerTrainer(_ s: CGFloat) -> some View {
        if backFrames.indices.contains(backFrame) {
            Image(uiImage: backFrames[backFrame]).interpolation(.none).resizable()
                .frame(width: 64 * s, height: 64 * s)
                .position(x: (playerCentre.x + playerX) * s, y: playerCentre.y * s)
        }
    }

    /// The six-ball party line from the intro: full balls for Pokémon still standing, dark ones for fainted, empty slots.
    private func partyRow(_ team: [BattleMon], alignRight: Bool, s: CGFloat) -> some View {
        let slots: [BattleMon?] = (0..<6).map { team.indices.contains($0) ? team[$0] : nil }
        let ordered = alignRight ? Array(slots.reversed()) : slots
        return VStack(spacing: 1 * s) {
            HStack(spacing: 1.5 * s) {
                ForEach(0..<6, id: \.self) { i in
                    if let m = ordered[i] {
                        Group {
                            if let img = ballFrames.first { Image(uiImage: img).interpolation(.none).resizable() }
                            else { BallGlyph(kind: .poke) }
                        }
                        .frame(width: 9 * s, height: 9 * s)
                        .saturation(m.fainted ? 0 : 1).brightness(m.fainted ? -0.35 : 0)
                    } else {
                        Circle().strokeBorder(Color(hex: 0x505860), lineWidth: 0.9 * s)
                            .background(Circle().fill(.white.opacity(0.8)))
                            .frame(width: 8 * s, height: 8 * s).padding(0.5 * s)
                    }
                }
            }
            Capsule().fill(Color(hex: 0x2F4A2A)).frame(width: 74 * s, height: 1.6 * s)
        }
        .padding(.horizontal, 5 * s).padding(.vertical, 3 * s)
        .glassCapsule()
    }

    private func ballPoint(_ now: Date) -> CGPoint? {
        guard let f = flight else { return ballAt }
        let t = min(1, max(0, now.timeIntervalSince(f.start) / f.duration))
        let x = f.from.x + (f.to.x - f.from.x) * t
        let y = f.from.y + (f.to.y - f.from.y) * t - 4 * t * (1 - t) * f.arc
        return CGPoint(x: x, y: y)
    }

    private func flightSpin(_ now: Date) -> Double {
        guard let f = flight else { return 0 }
        return min(1, now.timeIntervalSince(f.start) / f.duration) * 720
    }

    private func infoBox(_ m: BattleMon, mine isMine: Bool) -> some View {
        let frac = Double(max(0, m.hp)) / Double(max(1, m.maxHP))
        let bar = frac > 0.5 ? Color(hex: 0x58D068) : frac > 0.2 ? Color(hex: 0xF8C030) : Color(hex: 0xF05838)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(m.name.uppercased()).font(.rounded(16, .black)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if m.isShiny { Text("✨").font(.system(size: 11)) }
                Spacer(minLength: 4)
                Text("Lv\(m.level)").font(.rounded(15, .black)).foregroundStyle(Theme.ink)
            }
            HStack(spacing: 6) {
                Text("HP").font(.rounded(10, .black)).foregroundStyle(Color(hex: 0xF8B030))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color(hex: 0x40484A)))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.28))
                        Capsule().fill(bar).frame(width: max(0, g.size.width * frac))
                    }
                }
                .frame(height: 7)
                .animation(.easeInOut(duration: 0.5), value: m.hp)
            }
            if isMine {
                Text("\(max(0, m.hp))/ \(m.maxHP)").font(.rounded(15, .black)).monospacedDigit().foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCard(16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.4), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }

    // MARK: Controls

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
                    .opacity(busy ? 0.55 : 1)
                }
            }
            HStack(spacing: 10) {
                Button { forcedSwitch = false; choosingSwitch = true } label: {
                    Label("Pokémon", systemImage: "arrow.left.arrow.right").font(.rounded(14, .heavy)).foregroundStyle(.white)
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

    // MARK: Sending out

    private func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    /// A ball arcs to `to`, pops open with Emerald's particles and a flash, and the Pokémon grows out of it.
    private func throwBall(from: CGPoint, to: CGPoint, arc: CGFloat, foeSide: Bool) async {
        ballOpen = false
        ballAt = from
        SoundKit.shared.play(.ballThrow)
        flight = Flight(from: from, to: to, arc: arc, start: .now, duration: 0.55)
        await wait(550)
        flight = nil
        ballAt = to
        SoundKit.shared.play(.ballOpen)
        ballOpen = true
        openFX = (Date(), to)
        flash = (to, 0)
        withAnimation(.easeOut(duration: 0.12)) { flash = (to, 0.8) }
        if foeSide { foeScale = 0.1; foeShown = true } else { meScale = 0.1; meRecall = false; meShown = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if foeSide { foeScale = 1 } else { meScale = 1 }
        }
        await wait(160)
        ballAt = nil
        withAnimation(.easeOut(duration: 0.35)) { flash = (to, 0) }
        CryPlayer.shared.play(foeSide ? foes[foe].speciesID : mine[me].speciesID)
        await wait(450)
    }

    private func sendOutFoe() async {
        foeBoxIn = false
        await say("\(trainer.title) \(trainer.name) sent out \(foes[foe].name)!", 350)
        await throwBall(from: CGPoint(x: Self.vw + 16, y: foeFeet.y - 60), to: CGPoint(x: foeFeet.x, y: foeFeet.y - 14), arc: 30, foeSide: true)
        withAnimation(.spring(duration: 0.35)) { foeBoxIn = true }
    }

    /// `withTrainer`: the opening send-out, where you wind up and throw (then slide away).
    private func sendOutMine(withTrainer: Bool) async {
        meBoxIn = false
        text = "Go! \(mine[me].name)!"
        var from = CGPoint(x: -14, y: myFeet.y - 60)
        if withTrainer, !backFrames.isEmpty {
            let anim = style.backThrow
            Task { @MainActor in
                for (f, d) in anim.frames {
                    if backFrames.indices.contains(f) { backFrame = f }
                    if d > 0 { try? await Task.sleep(for: .seconds(d)) }
                }
            }
            await wait(Int((anim.frames.isEmpty ? 0.1 : anim.release) * 1000))
            from = CGPoint(x: playerCentre.x + 16, y: playerCentre.y - 22)
            withAnimation(.easeIn(duration: 0.55)) { playerX = -170 }
        }
        await throwBall(from: from, to: CGPoint(x: myFeet.x + 4, y: myFeet.y - 22), arc: 50, foeSide: false)
        withAnimation(.spring(duration: 0.35)) { meBoxIn = true }
    }

    private func recallMine() async {
        meBoxIn = false
        withAnimation(.easeIn(duration: 0.12)) { meRecall = true }
        withAnimation(.easeIn(duration: 0.35)) { meScale = 0.05 }
        SoundKit.shared.play(.ballOpen)
        await wait(380)
        meShown = false
        meRecall = false
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
        async let bg = BattleGfx.frontierBackground()
        async let pic = PretFiles.sprite("graphics/trainers/front_pics/\(trainer.pic).png")
        async let back = BattleGfx.trainerBack(style)
        async let balls = BattleGfx.ball(.poke)
        scene = await bg
        trainerPic = await pic
        backFrames = await back
        ballFrames = await balls
        backFrame = style.backIdleFrame
        await wait(150)

        // Both trainers slide in (the foe from the left, you from the right), then the party lines appear
        withAnimation(.easeOut(duration: 1.0)) { foeTrainerX = 0; playerX = 0 }
        await wait(1_000)
        withAnimation(.spring(duration: 0.4)) { ballRows = true }
        await say("\(trainer.title) \(trainer.name) would like to battle!", 1_600)
        if !trainer.intro.isEmpty { await say(trainer.intro, 1_500) }

        // The foe goes first: the trainer steps off and throws
        withAnimation(.easeIn(duration: 0.45)) { foeTrainerX = 110; ballRows = false }
        await wait(300)
        await sendOutFoe()
        // …then you
        await sendOutMine(withTrainer: true)
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
        withAnimation(.easeIn(duration: 0.3)) { foeBoxIn = false }
        await say("The foe's \(foes[foe].name) fainted!")
        foeShown = false
        if let next = foes.indices.first(where: { !foes[$0].fainted }) {
            foe = next
            await sendOutFoe()
            text = "What will \(mine[me].name) do?"
            busy = false
        } else {
            withAnimation(.easeOut(duration: 0.6)) { foeTrainerX = 0 }
            await wait(600)
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
        withAnimation(.easeIn(duration: 0.3)) { meBoxIn = false }
        await say("\(mine[me].name) fainted!")
        meShown = false
        if mine.contains(where: { !$0.fainted }) {
            forcedSwitch = true
            choosingSwitch = true
            text = "Choose your next Pokémon."
        } else {
            await say("You're out of usable Pokémon…", 1_200)
            withAnimation(.easeOut(duration: 0.6)) { foeShown = false; foeBoxIn = false; foeTrainerX = 0 }
            await wait(600)
            await say("You lost to \(trainer.title) \(trainer.name).", 1_400)
            outcome = false
        }
    }

    private func switchTo(_ i: Int) async {
        busy = true
        let wasForced = forcedSwitch
        forcedSwitch = false
        if !wasForced {
            await say("Come back, \(mine[me].name)!", 500)
            await recallMine()
        }
        me = i
        await sendOutMine(withTrainer: false)
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
