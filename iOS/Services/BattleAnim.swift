import SwiftUI
import UIKit

/// Move animations in the style of your trainer's generation: particles are cut from the games' own battle animation
/// graphics (pokeemerald graphics/battle_anims/sprites for Gen 3, pokecrystal gfx/battle_anims for Gen 2, tinted with
/// the move type's colours like the Game Boy Color palettes), moved the way those animations move — contact hits
/// with a lunge and an impact star, projectiles, beams, things raining down, powders, stat auras and healing sparkles.
struct MoveAnim: Equatable {
    enum Kind: Equatable { case contact, projectile, beam, rain, burst, auraUp, auraDown, powder, heal }

    let kind: Kind
    let from: CGPoint          // canvas pixels
    let to: CGPoint
    let particle: UIImage?
    let impact: UIImage?
    let size: CGFloat          // particle size in canvas pixels
    let start: Date
    let duration: Double

    static func == (a: MoveAnim, b: MoveAnim) -> Bool { a.start == b.start }

    static func kind(for m: MoveInfo, targetsSelf: Bool) -> Kind {
        if m.status || (m.power == nil && !MoveData.fixedDamage.contains(m.key)) {
            switch m.cat {
            case 3: return .heal
            case 1, 5: return .powder
            case 2: return (m.targetsUser || m.stats.allSatisfy { $0[1] > 0 }) ? .auraUp : .auraDown
            default: return targetsSelf ? .auraUp : .burst
            }
        }
        if ["earthquake", "magnitude", "fissure", "explosion", "self-destruct", "surf", "eruption"].contains(m.key) { return .burst }
        if ["rock-slide", "thunder", "blizzard", "razor-wind", "sky-attack", "icicle-spear", "petal-dance"].contains(m.key) { return .rain }
        if ["hyper-beam", "solar-beam", "ice-beam", "aurora-beam", "psybeam", "bubble-beam", "signal-beam", "flamethrower",
            "thunderbolt", "water-gun", "hydro-pump", "dragon-breath", "sludge-bomb", "blast-burn", "hydro-cannon",
            "frenzy-plant", "giga-drain", "mega-drain", "absorb", "aeroblast", "zap-cannon"].contains(m.key) { return .beam }
        if ["rock-throw", "rock-tomb", "mud-shot", "mud-slap", "sand-tomb", "bullet-seed", "pin-missile", "spike-cannon",
            "poison-sting", "twineedle", "razor-leaf", "magical-leaf", "shadow-ball", "sludge", "egg-bomb", "barrage",
            "bone-club", "bonemerang", "icy-wind", "powder-snow", "ember", "bubble", "swift", "gust", "twister"].contains(m.key) {
            return .projectile
        }
        return m.physical ? .contact : .projectile
    }
}

@MainActor
enum BattleAnimGfx {
    private static var cache: [String: UIImage] = [:]

    /// Emerald sprite sheet for each type (first frame is used).
    private static let emerald: [PokeType: String] = [
        .fire: "small_ember", .water: "water_orb", .electric: "spark_0", .grass: "razor_leaf", .ice: "ice_chunk",
        .poison: "poison_bubble", .psychic: "pink_orb", .ground: "flying_dirt", .rock: "rocks", .flying: "white_feather",
        .ghost: "shadow_ball", .dragon: "purple_flame", .dark: "black_smoke", .steel: "metal_ball", .bug: "needle",
        .normal: "yellow_star", .fighting: "punch_impact", .fairy: "sparkle_1",
    ]
    /// Crystal sheet per type: (file, frame size).
    private static let crystal: [PokeType: (String, Int)] = [
        .fire: ("fire", 8), .water: ("bubble", 16), .electric: ("charge", 16), .grass: ("plant", 16), .ice: ("ice", 8),
        .poison: ("poison", 8), .psychic: ("psychic", 8), .ground: ("sand", 16), .rock: ("rocks", 16), .flying: ("wind", 8),
        .ghost: ("smoke", 16), .dragon: ("fire", 8), .dark: ("smoke", 16), .steel: ("shine", 16), .bug: ("horn", 16),
        .normal: ("shine", 16), .fighting: ("hit", 16), .fairy: ("shine", 16),
    ]

