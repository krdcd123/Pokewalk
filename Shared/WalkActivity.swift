#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen / Dynamic Island — and, on watchOS 11+, in the
/// Apple Watch Smart Stack automatically (a handy fallback if the Watch app can't be sideloaded).
struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var buddyName: String
        var speciesID: Int
        var level: Int
        var progress: Double
        var stepsToday: Int
        var stepsToEncounter: Int
        var balls: Int
        var pendingEncounters: Int
        var kmToday: Double
        var latestWildName: String?
    }
    var trainerName: String
}
#endif
