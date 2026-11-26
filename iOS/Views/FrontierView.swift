import SwiftUI

/// Party › Gym Challenge and Battle Frontier: five battles a day, each tougher (and paying more BP) than the last.
/// Gym Challenge: four trainers, then your region's next Gym Leader — with all eight badges, the Elite Four and the
/// Champion. Battle Frontier (built once you're Champion): Frontier trainers and a Frontier Brain. Three tries a day.
struct FrontierView: View {
    @EnvironmentObject private var store: GameStore
    var mode: FrontierRules.Mode = .gym
    @State private var battling: Fight?
    @State private var result: String?
    @State private var frontierUnlocked = false

    struct Fight: Identifiable { let id = UUID(); let number: Int; let trainer: FrontierTrainer }

    var body: some View {
        let f = store.state.frontier
        ScrollView {
            VStack(spacing: 16) {
                statusCard(f)
                ladder(f)
                if mode == .gym { journeyCard(f) }
                if mode == .frontier, f.nextProject != nil || f.building != nil {
                    BuildCard(projects: FrontierRules.projects, built: f.built, building: f.building,
                              start: { store.startFrontierProject() },
                              finish: { if let p = store.finishFrontierProjectIfDone() { result = "The \(p.name) is ready! \(p.reward)." } })
                }
                if !f.badges.isEmpty || !f.symbols.isEmpty { badgeCard(f) }
            }
            .padding()
        }
        .onAppear { store.refreshFrontier() }
        .alert("You're the Champion! 🏆", isPresented: $frontierUnlocked) {
            Button("Great!") { SoundKit.shared.play(.select) }
        } message: {
            Text("You can now build the Battle Frontier. It's in the Menu — build the Battle Tower to open it.")
        }
        .fullScreenCover(item: $battling) { fight in
            BattleView(number: fight.number, trainer: fight.trainer) { won in
                let couldBuild = FrontierRules.canBuild(store.state)
                if let r = store.finishFrontierBattle(fight.number, trainer: fight.trainer, mode: mode, won: won) {
                    if !couldBuild && FrontierRules.canBuild(store.state) { frontierUnlocked = true }
                    var text = "You won! " + FrontierRules.rewardText(r)
                    if fight.trainer.isLeader, let b = fight.trainer.badge { text += " · \(b)!" }
                    if fight.trainer.isChampion && !fight.trainer.isBrain && mode == .gym {
                        text += " You're the Champion!"
                    }
                    result = text
                } else if !won {
                    let f = store.state.frontier
                    let left = FrontierRules.maxLosses(mode, store.state) - f.losses(mode)
                    result = left > 0
                        ? "You lost to \(fight.trainer.title) \(fight.trainer.name). \(left) \(left == 1 ? "try" : "tries") left today."
                        : "You lost to \(fight.trainer.title) \(fight.trainer.name). No tries left — come back tomorrow!"
                }
                battling = nil
            }
        }
    }

    private var title: String {
        if mode == .frontier { return "Battle Frontier" }
        return FrontierRules.isLeagueDay(store.state) ? "Pokémon League" : "Gym Challenge"
    }

