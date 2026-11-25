import Foundation
import UIKit
import HealthKit
import CoreMotion

// MARK: - Sleep from Apple Health

/// One night of sleep, built from Apple Health's sleep data (written by your Apple Watch's sleep tracking,
/// or by the iPhone's Sleep Schedule / bedtime). A night belongs to the day you went to bed:
/// sleeping at 23:30 on the 23rd — or at 01:00 on the 24th — is the night of the 23rd.
struct SleepNight: Equatable {
    struct Block: Equatable { var stage: Stage; var start: Date; var end: Date }
    enum Stage: String { case awake, rem, core, deep, asleep, inBed
        var title: String {
            switch self {
            case .awake: return "Awake"; case .rem: return "REM"; case .core: return "Core"
            case .deep: return "Deep"; case .asleep: return "Asleep"; case .inBed: return "In bed"
            }
        }
    }

    var day: Date
    var bedtime: Date            // fell asleep
    var wake: Date               // woke up
    var inBedFrom: Date?
    var asleep: TimeInterval
    var awake: TimeInterval
    var rem: TimeInterval
    var core: TimeInterval
    var deep: TimeInterval
    var awakenings: Int
    var blocks: [Block]          // for the timeline chart
    var hasStages: Bool          // Apple Watch stages (REM/Core/Deep) vs just asleep/in bed
    var avgHeartRate: Double?
    var minHeartRate: Double?
    var respiratoryRate: Double?
    var bloodOxygen: Double?     // 0–1
    var source: String

    var inBed: TimeInterval { wake.timeIntervalSince(inBedFrom ?? bedtime) }
    var efficiency: Double { inBed > 0 ? min(1, asleep / inBed) : 0 }
}

@MainActor
final class SleepService: ObservableObject {
    static let shared = SleepService()
    private let store = StepCounter.shared.store

    @Published private(set) var lastNight: SleepNight?
    @Published var popup: SleepNight?

