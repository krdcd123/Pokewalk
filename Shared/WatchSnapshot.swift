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
        var heldItem: String? = nil      // shows a red dot, like the trainer button on the phone
        var stepsWalked: Int = 0

        var species: Species { Dex.species(speciesID) }
    }

    /// One row of the Bag (balls, berries, items) for the watch's condensed list.
    struct BagLine: Codable, Equatable, Identifiable {
        var key: String
        var name: String
        var count: Int
        var pocket: String
        var id: String { key }
    }

    /// Part of today's route: coordinates flattened as [lat, lon, lat, lon, …].
    struct TrailSegment: Codable, Equatable {
        var drive: Bool
        var coords: [Double]
    }

    /// A wild Pokémon waiting to be caught.
    struct Wild: Codable, Equatable, Identifiable {
        var id: String
        var speciesID: Int
        var level: Int
        var isShiny: Bool
        var expiresAt: Date
        var species: Species { Dex.species(speciesID) }
    }

    var syncDate: Date
    var expPerStep: Double
    var partyShare: Double
    var lifetimeSteps: Int
    var balls: Int
    var stepsToEncounter: Int
    var stepsToBall: Int
    var ballSteps: Int
    var pendingEncounters: Int
    var distanceTodayKm: Double
    var trainerName: String
    var party: [Member]
    var bag: [BagLine] = []
    var wild: [Wild] = []
    var latitude: Double? = nil     // where you are (for the watch app's blurred map background)
    var longitude: Double? = nil
    var money: Int = 0
    var trail: [TrailSegment] = []  // today's walks (and drives), thinned out for the watch map

    var buddy: Member? { party.first { $0.isBuddy } }

    static let empty = WatchSnapshot(syncDate: .now, expPerStep: 0.25, partyShare: 0.2, lifetimeSteps: 0, balls: 0, stepsToEncounter: 0,
                                     stepsToBall: 0, ballSteps: 100, pendingEncounters: 0, distanceTodayKm: 0, trainerName: "",
                                     party: [])
}

/// A Member with steps-since-sync applied (only the buddy walks).
struct LiveMember {
    let member: WatchSnapshot.Member
    let liveExp: Int
    let pendingSteps: Int
    let expPerStep: Double

    init(_ member: WatchSnapshot.Member, stepsSinceSync: Int, expPerStep: Double, partyShare: Double) {
        self.member = member
        self.pendingSteps = stepsSinceSync
        let rate = member.isBuddy ? expPerStep : expPerStep * partyShare
        self.expPerStep = rate
        self.liveExp = min(member.exp + Int(Double(stepsSinceSync) * rate), member.species.growth.maxExp)
    }

    init(_ member: WatchSnapshot.Member, in snap: WatchSnapshot, stepsSinceSync: Int) {
        self.init(member, stepsSinceSync: stepsSinceSync, expPerStep: snap.expPerStep, partyShare: snap.partyShare)
    }

    private var growth: GrowthRate { member.species.growth }
    var level: Int { growth.level(forExp: liveExp) }
    var syncedLevel: Int { growth.level(forExp: member.exp) }
    var progress: Double { growth.progress(exp: liveExp) }
    var expToNext: Int { growth.expToNext(exp: liveExp) }
    /// Steps still to walk before the next level (at this Pokémon's Exp per step).
    var stepsToNext: Int { expPerStep > 0 ? Int((Double(expToNext) / expPerStep).rounded(.up)) : 0 }

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

    static func iconFile(_ speciesID: Int, shiny: Bool = false) -> URL {
        iconsDir.appendingPathComponent(shiny ? "\(speciesID)s.png" : "\(speciesID).png")
    }
    static func hasIcon(_ speciesID: Int, shiny: Bool = false) -> Bool {
        FileManager.default.fileExists(atPath: iconFile(speciesID, shiny: shiny).path)
    }

    /// The same PokeSprite box icons the phone uses (regular and shiny).
    static func remoteIconURL(_ speciesID: Int, shiny: Bool = false) -> URL {
        let key = Dex.species(speciesID).key
        return URL(string: "https://raw.githubusercontent.com/msikma/pokesprite/master/pokemon-gen8/\(shiny ? "shiny" : "regular")/\(key).png")!
    }