    static func particle(_ gen: BattleGen, type: PokeType, kind: MoveAnim.Kind) async -> UIImage? {
        switch kind {
        case .powder: return gen == .rse ? await emeraldFrame("poison_powder", tintFor: type) : await crystalFrame("powder", 8, type: type)
        case .auraUp, .auraDown, .heal:
            return gen == .rse ? await emeraldFrame(kind == .heal ? "green_sparkle" : "sparkle_1")
                               : await crystalFrame("shine", 16, type: kind == .heal ? .grass : kind == .auraUp ? .water : .fire)
        default:
            if gen == .rse { return await emeraldFrame(emerald[type] ?? "yellow_star") }
            let c = crystal[type] ?? ("shine", 16)
            return await crystalFrame(c.0, c.1, type: type)
        }
    }

    static func impact(_ gen: BattleGen) async -> UIImage? {
        gen == .rse ? await emeraldFrame("impact") : await crystalFrame("hit", 16, type: .normal)
    }

    private static func emeraldFrame(_ name: String, tintFor: PokeType? = nil) async -> UIImage? {
        let key = "e-" + name
        if let i = cache[key] { return i }
        guard let d = await PretFiles.data("graphics/battle_anims/sprites/\(name).png"), let png = IndexedPNG(d), let pal = png.palette else { return nil }
        let f = min(32, png.w, png.h)
        let img = png.render(palette: pal, transparentIndex: 0).cropping(CGRect(x: 0, y: 0, width: f, height: f))
        cache[key] = img
        return img
    }

    /// A Crystal battle-animation tile, coloured like the GBC palettes: white is see-through, the greys take the type's colours.
    private static func crystalFrame(_ name: String, _ size: Int, type: PokeType) async -> UIImage? {
        let key = "c-\(name)-\(type.rawValue)"
        if let i = cache[key] { return i }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("sprite-cache/pret", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("crystal_anim_\(name).png")
        var data = try? Data(contentsOf: file)
        if data == nil, let url = URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/battle_anims/\(name).png"),
           let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
            try? d.write(to: file, options: .atomic); data = d
        }
        guard let data, let png = IndexedPNG(data) else { return nil }
        let base = type.hex
        func rgb(_ h: UInt32, _ f: Double) -> (UInt8, UInt8, UInt8) {
            let r = Double((h >> 16) & 0xFF), g = Double((h >> 8) & 0xFF), b = Double(h & 0xFF)
            let m: (Double) -> UInt8 = { v in UInt8(max(0, min(255, f >= 1 ? v + (255 - v) * (f - 1) : v * f))) }
            return (m(r), m(g), m(b))
        }
        let maxV = png.depth >= 8 ? 255 : (1 << png.depth) - 1
        // 4 shades: black → dark, dark grey → type colour, light grey → light, white → see-through
        var pal: [(UInt8, UInt8, UInt8)] = []
        for i in 0...maxV {
            let v = Double(i) / Double(max(1, maxV))
            pal.append(v < 0.17 ? rgb(base, 0.35) : v < 0.5 ? rgb(base, 1) : rgb(base, 1.55))
        }
        let s = min(size, png.w, png.h)
        let img = png.render(palette: pal, transparentIndex: UInt8(maxV)).cropping(CGRect(x: 0, y: 0, width: s, height: s))
        cache[key] = img
        return img
    }
}

