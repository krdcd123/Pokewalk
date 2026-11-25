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
              let (d, resp) = try? await URLSession.shared.data(from: url),
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
           let p2 = await Self.palette("data/tilesets/primary/general/palettes/02.pal"),
           let p3 = await Self.palette("data/tilesets/primary/general/palettes/03.pal") {
            grass = Self.metatile(png, palette: p2, tiles: [2, 3, 3, 2])
            soil = Self.metatile(png, palette: p3, tiles: [0x10C, 0x11C, 0x11C, 0x10C])
            tileSheet = (png, [2: p2, 3: p3])
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

    // MARK: The garden map (Emerald metatiles: 4 bottom-layer tiles + 4 top-layer tiles, palette in the top bits)

    private static let g: [UInt16] = [0x2002, 0x2003, 0x2003, 0x2002]
    private static let metatiles: [Character: [UInt16]] = [
        "g": g + [0, 0, 0, 0],                                  // grass
        "t": g + [0x2006, 0x2007, 0x2016, 0x2416],              // tree crown
        "T": g + [0x200C, 0x200D, 0x201C, 0x201D],              // tree, bottom-left
        "U": g + [0x240D, 0x240C, 0x241D, 0x241C],              // tree, bottom-right
        "f": g + [0x21FC, 0x21FD, 0x21FE, 0x21FF],              // flowers
        "s": [0x310C, 0x311C, 0x311C, 0x310C, 0, 0, 0, 0],      // soft soil
        "h": [0x2010, 0x2011, 0x2020, 0x2021, 0, 0, 0, 0],      // tall grass (patches not dug yet)
    ]
    /// 10×10 metatiles. "1"–"9", "A"–"C" are patches 1–12 (soil if open, tall grass if not).
    static let layout = [
        "tttttttttt",
        "TUTUTUTUTU",
        "ttgfgggftt",
        "TUg1234gTU",
        "ttggggggtt",
        "TUf5678gTU",
        "ttgggggftt",
        "TUg9ABCgTU",
        "tttttttttt",
        "TUTUTUTUTU",
    ]
    static let fieldTiles = 10

    /// Where patch `i` is, in metatiles (its soil square).
    static func plotTile(_ i: Int) -> (x: Int, y: Int) { (3 + i % 4, 3 + 2 * (i / 4)) }

    func field(openPlots: Int) -> UIImage? {
        if let f = fields[openPlots] { return f }
        guard let (png, pals) = tileSheet else { return nil }
        let sheet2 = png.render(palette: pals[2]!, transparentIndex: 255), sheet3 = png.render(palette: pals[3]!, transparentIndex: 255)
        let top2 = png.render(palette: pals[2]!, transparentIndex: 0), top3 = png.render(palette: pals[3]!, transparentIndex: 0)
        let perRow = png.w / 8
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let n = Self.fieldTiles
        let img = UIGraphicsImageRenderer(size: CGSize(width: n * 16, height: n * 16), format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            for (y, row) in Self.layout.enumerated() {
                for (x, ch) in row.enumerated() {
                    var key = ch
                    if let i = "123456789ABC".firstIndex(of: ch) {
                        key = "123456789ABC".distance(from: "123456789ABC".startIndex, to: i) < openPlots ? "s" : "h"
                    }
                    guard let entries = Self.metatiles[key] else { continue }
                    for (k, e) in entries.enumerated() where k < 4 || e != 0 {
                        let idx = Int(e & 0x3FF), pal = Int(e >> 12)
                        let src = k < 4 ? (pal == 3 ? sheet3 : sheet2) : (pal == 3 ? top3 : top2)
                        guard var tile = src.image.cropping(to: CGRect(x: (idx % perRow) * 8, y: (idx / perRow) * 8, width: 8, height: 8))
                        else { continue }
                        if e & 0x400 != 0 || e & 0x800 != 0, let flipped = Self.flip(tile, h: e & 0x400 != 0, v: e & 0x800 != 0) { tile = flipped }
                        let q = k % 4
                        let rect = CGRect(x: x * 16 + (q % 2) * 8, y: y * 16 + (q / 2) * 8, width: 8, height: 8)
                        UIImage(cgImage: tile).draw(in: rect)
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
