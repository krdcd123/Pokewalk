import Foundation
import HealthKit
import AVFoundation

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

    /// The night of `day` (going to bed that day, waking the next), or nil if Health has no sleep for it.
    func night(for day: Date) async -> SleepNight? {
        let start = Calendar.current.startOfDay(for: day).addingTimeInterval(15 * 3600)
        let end = start.addingTimeInterval(24 * 3600)
        let samples = await sleepSamples(from: start, to: end)
        guard !samples.isEmpty else { return nil }

        // Prefer the Apple Watch's staged sleep when there is any; otherwise use whatever recorded sleep.
        let stagedValues: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM]
        let staged = samples.filter { s in HKCategoryValueSleepAnalysis(rawValue: s.value).map { stagedValues.contains($0) } ?? false }
        let watchSources = Set(staged.map { $0.sourceRevision.source.bundleIdentifier })
        let chosen = watchSources.isEmpty ? samples : samples.filter { watchSources.contains($0.sourceRevision.source.bundleIdentifier) }

        var blocks: [SleepNight.Block] = []
        var t: [SleepNight.Stage: TimeInterval] = [:]
        var inBedFrom: Date?
        for s in chosen.sorted(by: { $0.startDate < $1.startDate }) {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            let stage: SleepNight.Stage
            switch value {
            case .awake: stage = .awake
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepUnspecified: stage = .asleep
            case .inBed:
                inBedFrom = min(inBedFrom ?? s.startDate, s.startDate)
                continue
            default: continue
            }
            blocks.append(.init(stage: stage, start: s.startDate, end: s.endDate))
            t[stage, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        let sleeping = blocks.filter { $0.stage != .awake }
        guard let first = sleeping.map(\.start).min(), let last = sleeping.map(\.end).max() else { return nil }
        let asleep = (t[.rem] ?? 0) + (t[.core] ?? 0) + (t[.deep] ?? 0) + (t[.asleep] ?? 0)
        let awakenings = blocks.filter { $0.stage == .awake && $0.start > first && $0.end < last
            && $0.end.timeIntervalSince($0.start) >= 60 }.count

        async let hr = stat(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), first, last, [.discreteAverage, .discreteMin])
        async let rr = stat(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), first, last, [.discreteAverage])
        async let o2 = stat(.oxygenSaturation, unit: .percent(), first, last, [.discreteAverage])
        let (h, r, o) = await (hr, rr, o2)

        return SleepNight(day: Calendar.current.startOfDay(for: day), bedtime: first, wake: last, inBedFrom: inBedFrom,
                          asleep: asleep, awake: t[.awake] ?? 0, rem: t[.rem] ?? 0, core: t[.core] ?? 0, deep: t[.deep] ?? 0,
                          awakenings: awakenings, blocks: blocks, hasStages: !watchSources.isEmpty,
                          avgHeartRate: h.avg, minHeartRate: h.min, respiratoryRate: r.avg, bloodOxygen: o.avg,
                          source: watchSources.isEmpty ? "iPhone" : "Apple Watch")
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

    /// Refreshes last night and shows the morning popup once per night, after you've woken up.
    func refresh(showPopup: Bool) async {
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        var n = await night(for: yesterday)
        if n == nil || (n!.wake < .now.addingTimeInterval(-20 * 3600)) {
            if let t = await night(for: today), t.wake < .now { n = t }   // an earlier sleep tonight (nap / early night)
        }
        lastNight = n
        guard showPopup, let n, popup == nil else { return }
        let key = "sleepShown-\(Int(n.day.timeIntervalSince1970))"
        // Only once you're up: woke 10+ minutes ago, within the last 14 hours
        let since = Date().timeIntervalSince(n.wake)
        guard since > 10 * 60, since < 14 * 3600, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if SleepRecorder.shared.isRecording { SleepRecorder.shared.stop() }
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

// MARK: - Sleep talking recorder

/// Listens through the night and keeps the 5 loudest moments (sleep talking, snoring…) as short clips.
/// iOS only lets an app start the microphone while it's open, so you start it before bed; it keeps
/// listening with the screen off and stops when you open PokéWalk in the morning.
@MainActor
final class SleepRecorder: ObservableObject {
    static let shared = SleepRecorder()
    /// Read by the sound effects so they don't change the audio setup mid-recording.
    nonisolated(unsafe) static var active = false

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    private var engine: AVAudioEngine?
    private var listener: Listener?

    static let keep = 5

    static var root: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SleepTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func folder(for day: Date) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let d = root.appendingPathComponent(f.string(from: day), isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// The clips from a night, loudest first.
    static func clips(for day: Date) -> [URL] {
        let d = folder(for: day)
        let files = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "caf" }.sorted { score($0) > score($1) }
    }

    /// File names hold the clip's loudness: clip-<time>-<score>.caf
    static func score(_ url: URL) -> Double {
        Double(url.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "0") ?? 0
    }

    static func time(_ url: URL) -> Date? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count >= 3, let t = Double(parts[1]) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    func start() async -> String? {
        guard !isRecording else { return nil }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return "Allow the microphone for PokéWalk in Settings to record sleep talking." }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
            try session.setActive(true)
        } catch { return "Couldn't start the microphone." }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let night = SleepService.nightDay(for: .now)
        let listener = Listener(folder: Self.folder(for: night), format: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buf, _ in listener.process(buf) }
        do { try engine.start() } catch { return "Couldn't start the microphone." }
        self.engine = engine
        self.listener = listener
        Self.active = true
        isRecording = true
        startedAt = .now
        return nil
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        listener?.finish()
        engine = nil; listener = nil
        Self.active = false
        isRecording = false
        startedAt = nil
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    /// Runs on the audio thread: tracks the room's quiet level and saves bursts well above it.
    final class Listener: @unchecked Sendable {
        let folder: URL
        let format: AVAudioFormat
        private var floorDB: Float = -60
        private var file: AVAudioFile?
        private var clipStart = Date()
        private var lastLoud = Date()
        private var peak: Float = -160
        private var loudSum: Float = 0
        private let lock = NSLock()

        init(folder: URL, format: AVAudioFormat) { self.folder = folder; self.format = format }

        func process(_ buf: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buf.frameLength) { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(buf.frameLength))
            let db = 20 * log10(max(rms, 1e-7))
            // the quiet level drifts slowly; loud moments don't drag it up much
            floorDB = db < floorDB ? floorDB * 0.9 + db * 0.1 : floorDB * 0.999 + db * 0.001
            let loud = db > max(floorDB + 18, -48)
            let now = Date()
            if loud {
                lastLoud = now
                if file == nil {
                    clipStart = now; peak = -160; loudSum = 0
                    let tmp = folder.appendingPathComponent("recording.caf")
                    try? FileManager.default.removeItem(at: tmp)
                    file = try? AVAudioFile(forWriting: tmp, settings: format.settings)
                }
                peak = max(peak, db)
                loudSum += db - floorDB
            }
            if let file {
                try? file.write(from: buf)
                // end the clip after 2.5 s of quiet, or at 20 s
                if now.timeIntervalSince(lastLoud) > 2.5 || now.timeIntervalSince(clipStart) > 20 { close() }
            }
        }

        func finish() { lock.lock(); close(); lock.unlock() }

        private func close() {
            guard file != nil else { return }
            file = nil
            let tmp = folder.appendingPathComponent("recording.caf")
            let length = Date().timeIntervalSince(clipStart)
            guard length > 1.2 else { try? FileManager.default.removeItem(at: tmp); return }   // a single bump/cough
            let score = Int(loudSum)
            let dest = folder.appendingPathComponent("clip-\(Int(clipStart.timeIntervalSince1970))-\(score).caf")
            try? FileManager.default.moveItem(at: tmp, to: dest)
            // keep only the loudest few
            let all = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("clip-") }
                .sorted { SleepRecorder.score($0) > SleepRecorder.score($1) }
            for extra in all.dropFirst(SleepRecorder.keep) { try? FileManager.default.removeItem(at: extra) }
        }
    }
}