    static let sleepType = HKCategoryType(.sleepAnalysis)
    static var readTypes: Set<HKObjectType> {
        [sleepType, HKQuantityType(.heartRate), HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation)]
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// Which day a moment of the night belongs to (bedtime before 3pm the next day → that day).
    static func nightDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date.addingTimeInterval(-15 * 3600))
    }

    /// The night of `day`: Apple Health's sleep if there is any, otherwise PokéWalk's own estimate
    /// from when your iPhone sat still overnight.
    func night(for day: Date) async -> SleepNight? {
        if let n = await healthNight(for: day) { return n }
        return await MotionSleep.shared.night(for: day)
    }

    /// The night of `day` from Apple Health (watch, sleep schedule or a sleep app), or nil.
    func healthNight(for day: Date) async -> SleepNight? {
        let start = Calendar.current.startOfDay(for: day).addingTimeInterval(15 * 3600)
        let end = start.addingTimeInterval(24 * 3600)
        var samples = await sleepSamples(from: start, to: end).map {
            WatchSleepSample(value: $0.value, start: $0.startDate, end: $0.endDate, source: $0.sourceRevision.source.bundleIdentifier)
        }
        // The watch sends its sleep straight to PokéWalk when you wake (Apple Health on the iPhone can take a
        // while to get it from the watch). Use that until — or as well as — Health has it.
        let fromWatch = WatchSleepStore.samples(from: start, to: end)
        let stagedValues: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM]
        func isStaged(_ x: WatchSleepSample) -> Bool { HKCategoryValueSleepAnalysis(rawValue: x.value).map { stagedValues.contains($0) } ?? false }
        if !fromWatch.isEmpty && !samples.contains(where: isStaged) { samples = fromWatch }
        guard !samples.isEmpty else { return nil }

        // Prefer the Apple Watch's staged sleep when there is any; otherwise use whatever recorded sleep.
        let staged = samples.filter(isStaged)
        let watchSources = Set(staged.map(\.source))
        let chosen = watchSources.isEmpty ? samples : samples.filter { watchSources.contains($0.source) }

        var blocks: [SleepNight.Block] = []
        var t: [SleepNight.Stage: TimeInterval] = [:]
        var inBedFrom: Date?
        var inBedBlocks: [SleepNight.Block] = []
        for s in chosen.sorted(by: { $0.start < $1.start }) {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            let stage: SleepNight.Stage
            switch value {
            case .awake: stage = .awake
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepUnspecified: stage = .asleep
            case .inBed:
                inBedFrom = min(inBedFrom ?? s.start, s.start)
                inBedBlocks.append(.init(stage: .inBed, start: s.start, end: s.end))
                continue
            default: continue
            }
            blocks.append(.init(stage: stage, start: s.start, end: s.end))
            t[stage, default: 0] += s.end.timeIntervalSince(s.start)
        }
        // iPhone only (no watch): Health just has "in bed" time from your Sleep Schedule — use it as the night.
        var phoneOnly = false
        if !blocks.contains(where: { $0.stage != .awake }), !inBedBlocks.isEmpty {
            phoneOnly = true
            for b in inBedBlocks {
                blocks.append(.init(stage: .asleep, start: b.start, end: b.end))
                t[.asleep, default: 0] += b.end.timeIntervalSince(b.start)
            }
        }
        let sleeping = blocks.filter { $0.stage != .awake }
        guard let first = sleeping.map(\.start).min(), let last = sleeping.map(\.end).max() else { return nil }
        let remT: TimeInterval = t[.rem] ?? 0
        let coreT: TimeInterval = t[.core] ?? 0
        let deepT: TimeInterval = t[.deep] ?? 0
        let plainT: TimeInterval = t[.asleep] ?? 0
        let asleep: TimeInterval = remT + coreT + deepT + plainT
        let awakenings = blocks.filter { b -> Bool in
            guard b.stage == .awake, b.start > first, b.end < last else { return false }
            return b.end.timeIntervalSince(b.start) >= 60
        }.count

        async let hr = stat(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), first, last, [.discreteAverage, .discreteMin])
        async let rr = stat(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), first, last, [.discreteAverage])
        async let o2 = stat(.oxygenSaturation, unit: .percent(), first, last, [.discreteAverage])
        let (h, r, o) = await (hr, rr, o2)

        return SleepNight(day: Calendar.current.startOfDay(for: day), bedtime: first, wake: last, inBedFrom: inBedFrom,
                          asleep: asleep, awake: t[.awake] ?? 0, rem: t[.rem] ?? 0, core: t[.core] ?? 0, deep: t[.deep] ?? 0,
                          awakenings: awakenings, blocks: blocks, hasStages: !watchSources.isEmpty,
                          avgHeartRate: h.avg, minHeartRate: h.min, respiratoryRate: r.avg, bloodOxygen: o.avg,
                          source: phoneOnly ? "iPhone (time in bed)" : (watchSources.isEmpty ? "iPhone" : "Apple Watch"))
    }

    /// Average sleep over the nights before `day` (up to 7), for "compared with usual".
    func usual(before day: Date) async -> (asleep: TimeInterval, bedtimeMinutes: Double)? {
        var nights: [SleepNight] = []
        for i in 1...7 {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: day), let n = await night(for: d) { nights.append(n) }
        }
        guard !nights.isEmpty else { return nil }
        let avg = nights.reduce(0) { $0 + $1.asleep } / Double(nights.count)
        // bedtime as minutes after 6pm, so 23:30 and 00:30 average sensibly
        let mins = nights.map { n -> Double in
            let c = Calendar.current.dateComponents([.hour, .minute], from: n.bedtime)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) - 18 * 60
            if m < 0 { m += 24 * 60 }
            return m
        }
        return (avg, mins.reduce(0, +) / Double(mins.count))
    }

    /// One-time: clear sleep worked out by earlier builds (the rules changed), so nights are redone.
    static func resetOldSleepOnce() {
        let flag = "sleepReset-2026-11-24"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("sleep-estimates.json"))
        for day in ["2026-11-22", "2026-11-23"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent("SleepTalk/\(day)"))
        }
        for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix("sleepShown-") {
            UserDefaults.standard.removeObject(forKey: k)
        }
        MotionSleep.shared.clearCache()
    }

    /// Refreshes last night and shows the morning popup once per night, after you've woken up.
    func refresh(showPopup: Bool) async {
        Self.resetOldSleepOnce()
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        var n = await night(for: yesterday)
        if n == nil || (n!.wake < .now.addingTimeInterval(-20 * 3600)) {
            if let t = await night(for: today), t.wake < .now { n = t }   // an earlier sleep tonight (nap / early night)
        }
        if lastNight != n { lastNight = n }
        guard showPopup, let n, popup == nil else { return }
        let key = "sleepShown-\(Int(n.day.timeIntervalSince1970))"
        // Only once you're up for the day: woke 10+ minutes ago, within the last 14 hours, and it's
        // morning or later (checking your phone at 3am isn't waking up — listening carries on)
        // (Watch sleep is only written once you're up, so it needs no wait; the iPhone-only estimate does.)
        let since = Date().timeIntervalSince(n.wake)
        let hour = Calendar.current.component(.hour, from: .now)
        let wait: TimeInterval = n.source == "Apple Watch" ? 0 : 10 * 60
        guard since >= wait, since < 14 * 3600, hour >= 5, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        SleepRecorder.shared.stop()
        popup = n
    }

    // MARK: HealthKit helpers

    private func sleepSamples(from start: Date, to end: Date) async -> [HKCategorySample] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: Self.sleepType, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                cont.resume(returning: s as? [HKCategorySample] ?? [])
            }
            store.execute(q)
        }
    }

    private func stat(_ id: HKQuantityTypeIdentifier, unit: HKUnit, _ from: Date, _ to: Date,
                      _ options: HKStatisticsOptions) async -> (avg: Double?, min: Double?) {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: pred, options: options) { _, st, _ in
                cont.resume(returning: (st?.averageQuantity()?.doubleValue(for: unit), st?.minimumQuantity()?.doubleValue(for: unit)))
            }
            store.execute(q)
        }
    }
}

