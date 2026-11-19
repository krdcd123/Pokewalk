import Foundation
import CoreLocation
import HealthKit
import UserNotifications
import UIKit

@MainActor
final class GameStore: ObservableObject {
    static let shared = GameStore()

    @Published private(set) var state = GameState()
    @Published private(set) var hasGame = false
    @Published var stepsToday = 0
    @Published var metersToday: Double = 0
    @Published var toast: String?
    @Published var activeEncounter: PendingEncounter?
    @Published var evolutionCandidate: EvolutionCandidate?
    private var rampTimer: Timer?
    @Published var healthError: String?

    struct EvolutionCandidate: Identifiable, Equatable {
        let pokemonID: UUID
        let into: Int
        var id: UUID { pokemonID }
    }

    private let engine = StepEngine.shared
    private let tracker = LocationTracker.shared
    private var ticking = false
    private var lastTick = Date.distantPast
    private var observerStarted = false

    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pokewalk-save-v2.json")
    }

    init() {
        load()
        storage = Self.loadStorage()
    }

    // MARK: Storage — a box shared by every game on this phone (kept when you start a New Game)

    @Published private(set) var storage: [OwnedPokemon] = []

    static var storageURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Storage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PokeWalk-Storage.json")
    }

    private static func loadStorage() -> [OwnedPokemon] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        return (try? JSONDecoder().decode([OwnedPokemon].self, from: data)) ?? []
    }

    private func saveStorage() {
        if let data = try? JSONEncoder().encode(storage) { try? data.write(to: Self.storageURL, options: .atomic) }
    }

    /// Moves a Pokémon from a PC box into Storage. Party Pokémon (and your buddy) have to be boxed first.
    @discardableResult
    func sendToStorage(_ id: UUID) -> Bool {
        guard let mon = state.mon(id), !state.partyIDs.contains(id), state.buddyID != id else { return false }
        storage.append(mon)
        saveStorage()
        mutate { GameRules.release(id, in: &$0) }
        return true
    }

    /// Moves a Pokémon from Storage into this game's PC.
    func takeFromStorage(_ id: UUID) {
        guard let i = storage.firstIndex(where: { $0.id == id }) else { return }
        let mon = storage.remove(at: i)
        mutate { GameRules.storeInBox(mon, in: &$0) }
        saveStorage()
    }

    /// Adds Storage Pokémon from an imported save (skipping any already here).
    private func mergeStorage(_ mons: [OwnedPokemon]) {
        let have = Set(storage.map(\.id)).union(state.pokemon.map(\.id))
        storage += mons.filter { !have.contains($0.id) }
        saveStorage()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(GameState.self, from: data) else { return }
        state = decoded
        hasGame = !decoded.pokemon.isEmpty
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: saveURL, options: .atomic) }
        autoBackup()
        pushOutward()
    }

    // MARK: Backups & moving saves between installs

    /// A whole save (game + walk tracks) in one file.
    struct SaveFile: Codable {
        var format = "pokewalk-save"
        var exportedAt = Date()
        var state: GameState
        var tracks: [String: [[TrackPoint]]]
        var storage: [OwnedPokemon]? = nil
    }

    private var lastBackup = Date.distantPast

    /// Files app › On My iPhone › PokéWalk › Backups — kept up to date automatically (every few minutes).
    var autoBackupURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PokeWalk-backup.json")
    }

    private func autoBackup() {
        guard hasGame, Date().timeIntervalSince(lastBackup) > 300 else { return }
        lastBackup = .now
        if let data = try? JSONEncoder().encode(SaveFile(state: state, tracks: TrackStore.shared.allDays(), storage: storage)) {
            try? data.write(to: autoBackupURL, options: .atomic)
        }
    }

    /// Writes a fresh export file to share (Files, iCloud Drive, AirDrop…).
    func exportSave() -> URL? {
        let name = "PokeWalk-\(state.trainer.name)-\(Date().formatted(.iso8601.year().month().day())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(SaveFile(state: state, tracks: TrackStore.shared.allDays(), storage: storage)),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Loads a save exported from any PokéWalk install. Returns an error message, or nil on success.
    func importSave(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return "Couldn't read that file." }
        let dec = JSONDecoder()
        var importedStorage: [OwnedPokemon] = []
        let imported: GameState
        if let file = try? dec.decode(SaveFile.self, from: data) {
            imported = file.state
            TrackStore.shared.importDays(file.tracks)
            importedStorage = file.storage ?? []
        } else if let bare = try? dec.decode(GameState.self, from: data) {
            imported = bare
        } else {
            return "That isn't a PokéWalk save file."
        }
        guard !imported.pokemon.isEmpty else { return "That save has no Pokémon in it." }
        var s = imported
        // Keep whichever ledger has credited more, so steps are never rewarded twice.
        s.stepLedger.merge(state.stepLedger) { max($0, $1) }
        s.distanceLedger.merge(state.distanceLedger) { max($0, $1) }
        state = s
        hasGame = true
        mergeStorage(importedStorage)
        save()
        start()
        return nil
    }

    private func mutate(_ change: (inout GameState) -> Void) {
        change(&state)
        save()
    }

    // MARK: Startup

    func start() {
        guard hasGame else { return }
        // One-time: balls now come every 1,000 steps
        if !UserDefaults.standard.bool(forKey: "shiny8192") {
            UserDefaults.standard.set(true, forKey: "shiny8192")
            mutate { $0.settings.shinyOdds = 8_192 }
        }
        if !UserDefaults.standard.bool(forKey: "ballSteps1000") {
            UserDefaults.standard.set(true, forKey: "ballSteps1000")
            mutate { $0.settings.ballSteps = 1_000 }
        }
        tracker.onMovement = { [weak self] _ in self?.requestTick(minInterval: 20) }
        tracker.apply(mode: state.settings.trackingMode)
        engine.startLiveUpdates { [weak self] in self?.requestTick(minInterval: 15) }
        // While Shortcut-synced steps are being fed in, keep the counters moving smoothly.
        rampTimer?.invalidate()
        rampTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in if ShortcutSteps.isRamping { await self?.tick() } }
        }
        startHealthObserver()
        requestTick(minInterval: 0)
        LiveActivityManager.shared.startIfNeeded(with: self)
    }

    func requestPermissions() async {
        do { try await StepCounter.shared.requestAuthorizationWithDistance() }
        catch { healthError = error.localizedDescription }
        tracker.requestPermission()
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        let throwAction = UNNotificationAction(identifier: "throw", title: "Throw a ball", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "encounter", actions: [throwAction],
                                                                 intentIdentifiers: [])])
    }

    /// HealthKit wakes the app (roughly hourly) when new steps arrive — catches Watch-only walks.
    private func startHealthObserver() {
        let hk = StepCounter.shared
        guard hk.isAvailable, !observerStarted else { return }
        observerStarted = true
        let q = HKObserverQuery(sampleType: hk.stepType, predicate: nil) { _, completion, _ in
            Task { @MainActor in
                await GameStore.shared.tick()
                completion()
            }
        }
        hk.store.execute(q)
        hk.store.enableBackgroundDelivery(for: hk.stepType, frequency: .hourly) { _, _ in }
    }

    // MARK: New game

    func newGame(trainerName: String, appearance: String, starter: Int, nickname: String?, shiny: Bool = false) async {
        let loc = tracker.currentLocation()
        var met: MetLocation?
        if let loc {
            met = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                              placeName: await PlaceService.shared.placeName(for: loc))
        }
        var s = GameRules.newGame(trainerName: trainerName, appearance: appearance, starter: starter,
                                  nickname: nickname, location: met, shiny: shiny)
        // Start counting from now: today's earlier steps don't count.
        let today = Calendar.current.startOfDay(for: .now)
        s.stepLedger[TrackStore.key(for: today)] = await engine.steps(onDay: today)
        s.distanceLedger[TrackStore.key(for: today)] = await engine.distanceToday()
        state = s
        hasGame = true
        save()
        start()
    }

    // MARK: Step processing

    func requestTick(minInterval: TimeInterval) {
        guard Date().timeIntervalSince(lastTick) >= minInterval else { return }
        Task { await tick() }
    }

    func tick() async {
        guard hasGame, !ticking else { return }
        ticking = true
        defer { ticking = false; lastTick = .now }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var ledger = state.stepLedger
        var newSteps = 0

        let gameExisted = !ledger.isEmpty
        let startedDay = cal.startOfDay(for: state.trainer.startedOn)
        for day in [yesterday, today] {
            let key = TrackStore.key(for: day)
            let total = await engine.steps(onDay: day)
            if day == today { stepsToday = total }
            // Days we haven't seen yet count from midnight, unless they're before the game started.
            let processed = ledger[key] ?? ((gameExisted && day >= startedDay) ? 0 : total)
            ledger[key] = max(processed, total)
            if total > processed { newSteps += total - processed }
        }
        // Keep the ledger small.
        let keep = Set([yesterday, today].map { TrackStore.key(for: $0) })
        ledger = ledger.filter { keep.contains($0.key) }
        metersToday = await engine.distanceToday()
        // Distance since last sync goes to the buddy (counted the same way as steps).
        let todayKey = TrackStore.key(for: today)
        let creditedMeters = state.distanceLedger[todayKey] ?? 0
        let newMeters = max(0, metersToday - creditedMeters)

        guard newSteps > 0 else {
            if ledger != state.stepLedger { state.stepLedger = ledger; save() } else { pushOutward() }
            return
        }

        // Where are we? Shapes which Pokémon appear and records where they were met.
        let loc = tracker.currentLocation()
        var context = EncounterContext(habitats: await PlaceService.shared.habitats(near: loc),
                                       isNight: TimeOfDay.at(.now) == .night)
        if let loc {
            context.location = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                                           placeName: await PlaceService.shared.placeName(for: loc))
        }

        var s = state
        s.stepLedger = ledger
        s.distanceLedger = [todayKey: max(creditedMeters, metersToday)]
        let outcome = GameRules.apply(steps: newSteps, meters: newMeters, to: &s, context: context)
        state = s
        save()
        report(outcome)
    }

    private func report(_ o: StepOutcome) {
        let background = UIApplication.State.current != .active
        var lines: [String] = []
        if o.newLevel > o.oldLevel, let buddy = state.buddy {
            lines.append("\(buddy.name) grew to Lv. \(o.newLevel)!")
        }
        if let buddy = state.buddy {
            for candy in o.pickedUp { lines.append("\(buddy.name) picked up an \(Dex.itemName(candy))!") }
        }
        if !o.itemsFound.isEmpty {
            lines.append("Found " + o.itemsFound.map(Dex.itemName).joined(separator: ", ") + "!")
        }
        if let evo = o.evolutionReady, let mon = state.mon(evo.id) {
            if background {
                notify(title: "What? \(mon.name) is evolving!", body: "Open PokéWalk to watch.", id: "evo")
            } else {
                evolutionCandidate = EvolutionCandidate(pokemonID: evo.id, into: evo.into)
            }
        }
        for enc in o.newEncounters {
            if background && state.settings.notifyEncounters {
                let place = enc.location?.placeName.map { " near \($0)" } ?? ""
                notify(title: "A wild \(enc.species.name) appeared!\(enc.isShiny ? " ✨" : "")",
                       body: "Lv. \(enc.level)\(place). Tap to throw a ball.",
                       id: enc.id.uuidString, category: "encounter")
            }
        }
        if !o.newEncounters.isEmpty && !background {
            lines.append(o.newEncounters.count == 1 ? "A wild \(o.newEncounters[0].species.name) appeared!"
                                                    : "\(o.newEncounters.count) wild Pokémon appeared!")
        }
        if background, !lines.isEmpty, o.newEncounters.isEmpty {
            notify(title: "PokéWalk", body: lines.joined(separator: " "), id: "progress")
        } else if !lines.isEmpty {
            toast = lines.joined(separator: "  ")
        }
    }

    private func notify(title: String, body: String, id: String, category: String? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let category { c.categoryIdentifier = category; c.userInfo = ["encounterID": id] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    // MARK: Encounters

    func openEncounter(id: String) {
        guard let uuid = UUID(uuidString: id), let enc = state.pending.first(where: { $0.id == uuid }) else { return }
        activeEncounter = enc
    }

    func useBall(_ kind: BallKind) -> Bool {
        guard state.balls[kind, default: 0] > 0 else { return false }
        mutate { $0.balls[kind, default: 0] -= 1 }
        return true
    }

    /// Ends an encounter. Returns the new Pokémon if it was caught.
    @discardableResult
    func finish(_ safari: SafariEncounter) -> OwnedPokemon? {
        var caught: OwnedPokemon?
        mutate { s in
            s.pending.removeAll { $0.id == safari.wild.id }
            let w = safari.wild
            var entry = EncounterLogEntry(id: w.id, speciesID: w.speciesID, level: w.level, isShiny: w.isShiny,
                                          date: w.appearedAt, location: w.location ?? self.tracker.currentLocation().map {
                                              MetLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                                          }, outcome: .waiting)
            switch safari.phase {
            case .caught(let b): entry.outcome = .caught; entry.ball = b
            case .fled: entry.outcome = .fled
            case .ranAway: entry.outcome = .ranAway
            case .active: break
            }
            defer {
                if entry.outcome != .waiting {
                    s.encounterLog.removeAll { $0.id == entry.id }
                    s.encounterLog.append(entry)
                    if s.encounterLog.count > 2_000 { s.encounterLog.removeFirst(s.encounterLog.count - 2_000) }
                }
            }
            guard case .caught(let ball) = safari.phase else { return }
            var mon = GameRules.makePokemon(species: w.speciesID, level: w.level, ball: ball, trainer: s.trainer,
                                            settings: s.settings, location: w.location, date: .now)
            mon.gender = w.gender; mon.isShiny = w.isShiny; mon.nature = w.nature; mon.personality = w.personality
            mon.metDate = w.appearedAt
            if w.location == nil, let loc = tracker.currentLocation() {
                mon.metLocation = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            }
            GameRules.store(mon, in: &s)
            entry.caughtID = mon.id
            entry.location = mon.metLocation
            caught = mon
        }
        if let caught, caught.metLocation?.placeName == nil, let met = caught.metLocation {
            Task {
                let name = await PlaceService.shared.placeName(for: CLLocation(latitude: met.latitude, longitude: met.longitude))
                mutate { s in
                    if let i = s.index(of: caught.id) { s.pokemon[i].metLocation?.placeName = name }
                }
            }
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [safari.wild.id.uuidString])
        return caught
    }

    // MARK: Pokémon management

    func setBuddy(_ id: UUID) async {
        await tick()                         // steps so far belong to the old buddy
        mutate { GameRules.setBuddy(id, in: &$0) }
    }

    func move(from a: PCSlot, to b: PCSlot) { mutate { GameRules.move(from: a, to: b, in: &$0) } }
    func release(_ id: UUID) { mutate { GameRules.release(id, in: &$0) } }

    @discardableResult
    func sell(_ item: String, count: Int) -> Int {
        var earned = 0
        mutate { earned = GameRules.sell(item, count: count, in: &$0) }
        return earned
    }

    func buy(_ ball: BallKind, count: Int) -> Bool {
        var ok = false
        mutate { ok = GameRules.buy(ball, count: count, in: &$0) }
        return ok
    }

    /// Moves a Pokémon's held Exp. Candies into the Bag.
    @discardableResult
    func takeHeldItems(_ id: UUID) -> [String] {
        var taken: [String] = []
        mutate { taken = GameRules.takeHeldItems(from: id, in: &$0) }
        return taken
    }

    func rename(_ id: UUID, to name: String) {
        mutate { s in
            guard let i = s.index(of: id) else { return }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            s.pokemon[i].nickname = trimmed.isEmpty ? nil : String(trimmed.prefix(12))
        }
    }

    func renameBox(_ index: Int, to name: String) {
        mutate { s in if s.boxes.indices.contains(index) { s.boxes[index].name = String(name.prefix(16)) } }
    }

    func setWallpaper(_ index: Int, _ wallpaper: Int) {
        mutate { s in if s.boxes.indices.contains(index) { s.boxes[index].wallpaper = wallpaper } }
    }

    func addBox() { mutate { $0.boxes.append(PCBox(name: "Box \($0.boxes.count + 1)", wallpaper: $0.boxes.count % 8)) } }

    func evolve(_ c: EvolutionCandidate) {
        var bonus: OwnedPokemon?
        mutate { bonus = GameRules.evolve(c.pokemonID, into: c.into, in: &$0) }
        if let bonus { toast = "\(bonus.species.name) appeared in your party!" }
    }

    func declineEvolution(_ c: EvolutionCandidate) { mutate { GameRules.declineEvolution(c.pokemonID, in: &$0) } }

    func checkPendingEvolutions() {
        guard evolutionCandidate == nil else { return }
        for mon in state.party {
            if let into = GameRules.pendingEvolution(for: mon) {
                evolutionCandidate = EvolutionCandidate(pokemonID: mon.id, into: into)
                return
            }
        }
    }

    func use(_ item: String, on id: UUID) -> GameRules.ItemOutcome {
        var s = state
        let outcome = GameRules.use(item, on: id, in: &s)
        state = s
        save()
        switch outcome {
        case .evolves(let into): evolutionCandidate = EvolutionCandidate(pokemonID: id, into: into)
        case .leveled:
            if let mon = state.mon(id), let into = GameRules.pendingEvolution(for: mon) {
                evolutionCandidate = EvolutionCandidate(pokemonID: id, into: into)
            }
        case .friendship, .noEffect: break
        }
        return outcome
    }

    // MARK: Walks & settings

    func startWalk() { tracker.startWalk(); LiveActivityManager.shared.startIfNeeded(with: self) }
    func endWalk() { tracker.endWalk(mode: state.settings.trackingMode) }

    func updateSettings(_ change: (inout GameSettings) -> Void) {
        let oldMode = state.settings.trackingMode
        mutate { change(&$0.settings) }
        if state.settings.trackingMode != oldMode { tracker.apply(mode: state.settings.trackingMode) }
    }

    func setAppearance(_ id: String) { mutate { $0.trainer.appearance = id } }

    func setTrainerName(_ name: String) {
        mutate { s in
            let old = s.trainer.name
            s.trainer.name = name
            for i in s.pokemon.indices where s.pokemon[i].otID == s.trainer.trainerID && s.pokemon[i].otName == old {
                s.pokemon[i].otName = name
            }
        }
    }

    func resetGame() {
        tracker.apply(mode: .off)
        state = GameState()
        hasGame = false
        try? FileManager.default.removeItem(at: saveURL)
        pushOutward()
    }

    // MARK: Watch & Live Activity

    var snapshot: WatchSnapshot {
        WatchSnapshot(
            syncDate: state.lastSyncDate,
            expPerStep: state.settings.expPerStep,
            partyShare: state.settings.partyShare,
            lifetimeSteps: state.lifetimeSteps,
            balls: state.totalBalls,
            stepsToEncounter: state.counters.stepsToEncounter,
            stepsToBall: max(0, state.settings.ballSteps - state.counters.ballProgress),
            ballSteps: state.settings.ballSteps,
            pendingEncounters: state.pending.count,
            distanceTodayKm: metersToday / 1000,
            trainerName: state.trainer.name,
            party: state.party.map {
                .init(id: $0.id.uuidString, speciesID: $0.speciesID, name: $0.name, exp: $0.exp,
                      isBuddy: $0.id == state.buddyID, canEvolve: GameRules.pendingEvolution(for: $0) != nil,
                      isShiny: $0.isShiny, gender: $0.gender)
            })
    }

    func pushOutward() {
        let snap = snapshot
        SharedStore.saveSnapshot(snap)
        PhoneConnectivity.shared.send(snap)
        LiveActivityManager.shared.update(with: self)
    }
}

private extension UIApplication.State {
    @MainActor static var current: UIApplication.State { UIApplication.shared.applicationState }
}
