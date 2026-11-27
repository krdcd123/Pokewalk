import UIKit

/// Emerald map graphics drawn from the pret/pokeemerald decompilation (downloaded the first time they're
/// needed and cached — nothing from the game ships in the app). A tileset pair (primary + secondary) turns
/// metatile numbers into 16×16 pictures, the way the game builds its maps.
enum PretFiles {
    static let base = "https://raw.githubusercontent.com/pret/pokeemerald/master/"
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sprite-cache/pret", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func data(_ path: String) async -> Data? {
        let file = dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        if let d = try? Data(contentsOf: file) { return d }
        // "firered/…" paths come from pret/pokefirered
        // "ruby/…" paths come from pret/pokeruby (e.g. the Machoke movers)
        let full = path.hasPrefix("firered/") ? "https://raw.githubusercontent.com/pret/pokefirered/master/" + path.dropFirst(8)
            : path.hasPrefix("ruby/") ? "https://raw.githubusercontent.com/pret/pokeruby/master/" + path.dropFirst(5)
            : base + path
        guard let url = URL(string: full),
              let (d, resp) = try? await URLSession.shared.mirroredData(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        return d
    }

    static func palette(_ path: String) async -> [(UInt8, UInt8, UInt8)]? {
        guard let d = await data(path), let text = String(data: d, encoding: .utf8) else { return nil }
        let rows = text.split(whereSeparator: \.isNewline).dropFirst(3).compactMap { line -> (UInt8, UInt8, UInt8)? in
            let n = line.split(separator: " ").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
            return n.count >= 3 ? (n[0], n[1], n[2]) : nil
        }
        return rows.count >= 16 ? rows : nil
    }

    /// An object sprite (doll, cushion…) with its own palette (or a separate .pal); colour 0 is see-through.
    static func sprite(_ path: String, palette palPath: String? = nil) async -> UIImage? {
        guard let d = await data(path), let png = IndexedPNG(d) else { return nil }
        var pal = png.palette
        if let palPath { pal = await palette(palPath) ?? pal }
        guard let pal else { return nil }
        return png.render(palette: pal, transparentIndex: 0).cropping(CGRect(x: 0, y: 0, width: png.w, height: png.h))
    }

    /// Emerald's Egg.
    static func egg() async -> UIImage? { await sprite("graphics/pokemon/egg/front.png", palette: "graphics/pokemon/egg/normal.pal") }
}

@MainActor
final class PretTileset {
    private let primary: IndexedPNG
    private let secondary: IndexedPNG?
    private let primaryMeta: [UInt16]
    private let secondaryMeta: [UInt16]
    private let palettes: [Int: [(UInt8, UInt8, UInt8)]]
    private var sheets: [String: CGImage] = [:]
    private var cache: [String: UIImage] = [:]

    private init(primary: IndexedPNG, secondary: IndexedPNG?, primaryMeta: [UInt16], secondaryMeta: [UInt16],
                 palettes: [Int: [(UInt8, UInt8, UInt8)]]) {
        self.primary = primary; self.secondary = secondary
        self.primaryMeta = primaryMeta; self.secondaryMeta = secondaryMeta; self.palettes = palettes
    }

    private static func words(_ d: Data) -> [UInt16] {
        let b = [UInt8](d)
        return stride(from: 0, to: b.count - 1, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }
    }

    /// `primary` e.g. "data/tilesets/primary/general"; `secondary` metatiles folder and its tiles/palettes folder.
    static func load(primary p: String, secondaryMeta s: String? = nil, secondaryGfx g: String? = nil) async -> PretTileset? {
        guard let pt = await PretFiles.data(p + "/tiles.png").flatMap(IndexedPNG.init),
              let pm = await PretFiles.data(p + "/metatiles.bin") else { return nil }
        var pals: [Int: [(UInt8, UInt8, UInt8)]] = [:]
        for n in 0..<6 { if let pal = await PretFiles.palette(p + String(format: "/palettes/%02d.pal", n)) { pals[n] = pal } }
        var st: IndexedPNG?
        var sm = Data()
        if let s, let g {
            st = await PretFiles.data(g + "/tiles.png").flatMap(IndexedPNG.init)
            sm = await PretFiles.data(s + "/metatiles.bin") ?? Data()
            for n in 6..<13 { if let pal = await PretFiles.palette(g + String(format: "/palettes/%02d.pal", n)) { pals[n] = pal } }
        }
        return PretTileset(primary: pt, secondary: st, primaryMeta: words(pm), secondaryMeta: words(sm), palettes: pals)
    }

    private func sheet(secondary sec: Bool, palette: Int, top: Bool) -> CGImage? {
        let key = "\(sec)-\(palette)-\(top)"
        if let s = sheets[key] { return s }
        guard let png = sec ? secondary : primary, let pal = palettes[palette] else { return nil }
        let img = png.render(palette: pal, transparentIndex: top ? 0 : 255).image
        sheets[key] = img
        return img
    }

