import SwiftUI
import MapKit

/// Safari Zone-style encounter: tap the ball to throw (the catch is decided by the odds),
/// give bait to calm it down, or run.
struct SafariView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var safari: SafariEncounter
    @State private var ball: BallKind = .poke
    @State private var busy = false
    @State private var ballOffset: CGFloat = 0
    @State private var ballScale: CGFloat = 1
    @State private var wobble: Double = 0
    @State private var spriteHidden = false
    @State private var bannerText: String?
    @State private var caught: OwnedPokemon?
    @State private var throwing: String?        // shown instead of the result while the ball is shaking

    init(wild: PendingEncounter) { _safari = State(initialValue: SafariEncounter(wild: wild)) }

    private var wild: PendingEncounter { safari.wild }
    private var ballsLeft: Int { store.state.balls[ball, default: 0] }

    var body: some View {
        GeometryReader { geo in
            let spriteY = geo.size.height * 0.42
            let ballHomeY = geo.size.height - 130
            ZStack {
                background

                VStack { header; Spacer() }.padding(.top, 8)

                ZStack {
                    Ellipse().fill(Theme.ink.opacity(0.16)).frame(width: 200, height: 46).offset(y: 100)
                    AnimatedSprite(speciesID: wild.speciesID, shiny: wild.isShiny)
                        .frame(width: 170, height: 170)
                        .opacity(spriteHidden ? 0 : 1)
                        .scaleEffect(spriteHidden ? 0.2 : 1)
                }
                .position(x: geo.size.width / 2, y: spriteY)

                statusCard.position(x: geo.size.width / 2, y: geo.size.height * 0.66)

                // Tap the ball to throw it.
                Button { throwBall(distance: spriteY - ballHomeY) } label: {
                    ItemSprite(key: ball.itemKey)
                        .frame(width: 88 * ballScale, height: 88 * ballScale)
                        .rotationEffect(.degrees(wobble))
                        .frame(width: 110, height: 110)      // generous tap target
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(busy || ballsLeft == 0 || safari.phase != .active)
                .opacity(ballsLeft > 0 || busy ? 1 : 0.35)
                .position(x: geo.size.width / 2, y: ballHomeY + ballOffset)
                .accessibilityLabel("Throw \(ball.name), \(ballsLeft) left")
                .zIndex(2)   // keep the ball above the bottom controls so taps always reach it

                if !busy {
                    Text(ballsLeft > 0 ? "Tap to throw" : "No \(ball.name)s left")
                        .font(.rounded(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .glassCapsule()
                        .position(x: geo.size.width / 2, y: ballHomeY - 62)
                }

                bottomControls.position(x: geo.size.width / 2, y: geo.size.height - 70)

                if let text = bannerText {
                    Text(text).font(.rounded(30, .black)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(item: $caught, onDismiss: { dismiss() }) { CaughtView(pokemonID: $0.id, safari: safari) }
        .onDisappear { SoundKit.shared.setScene(.map) }
        .onAppear {
            SoundKit.shared.setScene(.battle)
            safari.caughtBefore = store.state.dexCaught.contains(wild.speciesID)
            pickAvailableBall(); CryPlayer.shared.play(wild.speciesID)
        }
    }

    // MARK: Pieces

    /// A zoomed-in, blurred view of the map where you met it, with the glass controls on top.
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

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    safari.run()
                    store.finish(safari)
                    dismiss()
                } label: {
                    Label("Run", systemImage: "arrow.right").font(.rounded(15, .heavy))
                        .padding(.horizontal, 16).frame(height: 40)
                        .glassCapsule(interactive: true)
                }
                .disabled(busy)
                Spacer()
                if let place = wild.location?.placeName {
                    Label(place, systemImage: "mappin.and.ellipse").font(.rounded(13, .heavy)).lineLimit(1)
                        .padding(.horizontal, 12).frame(height: 40)
                        .glassCapsule()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)

            Text(wild.isShiny ? "A SHINY POKÉMON APPEARED!" : "A WILD POKÉMON APPEARED!")
                .font(.rounded(12, .heavy)).foregroundStyle(wild.isShiny ? Color(hex: 0xF2C230) : Theme.inkSoft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(wild.species.name + (wild.isShiny ? " ✨" : "")).font(.rounded(32, .black))
                Text(wild.gender.symbol).font(.rounded(20, .heavy))
                Text("Lv \(wild.level)").font(.rounded(18, .heavy)).foregroundStyle(Theme.tealDark)
            }
            .foregroundStyle(Theme.ink)
            HStack { ForEach(wild.species.types, id: \.self) { TypeChip(type: $0) } }
        }
    }

    private var statusCard: some View {
        HStack {
            Text(throwing ?? safari.log.last ?? "")
            Spacer(minLength: 8)
            Text(safari.baitTurns > 0 ? "Eating · calmer" : "\(Int((safari.catchChance(ball: ball) * 100).rounded()))% catch")
                .foregroundStyle(safari.baitTurns > 0 ? Theme.tealDark : Theme.inkSoft)
        }
        .font(.rounded(13, .heavy))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14).frame(height: 44)
        .glassCard(16)
        .padding(.horizontal, 28)
    }

    private var bottomControls: some View {
        HStack {
            Button {
                withAnimation { safari.giveBait() }
                if safari.phase == .fled { endFled() }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "carrot.fill").font(.system(size: 22, weight: .bold))
                    Text("Bait").font(.rounded(12, .black))
                }
                .frame(width: 72, height: 72)
                .foregroundStyle(.white)
                .glassCircle(tint: Theme.orange)
            }
            .disabled(busy)

            Spacer()

            Menu {
                ForEach(BallKind.allCases.filter { $0.isStepBall || store.state.balls[$0, default: 0] > 0 }) { k in
                    Button("\(k.name) ×\(store.state.balls[k, default: 0])") { ball = k }
                        .disabled(store.state.balls[k, default: 0] == 0)
                }
            } label: {
                VStack(spacing: 0) {
                    Text("×\(ballsLeft)").font(.rounded(18, .black))
                    Text(ball.name).font(.rounded(10, .heavy)).foregroundStyle(Theme.inkSoft)
                }
                .frame(width: 72, height: 72)
                .foregroundStyle(.white)
                .glassCircle()
            }
            .disabled(busy)
        }
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    // MARK: Throwing

    private func throwBall(distance: CGFloat) {
        guard !busy, safari.phase == .active, store.useBall(ball) else { return }
        busy = true
        throwing = "You threw a \(ball.name)!"
        Task { @MainActor in
            // Ball arcs up to the Pokémon
            SoundKit.shared.play(.ballThrow)
            withAnimation(.easeOut(duration: 0.45)) { ballOffset = distance; ballScale = 0.55 }
            try? await Task.sleep(for: .milliseconds(480))

            let result = safari.throwBall(ball, quality: nil)

            // Pokémon goes into the ball, ball drops and wobbles 0–3 times
            withAnimation(.easeIn(duration: 0.25)) { spriteHidden = true }
            withAnimation(.easeIn(duration: 0.3)) { ballOffset += 70 }
            try? await Task.sleep(for: .milliseconds(500))
            for _ in 0..<result.shakes {
                SoundKit.shared.play(.ballShake)
                withAnimation(.easeInOut(duration: 0.15)) { wobble = -22 }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 0.15)) { wobble = 22 }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 0.15)) { wobble = 0 }
                try? await Task.sleep(for: .milliseconds(450))
            }

            if result.caught {
                // Third shake done — a beat of silence, then the click.
                try? await Task.sleep(for: .milliseconds(250))
                SoundKit.shared.play(.ballCatch)
                throwing = nil
                await show("Gotcha!\n\(wild.species.name) was caught!", duration: 1.4)
                caught = store.finish(safari)
                return
            }
            withAnimation(.spring(duration: 0.3)) { spriteHidden = false }
            throwing = nil
            await show(safari.log.last ?? "It broke free!", duration: 0.8)
            if result.fled { endFled(); return }
            withAnimation(.spring(duration: 0.4)) { ballOffset = 0; ballScale = 1; wobble = 0 }
            pickAvailableBall()
            busy = false
        }
    }

    private func pickAvailableBall() {
        if store.state.balls[ball, default: 0] == 0,
           let k = BallKind.allCases.first(where: { store.state.balls[$0, default: 0] > 0 }) { ball = k }
        if store.state.totalBalls == 0 { bannerText = "Out of balls!\nWalk to earn more." }
    }

    private func endFled() {
        busy = true
        Task { @MainActor in
            withAnimation { spriteHidden = true }
            await show("\(wild.species.name) fled!", duration: 1.2)
            store.finish(safari)
            dismiss()
        }
    }

    private func show(_ text: String, duration: Double) async {
        withAnimation(.spring) { bannerText = text }
        try? await Task.sleep(for: .seconds(duration))
        withAnimation { bannerText = nil }
    }
}
