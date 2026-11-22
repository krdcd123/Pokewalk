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

    /// The latest total from the Shortcut replaces the previous one (so a wrong sync can be corrected).
    static func record(steps: Int, meters: Double?) {
        let key = dayKey(Calendar.current.startOfDay(for: .now))
        d.set(steps, forKey: "shortcutSteps.\(key)")
        for old in ["shortcutTarget", "shortcutFrom", "shortcutAt"] { d.removeObject(forKey: "\(old).\(key)") }
        if let meters { d.set(meters, forKey: "shortcutMeters.\(key)") }
        d.set(Date(), forKey: "shortcutLastSync")
    }

    static func steps(for dayKey: String) -> Int { d.integer(forKey: "shortcutSteps.\(dayKey)") }

    static var isRamping: Bool { false }
    static func meters(for dayKey: String) -> Double { d.double(forKey: "shortcutMeters.\(dayKey)") }
    static var lastSync: Date? { d.object(forKey: "shortcutLastSync") as? Date }
}

/// Calories burned today (Apple Health › Active Energy, which includes your workouts) → in-game money.
struct SyncHealthCaloriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Calories to PokéWalk"
    static var description = IntentDescription("Gives PokéWalk today's active calories from Apple Health. Every 10 kcal you burn earns ₽1.")
    static var openAppWhenRun = false

    @Parameter(title: "Active calories today (kcal)") var calories: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Sync \(\.$calories) kcal to PokéWalk")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let earned = GameStore.shared.syncCalories(calories)
        return .result(dialog: earned > 0 ? "You earned ₽\(earned) in PokéWalk!" : "No new calories since the last sync.")
    }
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
    func perform() async throws -> some IntentResult {
        ShortcutSteps.record(steps: max(0, steps), meters: meters.map { max(0, $0) })
        await GameStore.shared.tick()
        return .result()
    }
}
