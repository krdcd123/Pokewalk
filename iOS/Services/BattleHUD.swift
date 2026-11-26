import UIKit

/// Which game's battle screen to copy: decided by your trainer (Red → Red/Blue, Gold/Kris → Crystal, others → Emerald).
enum BattleGen: String {
    case rby, gsc, rse

    static func of(_ style: TrainerStyle) -> BattleGen {
        switch style.id {
        case "red1": return .rby
        case "gold", "kris": return .gsc
        default: return .rse
        }
    }

    /// The opposing trainer's picture from the same generation's decompilation.
    func trainerPicURL(_ emeraldPic: String) -> URL? {
        switch self {
        case .rse: return nil
        case .gsc:
            let map: [String: String] = [
                "youngster": "youngster", "lass": "lass", "hiker": "hiker", "bug_catcher": "bug_catcher", "swimmer_f": "swimmer_f",
                "black_belt": "blackbelt_t", "psychic_m": "psychic_t", "beauty": "beauty", "cooltrainer_m": "cooltrainer_m",
                "cooltrainer_f": "cooltrainer_f", "expert_m": "gentleman", "dragon_tamer": "clair",
                "leader_roxanne": "brock", "leader_brawly": "chuck", "leader_wattson": "lt_surge", "leader_flannery": "blaine",
                "leader_norman": "whitney", "leader_winona": "falkner", "leader_tate_and_liza": "sabrina",
                "champion_wallace": "champion", "steven": "blue",
            ]
            let name = map[emeraldPic] ?? "red"            // Frontier Brains → Red, the strongest trainer in Gen 2
            return URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/trainers/\(name).png")
        case .rby:
            let map: [String: String] = [
                "youngster": "youngster", "lass": "lass", "hiker": "hiker", "bug_catcher": "bugcatcher", "swimmer_f": "swimmer",
                "black_belt": "blackbelt", "psychic_m": "psychic", "beauty": "beauty", "cooltrainer_m": "cooltrainerm",
                "cooltrainer_f": "cooltrainerf", "expert_m": "gentleman", "dragon_tamer": "lance",
                "leader_roxanne": "brock", "leader_brawly": "bruno", "leader_wattson": "lt.surge", "leader_flannery": "blaine",
                "leader_norman": "giovanni", "leader_winona": "koga", "leader_tate_and_liza": "sabrina",
                "champion_wallace": "rival3", "steven": "lance",
            ]
            let name = map[emeraldPic] ?? "rival3"
            return URL(string: "https://raw.githubusercontent.com/pret/pokered/master/gfx/trainers/\(name).png")
        }
    }

    /// The trainer's overworld sprite (standing, facing you) from the same generation.
    func overworldPath(_ emeraldPic: String) -> (url: URL, colour: UInt32)? {
        switch self {
        case .rse:
            let map: [String: String] = [
                "cooltrainer_m": "man_3", "cooltrainer_f": "woman_5", "dragon_tamer": "man_5", "champion_wallace": "wallace",
            ]
            var path = map[emeraldPic] ?? emeraldPic
            if emeraldPic.hasPrefix("leader_") {
                let who = emeraldPic.dropFirst(7)
                path = "gym_leaders/" + (who == "tate_and_liza" ? "tate" : String(who))
            } else if ["salon_maiden_anabel", "dome_ace_tucker", "palace_maven_spenser", "arena_tycoon_greta",
                       "factory_head_noland", "pike_queen_lucy", "pyramid_king_brandon"].contains(emeraldPic) {
                path = "frontier_brains/" + (emeraldPic.split(separator: "_").last.map(String.init) ?? "")
            }
            return URL(string: "https://raw.githubusercontent.com/pret/pokeemerald/master/graphics/object_events/pics/people/\(path).png").map { ($0, 0) }
        case .gsc, .rby:
            let map: [String: (String, UInt32)] = [
                "youngster": ("youngster", 0x3870E0), "lass": ("lass", 0xE04040), "hiker": ("pokefan_m", 0x9A6A3A),
                "bug_catcher": ("bug_catcher", 0x40A040), "swimmer_f": ("swimmer_girl", 0x3870E0), "black_belt": ("black_belt", 0x9A6A3A),
                "psychic_m": ("youngster", 0xB060C0), "beauty": ("beauty", 0xE060A0), "cooltrainer_m": ("cooltrainer_m", 0x3870E0),
                "cooltrainer_f": ("cooltrainer_f", 0xE04040), "expert_m": ("gentleman", 0x9A6A3A), "dragon_tamer": ("cooltrainer_m", 0x6040C0),
                "leader_roxanne": ("brock", 0x9A6A3A), "leader_brawly": (self == .rby ? "bruno" : "chuck", 0x9A6A3A),
                "leader_wattson": ("surge", 0x40A040), "leader_flannery": ("blaine", 0xE04040),
                "leader_norman": (self == .rby ? "rocket" : "whitney", 0xE060A0), "leader_winona": (self == .rby ? "koga" : "falkner", 0x3870E0),
                "leader_tate_and_liza": ("sabrina", 0xE04040), "champion_wallace": (self == .rby ? "blue" : "lance", 0xE04040),
                "steven": (self == .rby ? "lance" : "blue", 0x3870E0),
            ]
            let e = map[emeraldPic] ?? ("red", 0xE04040)
            return URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/sprites/\(e.0).png").map { ($0, e.1) }
        }
    }

