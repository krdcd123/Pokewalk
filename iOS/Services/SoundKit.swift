import Foundation
import AVFoundation
import UIKit

/// Sound effects and music. Every slot has a small original built-in sound; you can swap any of them
/// (and add battle / route music) for your own audio files in Settings › Sounds & music.
@MainActor
final class SoundKit: ObservableObject {
    static let shared = SoundKit()

    enum Effect: String, CaseIterable, Identifiable {
        case select, menuOpen, trainerCard, ballThrow, ballShake, ballCatch
        var id: String { rawValue }
        var title: String {
            switch self {
            case .select: return "Select (button taps)"
            case .menuOpen: return "Menu opens"
            case .trainerCard: return "Trainer card"
            case .ballThrow: return "Ball thrown"
            case .ballShake: return "Ball shakes"
            case .ballCatch: return "Caught!"
            }
        }
    }

    // MARK: Settings

    @Published var effectsOn: Bool = UserDefaults.standard.object(forKey: "sfxOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(effectsOn, forKey: "sfxOn") }
    }
    @Published var routeMusicOn: Bool = UserDefaults.standard.object(forKey: "routeMusicOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(routeMusicOn, forKey: "routeMusicOn"); refreshMusic() }
    }
    @Published var battleMusicOn: Bool = UserDefaults.standard.object(forKey: "battleMusicOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(battleMusicOn, forKey: "battleMusicOn"); refreshMusic() }
    }
    @Published private(set) var revision = 0          // bumps when files change, so Settings refreshes

    // MARK: Files

