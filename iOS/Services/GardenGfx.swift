import UIKit

/// Emerald's graphics for the Berry Garden, downloaded from the pret/pokeemerald decompilation the first
/// time they're needed (same as the battle graphics — nothing from the game ships inside the app):
/// the grass and soft-soil tiles from the overworld tileset, every berry tree's growth sprites, and the
/// Aroma Lady's trainer picture.
@MainActor
final class GardenGfx: ObservableObject {
    static let shared = GardenGfx()

    @Published private(set) var grass: UIImage?
    @Published private(set) var soil: UIImage?
    /// The whole garden (trees round the edge, flowers, rows of soft soil), drawn once per number of open patches.
    private var fields: [Int: UIImage] = [:]
    private var tileSheet: (png: IndexedPNG, pals: [Int: [(UInt8, UInt8, UInt8)]])?
    @Published private(set) var aromaLady: UIImage?
    @Published private(set) var dirt: UIImage?
    @Published private(set) var sprout: [UIImage] = []
    @Published private(set) var trees: [String: [UIImage]] = [:]      // berry key → 6 frames (16×32)

    private static let base = "https://raw.githubusercontent.com/pret/pokeemerald/master/"
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sprite-cache/garden", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func data(_ path: String) async -> Data? {
        let file = dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        if let d = try? Data(contentsOf: file) { return d }
        guard let url = URL(string: base + path),
              let (d, resp) = try? await URLSession.shared.mirroredData(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        return d
    }

    /// JASC-PAL text → colours.
    private static func palette(_ path: String) async -> [(UInt8, UInt8, UInt8)]? {
        guard let d = await data(path), let text = String(data: d, encoding: .utf8) else { return nil }
        let rows = text.split(whereSeparator: \.isNewline).dropFirst(3).compactMap { line -> (UInt8, UInt8, UInt8)? in
            let n = line.split(separator: " ").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
            return n.count >= 3 ? (n[0], n[1], n[2]) : nil
        }
        return rows.count >= 16 ? rows : nil
    }

    /// Which tree picture each berry uses in Emerald (Qualot shares Wepear's).
    static func treeFile(_ berry: String) -> String {
        let name = berry.replacingOccurrences(of: "-berry", with: "")
        return name == "qualot" ? "wepear" : name
    }

    private var loading = false

