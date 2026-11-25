import UIKit

/// Battle graphics cut from the original games' sprite sheets (downloaded from the pret decompilation
/// projects on GitHub and cached): the trainer's back sprite with its throwing frames, and the in-battle
/// Poké Balls (closed + open frames).
enum BattleGfx {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sprite-cache/battle", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func data(_ url: URL, name: String) async -> Data? {
        let file = dir.appendingPathComponent(name)
        if let d = try? Data(contentsOf: file) { return d }
        guard let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        return d
    }

    /// The player's back sprite, one image per frame.
    static func trainerBack(_ style: TrainerStyle) async -> [UIImage] {
        guard let d = await data(style.backPicURL, name: "back-\(style.id).png"), var px = Pixels(d) else { return [] }
        switch style.sheet {
        case .gbc(let accent):
            px.clearGameBoyBackground()
            px.fillWhiteSpeckles()
            px.mapGreys(light: 0xF8B888, dark: accent)
        case .gb:
            px.clearGameBoyBackground()
            px.fillWhiteSpeckles()
            px.mapGreys(light: 0xAAAAAA, dark: 0x555555)
        case .gen3:
            break
        }
        if style.isGameBoy { px.dropToBottom() }      // Red's sprite has empty rows under him: sit him on the box
        if case .gen3 = style.sheet {
            if px.alpha(0, 0) == 255 { px.clearColour(px.rgb(0, 0)) }   // no transparency: colour 0 is the background
        }
        return px.frames(height: px.w)
    }

    /// Balls Game Boy trainers throw with their own game's sprite (Crystal's thrown ball, coloured per ball;
    /// Red from Red/Blue/Yellow keeps it black and white). Newer balls use Emerald's.
    private static let gen2Colours: [BallKind: (UInt32, UInt32)] = [
        .poke: (rgb5(31, 19, 24), rgb5(30, 10, 6)),
        .great: (rgb5(8, 12, 31), rgb5(1, 4, 31)),
        .ultra: (rgb5(31, 31, 7), rgb5(31, 16, 1)),
        .master: (rgb5(12, 25, 1), rgb5(5, 14, 0)),
    ]
    private static func rgb5(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> UInt32 {
        ((r * 255 / 31) << 16) | ((g * 255 / 31) << 8) | (b * 255 / 31)
    }

    /// The in-battle ball for this trainer: [closed, open].
    static func ball(_ kind: BallKind, for style: TrainerStyle) async -> [UIImage] {
        if style.isGameBoy {
            let gen1 = { if case .gb = style.sheet { return true }; return false }()
            let colours: (UInt32, UInt32)? = gen1
                ? ([.poke, .great, .ultra, .master, .safari].contains(kind) ? (0xAAAAAA, 0x555555) : nil)
                : gen2Colours[kind]
            if let colours,
               let d = await data(URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/battle_anims/pokeball.png")!,
                                  name: "ball-gen2.png"),
               var px = Pixels(d) {
                px.clearColour((255, 255, 255))           // colour 0 is always see-through on the Game Boy
                px.mapGreys(light: colours.0, dark: colours.1)
                let f = px.frames(height: 16)               // 0 closed, 1 tilted, 2 open
                if f.count >= 3 { return [f[0], f[2]] }
            }
        }
        return await ball(kind)
    }

    /// Emerald's in-battle ball: [closed, open].
    static func ball(_ kind: BallKind) async -> [UIImage] {
        let url = URL(string: "https://raw.githubusercontent.com/pret/pokeemerald/master/graphics/balls/\(kind.rawValue).png")!
        guard let d = await data(url, name: "ball-\(kind.rawValue).png"), var px = Pixels(d) else { return [] }
        // Colour 0 (white) is the background, but the balls also use white inside — so only clear the white
        // that's connected to each frame's edge.
        px.floodClear(from: (255, 255, 255), frameHeight: 16)
        return Array(px.frames(height: 16).prefix(2))
    }
}

/// Tiny RGBA pixel buffer helper (row 0 = top).
private struct Pixels {
    var w: Int, h: Int, p: [UInt8]

