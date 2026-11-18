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
        case front, shiny, icons, items, trainers

        var exts: [String] { self == .front || self == .shiny ? ["gif", "png", "webp"] : ["png", "gif"] }

        func remoteURL(id: Int, key: String) -> URL? {
            let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites"
            switch self {
            case .front: return id <= 649 ? URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/\(id).gif") : nil
            case .shiny: return id <= 649 ? URL(string: "\(base)/pokemon/versions/generation-v/black-white/animated/shiny/\(id).gif") : nil
            case .icons: return SharedStore.remoteIconURL(id)
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
        let names = kind == .items ? [key] : candidateNames(id: id, key: key, name: name)
        if let u = find(in: userRoot.appendingPathComponent(kind.rawValue), names: names, exts: kind.exts) { return u }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sprites/\(kind.rawValue)"),
           let u = find(in: bundled, names: names, exts: kind.exts) { return u }
        return find(in: cacheRoot.appendingPathComponent(kind.rawValue), names: [kind == .items ? key : String(id)], exts: kind.exts)
    }

    func url(_ kind: Kind, speciesID id: Int) async -> URL? {
        let sp = Dex.species(id)
        return await url(kind, id: id, key: sp.key, name: sp.name)
    }

    func itemURL(_ key: String) async -> URL? { await url(.items, id: 0, key: key, name: key) }

    enum TrainerPose: String { case walk, head, card }

    /// Your own trainer sprites first (Sprites/trainers/<id>-<pose>.gif/png), then the downloaded battle sprite.
    func trainerURL(_ style: TrainerStyle, _ pose: TrainerPose) async -> URL? {
        let dir = userRoot.appendingPathComponent(Kind.trainers.rawValue)
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sprites/trainers")
        let names = pose == .head ? ["\(style.id)-head", "\(style.id)-walk"] :
                    pose == .walk ? ["\(style.id)-walk"] : ["\(style.id)-card", "\(style.id)"]
        for root in [dir, bundled].compactMap({ $0 }) {
            if let u = find(in: root, names: names, exts: ["gif", "png"]) { return u }
        }
        return await url(.trainers, id: 0, key: style.id, name: style.id)
    }

    /// True if the player supplied a real walking animation (otherwise the UI fakes a walk with a bob).
    func hasWalkAnimation(_ style: TrainerStyle) -> Bool {
        let dir = userRoot.appendingPathComponent(Kind.trainers.rawValue)
        return find(in: dir, names: ["\(style.id)-walk", "\(style.id)-head"], exts: ["gif"]) != nil
    }

    /// Small PNG of the buddy for the Live Activity (it has to fit in ActivityKit's ~4 KB payload).
    func liveActivityImage(speciesID: Int, shiny: Bool) async -> Data? {
        var candidates: [URL] = []
        if let u = await url(shiny ? .shiny : .front, speciesID: speciesID) { candidates.append(u) }
        if let u = await url(.icons, speciesID: speciesID) { candidates.append(u) }
        for u in candidates {
            guard let img = GIFCache.shared.image(at: u), let frame = img.images?.first ?? Optional(img),
                  let cg = frame.cgImage?.croppedToContent() else { continue }
            for side in [64, 48, 40] {
                if let data = cg.scaledPNG(maxSide: side), data.count <= 2_400 { return data }
            }
        }
        return nil
    }

    func url(_ kind: Kind, id: Int, key: String, name: String) async -> URL? {
        if let u = localURL(kind, id: id, key: key, name: name) { return u }
        guard let remote = kind.remoteURL(id: id, key: key) else { return nil }
        let cacheKey = "\(kind.rawValue)/\(kind == .items ? key : String(id))"
        lock.lock()
        if let t = inFlight[cacheKey] { lock.unlock(); return await t.value }
        let ext = remote.pathExtension
        let dest = cacheRoot.appendingPathComponent("\(cacheKey).\(ext)")
        let task = Task<URL?, Never> {
            guard let (data, resp) = try? await URLSession.shared.data(from: remote),
                  (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
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
        .task(id: "\(speciesID)-\(shiny)-\(kind?.rawValue ?? "")") {
            let k = kind ?? (shiny ? .shiny : .front)
            var url = await SpriteStore.shared.url(k, speciesID: speciesID)
            if url == nil && k == .shiny { url = await SpriteStore.shared.url(.front, speciesID: speciesID) }
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
        .task(id: key) {
            guard let url = await SpriteStore.shared.itemURL(key) else { return }
            image = await Task.detached { GIFCache.shared.image(at: url) }.value
        }
    }
}

struct PixelImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
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

/// A trainer sprite: plays your walking GIF if you added one, otherwise bobs the battle sprite as a walk cycle.
struct TrainerSprite: View {
    let style: TrainerStyle
    var pose: SpriteStore.TrainerPose = .walk
    @State private var image: UIImage?
    @State private var step = false

    var body: some View {
        Group {
            if let image {
                PixelImageView(image: image)
                    .offset(y: image.images == nil && pose != .card && step ? -3 : 0)
                    .animation(image.images == nil && pose != .card
                               ? .easeInOut(duration: 0.28).repeatForever(autoreverses: true) : .default, value: step)
            } else {
                ProgressView()
            }
        }
        .onAppear { step = true }
        .task(id: "\(style.id)-\(pose.rawValue)") {
            guard let url = await SpriteStore.shared.trainerURL(style, pose) else { return }
            image = await Task.detached { GIFCache.shared.image(at: url) }.value
        }
    }
}
