import SwiftUI

/// The wild Pokémon's platform, themed by its type like the games' battle terrains (water, forest,
/// rocky ground, cave…) — drawn as a tinted Liquid Glass ellipse with a few details on top.
struct BattlePlatform: View {
    enum Terrain {
        case plain, water, ice, forest, fire, rocky, sand, cave, sky, electric, pink, steel

        init(_ type: PokeType?) {
            switch type {
            case .water: self = .water
            case .ice: self = .ice
            case .grass, .bug: self = .forest
            case .fire: self = .fire
            case .rock, .fighting: self = .rocky
            case .ground: self = .sand
            case .ghost, .dark, .poison, .psychic: self = .cave
            case .flying, .dragon: self = .sky
            case .electric: self = .electric
            case .fairy: self = .pink
            case .steel: self = .steel
            default: self = .plain
            }
        }

        var tint: Color? {
            switch self {
            case .plain: return nil
            case .water: return Color(hex: 0x3A9BFF)
            case .ice: return Color(hex: 0xA8E6FF)
            case .forest: return Color(hex: 0x4DBA4A)
            case .fire: return Color(hex: 0xFF6A2A)
            case .rocky: return Color(hex: 0xA68A64)
            case .sand: return Color(hex: 0xE2C26E)
            case .cave: return Color(hex: 0x8A5CD6)
            case .sky: return Color(hex: 0x9CD4FF)
            case .electric: return Color(hex: 0xFFD83A)
            case .pink: return Color(hex: 0xFF9AD0)
            case .steel: return Color(hex: 0xB4BFCC)
            }
        }
    }

    let terrain: Terrain
    let width: CGFloat

    init(type: PokeType?, width: CGFloat) { terrain = Terrain(type); self.width = width }

    private var height: CGFloat { width * 0.22 }
    private var tint: Color { terrain.tint ?? Color(hex: 0x8FB8A0) }

    var body: some View {
        ZStack {
            // soft shadow on the "ground"
            Ellipse().fill(.black.opacity(0.35))
                .frame(width: width * 0.96, height: height * 0.9)
                .blur(radius: 10)
                .offset(y: height * 0.32)
            // the side of the disc, so it looks thick
            Ellipse()
                .fill(LinearGradient(colors: [tint.opacity(0.75), Self.darker(tint).opacity(0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)
                .offset(y: height * 0.18)
            top
            PlatformDetails(terrain: terrain, width: width, height: height)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    /// The lit top surface: tinted glass, a highlight towards the top left, a bright rim.
    @ViewBuilder private var top: some View {
        let shape = Ellipse()
        ZStack {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(tint.opacity(0.55)), in: shape)
            } else {
                shape.fill(tint.opacity(0.55)).background(.ultraThinMaterial, in: shape)
            }
            shape.fill(RadialGradient(colors: [.white.opacity(0.35), .clear],
                                      center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: width * 0.45))
            shape.inset(by: width * 0.08).stroke(.white.opacity(0.12), lineWidth: 1)
            shape.stroke(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.1)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        }
        .frame(width: width, height: height)
    }

    static func darker(_ c: Color) -> Color {
        let u = UIColor(c)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s * 1.1), brightness: b * 0.45)
    }
}

/// The decorations on top of a platform, per terrain (some gently animated).
private struct PlatformDetails: View {
    let terrain: BattlePlatform.Terrain
    let width: CGFloat
    let height: CGFloat

    /// A point on an ellipse `k` of the way out from the centre, at angle `deg` (0 = right, 90 = front).
    private func rim(_ deg: Double, _ k: CGFloat = 0.92) -> CGSize {
        let t = deg * .pi / 180
        return CGSize(width: CGFloat(cos(t)) * width / 2 * k, height: CGFloat(sin(t)) * height / 2 * k)
    }

    var body: some View {
        switch terrain {
        case .forest, .plain: grass
        case .water: water
        case .ice: ice
        case .fire: fire
        case .rocky: rocks(sandy: false)
        case .sand: sand
        case .steel: steel
        case .cave: cave
        case .sky: sky
        case .electric: electric
        case .pink: flowers
        }
    }

    // Grass: tufts all round the rim (taller at the back), plus a few flowers
    private var grass: some View {
        let lush = terrain == .forest
        let angles: [Double] = [190, 215, 240, 265, 290, 315, 340, 5, 30, 150, 170, 60, 120]
        return ZStack {
            ForEach(Array(angles.enumerated()), id: \.offset) { i, a in
                let back = a > 180 || a < 0
                let o = rim(a, 0.93)
                GrassTuft()
                    .fill(Color(hex: i.isMultiple(of: 2) ? (lush ? 0x6BDB5F : 0x9BD88A) : (lush ? 0x3FA23C : 0x6FB463)))
                    .frame(width: width * 0.075, height: height * (back ? 0.62 : 0.42))
                    .offset(x: o.width, y: o.height - height * (back ? 0.22 : 0.12))
            }
            if lush {
                ForEach(0..<4, id: \.self) { i in
                    let o = rim([200, 300, 20, 140][i], 0.55)
                    Circle().fill(Color(hex: [0xFFF2A0, 0xFFFFFF, 0xFFB8D8, 0xFFF2A0][i]))
                        .frame(width: 5, height: 5)
                        .offset(o)
                }
            }
        }
    }

