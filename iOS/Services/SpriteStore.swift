import SwiftUI
import UIKit
import ImageIO

/// Finds sprites in this order:
///   1. Files app › On My iPhone › PokéWalk › Sprites/<folder>/   (what you drop in or import)
///   2. A "Sprites/<folder>" directory bundled into the app at build time
///   3. A cached download from PokeAPI's sprite repo
/// Accepted file names: 25.gif, 025.gif, pikachu.gif, mrmime.gif / mr-mime.gif (Showdown style), etc.
final class SpriteStore {
    static let shared = SpriteStore()

    enum Kind: String, CaseIterable {
        case front, shiny, back, backShiny, icons, iconsShiny, items, trainers

        var exts: [String] { [.front, .shiny, .back, .backShiny].contains(self) ? ["gif", "png", "webp"] : ["png", "gif"] }

        /// Items and trainers are cached by name; Pokémon by Pokédex number.
        var keyedByName: Bool { self == .items || self == .trainers }

        func remoteURL(id: Int, key: String) -> URL? {
            let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites"
            switch self {
            case .front: return id <= 649 ? URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/\(id).gif") : nil
            case .shiny: return id <= 649 ? URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/shiny/\(id).gif") : nil
            case .back: return id <= 649 ? URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/back/\(id).gif") : nil
            case .backShiny: return id <= 649 ? URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/back/shiny/\(id).gif") : nil
            // Box icons (regular + shiny, same style) from PokeSprite
            case .icons: return URL(string: "https://raw.githubusercontent.com/msikma/pokesprite/master/pokemon-gen8/regular/\(key).png")
            case .iconsShiny: return URL(string: "https://raw.githubusercontent.com/msikma/pokesprite/master/pokemon-gen8/shiny/\(key).png")
            case .items: return URL(string: "\(base)/items/\(key).png")
            case .trainers: return TrainerStyle.all.first { $0.id == key }?.remoteSpriteURL
            }
        }
    }