    init?(_ data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        w = cg.width; h = cg.height
        p = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { p[(y * w + x) * 4 + 3] }
    func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { let i = (y * w + x) * 4; return (p[i], p[i + 1], p[i + 2]) }

    mutating func clearColour(_ c: (UInt8, UInt8, UInt8)) {
        for i in stride(from: 0, to: p.count, by: 4) where (p[i], p[i + 1], p[i + 2]) == c {
            p[i] = 0; p[i + 1] = 0; p[i + 2] = 0; p[i + 3] = 0
        }
    }

    /// Clears pixels of colour `c` reachable from the edges of each frame.
    mutating func floodClear(from c: (UInt8, UInt8, UInt8), frameHeight: Int? = nil,
                             seedBottom: Bool = true, sideSeedLimit: Int? = nil) {
        let fh = frameHeight ?? h
        func matches(_ x: Int, _ y: Int) -> Bool { let i = (y * w + x) * 4; return p[i + 3] > 0 && (p[i], p[i + 1], p[i + 2]) == c }
        for top in stride(from: 0, to: h, by: fh) {
            let bottom = min(h, top + fh) - 1
            var stack: [(Int, Int)] = []
            for x in 0..<w { stack.append((x, top)); if seedBottom { stack.append((x, bottom)) } }
            for y in top...min(bottom, top + (sideSeedLimit ?? fh) - 1) { stack.append((0, y)); stack.append((w - 1, y)) }
            while let (x, y) = stack.popLast() {
                guard x >= 0, x < w, y >= top, y <= bottom, matches(x, y) else { continue }
                let i = (y * w + x) * 4
                p[i] = 0; p[i + 1] = 0; p[i + 2] = 0; p[i + 3] = 0
                stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
            }
        }
    }

    /// Single white pixels in a dither pattern (e.g. the brim of Kris's hat) read as holes once the
    /// background is gone, so they take the light shade instead.
    mutating func fillWhiteSpeckles() {
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < w, y >= 0, y < h else { return false }
            let i = (y * w + x) * 4; return p[i + 3] > 0 && p[i] >= 250 && p[i + 1] >= 250 && p[i + 2] >= 250
        }
        var seen = Set<Int>()
        for y in 0..<h { for x in 0..<w where isWhite(x, y) && !seen.contains(y * w + x) {
            var comp: [(Int, Int)] = [], stack = [(x, y)]
            seen.insert(y * w + x)
            while let (cx, cy) = stack.popLast() {
                comp.append((cx, cy))
                for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                where isWhite(nx, ny) && !seen.contains(ny * w + nx) {
                    seen.insert(ny * w + nx); stack.append((nx, ny))
                }
            }
            if comp.count <= 2 {
                for (cx, cy) in comp { let i = (cy * w + cx) * 4; p[i] = 170; p[i + 1] = 170; p[i + 2] = 170 }
            }
        } }
    }

    /// Moves the picture down so its lowest drawn row touches the bottom edge.
    mutating func dropToBottom() {
        var last = -1
        for y in 0..<h where (0..<w).contains(where: { alpha($0, y) > 0 }) { last = y }
        let shift = h - 1 - last
        guard last >= 0, shift > 0 else { return }
        let row = w * 4
        for y in stride(from: h - 1, through: 0, by: -1) {
            let dst = y * row
            if y >= shift { for i in 0..<row { p[dst + i] = p[(y - shift) * row + i] } }
            else { for i in 0..<row { p[dst + i] = 0 } }
        }
    }