    /// Animated Gen 5 sprite (up to #649) for the watch's summary screen.
    static func remoteFrontURL(_ speciesID: Int, shiny: Bool) -> URL? {
        guard speciesID <= 649 else { return nil }
        let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated"
        return URL(string: shiny ? "\(base)/shiny/\(speciesID).gif" : "\(base)/\(speciesID).gif")
    }

    static func remoteItemURL(_ key: String) -> URL {
        let k = Fishing.isBait(key) ? "honey" : Fishing.isLure(key) ? "lax-incense" : key
        return URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/\(k).png")!
    }

    static var spritesDir: URL {
        let dir = containerURL.appendingPathComponent("sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func itemFile(_ key: String) -> URL { spritesDir.appendingPathComponent("item-\(key).png") }
    static func frontFile(_ speciesID: Int, shiny: Bool) -> URL {
        spritesDir.appendingPathComponent("front-\(speciesID)\(shiny ? "s" : "").gif")
    }

    /// Downloads `remote` to `file` once.
    @discardableResult
    static func fetch(_ remote: URL, to file: URL) async -> URL? {
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let (data, resp) = try? await URLSession.shared.data(from: remote),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        try? data.write(to: file, options: .atomic)
        return file
    }

    @discardableResult
    static func fetchIcon(_ speciesID: Int, shiny: Bool = false) async -> URL? {
        await fetch(remoteIconURL(speciesID, shiny: shiny), to: iconFile(speciesID, shiny: shiny))
    }
}


// MARK: - Tolerant decoding
// The watch keeps the last snapshot it got. When a new version adds fields, an older saved snapshot
// (or one from a phone that hasn't updated yet) must still load instead of failing and showing nothing.

extension WatchSnapshot.Member {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        name = try c.decode(String.self, forKey: .name)
        exp = try c.decode(Int.self, forKey: .exp)
        isBuddy = try c.decodeIfPresent(Bool.self, forKey: .isBuddy) ?? false
        canEvolve = try c.decodeIfPresent(Bool.self, forKey: .canEvolve) ?? false
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        gender = (try? c.decodeIfPresent(Gender.self, forKey: .gender)) ?? .genderless
        heldItem = try c.decodeIfPresent(String.self, forKey: .heldItem)
        stepsWalked = try c.decodeIfPresent(Int.self, forKey: .stepsWalked) ?? 0
    }
}

extension WatchSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncDate = try c.decodeIfPresent(Date.self, forKey: .syncDate) ?? .now
        expPerStep = try c.decodeIfPresent(Double.self, forKey: .expPerStep) ?? 0.25
        partyShare = try c.decodeIfPresent(Double.self, forKey: .partyShare) ?? 0.2
        lifetimeSteps = try c.decodeIfPresent(Int.self, forKey: .lifetimeSteps) ?? 0
        balls = try c.decodeIfPresent(Int.self, forKey: .balls) ?? 0
        stepsToEncounter = try c.decodeIfPresent(Int.self, forKey: .stepsToEncounter) ?? 0
        stepsToBall = try c.decodeIfPresent(Int.self, forKey: .stepsToBall) ?? 0
        ballSteps = try c.decodeIfPresent(Int.self, forKey: .ballSteps) ?? 1_000
        pendingEncounters = try c.decodeIfPresent(Int.self, forKey: .pendingEncounters) ?? 0
        distanceTodayKm = try c.decodeIfPresent(Double.self, forKey: .distanceTodayKm) ?? 0
        trainerName = try c.decodeIfPresent(String.self, forKey: .trainerName) ?? ""
        party = (try? c.decodeIfPresent([Member].self, forKey: .party)) ?? []
        bag = (try? c.decodeIfPresent([BagLine].self, forKey: .bag)) ?? []
        wild = (try? c.decodeIfPresent([Wild].self, forKey: .wild)) ?? []
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        money = (try? c.decodeIfPresent(Int.self, forKey: .money)) ?? 0
        trail = (try? c.decodeIfPresent([TrailSegment].self, forKey: .trail)) ?? []
    }
}
