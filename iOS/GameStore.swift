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

    init() { load() }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(GameState.self, from: data) else { return }
        state = decoded
        hasGame = !decoded.pokemon.isEmpty
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: saveURL, options: .atomic) }
        pushOutward()
    }

    private func mutate(_ change: (inout GameState) -> Void) {
        change(&state)
        save()
    }

    // MARK: Startup

    func start() {
        guard hasGame else { return }
        tracker.onMovement = { [weak self] _ in self?.requestTick(minInterval: 20) }
        tracker.apply(mode: state.settings.trackingMode)
        engine.startLiveUpdates { [weak self] in self?.requestTick(minInterval: 15) }
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

    func newGame(trainerName: String, starter: Int, nickname: String?) async {
        let loc = tracker.currentLocation()
        var met: MetLocation?
        if let loc {
            met = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                              placeName: await PlaceService.shared.placeName(for: loc))
        }
        var s = GameRules.newGame(trainerName: trainerName, starter: starter, nickname: nickname, location: met)
        // Start counting from now: today's earlier steps don't count.
        let today = Calendar.current.startOfDay(for: .now)
        s.stepLedger[TrackStore.key(for: today)] = await engine.steps(onDay: today)
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
        let outcome = GameRules.apply(steps: newSteps, to: &s, context: context)
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
            guard case .caught(let ball) = safari.phase else { return }
            let w = safari.wild
            var mon = GameRules.makePokemon(species: w.speciesID, level: w.level, ball: ball, trainer: s.trainer,
                                            settings: s.settings, location: w.location, date: .now)
            mon.gender = w.gender; mon.isShiny = w.isShiny; mon.nature = w.nature; mon.personality = w.personality
            mon.metDate = w.appearedAt
            if w.location == nil, let loc = tracker.currentLocation() {
                mon.metLocation = MetLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            }
            GameRules.store(mon, in: &s)
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
        case .noEffect: break
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
            expMultiplier: state.settings.expMultiplier,
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
