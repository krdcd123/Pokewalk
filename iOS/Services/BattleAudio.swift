import Foundation
import AVFoundation

/// Battle Frontier sound: trainer battle music streamed from Pokémon Showdown's audio index, move sounds from the
/// Pokémon GO assets (PokeMiners/pogo_assets), and Emerald's own hit and low-HP sounds, rebuilt from the game's
/// sound data (pokeemerald's MIDI + voicegroup: the PSG noise/square channels and the snare sample) at runtime.
/// Nothing is bundled: everything is downloaded once and cached.
@MainActor
final class BattleAudio: ObservableObject {
    static let shared = BattleAudio()

    struct Track: Hashable { let file: String; let title: String }

    /// From https://play.pokemonshowdown.com/audio/
    static let tracks: [String: Track] = [
        "rby": Track(file: "hgss-kanto-trainer", title: "HGSS · Kanto Trainer Battle"),
        "gsc": Track(file: "hgss-johto-trainer", title: "HGSS · Johto Trainer Battle"),
        "rse": Track(file: "oras-trainer", title: "ORAS · Trainer Battle"),
        "leader": Track(file: "bw2-kanto-gym-leader", title: "BW2 · Kanto Gym Leader Battle"),
        "rival": Track(file: "oras-rival", title: "ORAS · Rival Battle"),
        "elite": Track(file: "spl-elite4", title: "Elite Four Battle"),
        "brain": Track(file: "bw-subway-trainer", title: "BW · Subway Trainer Battle"),
    ]