    /// The Game Boy games had a plain white battle background.
    var isGameBoy: Bool { self != .rse }
}

/// The real health boxes, drawn pixel for pixel from the decompilations' graphics and fonts:
/// Emerald's healthbox sprites, HP bar and small font; Crystal's battle font tiles, HP bar and HUD border tiles.
@MainActor
final class BattleHUD {
    static let shared = BattleHUD()

    // MARK: Loading

    private var gba: (opp: IndexedPNG, player: IndexedPNG, hpbar: IndexedPNG, font: IndexedPNG)?
    private var gb: (font: IndexedPNG, extra: IndexedPNG, enemyBorder: IndexedPNG, border: IndexedPNG, exp: IndexedPNG)?

    func load(_ gen: BattleGen) async {
        switch gen {
        case .rse:
            guard gba == nil else { return }
            async let a = PretFiles.data("graphics/battle_interface/healthbox_singles_opponent.png")
            async let b = PretFiles.data("graphics/battle_interface/healthbox_singles_player.png")
            async let c = PretFiles.data("graphics/battle_interface/hpbar.png")
            async let d = PretFiles.data("graphics/fonts/latin_small.png")
            if let o = await a.flatMap(IndexedPNG.init), let p = await b.flatMap(IndexedPNG.init),
               let h = await c.flatMap(IndexedPNG.init), let f = await d.flatMap(IndexedPNG.init) {
                gba = (o, p, h, f)
            }
        case .gsc, .rby:
            guard gb == nil else { return }
            func get(_ path: String) async -> IndexedPNG? {
                let name = "crystal_" + path.replacingOccurrences(of: "/", with: "_")
                let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("sprite-cache/pret", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent(name)
                if let d = try? Data(contentsOf: file) { return IndexedPNG(d) }
                guard let url = URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/" + path),
                      let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                try? d.write(to: file, options: .atomic)
                return IndexedPNG(d)
            }
            if let f = await get("gfx/font/font.png"), let e = await get("gfx/font/font_battle_extra.png"),
               let eb = await get("gfx/battle/enemy_hp_bar_border.png"), let b = await get("gfx/battle/hp_exp_bar_border.png"),
               let x = await get("gfx/battle/expbar.png") {
                gb = (f, e, eb, b, x)
            }
        }
    }

    /// A Game Boy trainer picture (Crystal's carry their colours; Red/Blue's are grey).
    static func gbTrainerPic(_ url: URL) async -> UIImage? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("sprite-cache/pret", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("gbtrainer_" + url.pathComponents.suffix(4).joined(separator: "_"))
        var data = try? Data(contentsOf: file)
        if data == nil, let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
            try? d.write(to: file, options: .atomic); data = d
        }
        guard let data, let png = IndexedPNG(data) else { return nil }
        let pal = png.palette ?? Self.grey(png.depth)
        return png.render(palette: pal, transparentIndex: 255).cropping(CGRect(x: 0, y: 0, width: png.w, height: png.h))
    }