/// Draws a MoveAnim over the battle scene.
struct MoveAnimLayer: View {
    let anim: MoveAnim
    let s: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            let t = min(1, max(0, tl.date.timeIntervalSince(anim.start) / anim.duration))
            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { i in
                    if let p = particle(i, t: t) {
                        piece(anim.particle, at: p.pos, scale: p.scale, rotation: p.rot, opacity: p.alpha)
                    }
                }
                if anim.kind == .contact || anim.kind == .projectile || anim.kind == .beam || anim.kind == .rain {
                    // the impact star where it lands
                    let it = (t - impactAt) / (1 - impactAt)
                    if it > 0, it < 1 {
                        piece(anim.impact, at: anim.to, scale: 0.7 + it * 0.7, rotation: 0, opacity: 1 - it)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var impactAt: Double { anim.kind == .contact ? 0.35 : 0.65 }

    private var count: Int {
        switch anim.kind {
        case .contact: return anim.particle == nil ? 0 : 4
        case .projectile: return 3
        case .beam: return 10
        case .rain: return 7
        case .burst: return 8
        case .auraUp, .auraDown, .heal: return 7
        case .powder: return 9
        }
    }

    private struct P { var pos: CGPoint; var scale: Double; var rot: Double; var alpha: Double }

    /// Where particle i is at time t (0…1).
    private func particle(_ i: Int, t: Double) -> P? {
        let f = anim.from, to = anim.to
        let r = Double((i * 7919) % 97) / 97            // fixed per-particle randomness
        switch anim.kind {
        case .projectile, .beam:
            let delay = anim.kind == .beam ? Double(i) * 0.045 : Double(i) * 0.12
            let span = anim.kind == .beam ? 0.4 : 0.5
            let u = (t - delay) / span
            guard u > 0, u < 1 else { return nil }
            let arc = anim.kind == .beam ? 0 : 4 * u * (1 - u) * 22
            return P(pos: CGPoint(x: f.x + (to.x - f.x) * u, y: f.y + (to.y - f.y) * u - arc),
                     scale: 0.9, rot: u * 360, alpha: 1)
        case .rain:
            let delay = Double(i) * 0.07
            let u = (t - delay) / 0.45
            guard u > 0, u < 1 else { return nil }
            let x = to.x + (r - 0.5) * 50
            return P(pos: CGPoint(x: x, y: to.y - 90 + 90 * u), scale: 1, rot: 0, alpha: 1)
        case .burst, .contact:
            let start = anim.kind == .contact ? 0.35 : 0.1
            let u = (t - start) / 0.55
            guard u > 0, u < 1 else { return nil }
            let a = Double(i) / Double(count) * 2 * .pi
            let d = 8 + 34 * u
            return P(pos: CGPoint(x: to.x + cos(a) * d, y: to.y + sin(a) * d * 0.7), scale: 1 - u * 0.4, rot: u * 180, alpha: 1 - u)
        case .auraUp, .heal:
            let delay = Double(i) * 0.08
            let u = (t - delay) / 0.55
            guard u > 0, u < 1 else { return nil }
            let x = f.x + (r - 0.5) * 50
            return P(pos: CGPoint(x: x, y: f.y + 24 - 50 * u), scale: 0.8, rot: 0, alpha: u < 0.8 ? 1 : (1 - u) * 5)
        case .auraDown:
            let delay = Double(i) * 0.08
            let u = (t - delay) / 0.55
            guard u > 0, u < 1 else { return nil }
            let x = to.x + (r - 0.5) * 50
            return P(pos: CGPoint(x: x, y: to.y - 30 + 50 * u), scale: 0.8, rot: 0, alpha: u < 0.8 ? 1 : (1 - u) * 5)
        case .powder:
            let delay = Double(i) * 0.06
            let u = (t - delay) / 0.6
            guard u > 0, u < 1 else { return nil }
            let x = to.x + (r - 0.5) * 56 + sin(u * 9 + Double(i)) * 6
            return P(pos: CGPoint(x: x, y: to.y - 50 + 60 * u), scale: 0.8, rot: 0, alpha: 1 - max(0, u - 0.7) * 3)
        }
    }

    @ViewBuilder private func piece(_ img: UIImage?, at p: CGPoint, scale: Double, rotation: Double, opacity: Double) -> some View {
        if let img {
            let w = img.size.width * scale * (anim.size / max(1, img.size.width))
            Image(uiImage: img).interpolation(.none).resizable()
                .frame(width: w * s, height: w * s)
                .rotationEffect(.degrees(rotation))
                .opacity(opacity)
                .position(x: p.x * s, y: p.y * s)
        }
    }
}