    let userRoot: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Sprites", isDirectory: true)
    }()

    private let cacheRoot: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sprite-cache", isDirectory: true)

    private var inFlight: [String: Task<URL?, Never>] = [:]
    private let lock = NSLock()

    init() {
        // One-time: box icons switched to the PokeSprite set (which has shiny versions) — drop the old ones
        if !UserDefaults.standard.bool(forKey: "iconsV3") {
            UserDefaults.standard.set(true, forKey: "iconsV3")
            try? FileManager.default.removeItem(at: cacheRoot.appendingPathComponent(Kind.icons.rawValue))
            try? FileManager.default.removeItem(at: cacheRoot.appendingPathComponent(Kind.iconsShiny.rawValue))
        }
        for k in Kind.allCases {
            try? FileManager.default.createDirectory(at: userRoot.appendingPathComponent(k.rawValue), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: cacheRoot.appendingPathComponent(k.rawValue), withIntermediateDirectories: true)
        }
        let readme = userRoot.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? """
            Put your sprites here (or use Settings › Sprites › Import folder in the app).
              front/  animated Gen 5 sprites  (25.gif, 025.gif or pikachu.gif)
              shiny/  shiny animated sprites  (same names)
              icons/  party/box icons for the Watch (25.png …)
              items/  item sprites            (poke-ball.png, great-ball.png, rare-candy.png …)
              trainers/ red-walk.gif, red-head.gif, red-card.png (also leaf, gold, kris, brendan, may)
            Anything missing is downloaded from PokeAPI's sprite repo.
            """.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    private func candidateNames(id: Int, key: String, name: String) -> [String] {
        let showdown = name.lowercased()
            .replacingOccurrences(of: "♀", with: "f").replacingOccurrences(of: "♂", with: "m")
            .filter { $0.isLetter || $0.isNumber }
        return Array(NSOrderedSet(array: [String(id), String(format: "%03d", id), String(format: "%04d", id), key,
                                          key.replacingOccurrences(of: "-", with: ""), showdown])) as! [String]
    }

    private func find(in dir: URL, names: [String], exts: [String]) -> URL? {
        for n in names {
            for e in exts {
                let u = dir.appendingPathComponent("\(n).\(e)")
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    /// Synchronous lookup of a local copy (user, bundled or cached). No network.
    func localURL(_ kind: Kind, id: Int, key: String, name: String) -> URL? {
        let names = kind.keyedByName ? [key] : candidateNames(id: id, key: key, name: name)
        if let u = find(in: userRoot.appendingPathComponent(kind.rawValue), names: names, exts: kind.exts) { return u }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sprites/\(kind.rawValue)"),
           let u = find(in: bundled, names: names, exts: kind.exts) { return u }
        return find(in: cacheRoot.appendingPathComponent(kind.rawValue), names: [kind.keyedByName ? key : String(id)], exts: kind.exts)
    }

    func url(_ kind: Kind, speciesID id: Int) async -> URL? {
        let sp = Dex.species(id)
        return await url(kind, id: id, key: sp.key, name: sp.name)
    }

    func itemURL(_ key: String) async -> URL? { await url(.items, id: 0, key: key, name: key) }

    enum TrainerPose: String { case walk, head, card, bike }

    /// Your own trainer file for a pose (Sprites/trainers/<id>-walk.gif, <id>-head.gif, <id>-card.png), if any.
    func userTrainerFile(_ style: TrainerStyle, _ pose: TrainerPose) -> URL? {
        let roots = [userRoot.appendingPathComponent(Kind.trainers.rawValue),
                     Bundle.main.resourceURL?.appendingPathComponent("Sprites/trainers")].compactMap { $0 }
        let names = pose == .head ? ["\(style.id)-head", "\(style.id)-walk"] :
                    pose == .walk ? ["\(style.id)-walk"] : ["\(style.id)-card", "\(style.id)"]
        for root in roots { if let u = find(in: root, names: names, exts: ["gif", "png"]) { return u } }
        return nil
    }

    /// Full trainer sprite for the trainer card (yours, else the battle sprite from Showdown).
    func trainerCardURL(_ style: TrainerStyle) async -> URL? {
        if let u = userTrainerFile(style, .card) { return u }
        return await url(.trainers, id: 0, key: style.id, name: style.id)
    }

    /// The small overworld walking sprite (yours, else built from the original game's sprite sheet).
    /// Riding the bike (shown on the map while you're driving).
    func trainerBike(_ style: TrainerStyle) async -> UIImage? {
        if let u = userTrainerFile(style, .bike) { return GIFCache.shared.image(at: u) }
        let file = cacheRoot.appendingPathComponent("trainers/\(style.id)-bike.png")
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let (data, resp) = try? await URLSession.shared.data(from: style.bikeURL),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return await trainerWalk(style) }
            try? data.write(to: file, options: .atomic)
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Gen 3 bike frames are 32 px wide (walking ones are 16); GBC bike sheets use the walking layout
        if case .gen3 = style.sheet { return OverworldSheet.walkAnimation(from: data, sheet: style.sheet, frameWidth: 32) }
        return OverworldSheet.walkAnimation(from: data, sheet: style.sheet)
    }

    func trainerWalk(_ style: TrainerStyle) async -> UIImage? {
        if let u = userTrainerFile(style, .walk) ?? userTrainerFile(style, .head) { return GIFCache.shared.image(at: u) }
        let file = cacheRoot.appendingPathComponent("trainers/\(style.id)-overworld.png")
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let (data, resp) = try? await URLSession.shared.data(from: style.overworldURL),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? data.write(to: file, options: .atomic)
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return OverworldSheet.walkAnimation(from: data, sheet: style.sheet)
    }

    /// Small PNG of the buddy for the Live Activity (it has to fit in ActivityKit's ~4 KB payload).
    /// Tiny party/box icon for the Dynamic Island.
    func liveActivityIcon(speciesID: Int, shiny: Bool = false) async -> Data? {
        guard let u = await url(shiny ? .iconsShiny : .icons, speciesID: speciesID),
              let img = GIFCache.shared.image(at: u), let frame = img.images?.first ?? Optional(img),
              let cg = frame.cgImage?.croppedToContent() else { return nil }
        for side in [40, 32, 26] {
            if let data = cg.scaledPNG(maxSide: side), data.count <= 1_000 { return data }
        }
        return nil
    }

    func liveActivityImage(speciesID: Int, shiny: Bool) async -> Data? {
        var candidates: [URL] = []
        if let u = await url(shiny ? .shiny : .front, speciesID: speciesID) { candidates.append(u) }
        if let u = await url(.icons, speciesID: speciesID) { candidates.append(u) }
        for u in candidates {
            guard let img = GIFCache.shared.image(at: u), let frame = img.images?.first ?? Optional(img),
                  let cg = frame.cgImage?.croppedToContent() else { continue }
            for side in [64, 48, 40] {
                if let data = cg.scaledPNG(maxSide: side), data.count <= 1_600 { return data }   // ActivityKit caps the whole state at 4 KB
            }
        }
        return nil
    }

    /// Crops a box icon to the Pokémon and adds a thin even margin (no scaling, so pixels stay crisp).
    static func trimIcon(_ data: Data) -> Data? {
        guard let img = UIImage(data: data)?.cgImage, let crop = img.croppedToContent() else { return nil }
        let pad = 2
        let w = crop.width + pad * 2, h = crop.height + pad * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: CGRect(x: pad, y: pad, width: crop.width, height: crop.height))
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out).pngData()
    }

    func url(_ kind: Kind, id: Int, key: String, name: String) async -> URL? {
        if let u = localURL(kind, id: id, key: key, name: name) { return u }
        guard let remote = kind.remoteURL(id: id, key: key) else { return nil }
        let cacheKey = "\(kind.rawValue)/\(kind.keyedByName ? key : String(id))"
        lock.lock()
        if let t = inFlight[cacheKey] { lock.unlock(); return await t.value }
        let ext = remote.pathExtension
        let dest = cacheRoot.appendingPathComponent("\(cacheKey).\(ext)")
        let task = Task<URL?, Never> {
            guard let (raw, resp) = try? await URLSession.shared.data(from: remote),
                  (resp as? HTTPURLResponse)?.statusCode == 200, !raw.isEmpty else { return nil }
            var data = raw
            // PokeSprite box icons sit in a big empty canvas: trim it so they fill their slots like before
            if kind == .icons || kind == .iconsShiny, let trimmed = Self.trimIcon(raw) { data = trimmed }
            try? data.write(to: dest, options: .atomic)
            return dest
        }
        inFlight[cacheKey] = task
        lock.unlock()
        let result = await task.value
        lock.lock(); inFlight[cacheKey] = nil; lock.unlock()
        return result
    }

    /// Copies the party icon into the App Group so the Watch transfer and widgets can use it.
    @discardableResult
    func ensureSharedIcon(_ id: Int) async -> URL? {
        let dest = SharedStore.iconFile(id)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let src = await url(.icons, speciesID: id) else { return nil }
        try? FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    /// Import a folder the player picked in the Files app into Sprites/<kind>.
    func importFolder(_ folder: URL, as kind: Kind) throws -> Int {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let dest = userRoot.appendingPathComponent(kind.rawValue)
        var count = 0
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard kind.exts.contains(file.pathExtension.lowercased()) else { continue }
            let target = dest.appendingPathComponent(file.lastPathComponent.lowercased())
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: file, to: target)
            count += 1
        }
        GIFCache.shared.removeAll()
        if kind == .icons { try? FileManager.default.removeItem(at: SharedStore.iconsDir) }
        return count
    }

    func clearDownloads() {
        try? FileManager.default.removeItem(at: cacheRoot)
        for k in Kind.allCases {
            try? FileManager.default.createDirectory(at: cacheRoot.appendingPathComponent(k.rawValue), withIntermediateDirectories: true)
        }
        GIFCache.shared.removeAll()
    }
}