// MARK: - Live "asleep" detection (no microphone)

/// At night it watches the iPhone's motion chip live: still for 15 minutes → you've dropped off (the map's
/// Today card shows "Sleeping"); moving about → awake again. It used to record sleep talking too — that's
/// gone, and any old clips are deleted.
@MainActor
final class SleepRecorder: ObservableObject {
    static let shared = SleepRecorder()
    /// Nothing records any more (kept so the sound code doesn't need to check).
    static let active = false

    @Published private(set) var isRecording = false        // watching for sleep
    @Published private(set) var startedAt: Date?
    @Published private(set) var asleepSince: Date?
    private let motion = CMMotionActivityManager()
    private var stillSince: Date?
    private var stillTimer: Timer?
    nonisolated static let stillToCountAsAsleep: TimeInterval = 15 * 60

    /// From what hour it starts watching (Settings), until 4am. 23 = 11pm.
    static var listenFromHour: Int {
        get { UserDefaults.standard.object(forKey: "sleepListenFrom") as? Int ?? 23 }
        set { UserDefaults.standard.set(newValue, forKey: "sleepListenFrom") }
    }

    static func hourText(_ h: Int) -> String {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)?
            .formatted(date: .omitted, time: .shortened) ?? "\(h):00"
    }

    /// Deletes the old sleep-talk clips once.
    static func removeOldClips() {
        guard !UserDefaults.standard.bool(forKey: "sleepTalkRemoved") else { return }
        UserDefaults.standard.set(true, forKey: "sleepTalkRemoved")
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SleepTalk")
        try? FileManager.default.removeItem(at: d)
    }

    /// Called on every check: starts at night (from your chosen time until 4am), stops in the morning.
    @discardableResult
    func autoStartOrStop() async -> String? {
        Self.removeOldClips()
        let hour = Calendar.current.component(.hour, from: .now)
        if isRecording, (5..<15).contains(hour), let s = startedAt, Date().timeIntervalSince(s) > 2 * 3600 {
            stop()
            return nil
        }
        let from = Self.listenFromHour
        let inWindow = from >= 12 ? (hour >= from || hour < 4) : (hour >= from && hour < 4)
        guard !isRecording, inWindow, CMMotionActivityManager.isActivityAvailable() else { return nil }
        start()
        return nil
    }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        startedAt = .now
        asleepSince = nil
        stillSince = .now
        motion.startActivityUpdates(to: .main) { [weak self] a in
            guard let self, let a else { return }
            Task { @MainActor in
                if a.walking || a.running || a.cycling || a.automotive {
                    self.stillSince = nil
                    self.asleepSince = nil
                } else if a.stationary, self.stillSince == nil {
                    self.stillSince = a.startDate
                }
                self.checkAsleep()
            }
        }
        stillTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAsleep() }
        }
    }

    private func checkAsleep() {
        guard isRecording, asleepSince == nil, let still = stillSince,
              Date().timeIntervalSince(still) >= Self.stillToCountAsAsleep else { return }
        asleepSince = still
    }

    func stop() {
        guard isRecording else { return }
        motion.stopActivityUpdates()
        stillTimer?.invalidate(); stillTimer = nil
        asleepSince = nil; stillSince = nil
        isRecording = false
        startedAt = nil
    }
}

