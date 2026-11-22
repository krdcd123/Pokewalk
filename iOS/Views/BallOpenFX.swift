import SwiftUI

/// The burst when a ball opens, recreated from the games' own code:
/// - Emerald (battle_anim_throw.c): each ball has its own particle pattern, shape and spin
///   (Poké Ball sparkles fly out in two rings, Master Ball stars in a double spiral, Dive Ball bubbles, …).
/// - Crystal (BattleAnim_ThrowPokeBall): a puff of smoke for every ball; the Master Ball adds 8 sparkles.
/// Positions are in GBA/Game Boy pixels, scaled by `px`. The game runs at 60 frames a second.
struct BallOpenFX: View {
    let kind: BallKind
    let gameBoy: Bool
    let start: Date
    let px: CGFloat

    @State private var particles: [UIImage] = []
    @State private var smoke: [UIImage] = []
    @State private var sparkle: UIImage?
    @State private var finished = false

    var body: some View {
        Group {
            if !finished {
                TimelineView(.animation) { tl in
                    let f = Int(tl.date.timeIntervalSince(start) * 60)
                    ZStack {
                        if gameBoy { gen2(frame: f) } else { gen3(frame: f) }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: start) {
            finished = false
            if gameBoy {
                let g = await BattleGfx.gen2Poof(colour: kind == .master)
                smoke = g.smoke; sparkle = g.sparkle
            } else {
                particles = await BattleGfx.ballParticles()
            }
            try? await Task.sleep(for: .seconds(gameBoy ? 2.0 : 1.2))
            finished = true
        }
    }

    // MARK: Emerald

    struct Particle { var x: Double; var y: Double; var frame: Int; var flip: Bool }

    private static func sin8(_ a: Int, _ amp: Double) -> Double { sin(Double(a & 0xFF) / 256 * 2 * .pi) * amp }
    private static func cos8(_ a: Int, _ amp: Double) -> Double { cos(Double(a & 0xFF) / 256 * 2 * .pi) * amp }

    /// Which particle picture each ball uses, and how it animates (sAnims_BallParticles).
    private static func particleFrame(_ k: BallKind, t: Int) -> (Int, Bool) {
        switch k {
        case .poke, .great, .safari:
            let seq: [(Int, Bool)] = [(0, false), (1, false), (2, false), (0, true), (2, false), (1, false)]
            return seq[t % 6]
        case .master: return (3, false)
        case .net, .dive: return (4, false)
        case .nest: return (5, false)
        case .luxury, .premier: return ((t / 4) % 2 == 0 ? 6 : 7, false)
        case .ultra, .repeatBall, .timer: return (7, false)
        }
    }

    /// Every particle on screen at frame `f` (relative to the ball, y down).
    static func emerald(_ k: BallKind, frame f: Int) -> [Particle] {
        var out: [Particle] = []
        func fan(count: Int, step: Int, spin: Int, waves: [(delay: Int, dx: Double, dy: Double)]) {
            for w in waves {
                let t = f - w.delay
                guard t >= 0, t < 51 else { continue }
                for i in 0..<count {
                    let a = i * step + t * spin
                    let fr = particleFrame(k, t: t)
                    out.append(Particle(x: sin8(a, Double(t) * w.dx), y: cos8(a, Double(t) * w.dy), frame: fr.0, flip: fr.1))
                }
            }
        }
        switch k {
        case .poke:
            // one sparkle a frame for 16 frames, flying straight out (two rings of 8 directions)
            for i in 0..<16 {
                let t = f - i
                guard t >= 0, t < 25 else { continue }
                let a = (i % 8) * 32
                let fr = particleFrame(k, t: t)
                out.append(Particle(x: sin8(a, Double(2 * t)), y: cos8(a, Double(2 * t)), frame: fr.0, flip: fr.1))
            }
        case .great, .luxury: fan(count: 8, step: 32, spin: 8, waves: [(0, 2, 2), (9, 2, 2)])
        case .safari, .net: fan(count: 8, step: 32, spin: 4, waves: [(0, 1, 1)])
        case .ultra, .nest: fan(count: 10, step: 25, spin: 5, waves: [(0, 1, 1)])
        case .master: fan(count: 8, step: 32, spin: 8, waves: [(0, 2, 1), (0, 1, 2)])
        case .dive: fan(count: 8, step: 32, spin: 10, waves: [(0, 1, 2)])
        case .timer: fan(count: 8, step: 32, spin: 10, waves: [(0, 2, 1)])
        case .repeatBall:
            guard f < 51 else { break }
            for i in 0..<12 {
                let a = i * 21 + f * 6
                let fr = particleFrame(k, t: f)
                out.append(Particle(x: sin8(a, Double(f)), y: cos8(a, sin8(a, Double(f))), frame: fr.0, flip: fr.1))
            }
        case .premier:
            guard f < 51 else { break }
            for i in 0..<8 {
                let a = i * 32 + f * 10
                let fr = particleFrame(k, t: f)
                out.append(Particle(x: sin8(a, Double(f)), y: cos8(a, sin8(a & 0x3F, Double(f))), frame: fr.0, flip: fr.1))
            }
        }
        return out
    }

    @ViewBuilder private func gen3(frame f: Int) -> some View {
        if particles.count >= 8 {
            let list = Self.emerald(kind, frame: f)
            ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                Image(uiImage: particles[p.frame]).interpolation(.none).resizable()
                    .frame(width: 8 * px, height: 8 * px)
                    .scaleEffect(x: p.flip ? -1 : 1, y: 1)
                    .offset(x: p.x * px, y: p.y * px)
            }
        }
    }

    // MARK: Crystal

    @ViewBuilder private func gen2(frame f: Int) -> some View {
        // Ball poof: 4 steps of 3 frames — a small puff, then smoke spreading out in four directions
        if smoke.count >= 3, f < 12 {
            let step = f / 3
            if step == 0 {
                Image(uiImage: smoke[1]).interpolation(.none).resizable()
                    .frame(width: 16 * px, height: 16 * px)
            } else {
                let d = Double(step) * 6
                ForEach(0..<4, id: \.self) { i in
                    let sx: Double = i % 2 == 0 ? -1 : 1, sy: Double = i < 2 ? -1 : 1
                    Image(uiImage: smoke[step == 3 ? 2 : 0]).interpolation(.none).resizable()
                        .frame(width: 16 * px, height: 16 * px)
                        // the smoke piece is drawn as the top-right puff: mirror it out to each corner
                        .scaleEffect(x: sx, y: -sy)
                        .offset(x: sx * d * px, y: sy * d * px * 0.8)
                        .opacity(step == 3 ? 0.7 : 1)
                }
            }
        }
        // Master Ball: 8 sparkles shoot out (24 frames after the poof, for 64 frames)
        if kind == .master, let sparkle, f >= 28, f < 92 {
            let t = Double(f - 28)
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi
                Image(uiImage: sparkle).interpolation(.none).resizable()
                    .frame(width: 8 * px, height: 8 * px)
                    .offset(x: cos(a) * t * 0.9 * px, y: sin(a) * t * 0.9 * px)
                    .opacity(t < 48 ? 1 : (64 - t) / 16)
            }
        }
    }
}

extension BallKind {
    /// Emerald's gBallOpenFadeColors: the colour the Pokémon flashes as it's drawn into the ball.
    var openFadeColor: Color {
        let c: (Double, Double, Double)
        switch self {
        case .poke: c = (31, 22, 30)
        case .great: c = (16, 23, 30)
        case .safari: c = (23, 30, 20)
        case .ultra: c = (31, 31, 15)
        case .master: c = (23, 20, 28)
        case .net: c = (21, 31, 25)
        case .dive: c = (12, 25, 30)
        case .nest: c = (30, 27, 10)
        case .repeatBall: c = (31, 24, 16)
        case .timer: c = (29, 30, 30)
        case .luxury: c = (31, 17, 10)
        case .premier: c = (31, 9, 10)
        }
        return Color(red: c.0 / 31, green: c.1 / 31, blue: c.2 / 31)
    }
}
