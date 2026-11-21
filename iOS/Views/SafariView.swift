import SwiftUI
import MapKit

/// A Gen 3-style wild encounter: the Pokémon slides in on its platform (top right) while your trainer slides
/// in from the right (bottom left), the text box types "A wild … appeared!", then you throw balls, berries or run.
struct SafariView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var safari: SafariEncounter
    @State private var ball: BallKind = .poke
    @State private var busy = false
    @State private var caught: OwnedPokemon?

    // Intro
    @State private var slideStart: Date?
    @State private var introDone = false
    @State private var shaded = true             // darker until it reaches its spot (like Emerald)
    @State private var boxesIn = false           // name box slides in once everything has arrived
    @State private var showRates = false
    @State private var message = ""

    // Sprites
    @State private var enemyBounds = SpriteBounds.fallback
    @State private var trainerFrames: [UIImage] = []
    @State private var trainerFrame = 0
    @State private var ballFrames: [UIImage] = []

    // The thrown ball
    @State private var ballVisible = false
    @State private var ballOpen = false
    @State private var ballPos: CGPoint = .zero
    @State private var flight: Flight?
    @State private var wobble: Double = 0
    @State private var ballDim = false
    @State private var stars = false
    @State private var spriteHidden = false
    @State private var flash = 0.0

    private struct Flight { var from: CGPoint; var to: CGPoint; var start: Date; var duration: Double }

    init(wild: PendingEncounter) { _safari = State(initialValue: SafariEncounter(wild: wild)) }

    private var wild: PendingEncounter { safari.wild }
    private var ballsLeft: Int { store.state.balls[ball, default: 0] }
    private var style: TrainerStyle { store.state.trainer.style }
    private var trainerName: String { store.state.trainer.name }

    /// Every position on the battle screen, worked out from its size.
    private struct Layout {
        let size: CGSize
        var W: CGFloat { size.width }
        var H: CGFloat { size.height }
        /// Pixel scales: the trainer's 64 px back sprite, and the (bigger, more detailed) Gen 5 Pokémon sprites.
        var t: CGFloat { min(W * 0.0075, H * 0.0036) }
        var e: CGFloat { t * 0.72 }
        var barCenterY: CGFloat { H * 0.665 }
        var barHeight: CGFloat { 84 }
        var barTop: CGFloat { barCenterY - barHeight / 2 }
        var enemyPlatform: CGPoint { CGPoint(x: W * 0.70, y: H * 0.355) }
        var trainerSize: CGFloat { 64 * t }
        var trainerX: CGFloat { W * 0.30 }
        var playerPlatform: CGPoint { CGPoint(x: trainerX + 6, y: barTop - 16) }
        var trainerTop: CGFloat { barTop + 6 - trainerSize }       // its waist tucks behind the text box
        var ballSize: CGFloat { 16 * t * 0.85 }
        var hand: CGPoint { CGPoint(x: trainerX + trainerSize * 0.28, y: trainerTop + trainerSize * 0.3) }
        var buttonsY: CGFloat { H - 92 }
    }

    var body: some View {
        GeometryReader { geo in
            let L = Layout(size: geo.size)
            ZStack {
                background

                TimelineView(.animation(paused: !animating)) { tl in
                    let p = introProgress(at: tl.date)
                    ZStack {
                        enemy(L, p: p)
                        trainer(L, p: p)
                        thrownBall(L, now: tl.date)
                    }
                }

                topBar.frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)

                if boxesIn {
                    nameBox
                        .frame(maxWidth: L.W * 0.6, alignment: .leading)
                        .position(x: L.W * 0.6 / 2 + 16, y: L.H * 0.15)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                textBox(L).position(x: L.W / 2, y: L.barCenterY).zIndex(3)

                bottomControls(L).position(x: L.W / 2, y: L.buttonsY)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(item: $caught, onDismiss: { dismiss() }) { CaughtView(pokemonID: $0.id, safari: safari) }
        .onDisappear { SoundKit.shared.setScene(.map) }
        .task(id: ball) { ballFrames = await BattleGfx.ball(ball) }
        .onAppear(perform: start)
    }

    private var animating: Bool { (slideStart != nil && !introDone) || flight != nil }

    // MARK: Intro

    private func start() {
        SoundKit.shared.setScene(.battle)
        safari.caughtBefore = store.state.dexCaught.contains(wild.speciesID)
        pickAvailableBall()
        trainerFrame = style.backIdleFrame
        Task { @MainActor in
            // Load everything first, so the Pokémon, the trainer and their platforms arrive together
            async let back = BattleGfx.trainerBack(style)
            await preloadSprite()
            trainerFrames = await back
            // Both slide in (shaded Pokémon from the left, you from the right), then it lights up and cries
            slideStart = .now
            try? await Task.sleep(for: .milliseconds(1_120))
            withAnimation(.easeOut(duration: 0.35)) { shaded = false }
            introDone = true
            withAnimation(.spring(duration: 0.4)) { boxesIn = true }
            try? await Task.sleep(for: .milliseconds(200))
            CryPlayer.shared.play(wild.speciesID)
            if wild.isShiny {
                try? await Task.sleep(for: .milliseconds(350))
                SoundKit.shared.play(.shiny)
            }
            await type(wild.isShiny ? "A shiny \(wild.species.name) appeared!" : "A wild \(wild.species.name) appeared!",
                       hold: 1.1)
            withAnimation(.easeInOut(duration: 0.3)) { message = "" }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.35)) { showRates = true }
            if store.state.totalBalls == 0 { message = "Out of balls! Walk to earn more." }
            else { message = "What will \(trainerName) do?" }
        }
    }

    /// Shows a line in the text box and waits for it to finish typing (plus `hold` seconds).
    private func type(_ text: String, hold: Double) async {
        message = text
        try? await Task.sleep(for: .seconds(Double(text.count) * TypewriterText.perChar + hold))
    }

    // MARK: Pieces

    /// A zoomed-in, blurred view of the map where you met it.
    @ViewBuilder private var background: some View {
        let loc = wild.location.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            ?? LocationTracker.shared.currentLocation()?.coordinate
        ZStack {
            if let loc {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: loc, distance: 260, heading: 0, pitch: 55)),
                    interactionModes: [])
                    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                    .allowsHitTesting(false)
                    .scaleEffect(1.15)                 // hide the blurred edges
                    .blur(radius: 14)
            } else {
                AppBackground()
            }
            LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.05), .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private func platform(width: CGFloat) -> some View {
        Ellipse()
            .fill(.white.opacity(0.13))
            .overlay(Ellipse().stroke(.white.opacity(0.12), lineWidth: 1))
            .frame(width: width, height: width * 0.2)
    }

    /// The wild Pokémon on its platform (it floats above it if it flies or levitates).
    @ViewBuilder private func enemy(_ L: Layout, p: Double) -> some View {
        let b = enemyBounds
        let w = b.size.width * L.e, h = b.size.height * L.e
        let lift = CGFloat(BattleElevation.pixels(wild.speciesID)) * 1.5 * L.e
        let feet = L.enemyPlatform.y - 4
        // centre the canvas so the lowest visible pixel rests on the platform
        let cy = feet - (b.bottom - b.size.height / 2) * L.e - lift
        let dx = -L.W * (1 - p)
        ZStack {
            platform(width: L.W * 0.52)
                .position(L.enemyPlatform)
            AnimatedSprite(speciesID: wild.speciesID, shiny: wild.isShiny)
                .frame(width: w, height: h)
                .brightness(shaded ? -0.45 : 0)
                .saturation(shaded ? 0.6 : 1)
                .opacity(spriteHidden ? 0 : 1)
                .scaleEffect(spriteHidden ? 0.1 : 1)
                .position(x: L.enemyPlatform.x, y: cy)
            Circle().fill(.white).frame(width: 150, height: 150).blur(radius: 24)
                .opacity(flash).allowsHitTesting(false)
                .position(hitPoint(L))
        }
        .offset(x: dx)
        .opacity(min(1, p * 2))
    }

    /// Your trainer's back sprite on the near platform.
    @ViewBuilder private func trainer(_ L: Layout, p: Double) -> some View {
        ZStack {
            platform(width: L.W * 0.66)
                .position(L.playerPlatform)
            if trainerFrames.indices.contains(trainerFrame) {
                Image(uiImage: trainerFrames[trainerFrame])
                    .interpolation(.none)
                    .resizable()
                    .frame(width: L.trainerSize, height: L.trainerSize)
                    .position(x: L.trainerX, y: L.trainerTop + L.trainerSize / 2)
            }
        }
        .offset(x: L.W * (1 - p))
        .opacity(min(1, p * 2))
    }

    private func hitPoint(_ L: Layout) -> CGPoint {
        let b = enemyBounds
        let lift = CGFloat(BattleElevation.pixels(wild.speciesID)) * 1.5 * L.e
        let visible = (b.bottom - b.top) * L.e
        return CGPoint(x: L.enemyPlatform.x, y: L.enemyPlatform.y - 4 - lift - visible * 0.55)
    }

    private func groundPoint(_ L: Layout) -> CGPoint {
        CGPoint(x: L.enemyPlatform.x, y: L.enemyPlatform.y - L.ballSize * 0.35)
    }

    /// The Emerald ball sprite: flies in an arc (spinning), opens, drops, bounces and shakes.
    @ViewBuilder private func thrownBall(_ L: Layout, now: Date) -> some View {
        if ballVisible {
            let bp = ballPoint(at: now)
            ZStack {
                Group {
                    if ballFrames.count >= 2 {
                        Image(uiImage: ballFrames[ballOpen ? 1 : 0]).interpolation(.none).resizable()
                    } else {
                        BallGlyph(kind: ball)
                    }
                }
                .frame(width: L.ballSize, height: L.ballSize)
                .rotationEffect(.degrees(bp.1))
                .rotationEffect(.degrees(wobble), anchor: .bottom)
                .brightness(ballDim ? -0.25 : 0)
                // Caught: tiny stars pop out of the ball
                ForEach(0..<6, id: \.self) { i in
                    let a = Double(i) / 6 * 2 * .pi - .pi / 2
                    Image(systemName: "star.fill")
                        .font(.system(size: 9 + CGFloat(i % 2) * 4, weight: .black))
                        .foregroundStyle(Color(hex: 0xFFE27A))
                        .offset(x: stars ? cos(a) * 40 : 0, y: stars ? sin(a) * 40 - 8 : 0)
                        .opacity(stars ? 0 : (ballDim ? 1 : 0))
                        .scaleEffect(stars ? 1.2 : 0.3)
                }
            }
            .position(bp.0)
        }
    }

    private func ballPoint(at now: Date) -> (CGPoint, Double) {
        guard let f = flight else { return (ballPos, 0) }
        let t = min(1, max(0, now.timeIntervalSince(f.start) / f.duration))
        let x = f.from.x + (f.to.x - f.from.x) * t
        let arc = 4 * t * (1 - t) * 120
        let y = f.from.y + (f.to.y - f.from.y) * t - arc
        return (CGPoint(x: x, y: y), t * 720)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if let place = wild.location?.placeName {
                Label(place, systemImage: "mappin.and.ellipse").font(.rounded(13, .heavy)).lineLimit(1)
                    .padding(.horizontal, 12).frame(height: 36)
                    .glassCapsule()
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 16)
    }

    /// Name, gender, level and types, top left like the games' health box.
    private var nameBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(wild.species.name + (wild.isShiny ? " ✨" : ""))
                    .font(.rounded(22, .black)).lineLimit(1).minimumScaleFactor(0.6)
                Text(wild.gender.symbol).font(.rounded(16, .heavy))
                    .foregroundStyle(wild.gender == .female ? Color(hex: 0xFF8FA8) : Color(hex: 0x7FB8FF))
                Spacer(minLength: 4)
                Text("Lv\(wild.level)").font(.rounded(15, .heavy)).foregroundStyle(Theme.tealDark)
            }
            HStack(spacing: 6) { ForEach(wild.species.types, id: \.self) { TypeChip(type: $0) } }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCard(18)
    }

    /// The text box: types out messages; the catch / flee odds sit on the right once the intro is done.
    private func textBox(_ L: Layout) -> some View {
        HStack(alignment: .center) {
            TypewriterText(text: message)
                .font(.rounded(16, .heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
            if showRates {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(pct(safari.catchChance(ball: ball)))% catch")
                        .foregroundStyle(Theme.inkSoft)
                    Text(safari.baitTurns > 0 ? "\(pct(safari.fleeChance))% flee · eating" : "\(pct(safari.fleeChance))% flee")
                        .foregroundStyle(safari.baitTurns > 0 ? Theme.tealDark : Theme.orange)
                }
                .font(.rounded(13, .heavy))
                .contentTransition(.numericText())
                .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .frame(height: L.barHeight)
        .frame(maxWidth: .infinity)
        .glassCard(22)
        .padding(.horizontal, 12)
    }

    private func bottomControls(_ L: Layout) -> some View {
        let canAct = introDone && showRates && !busy && safari.phase == .active
        return HStack(alignment: .center) {
            // Berry: tap throws the one you have most of; hold to pick which
            Menu {
                ForEach(ownedBerries, id: \.self) { key in
                    Button("\(Dex.itemName(key)) ×\(store.state.bag[key] ?? 0)") { throwBerry(key) }
                }
            } label: {
                controlLabel(berryCount == 0 ? "No berries" : "Berry ×\(berryCount)", tint: Theme.orange) {
                    if let key = ownedBerries.first {
                        ItemSprite(key: key).frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "leaf.fill").font(.system(size: 22, weight: .bold))
                    }
                }
            } primaryAction: {
                if let key = ownedBerries.first { throwBerry(key) }
            }
            .disabled(!canAct || berryCount == 0)
            .opacity(berryCount == 0 ? 0.55 : 1)

            Spacer()

            // Ball: tap throws it; hold to switch ball
            Menu {
                ForEach(BallKind.allCases.filter { $0.isStepBall || store.state.balls[$0, default: 0] > 0 }) { k in
                    Button {
                        ball = k
                        SoundKit.shared.play(.select)
                    } label: {
                        if k == ball {
                            Label("\(k.name) ×\(store.state.balls[k, default: 0])", systemImage: "checkmark")
                        } else {
                            Text("\(k.name) ×\(store.state.balls[k, default: 0])")
                        }
                    }
                    .disabled(store.state.balls[k, default: 0] == 0)
                }
            } label: {
                controlLabel("\(ball.name) ×\(ballsLeft)", size: 86) {
                    ItemSprite(key: ball.itemKey).frame(width: 40, height: 40)
                }
            } primaryAction: {
                if ballsLeft > 0 { throwBall(L) }
                else { message = "No \(ball.name)s left! Hold to pick another." }
            }
            .disabled(!canAct)
            .opacity(ballsLeft > 0 ? 1 : 0.55)
            .accessibilityLabel("Throw \(ball.name), \(ballsLeft) left. Hold to change ball.")

            Spacer()

            Button(action: run) {
                controlLabel("Run", tint: nil) {
                    Image(systemName: "figure.run").font(.system(size: 22, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .disabled(!introDone || busy)
        }
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    private func controlLabel<Icon: View>(_ title: String, size: CGFloat = 72, tint: Color? = nil,
                                          @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 2) {
            icon()
            Text(title).font(.rounded(10, .black)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .frame(width: size, height: size)
        .foregroundStyle(.white)
        .glassCircle(tint: tint)
    }

    // MARK: Actions

    private func run() {
        guard introDone, !busy else { return }
        busy = true
        SoundKit.shared.play(.runAway)
        safari.run()
        store.finish(safari)
        Task { @MainActor in
            await type("Got away safely!", hold: 0.4)
            dismiss()
        }
    }

    /// Plays the trainer's throwing frames (Gen 3 trainers; Gold/Kris just stand there, like Gen 2).
    private func playThrowAnimation() {
        let anim = style.backThrow
        guard !anim.frames.isEmpty, !trainerFrames.isEmpty else { return }
        Task { @MainActor in
            for (f, d) in anim.frames {
                if trainerFrames.indices.contains(f) { trainerFrame = f }
                if d > 0 { try? await Task.sleep(for: .seconds(d)) }
            }
            try? await Task.sleep(for: .milliseconds(500))
            trainerFrame = style.backIdleFrame
        }
    }

    private func throwBall(_ L: Layout) {
        guard !busy, introDone, safari.phase == .active, store.useBall(ball) else { return }
        busy = true
        message = "\(trainerName) threw a \(ball.name)!"
        Task { @MainActor in
            // 1. Wind up and throw: the ball arcs from your hand to the Pokémon
            playThrowAnimation()
            try? await Task.sleep(for: .seconds(trainerFrames.isEmpty || style.backThrow.frames.isEmpty ? 0.1 : style.backThrow.release))
            SoundKit.shared.play(.ballThrow)
            let hit = hitPoint(L)
            ballOpen = false; wobble = 0; ballDim = false; stars = false
            ballPos = L.hand
            ballVisible = true
            flight = Flight(from: L.hand, to: hit, start: .now, duration: 0.6)
            try? await Task.sleep(for: .milliseconds(600))
            ballPos = hit
            flight = nil

            let result = safari.throwBall(ball, quality: nil)

            // 2. It hits: the ball pops open, the Pokémon is pulled in with a flash, then it snaps shut
            SoundKit.shared.play(.ballOpen)
            ballOpen = true
            withAnimation(.easeOut(duration: 0.12)) { flash = 0.7 }
            withAnimation(.easeIn(duration: 0.35)) { spriteHidden = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.3)) { flash = 0 }
            ballOpen = false
            try? await Task.sleep(for: .milliseconds(200))

            // 3. It drops to the ground and bounces three times
            let ground = groundPoint(L)
            for (i, h) in [CGFloat(0), 26, 12].enumerated() {
                if i > 0 {
                    withAnimation(.easeOut(duration: 0.16)) { ballPos.y = ground.y - h }
                    try? await Task.sleep(for: .milliseconds(170))
                }
                withAnimation(.easeIn(duration: i == 0 ? 0.3 : 0.16)) { ballPos = ground }
                try? await Task.sleep(for: .milliseconds(i == 0 ? 310 : 170))
                SoundKit.shared.play(.ballBounce)
            }
            try? await Task.sleep(for: .milliseconds(450))

            // 4. Shakes, each with the shake sound
            for _ in 0..<result.shakes {
                SoundKit.shared.play(.ballShake)
                withAnimation(.easeInOut(duration: 0.15)) { wobble = -22 }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 0.15)) { wobble = 22 }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 0.15)) { wobble = 0 }
                try? await Task.sleep(for: .milliseconds(550))
            }

            if result.caught {
                // 5. Click! Stars pop out, the ball dims, then the catch fanfare
                SoundKit.shared.play(.ballClick)
                ballDim = true
                withAnimation(.easeOut(duration: 0.7)) { stars = true }
                try? await Task.sleep(for: .milliseconds(650))
                if SoundKit.shared.caughtMusicFile != nil && SoundKit.shared.battleMusicOn {
                    SoundKit.shared.setScene(.caught)
                } else {
                    SoundKit.shared.play(.ballCatch)
                }
                await type("Gotcha! \(wild.species.name) was caught!", hold: 1.2)
                caught = store.finish(safari)
                return
            }
            // Broke free: the ball bursts open and the Pokémon comes back out
            SoundKit.shared.play(.ballOpen)
            ballOpen = true
            withAnimation(.easeOut(duration: 0.1)) { flash = 0.7 }
            withAnimation(.spring(duration: 0.3)) { spriteHidden = false }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.15)) { ballVisible = false }
            ballOpen = false
            await type(safari.log.last ?? "Oh no! It broke free!", hold: 0.6)
            if result.fled { endFled(); return }
            pickAvailableBall()
            message = store.state.totalBalls == 0 ? "Out of balls! Walk to earn more." : "What will \(trainerName) do?"
            busy = false
        }
    }

    /// Waits (at most ~2.5 s) until the wild Pokémon's sprite is downloaded, then measures where its feet are.
    private func preloadSprite() async {
        let id = wild.speciesID, shiny = wild.isShiny
        let load = Task.detached { () -> SpriteBounds? in
            var u = await SpriteStore.shared.url(shiny ? .shiny : .front, speciesID: id)
            if u == nil && shiny { u = await SpriteStore.shared.url(.front, speciesID: id) }
            guard let u, let img = GIFCache.shared.image(at: u) else { return nil }
            return SpriteBounds(img)
        }
        let timeout = Task { try? await Task.sleep(for: .milliseconds(2_500)); load.cancel() }
        if let b = await load.value { enemyBounds = b }
        timeout.cancel()
    }

    /// 0 → 1 over 1.1 s, eased out (fast start, gentle stop).
    private func introProgress(at date: Date) -> Double {
        if introDone { return 1 }
        guard let start = slideStart else { return 0 }
        let t = min(1, max(0, date.timeIntervalSince(start) / 1.1))
        return 1 - pow(1 - t, 3)
    }

    private func pct(_ p: Double) -> Int { Int((p * 100).rounded()) }

    /// Berries you have, most first.
    private var ownedBerries: [String] {
        ItemCatalog.berries.filter { (store.state.bag[$0] ?? 0) > 0 }
            .sorted { (store.state.bag[$0] ?? 0) > (store.state.bag[$1] ?? 0) }
    }
    private var berryCount: Int { ItemCatalog.berries.reduce(0) { $0 + (store.state.bag[$1] ?? 0) } }

    private func throwBerry(_ key: String) {
        guard store.consume(key) else { return }
        SoundKit.shared.play(.useItem)
        withAnimation { safari.giveBerry(Dex.itemName(key)) }
        message = safari.log.last ?? "\(trainerName) threw a \(Dex.itemName(key))!"
        if safari.phase == .fled { endFled() }
    }

    private func pickAvailableBall() {
        if store.state.balls[ball, default: 0] == 0,
           let k = BallKind.allCases.first(where: { store.state.balls[$0, default: 0] > 0 }) { ball = k }
    }

    private func endFled() {
        busy = true
        Task { @MainActor in
            withAnimation { spriteHidden = true }
            await type("\(wild.species.name) fled!", hold: 0.9)
            store.finish(safari)
            dismiss()
        }
    }
}

/// Text that types itself out letter by letter, like the games' text boxes (the layout never jumps:
/// letters not typed yet are just invisible).
struct TypewriterText: View {
    let text: String
    static let perChar = 0.03
    @State private var shown = 0

    var body: some View {
        var typed = AttributedString(String(text.prefix(shown)))
        typed.foregroundColor = Theme.ink
        var rest = AttributedString(String(text.dropFirst(shown)))
        rest.foregroundColor = .clear
        return Text(typed + rest)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .task(id: text) {
                shown = 0
                for i in 1...max(1, text.count) {
                    try? await Task.sleep(for: .seconds(Self.perChar))
                    if Task.isCancelled { return }
                    shown = i
                }
            }
    }
}
