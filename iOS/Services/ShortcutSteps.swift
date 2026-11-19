import Foundation
import AppIntents

/// Steps handed over by a Shortcut ("Find Health Samples" → this action). Lets PokéWalk see Apple Watch
/// steps even when the sideloading tool stripped the app's own Apple Health permission.
enum ShortcutSteps {
    private static var d: UserDefaults { .standard }

    /// Same "yyyy-MM-dd" day key as TrackStore, usable off the main actor.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func record(steps: Int, meters: Double?) {
        let key = dayKey(Calendar.current.startOfDay(for: .now))
        let current = self.steps(for: key)                       // where the ramp is right now
        let target = max(steps, d.integer(forKey: "shortcutTarget.\(key)"))
        d.set(current, forKey: "shortcutFrom.\(key)")
        d.set(target, forKey: "shortcutTarget.\(key)")
        d.set(Date().timeIntervalSince1970, forKey: "shortcutAt.\(key)")
        d.set(target, forKey: "shortcutSteps.\(key)")
        if let meters { d.set(max(meters, self.meters(for: key)), forKey: "shortcutMeters.\(key)") }
        d.set(Date(), forKey: "shortcutLastSync")
    }

    /// Synced totals count straight away, in one go.
    static func steps(for dayKey: String) -> Int {
        max(d.integer(forKey: "shortcutSteps.\(dayKey)"), d.integer(forKey: "shortcutTarget.\(dayKey)"))
    }

    /// True while a synced total is still being fed in.
    static var isRamping: Bool {
        let key = dayKey(Calendar.current.startOfDay(for: .now))
        let target = d.integer(forKey: "shortcutTarget.\(key)")
        return target > 0 && steps(for: key) < target
    }
    static func meters(for dayKey: String) -> Double { d.double(forKey: "shortcutMeters.\(dayKey)") }
    static var lastSync: Date? { d.object(forKey: "shortcutLastSync") as? Date }
}

struct SyncHealthStepsIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Steps to PokéWalk"
    static var description = IntentDescription("Gives PokéWalk today's step total from Apple Health (including your Apple Watch).")
    static var openAppWhenRun = false

    @Parameter(title: "Steps today") var steps: Int
    @Parameter(title: "Distance today (metres)", default: nil) var meters: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Sync \(\.$steps) steps to PokéWalk") { \.$meters }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        ShortcutSteps.record(steps: max(0, steps), meters: meters.map { max(0, $0) })
        await GameStore.shared.tick()
        return .result(dialog: "PokéWalk synced \(steps.formatted()) steps.")
    }
}

struct PokeWalkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SyncHealthStepsIntent(), phrases: ["Sync steps to \(.applicationName)"],
                    shortTitle: "Sync Steps", systemImageName: "figure.walk")
    }
}
