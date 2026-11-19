import SwiftUI

/// "Go! Chikorita!" — the Pokémon bursts out of the ball it was caught in, with that ball's colours and effect.
/// The buddy skips this: it's already out, walking with you.
struct BallSendOut: View {
    let speciesID: Int
    let shiny: Bool
    let ball: BallKind
    var skip = false
    var playSounds = true
    var onRelease: () -> Void = {}

    @State private var stage = 0          // 0 ball drops · 1 wobble · 2 burst · 3 out
    @State private var burst = false
    @State private var flash = 0.0
    @State private var sparkle = false

    private var effect: BallEffect { BallEffect(ball) }

    var body: some View {
        if skip {
            AnimatedSprite(speciesID: speciesID, shiny: shiny).frame(width: 130, height: 130)
        } else {
            sendOut
        }
    }

    private var sendOut: some View {
        ZStack {
            // Particles from the ball's colours
            ForEach(0..<effect.count, id: \.self) { i in
                let angle = Double(i) / Double(effect.count) * 2 * .pi + effect.twist
                let dist: CGFloat = burst ? CGFloat(58 + (i % 3) * 16) : 0
                particle(i)
                    .offset(x: cos(angle) * dist, y: sin(angle) * dist * effect.squash - (burst && effect.rises ? 24 : 0))
                    .opacity(stage >= 2 && !burst ? 1 : 0)
                    .scaleEffect(burst ? 0.4 : 1.1)
            }

            // The Pokémon
            AnimatedSprite(speciesID: speciesID, shiny: shiny)
                .frame(width: 130, height: 130)
                .scaleEffect(stage >= 3 ? 1 : 0.05, anchor: .bottom)
                .brightness(stage >= 3 ? 0 : 1)
                .opacity(stage >= 2 ? 1 : 0)

            // Shiny stars after it appears
            if shiny {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: i.isMultiple(of: 2) ? 18 : 12, weight: .black))
                        .foregroundStyle(Color(hex: 0xFFE27A))
                        .offset(x: CGFloat([-48, 44, -30, 52, -56, 26][i]), y: CGFloat([-40, -50, 34, 18, -4, -62][i]))
                        .scaleEffect(sparkle ? 1 : 0.1)
                        .opacity(sparkle ? 0 : 1)
                }
            }

            // The ball
            ItemSprite(key: ball.itemKey)
                .frame(width: 34, height: 34)
                .offset(y: 40)
                .opacity(stage >= 2 ? 0 : 1)

            // White flash as it opens
            Circle().fill(.white)
                .frame(width: 90, height: 90)
                .blur(radius: 18)
                .scaleEffect(flash > 0 ? 1.6 : 0.2)
                .opacity(flash)
                .offset(y: 20)
        }
        .frame(width: 180, height: 140)
        .onAppear(perform: run)
    }

    @ViewBuilder private func particle(_ i: Int) -> some View {
        let c = effect.colors[i % effect.colors.count]
        switch effect.shape {
        case .star: Image(systemName: "star.fill").font(.system(size: 11, weight: .black)).foregroundStyle(c)
        case .bubble: Circle().stroke(c, lineWidth: 2).frame(width: 12, height: 12)
        case .heart: Image(systemName: "heart.fill").font(.system(size: 11, weight: .black)).foregroundStyle(c)
        case .spark: Capsule().fill(c).frame(width: 4, height: 14).rotationEffect(.radians(Double(i)))
        case .dot: Circle().fill(c).frame(width: 9, height: 9)
        }
    }

    private func run() {
        if skip { stage = 3; return }
        Task { @MainActor in
            stage = 1                                                              // the ball, briefly
            try? await Task.sleep(for: .milliseconds(300))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if playSounds { SoundKit.shared.play(.ballOpen) }
            withAnimation(.easeOut(duration: 0.12)) { stage = 2; flash = 1 }        // pops open
            withAnimation(.easeOut(duration: 0.7)) { burst = true }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62).delay(0.05)) { stage = 3 }
            onRelease()
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.4)) { flash = 0 }
            if shiny {
                try? await Task.sleep(for: .milliseconds(250))
                if playSounds { SoundKit.shared.play(.shiny) }
                withAnimation(.easeOut(duration: 0.9)) { sparkle = true }
            }
        }
    }
}

/// How each ball's release looks (inspired by the games' ball colours).
private struct BallEffect {
    enum Shape { case dot, star, bubble, heart, spark }
    var colors: [Color]
    var shape: Shape = .dot
    var count = 12
    var twist = 0.0
    var squash: CGFloat = 1
    var rises = false

    init(_ ball: BallKind) {
        switch ball {
        case .poke:    colors = [Color(hex: 0xE04A3F), .white]
        case .great:   colors = [Color(hex: 0x3D7BE0), Color(hex: 0xE04A3F), .white]
        case .ultra:   colors = [Color(hex: 0xF2C230), Color(hex: 0x2D2D2D)]; shape = .spark
        case .net:     colors = [Color(hex: 0x3FB8C9), .white]; shape = .bubble; squash = 0.7
        case .dive:    colors = [Color(hex: 0x3A6FD8), Color(hex: 0x9BD7F5)]; shape = .bubble; rises = true
        case .nest:    colors = [Color(hex: 0x8DBF3F), Color(hex: 0xF2D46B)]; twist = 0.3
        case .repeatBall: colors = [Color(hex: 0xE8902A), Color(hex: 0xF2C230)]; shape = .spark; count = 14
        case .timer:   colors = [Color(hex: 0xE04A3F), .white, Color(hex: 0x2D2D2D)]; shape = .spark; count = 10
        case .luxury:  colors = [Color(hex: 0xF2C230), Color(hex: 0xE04A3F)]; shape = .heart; count = 10
        case .premier: colors = [Color(hex: 0xE04A3F), .white]; shape = .star; count = 14
        case .safari:  colors = [Color(hex: 0x6E8B3D), Color(hex: 0xC9A86A)]; twist = 0.5
        case .master:  colors = [Color(hex: 0x7A3FB8), Color(hex: 0xE05FA0), .white]; shape = .star; count = 18
        }
    }
}
