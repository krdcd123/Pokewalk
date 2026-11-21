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
        if style.id == "gold" || style.id == "kris" {
            // Crystal: 4-shade greyscale; white around the sprite is the background
            // Only seed from the top and the upper sides: the jacket is white too and is cut off at the
            // bottom edge, so filling from there would erase it
            px.floodClear(from: (255, 255, 255), seedBottom: false, sideSeedLimit: px.h * 6 / 10)
            let accent: UInt32 = style.id == "gold" ? 0xFF3A08 : 0x524AFF
            px.recolourGreys(skin: 0xF8B888, accent: accent)
        } else if px.alpha(0, 0) == 255 {
            px.clearColour(px.rgb(0, 0))        // no transparency chunk: palette colour 0 is the background
        }
        return px.frames(height: px.w)
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

    /// Game Boy Color-style colouring of a greyscale sprite.
    mutating func recolourGreys(skin: UInt32, accent: UInt32) {
        for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
            let c: UInt32
            switch p[i] {
            case 200...: c = 0xF8F8F8
            case 128..<200: c = skin
            case 40..<128: c = accent
            default: c = 0x181818
            }
            p[i] = UInt8((c >> 16) & 0xFF); p[i + 1] = UInt8((c >> 8) & 0xFF); p[i + 2] = UInt8(c & 0xFF)
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