    nonisolated static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("Route", isDirectory: true),
                                                 withIntermediateDirectories: true)
        return d
    }()
    private static let audioExts = ["mp3", "m4a", "aac", "wav", "caf", "aif", "aiff"]

    private func customFile(named base: String) -> URL? {
        for ext in Self.audioExts {
            let u = Self.dir.appendingPathComponent("\(base).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
    func hasCustom(_ e: Effect) -> Bool { customFile(named: e.rawValue) != nil }
    var battleFile: URL? { customFile(named: "battle") }
    var routeFiles: [URL] {
        let d = Self.dir.appendingPathComponent("Route", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
            .filter { Self.audioExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies a picked file into the app. `slot` is an Effect raw value, "battle", or "route".
    func importFile(_ url: URL, slot: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard Self.audioExts.contains(ext), let data = try? Data(contentsOf: url) else { return }
        let dest: URL
        if slot == "route" {
            dest = Self.dir.appendingPathComponent("Route/\(url.lastPathComponent)")
        } else {
            removeCustom(slot: slot)
            dest = Self.dir.appendingPathComponent("\(slot).\(ext)")
        }
        try? data.write(to: dest, options: .atomic)
        players[slot] = nil
        revision += 1
        refreshMusic(restart: slot == "battle" || slot == "route")
    }

    func removeCustom(slot: String) {
        if slot == "route" {
            for u in routeFiles { try? FileManager.default.removeItem(at: u) }
        } else if let u = customFile(named: slot) {
            try? FileManager.default.removeItem(at: u)
        }
        players[slot] = nil
        revision += 1
        refreshMusic(restart: true)
    }

    // MARK: Effects

    private var players: [String: AVAudioPlayer] = [:]

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ e: Effect) {
        guard effectsOn else { return }
        activateSession()
        if players[e.rawValue] == nil {
            if let u = customFile(named: e.rawValue) {
                players[e.rawValue] = try? AVAudioPlayer(contentsOf: u)
            } else {
                players[e.rawValue] = try? AVAudioPlayer(data: Synth.wav(for: e))
            }
            players[e.rawValue]?.prepareToPlay()
        }
        guard let p = players[e.rawValue] else { return }
        p.volume = 0.7
        p.currentTime = 0
        p.play()
    }

    // MARK: Music

    enum Scene { case none, map, battle }
    private var scene: Scene = .none
    private var music: AVAudioPlayer?
    private var musicDelegate = MusicDelegate()
    private var routeQueue: [URL] = []

    func setScene(_ s: Scene) {
        guard s != scene else { return }
        scene = s
        refreshMusic(restart: true)
    }

    private func refreshMusic(restart: Bool = false) {
        let wanted: Scene = {
            switch scene {
            case .battle: return battleMusicOn && battleFile != nil ? .battle : .none
            case .map: return routeMusicOn && !routeFiles.isEmpty ? .map : .none
            case .none: return .none
            }
        }()
        if wanted == .none { fadeOutMusic(); return }
        if !restart, music?.isPlaying == true { return }
        // Don't talk over the user's own music/podcast on the map.
        if wanted == .map, AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint { fadeOutMusic(); return }
        activateSession()
        let file: URL?
        if wanted == .battle {
            file = battleFile
        } else {
            if routeQueue.isEmpty { routeQueue = routeFiles.shuffled() }
            file = routeQueue.isEmpty ? nil : routeQueue.removeFirst()
        }
        guard let file, let p = try? AVAudioPlayer(contentsOf: file) else { return }
        music?.stop()
        music = p
        p.numberOfLoops = wanted == .battle ? -1 : 0       // route tracks play through, then the next one
        musicDelegate.onFinish = { [weak self] in Task { @MainActor in self?.refreshMusic(restart: true) } }
        p.delegate = musicDelegate
        p.volume = 0
        p.play()
        p.setVolume(wanted == .battle ? 0.55 : 0.4, fadeDuration: 0.8)
    }

    private func fadeOutMusic() {
        guard let m = music else { return }
        m.setVolume(0, fadeDuration: 0.5)
        Task { try? await Task.sleep(for: .milliseconds(550)); if m !== self.music || self.scene == .none || true { m.stop() } }
        music = nil
    }

    func appBecameActive() { refreshMusic() }
    func appWentToBackground() { music?.stop(); music = nil }

    // MARK: Global "select" sound for taps

    private var tapRecognizer: UITapGestureRecognizer?
    private let tapDelegate = TapDelegate()

    func installTapSound() {
        guard tapRecognizer == nil,
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return }
        let r = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        r.cancelsTouchesInView = false
        r.delaysTouchesEnded = false
        r.delegate = tapDelegate
        window.addGestureRecognizer(r)
        tapRecognizer = r
    }

    @objc private func tapped(_ r: UITapGestureRecognizer) {
        guard let window = r.view, let hit = window.hitTest(r.location(in: window), with: nil) else { return }
        // Not for taps on the map itself or while typing
        var v: UIView? = hit
        while let cur = v {
            let name = String(describing: type(of: cur))
            if name.contains("MKMapView") || name.contains("Keyboard") || cur is UITextField || cur is UITextView { return }
            v = cur.superview
        }
        play(.select)
    }
}

private final class MusicDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}

private final class TapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Tiny original chiptune-style blips, generated in code (square waves), used until you add your own files.
private enum Synth {
    static func wav(for e: SoundKit.Effect) -> Data {
        // (frequency Hz, duration s); 0 Hz = rest
        let notes: [(Double, Double)]
        var duty = 0.5, noise = false
        switch e {
        case .select:      notes = [(1568, 0.035), (2093, 0.045)]
        case .menuOpen:    notes = [(784, 0.05), (1047, 0.05), (1319, 0.08)]
        case .trainerCard: notes = [(1047, 0.06), (1319, 0.06), (1568, 0.06), (2093, 0.12)]; duty = 0.25
        case .ballThrow:   notes = (0..<10).map { (1800 - Double($0) * 120, 0.018) }; noise = true
        case .ballShake:   notes = [(220, 0.04), (0, 0.03), (196, 0.05)]
        case .ballCatch:   notes = [(0, 0.05), (2637, 0.04), (0, 0.06), (523, 0.09), (659, 0.09), (784, 0.09), (1047, 0.22)]; duty = 0.25
        }
        let rate = 22_050.0
        var samples: [Int16] = []
        var seed: UInt32 = 12345
        for (f, d) in notes {
            let n = Int(d * rate)
            for i in 0..<n {
                var v = 0.0
                if f > 0 {
                    let phase = (Double(i) * f / rate).truncatingRemainder(dividingBy: 1)
                    v = phase < duty ? 1 : -1
                    if noise { seed = seed &* 1_103_515_245 &+ 12_345; v *= Double(seed >> 16 & 0x7FFF) / 32_768 }
                }
                let env = min(1, Double(n - i) / (rate * 0.01))    // tiny fade-out per note, no clicks
                samples.append(Int16(v * env * 0.28 * 32_767))
            }
        }
        var d = Data()
        func u32(_ x: UInt32) { var y = x.littleEndian; d.append(Data(bytes: &y, count: 4)) }
        func u16(_ x: UInt16) { var y = x.littleEndian; d.append(Data(bytes: &y, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        samples.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}
