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

    private var height: CGFloat { width * 0.2 }

    var body: some View {
        ZStack {
            base
            details
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var base: some View {
        let tint = terrain.tint
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(tint.map { .regular.tint($0.opacity(0.45)) } ?? .regular, in: Ellipse())
                .overlay(Ellipse().stroke(.white.opacity(0.22), lineWidth: 1))
        } else {
            Ellipse().fill((tint ?? .white).opacity(tint == nil ? 0.13 : 0.32))
                .background(.ultraThinMaterial, in: Ellipse())
                .overlay(Ellipse().stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }

    @ViewBuilder private var details: some View {
        switch terrain {
        case .water, .ice:
            // ripples (ice: frosty rings + glints)
            ForEach(0..<3, id: \.self) { i in
                Ellipse().stroke(.white.opacity(0.35 - Double(i) * 0.08), lineWidth: 1.5)
                    .frame(width: width * (0.35 + CGFloat(i) * 0.2), height: height * (0.35 + CGFloat(i) * 0.2))
            }
            if terrain == .ice {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "sparkle").font(.system(size: 10, weight: .black)).foregroundStyle(.white.opacity(0.8))
                        .offset(x: width * [-0.28, 0.22, 0.05][i], y: height * [-0.15, 0.1, -0.3][i])
                }
            }
        case .forest:
            // tufts of grass along the back edge
            ForEach(0..<7, id: \.self) { i in
                GrassTuft().fill(Color(hex: i.isMultiple(of: 2) ? 0x5FD35A : 0x3FA23C).opacity(0.85))
                    .frame(width: width * 0.07, height: height * 0.45)
                    .offset(x: width * (-0.36 + CGFloat(i) * 0.12), y: -height * (0.2 + (i.isMultiple(of: 3) ? 0.05 : 0)))
            }
        case .rocky, .sand, .steel:
            // pebbles
            ForEach(0..<5, id: \.self) { i in
                Ellipse().fill(.white.opacity(terrain == .sand ? 0.25 : 0.3))
                    .overlay(Ellipse().stroke(.black.opacity(0.15), lineWidth: 1))
                    .frame(width: width * [0.06, 0.045, 0.07, 0.04, 0.05][i], height: height * [0.22, 0.17, 0.25, 0.15, 0.2][i])
                    .offset(x: width * [-0.33, -0.2, 0.28, 0.36, 0.12][i], y: height * [0.05, -0.2, 0.12, -0.12, 0.25][i])
            }
        case .fire:
            // embers
            ForEach(0..<6, id: \.self) { i in
                Circle().fill(Color(hex: i.isMultiple(of: 2) ? 0xFFB13A : 0xFF5A2A))
                    .frame(width: 5, height: 5).blur(radius: 1)
                    .offset(x: width * [-0.3, -0.12, 0.08, 0.25, 0.36, -0.38][i], y: height * [-0.2, 0.15, -0.25, 0.1, -0.1, 0.05][i])
            }
        case .cave:
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color(hex: 0xC9A8FF).opacity(0.7)).frame(width: 4, height: 4).blur(radius: 0.5)
                    .offset(x: width * [-0.3, 0.1, 0.32, -0.08][i], y: height * [-0.1, 0.2, -0.18, -0.3][i])
            }
        case .sky:
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(.white.opacity(0.4)).frame(width: width * 0.18, height: height * 0.18)
                    .offset(x: width * [-0.25, 0.27][i], y: height * [-0.1, 0.15][i])
            }
        case .electric:
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "bolt.fill").font(.system(size: 11, weight: .black)).foregroundStyle(Color(hex: 0xFFF2A0))
                    .offset(x: width * [-0.3, 0.05, 0.33][i], y: height * [0.05, -0.25, 0.1][i])
            }
        case .pink:
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: "heart.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white.opacity(0.7))
                    .offset(x: width * [-0.32, -0.1, 0.18, 0.34][i], y: height * [-0.1, 0.22, -0.22, 0.08][i])
            }
        case .plain:
            EmptyView()
        }
    }
}

/// Three little blades of grass.
private struct GrassTuft: Shape {
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