    private func tile(_ e: UInt16, top: Bool) -> CGImage? {
        let idx = Int(e & 0x3FF)
        let sec = idx >= 512
        let i = sec ? idx - 512 : idx
        guard let png = sec ? secondary : primary,
              let sheet = sheet(secondary: sec, palette: Int(e >> 12), top: top) else { return nil }
        let perRow = png.w / 8
        guard var t = sheet.cropping(to: CGRect(x: (i % perRow) * 8, y: (i / perRow) * 8, width: 8, height: 8)) else { return nil }
        if e & 0xC00 != 0, let f = Self.flip(t, h: e & 0x400 != 0, v: e & 0x800 != 0) { t = f }
        return t
    }

    private func entries(_ id: Int) -> [UInt16]? {
        let sec = id >= 512
        let list = sec ? secondaryMeta : primaryMeta
        let i = (sec ? id - 512 : id) * 8
        guard i + 8 <= list.count else { return nil }
        return Array(list[i..<(i + 8)])
    }

    /// Draws metatile `id` into the current context at (x, y). `topOnly` draws just the upper layer
    /// (decorations sit on whatever floor is already there).
    private func draw(_ id: Int, at x: Int, _ y: Int, topOnly: Bool) {
        guard let e = entries(id) else { return }
        for k in 0..<8 {
            if topOnly && k < 4 { continue }
            if k >= 4 && (e[k] & 0x3FF) == 0 { continue }
            guard let t = tile(e[k], top: k >= 4) else { continue }
            let q = k % 4
            UIImage(cgImage: t).draw(in: CGRect(x: x + (q % 2) * 8, y: y + (q / 2) * 8, width: 8, height: 8))
        }
    }

    private static let fmt: UIGraphicsImageRendererFormat = { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()

    /// A whole map: rows of metatile numbers.
    func compose(_ grid: [[Int]]) -> UIImage {
        let w = (grid.map(\.count).max() ?? 0) * 16, h = grid.count * 16
        return UIGraphicsImageRenderer(size: CGSize(width: max(1, w), height: max(1, h)), format: Self.fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            for (y, row) in grid.enumerated() { for (x, id) in row.enumerated() { draw(id, at: x * 16, y * 16, topOnly: false) } }
        }
    }

    /// A decoration from its metatiles (top layers only, w×h).
    func decoration(_ tiles: [Int], w: Int, h: Int) -> UIImage {
        let key = tiles.map(String.init).joined(separator: ",")
        if let c = cache[key] { return c }
        let img = UIGraphicsImageRenderer(size: CGSize(width: w * 16, height: h * 16), format: Self.fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            for (i, id) in tiles.enumerated() { draw(id, at: (i % w) * 16, (i / w) * 16, topOnly: true) }
        }
        cache[key] = img
        return img
    }

    private static func flip(_ img: CGImage, h: Bool, v: Bool) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.translateBy(x: h ? CGFloat(img.width) : 0, y: v ? CGFloat(img.height) : 0)
        ctx.scaleBy(x: h ? -1 : 1, y: v ? -1 : 1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }
}

/// The ranch's graphics: the outdoors (Emerald's general tileset) and the house (Secret Base tilesets).
@MainActor
final class RanchGfx: ObservableObject {
    static let shared = RanchGfx()
    @Published private(set) var outdoors: PretTileset?
    @Published private(set) var rooms: [String: PretTileset] = [:]
    @Published private(set) var sprites: [String: UIImage] = [:]
    private var loadingRooms: Set<String> = []

    /// Room styles: Secret Base looks (unlocked by the Workshop).
    static let styles: [(key: String, name: String)] = [
        ("tree", "Treehouse"), ("shrub", "Shrub"), ("brown_cave", "Brown Cave"),
        ("red_cave", "Red Cave"), ("blue_cave", "Blue Cave"), ("yellow_cave", "Yellow Cave"),
    ]

    func loadOutdoors() async {
        guard outdoors == nil else { return }
        outdoors = await PretTileset.load(primary: "data/tilesets/primary/general")
    }

    func loadRoom(_ style: String) async {
        guard rooms[style] == nil, !loadingRooms.contains(style) else { return }
        loadingRooms.insert(style)
        defer { loadingRooms.remove(style) }
        if let t = await PretTileset.load(primary: "data/tilesets/primary/secret_base",
                                          secondaryMeta: "data/tilesets/secondary/secret_base",
                                          secondaryGfx: "data/tilesets/secondary/secret_base/" + style) {
            rooms[style] = t
        }
    }

    func loadSprite(_ path: String) async {
        guard sprites[path] == nil, let img = await PretFiles.sprite(path) else { return }
        sprites[path] = img
    }
}
