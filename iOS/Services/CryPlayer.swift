import Foundation
import AVFoundation

/// Pokémon cries (MP3s from Pokémon Showdown's audio library), saved on the phone after the first play.
/// Uses the "ambient" audio session: obeys the silent switch and mixes with your music.
@MainActor
final class CryPlayer: ObservableObject {
    static let shared = CryPlayer()

    @Published private(set) var progress: Double?      // download-all progress; nil = not running
    @Published private(set) var failed = 0
    @Published private(set) var finished = false

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "criesEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "criesEnabled"); objectWillChange.send() }
    }

    private var player: AVAudioPlayer?

    nonisolated static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cries", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    nonisolated static func file(_ id: Int) -> URL { dir.appendingPathComponent("\(id).mp3") }

    /// Showdown names: lowercase letters and digits only (mr-mime → mrmime, ho-oh → hooh, nidoran-f → nidoranf).
    nonisolated static func remote(_ id: Int) -> URL? {
        let name = Dex.species(id).key.lowercased().filter { $0.isLetter || $0.isNumber }
        return URL(string: "https://play.pokemonshowdown.com/audio/cries/\(name).mp3")
    }

    /// Saves one cry if it isn't already on the phone. Returns its file.
    nonisolated static func fetch(_ id: Int) async -> URL? {
        let f = file(id)
        if FileManager.default.fileExists(atPath: f.path) { return f }
        guard let url = remote(id),
              let (data, resp) = try? await URLSession.shared.mirroredData(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 500 else { return nil }
        try? data.write(to: f, options: .atomic)
        return f
    }

    func play(_ speciesID: Int) {
        guard enabled else { return }
        Task {
            guard let f = await Self.fetch(speciesID) else { return }
            if !SleepRecorder.active { try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers]) }
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: f)
            player?.volume = 0.8
            player?.play()
        }
    }

    var downloadedCount: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: Self.dir.path)) ?? []).filter { $0.hasSuffix(".mp3") }.count
    }

    /// Saves all 386 cries (a few MB) for offline play.
    func downloadAll() {
        guard progress == nil else { return }
        progress = 0; failed = 0; finished = false
        Task.detached(priority: .utility) {
            let ids = Array(1...Dex.count)
            var done = 0, bad = 0, next = 0
            await withTaskGroup(of: Bool.self) { group in
                while next < min(8, ids.count) {
                    let id = ids[next]; next += 1
                    group.addTask { await CryPlayer.fetch(id) != nil }
                }
                for await ok in group {
                    done += 1; if !ok { bad += 1 }
                    if next < ids.count {
                        let id = ids[next]; next += 1
                        group.addTask { await CryPlayer.fetch(id) != nil }
                    }
                    if done % 8 == 0 {
                        let p = Double(done) / Double(ids.count), b = bad
                        await MainActor.run { self.progress = p; self.failed = b }
                    }
                }
            }
            let b = bad
            await MainActor.run { self.progress = nil; self.failed = b; self.finished = true }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: Self.dir)
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        finished = false
        objectWillChange.send()
    }
}