// MARK: - Animated GIF decoding

final class GIFCache {
    static let shared = GIFCache()
    private let cache = NSCache<NSURL, UIImage>()
    func removeAll() { cache.removeAllObjects() }

    func image(at url: URL) -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        var frames: [UIImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += delay < 0.02 ? 0.1 : delay
        }
        let image: UIImage? = frames.count > 1 ? UIImage.animatedImage(with: frames, duration: duration) : frames.first
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// Crisp, animated pixel sprite (Gen 5 GIFs play their animation).
struct AnimatedSprite: View {
    let speciesID: Int
    var shiny = false
    var kind: SpriteStore.Kind? = nil       // override (e.g. .icons)

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                PixelImageView(image: image)
            } else {
                ProgressView().tint(Theme.inkSoft)
            }
        }
        .spriteHitArea()
        .task(id: "\(speciesID)-\(shiny)-\(kind?.rawValue ?? "")") {
            var k = kind ?? (shiny ? .shiny : .front)
            if k == .icons && shiny { k = .iconsShiny }
            var url = await SpriteStore.shared.url(k, speciesID: speciesID)
            if url == nil && k == .shiny { url = await SpriteStore.shared.url(.front, speciesID: speciesID) }
            if url == nil && k == .backShiny { url = await SpriteStore.shared.url(.back, speciesID: speciesID) }
            if url == nil && (k == .back || k == .backShiny) { url = await SpriteStore.shared.url(shiny ? .shiny : .front, speciesID: speciesID) }
            if url == nil { url = await SpriteStore.shared.url(.icons, speciesID: speciesID) }
            guard let url else { return }
            image = await Task.detached { GIFCache.shared.image(at: url) }.value
        }
    }
}