    // Water: rings rippling outwards, glints and a lily pad
    private var water: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = (t / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Ellipse().stroke(.white.opacity(0.45 * (1 - p)), lineWidth: 1.5)
                        .frame(width: width * CGFloat(0.15 + 0.75 * p), height: height * CGFloat(0.15 + 0.75 * p))
                }
                LilyPad().fill(Color(hex: 0x4FBF5A).opacity(0.9))
                    .frame(width: width * 0.11, height: height * 0.32)
                    .offset(rim(210, 0.6))
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white.opacity(0.5 + 0.5 * sin(t * 2 + Double(i) * 2)))
                        .offset(rim([250, 330, 40][i], 0.7))
                }
            }
        }
    }

    // Ice: crystal shards round the back rim, frosty sparkles
    private var ice: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let a = [195.0, 225, 255, 290, 320, 345][i]
                Crystal().fill(LinearGradient(colors: [.white, Color(hex: 0xA8E6FF)], startPoint: .top, endPoint: .bottom))
                    .overlay(Crystal().stroke(.white.opacity(0.8), lineWidth: 0.8))
                    .frame(width: width * 0.04, height: height * [0.7, 0.5, 0.85, 0.6, 0.75, 0.45][i])
                    .offset(x: rim(a).width, y: rim(a).height - height * 0.25)
            }
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: "sparkle").font(.system(size: 9, weight: .black)).foregroundStyle(.white.opacity(0.85))
                    .offset(rim([150, 30, 100, 70][i], 0.6))
            }
        }
    }

    // Fire: glowing lava cracks and embers floating up
    private var fire: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                LavaCracks().stroke(Color(hex: 0xFFB13A), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: width * 0.7, height: height * 0.6)
                    .shadow(color: Color(hex: 0xFF5A2A), radius: 4)
                    .opacity(0.75 + 0.25 * sin(t * 3))
                ForEach(0..<7, id: \.self) { i in
                    let p = (t / 2.2 + Double(i) / 7).truncatingRemainder(dividingBy: 1)
                    let o = rim(Double(i) * 51, 0.7)
                    Circle().fill(Color(hex: i.isMultiple(of: 2) ? 0xFFC54A : 0xFF6A2A))
                        .frame(width: 4, height: 4).blur(radius: 0.5)
                        .offset(x: o.width + CGFloat(sin(t * 3 + Double(i))) * 3, y: o.height - CGFloat(p) * height * 1.4)
                        .opacity(1 - p)
                }
            }
        }
    }

    // Rocks: shaded boulders round the rim and gravel
    private func rocks(sandy: Bool) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let a = [200.0, 240, 300, 335, 20, 160][i]
                let sz = [0.09, 0.06, 0.1, 0.07, 0.05, 0.065][i]
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0xD8C8B0), Color(hex: 0x7A6650)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Ellipse().stroke(.black.opacity(0.25), lineWidth: 0.8))
                    .frame(width: width * sz, height: width * sz * 0.7)
                    .offset(x: rim(a).width, y: rim(a).height - width * sz * 0.2)
            }
            ForEach(0..<8, id: \.self) { i in
                Circle().fill(.white.opacity(0.3)).frame(width: 3, height: 3)
                    .offset(rim(Double(i) * 45 + 20, 0.45))
            }
        }
    }

    // Sand: wind-blown dune lines and a couple of pebbles
    private var sand: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                DuneLine().stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: width * [0.5, 0.38, 0.28][i], height: height * 0.12)
                    .offset(y: height * CGFloat([-0.15, 0.05, 0.22][i]))
            }
            rocks(sandy: true).opacity(0.6).scaleEffect(0.8)
        }
    }

    // Steel: a plated ring with rivets
    private var steel: some View {
        ZStack {
            Ellipse().stroke(.white.opacity(0.35), lineWidth: 2)
                .frame(width: width * 0.62, height: height * 0.62)
            ForEach(0..<10, id: \.self) { i in
                Circle().fill(LinearGradient(colors: [.white, Color(hex: 0x8090A0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 4)
                    .offset(rim(Double(i) * 36, 0.82))
            }
        }
    }

    // Cave: purple crystals and floating motes
    private var cave: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let a = [205.0, 250, 310, 340][i]
                    Crystal().fill(LinearGradient(colors: [Color(hex: 0xE0C8FF), Color(hex: 0x7A48C8)], startPoint: .top, endPoint: .bottom))
                        .frame(width: width * 0.045, height: height * [0.6, 0.8, 0.55, 0.7][i])
                        .offset(x: rim(a).width, y: rim(a).height - height * 0.25)
                        .shadow(color: Color(hex: 0xB080FF), radius: 3)
                }
                ForEach(0..<5, id: \.self) { i in
                    let o = rim(Double(i) * 72 + 30, 0.55)
                    Circle().fill(Color(hex: 0xD8B8FF))
                        .frame(width: 4, height: 4).blur(radius: 0.5)
                        .offset(x: o.width, y: o.height - CGFloat(4 + 4 * sin(t * 1.5 + Double(i))))
                        .opacity(0.5 + 0.5 * sin(t * 2 + Double(i)))
                }
            }
        }
    }

    // Sky: puffy clouds round the rim
    private var sky: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                CloudPuff()
                    .frame(width: width * [0.22, 0.16, 0.2, 0.14][i], height: height * 0.4)
                    .offset(rim([200, 330, 20, 150][i], 0.85))
            }
        }
    }

    // Electric: glowing zig-zags and flickering sparks
    private var electric: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    ZigZag().stroke(Color(hex: 0xFFF2A0), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: width * 0.12, height: height * 0.3)
                        .shadow(color: Color(hex: 0xFFD83A), radius: 4)
                        .offset(rim([210, 330, 80][i], 0.62))
                        .opacity(sin(t * 7 + Double(i) * 2.1) > -0.3 ? 1 : 0.2)
                }
            }
        }
    }

    // Fairy: little flowers dotted round
    private var flowers: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Flower(petal: Color(hex: [0xFFFFFF, 0xFFD0E8, 0xFFFFFF, 0xFFE8A0, 0xFFD0E8, 0xFFFFFF][i]))
                    .frame(width: 10, height: 10)
                    .offset(rim(Double(i) * 60 + 15, 0.72))
            }
        }
    }
}