    /// The first (standing, facing down) frame of a trainer's overworld sprite.
    static func overworld(_ pic: String, gen: BattleGen) async -> UIImage? {
        guard let (url, colour) = gen.overworldPath(pic) else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("sprite-cache/pret", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("ow_" + url.pathComponents.suffix(3).joined(separator: "_"))
        var data = try? Data(contentsOf: file)
        if data == nil, let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
            try? d.write(to: file, options: .atomic); data = d
        }
        guard let data, let png = IndexedPNG(data) else { return nil }
        if gen == .rse, let pal = png.palette {
            let fw = png.h >= 32 && png.w % 9 == 0 && png.w / 9 <= 32 ? png.w / 9 : 16
            return png.render(palette: pal, transparentIndex: 0).cropping(CGRect(x: 0, y: 0, width: fw, height: png.h))
        }
        // Game Boy: white is see-through, light grey skin, dark grey the trainer's colour, black outlines
        let maxV = png.depth >= 8 ? 255 : (1 << png.depth) - 1
        let c = (UInt8((colour >> 16) & 0xFF), UInt8((colour >> 8) & 0xFF), UInt8(colour & 0xFF))
        var pal: [(UInt8, UInt8, UInt8)] = []
        for i in 0...maxV {
            let v = Double(i) / Double(max(1, maxV))
            pal.append(v < 0.17 ? (16, 16, 24) : v < 0.5 ? c : (248, 208, 152))
        }
        return png.render(palette: pal, transparentIndex: UInt8(maxV)).cropping(CGRect(x: 0, y: 0, width: min(16, png.w), height: min(16, png.h)))
    }

    private static func grey(_ depth: Int) -> [(UInt8, UInt8, UInt8)] {
        let n = 1 << min(8, depth)
        return (0..<n).map { i in let v = UInt8(i * 255 / max(1, n - 1)); return (v, v, v) }
    }

    // MARK: Drawing

