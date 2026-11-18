import Foundation

/// The compact view of the save game that the iPhone sends to the Watch.
struct WatchSnapshot: Codable, Equatable {
    struct Member: Codable, Equatable, Identifiable {
        var id: String
        var speciesID: Int
        var name: String
        var exp: Int
        var isBuddy: Bool
        var canEvolve: Bool
        var isShiny: Bool = false
        var gender: Gender = .genderless

        var species: Species { Dex.species(speciesID) }
    }

    var syncDate: Date
    var expMultiplier: Int
    var lifetimeSteps: Int
    var balls: Int
    var stepsToEncounter: Int
    var stepsToBall: Int
    var ballSteps: Int
    var pendingEncounters: Int
    var distanceTodayKm: Double
    var trainerName: String
    var party: [Member]

    var buddy: Member? { party.first { $0.isBuddy } }

    static let empty = WatchSnapshot(syncDate: .now, expMultiplier: 1, lifetimeSteps: 0, balls: 0, stepsToEncounter: 0,
                                     stepsToBall: 0, ballSteps: 100, pendingEncounters: 0, distanceTodayKm: 0, trainerName: "",
                                     party: [])
}

/// A Member with steps-since-sync applied (only the buddy walks).
struct LiveMember {
    let member: WatchSnapshot.Member
    let liveExp: Int
    let pendingSteps: Int

    init(_ member: WatchSnapshot.Member, stepsSinceSync: Int, multiplier: Int) {
        self.member = member
        self.pendingSteps = member.isBuddy ? stepsSinceSync : 0
        self.liveExp = min(member.exp + pendingSteps * max(1, multiplier), member.species.growth.maxExp)
    }

    private var growth: GrowthRate { member.species.growth }
    var level: Int { growth.level(forExp: liveExp) }
    var syncedLevel: Int { growth.level(forExp: member.exp) }
    var progress: Double { growth.progress(exp: liveExp) }
    var expToNext: Int { growth.expToNext(exp: liveExp) }

    var readyToEvolve: Bool {
        if member.canEvolve { return true }
        return member.species.evolutions.contains { $0.kind == .level && level >= ($0.level ?? 101) }
    }
}

// MARK: - Shared App Group storage

enum SharedStore {
    /// Sideloading tools (AltStore, SideStore, Sideloadly…) often rename App Groups when they re-sign,
    /// so read the real group from the embedded provisioning profile first, then fall back to Info.plist.
    static let groupID: String = provisionedGroup()
        ?? (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String)
        ?? "group.com.example.pokewalk"

    private static func provisionedGroup() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>") else { return nil }
        let plistData = Data(text[start.lowerBound..<end.upperBound].utf8)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let ents = plist["Entitlements"] as? [String: Any],
              let groups = ents["com.apple.security.application-groups"] as? [String] else { return nil }
        return groups.first { $0.lowercased().contains("pokewalk") } ?? groups.first
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private static let snapshotKey = "watchSnapshot"
    private static let liveStepsKey = "liveStepsSinceSync"
    private static let liveStepsDateKey = "liveStepsUpdated"

    static func saveSnapshot(_ snap: WatchSnapshot) {
        if let data = try? JSONEncoder().encode(snap) { defaults.set(data, forKey: snapshotKey) }
    }

    static func loadSnapshot() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    static func saveLiveSteps(_ steps: Int, forSync syncDate: Date) {
        defaults.set(steps, forKey: liveStepsKey)
        defaults.set(syncDate.timeIntervalSince1970, forKey: liveStepsDateKey)
    }

    static func cachedLiveSteps(forSync syncDate: Date) -> Int {
        let stamp = defaults.double(forKey: liveStepsDateKey)
        guard abs(stamp - syncDate.timeIntervalSince1970) < 1 else { return 0 }
        return defaults.integer(forKey: liveStepsKey)
    }

    // Party icons (small box icons) shared with complications -------------

    static var iconsDir: URL {
        let dir = containerURL.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func iconFile(_ speciesID: Int) -> URL { iconsDir.appendingPathComponent("\(speciesID).png") }
    static func hasIcon(_ speciesID: Int) -> Bool { FileManager.default.fileExists(atPath: iconFile(speciesID).path) }

    /// PokeAPI's Gen 7 box icons cover every species up to #807.
    static func remoteIconURL(_ speciesID: Int) -> URL {
        URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-vii/icons/\(speciesID).png")!
    }

    @discardableResult
    static func fetchIcon(_ speciesID: Int) async -> URL? {
        let file = iconFile(speciesID)
        if hasIcon(speciesID) { return file }
        guard let (data, resp) = try? await URLSession.shared.data(from: remoteIconURL(speciesID)),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        try? data.write(to: file, options: .atomic)
        return file
    }
}
