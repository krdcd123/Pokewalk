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
    @Published var hatching: OwnedPokemon?           // Egg hatching on the map
    var hatchQueue: [UUID] = []
    @Published var activeEncounter: PendingEncounter?
    /// Set when a pickup notification is tapped: the map opens the Party panel.
    @Published var openPartyAt: Date?
    /// A Garden or Ranch notification was tapped: open that tab of Activities.
    @Published var openActivity: String?
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

    /// Saving used to encode and write the whole game, rebuild the watch snapshot and redraw the Live Activity on
    /// every single change — a step sync makes many changes in a row, which kept the CPU busy (heat, battery).
    /// Now changes in quick succession are saved together a moment later, and the encoding + disk write happen
    /// off the main thread. Nothing is lost: it saves immediately in the background, and when the app leaves the screen.
    private var saveWork: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "pokewalk.save", qos: .utility)

    private func save() {
        saveWork?.cancel()
        // In the background iOS may suspend us at any moment: write straight away
        if UIApplication.shared.applicationState == .background { saveNow(); return }
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    /// Writes any pending changes now (called when the app goes to the background).
    func saveNow() {
        saveWork?.cancel(); saveWork = nil
        let copy = state, url = saveURL
        saveQueue.async {
            if let data = try? JSONEncoder().encode(copy) { try? data.write(to: url, options: .atomic) }
        }
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
        // reading every day's track and encoding it all is the heaviest save there is: do it off the main thread
        TrackStore.shared.flush()
        let copy = state, box = storage, url = autoBackupURL, dir = TrackStore.shared.directory
        saveQueue.async {
            let tracks = TrackStore.readAllDays(in: dir)
            if let data = try? JSONEncoder().encode(SaveFile(state: copy, tracks: tracks, storage: box)) {
                try? data.write(to: url, options: .atomic)
            }
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
        migrateGardenToOnePerPatch()
        // Pokémon working in the Garden / Ranch don't sit in a PC box
        mutate { s in for id in s.garden.workers + s.ranch.ranchers + s.daycare.parents { GameRules.takeOutOfBox(id, in: &s) } }
        finishRanchProjectIfDone()
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
                await GameStore.shared.sleepArrived()
                completion()
            }
        }
        hk.store.execute(sl)
        // wake PokéWalk the moment new sleep lands in Health, even in the background
        hk.store.enableBackgroundDelivery(for: HKCategoryType(.sleepAnalysis), frequency: .immediate) { _, _ in }
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

    /// When the current step check started: if one ever gets stuck waiting on Health / motion data, the next
    /// one carries on after 2 minutes instead of steps freezing until the app is force closed.
    private var tickStartedAt = Date.distantPast
    /// Steps taken off today for non-walking workouts (shown in Settings › Step sync).
    @Published private(set) var workoutStepsToday = 0

    /// Today's step count on the map: your real total (Apple Health / watch / iPhone, whichever is highest)
    /// minus steps your watch counted during non-walking workouts. Runs on its own so it always updates.
    func refreshStepsToday() async {
        let today = Calendar.current.startOfDay(for: .now)
        let raw = await engine.steps(onDay: today)
        let workout = min(raw, await StepCounter.shared.nonWalkingWorkoutSteps(onDay: today))
        workoutStepsToday = workout
        stepsToday = max(0, raw - workout)
    }

    func tick() async {
        guard hasGame else { return }
        await refreshStepsToday()
        if ticking && Date().timeIntervalSince(tickStartedAt) > 120 { ticking = false }
        guard !ticking else { return }
        await checkLure()
        stampToday()                    // past midnight with the app still open: today's stamp
        await syncHealthCalories()
        await processWorkouts()
        ticking = true
        tickStartedAt = .now
        defer { ticking = false; lastTick = .now }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var ledger = state.stepLedger
        var newSteps = 0

        let gameExisted = !ledger.isEmpty
        let startedDay = cal.startOfDay(for: state.trainer.startedOn)
        // Cycling right now (or since the last check)? Then new steps are your arms, not walking: no rewards.
        // …or in a PokéWalk workout that isn't walking (cycling, swimming, gym…): rewards pause for all of it
        let detectedCycling = await CyclingDetector.cycling(since: lastTick)
        let cyclingNow = PhoneWorkout.shared.pausesSteps || detectedCycling
        var skippedNow: [String: Int] = [:]
        for day in [yesterday, today] {
            let key = TrackStore.key(for: day)
            // Steps from non-walking workouts (cycling, gym…) don't count: the watch counts arm movement as steps.
            // Steps already left out live (while cycling) aren't taken off a second time.
            let raw = await engine.steps(onDay: day)
            let workout = await StepCounter.shared.nonWalkingWorkoutSteps(onDay: day)
            let skipped = state.cyclingSkipped[key] ?? 0
            let total = max(0, raw - max(0, workout - skipped))
            // Today's step count is your real total (same as Apple Health / your watch) minus steps the watch counted
            // during non-walking workouts. Steps left out of rewards while cycling don't lower it again.
            if day == today { stepsToday = max(0, raw - min(raw, workout)); workoutStepsToday = min(raw, workout) }
            // Days we haven't seen yet count from midnight, unless they're before the game started.
            let processed = ledger[key] ?? ((gameExisted && day >= startedDay) ? 0 : total)
            ledger[key] = max(processed, total)
            guard total > processed else { continue }
            if cyclingNow && day == today {
                skippedNow[key] = total - processed          // counted as done, but no rewards
            } else {
                newSteps += total - processed
            }
        }
        if !skippedNow.isEmpty {
            for (k, n) in skippedNow { state.cyclingSkipped[k, default: 0] += n }
            state.cyclingSkipped = state.cyclingSkipped.filter { k, _ in ledger[k] != nil }
        }
        // Keep the ledger small.
        let keep = Set([yesterday, today].map { TrackStore.key(for: $0) })
        ledger = ledger.filter { keep.contains($0.key) }
        metersToday = await engine.distanceToday()
        // Distance since last sync goes to the buddy (counted the same way as steps).
        let todayKey = TrackStore.key(for: today)
        let creditedMeters = state.distanceLedger[todayKey] ?? 0
        // Distance while cycling doesn't go to your buddy either
        let newMeters = cyclingNow ? 0 : max(0, metersToday - creditedMeters)
        if cyclingNow { state.distanceLedger[todayKey] = max(creditedMeters, metersToday) }

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
        // Pickups always come as a normal notification (a banner even with the app open), never just a toast.
        let alwaysNotify = news.filter(\.pickup)
        if !background { news.removeAll(where: \.pickup) }
        for n in background ? [] : alwaysNotify {
            let mon = state.mon(n.id)
            notify(title: n.text, body: mon.map { "Lv. \($0.level) · Tap to see your party." } ?? "",
                   id: "\(n.id.uuidString)-\(Int(Date().timeIntervalSince1970))-\(n.text.hashValue)",
                   category: "pickup", icon: mon.map { ($0.speciesID, $0.isShiny) })
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
        // Daycare
        if o.eggFound {
            notify(title: "The Daycare found an Egg! 🥚", body: "Pick it up from the Daycare and carry it to hatch it.",
                   id: "egg-found-\(Int(Date().timeIntervalSince1970))", category: nil)
        }
        for mon in o.hatched {
            hatchQueue.append(mon.id)
            notify(title: "Oh? Your Egg is hatching!", body: "Open PokéWalk to see what came out.",
                   id: "hatch-\(mon.id.uuidString)", category: nil)
        }
        if !o.hatched.isEmpty && !background { showHatchIfNeeded() }
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
                // Only named (with its picture) if you've caught that species before; otherwise it's a mystery
                let known = state.dexCaught.contains(enc.speciesID)
                notify(title: "A wild \(known ? enc.species.name : "???") appeared!\(enc.isShiny ? " ✨" : "")",
                       body: "Lv. \(enc.level)\(place). Tap to throw a ball.",
                       id: enc.id.uuidString, category: "encounter",
                       icon: known ? (enc.speciesID, enc.isShiny) : nil)
            }
        }
        if !o.newEncounters.isEmpty && !background {
            lines.append(o.newEncounters.count == 1
                         ? "A wild \(state.dexCaught.contains(o.newEncounters[0].speciesID) ? o.newEncounters[0].species.name : "???") appeared!"
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
        markOpened(enc.id)
    }

    // MARK: Battle Frontier

    func refreshFrontier() {
        var t = state
        FrontierRules.refresh(&t)
        if t.frontier != state.frontier { mutate { FrontierRules.refresh(&$0) } }
    }

    /// Records a Gym Challenge / Battle Frontier battle. Returns the reward if won. Three losses a day and you're done.
    func finishFrontierBattle(_ battle: Int, trainer: FrontierTrainer, mode: FrontierRules.Mode = .gym, won: Bool) -> FrontierRules.Reward? {
        refreshFrontier()
        let f = state.frontier
        guard f.won(mode) == battle - 1, !f.done(mode) else { return nil }
        guard won else {
            let limit = FrontierRules.maxLosses(mode, state)
            mutate { s in
                if mode == .gym {
                    s.frontier.losses += 1
                    if s.frontier.losses >= limit { s.frontier.lost = true }
                } else {
                    s.frontier.fLosses += 1
                    if s.frontier.fLosses >= limit { s.frontier.fLost = true }
                }
            }
            return nil
        }
        let r = FrontierRules.reward(for: battle, trainer: trainer, mode: mode, in: state)
        let leaderKey: String? = trainer.isLeader ? FrontierRules.everyLeader.first(where: { "leader_" + $0.key == trainer.pic })?.key : nil
        let region = FrontierRules.region(state).rawValue
        mutate { s in
            if mode == .gym { s.frontier.won = battle } else { s.frontier.fWon = battle }
            s.frontier.totalWins += 1
            s.stats["frontierWins", default: 0] += 1
            s.frontier.bp += r.bp
            s.frontier.bpEarned += r.bp
            if let key = leaderKey {
                if !s.frontier.leadersBeaten.contains(key) { s.frontier.leadersBeaten.append(key) }
                if !s.frontier.badges.contains(key) { s.frontier.badges.append(key) }
            }
            if trainer.isChampion, !s.frontier.symbols.contains(trainer.name) { s.frontier.symbols.append(trainer.name) }
            if trainer.isChampion, mode == .gym, !s.frontier.champions.contains(region) { s.frontier.champions.append(region) }
            if trainer.isChampion { s.stats["championWins", default: 0] += 1 }
            // battling raises friendship a little
            for id in s.partyIDs { if let i = s.index(of: id) { s.pokemon[i].friendship = min(255, s.pokemon[i].friendship + 1) } }
        }
        return r
    }

    func startContestProject() -> Bool {
        guard ContestRules.canStart(state), state.contests.building == nil, let p = state.contests.nextProject,
              canAfford(p) else { return false }
        let end = Date().addingTimeInterval(p.hours * 3600)
        mutate { s in
            s.money -= p.money
            for (m, n) in p.cost { s.ranch.materials[m.rawValue, default: 0] -= n }
            s.contests.building = RanchBuild(project: p.id, startedAt: .now, endsAt: end)
        }
        notify(title: "\(p.name) is finished! 🎀", body: "Come and see the Contest Hall — \(p.reward).",
               id: "contest-build", category: nil, at: end)
        return true
    }

    @discardableResult
    func finishContestProjectIfDone() -> RanchProject? {
        guard let b = state.contests.building, b.endsAt <= .now,
              let p = ContestRules.projects.first(where: { $0.id == b.project }) else { return nil }
        mutate { s in
            s.contests.building = nil
            s.contests.built = max(s.contests.built, p.id + 1)
        }
        return p
    }

    func startFrontierProject() -> Bool {
        guard FrontierRules.canBuild(state), state.frontier.building == nil, let p = state.frontier.nextProject,
              canAfford(p) else { return false }
        let end = Date().addingTimeInterval(p.hours * 3600)
        mutate { s in
            s.money -= p.money
            for (m, n) in p.cost { s.ranch.materials[m.rawValue, default: 0] -= n }
            s.frontier.building = RanchBuild(project: p.id, startedAt: .now, endsAt: end)
        }
        notify(title: "\(p.name) is finished! 🏆", body: "Come and see the Battle Frontier — \(p.reward).",
               id: "frontier-build", category: nil, at: end)
        return true
    }

    @discardableResult
    func finishFrontierProjectIfDone() -> RanchProject? {
        guard let b = state.frontier.building, b.endsAt <= .now,
              let p = FrontierRules.projects.first(where: { $0.id == b.project }) else { return nil }
        mutate { s in
            s.frontier.building = nil
            s.frontier.built = max(s.frontier.built, p.id + 1)
        }
        return p
    }

    // MARK: Contests

    func blend(_ c: ContestCategory?) -> Bool {
        var ok = false
        mutate { ok = ContestRules.blend(c, in: &$0) }
        return ok
    }

    func feedBlock(_ block: String, to id: UUID) -> Bool {
        var ok = false
        mutate { ok = ContestRules.feed(block, to: id, in: &$0) }
        return ok
    }

    /// Records a contest result (place 1–4). Returns the prize text if it won.
    func finishContest(_ mon: UUID, _ c: ContestCategory, _ r: ContestRank, place: Int) -> String? {
        var prize: String?
        mutate { s in
            s.contests.entered += 1
            s.stats["contestsEntered", default: 0] += 1
            guard place == 1 else { return }
            s.contests.wins += 1
            s.stats["contestWins", default: 0] += 1
            let ribbon = "\(c.rawValue)-\(r.rawValue)"
            let firstMaster = r == .master && !s.contests.ribbons.values.contains { $0.contains(ribbon) }
            if !s.contests.ribbons(mon).contains(ribbon) { s.contests.ribbons[mon.uuidString, default: []].append(ribbon) }
            s.money += r.prize
            var text = "\(c.name) Ribbon (\(r.name) Rank) · ₽\(r.prize.formatted())"
            if firstMaster, let doll = ContestRules.masterPrizes[c] {
                s.ranch.decor[doll, default: 0] += 1
                text += " · \(RanchDecor.find(doll)?.name ?? "a doll") for your house"
            }
            prize = text
        }
        return prize
    }

    // MARK: Daycare

    func showHatchIfNeeded() {
        guard hatching == nil, workoutPopup == nil, evolutionCandidate == nil, !hatchQueue.isEmpty else { return }
        let id = hatchQueue.removeFirst()
        hatching = state.mon(id)
    }

    func dismissHatch() {
        hatching = nil
        SoundKit.shared.play(.select)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            showHatchIfNeeded()
        }
    }

    var daycareParents: [OwnedPokemon] { state.daycare.parents.compactMap { state.mon($0) } }

    func leaveAtDaycare(_ id: UUID) {
        guard state.daycare.open, state.boxedIDs.contains(id), state.daycare.parents.count < 2 else { return }
        mutate { s in
            s.daycare.parents.append(id)
            s.daycare.eggProgress = 0
            GameRules.takeOutOfBox(id, in: &s)
        }
    }

    func takeFromDaycare(_ id: UUID) {
        mutate { s in
            s.daycare.parents.removeAll { $0 == id }
            GameRules.returnToBox(id, in: &s)
        }
    }

    /// Picks up the waiting Egg into your basket.
    func collectEgg() -> Bool {
        guard let egg = state.daycare.waiting, state.daycare.basket.count < Daycare.basketSize else { return false }
        mutate { s in
            s.daycare.basket.append(egg)
            s.daycare.waiting = nil
        }
        return true
    }

    func startDaycareProject() -> Bool {
        guard DaycareRules.canStart(state), state.daycare.building == nil, let p = state.daycare.nextProject,
              canAfford(p) else { return false }
        let end = Date().addingTimeInterval(p.hours * 3600)
        mutate { s in
            s.money -= p.money
            for (m, n) in p.cost { s.ranch.materials[m.rawValue, default: 0] -= n }
            s.daycare.building = RanchBuild(project: p.id, startedAt: .now, endsAt: end)
        }
        notify(title: "\(p.name) is finished! 🥚", body: "Come and see the Daycare — \(p.reward).",
               id: "daycare-build", category: nil, at: end)
        return true
    }

    @discardableResult
    func finishDaycareProjectIfDone() -> RanchProject? {
        guard let b = state.daycare.building, b.endsAt <= .now,
              let p = DaycareRules.projects.first(where: { $0.id == b.project }) else { return nil }
        mutate { s in
            s.daycare.building = nil
            s.daycare.built = max(s.daycare.built, p.id + 1)
            if p.id == 3 { s.bag["oval-charm", default: 0] += 1 }
        }
        return p
    }

    func claimAchievement(_ a: Achievement) -> Bool {
        var ok = false
        mutate { ok = Achievements.claim(a, in: &$0) }
        return ok
    }

    func buyItem(_ key: String, price: Int) -> Bool {
        guard state.money >= price else { return false }
        mutate { s in s.money -= price; s.bag[key, default: 0] += 1 }
        return true
    }

    /// Uses a Repel, herb, flute, Honey, Revive… from the Bag.
    func useFieldItem(_ key: String) async -> FieldItems.UseResult {
        let loc = tracker.currentLocation()
        var context = EncounterContext(habitats: await PlaceService.shared.habitats(near: loc),
                                       isNight: TimeOfDay.at(.now) == .night)
        if let loc {
            context.location = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                                           placeName: await PlaceService.shared.placeName(for: loc))
        }
        var r = FieldItems.UseResult.nothing("")
        mutate { s in r = FieldItems.use(key, in: &s, context: context, location: context.location) }
        switch r {
        case .appeared(let enc): toast = "A wild \(state.dexCaught.contains(enc.speciesID) ? enc.species.name : "Pokémon") appeared!"
        case .started: toast = "\(Dex.itemName(key)) is working!"
        case .nothing(let why): toast = why
        }
        return r
    }

    /// Ball Fetch: after a ball misses, the buddy sometimes brings it back.
    func ballFetch(_ kind: BallKind) {
        guard state.buddyAbility == .ballFetch, Double.random(in: 0..<1) < 0.3, let b = state.buddy else { return }
        mutate { $0.balls[kind, default: 0] += 1 }
        toast = "\(b.name) fetched your \(kind.name) back!"
    }

    func useBall(_ kind: BallKind) -> Bool {
        guard state.balls[kind, default: 0] > 0 else { return false }
        mutate { $0.balls[kind, default: 0] -= 1; $0.stats["ballsThrown", default: 0] += 1 }
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
            if w.speciesID == Swarm.species(w.appearedAt).id { s.stats["swarmCaught", default: 0] += 1 }
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

    /// Active calories from Apple Health: ₽1 for every 4 kcal burned today.
    /// The latest total for the day replaces the last one, so only new calories pay out.
    static let pokeDollarsPerKcal = 0.25

    /// On top of the calories: finishing a workout pays ₽50 + ₽5 a minute (up to ₽1,000).
    static func workoutBonus(minutes: Double) -> Int { min(1_000, 50 + Int(minutes * 5)) }

    private func day0StepsChanged(_ m: [String: Int]) -> Bool { !m.isEmpty }

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
                                         stepsNotCounted: stepsDuring,
                                         money: Int(w.kcal * Self.pokeDollarsPerKcal) + Self.workoutBonus(minutes: w.end.timeIntervalSince(w.start) / 60),
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
                s.money += Int(Double(Self.workoutBonus(minutes: r.end.timeIntervalSince(r.start) / 60))
                               * FieldItems.multiplier(.money, in: s))     // the calories pay separately
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
    /// New sleep from the watch / Apple Health. App open → the morning card straight away. In the background →
    /// a "Good morning" notification at once (tap it and the card is waiting).
    func sleepArrived() async {
        if UIApplication.State.current == .active { await checkPopups(forceSleep: true); return }
        guard hasGame else { return }
        await SleepService.shared.refresh(showPopup: false)
        guard let n = SleepService.shared.lastNight else { return }
        let day = Int(n.day.timeIntervalSince1970)
        let since = Date().timeIntervalSince(n.wake)
        let hour = Calendar.current.component(.hour, from: .now)
        let wait: TimeInterval = n.source == "Apple Watch" ? 0 : 10 * 60
        guard since >= wait, since < 14 * 3600, hour >= 5,
              !UserDefaults.standard.bool(forKey: "sleepShown-\(day)"),
              !UserDefaults.standard.bool(forKey: "sleepNotified-\(day)") else { return }
        UserDefaults.standard.set(true, forKey: "sleepNotified-\(day)")
        notify(title: "Good morning! ☀️",
               body: "You slept \(SleepFormat.hm(n.asleep)) (\(SleepFormat.time(n.bedtime))–\(SleepFormat.time(n.wake))). Tap to see last night.",
               id: "sleep-\(day)")
    }

    /// Last time sleep was re-read (it reads Health + a week of motion data, so not every 30 s).
    private var lastSleepRefresh = Date.distantPast

    func checkPopups(forceSleep: Bool = false) async {
        guard hasGame, UIApplication.State.current == .active else { return }
        stampToday()
        showPendingStamp()
        if evolutionCandidate == nil { checkPendingEvolutions() }
        showWorkoutPopupIfNeeded()
        showHatchIfNeeded()
        if let p = finishRanchProjectIfDone() { toast = "The \(p.name) at your ranch is finished!" }
        if let p = finishDaycareProjectIfDone() { toast = "The \(p.name) at the Daycare is finished!" }
        // Mornings (5am–1pm, when the good-morning card can appear) check every minute, otherwise every 5
        let hour = Calendar.current.component(.hour, from: .now)
        let every: TimeInterval = (5..<13).contains(hour) ? 60 : 300
        if forceSleep || Date().timeIntervalSince(lastSleepRefresh) >= every {
            lastSleepRefresh = .now
            await SleepService.shared.refresh(showPopup: workoutPopup == nil && evolutionCandidate == nil)
        }
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
        SoundKit.shared.play(.select)
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

    /// You opened this wild Pokémon (saw it up close): if it later leaves, the Journal shows it, not a silhouette.
    func markOpened(_ id: UUID) {
        guard !state.openedEncounters.contains(id) else { return }
        mutate { s in
            s.openedEncounters.append(id)
            if s.openedEncounters.count > 100 { s.openedEncounters.removeFirst(s.openedEncounters.count - 100) }
        }
    }

    /// Buys an evolution item for its (steep) price.
    func buyEvolutionItem(_ key: String) -> Bool {
        guard EvolutionShop.isEvolutionItem(key), state.money >= EvolutionShop.price else { return false }
        mutate { s in
            s.money -= EvolutionShop.price
            s.bag[key, default: 0] += 1
        }
        return true
    }

    /// Cheaper, but you get a random evolution item. Returns which one.
    func buyMysteryEvolutionItem() -> String? {
        guard state.money >= EvolutionShop.mysteryPrice, let key = EvolutionShop.items.randomElement() else { return nil }
        mutate { s in
            s.money -= EvolutionShop.mysteryPrice
            s.bag[key, default: 0] += 1
        }
        return key
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
            s.activeLure = ActiveLure(berries: n, flavor: Fishing.flavor(key), startedAt: now, endsAt: now.addingTimeInterval(Fishing.lureDuration))
        }
        notify(title: "Your lure is ready!", body: "Something was attracted by your \(Fishing.name(key) ?? "lure"). Open PokéWalk to see.",
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
        context.favouredTypes = lure.flavor?.lureTypes ?? []
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
        mutate { s in
            result = Fishing.cast(bait: bait, in: &s, location: here)
            if case .bite = result { s.stats["fishHooked", default: 0] += 1 }
        }
        return result
    }

    /// The BP counter: Frontier Battle Points for items and special balls.
    func buyWithBP(_ e: BPShop.Entry, count: Int = 1) -> Bool {
        var ok = false
        mutate { ok = BPShop.buy(e, count: count, in: &$0) }
        return ok
    }

    func buy(_ ball: BallKind, count: Int) -> Bool {
        var ok = false
        mutate { ok = GameRules.buy(ball, count: count, in: &$0) }
        return ok
    }

    /// Wild Pokémon that have run off (their time ran out) leave the list straight away, even without new steps.
    func pruneExpiredEncounters() {
        guard state.pending.contains(where: { $0.expiresAt <= .now }) else { return }
        mutate { s in
            GameRules.logLeft(s.pending.filter { $0.expiresAt <= .now }, in: &s)
            s.pending.removeAll { $0.expiresAt <= .now }
        }
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
                .init(id: $0.id.uuidString, speciesID: $0.speciesID, level: $0.level, isShiny: $0.isShiny, expiresAt: $0.expiresAt,
                      caughtBefore: state.dexCaught.contains($0.speciesID))
            },
            latitude: tracker.currentLocation()?.coordinate.latitude,
            longitude: tracker.currentLocation()?.coordinate.longitude,
            money: state.money,
            trail: watchTrail,
            garden: watchGarden,
            activities: watchActivities)
    }

    /// Ranch / Daycare / Frontier / Contests summary for the watch.
    private var watchActivities: WatchSnapshot.Activities {
        let s = state
        var a = WatchSnapshot.Activities()
        a.ranchBuilt = s.ranch.built
        a.ranchTotal = RanchProject.all.count
        a.materials = s.ranch.materials
        a.ranchers = ranchWorkers.map(\.speciesID)
        a.slots = s.ranch.slots
        a.shiftStart = s.ranch.shiftStart
        a.shiftEnd = s.ranch.shiftEnd
        if let b = s.ranch.building { a.buildName = RanchProject.all.first { $0.id == b.project }?.name; a.buildEnds = b.endsAt }
        a.nextProject = s.ranch.nextProject?.name
        a.daycareOpen = s.daycare.open
        let parents = daycareParents
        a.parents = parents.map(\.speciesID)
        if parents.count == 2 { a.compatibility = DaycareRules.compatibilityText(DaycareRules.compatibility(parents[0], parents[1])) }
        a.eggWaiting = s.daycare.waiting != nil
        a.eggs = s.daycare.basket.map { [max(0, $0.stepsLeft), $0.total] }
        a.hatched = s.daycare.hatched
        a.frontierWon = s.frontier.day == FrontierRules.today() ? s.frontier.won : 0
        a.frontierLost = s.frontier.day == FrontierRules.today() && s.frontier.lost
        a.badges = s.frontier.badges.count
        a.leaderToday = FrontierRules.isLeagueDay(s) ? "Pokémon League" : FrontierRules.nextLeader(s)?.name ?? "Gym rematch"
        a.contestWins = s.contests.wins
        a.ribbons = s.contests.ribbons.values.reduce(0) { $0 + $1.count }
        a.season = Season.at().name
        a.swarm = Swarm.species().id
        return a
    }

    /// Open garden patches for the watch.
    private var watchGarden: [WatchSnapshot.GardenSpot] {
        let b = gardenBonuses
        return (0..<(state.garden.fields * Garden.plotsPerField)).filter(gardenPlotOpen).map { id in
            let p = gardenPlot(id)
            return .init(id: id, berry: p.berry, plantedAt: p.plantedAt, readyAt: GardenRules.readyAt(p, bonuses: b))
        }
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

// MARK: - Berry Garden

extension GameStore {
    /// Box Pokémon working in the garden (anyone moved into your party stops working).
    var gardenWorkers: [OwnedPokemon] {
        state.garden.workers.compactMap { state.mon($0) }.filter { !state.partyIDs.contains($0.id) }
    }
    var gardenBonuses: GardenBonuses { GardenRules.bonuses(workers: gardenWorkers) }
    /// Open patches in the first garden (8, or more with Tillers).
    var gardenPlotCount: Int { min(Garden.plotsPerField, gardenBonuses.plots) }
    var gardenFirstFieldCleared: Bool { gardenPlotCount >= Garden.plotsPerField }
    /// Can this patch be planted? First garden: the ones the Tillers have cleared. Bought gardens: all of them.
    func gardenPlotOpen(_ id: Int) -> Bool {
        let field = id / Garden.plotsPerField
        guard field < state.garden.fields else { return false }
        return field > 0 || id < gardenPlotCount
    }
    func gardenPlot(_ id: Int) -> GardenPlot { state.garden.plots.first { $0.id == id } ?? GardenPlot(id: id) }

    /// Buys the next garden with Pokédollars (only once the first one is fully cleared).
    @discardableResult
    func buyGardenField() -> Bool {
        let next = state.garden.fields
        guard next < Garden.maxFields, gardenFirstFieldCleared, state.money >= Garden.fieldPrice(next) else { return false }
        mutate { s in
            s.money -= Garden.fieldPrice(next)
            s.garden.fields = next + 1
        }
        return true
    }

    /// When the next planted berry is ready (for the map's timer).
    var nextGardenReady: Date? {
        let b = gardenBonuses
        return state.garden.plots.compactMap { GardenRules.readyAt($0, bonuses: b) }.min()
    }
    var gardenPlanted: Int { state.garden.plots.filter { $0.berry != nil }.count }

    private func ensurePlots(_ s: inout GameState) {
        while s.garden.plots.count < Garden.maxPlots { s.garden.plots.append(GardenPlot(id: s.garden.plots.count)) }
    }

    @discardableResult
    func plant(_ berry: String, in plotID: Int) -> Bool {
        guard (state.bag[berry] ?? 0) > 0, gardenPlotOpen(plotID) else { return false }
        let hours = GardenRules.hoursToGrow(gardenBonuses)
        var ok = false
        mutate { s in
            ensurePlots(&s)
            guard let i = s.garden.plots.firstIndex(where: { $0.id == plotID }), s.garden.plots[i].berry == nil else { return }
            s.bag[berry, default: 0] -= 1
            if s.bag[berry] == 0 { s.bag[berry] = nil }
            s.garden.plots[i].berry = berry
            s.garden.plots[i].plantedAt = .now
            s.garden.plots[i].growHours = hours
            s.stats["berriesPlanted", default: 0] += 1
            ok = true
        }
        if ok { rescheduleGardenNotifications() }
        return ok
    }

    struct HarvestResult { let berry: String; let count: Int; let bonus: String?; let replanted: Bool }

    func harvest(_ plotID: Int) -> HarvestResult? {
        let b = gardenBonuses
        guard let plot = state.garden.plots.first(where: { $0.id == plotID }), let berry = plot.berry,
              GardenRules.progress(plot, bonuses: b) >= 1 else { return nil }
        let count = GardenRules.yield(b)
        var bonus: String?
        if Double.random(in: 0..<1) < b.bonusBerryChance {
            bonus = ItemCatalog.berries.filter { $0 != berry }.randomElement()
        }
        let replant = Double.random(in: 0..<1) < b.replantChance
        let workerIDs = gardenWorkers.map(\.id)
        mutate { s in
            guard let i = s.garden.plots.firstIndex(where: { $0.id == plotID }) else { return }
            s.bag[berry, default: 0] += count
            s.stats["berriesHarvested", default: 0] += count + (bonus == nil ? 0 : 1)
            if let bonus { s.bag[bonus, default: 0] += 1 }
            s.garden.plots[i].berry = replant ? berry : nil
            s.garden.plots[i].plantedAt = replant ? .now : nil
            s.garden.plots[i].growHours = replant ? GardenRules.hoursToGrow(b) : nil
            s.garden.harvests += 1
            for id in workerIDs {
                guard let m = s.index(of: id) else { continue }
                s.pokemon[m].friendship = min(255, s.pokemon[m].friendship + b.friendshipPerHarvest)
            }
        }
        rescheduleGardenNotifications()
        return HarvestResult(berry: berry, count: count, bonus: bonus, replanted: replant)
    }

    func addGardenWorker(_ id: UUID) {
        guard state.boxedIDs.contains(id), gardenWorkers.count < Garden.maxWorkers,
              !state.garden.workers.contains(id) else { return }
        let h = GardenRules.hoursToGrow(gardenBonuses)
        mutate { s in
            Self.fixTimers(&s, hours: h)
            s.garden.workers = s.garden.workers.filter { w in !s.partyIDs.contains(w) && s.index(of: w) != nil }
            s.garden.workers.append(id)
            GameRules.takeOutOfBox(id, in: &s)
        }
        rescheduleGardenNotifications()
    }

    func removeGardenWorker(_ id: UUID) {
        let h = GardenRules.hoursToGrow(gardenBonuses)
        mutate { s in
            Self.fixTimers(&s, hours: h)
            s.garden.workers.removeAll { $0 == id }
            GameRules.returnToBox(id, in: &s)
        }
        rescheduleGardenNotifications()
    }

    /// Ovals used to hold two plants each: keep the first plant in each oval (in its middle) and give the
    /// other one's berry back.
    func migrateGardenToOnePerPatch() {
        guard !state.garden.onePerPatch else { return }
        mutate { s in
            var new: [GardenPlot] = []
            var refund: [String] = []
            for old in s.garden.plots.sorted(by: { $0.id < $1.id }) where old.berry != nil {
                let field = old.id / 12, oval = (old.id % 12) / 2
                let id = field * Garden.plotsPerField + oval
                if new.contains(where: { $0.id == id }) { refund.append(old.berry!) }
                else { var p = old; p.id = id; new.append(p) }
            }
            for id in 0..<(s.garden.fields * Garden.plotsPerField) where !new.contains(where: { $0.id == id }) {
                new.append(GardenPlot(id: id))
            }
            s.garden.plots = new.sorted { $0.id < $1.id }
            for b in refund { s.bag[b, default: 0] += 1 }
            s.garden.onePerPatch = true
        }
        rescheduleGardenNotifications()
    }

    /// Plants from before each one kept its own timer: fix theirs now, so changing workers doesn't move them.
    private static func fixTimers(_ s: inout GameState, hours: Double) {
        for i in s.garden.plots.indices where s.garden.plots[i].berry != nil && s.garden.plots[i].growHours == nil {
            s.garden.plots[i].growHours = hours
        }
    }

    /// The Aroma Lady's present: one berry a day.
    func claimGardenGift() -> String? {
        let day = DailyStampsKey.key(DailyStamps.clock)
        guard state.garden.lastGiftDay != day else { return nil }
        let berry = ItemCatalog.berries.randomElement()!
        mutate { s in
            s.garden.lastGiftDay = day
            s.bag[berry, default: 0] += 1
        }
        return berry
    }
    var gardenGiftWaiting: Bool { state.garden.lastGiftDay != DailyStampsKey.key(DailyStamps.clock) }

    /// One "ready to pick" notification per planted patch (re-timed when your workers change).
    func rescheduleGardenNotifications() {
        let ids = (0..<36).map { "garden-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        let b = gardenBonuses
        // patches ready at (about) the same time share one notification
        var groups: [Int: [GardenPlot]] = [:]
        for p in state.garden.plots {
            guard let at = GardenRules.readyAt(p, bonuses: b), at > .now else { continue }
            groups[Int(at.timeIntervalSince1970 / 300), default: []].append(p)
        }
        if !groups.isEmpty { ensureNotificationPermission() }
        let helper = state.garden.workers.compactMap { state.mon($0) }.first
        for (_, plots) in groups {
            guard let first = plots.first, let at = plots.compactMap({ GardenRules.readyAt($0, bonuses: b) }).max(),
                  let berry = first.berry else { continue }
            let kinds = Array(Set(plots.compactMap(\.berry))).sorted().map { Dex.itemName($0) }
            let what = plots.count == 1 ? "Your \(Dex.itemName(berry)) is"
                : kinds.count == 1 ? "\(plots.count) \(kinds[0]) plants are" : "\(plots.count) berry plants (\(kinds.joined(separator: ", "))) are"
            notify(title: "Berries are ready! 🍓", body: "\(what) ready to pick in the Garden.",
                   id: "garden-\(first.id)", category: "garden", icon: helper.map { ($0.speciesID, $0.isShiny) }, at: at)
        }
    }
}

// MARK: - Ranch

extension GameStore {
    var ranch: Ranch { state.ranch }
    var ranchWorkers: [OwnedPokemon] { state.ranch.ranchers.compactMap { state.mon($0) } }
    var ranchShiftRunning: Bool { state.ranch.shiftEnd != nil }
    var ranchShiftDone: Bool { (state.ranch.shiftEnd ?? .distantFuture) <= .now }

    /// The soonest ranch timer, for the map (shift or building).
    var nextRanchTimer: (date: Date, building: Bool)? {
        let shift = state.ranch.shiftEnd.map { ($0, false) }
        let build = state.ranch.building.map { ($0.endsAt, true) }
        return [shift, build].compactMap { $0 }.min { $0.0 < $1.0 }
    }

    func addRancher(_ id: UUID) {
        guard state.boxedIDs.contains(id), ranchWorkers.count < state.ranch.slots, !ranchShiftRunning else { return }
        mutate { s in
            s.ranch.ranchers.append(id)
            GameRules.takeOutOfBox(id, in: &s)
        }
    }

    func removeRancher(_ id: UUID) {
        guard !ranchShiftRunning else { return }
        mutate { s in
            s.ranch.ranchers.removeAll { $0 == id }
            GameRules.returnToBox(id, in: &s)
        }
    }

    var ranchShiftHours: Double { RanchRules.shiftHours(ranch: state.ranch, workers: ranchWorkers) }

    func startRanchShift() {
        guard !ranchWorkers.isEmpty, !ranchShiftRunning else { return }
        let end = Date().addingTimeInterval(ranchShiftHours * 3600)
        mutate { s in
            s.ranch.shiftStart = .now
            s.ranch.shiftEnd = end
        }
        rescheduleRanchNotification()
    }

    /// "Your Pokémon are back from the Ranch", at the end of the shift, with the first rancher's picture.
    func rescheduleRanchNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ranch-shift"])
        guard let end = state.ranch.shiftEnd, end > .now else { return }
        ensureNotificationPermission()
        let names = ranchWorkers.map(\.name)
        let who: String
        switch names.count {
        case 0: who = "Your ranchers are"
        case 1: who = "\(names[0]) is"
        case 2: who = "\(names[0]) and \(names[1]) are"
        default: who = names.dropLast().joined(separator: ", ") + " and \(names.last!) are"
        }
        notify(title: "Back from the Ranch! 🧺", body: "\(who) back with their haul. Tap to collect it.",
               id: "ranch-shift", category: "ranch", icon: ranchWorkers.first.map { ($0.speciesID, $0.isShiny) }, at: end)
    }

    /// Re-books the Garden and Ranch reminders (after a reinstall, a restore, or anything that dropped them).
    func rescheduleTimerNotifications() {
        rescheduleGardenNotifications()
        rescheduleRanchNotification()
    }

    /// Asks for notification permission if it was never asked (e.g. it was skipped at the start).
    func ensureNotificationPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    /// Calls the ranchers back early: the shift is cancelled (nothing gathered) so the team can be changed.
    func recallRanchShift() {
        guard ranchShiftRunning else { return }
        mutate { s in
            s.ranch.shiftStart = nil
            s.ranch.shiftEnd = nil
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ranch-shift"])
    }

    /// Collects a finished shift: materials, Pokédollars, friendship and any rare finds.
    func collectRanchShift() -> RanchRules.Haul? {
        guard ranchShiftDone else { return nil }
        var total = RanchRules.Haul()
        var gains: [(UUID, Int)] = []
        let team = RanchTeam.of(ranchWorkers)
        for mon in ranchWorkers {
            let h = RanchRules.haul(for: mon, ranch: state.ranch, team: team)
            for (m, n) in h.materials { total.materials[m, default: 0] += n }
            total.money += h.money
            if let t = h.ticket, total.ticket == nil { total.ticket = t }
            gains.append((mon.id, h.friendship))
            total.friendship += h.friendship
        }
        total.money = Int(Double(total.money) * FieldItems.multiplier(.money, in: state))    // Amulet Coin
        mutate { s in
            for (m, n) in total.materials { s.ranch.materials[m.rawValue, default: 0] += n }
            s.money += total.money
            if let t = total.ticket { s.bag[t, default: 0] += 1 }
            for (id, f) in gains {
                if let i = s.index(of: id) { s.pokemon[i].friendship = min(255, s.pokemon[i].friendship + f) }
            }
            s.ranch.shiftStart = nil
            s.ranch.shiftEnd = nil
            s.ranch.shiftCount += 1
        }
        return total
    }

    func canAfford(_ p: RanchProject) -> Bool {
        state.money >= p.money && p.cost.allSatisfy { state.ranch.amount($0.key) >= $0.value }
    }

    func startRanchProject() -> Bool {
        guard state.ranch.building == nil, let p = state.ranch.nextProject, canAfford(p) else { return false }
        let end = Date().addingTimeInterval(p.hours * 3600)
        mutate { s in
            s.money -= p.money
            for (m, n) in p.cost { s.ranch.materials[m.rawValue, default: 0] -= n }
            s.ranch.building = RanchBuild(project: p.id, startedAt: .now, endsAt: end)
        }
        notify(title: "\(p.name) is finished! 🏗️", body: "Come and see the ranch — \(p.reward).",
               id: "ranch-build", category: "ranch", at: end)
        return true
    }

    /// Finishes the building work once its time is up. Returns the project if it just finished.
    @discardableResult
    func finishRanchProjectIfDone() -> RanchProject? {
        guard let b = state.ranch.building, b.endsAt <= .now,
              let p = RanchProject.all.first(where: { $0.id == b.project }) else { return nil }
        mutate { s in
            s.ranch.building = nil
            s.ranch.built = max(s.ranch.built, p.id + 1)
            if let t = p.ticket { s.bag[t, default: 0] += 1 }
        }
        return p
    }

    // Furniture

    func buyDecor(_ d: RanchDecor) -> Bool {
        guard state.ranch.houseBuilt, state.money >= d.price else { return false }
        mutate { s in
            s.money -= d.price
            s.ranch.decor[d.key, default: 0] += 1
            s.stats["decorBought", default: 0] += 1
        }
        return true
    }

    func placeDecor(_ key: String, x: Int, y: Int) -> Bool {
        guard (state.ranch.decor[key] ?? 0) > 0, let d = RanchDecor.find(key), RanchHouse.fits(d, x: x, y: y, in: state.ranch) else { return false }
        mutate { s in
            s.ranch.decor[key, default: 0] -= 1
            if s.ranch.decor[key] == 0 { s.ranch.decor[key] = nil }
            s.ranch.placed.append(PlacedDecor(key: key, x: x, y: y))
        }
        return true
    }

    func pickUpDecor(_ id: UUID) {
        guard let p = state.ranch.placed.first(where: { $0.id == id }) else { return }
        mutate { s in
            s.ranch.placed.removeAll { $0.id == id }
            s.ranch.decor[p.key, default: 0] += 1
        }
    }

    static let roomStylePrice = 10_000

    func setRoomStyle(_ key: String) -> Bool {
        if state.ranch.styles.contains(key) {
            mutate { $0.ranch.style = key }
            return true
        }
        guard state.ranch.has(7), state.money >= Self.roomStylePrice else { return false }
        mutate { s in
            s.money -= Self.roomStylePrice
            s.ranch.styles.append(key)
            s.ranch.style = key
        }
        return true
    }

    // Event tickets

    /// Uses an event ticket: its legendary Pokémon appears in your wild encounters for a day.
    func useTicket(_ key: String) -> PendingEncounter? {
        guard (state.bag[key] ?? 0) > 0, let t = RanchTickets.ticket(key), let id = t.species.randomElement() else { return nil }
        let sp = Dex.species(id)
        let enc = PendingEncounter(speciesID: id, level: 50, gender: GameRules.rollGender(sp),
                                   isShiny: Int.random(in: 0..<max(1, state.settings.shinyOdds)) == 0,
                                   nature: Dex.natures.randomElement()!, personality: .random(in: 0...UInt32.max),
                                   appearedAt: .now, expiresAt: Date().addingTimeInterval(24 * 3600),
                                   location: tracker.currentLocation().map {
                                       MetLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                                   }, habitat: nil)
        mutate { s in
            s.bag[key, default: 0] -= 1
            if s.bag[key] == 0 { s.bag[key] = nil }
            s.pending.append(enc)
            s.dexSeen.insert(id)
            s.stats["ticketsUsed", default: 0] += 1
        }
        toast = "\(t.name): a wild \(sp.name) appeared! It's waiting in your encounters for a day."
        return enc
    }
}

/// Where furniture can go in the house.
enum RanchHouse {
    /// Floor cells (x, y) in the room; the back wall is row 1.
    static func floor(_ r: Ranch) -> (x: ClosedRange<Int>, y: ClosedRange<Int>) {
        let (w, h) = r.roomSize
        return (2...(w - 3), 2...(h - 2))
    }

    static func cells(_ d: RanchDecor, x: Int, y: Int) -> [(Int, Int)] {
        (0..<d.h).flatMap { dy in (0..<d.w).map { dx in (x + dx, y + dy) } }
    }

    static func fits(_ d: RanchDecor, x: Int, y: Int, in r: Ranch, ignoring: UUID? = nil) -> Bool {
        let f = floor(r)
        let mine = cells(d, x: x, y: y)
        if d.placement == .wall {
            guard y == 1, mine.allSatisfy({ f.x.contains($0.0) }) else { return false }
        } else {
            guard mine.allSatisfy({ f.x.contains($0.0) && f.y.contains($0.1) }) else { return false }
        }
        for p in r.placed where p.id != ignoring {
            guard let other = RanchDecor.find(p.key) else { continue }
            let theirs = cells(other, x: p.x, y: p.y)
            if mine.contains(where: { c in theirs.contains { $0 == c } }) { return false }
        }
        return true
    }
}

private extension UIApplication.State {
    @MainActor static var current: UIApplication.State { UIApplication.shared.applicationState }
}
