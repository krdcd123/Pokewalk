import Foundation
import HealthKit

/// Thin async wrapper over HealthKit's step count. On iPhone this already merges
/// iPhone + Apple Watch steps without double counting (cumulative-sum statistics).
final class StepCounter {
    static let shared = StepCounter()

    let store = HKHealthStore()
    let stepType = HKQuantityType(.stepCount)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [stepType])
    }

    /// Total steps in [start, end).
    func steps(from start: Date, to end: Date = .now) async throws -> Int {
        guard isAvailable, start < end else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(quantityType: stepType,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    cont.resume(returning: 0)
                } else if let error {
                    cont.resume(throwing: error)
                } else {
                    let value = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    cont.resume(returning: Int(value))
                }
            }
            store.execute(query)
        }
    }

    func stepsToday() async throws -> Int {
        try await steps(from: Calendar.current.startOfDay(for: .now))
    }

    /// Steps per day for the last `days` days (oldest first).
    func dailySteps(days: Int) async throws -> [(date: Date, steps: Int)] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86_400)
        let start = cal.date(byAdding: .day, value: -days, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(quantityType: stepType,
                                                    quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum,
                                                    anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { cont.resume(throwing: error); return }
                var out: [(date: Date, steps: Int)] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    out.append((date: stats.startDate, steps: Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }
}

extension StepCounter {
    private var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }

    func requestAuthorizationWithDistance() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [stepType, distanceType])
    }

    /// Walking + running distance in metres in [start, end).
    func distance(from start: Date, to end: Date = .now) async throws -> Double {
        guard isAvailable, start < end else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: distanceType, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, error in
                if let error = error as? HKError, error.code == .errorNoData { cont.resume(returning: 0); return }
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .meter()) ?? 0)
            }
            store.execute(q)
        }
    }

    /// Steps on one calendar day.
    func steps(onDayStarting day: Date) async throws -> Int {
        try await steps(from: day, to: min(.now, day.addingTimeInterval(86_400)))
    }
}
