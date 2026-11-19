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
        var kmToday: Double            // shown as miles
        var spritePNG: Data?
        var iconPNG: Data? = nil       // party/box icon for the Dynamic Island
        var tintHex: UInt32? = nil     // buddy's main type colour, for the Watch accent
        var hop = false                // flips as you walk, so the icon bobs like the PC box icons
    }
    var trainerName: String
}
#endif
