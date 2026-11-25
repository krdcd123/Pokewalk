import Foundation

/// One sleep sample, from Apple Health or sent straight from the watch app to the iPhone
/// (the iPhone's Apple Health can take a while to receive the watch's sleep in the morning).
struct WatchSleepSample: Codable, Equatable {
    var value: Int          // HKCategoryValueSleepAnalysis raw value
    var start: Date
    var end: Date
    var source: String
}
