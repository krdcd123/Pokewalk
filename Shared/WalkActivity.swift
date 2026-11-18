#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Lock Screen Live Activity (also shown in the Apple Watch Smart Stack on watchOS 11+).
/// The buddy's sprite travels inside the state, so the extension needs no App Group.
struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var buddyName: String
        var speciesID: Int
        var level: Int
        var progress: Double
        var expToNext: Int
        var stepsToday: Int
        var stepsToEncounter: Int
        var pendingEncounters: Int
        var kmToday: Double
        var spritePNG: Data?
    }
    var trainerName: String
}
#endif