    private struct Canvas {
        let w: Int, h: Int
        var px: [UInt8]
        init(_ w: Int, _ h: Int) { self.w = w; self.h = h; px = [UInt8](repeating: 0, count: w * h * 4) }
        mutating func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let i = (y * w + x) * 4
            px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2; px[i + 3] = 255
        }
        func image() -> UIImage? {
            guard let p = CGDataProvider(data: Data(px) as CFData),
                  let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
            return UIImage(cgImage: cg)
        }
    }

    /// GBA colours are 5 bits per channel.
    private static func gba(_ r: Int, _ g: Int, _ b: Int) -> (UInt8, UInt8, UInt8) { (UInt8(r & 0xF8), UInt8(g & 0xF8), UInt8(b & 0xF8)) }

    func image(_ gen: BattleGen, mon m: BattleMon, hp: Int, player: Bool) -> UIImage? {
        gen == .rse ? emerald(m, hp: hp, player: player) : gameBoy(gen, m, hp: hp, player: player)
    }

    // MARK: Emerald

    private static let smallWidths: [Int] = [
        3, 5, 5, 5, 5, 5, 5, 5, 5, 4, 3, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 4, 3, 4, 4, 5, 5, 5, 6, 5, 5, 5, 5, 5, 5, 8, 7, 8, 3,
        3, 3, 3, 3, 8, 8, 7, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 8, 8, 8, 8, 8, 8, 8, 4, 7, 5, 5, 3, 3,
        3, 3, 3, 3, 3, 3, 3, 3, 5, 3, 3, 3, 3, 3, 3, 4, 3, 3, 3, 3, 3, 3, 3, 5, 3, 8, 8, 8, 8, 1, 2, 3, 4, 5, 6, 7, 5, 7, 7, 3, 3, 3, 3, 3, 3, 3, 3, 3,
        3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 8, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 8, 5, 8, 5, 5, 5, 5, 5, 5,
        5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 8,
        7, 5, 5, 5, 5, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    ]

    /// Emerald's character encoding (charmap.txt).
    private static func emeraldCode(_ c: Character) -> Int {
        switch c {
        case "A"..."Z": return 0xBB + Int(c.asciiValue! - 65)
        case "a"..."z": return 0xD5 + Int(c.asciiValue! - 97)
        case "0"..."9": return 0xA1 + Int(c.asciiValue! - 48)
        case "!": return 0xAB
        case "?": return 0xAC
        case ".": return 0xAD
        case "-": return 0xAE
        case "'", "’": return 0xB4
        case "♂": return 0xB5
        case "♀": return 0xB6
        case "/": return 0xBA
        case "é": return 0x1B
        default: return 0x00
        }
    }

    /// Draws text with the small font; colours: foreground, shadow. Returns the width used.
    @discardableResult
    private func text(_ s: String, x: Int, y: Int, on c: inout Canvas, fg: (UInt8, UInt8, UInt8), shadow: (UInt8, UInt8, UInt8)) -> Int {
        guard let font = gba?.font else { return 0 }
        var cx = x
        for ch in s {
            let code = Self.emeraldCode(ch)
            let gx = (code % 16) * 16, gy = (code / 16) * 16
            let width = Self.smallWidths[min(code, Self.smallWidths.count - 1)]
            for yy in 0..<16 {
                for xx in 0..<min(16, max(8, width)) {
                    let v = font.indices[(gy + yy) * font.w + gx + xx]
                    if v == 1 { c.set(cx + xx, y + yy, fg) } else if v == 2 { c.set(cx + xx, y + yy, shadow) }
                }
            }
            cx += width
        }
        return cx - x
    }

    private func emerald(_ m: BattleMon, hp: Int, player: Bool) -> UIImage? {
        guard let g = gba else { return nil }
        let box = player ? g.player : g.opp
        let rows = player ? 40 : 32
        var c = Canvas(box.w, rows)
        // the box itself, in its own colours (colour 0 is see-through)
        if let pal = box.palette {
            for y in 0..<rows { for x in 0..<box.w {
                let v = box.indices[y * box.w + x]
                if v != 0, Int(v) < pal.count { c.set(x, y, Self.gba(Int(pal[Int(v)].0), Int(pal[Int(v)].1), Int(pal[Int(v)].2))) }
            } }
        }
        let fg = Self.gba(64, 64, 64), shadow = Self.gba(216, 208, 176)
        // Positions measured from Emerald's battle screen, relative to these images
        let nameX = player ? 16 : 8
        let lvX = player ? 72 : 64
        let barOrigin = player ? (24, 16) : (16, 16)
        let w = text(m.name.uppercased(), x: nameX, y: 3, on: &c, fg: fg, shadow: shadow)
        switch m.gender {
        case .male: text("♂", x: nameX + w, y: 3, on: &c, fg: Self.gba(64, 200, 248), shadow: Self.gba(152, 208, 248))
        case .female: text("♀", x: nameX + w, y: 3, on: &c, fg: Self.gba(248, 152, 144), shadow: Self.gba(248, 208, 200))
        default: break
        }
        if m.status != .none {
            text(m.status.short, x: lvX, y: 3, on: &c, fg: Self.gba(216, 104, 88), shadow: shadow)
        } else {
            let lv = String(m.level)
            let x = lvX + 5 * (3 - lv.count)
            // "Lv" is glyph 0x34 in the small font, 8 px wide
            do { let font = g.font
                for yy in 0..<16 { for xx in 0..<8 {
                    let v = font.indices[(48 + yy) * font.w + 64 + xx]
                    if v == 1 { c.set(x + xx, 3 + yy, fg) } else if v == 2 { c.set(x + xx, 3 + yy, shadow) }
                } }
            }
            text(lv, x: x + 8, y: 3, on: &c, fg: fg, shadow: shadow)
        }
        // "HP" label from hpbar.png, then the 48 px bar
        if let pal = g.hpbar.palette {
            for y in 0..<8 { for x in 8..<24 {
                let v = g.hpbar.indices[y * g.hpbar.w + x]
                if v != 0 { c.set(barOrigin.0 + x, barOrigin.1 + y, Self.gba(Int(pal[Int(v)].0), Int(pal[Int(v)].1), Int(pal[Int(v)].2))) }
            } }
        }
        let filled = hp <= 0 ? 0 : max(1, hp * 48 / max(1, m.maxHP))
        let (dark, light): ((UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8)) =
            filled > 24 ? (Self.gba(88, 208, 128), Self.gba(112, 248, 168))
            : filled > 9 ? (Self.gba(200, 168, 8), Self.gba(248, 224, 56))
            : (Self.gba(168, 64, 72), Self.gba(248, 88, 56))
        let outline = Self.gba(80, 104, 88), white = Self.gba(248, 248, 248)
        let bx = barOrigin.0 + 24, by = barOrigin.1
        for x in 0..<48 {
            c.set(bx + x, by + 1, outline)
            c.set(bx + x, by + 2, white)
            c.set(bx + x, by + 3, x < filled ? dark : Self.gba(72, 64, 88))
            c.set(bx + x, by + 4, x < filled ? light : outline)
            c.set(bx + x, by + 5, white)
            c.set(bx + x, by + 6, outline)
        }
        for y in 1...6 { c.set(bx + 48, by + y, y == 1 || y == 6 ? outline : Self.gba(56, 80, 64)) }
        // Your HP as numbers: "cur/max", each right-aligned in 3 digits
        if player {
            func digits(_ n: Int, endX: Int) {
                let s = Array(String(max(0, n)))
                for (i, ch) in s.reversed().enumerated() { text(String(ch), x: endX - 5 * (i + 1), y: 21, on: &c, fg: fg, shadow: shadow) }
            }
            digits(hp, endX: 75)
            text("/", x: 75, y: 21, on: &c, fg: fg, shadow: shadow)
            digits(m.maxHP, endX: 95)
            // Exp bar: 64 px along the bottom (rows 35–36 from x 32), filled by progress through the level
            let expPx = Int((m.expFraction * 64).rounded(.down))
            for x in 0..<expPx {
                c.set(32 + x, 35, Self.gba(72, 200, 248))
                c.set(32 + x, 36, Self.gba(40, 152, 232))
            }
        }
        return c.image()
    }

    // MARK: Crystal / Red & Blue

    private func gameBoy(_ gen: BattleGen, _ m: BattleMon, hp: Int, player: Bool) -> UIImage? {
        guard let g = gb else { return nil }
        let white: (UInt8, UInt8, UInt8) = (255, 255, 255), black: (UInt8, UInt8, UInt8) = (0, 0, 0)
        let filled = hp <= 0 ? 0 : max(1, hp * 48 / max(1, m.maxHP))
        let barColour: (UInt8, UInt8, UInt8) = gen == .rby ? (64, 64, 64)
            : filled >= 24 ? (0, 184, 0) : filled >= 10 ? (248, 168, 0) : (248, 0, 0)
        let light: (UInt8, UInt8, UInt8) = gen == .rby ? (168, 168, 168) : (240, 208, 120)
        // The HUD as a small tile map (8×8 tiles), like the game builds it
        let cols = 10, rows = player ? 5 : 4
        var c = Canvas(cols * 8, rows * 8)
        for i in 0..<(c.w * c.h) { c.px[i * 4] = 0; c.px[i * 4 + 3] = 0 }

        func tile(_ png: IndexedPNG, _ index: Int, at col: Int, _ row: Int, oneBit: Bool = false) {
            let per = png.w / 8
            let tx = (index % per) * 8, ty = (index / per) * 8
            let maxV = png.depth >= 8 ? 255 : (1 << png.depth) - 1
            for y in 0..<8 { for x in 0..<8 {
                guard ty + y < png.h, tx + x < png.w else { continue }
                let raw = Int(png.indices[(ty + y) * png.w + tx + x])
                let v = raw * 255 / max(1, maxV)                // 255 white … 0 black
                let colour: (UInt8, UInt8, UInt8) = v > 212 ? white : v > 127 ? light : v > 42 ? barColour : black
                c.set(col * 8 + x, row * 8 + y, colour)
            } }
        }
        func blank(_ col: Int, _ row: Int) { for y in 0..<8 { for x in 0..<8 { c.set(col * 8 + x, row * 8 + y, white) } } }
        // Game Boy charmap: A=$80 … ; font.png holds $80–$FF
        func code(_ ch: Character) -> Int? {
            switch ch {
            case "A"..."Z": return 0x80 + Int(ch.asciiValue! - 65)
            case "a"..."z": return 0xA0 + Int(ch.asciiValue! - 97)
            case "0"..."9": return 0xF6 + Int(ch.asciiValue! - 48)
            case "♂": return 0xEF
            case "♀": return 0xF5
            case "/": return 0xF3
            case ".": return 0xE8
            case "-": return 0xE3
            case "'": return 0xE0
            case "!": return 0xE7
            case "?": return 0xE6
            default: return nil
            }
        }
        func put(_ s: String, col: Int, row: Int) {
            for (i, ch) in s.enumerated() where col + i < cols {
                if let k = code(ch) { tile(g.font, k - 0x80, at: col + i, row) } else { blank(col + i, row) }
            }
        }
        func hpBar(col: Int, row: Int) {
            tile(g.extra, 0, at: col, row); tile(g.extra, 1, at: col + 1, row)       // "HP:"
            for t in 0..<6 {
                let px = max(0, min(8, filled - t * 8))
                tile(g.extra, 2 + px, at: col + 2 + t, row)                         // $62 empty … $6A full
            }
        }
        // the HUD's white background
        for row in 0..<rows { for col in 0..<cols { blank(col, row) } }

        let name = String(m.name.uppercased().prefix(10))
        let gender = m.gender == .male ? "♂" : m.gender == .female ? "♀" : ""
        if !player {
            // Crystal's enemy HUD at screen tiles (1,0)–(10,3), drawn here from column 0
            put(name, col: 0, row: 0)
            if m.status != .none { put(m.status.short, col: 5, row: 1) }
            else if m.level >= 100 { put(String(m.level), col: 5, row: 1) }
            else { tile(g.enemyBorder, 2, at: 5, 1); put(String(m.level), col: 6, row: 1) }     // <LV> then the level
            if gen == .gsc { put(gender, col: 8, row: 1) }
            hpBar(col: 1, row: 2)
            tile(g.extra, 11, at: 9, 2)                     // bar end
            tile(g.enemyBorder, 1, at: 0, 2)                // left side
            tile(g.border, 1, at: 0, 3)                     // bottom left
            for col in 1...8 { tile(g.border, 3, at: col, 3) }
            tile(g.border, 5, at: 9, 3)                     // bottom right
        } else {
            // Crystal's player HUD at screen tiles (9,7)–(18,11), drawn here from column 0
            put(name, col: 1, row: 0)
            if m.status != .none { put(m.status.short, col: 5, row: 1) }
            else if m.level >= 100 { put(String(m.level), col: 5, row: 1) }
            else { tile(g.enemyBorder, 2, at: 5, 1); put(String(m.level), col: 6, row: 1) }
            if gen == .gsc { put(gender, col: 8, row: 1) }
            hpBar(col: 1, row: 2)
            tile(g.border, 0, at: 9, 2)                     // right side
            let nums = String(format: "%3d/%3d", max(0, hp), m.maxHP)
            put(nums, col: 2, row: 3)
            tile(g.border, 0, at: 9, 3)
            tile(g.enemyBorder, 3, at: 0, 4)                // bottom left ramp
            for col in 1...8 { tile(g.border, 3, at: col, 4) }   // the Exp bar's line along the bottom…
            // …filled from the right, like Gold/Silver/Crystal
            let expPx = Int((m.expFraction * 64).rounded(.down))
            let expColour: (UInt8, UInt8, UInt8) = gen == .rby ? (64, 64, 64) : (32, 144, 248)
            for x in 0..<expPx { c.set(8 + 63 - x, 4 * 8 + 3, expColour); c.set(8 + 63 - x, 4 * 8 + 4, expColour) }
            tile(g.border, 4, at: 9, 4)                     // bottom right
        }
        return c.image()
    }
}