    private func statusCard(_ f: Frontier) -> some View {
        let won = f.won(mode), done = f.done(mode)
        let limit = FrontierRules.maxLosses(mode, store.state)
        let tries = max(0, limit - f.losses(mode))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: mode == .frontier ? "building.columns.fill" : "flag.2.crossed.fill")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title): \(won)/5").font(.rounded(22, .black)).foregroundStyle(.white)
                    Text(done ? "Out of tries — it reopens tomorrow." : won == 5 ? "Cleared! Come back tomorrow for more."
                         : "\(tries) of \(limit) tries left today · lose and you can try that battle again.")
                        .font(.rounded(13, .bold)).foregroundStyle(done ? .orange : Theme.inkSoft)
                }
                Spacer()
            }
            if let result {
                Text(result).font(.rounded(13, .heavy)).foregroundStyle(.yellow)
            }
            HStack(spacing: 6) {
                Image(systemName: "star.circle.fill").foregroundStyle(Color(hex: 0xF5C542))
                Text("\(f.bp) BP").font(.rounded(15, .black)).foregroundStyle(.white)
                Text("· spend them at the Poké Mart's BP counter").font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            Text("New trainers every day. Your Pokémon's levels set theirs, and every Pokémon gets four random moves from everything it can learn.")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .glassCard(22)
    }

    private func ladder(_ f: Frontier) -> some View {
        let won = f.won(mode), done = f.done(mode)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(1...5, id: \.self) { n in
                let t = FrontierRules.trainer(for: n, in: store.state, mode: mode)
                let isNext = n == won + 1 && !done
                let beaten = n <= won
                let shown = beaten || isNext || n == 5 || t.isElite
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(beaten ? Color.green.opacity(0.55) : isNext ? Color.orange.opacity(0.55) : Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        TrainerOverworld(pic: t.pic, gen: BattleGen.of(store.state.trainer.style), hidden: !shown)
                            .frame(width: 34, height: 40)
                        if beaten {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white, .green).offset(x: 15, y: 15)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shown ? "\(t.title) \(t.name)" : "???").font(.rounded(15, .heavy)).foregroundStyle(.white)
                        Text(beaten || isNext ? "\(t.team.count) Pokémon · Lv. \(t.team.map(\.level).max() ?? 0)" + (t.intro.isEmpty ? "" : " · \(t.intro)")
                             : n == 5 ? t.intro : "A tougher trainer")
                            .font(.rounded(11, .semibold)).foregroundStyle(Theme.inkSoft)
                        Text(FrontierRules.rewardText(FrontierRules.reward(for: n, trainer: t, mode: mode, in: store.state)))
                            .font(.rounded(11, .bold)).foregroundStyle(Color(hex: 0xF5C542))
                    }
                    Spacer()
                    if isNext && won < 5 {
                        Button {
                            SoundKit.shared.play(.menuOpen)
                            result = nil
                            battling = Fight(number: n, trainer: t)
                        } label: {
                            Text(f.losses(mode) > 0 && n == won + 1 ? "Retry!" : "Battle!").font(.rounded(14, .heavy)).foregroundStyle(.white)
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

    /// Your Gym journey: the region's eight leaders in order, then the League.
    private func journeyCard(_ f: Frontier) -> some View {
        let leaders = FrontierRules.allLeaders(FrontierRules.region(store.state))
        let next = FrontierRules.nextLeader(store.state)
        let champ = FrontierRules.isChampion(store.state)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Gym journey").font(.rounded(16, .heavy)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                ForEach(Array(leaders.enumerated()), id: \.offset) { i, l in
                    let have = f.badges.contains(l.key)
                    VStack(spacing: 2) {
                        Image(systemName: have ? "seal.fill" : l.key == next?.key ? "seal" : "lock.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(have ? Color(hex: l.type.hex) : l.key == next?.key ? .orange : Theme.inkSoft)
                        Text("\(i + 1). \(l.name)").font(.rounded(10, .heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        Text(l.badge).font(.rounded(9, .bold)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(next.map { "Next: \($0.name) (\($0.type.displayName)) — the 5th battle of each day until you win the \($0.badge)." }
                 ?? (champ ? "You're the Champion! Gym Leaders take turns for rematches, and the League rematch is on Sundays."
                           : "All eight badges! Today's run is the Pokémon League: the Elite Four, then the Champion."))
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .glassCard(22)
    }

    private func badgeCard(_ f: Frontier) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badges & symbols").font(.rounded(16, .heavy)).foregroundStyle(.white)
            // your region's eight first, then any you earned with another trainer
            let mine = FrontierRules.allLeaders(FrontierRules.region(store.state))
            let all = mine + FrontierRules.everyLeader.filter { l in f.badges.contains(l.key) && !mine.contains { $0.key == l.key } }
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

/// Party › Battle Frontier: locked until you're Champion, then built like the Daycare.
struct BattleFrontierHub: View {
    @EnvironmentObject private var store: GameStore
    @State private var says: String?

    var body: some View {
        let f = store.state.frontier
        Group {
            if f.open {
                FrontierView(mode: .frontier)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image(systemName: FrontierRules.canBuild(store.state) ? "building.columns.fill" : "lock.fill")
                                .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 50, height: 50).glassCircle()
                            Text(says ?? (FrontierRules.canBuild(store.state)
                                 ? "You're the Champion! Build the Battle Tower to open the Battle Frontier."
                                 : "Win all eight badges in the Gym Challenge, then beat the Elite Four and the Champion. After that you can build the Battle Frontier."))
                                .font(.rounded(14, .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .glassCard(22)
                        if FrontierRules.canBuild(store.state) {
                            BuildCard(projects: FrontierRules.projects, built: f.built, building: f.building,
                                      start: { store.startFrontierProject() },
                                      finish: { if let p = store.finishFrontierProjectIfDone() { says = "The \(p.name) is ready! \(p.reward)." } })
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { store.finishFrontierProjectIfDone() }
    }
}

/// A trainer's overworld sprite in the ladder (a dark silhouette until you've reached them).
struct TrainerOverworld: View {
    let pic: String
    let gen: BattleGen
    var hidden = false
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .colorMultiply(hidden ? .black : .white)
                    .opacity(hidden ? 0.6 : 1)
            } else {
                Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.5))
            }
        }
        .task(id: pic + gen.rawValue) { image = await BattleHUD.overworld(pic, gen: gen) }
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
    /// Red → Red/Blue's battle screen, Gold/Kris → Crystal's, everyone else → Emerald's
    private var gen: BattleGen { BattleGen.of(style) }
    @State private var shownHP: [UUID: Int] = [:]
    @State private var anim: MoveAnim?
    @State private var field = BattleField()
    @State private var pendingDrag: BattleSide?
    @State private var meLunge: CGFloat = 0
    @State private var foeLunge: CGFloat = 0
    @State private var shake: CGFloat = 0      // what the HP bars show (they drain smoothly)
    @ObservedObject private var audio = BattleAudio.shared

    // Laid out on the original screen's pixel grid — Emerald's 240 px wide, the Game Boy's 160 px — as tall as the
    // top half allows (vh), arranged like the games: foe box top left, foe top right, you bottom left, your box bottom right.
    @State private var vh: CGFloat = 200
    @State private var wall: UIImage?
    @State private var platform: UIImage?
    private var vw: CGFloat { gen.isGameBoy ? 160 : 240 }
    private var foeFeet: CGPoint { gen.isGameBoy ? CGPoint(x: 120, y: max(60, vh * 0.40)) : CGPoint(x: 172, y: max(72, vh * 0.48)) }
    private var myFeet: CGPoint { gen.isGameBoy ? CGPoint(x: 40, y: vh - 2) : CGPoint(x: 62, y: vh - 4) }
    private var foeTrainerCentre: CGPoint { CGPoint(x: foeFeet.x, y: foeFeet.y - (gen.isGameBoy ? 26 : 30)) }
    private var playerCentre: CGPoint {
        let h = (backFrames.first?.size.height ?? 64) * backScale
        return CGPoint(x: gen.isGameBoy ? 40 : 80, y: vh - 2 - h / 2)
    }
    private var foeBoxOrigin: CGPoint { gen.isGameBoy ? CGPoint(x: 6, y: 8) : CGPoint(x: 6, y: 10) }
    private var myBoxOrigin: CGPoint { gen.isGameBoy ? CGPoint(x: 76, y: vh - 46) : CGPoint(x: 124, y: vh - 82) }
    private var foeBoxCentre: CGPoint { CGPoint(x: foeBoxOrigin.x + (gen.isGameBoy ? 40 : 54), y: foeBoxOrigin.y + 14) }
    private var myBoxCentre: CGPoint { CGPoint(x: myBoxOrigin.x + (gen.isGameBoy ? 40 : 58), y: myBoxOrigin.y + 18) }
    private var backScale: CGFloat { gen.isGameBoy ? 1.3 : 1.3 }      // your trainer's back sprite
    private var foeSize: CGFloat { gen.isGameBoy ? 0.9 : 1.05 }        // sprite size on the canvas
    private var mySize: CGFloat { gen.isGameBoy ? 1.05 : 1.3 }

    var body: some View {
        GeometryReader { geo in
            let sceneW = geo.size.width - 20
            let sceneH = geo.size.height / 2 - 16
            let s = sceneW / vw
            ZStack(alignment: .top) {
                VStack(spacing: 12) {
                    // Emerald's scene in a glass frame
                    ZStack(alignment: .topLeading) {
                        Color(hex: gen.isGameBoy ? 0xFFFFFF : 0xF6F6FF)
                        if !gen.isGameBoy, let wall {
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
                            wall = BattleGfx.frontierWall(scene, height: Int(vh) + 4, width: Int(vw))
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
                        sideButtons.padding(.bottom, 14)
                        HStack(spacing: 8) {
                            Text("Battle \(number) of 5").font(.rounded(12, .heavy)).foregroundStyle(.white.opacity(0.7))
                            if let t = audio.nowPlaying {
                                Label(t.title, systemImage: "music.note")
                                    .font(.rounded(12, .heavy)).foregroundStyle(.white)
                                    .lineLimit(1)
                                    .symbolEffect(.pulse, options: .repeating)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .glassCapsule()
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(duration: 0.4), value: audio.nowPlaying)
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
        .onAppear { SoundKit.shared.setScene(.none) }
        .onDisappear { BattleAudio.shared.stopMusic(); SoundKit.shared.setScene(.map) }
        .onChange(of: lowHealth) { _, on in BattleAudio.shared.setLowHealth(on) }
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
            Color.clear.frame(width: vw * s, height: vh * s)
            if !gen.isGameBoy, let platform {
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
            if let anim { MoveAnimLayer(anim: anim, s: s) }
            if let fx = openFX {
                BallOpenFX(kind: .poke, gameBoy: false, start: fx.start, px: s)
                    .id(fx.start)
                    .position(x: fx.at.x * s, y: fx.at.y * s)
            }
            if foeBoxIn, foes.indices.contains(foe), let img = hud(foes[foe], player: false) {
                Image(uiImage: img).interpolation(.none).resizable()
                    .frame(width: img.size.width * s, height: img.size.height * s)
                    .position(x: (foeBoxOrigin.x + img.size.width / 2) * s, y: (foeBoxOrigin.y + img.size.height / 2) * s)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if meBoxIn, mine.indices.contains(me), let img = hud(mine[me], player: true) {
                Image(uiImage: img).interpolation(.none).resizable()
                    .frame(width: img.size.width * s, height: img.size.height * s)
                    .position(x: (myBoxOrigin.x + img.size.width / 2) * s, y: (myBoxOrigin.y + img.size.height / 2) * s)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: vw * s, height: vh * s, alignment: .topLeading)
        .offset(x: shake * s)
    }

    @ViewBuilder private func foeMon(_ s: CGFloat) -> some View {
        if foeShown, foes.indices.contains(foe) {
            let m = foes[foe], b = foeBounds, e = s * foeSize
            let lift = CGFloat(BattleElevation.pixels(m.speciesID)) * 1.5 * e
            let cy = foeFeet.y * s - (b.bottom - b.size.height / 2) * e - lift
            AnimatedSprite(speciesID: m.speciesID, shiny: m.isShiny)
                .frame(width: b.size.width * e, height: b.size.height * e)
                .scaleEffect(foeScale, anchor: .bottom)
                .offset(x: -foeLunge * 18 * s, y: foeLunge * 10 * s)
                .opacity(m.fainted ? 0 : (foeFlash ? 0.25 : 1))
                .offset(y: m.fainted ? 40 * s : 0)
                .position(x: foeFeet.x * s, y: cy)
        }
    }

    @ViewBuilder private func myMon(_ s: CGFloat) -> some View {
        if meShown, mine.indices.contains(me) {
            let m = mine[me], b = meBounds, e = s * mySize
            let cy = myFeet.y * s - (b.bottom - b.size.height / 2) * e
            AnimatedSprite(speciesID: m.speciesID, shiny: m.isShiny, kind: m.isShiny ? .backShiny : .back)
                .frame(width: b.size.width * e, height: b.size.height * e)
                .colorMultiply(meRecall ? Color(hex: 0xFF5A5A) : .white)
                .scaleEffect(meScale, anchor: .bottom)
                .offset(x: meLunge * 20 * s, y: -meLunge * 12 * s)
                .opacity(m.fainted ? 0 : (meFlash ? 0.25 : 1))
                .offset(y: m.fainted ? 50 * s : 0)
                .position(x: myFeet.x * s, y: cy)
        }
    }

    private func hud(_ m: BattleMon, player: Bool) -> UIImage? {
        BattleHUD.shared.image(gen, mon: m, hp: shownHP[m.id] ?? m.hp, player: player)
    }

    /// Your Pokémon's HP bar is red: Emerald's low-health beeping
    private var lowHealth: Bool {
        guard outcome == nil, meBoxIn, mine.indices.contains(me) else { return false }
        let hp = shownHP[mine[me].id] ?? mine[me].hp
        return hp > 0 && hp * 48 / max(1, mine[me].maxHP) < 10
    }

    @ViewBuilder private func foeTrainer(_ s: CGFloat) -> some View {
        if let trainerPic {
            let size = trainerPic.size.width
            Image(uiImage: trainerPic).interpolation(.none).resizable()
                .frame(width: size * s, height: size * s)
                .position(x: (foeTrainerCentre.x + foeTrainerX) * s, y: foeTrainerCentre.y * s)
        }
    }

    @ViewBuilder private func playerTrainer(_ s: CGFloat) -> some View {
        if backFrames.indices.contains(backFrame) {
            let size = backFrames[backFrame].size
            Image(uiImage: backFrames[backFrame]).interpolation(.none).resizable()
                .frame(width: size.width * backScale * s, height: size.height * backScale * s)
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
            let my = mine[me]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                if my.hasUsableMove {
                    ForEach(Array(my.moves.enumerated()), id: \.offset) { i, m in
                        Button { Task { await turn(i) } } label: {
                            VStack(spacing: 1) {
                                Text(m.name).font(.rounded(15, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                                Text("\(m.type.displayName.uppercased())  PP \(m.pp)/\(m.maxPP)")
                                    .font(.rounded(10, .bold)).monospacedDigit().opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .glassCapsule(tint: Color(hex: m.type.hex), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || !my.canSelect(i))
                        .opacity(busy || !my.canSelect(i) ? 0.55 : 1)
                    }
                } else {
                    // no PP left anywhere: Struggle
                    Button { Task { await turn(-1) } } label: {
                        Text("Struggle").font(.rounded(15, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .glassCapsule(tint: Color(hex: PokeType.normal.hex), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
    }

    /// Mean Look, Spider Web, Block, Ingrain, Shadow Tag, Arena Trap and Magnet Pull keep you in.
    private var cantEscape: Bool {
        guard mine.indices.contains(me), foes.indices.contains(foe) else { return false }
        let m = mine[me], f = foes[foe]
        if m.trapped { return true }
        if f.has("Shadow Tag") { return true }
        if f.has("Arena Trap"), !m.types.contains(.flying), !m.has("Levitate") { return true }
        if f.has("Magnet Pull"), m.types.contains(.steel) { return true }
        return false
    }

    /// Switch and give up sit lower down, away from the moves.
    @ViewBuilder private var sideButtons: some View {
        if outcome == nil, mine.indices.contains(me), foes.indices.contains(foe) {
            HStack(spacing: 10) {
                Button { forcedSwitch = false; choosingSwitch = true } label: {
                    Label("Pokémon", systemImage: "arrow.left.arrow.right").font(.rounded(15, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .glassCapsule(tint: Color(hex: 0xF5C542), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(busy || mine.filter { !$0.fainted }.count < 2 || cantEscape)
                Button { Task { await forfeit() } } label: {
                    Label("Give up", systemImage: "flag.fill").font(.rounded(15, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .glassCapsule(tint: Color(hex: 0xE5484D), interactive: true)
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

    private func sendOutFoe(thrown: Bool = true) async {
        foeBoxIn = false
        if thrown { await say("\(trainer.title) \(trainer.name) sent out \(foes[foe].name)!", 350) }
        await throwBall(from: CGPoint(x: vw + 16, y: foeFeet.y - 60), to: CGPoint(x: foeFeet.x, y: foeFeet.y - 14), arc: 30, foeSide: true)
        withAnimation(.spring(duration: 0.35)) { foeBoxIn = true }
        if meShown { await switchedIn(.foe) }
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
        for m in mine + foes { shownHP[m.id] = m.hp }
        startMusic()
        async let bg = BattleGfx.frontierBackground()
        async let pic = loadTrainerPic()
        async let back = BattleGfx.trainerBack(style)
        async let balls = BattleGfx.ball(.poke)
        await BattleHUD.shared.load(gen)
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
        await switchedIn(.foe)
        await switchedIn(.mine)
        busy = false
        text = "What will \(mine[me].name) do?"
    }

    /// The opponent's picture from your trainer's generation.
    private func loadTrainerPic() async -> UIImage? {
        if let u = gen.trainerPicURL(trainer.pic) { return await BattleHUD.gbTrainerPic(u) }
        if let fr = BattleGen.fireRedFrontPic(trainer.pic) { return await PretFiles.sprite("firered/" + fr) }
        return await PretFiles.sprite("graphics/trainers/front_pics/\(trainer.pic).png")
    }

    private func startMusic() {
        let key: String
        if trainer.isChampion || trainer.isElite { key = trainer.isBrain ? "brain" : "elite" }
        else if trainer.isLeader { key = "leader" }
        else { key = gen.rawValue }
        if let t = BattleAudio.tracks[key] { BattleAudio.shared.startMusic(t) }
    }

    /// One turn through the Gen 3 engine; then its events are played out in order.
    private func turn(_ move: Int?) async {
        busy = true
        await runTurn(myMove: move)
        if await settle() { return }
        // Two-turn moves, recharging, Thrash, Rollout and Bide carry on by themselves
        if mine[me].actsAlone, !foes[foe].fainted {
            await wait(400)
            await turn(0)
            return
        }
        text = "What will \(mine[me].name) do?"
        busy = false
    }

    /// Runs the engine for one turn (`myMove` nil = you switched, so only the foe acts) and plays it out.
    private func runTurn(myMove: Int?) async {
        let foeMove = BattleEngine.aiMove(foes[foe], vs: mine[me], field: field)
        var a = mine[me], b = foes[foe], f = field
        let events = BattleEngine.turn(mine: &a, foe: &b, field: &f, myMove: myMove, foeMove: foeMove)
        await apply(a, b, f, events)
    }

    /// Puts the engine's results in place, with the HP bars following the events.
    private func apply(_ a: BattleMon, _ b: BattleMon, _ f: BattleField, _ events: [BattleEvent]) async {
        let myHP = a.hp, foeHP = b.hp
        mine[me] = a; foes[foe] = b; field = f
        mine[me].hp = shownHP[a.id] ?? myHP; foes[foe].hp = shownHP[b.id] ?? foeHP
        await play(events)
        mine[me].hp = myHP; foes[foe].hp = foeHP
        shownHP[a.id] = myHP; shownHP[b.id] = foeHP
    }

    /// Fainting and Roar/Whirlwind after a turn. Returns true when the battle has moved on (or ended).
    private func settle() async -> Bool {
        if let side = pendingDrag {
            pendingDrag = nil
            if side == .foe, !foes[foe].fainted, let next = foes.indices.filter({ $0 != foe && !foes[$0].fainted }).randomElement() {
                foes[foe].switchedOut()
                withAnimation(.easeIn(duration: 0.3)) { foeBoxIn = false; foeShown = false }
                await wait(350)
                foe = next
                shownHP[foes[foe].id] = foes[foe].hp
                await say("The foe's \(foes[foe].name) was dragged out!", 500)
                await sendOutFoe(thrown: false)
            } else if side == .mine, !mine[me].fainted, let next = mine.indices.filter({ $0 != me && !mine[$0].fainted }).randomElement() {
                await recallMine()
                mine[me].switchedOut()
                me = next
                shownHP[mine[me].id] = mine[me].hp
                await say("\(mine[me].name) was dragged out!", 500)
                await sendOutMine(withTrainer: false)
                await switchedIn(.mine)
            } else {
                await say("But it failed!", 700)
            }
        }
        if foes[foe].fainted { await foeFainted(); if mine[me].fainted, outcome == nil { await myFainted() }; return true }
        if mine[me].fainted { await myFainted(); return true }
        return false
    }

    /// Spikes, Intimidate, Trace and weather abilities as a Pokémon comes out.
    private func switchedIn(_ side: BattleSide) async {
        guard mine.indices.contains(me), foes.indices.contains(foe) else { return }
        var a = mine[me], b = foes[foe], f = field
        let ev = side == .mine ? BattleEngine.switchIn(&a, side: .mine, other: &b, field: &f)
                               : BattleEngine.switchIn(&b, side: .foe, other: &a, field: &f)
        guard !ev.isEmpty else { return }
        await apply(a, b, f, ev)
    }

    /// The move's animation, in the style of your trainer's generation.
    private func animate(_ m: MoveInfo, by side: BattleSide) async {
        let mineSide = side == .mine
        let me = CGPoint(x: myFeet.x + 6, y: myFeet.y - 34), them = CGPoint(x: foeFeet.x, y: foeFeet.y - 24)
        let kind = MoveAnim.kind(for: m, targetsSelf: m.targetsUser)
        let selfMove = kind == .auraUp || kind == .heal
        let from = mineSide ? me : them
        let to = selfMove ? from : (mineSide ? them : me)
        async let p = BattleAnimGfx.particle(gen, type: m.type, kind: kind)
        async let i = BattleAnimGfx.impact(gen)
        let particle = await p, impact = await i
        let duration = kind == .contact ? 0.8 : 0.95
        anim = MoveAnim(kind: kind, from: from, to: to, particle: kind == .contact && m.type == .normal ? nil : particle,
                        impact: impact, size: gen.isGameBoy ? 16 : 24, start: .now, duration: duration)
        if kind == .contact {
            withAnimation(.easeOut(duration: 0.18)) { if mineSide { meLunge = 1 } else { foeLunge = 1 } }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeIn(duration: 0.2)) { if mineSide { meLunge = 0 } else { foeLunge = 0 } }
        }
        if ["earthquake", "magnitude", "fissure", "explosion", "self-destruct"].contains(m.key) {
            for k in 0..<8 {
                withAnimation(.linear(duration: 0.05)) { shake = k % 2 == 0 ? 4 : -4 }
                try? await Task.sleep(for: .milliseconds(55))
            }
            withAnimation(.linear(duration: 0.05)) { shake = 0 }
        }
        try? await Task.sleep(for: .milliseconds(Int(duration * 1000) - (kind == .contact ? 220 : 0)))
        anim = nil
    }

    private func play(_ events: [BattleEvent]) async {
        for e in events {
            switch e {
            case .say(let t):
                await say(t, 900)
            case .uses(let side, let m):
                BattleAudio.shared.playMove(m)
                await animate(m, by: side)
            case .hp(let side, let hp, let eff):
                let isMine = side == .mine
                guard (isMine ? mine : foes).indices.contains(isMine ? me : foe) else { continue }
                let id = isMine ? mine[me].id : foes[foe].id
                let before = shownHP[id] ?? hp
                if let eff {
                    BattleAudio.shared.playHit(eff)
                    Haptics.tap()
                    for _ in 0..<2 {
                        if isMine { meFlash.toggle() } else { foeFlash.toggle() }
                        try? await Task.sleep(for: .milliseconds(90))
                        if isMine { meFlash.toggle() } else { foeFlash.toggle() }
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                }
                // the bar drains (or fills) a step at a time, like the games
                let steps = max(1, min(24, abs(before - hp)))
                for k in 1...steps {
                    shownHP[id] = before + (hp - before) * k / steps
                    try? await Task.sleep(for: .milliseconds(28))
                }
                if isMine { mine[me].hp = hp } else { foes[foe].hp = hp }
                try? await Task.sleep(for: .milliseconds(200))
            case .stat(_, let up):
                BattleAudio.shared.playStat(up: up)
            case .status:
                break
            case .forceSwitch(let side):
                pendingDrag = side
            case .transform:
                CryPlayer.shared.play(mine[me].speciesID)
            }
        }
    }

    private func foeFainted() async {
        CryPlayer.shared.play(foes[foe].speciesID)
        withAnimation(.easeIn(duration: 0.3)) { foeBoxIn = false }
        await say("The foe's \(foes[foe].name) fainted!")
        foeShown = false
        if let next = foes.indices.first(where: { !foes[$0].fainted }) {
            foe = next
            shownHP[foes[foe].id] = foes[foe].hp
            await sendOutFoe()
            if mine[me].fainted { return }          // you choose your next one first
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
        mine[me].switchedOut()
        me = i
        shownHP[mine[me].id] = mine[me].hp
        await sendOutMine(withTrainer: false)
        await switchedIn(.mine)
        if !wasForced {
            // switching uses your turn: only the foe moves
            await runTurn(myMove: nil)
        }
        if await settle() { return }
        text = "What will \(mine[me].name) do?"
        busy = false
    }

    private func forfeit() async {
        busy = true
        await say("You gave up the battle.", 1_000)
        outcome = false
    }
}