    @Published private(set) var nowPlaying: Track?

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var effects: [AVAudioPlayer] = []
    private var lowHP: AVAudioPlayer?
    private var sfxCache: [String: Data] = [:]

    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("battle-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func session() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: Music

    func startMusic(_ t: Track) {
        stopMusic()
        nowPlaying = t
        guard SoundKit.shared.battleMusicOn else { return }
        session()
        Task {
            // Cache the file so it loops gaplessly and works offline next time
            let url = await cached(URL(string: "https://play.pokemonshowdown.com/audio/\(t.file).mp3")!, name: "\(t.file).mp3")
                ?? URL(string: "https://play.pokemonshowdown.com/audio/\(t.file).mp3")!
            guard nowPlaying == t else { return }
            let item = AVPlayerItem(url: url)
            let q = AVQueuePlayer()
            looper = AVPlayerLooper(player: q, templateItem: item)
            q.volume = Float(SoundKit.shared.battleVolume)
            q.play()
            player = q
        }
    }

    func stopMusic() {
        player?.pause()
        looper = nil
        player = nil
        nowPlaying = nil
        setLowHealth(false)
    }

    // MARK: Effects

    private func play(_ data: Data, volume: Double = 1) {
        guard SoundKit.shared.effectsOn, let p = try? AVAudioPlayer(data: data) else { return }
        session()
        p.volume = Float(SoundKit.shared.effectsVolume * volume)
        p.play()
        effects.removeAll { !$0.isPlaying }
        effects.append(p)
    }

    private func cached(_ url: URL, name: String) async -> URL? {
        let file = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let (d, r) = try? await URLSession.shared.mirroredData(from: url), (r as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        return file
    }

    /// The move's Pokémon GO sound.
    func playMove(_ m: MoveInfo) {
        guard let url = MoveData.soundURL(m), let f = m.sound else { return }
        Task {
            guard let file = await cached(url, name: "move-" + f), let d = try? Data(contentsOf: file) else { return }
            play(d, volume: 0.9)
        }
    }

    func playStat(up: Bool) {
        let f = up ? "se_go_b_att_parameter_up.wav" : "se_go_b_att_parameter_down.wav"
        Task {
            guard let file = await cached(URL(string: "https://raw.githubusercontent.com/PokeMiners/pogo_assets/master/Sounds/Combat/\(f)")!, name: f),
                  let d = try? Data(contentsOf: file) else { return }
            play(d, volume: 0.8)
        }
    }

    /// Emerald's SE_EFFECTIVE / SE_SUPER_EFFECTIVE / SE_NOT_EFFECTIVE.
    func playHit(_ effectiveness: Double) {
        let kind: GBASfx.Kind = effectiveness >= 2 ? .superEffective : effectiveness < 1 ? .notEffective : .effective
        Task {
            guard let d = await sfx(kind) else { return }
            play(d)
        }
    }

    /// Emerald's SE_LOW_HEALTH beeping, looping while your Pokémon's HP bar is red.
    func setLowHealth(_ on: Bool) {
        if !on || !SoundKit.shared.effectsOn { lowHP?.stop(); lowHP = nil; return }
        guard lowHP == nil else { return }
        Task {
            guard let d = await sfx(.lowHealth), lowHP == nil, let p = try? AVAudioPlayer(data: d) else { return }
            session()
            p.numberOfLoops = -1
            p.volume = Float(SoundKit.shared.effectsVolume * 0.7)
            p.play()
            lowHP = p
        }
    }

    private func sfx(_ k: GBASfx.Kind) async -> Data? {
        if let d = sfxCache[k.rawValue] { return d }
        let snare = await PretFiles.data("sound/direct_sound_samples/unknown_synth_snare.wav")
        let d = GBASfx.render(k, snare: snare)
        sfxCache[k.rawValue] = d
        return d
    }
}

// MARK: - Emerald sound effects, synthesised from the game's data

/// pokeemerald plays these from sound/songs/midi/se_*.mid with the rs_sfx_1 voicegroup:
/// program 125/127 = PSG noise (decay 2 / decay 1), program 15 = PSG square (50% duty, decay 6),
/// program 0 = the "unknown_synth_snare" DirectSound sample (ADSR 255, 249, 103, 165).
enum GBASfx {
    enum Kind: String { case effective, superEffective, notEffective, lowHealth }

    private static let rate = 44_100.0
    private static let frame = 1 / 59.7275            // the GBA's frame rate drives the envelopes

    private enum Voice { case noise(decay: Int, release: Int), square(decay: Int, release: Int), snare }
    /// (start tick, end tick, MIDI key, velocity, pitch bend in semitones)
    private typealias Note = (Int, Int, Int, Int, Double)

    static func render(_ k: Kind, snare: Data?) -> Data {
        var tracks: [(Voice, [Note])] = []
        var tick = 0.666666 / 24                       // tempo 666666 µs per beat, 24 ticks per beat
        var songVolume = 110.0
        switch k {
        case .effective:
            tracks = [(.noise(decay: 2, release: 0), [(0, 3, 58, 100, 0), (3, 6, 63, 100, -1.03), (6, 39, 63, 100, 0)]),
                      (.snare, [(0, 3, 60, 127, 0), (3, 21, 60, 127, 0)])]
        case .notEffective:
            tracks = [(.noise(decay: 1, release: 1), [(0, 3, 55, 100, 0), (3, 9, 58, 100, 0)]),
                      (.snare, [(0, 9, 46, 127, 0)])]
        case .superEffective:
            let n: [Note] = [(0, 3, 60, 100, 0), (3, 6, 57, 100, 0), (6, 9, 60, 100, 0), (9, 15, 67, 72, 0), (15, 18, 60, 52, 0),
                             (18, 24, 67, 48, 0), (24, 27, 60, 28, 0), (27, 33, 67, 28, 0), (33, 36, 60, 28, 0), (36, 42, 67, 28, 0),
                             (42, 45, 60, 12, 0), (45, 51, 67, 12, 0)]
            let s: [Note] = [(0, 3, 72, 127, 0), (3, 6, 60, 127, 0), (6, 9, 72, 127, 0), (9, 15, 67, 88, 0), (15, 18, 60, 64, 0),
                             (18, 24, 67, 64, 0), (24, 27, 60, 44, 0), (27, 33, 67, 44, 0), (33, 36, 60, 28, 0), (36, 42, 67, 28, 0),
                             (42, 45, 60, 12, 0), (45, 51, 67, 12, 0)]
            tracks = [(.noise(decay: 2, release: 0), n), (.snare, s)]
        case .lowHealth:
            tick = 0.4 / 24
            songVolume = 100
            tracks = [(.square(decay: 6, release: 1), [(0, 12, 74, 80, 2176.0 / 8192 * 2), (12, 24, 69, 80, 3968.0 / 8192 * 2)])]
        }
        let loopLength = k == .lowHealth ? 24 : nil
        let total = Double(loopLength ?? (tracks.flatMap { $0.1 }.map(\.1).max() ?? 0) + 30) * tick
        var out = [Double](repeating: 0, count: Int(total * rate))
        let sample = snare.flatMap(wavSamples)
        for (voice, notes) in tracks {
            for n in notes {
                let start = Double(n.0) * tick, end = Double(n.1) * tick
                render(voice, key: Double(n.2) + n.4, velocity: Double(n.3) / 127 * songVolume / 127,
                       from: start, to: end, into: &out, sample: sample, cutAt: loopLength.map { Double($0) * tick })
            }
        }
        let peak = max(0.0001, out.map(abs).max() ?? 1)
        let gain = min(1, 0.9 / peak)
        return wav(out.map { $0 * gain })
    }

    private static func render(_ v: Voice, key: Double, velocity: Double, from start: Double, to end: Double,
                               into out: inout [Double], sample: (rate: Double, data: [Double])?, cutAt: Double?) {
        let i0 = Int(start * rate)
        switch v {
        case .noise(let decay, let release), .square(let decay, let release):
            // CGB envelope: peak volume 0–15, −1 every `decay` frames while held, −1 every `release` frames after
            let peak = (15 * velocity).rounded()
            var lfsr: UInt16 = 0x7FFF
            var clockAcc = 0.0
            var phase = 0.0
            let isNoise: Bool = { if case .noise = v { return true }; return false }()
            let clock: Double = {
                guard isNoise else { return 440 * pow(2, (key - 69) / 12) }
                // m4a's gNoiseTable: key−21 → NR43 (shift s, divisor r), clock = 524288 / r / 2^(s+1)
                let table: [UInt8] = [0xD7, 0xD6, 0xD5, 0xD4, 0xC7, 0xC6, 0xC5, 0xC4, 0xB7, 0xB6, 0xB5, 0xB4, 0xA7, 0xA6, 0xA5, 0xA4,
                                      0x97, 0x96, 0x95, 0x94, 0x87, 0x86, 0x85, 0x84, 0x77, 0x76, 0x75, 0x74, 0x67, 0x66, 0x65, 0x64,
                                      0x57, 0x56, 0x55, 0x54, 0x47, 0x46, 0x45, 0x44, 0x37, 0x36, 0x35, 0x34, 0x27, 0x26, 0x25, 0x24,
                                      0x17, 0x16, 0x15, 0x14, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00]
                let k = max(0, min(59, Int(key.rounded()) - 21))
                let b = table[k]
                let s = Double(b >> 4), r = Double(b & 7)
                return 524_288 / (r == 0 ? 0.5 : r) / pow(2, s + 1)
            }()
            var i = i0
            while i < out.count {
                let t = Double(i) / rate
                if let c = cutAt, t >= c { break }
                let held = t < end
                let framesIn = (t - start) / frame
                var vol: Double
                if held {
                    vol = max(0, peak - floor(framesIn / Double(max(1, decay))))
                } else {
                    if release == 0 { break }
                    let atEnd = max(0, peak - floor((end - start) / frame / Double(max(1, decay))))
                    vol = max(0, atEnd - floor((t - end) / frame / Double(release)))
                    if vol <= 0 { break }
                }
                var s: Double
                if isNoise {
                    clockAcc += clock / rate
                    var acc = 0.0, n = 0.0
                    while clockAcc >= 1 {
                        let bit = (lfsr ^ (lfsr >> 1)) & 1
                        lfsr = (lfsr >> 1) | (bit << 14)
                        acc += (lfsr & 1) == 0 ? 1 : -1
                        n += 1; clockAcc -= 1
                    }
                    s = n > 0 ? acc / n : ((lfsr & 1) == 0 ? 1 : -1)
                } else {
                    phase += clock / rate
                    s = phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1      // 50% duty
                }
                out[i] += s * vol / 15 * 0.5
                i += 1
            }
        case .snare:
            guard let sample else { return }
            // DirectSound ADSR per frame: attack 255 (instant), decay ×249/256 down to 103, release ×165/256
            let step = sample.rate * pow(2, (key - 60) / 12) / rate
            var pos = 0.0
            var env = 255.0
            var lastFrame = 0
            var i = i0
            while i < out.count, Int(pos) < sample.data.count {
                let t = Double(i) / rate
                if let c = cutAt, t >= c { break }
                let f = Int((t - start) / frame)
                while lastFrame < f {
                    lastFrame += 1
                    let ft = start + Double(lastFrame) * frame
                    if ft < end { env = max(103, env * 249 / 256) } else { env = env * 165 / 256 }
                }
                if env < 1 { break }
                out[i] += sample.data[Int(pos)] * env / 255 * velocity
                pos += step
                i += 1
            }
        }
    }

    /// 8-bit unsigned (or 16-bit) PCM samples from a WAV file.
    private static func wavSamples(_ d: Data) -> (rate: Double, data: [Double])? {
        let b = [UInt8](d)
        guard b.count > 44, b[0] == 0x52, b[8] == 0x57 else { return nil }
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        var i = 12, sr = 11_025, bits = 8
        while i + 8 <= b.count {
            let id = String(bytes: b[i..<(i + 4)], encoding: .ascii) ?? ""
            let len = u32(i + 4)
            if id == "fmt " { sr = u32(i + 12); bits = u16(i + 22) }
            if id == "data" {
                let body = b[(i + 8)..<min(b.count, i + 8 + len)]
                if bits == 8 { return (Double(sr), body.map { (Double($0) - 128) / 128 }) }
                let arr = Array(body)
                return (Double(sr), stride(from: 0, to: arr.count - 1, by: 2).map { Double(Int16(bitPattern: UInt16(arr[$0]) | UInt16(arr[$0 + 1]) << 8)) / 32768 })
            }
            i += 8 + len + (len & 1)
        }
        return nil
    }

    private static func wav(_ s: [Double]) -> Data {
        var d = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func put16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let n = UInt32(s.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); put32(36 + n); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1); put32(44_100); put32(88_200); put16(2); put16(16)
        d.append(contentsOf: Array("data".utf8)); put32(n)
        for v in s { put16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32_000))) }
        return d
    }
}