// MARK: - Sleep sent straight from the watch

/// The last ~2 nights of sleep the watch app sent over WatchConnectivity.
enum WatchSleepStore {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-sleep.json")
    }

    static func save(_ new: [WatchSleepSample]) {
        let cutoff = Date().addingTimeInterval(-3 * 86_400)
        var all = load().filter { $0.end > cutoff }
        for x in new where !all.contains(x) { all.append(x) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: url, options: .atomic) }
    }

    static func load() -> [WatchSleepSample] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([WatchSleepSample].self, from: $0) } ?? []
    }

    static func samples(from: Date, to: Date) -> [WatchSleepSample] {
        load().filter { $0.start >= from && $0.start < to }
    }
}


// MARK: - Sleep without a watch or bedtime

/// Works out sleep from the iPhone alone: the motion chip keeps a 7-day log of when the phone was
/// still or moving, even while PokéWalk is closed. The longest still stretch overnight (short pickups
/// to check the time are joined up and counted as waking) is taken as your sleep.
/// Nights are saved, so they stay in the Journal after the phone's 7 days are up.
@MainActor
final class MotionSleep {
    static let shared = MotionSleep()
    private let manager = CMMotionActivityManager()

    private struct Saved: Codable { var bedtime: Date; var wake: Date; var wakes: [Date] }
    private var cache: [String: Saved] = [:]
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sleep-estimates.json")

    init() {
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode([String: Saved].self, from: d) { cache = c }
    }

    func clearCache() { cache = [:] }

