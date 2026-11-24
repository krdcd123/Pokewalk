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
    /// When to rain confetti (the daily stamp).
    @Published var confettiAt: Date?
    @Published var workoutPopup: WorkoutRecord?      // "Workout complete!" card on the map
    @Published var activeEncounter: PendingEncounter?
    /// Set when a pickup notification is tapped: the map opens the Party panel.
    @Published var openPartyAt: Date?
    @Published var evolutionCandidate: EvolutionCandidate?
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
        // One-time: wild Pokémon on walks are shiny 1 in 512 (starters stay fixed at 1 in 8192)
        if !UserDefaults.standard.bool(forKey: "shinyWild512") {
            UserDefaults.standard.set(true, forKey: "shinyWild512")
            mutate { $0.settings.shinyOdds = 512 }
        }
        if !UserDefaults.standard.bool(forKey: "ballSteps1000") {
            UserDefaults.standard.set(true, forKey: "ballSteps1000")
            mutate { $0.settings.ballSteps = 1_000 }
        }
        tracker.onMovement = { [weak self] _ in self?.requestTick(minInterval: 20) }
        tracker.apply(mode: state.settings.trackingMode)
        engine.startLiveUpdates { [weak self] in self?.requestTick(minInterval: 15) }
        startHealthObserver()
        requestTick(minInterval: 0)
        // Heartbeat: while PokéWalk is running (it now stays awake in the background), check for new
        // steps every minute — encounters, items and level-ups notify on time instead of when you open it.
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in GameStore.shared.requestTick(minInterval: 45) }
        }
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
        // Workouts / active calories → money
        let e = HKObserverQuery(sampleType: hk.energyType, predicate: nil) { _, completion, _ in
            Task { @MainActor in
                await GameStore.shared.syncHealthCalories()
                completion()
            }
        }
        hk.store.execute(e)
        hk.store.enableBackgroundDelivery(for: hk.energyType, frequency: .hourly) { _, _ in }
        // Finished workouts → reward + "Workout complete!"
        let w = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, _ in
            Task { @MainActor in
                await GameStore.shared.tick()
                completion()
            }
        }
        hk.store.execute(w)
        hk.store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { _, _ in }
        // Your watch saves last night's sleep a little after you wake: show the morning card as soon as it lands
        let sl = HKObserverQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: nil) { _, completion, _ in
            Task { @MainActor in
                await GameStore.shared.checkPopups()
                completion()
            }
        }
        hk.store.execute(sl)
    }

    /// Today's active calories from Apple Health (workouts included) → ₽1 per 10 kcal, only new ones pay.
    func syncHealthCalories() async {
        guard StepCounter.shared.isAvailable,
              let kcal = try? await StepCounter.shared.activeEnergy(from: Calendar.current.startOfDay(for: .now)),
              kcal > 0 else { return }
        syncCalories(kcal)
    }

    // MARK: New game

    func newGame(trainerName: String, appearance: String, starter: Int, nickname: String?, shiny: Bool = false,
                 gender: Gender? = nil) async {
        let loc = tracker.currentLocation()
        var met: MetLocation?
        if let loc {
            met = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                              placeName: await PlaceService.shared.placeName(for: loc))
        }
        var s = GameRules.newGame(trainerName: trainerName, appearance: appearance, starter: starter,
                                  nickname: nickname, location: met, shiny: shiny, gender: gender)
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
        await checkLure()
        stampToday()                    // past midnight with the app still open: today's stamp
        await syncHealthCalories()
        await processWorkouts()
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
            // Steps from non-walking workouts (cycling, gym…) don't count: the watch counts arm movement as steps.
            let raw = await engine.steps(onDay: day)
            let total = max(0, raw - (await StepCounter.shared.nonWalkingWorkoutSteps(onDay: day)))
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
        // Per-Pokémon news (level ups and pickups), each with that Pokémon's box icon
        var news: [(id: UUID, text: String, pickup: Bool)] = []
        if o.newLevel > o.oldLevel, let buddy = state.buddy {
            news.append((buddy.id, "\(buddy.name) grew to Lv. \(o.newLevel)!", false))
        }
        for up in o.partyLevelUps where up.id != state.buddyID {
            if let mon = state.mon(up.id) { news.append((mon.id, "\(mon.name) grew to Lv. \(up.level)!", false)) }
        }
        for pick in o.pickedUp {
            guard let mon = state.mon(pick.id) else { continue }
            let name = Dex.itemName(pick.item)
            news.append((mon.id, "\(mon.name) picked up \(name.first.map { "AEIOU".contains($0) } == true ? "an" : "a") \(name)!", true))
        }
        if background {
            for n in news {
                let mon = state.mon(n.id)
                notify(title: n.text, body: mon.map { "Lv. \($0.level) · Open PokéWalk to see." } ?? "",
                       id: "\(n.id.uuidString)-\(Int(Date().timeIntervalSince1970))-\(n.text.hashValue)",
                       category: n.pickup ? "pickup" : nil,         // tapping a pickup opens your Party
                       icon: mon.map { ($0.speciesID, $0.isShiny) })
            }
        } else {
            lines += news.map(\.text)
        }
        if !o.itemsFound.isEmpty {
            lines.append("Found " + o.itemsFound.map(Dex.itemName).joined(separator: ", ") + "!")
        }
        if let evo = o.evolutionReady, let mon = state.mon(evo.id) {
            if background {
                notify(title: "What? \(mon.name) is evolving!", body: "Open PokéWalk to watch.", id: "evo",
                       icon: (mon.speciesID, mon.isShiny))
            } else {
                evolutionCandidate = EvolutionCandidate(pokemonID: evo.id, into: evo.into)
            }
        }
        for enc in o.newEncounters {
            if background && state.settings.notifyEncounters {
                let place = enc.location?.placeName.map { " near \($0)" } ?? ""
                notify(title: "A wild \(enc.species.name) appeared!\(enc.isShiny ? " ✨" : "")",
                       body: "Lv. \(enc.level)\(place). Tap to throw a ball.",
                       id: enc.id.uuidString, category: "encounter", icon: (enc.speciesID, enc.isShiny))
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

    /// Posts a notification. `icon` attaches that Pokémon's box sprite (iOS keeps the app icon in the corner;
    /// the sprite shows as the picture on the right).
    private func notify(title: String, body: String, id: String, category: String? = nil, icon: (Int, Bool)? = nil,
                        at date: Date? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = category ?? "pokewalk"
        if let category {
            c.categoryIdentifier = category
            c.userInfo = category == "encounter" ? ["encounterID": id] : ["open": category]
        }
        Task {
            if let (species, shiny) = icon, let file = await SpriteStore.shared.notificationIcon(speciesID: species, shiny: shiny),
               let att = try? UNNotificationAttachment(identifier: "icon", url: file,
                                                       options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]) {
                c.attachments = [att]
            }
            let trigger = date.map {
                UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false)
            }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
        }
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
            s.dexSeen.insert(safari.wild.speciesID)        // met it (fished, lured or walked into) — even if it got away
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

    func reorderParty(_ id: UUID, to index: Int) { mutate { GameRules.reorderParty(id, to: index, in: &$0) } }

    func move(from a: PCSlot, to b: PCSlot) { mutate { GameRules.move(from: a, to: b, in: &$0) } }
    func release(_ id: UUID) { mutate { GameRules.release(id, in: &$0) } }

    @discardableResult
    func sell(_ item: String, count: Int) -> Int {
        var earned = 0
        mutate { earned = GameRules.sell(item, count: count, in: &$0) }
        return earned
    }

    /// Stamps today's box on the weekly stamp card (once a day) and gives that day's reward.
    func stampToday() {
        var result: (day: Int, rewards: [DailyStamps.Reward])?
        mutate { result = DailyStamps.stamp(&$0) }
        guard let result else { return }
        let text = result.day == DailyStamps.days
            ? "Stamp card complete! The present had \(DailyStamps.text(result.rewards))."
            : "Day \(result.day) stamp! Your present had \(DailyStamps.text(result.rewards))."
        // Stamped while PokéWalk was in the background (e.g. woken by steps after midnight):
        // save the celebration for when you open it.
        if UIApplication.State.current != .active {
            UserDefaults.standard.set(text, forKey: "pendingStampText")
            UserDefaults.standard.set(result.day == DailyStamps.days, forKey: "pendingStampComplete")
            return
        }
        celebrateStamp(text, complete: result.day == DailyStamps.days)
    }

    private func celebrateStamp(_ text: String, complete: Bool) {
        confettiAt = .now
        SoundKit.shared.play(complete ? .ballCatch : .useItem)
        toast = text
    }

    /// Plays a stamp celebration that happened while the app was in the background.
    func showPendingStamp() {
        guard let text = UserDefaults.standard.string(forKey: "pendingStampText") else { return }
        let complete = UserDefaults.standard.bool(forKey: "pendingStampComplete")
        UserDefaults.standard.removeObject(forKey: "pendingStampText")
        celebrateStamp(text, complete: complete)
    }

    /// Active calories from Apple Health: ₽1 for every 10 kcal burned today.
    /// The latest total for the day replaces the last one, so only new calories pay out.
    static let pokeDollarsPerKcal = 0.1

    // MARK: Workouts


    private var processingWorkouts = false

    /// Looks for newly finished workouts in Apple Health and rewards them (once each).
    func processWorkouts() async {
        guard hasGame, StepCounter.shared.isAvailable, !processingWorkouts else { return }
        processingWorkouts = true          // several triggers can fire at once; only one check at a time
        defer { processingWorkouts = false }
        removeDuplicateWorkouts()
        removeWorkoutExp()
        let key = "workoutsCountFrom"
        if UserDefaults.standard.object(forKey: key) == nil {
            // First time: today's workouts count, older ones don't.
            UserDefaults.standard.set(Calendar.current.startOfDay(for: .now), forKey: key)
        }
        let from = max(UserDefaults.standard.object(forKey: key) as? Date ?? .now,
                       Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now)
        let known = Set(state.workouts.map(\.id))
        let fresh = await StepCounter.shared.workouts(from: from).filter { !known.contains($0.id) && $0.end <= .now }
        guard !fresh.isEmpty else { return }

        var records: [WorkoutRecord] = []
        for w in fresh {
            let stepsDuring = w.countsSteps ? 0 : ((try? await StepCounter.shared.steps(from: w.start, to: w.end)) ?? 0)
            let exp = 0     // workouts never give Exp themselves; walking/running/hiking earn it through their steps
            records.append(WorkoutRecord(id: w.id, name: w.name, symbol: w.symbol, start: w.start, end: w.end,
                                         kcal: Int(w.kcal.rounded()), meters: w.meters, countsSteps: w.countsSteps,
                                         stepsNotCounted: stepsDuring, money: Int(w.kcal * Self.pokeDollarsPerKcal),
                                         exp: exp, expMonID: nil, levelUp: nil))
        }
        mutate { s in
            for var r in records where !s.workouts.contains(where: { $0.id == r.id }) {
                if r.exp > 0, let bi = s.buddyID.flatMap({ s.index(of: $0) }) {
                    // Exp to the buddy, and the usual party share to everyone else in the party
                    let before = s.pokemon[bi].level
                    s.pokemon[bi].exp = min(s.pokemon[bi].exp + r.exp, s.pokemon[bi].species.growth.maxExp)
                    let after = s.pokemon[bi].level
                    r.expMonID = s.pokemon[bi].id
                    if after > before { r.levelUp = "\(s.pokemon[bi].name) grew to Lv. \(after)!" }
                    let share = Int(Double(r.exp) * s.settings.partyShare)
                    if share > 0 {
                        for pid in s.partyIDs where pid != s.buddyID {
                            if let i = s.index(of: pid) {
                                s.pokemon[i].exp = min(s.pokemon[i].exp + share, s.pokemon[i].species.growth.maxExp)
                            }
                        }
                    }
                }
                s.workouts.append(r)
                s.unseenWorkouts.append(r.id)
            }
            if s.workouts.count > 500 { s.workouts.removeFirst(s.workouts.count - 500) }
        }
        if UIApplication.State.current == .active {
            showWorkoutPopupIfNeeded()
        } else if let r = records.last {
            notify(title: "\(r.name) workout done! 🎉", body: "Open PokéWalk to see what you earned.",
                   id: "workout-\(r.id)", category: nil, icon: state.buddy.map { ($0.speciesID, $0.isShiny) })
        }
    }

    /// Earlier build bug: the same workout could be recorded (and rewarded) more than once.
    /// Keep one of each and take back the extra Exp the copies gave.
    private func removeDuplicateWorkouts() {
        var seen = Set<String>()
        let dupes = state.workouts.filter { !seen.insert($0.id).inserted }
        let unseenDupes = state.unseenWorkouts.count != Set(state.unseenWorkouts).count
        guard !dupes.isEmpty || unseenDupes else { return }
        mutate { s in
            for d in dupes where d.exp > 0 {
                if let id = d.expMonID, let i = s.index(of: id) {
                    s.pokemon[i].exp = max(0, s.pokemon[i].exp - d.exp)
                }
                let share = Int(Double(d.exp) * s.settings.partyShare)
                if share > 0 {
                    for pid in s.partyIDs where pid != d.expMonID {
                        if let i = s.index(of: pid) { s.pokemon[i].exp = max(0, s.pokemon[i].exp - share) }
                    }
                }
            }
            var keep = Set<String>()
            s.workouts = s.workouts.filter { keep.insert($0.id).inserted }
            var keepUnseen = Set<String>()
            s.unseenWorkouts = s.unseenWorkouts.filter { keepUnseen.insert($0).inserted }
        }
        if let p = workoutPopup, !state.unseenWorkouts.contains(p.id) { workoutPopup = nil }
    }

    /// An earlier build gave Exp for non-walking workouts. Take it back (once).
    private func removeWorkoutExp() {
        guard state.workouts.contains(where: { $0.exp > 0 }) else { return }
        mutate { s in
            for k in s.workouts.indices where s.workouts[k].exp > 0 {
                let r = s.workouts[k]
                if let id = r.expMonID, let i = s.index(of: id) {
                    s.pokemon[i].exp = max(0, s.pokemon[i].exp - r.exp)
                }
                let share = Int(Double(r.exp) * s.settings.partyShare)
                if share > 0 {
                    for pid in s.partyIDs where pid != r.expMonID {
                        if let i = s.index(of: pid) { s.pokemon[i].exp = max(0, s.pokemon[i].exp - share) }
                    }
                }
                s.workouts[k].exp = 0
                s.workouts[k].levelUp = nil
            }
        }
    }

    // MARK: Popups (also while the app just stays open)

    private var popupTimer: Timer?
    private var heartbeat: Timer?

    /// Everything that can pop up: today's stamp (from 7am), evolutions, workouts, the morning sleep card,
    /// and sleep listening. Runs when the app opens and then every 30 seconds while it's on screen,
    /// so nothing waits for the app to be closed and reopened.
    func checkPopups() async {
        guard hasGame, UIApplication.State.current == .active else { return }
        stampToday()
        showPendingStamp()
        if evolutionCandidate == nil { checkPendingEvolutions() }
        showWorkoutPopupIfNeeded()
        await SleepService.shared.refresh(showPopup: workoutPopup == nil && evolutionCandidate == nil)
        if let note = await SleepRecorder.shared.autoStartOrStop() { toast = note }
    }

    func startPopupChecks() {
        popupTimer?.invalidate()
        popupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in await GameStore.shared.checkPopups() }
        }
    }

    func stopPopupChecks() {
        popupTimer?.invalidate()
        popupTimer = nil
    }

    /// Shows the next "Workout complete!" card, with confetti and the candy sound.
    func showWorkoutPopupIfNeeded() {
        guard workoutPopup == nil, let id = state.unseenWorkouts.first else { return }
        guard let r = state.workouts.first(where: { $0.id == id }) else {
            mutate { $0.unseenWorkouts.removeAll { $0 == id } }
            return
        }
        workoutPopup = r
        confettiAt = .now
        SoundKit.shared.play(.useItem)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func dismissWorkoutPopup() {
        guard let r = workoutPopup else { return }
        workoutPopup = nil
        mutate { $0.unseenWorkouts.removeAll { $0 == r.id } }
        // another one waiting? show it after a moment
        if !state.unseenWorkouts.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                showWorkoutPopupIfNeeded()
            }
        }
    }

    /// Active calories burned today (from Apple Health), as last synced.
    var caloriesToday: Int { state.caloriesDay == DailyStamps.key(.now) ? Int(state.caloriesPaid.rounded()) : 0 }

    @discardableResult
    func syncCalories(_ total: Double) -> Int {
        var earned = 0, gained = 0.0
        mutate { s in
            let today = DailyStamps.key(.now)
            if s.caloriesDay != today { s.caloriesDay = today; s.caloriesPaid = 0 }
            let t = max(0, total)
            guard t > s.caloriesPaid else { return }
            earned = Int(t * Self.pokeDollarsPerKcal) - Int(s.caloriesPaid * Self.pokeDollarsPerKcal)
            gained = t - s.caloriesPaid
            s.lifetimeCalories += gained
            s.caloriesPaid = t
            s.money += earned
        }
        // a toast only for a real chunk (a workout), not every few calories through the day
        if earned >= 10 {
            toast = "Burned \(Int(gained.rounded())) kcal — you earned ₽\(earned)!"
        }
        return earned
    }

    func buyFishingRod() -> Bool {
        guard (state.bag[Fishing.rodKey] ?? 0) == 0, state.money >= Fishing.rodPrice else { return false }
        mutate { s in
            s.money -= Fishing.rodPrice
            s.bag[Fishing.rodKey] = 1
        }
        return true
    }

    func makeBait(berries n: Int, lure: Bool = false) -> Bool {
        var ok = false
        mutate { ok = Fishing.makeBait(berries: n, lure: lure, in: &$0) }
        return ok
    }

    func makeBait(using picks: [String: Int], lure: Bool) -> Bool {
        var ok = false
        mutate { ok = Fishing.makeBait(using: picks, lure: lure, in: &$0) }
        return ok
    }

    /// Buys a ready-made bait or lure at the Poké Mart.
    func buyBaitOrLure(_ key: String) -> Bool {
        guard let price = Fishing.price(key), state.money >= price else { return false }
        mutate { s in
            s.money -= price
            s.bag[key, default: 0] += 1
        }
        return true
    }

    /// Sets a lure going (one at a time): in 30 minutes it attracts a wild Pokémon.
    func useLure(_ key: String) -> Bool {
        guard state.activeLure == nil, let n = Fishing.lureBerries(key), (state.bag[key] ?? 0) > 0 else { return false }
        let now = Date()
        mutate { s in
            s.bag[key, default: 0] -= 1
            if s.bag[key] == 0 { s.bag[key] = nil }
            s.activeLure = ActiveLure(berries: n, startedAt: now, endsAt: now.addingTimeInterval(Fishing.lureDuration))
        }
        notify(title: "Your lure is ready!", body: "Something was attracted by your \(Fishing.lureName(berries: n)). Open PokéWalk to see.",
               id: "lure", at: now.addingTimeInterval(Fishing.lureDuration))
        return true
    }

    /// When the lure's time is up: brings the rarest of a few candidate Pokémon (more berries, more candidates,
    /// higher level) into your wild encounters.
    func checkLure() async {
        guard let lure = state.activeLure, Date() >= lure.endsAt else { return }
        let loc = tracker.currentLocation()
        var context = EncounterContext(habitats: await PlaceService.shared.habitats(near: loc),
                                       isNight: TimeOfDay.at(.now) == .night)
        if let loc {
            context.location = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                                           placeName: await PlaceService.shared.placeName(for: loc))
        }
        guard state.activeLure == lure else { return }        // already handled while we were looking
        let candidates = (0..<Fishing.lurePicks(berries: lure.berries)).map { _ in
            GameRules.generateEncounter(context: context, lifetimeSteps: state.lifetimeSteps, settings: state.settings)
        }
        guard var enc = candidates.min(by: { GameRules.rarityWeight($0.species) < GameRules.rarityWeight($1.species) })
        else { return }
        enc.level = min(100, enc.level + Fishing.lureLevelBonus(berries: lure.berries))
        mutate { s in
            s.activeLure = nil
            s.pending.append(enc)
        }
        toast = "Your lure attracted a wild \(enc.species.name)!\(enc.isShiny ? " ✨" : "") It's in your encounters."
    }

    func fish(with bait: String) -> Fishing.Result {
        var result = Fishing.Result.notReady
        let here = tracker.currentLocation().map {
            MetLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        mutate { result = Fishing.cast(bait: bait, in: &$0, location: here) }
        return result
    }

    func buy(_ ball: BallKind, count: Int) -> Bool {
        var ok = false
        mutate { ok = GameRules.buy(ball, count: count, in: &$0) }
        return ok
    }

    /// Wild Pokémon that have run off (their time ran out) leave the list straight away, even without new steps.
    func pruneExpiredEncounters() {
        guard state.pending.contains(where: { $0.expiresAt <= .now }) else { return }
        mutate { $0.pending.removeAll { $0.expiresAt <= .now } }
    }

    /// Uses up one of an item from the Bag (e.g. a berry thrown in a wild encounter).
    @discardableResult
    func consume(_ item: String) -> Bool {
        guard (state.bag[item] ?? 0) > 0 else { return false }
        mutate { s in
            s.bag[item, default: 0] -= 1
            if s.bag[item] == 0 { s.bag[item] = nil }
        }
        return true
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
                      isShiny: $0.isShiny, gender: $0.gender, heldItem: $0.heldItems.first, stepsWalked: $0.stepsWalked)
            },
            bag: watchBag,
            wild: state.pending.filter { $0.expiresAt > .now }.map {
                .init(id: $0.id.uuidString, speciesID: $0.speciesID, level: $0.level, isShiny: $0.isShiny, expiresAt: $0.expiresAt)
            },
            latitude: tracker.currentLocation()?.coordinate.latitude,
            longitude: tracker.currentLocation()?.coordinate.longitude,
            money: state.money,
            trail: watchTrail)
    }

    /// Today's route for the watch map, thinned to about 300 points in total.
    private var watchTrail: [WatchSnapshot.TrailSegment] {
        // split each recorded segment where it switches between walking and driving
        var parts: [(drive: Bool, pts: [TrackPoint])] = []
        for seg in TrackStore.shared.today {
            for p in seg {
                if let last = parts.last, last.drive == p.isDrive, !last.pts.isEmpty { parts[parts.count - 1].pts.append(p) }
                else { parts.append((p.isDrive, [p])) }
            }
            parts.append((false, []))     // segment break
        }
        parts.removeAll { $0.pts.count < 2 }
        let total = parts.reduce(0) { $0 + $1.pts.count }
        let stride = max(1, total / 300)
        return parts.map { part in
            var kept: [TrackPoint] = []
            for (i, p) in part.pts.enumerated() where i % stride == 0 || i == part.pts.count - 1 { kept.append(p) }
            return .init(drive: part.drive, coords: kept.flatMap { [$0.lat, $0.lon] })
        }
    }

    /// The Bag, condensed for the watch: balls, then berries, then everything else.
    private var watchBag: [WatchSnapshot.BagLine] {
        let balls = BallKind.allCases.compactMap { k -> WatchSnapshot.BagLine? in
            let n = state.balls[k, default: 0]
            return n > 0 ? .init(key: k.itemKey, name: k.name, count: n, pocket: "Balls") : nil
        }
        let rest = state.bag.filter { $0.value > 0 }.map { k, n in
            WatchSnapshot.BagLine(key: k, name: Dex.itemName(k), count: n,
                                  pocket: ItemCatalog.isBerry(k) ? "Berries" : k == Fishing.rodKey ? "Key items" : "Items")
        }
        let order = ["Berries": 0, "Items": 1, "Key items": 2]
        return balls + rest.sorted { (order[$0.pocket] ?? 9, $0.name) < (order[$1.pocket] ?? 9, $1.name) }
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