    func load() async {
        guard !loading, grass == nil || trees.isEmpty || aromaLady == nil else { return }
        loading = true
        defer { loading = false }

        // Overworld tiles: grass = metatile 0x001, soft soil = metatile 0x10C (general tileset)
        if let d = await Self.data("data/tilesets/primary/general/tiles.png"), let png = IndexedPNG(d),
           let p1 = await Self.palette("data/tilesets/primary/general/palettes/01.pal"),
           let p2 = await Self.palette("data/tilesets/primary/general/palettes/02.pal"),
           let p3 = await Self.palette("data/tilesets/primary/general/palettes/03.pal") {
            grass = Self.metatile(png, palette: p2, tiles: [2, 3, 3, 2])
            soil = Self.metatile(png, palette: p3, tiles: [0x10C, 0x11C, 0x11C, 0x10C])
            tileSheet = (png, [1: p1, 2: p2, 3: p3])
        }
        if let d = await Self.data("graphics/trainers/front_pics/aroma_lady.png"), let png = IndexedPNG(d), let pal = png.palette {
            aromaLady = png.render(palette: pal, transparentIndex: 0).cropping(CGRect(x: 0, y: 0, width: png.w, height: png.h))
        }
        let folder = "graphics/object_events/pics/berry_trees/"
        if let d = await Self.data(folder + "dirt_pile.png"), let png = IndexedPNG(d), let pal = png.palette {
            dirt = png.render(palette: pal, transparentIndex: 0).cropping(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        if let d = await Self.data(folder + "sprout.png"), let png = IndexedPNG(d), let pal = png.palette {
            let r = png.render(palette: pal, transparentIndex: 0)
            sprout = (0..<2).compactMap { r.cropping(CGRect(x: $0 * 16, y: 0, width: 16, height: 16)) }
        }
        var t: [String: [UIImage]] = [:]
        for berry in ItemCatalog.berries {
            guard let d = await Self.data(folder + Self.treeFile(berry) + ".png"), let png = IndexedPNG(d),
                  let pal = png.palette else { continue }
            let r = png.render(palette: pal, transparentIndex: 0)
            t[berry] = (0..<(png.w / 16)).compactMap { r.cropping(CGRect(x: $0 * 16, y: 0, width: 16, height: png.h)) }
        }
        trees = t
    }

    // MARK: The garden map — Route 123's Berry Master garden (fenced, oval soil patches), tidied into a card.
    // Emerald metatiles: 4 bottom-layer + 4 top-layer tiles; tile number in the low 10 bits, flips in bits
    // 10/11, palette in the top 4.

    private static let metatiles: [String: [UInt16]] = [
        "c6": [0x2002, 0x2402, 0x2003, 0x2403, 0x2004, 0x2404, 0x2014, 0x2414],   // forest
        "16": [0x200E, 0x240E, 0x201E, 0x241E, 0, 0, 0, 0],                       // forest edge (trunks)
        "01": [0x2002, 0x2003, 0x2003, 0x2002, 0, 0, 0, 0],                       // grass
        "04": [0x2002, 0x2003, 0x2003, 0x2002, 0x21FC, 0x21FD, 0x21FE, 0x21FF],   // flowers
        "0d": [0x2010, 0x2011, 0x2020, 0x2021, 0, 0, 0, 0],                       // tall grass
        "141": [0x2002, 0x2003, 0x2003, 0x2002, 0, 0x10FF, 0, 0x110F],            // fence corners / sides
        "149": [0x2002, 0x2003, 0x2003, 0x2002, 0x112F, 0x112F, 0x113F, 0x113F],
        "139": [0x2002, 0x2003, 0x2003, 0x2002, 0x10FF, 0, 0x110F, 0],
        "142": [0x2002, 0x2003, 0x2003, 0x2002, 0, 0x110F, 0, 0x110F],
        "140": [0x2002, 0x2003, 0x2003, 0x2002, 0x110F, 0, 0x110F, 0],
        "133": [0x2002, 0x2003, 0x2003, 0x2002, 0, 0x110F, 0, 0x118E],
        "132": [0x2002, 0x2003, 0x2002, 0x2002, 0x110F, 0, 0x118E, 0],
        "273": [0x392B, 0x392C, 0x391B, 0x311C, 0, 0, 0, 0],                      // oval soil patch (2×2)
        "275": [0x30FC, 0x34FB, 0x310C, 0x350B, 0, 0, 0, 0],
        "27b": [0x312B, 0x352C, 0x2003, 0x2002, 0, 0, 0, 0],
        "27d": [0x3CFC, 0x3CFB, 0x2003, 0x2002, 0, 0, 0, 0],
    ]
    /// 12×9 metatiles. "P0"…"P5" are the six oval patches (one plant each); unopened ones are overgrown.
    static let layout: [[String]] = [
        "c6 c6 c6 c6 c6 c6 c6 c6 c6 c6 c6 c6",
        "16 16 16 16 16 16 16 16 16 16 16 16",
        "01 141 149 149 149 149 149 149 149 149 139 01",
        "01 142 P0 P0 01 P1 P1 01 P2 P2 140 01",
        "01 142 P0 P0 01 P1 P1 01 P2 P2 140 01",
        "01 142 P3 P3 01 P4 P4 01 P5 P5 140 01",
        "01 142 P3 P3 01 P4 P4 01 P5 P5 140 01",
        "04 133 149 149 01 01 01 01 149 149 132 04",
        "01 01 04 01 01 01 01 01 01 04 01 01",
    ].map { $0.split(separator: " ").map(String.init) }
    static let fieldWidth = 12, fieldHeight = 9

    /// Top-left metatile of oval patch `j`.
    static func ovalTile(_ j: Int) -> (x: Int, y: Int) { (2 + 3 * (j % 3), 3 + 2 * (j / 3)) }

    private var sheets: [String: IndexedPNG.Rendered] = [:]

    func field(openPlots: Int) -> UIImage? {
        if let f = fields[openPlots] { return f }
        guard let (png, pals) = tileSheet else { return nil }
        func sheet(_ pal: Int, top: Bool) -> IndexedPNG.Rendered? {
            let key = "\(pal)-\(top)"
            if let r = sheets[key] { return r }
            guard let p = pals[pal] else { return nil }
            let r = png.render(palette: p, transparentIndex: top ? 0 : 255)
            sheets[key] = r
            return r
        }
        let perRow = png.w / 8
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let size = CGSize(width: Self.fieldWidth * 16, height: Self.fieldHeight * 16)
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            // which part of each oval a "P" cell is: count P cells seen per oval
            var seen: [Character: Int] = [:]
            for (y, row) in Self.layout.enumerated() {
                for (x, cell) in row.enumerated() {
                    var key = cell
                    if cell.hasPrefix("P"), let j = cell.last, let n = Int(String(j)) {
                        let part = seen[j, default: 0]
                        seen[j] = part + 1
                        key = n < openPlots ? ["273", "275", "27b", "27d"][part % 4] : "0d"
                    }
                    guard let entries = Self.metatiles[key] else { continue }
                    for (k, e) in entries.enumerated() {
                        let idx = Int(e & 0x3FF)
                        if k >= 4 && idx == 0 { continue }
                        guard let src = sheet(Int(e >> 12), top: k >= 4),
                              var tile = src.image.cropping(to: CGRect(x: (idx % perRow) * 8, y: (idx / perRow) * 8, width: 8, height: 8))
                        else { continue }
                        if e & 0xC00 != 0, let f = Self.flip(tile, h: e & 0x400 != 0, v: e & 0x800 != 0) { tile = f }
                        let q = k % 4
                        UIImage(cgImage: tile).draw(in: CGRect(x: x * 16 + (q % 2) * 8, y: y * 16 + (q / 2) * 8, width: 8, height: 8))
                    }
                }
            }
        }
        fields[openPlots] = img
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

    /// Four 8×8 tiles (top-left, top-right, bottom-left, bottom-right) → one 16×16 metatile.
    private static func metatile(_ png: IndexedPNG, palette: [(UInt8, UInt8, UInt8)], tiles: [Int]) -> UIImage? {
        let sheet = png.render(palette: palette, transparentIndex: 255)
        let perRow = png.w / 8
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            for (k, idx) in tiles.enumerated() {
                guard let tile = sheet.cropping(CGRect(x: (idx % perRow) * 8, y: (idx / perRow) * 8, width: 8, height: 8))
                else { continue }
                tile.draw(in: CGRect(x: (k % 2) * 8, y: (k / 2) * 8, width: 8, height: 8))
            }
        }
    }

    /// The sprite for a plot at this stage (`frame` alternates 0/1 for the gentle sway).
    func sprite(berry: String, stage: BerryStage, frame: Int) -> UIImage? {
        let f = frame % 2
        switch stage {
        case .planted: return dirt
        case .sprout: return sprout.isEmpty ? nil : sprout[f % sprout.count]
        case .taller: return trees[berry]?[safe: f]
        case .flowering: return trees[berry]?[safe: 2 + f]
        case .berries: return trees[berry]?[safe: 4 + f]
        }
    }
}