    private func key(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: day)
    }

    func night(for day: Date) async -> SleepNight? {
        let day = Calendar.current.startOfDay(for: day)
        let k = key(day)
        let from = day.addingTimeInterval(18 * 3600)               // 6pm…
        let to = min(Date(), day.addingTimeInterval((24 + 14) * 3600))  // …to 2pm the next day
        // Recompute while the phone still has the data (and the night might still be going), else use the saved one.
        if from.timeIntervalSinceNow > -6.5 * 86_400, CMMotionActivityManager.isActivityAvailable(),
           let est = await estimate(from: from, to: to) {
            if est.wake < Date().addingTimeInterval(-15 * 60) {     // finished: keep it
                cache[k] = est
                if let d = try? JSONEncoder().encode(cache) { try? d.write(to: url, options: .atomic) }
            }
            return make(day, est)
        }
        return cache[k].map { make(day, $0) }
    }

    private func make(_ day: Date, _ e: Saved) -> SleepNight {
        // Blocks: asleep, with short "awake" marks where the phone was picked up
        var blocks: [SleepNight.Block] = []
        var cursor = e.bedtime
        for w in e.wakes.sorted() where w > cursor && w < e.wake {
            blocks.append(.init(stage: .asleep, start: cursor, end: w))
            let back = min(e.wake, w.addingTimeInterval(4 * 60))
            blocks.append(.init(stage: .awake, start: w, end: back))
            cursor = back
        }
        blocks.append(.init(stage: .asleep, start: cursor, end: e.wake))
        let awake = blocks.filter { $0.stage == .awake }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let total = e.wake.timeIntervalSince(e.bedtime)
        return SleepNight(day: day, bedtime: e.bedtime, wake: e.wake, inBedFrom: nil, asleep: total - awake, awake: awake,
                          rem: 0, core: 0, deep: 0, awakenings: e.wakes.count, blocks: blocks, hasStages: false,
                          avgHeartRate: nil, minHeartRate: nil, respiratoryRate: nil, bloodOxygen: nil,
                          source: "your iPhone sitting still (estimate)")
    }

    private func activities(from: Date, to: Date) async -> [CMMotionActivity] {
        await withCheckedContinuation { cont in
            manager.queryActivityStarting(from: from, to: to, to: .main) { list, _ in cont.resume(returning: list ?? []) }
        }
    }

    private func estimate(from: Date, to: Date) async -> Saved? {
        guard from < to else { return nil }
        let list = await activities(from: from, to: to)
        guard !list.isEmpty else { return nil }
        // Still stretches: each activity lasts until the next one starts
        var still: [(start: Date, end: Date)] = []
        for (i, a) in list.enumerated() {
            let end = i + 1 < list.count ? list[i + 1].startDate : to
            let isStill = a.stationary && !a.walking && !a.running && !a.automotive && !a.cycling
            guard isStill, end > a.startDate else { continue }
            if let last = still.last, a.startDate.timeIntervalSince(last.end) < 1 { still[still.count - 1].end = end }
            else { still.append((a.startDate, end)) }
        }
        // Join stretches split by a quick pickup (under 15 minutes), keeping the pieces
        var merged: [(start: Date, end: Date, parts: [(start: Date, end: Date)])] = []
        for st in still {
            if let last = merged.last, st.start.timeIntervalSince(last.end) <= 15 * 60 {
                merged[merged.count - 1].end = st.end
                merged[merged.count - 1].parts.append(st)
            } else {
                merged.append((st.start, st.end, [st]))
            }
        }
        // You're only asleep once the phone has stayed still for 15 minutes in one go (same rule as
        // the live "Sleeping" on the map). Pickups before that are settling down, not waking up.
        let asleepAfter = SleepRecorder.stillToCountAsAsleep
        merged = merged.compactMap { m -> (start: Date, end: Date, parts: [(start: Date, end: Date)])? in
            guard let i = m.parts.firstIndex(where: { $0.end.timeIntervalSince($0.start) >= asleepAfter }) else { return nil }
            let parts = Array(m.parts[i...])
            return (parts[0].start, m.end, parts)
        }
        // Your sleep: the longest one that starts in the evening / night and lasts 3+ hours
        let cal = Calendar.current
        let candidates = merged.filter { m in
            let h = cal.component(.hour, from: m.start)
            return (h >= 19 || h < 6) && m.end.timeIntervalSince(m.start) >= 3 * 3600
        }
        guard let best = candidates.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) else { return nil }
        let bed = best.start
        let wakes = best.parts.dropLast().map { $0.end }      // each pickup after you'd fallen asleep
        return Saved(bedtime: bed, wake: best.end, wakes: wakes)
    }
}