struct ItemSprite: View {
    let key: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { PixelImageView(image: image) }
            else if let ball = BallKind.allCases.first(where: { $0.itemKey == key }) { BallGlyph(kind: ball) }
            else { Image(systemName: "shippingbox.fill").resizable().scaledToFit().foregroundStyle(Theme.inkSoft) }
        }
        .spriteHitArea()
        .task(id: key) {
            guard let url = await SpriteStore.shared.itemURL(key) else { return }
            image = await Task.detached { GIFCache.shared.image(at: url) }.value
        }
    }
}

extension View {
    /// Sprites are drawn by a UIKit image view; keep it out of hit testing and give SwiftUI a tappable shape instead.
    func spriteHitArea() -> some View {
        self.allowsHitTesting(false).background(Color.white.opacity(0.001)).contentShape(Rectangle())
    }
}

struct PixelImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.isUserInteractionEnabled = false   // never swallow taps meant for the button the sprite sits in
        v.contentMode = .scaleAspectFit
        v.layer.magnificationFilter = .nearest
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image {
            v.image = image
            if image.images != nil { v.startAnimating() }
        }
    }
}


// MARK: - Live Activity image helpers

extension CGImage {
    /// Trims transparent padding around a sprite.
    func croppedToContent() -> CGImage? {
        let w = width, h = height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return self }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let px = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return self }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
            minX = Swift.min(minX, x); maxX = Swift.max(maxX, x); minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return self }
        // The bitmap's first row in memory is the image's top row, matching cropping(to:)'s top-left origin.
        return cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? self
    }

    /// Nearest-neighbour downscale (keeps pixel art crisp) to PNG.
    func scaledPNG(maxSide: Int) -> Data? {
        let scale = Swift.min(1, Double(maxSide) / Double(Swift.max(width, height)))
        let w = Swift.max(1, Int(Double(width) * scale)), h = Swift.max(1, Int(Double(height) * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { r in
            r.cgContext.interpolationQuality = .none
            r.cgContext.translateBy(x: 0, y: CGFloat(h)); r.cgContext.scaleBy(x: 1, y: -1)
            r.cgContext.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return img.pngData()
    }
}

/// A trainer sprite: the small overworld walking animation (.walk / .head) or the full card sprite (.card).
struct TrainerSprite: View {
    let style: TrainerStyle
    var pose: SpriteStore.TrainerPose = .walk
    /// false = standing still (first frame of the walk cycle).
    var animating: Bool = true
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                PixelImageView(image: animating ? image : (image.images?.first ?? image))
            } else { ProgressView() }
        }
        .spriteHitArea()
        .task(id: "\(style.id)-\(pose.rawValue)") {
            image = nil
            if pose == .card {
                guard let url = await SpriteStore.shared.trainerCardURL(style) else { return }
                image = await Task.detached { GIFCache.shared.image(at: url) }.value
            } else if pose == .bike {
                image = await SpriteStore.shared.trainerBike(style)
            } else {
                image = await SpriteStore.shared.trainerWalk(style)
            }
        }
    }
}