    /// Colours a 4-shade Game Boy sprite: light and dark shades get these colours (white and black stay).
    mutating func mapGreys(light: UInt32, dark: UInt32) {
        for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
            let c: UInt32
            switch p[i] {
            case 200...: c = 0xF8F8F8
            case 128..<200: c = light
            case 40..<128: c = dark
            default: c = 0x181818
            }
            p[i] = UInt8((c >> 16) & 0xFF); p[i + 1] = UInt8((c >> 8) & 0xFF); p[i + 2] = UInt8(c & 0xFF)
        }
    }

    /// Game Boy back sprites sit on a white background, but the trainer's clothes are white too and run
    /// off the bottom edge (with gaps in the outline), so a plain flood fill eats them. Instead: clear the
    /// white reachable from the top or the right edge, then in each row the white before the first / after the last drawn pixel.
    mutating func clearGameBoyBackground() {
        func isWhite(_ x: Int, _ y: Int) -> Bool { let i = (y * w + x) * 4; return p[i] >= 250 && p[i + 1] >= 250 && p[i + 2] >= 250 }
        func clear(_ x: Int, _ y: Int) { let i = (y * w + x) * 4; p[i] = 0; p[i + 1] = 0; p[i + 2] = 0; p[i + 3] = 0 }
        // seeds: the whole top row and the whole right edge (the trainer faces right, so the gap between
        // their arm and hand opens to the right; the left edge isn't used — the jacket runs into it there)
        var stack: [(Int, Int)] = (0..<w).map { ($0, 0) } + (0..<h).map { (w - 1, $0) }
        while let (x, y) = stack.popLast() {
            guard x >= 0, x < w, y >= 0, y < h, alpha(x, y) > 0, isWhite(x, y) else { continue }
            clear(x, y)
            stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
        }
        for y in 0..<h {
            var x = 0
            while x < w, alpha(x, y) == 0 || isWhite(x, y) { clear(x, y); x += 1 }
            x = w - 1
            while x >= 0, alpha(x, y) == 0 || isWhite(x, y) { clear(x, y); x -= 1 }
        }
        // Background pockets that only open downwards into cleared space (e.g. under Kris's ponytail):
        // spread the clearing up and sideways — never down, which is where the white clothes are.
        var spread: [(Int, Int)] = []
        for y in 0..<h { for x in 0..<w where alpha(x, y) == 0 { spread.append((x, y)) } }
        while let (x, y) = spread.popLast() {
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y - 1)]
            where nx >= 0 && nx < w && ny >= 0 && alpha(nx, ny) > 0 && isWhite(nx, ny) {
                clear(nx, ny); spread.append((nx, ny))
            }
        }
    }

    func frames(height fh: Int) -> [UIImage] {
        guard fh > 0, let provider = CGDataProvider(data: Data(p) as CFData),
              let full = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return [] }
        return stride(from: 0, to: h - fh + 1, by: fh).compactMap { y in
            full.cropping(to: CGRect(x: 0, y: y, width: w, height: fh)).map { UIImage(cgImage: $0) }
        }
    }
}

/// How high above its platform a Pokémon floats in battle (Emerald's gEnemyMonElevation, in GBA pixels).
enum BattleElevation {
    static let table: [Int: Int] = [
        12: 8, 15: 8, 16: 16, 18: 4, 22: 6, 41: 8, 42: 8, 49: 8, 74: 16, 81: 16, 82: 8, 92: 4, 93: 4, 100: 10,
        101: 12, 109: 8, 110: 6, 142: 7, 144: 6, 145: 8, 146: 5, 149: 6, 151: 8, 166: 8, 169: 6, 187: 11, 188: 12,
        189: 9, 193: 8, 200: 8, 201: 8, 207: 6, 249: 6, 250: 6, 251: 15, 267: 8, 269: 10, 278: 16, 279: 8, 284: 10,
        291: 10, 292: 8, 330: 7, 333: 12, 334: 8, 337: 13, 338: 4, 343: 4, 344: 10, 351: 16, 353: 12, 354: 8,
        355: 9, 358: 12, 362: 12, 374: 8, 380: 6, 381: 6, 384: 6, 385: 12, 386: 8,
    ]
    static func pixels(_ speciesID: Int) -> Int { table[speciesID] ?? 0 }
}

/// Where a sprite's visible pixels are inside its canvas (union over all animation frames), in pixels.
struct SpriteBounds {
    var size: CGSize
    var top: CGFloat
    var bottom: CGFloat

    static let fallback = SpriteBounds(size: CGSize(width: 96, height: 96), top: 20, bottom: 84)

    init(size: CGSize, top: CGFloat, bottom: CGFloat) { self.size = size; self.top = top; self.bottom = bottom }

    init?(_ image: UIImage) {
        let frames = image.images ?? [image]
        var minY = Int.max, maxY = -1, W = 0, H = 0
        for f in frames.prefix(40) {
            guard let cg = f.cgImage else { continue }
            let w = cg.width, h = cg.height
            W = max(W, w); H = max(H, h)
            var px = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 16 { minY = min(minY, y); maxY = max(maxY, y); break } }
        }
        guard maxY >= minY, W > 0 else { return nil }
        size = CGSize(width: W, height: H); top = CGFloat(minY); bottom = CGFloat(maxY + 1)
    }
}

// MARK: - Ball-opening effects

extension BattleGfx {
    /// Emerald's ball-opening particles (graphics/battle_anims/sprites/particles.png, 8 frames of 8×8)
    /// coloured with the circle_impact palette like the game does.
    static func ballParticles() async -> [UIImage] {
        guard let d = await data(URL(string: "https://raw.githubusercontent.com/pret/pokeemerald/master/graphics/battle_anims/sprites/particles.png")!,
                                 name: "particles.png"),
              let p = await data(URL(string: "https://raw.githubusercontent.com/pret/pokeemerald/master/graphics/battle_anims/sprites/circle_impact.png")!,
                                 name: "circle_impact.png"),
              let img = IndexedPNG(d), let pal = IndexedPNG(p)?.palette else { return [] }
        return img.render(palette: pal, transparentIndex: 0).framesOf(height: 8)
    }