private struct Crystal: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
            p.closeSubpath()
        }
    }
}

private struct LilyPad: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            let c = CGPoint(x: r.midX, y: r.midY)
            p.move(to: c)
            for deg in stride(from: 20.0, through: 340.0, by: 10.0) {
                let t = deg * .pi / 180
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(t)) * r.width / 2, y: c.y + CGFloat(sin(t)) * r.height / 2))
            }
            p.closeSubpath()
        }
    }
}

private struct LavaCracks: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
            p.move(to: pt(0.1, 0.5)); p.addLine(to: pt(0.3, 0.4)); p.addLine(to: pt(0.45, 0.55)); p.addLine(to: pt(0.62, 0.42))
            p.addLine(to: pt(0.85, 0.5))
            p.move(to: pt(0.45, 0.55)); p.addLine(to: pt(0.5, 0.85))
            p.move(to: pt(0.3, 0.4)); p.addLine(to: pt(0.25, 0.15))
            p.move(to: pt(0.62, 0.42)); p.addLine(to: pt(0.72, 0.18))
        }
    }
}

private struct DuneLine: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY), control1: CGPoint(x: r.minX + r.width * 0.3, y: r.minY),
                       control2: CGPoint(x: r.minX + r.width * 0.7, y: r.maxY + r.height))
        }
    }
}

private struct ZigZag: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.55, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY - r.height * 0.2))
        }
    }
}

private struct CloudPuff: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Circle().frame(width: h * 0.8, height: h * 0.8).offset(x: -w * 0.25, y: h * 0.1)
                Circle().frame(width: h, height: h)
                Circle().frame(width: h * 0.75, height: h * 0.75).offset(x: w * 0.27, y: h * 0.12)
            }
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: w, height: h)
        }
    }
}

private struct Flower: View {
    let petal: Color
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(petal).frame(width: 4.5, height: 4.5)
                    .offset(x: CGFloat(cos(Double(i) * 1.2566)) * 3, y: CGFloat(sin(Double(i) * 1.2566)) * 3)
            }
            Circle().fill(Color(hex: 0xFFD23A)).frame(width: 3.5, height: 3.5)
        }
    }
}

/// The wild Pokémon button's icon: a clump of tall wild grass.
struct WildGrassIcon: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            GrassTuft().frame(width: 16, height: 20).offset(x: -9, y: 0)
            GrassTuft().frame(width: 16, height: 20).offset(x: 9, y: 0)
            GrassTuft().frame(width: 20, height: 28)
        }
        .frame(width: 34, height: 30, alignment: .bottom)
    }
}

/// Three little blades of grass.
struct GrassTuft: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        for (x, top) in [(0.2, 0.25), (0.5, 0.0), (0.8, 0.3)] {
            p.move(to: CGPoint(x: r.minX + w * (x - 0.15), y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * x, y: r.minY + h * top),
                           control: CGPoint(x: r.minX + w * (x - 0.1), y: r.minY + h * 0.5))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * (x + 0.15), y: r.maxY),
                           control: CGPoint(x: r.minX + w * (x + 0.05), y: r.minY + h * 0.55))
        }
        return p
    }
}