/// Cuts the "walking towards you" frames out of the original games' overworld sprite sheets.
enum OverworldSheet {
    static func walkAnimation(from data: Data, sheet: TrainerStyle.Sheet, frameWidth: Int = 16) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))   // row 0 in memory = top of image

        func setRGBA(_ i: Int, _ c: UInt32, _ a: UInt8 = 255) {
            px[i] = UInt8((c >> 16) & 0xFF); px[i + 1] = UInt8((c >> 8) & 0xFF); px[i + 2] = UInt8(c & 0xFF); px[i + 3] = a
        }

        var frameRects: [CGRect] = []
        var flipLast = false
        switch sheet {
        case .gen3:
            let bg = (px[0], px[1], px[2])           // palette colour 0 is the background
            for i in stride(from: 0, to: px.count, by: 4) where (px[i], px[i + 1], px[i + 2]) == bg {
                px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
            }
            // frames: 0 stand-down, 3 & 4 walk-down
            frameRects = [0, 3, 0, 4].map { CGRect(x: $0 * frameWidth, y: 0, width: frameWidth, height: min(32, h)) }
        case .gbc(let accent):
            for i in stride(from: 0, to: px.count, by: 4) {
                switch px[i] {                       // greyscale: 255 white, 170 light, 85 dark, 0 black
                case 200...: px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
                case 128..<200: setRGBA(i, 0xFF9C52)  // skin
                case 40..<128: setRGBA(i, accent)     // clothes (red for Gold, blue for Kris)
                default: setRGBA(i, 0x101010)
                }
            }
            // frames: 0 stand-down, 3 walk-down (the GBC mirrors it for the other step)
            frameRects = [0, 3, 0, 3].map { CGRect(x: 0, y: $0 * 16, width: 16, height: 16) }
            flipLast = true
        }

        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let full = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }

        // Trim the empty margin shared by all frames, so the sprite is centred and fills its frame.
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for r in frameRects {
            for y in Int(r.minY)..<Int(r.maxY) {
                for x in Int(r.minX)..<Int(r.maxX) where px[(y * w + x) * 4 + 3] > 0 {
                    minX = min(minX, x - Int(r.minX)); maxX = max(maxX, x - Int(r.minX))
                    minY = min(minY, y - Int(r.minY)); maxY = max(maxY, y - Int(r.minY))
                }
            }
        }
        if maxX >= minX, maxY >= minY {
            // keep the sprite horizontally symmetric so it doesn't jump when the walk frame mirrors
            let left = min(minX, Int(frameRects[0].width) - 1 - maxX)
            let right = Int(frameRects[0].width) - 1 - left
            frameRects = frameRects.map { CGRect(x: $0.minX + CGFloat(left), y: $0.minY + CGFloat(minY),
                                                width: CGFloat(right - left + 1), height: CGFloat(maxY - minY + 1)) }
        }

        var frames: [UIImage] = []
        for (n, r) in frameRects.enumerated() {
            guard var f = full.cropping(to: r) else { continue }
            if flipLast && n == frameRects.count - 1, let flipped = mirrored(f) { f = flipped }
            frames.append(UIImage(cgImage: f))
        }
        return frames.count > 1 ? UIImage.animatedImage(with: frames, duration: 0.9) : frames.first
    }

    /// Left-right mirror of a frame (drawn into pixels, so animated images keep it).
    private static func mirrored(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8,
                                  bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: CGFloat(img.width), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }
}


/// "Download all sprites": saves every Gen 1–3 Pokémon's animated, shiny and box sprites (plus all
/// trainer sprites) so the app looks complete with no signal. Keeps running if you leave Settings.
@MainActor
final class SpriteDownloader: ObservableObject {
    static let shared = SpriteDownloader()
    @Published private(set) var progress: Double?      // nil = not running
    @Published private(set) var failed = 0
    @Published private(set) var finished = false

    func start() {
        guard progress == nil else { return }
        progress = 0; failed = 0; finished = false
        Task.detached(priority: .utility) {
            var jobs: [(SpriteStore.Kind, Int)] = []
            for id in 1...Dex.count { for k in [SpriteStore.Kind.front, .icons, .iconsShiny, .shiny, .back, .backShiny] { jobs.append((k, id)) } }
            let total = Double(jobs.count + TrainerStyle.all.count)
            var done = 0, bad = 0
            await withTaskGroup(of: Bool.self) { group in
                var next = 0
                while next < min(8, jobs.count) {     // 8 downloads at a time
                    let (k, id) = jobs[next]; next += 1
                    group.addTask { await SpriteStore.shared.url(k, speciesID: id) != nil }
                }
                for await ok in group {
                    done += 1; if !ok { bad += 1 }
                    if next < jobs.count {
                        let (k, id) = jobs[next]; next += 1
                        group.addTask { await SpriteStore.shared.url(k, speciesID: id) != nil }
                    }
                    if done % 12 == 0 {
                        let p = Double(done) / total, b = bad
                        await MainActor.run { self.progress = p; self.failed = b }
                    }
                }
            }
            for style in TrainerStyle.all {
                _ = await SpriteStore.shared.trainerCardURL(style)
                _ = await SpriteStore.shared.trainerWalk(style)
                done += 1
            }
            let b = bad
            await MainActor.run { self.progress = nil; self.failed = b; self.finished = true }
        }
    }
}