    /// Crystal's "ball poof" smoke (3 pieces of 16×16) and the Master Ball sparkle (8×8).
    static func gen2Poof(colour: Bool) async -> (smoke: [UIImage], sparkle: UIImage?) {
        guard let d = await data(URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/battle_anims/smoke.png")!,
                                 name: "c_smoke.png"),
              let smoke = IndexedPNG(d) else { return ([], nil) }
        // Game Boy shades 0 (black) … 3 (white, see-through)
        let grey: [UInt32] = [0x484848, 0x9A9A9A, 0xE0E0E0, 0]
        let smokes = smoke.render(palette: grey.map(Self.rgb), transparentIndex: 3).framesOf(height: 16)
        var sparkle: UIImage?
        if let s = await data(URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/battle_anims/speed.png")!,
                              name: "c_speed.png"),
           let sp = IndexedPNG(s) {
            let pal: [UInt32] = colour ? [0x885000, 0xF8B800, 0xFFF0A0, 0] : [0x303030, 0x707070, 0xB8B8B8, 0]
            sparkle = sp.render(palette: pal.map(Self.rgb), transparentIndex: 3).cropping(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return (smokes, sparkle)
    }

    fileprivate static func rgb(_ c: UInt32) -> (UInt8, UInt8, UInt8) {
        (UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF))
    }

    /// Game Boy trainers use their own ball sprite for these (Crystal's, or grey for Red/Blue/Yellow).
    static func usesGameBoyBall(_ kind: BallKind, style: TrainerStyle) -> Bool {
        guard style.isGameBoy else { return false }
        if case .gb = style.sheet { return [.poke, .great, .ultra, .master, .safari].contains(kind) }
        return [.poke, .great, .ultra, .master].contains(kind)
    }
}

/// A tiny decoder for the decomp projects' indexed / greyscale PNGs, keeping the colour *indices*
/// (needed to apply the game's own palettes). Handles 1/2/4/8-bit, colour type 0 or 3, not interlaced.
struct IndexedPNG {
    let w: Int, h: Int
    let indices: [UInt8]
    let palette: [(UInt8, UInt8, UInt8)]?

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count > 33, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 else { return nil }
        var i = 8, idat = [UInt8](), pal: [(UInt8, UInt8, UInt8)]?
        var W = 0, H = 0, depth = 0, ctype = 0
        func u32(_ o: Int) -> Int { Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]) }
        while i + 8 <= b.count {
            let len = u32(i)
            let type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let body = i + 8
            guard body + len <= b.count else { return nil }
            switch type {
            case "IHDR":
                W = u32(body); H = u32(body + 4); depth = Int(b[body + 8]); ctype = Int(b[body + 9])
                guard b[body + 12] == 0, ctype == 0 || ctype == 3 else { return nil }
            case "PLTE":
                pal = stride(from: body, to: body + len - 2, by: 3).map { (b[$0], b[$0 + 1], b[$0 + 2]) }
            case "IDAT":
                idat += b[body..<(body + len)]
            default: break
            }
            i = body + len + 4
        }
        // zlib → raw deflate (drop the 2-byte header and 4-byte checksum)
        guard W > 0, H > 0, idat.count > 6,
              let raw = try? (Data(idat[2..<(idat.count - 4)]) as NSData).decompressed(using: .zlib) as Data
        else { return nil }
        let r = [UInt8](raw)
        let rowBytes = (W * depth + 7) / 8
        guard r.count >= H * (rowBytes + 1) else { return nil }
        var prev = [UInt8](repeating: 0, count: rowBytes)
        var out = [UInt8](repeating: 0, count: W * H)
        let bpp = max(1, depth / 8)
        for y in 0..<H {
            let f = r[y * (rowBytes + 1)]
            var line = Array(r[(y * (rowBytes + 1) + 1)..<((y + 1) * (rowBytes + 1))])
            for x in 0..<rowBytes {
                let a = x >= bpp ? Int(line[x - bpp]) : 0, up = Int(prev[x]), c = x >= bpp ? Int(prev[x - bpp]) : 0
                let v = Int(line[x])
                switch f {
                case 1: line[x] = UInt8((v + a) & 0xFF)
                case 2: line[x] = UInt8((v + up) & 0xFF)
                case 3: line[x] = UInt8((v + (a + up) / 2) & 0xFF)
                case 4:
                    let p = a + up - c, pa = abs(p - a), pb = abs(p - up), pc = abs(p - c)
                    line[x] = UInt8((v + (pa <= pb && pa <= pc ? a : pb <= pc ? up : c)) & 0xFF)
                default: break
                }
            }
            for x in 0..<W {
                let bit = x * depth
                let byte = line[bit / 8]
                let shift = 8 - depth - (bit % 8)
                out[y * W + x] = (byte >> UInt8(shift)) & UInt8((1 << depth) - 1)
            }
            prev = line
        }
        w = W; h = H; indices = out; palette = pal
    }

    struct Rendered {
        let image: CGImage
        func framesOf(height fh: Int) -> [UIImage] {
            stride(from: 0, to: image.height - fh + 1, by: fh).compactMap {
                image.cropping(to: CGRect(x: 0, y: $0, width: image.width, height: fh)).map { UIImage(cgImage: $0) }
            }
        }
        func cropping(_ r: CGRect) -> UIImage? { image.cropping(to: r).map { UIImage(cgImage: $0) } }
    }

    func render(palette pal: [(UInt8, UInt8, UInt8)], transparentIndex: UInt8) -> Rendered {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for (n, ix) in indices.enumerated() where ix != transparentIndex && Int(ix) < pal.count {
            let c = pal[Int(ix)]
            px[n * 4] = c.0; px[n * 4 + 1] = c.1; px[n * 4 + 2] = c.2; px[n * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return Rendered(image: img)
    }
}

// MARK: - Battle Frontier scene

extension BattleGfx {
    /// Emerald's Battle Frontier battle background (the "building" environment with the Frontier palette):
    /// the 240×112 part above the text box, drawn from tiles.png + map.bin like the GBA does.
    @MainActor static func frontierBackground() async -> UIImage? {
        if let cached = frontierBG { return cached }
        guard let tilesData = await PretFiles.data("graphics/battle_environment/building/tiles.png"),
              let tiles = IndexedPNG(tilesData),
              let mapData = await PretFiles.data("graphics/battle_environment/building/map.bin"),
              let pal = await PretFiles.palette("graphics/battle_environment/stadium/battle_frontier.pal") else { return nil }
        let map = [UInt8](mapData)
        let W = 240, H = 112, cols = 32
        let perRow = tiles.w / 8
        var px = [UInt8](repeating: 255, count: W * H * 4)
        for ty in 0..<(H / 8) {
            for tx in 0..<(W / 8) {
                let o = (ty * cols + tx) * 2
                guard o + 1 < map.count else { continue }
                let e = Int(map[o]) | Int(map[o + 1]) << 8
                let t = e & 0x3FF, hf = e & 0x400 != 0, vf = e & 0x800 != 0
                let p = max(0, (e >> 12) - 2)              // loaded at BG palette 2
                for y in 0..<8 {
                    for x in 0..<8 {
                        let sx = hf ? 7 - x : x, sy = vf ? 7 - y : y
                        let ix = (t / perRow) * 8 + sy, iy = (t % perRow) * 8 + sx
                        guard ix < tiles.h, iy < tiles.w else { continue }
                        let c = Int(tiles.indices[ix * tiles.w + iy])
                        let k = min(pal.count - 1, p * 16 + c)
                        let d = ((ty * 8 + y) * W + tx * 8 + x) * 4
                        px[d] = pal[k].0; px[d + 1] = pal[k].1; px[d + 2] = pal[k].2; px[d + 3] = 255
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let img = UIImage(cgImage: cg)
        frontierBG = img
        return img
    }
    @MainActor private static var frontierBG: UIImage?

    /// Where a Pokémon sprite's feet are (so it stands on its platform).
    static func bounds(_ speciesID: Int, kind: SpriteStore.Kind) async -> SpriteBounds? {
        let load = Task.detached { () -> SpriteBounds? in
            guard let u = await SpriteStore.shared.url(kind, speciesID: speciesID), let img = GIFCache.shared.image(at: u) else { return nil }
            return SpriteBounds(img)
        }
        let timeout = Task { try? await Task.sleep(for: .milliseconds(2_500)); load.cancel() }
        defer { timeout.cancel() }
        return await load.value
    }
}
