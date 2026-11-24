import Foundation
import HealthKit

/// Every workout you can start from PokéWalk (phone or watch). Recorded by the watch like Apple's
/// Workout app and saved to Apple Health; step rewards pause for anything that isn't walking.
struct WorkoutKind: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let type: HKWorkoutActivityType
    let indoor: Bool
    var poolSwim: Bool = false

    /// Walking, running and hiking steps are real steps; everything else pauses step rewards.
    var countsSteps: Bool { [.walking, .running, .hiking].contains(type) }
    var isCycling: Bool { type == .cycling }
    var isSwimming: Bool { type == .swimming }
    /// Distance is worth showing for these.
    var tracksDistance: Bool { [.walking, .running, .hiking, .cycling, .swimming, .rowing].contains(type) }

    var configuration: HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration()
        c.activityType = type
        c.locationType = indoor ? .indoor : .outdoor
        if type == .swimming {
            c.swimmingLocationType = poolSwim ? .pool : .openWater
            if poolSwim { c.lapLength = HKQuantity(unit: .meter(), doubleValue: 25) }
        }
        return c
    }

    var distanceType: HKQuantityType? {
        switch type {
        case .cycling: return HKQuantityType(.distanceCycling)
        case .swimming: return HKQuantityType(.distanceSwimming)
        case .walking, .running, .hiking: return HKQuantityType(.distanceWalkingRunning)
        default: return nil
        }
    }

    static let all: [WorkoutKind] = [
        .init(id: "walk-out", name: "Outdoor Walk", symbol: "figure.walk", type: .walking, indoor: false),
        .init(id: "walk-in", name: "Indoor Walk", symbol: "figure.walk.treadmill", type: .walking, indoor: true),
        .init(id: "run-out", name: "Outdoor Run", symbol: "figure.run", type: .running, indoor: false),
        .init(id: "run-in", name: "Indoor Run", symbol: "figure.run.treadmill", type: .running, indoor: true),
        .init(id: "cycle-out", name: "Outdoor Cycle", symbol: "figure.outdoor.cycle", type: .cycling, indoor: false),
        .init(id: "cycle-in", name: "Indoor Cycle", symbol: "figure.indoor.cycle", type: .cycling, indoor: true),
        .init(id: "hike", name: "Hiking", symbol: "figure.hiking", type: .hiking, indoor: false),
        .init(id: "swim-pool", name: "Pool Swim", symbol: "figure.pool.swim", type: .swimming, indoor: true, poolSwim: true),
        .init(id: "swim-open", name: "Open Water Swim", symbol: "figure.open.water.swim", type: .swimming, indoor: false),
        .init(id: "elliptical", name: "Elliptical", symbol: "figure.elliptical", type: .elliptical, indoor: true),
        .init(id: "rower", name: "Rower", symbol: "figure.rower", type: .rowing, indoor: true),
        .init(id: "stairs", name: "Stair Stepper", symbol: "figure.stair.stepper", type: .stairClimbing, indoor: true),
        .init(id: "hiit", name: "HIIT", symbol: "figure.highintensity.intervaltraining", type: .highIntensityIntervalTraining, indoor: true),
        .init(id: "strength", name: "Strength", symbol: "figure.strengthtraining.traditional", type: .traditionalStrengthTraining, indoor: true),
        .init(id: "functional", name: "Functional Strength", symbol: "figure.strengthtraining.functional", type: .functionalStrengthTraining, indoor: true),
        .init(id: "core", name: "Core Training", symbol: "figure.core.training", type: .coreTraining, indoor: true),
        .init(id: "yoga", name: "Yoga", symbol: "figure.yoga", type: .yoga, indoor: true),
        .init(id: "pilates", name: "Pilates", symbol: "figure.pilates", type: .pilates, indoor: true),
        .init(id: "dance", name: "Dance", symbol: "figure.dance", type: .cardioDance, indoor: true),
        .init(id: "boxing", name: "Boxing", symbol: "figure.boxing", type: .boxing, indoor: true),
        .init(id: "kickboxing", name: "Kickboxing", symbol: "figure.kickboxing", type: .kickboxing, indoor: true),
        .init(id: "taichi", name: "Tai Chi", symbol: "figure.taichi", type: .taiChi, indoor: true),
        .init(id: "football", name: "Football", symbol: "figure.soccer", type: .soccer, indoor: false),
        .init(id: "basketball", name: "Basketball", symbol: "figure.basketball", type: .basketball, indoor: false),
        .init(id: "tennis", name: "Tennis", symbol: "figure.tennis", type: .tennis, indoor: false),
        .init(id: "cooldown", name: "Cooldown", symbol: "figure.cooldown", type: .cooldown, indoor: true),
        .init(id: "other", name: "Other", symbol: "figure.mixed.cardio", type: .other, indoor: true),
    ]

    static func kind(id: String) -> WorkoutKind? { all.first { $0.id == id } }

    static func kind(for c: HKWorkoutConfiguration) -> WorkoutKind {
        if c.activityType == .swimming {
            return kind(id: c.swimmingLocationType == .pool ? "swim-pool" : "swim-open")!
        }
        return all.first { $0.type == c.activityType && $0.indoor == (c.locationType == .indoor) }
            ?? all.first { $0.type == c.activityType }
            ?? WorkoutKind(id: "other", name: "Workout", symbol: "figure.mixed.cardio", type: c.activityType, indoor: true)
    }

    /// What can be written to Apple Health for a workout.
    static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
         HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
         HKQuantityType(.swimmingStrokeCount), HKSeriesType.workoutRoute()]
    }
    static var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
         HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
         HKQuantityType(.stepCount)]
    }
}

/// Live numbers sent from the watch to the phone during a workout.
struct WorkoutLive: Codable, Equatable {
    var kindID: String
    var start: Date
    var elapsed: TimeInterval        // excluding pauses
    var paused: Bool
    var kcal: Double
    var meters: Double
    var heartRate: Double?
    var ended = false
}
