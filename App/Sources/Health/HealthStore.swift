import Engine
import Foundation
import HealthKit

/// Reads from and writes to Apple Health, which stays the source of truth
/// for weight, body measurements and activity.
struct HealthStore: HealthSource {
    private let store = HKHealthStore()

    private static let bodyMass = HKQuantityType(.bodyMass)

    /// Everything the app reads. Requested together so the user sees one prompt.
    private static let readTypes: Set<HKObjectType> = [
        bodyMass,
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.stepCount),
        HKQuantityType(.appleExerciseTime),
        HKObjectType.workoutType(),
    ]

    /// Weights the user tells the app are saved to Apple Health. In the
    /// simulator, sample steps and workouts are written too.
    private static var shareTypes: Set<HKSampleType> {
        #if DEBUG && targetEnvironment(simulator)
        [bodyMass, HKQuantityType(.stepCount), HKObjectType.workoutType()]
        #else
        [bodyMass]
        #endif
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func needsAuthorization() async throws -> Bool {
        let status = try await store.statusForAuthorizationRequest(
            toShare: Self.shareTypes, read: Self.readTypes
        )
        return status != .unnecessary
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    func weightReadings(since start: Date) async throws -> [WeightTrend.Reading] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: Self.bodyMass,
                predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            WeightTrend.Reading(date: $0.startDate, weight: $0.quantity.doubleValue(for: .pound()))
        }
    }

    func activity(from start: Date, to end: Date) async throws -> ActivityData {
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        // Per-minute sums; Health merges Watch and iPhone counts.
        let stepsQuery = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: range),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(minute: 1)
        )
        let steps = try await stepsQuery.result(for: store).statistics().compactMap { minute in
            minute.sumQuantity().map { (minute: minute.startDate, count: $0.doubleValue(for: .count())) }
        }

        let workoutsQuery = HKSampleQueryDescriptor(
            predicates: [.workout(range)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let intervals = try await workoutsQuery.result(for: store).compactMap { workout in
            Self.credit(for: workout.workoutActivityType).map {
                ActiveDay.Interval(start: workout.startDate, end: workout.endDate, credit: $0)
            }
        }
        return ActivityData(steps: steps, intervals: intervals)
    }

    /// Calls `onUpdate` when new steps or workouts arrive, including when iOS
    /// wakes the app in the background for them (at most hourly).
    func observeActivity(onUpdate: @escaping @Sendable () async -> Void) {
        let types: [HKSampleType] = [HKQuantityType(.stepCount), HKObjectType.workoutType()]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { return completion() }
                // HealthKit's completion handler can be called from any thread,
                // but isn't annotated Sendable. Calling it after the update
                // keeps the app awake in the background until the work is done.
                nonisolated(unsafe) let completion = completion
                Task {
                    await onUpdate()
                    completion()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    /// How much a workout counts toward active time. Walks are left out
    /// because their brisk minutes already count through steps.
    static func credit(for type: HKWorkoutActivityType) -> Double? {
        switch type {
        case .walking: nil
        case .yoga, .flexibility, .mindAndBody, .taiChi, .cooldown, .preparationAndRecovery: 0.5
        default: 1
        }
    }

    /// Saves weights in pounds, e.g. sample data in dev builds.
    func save(weights: [(date: Date, pounds: Double)]) async throws {
        let samples = weights.map {
            HKQuantitySample(
                type: Self.bodyMass,
                quantity: HKQuantity(unit: .pound(), doubleValue: $0.pounds),
                start: $0.date, end: $0.date
            )
        }
        try await store.save(samples)
    }
}

#if DEBUG && targetEnvironment(simulator)
extension HealthStore {
    /// Writes sample steps and workouts. Simulator only: the simulator's
    /// Health is separate from the phone's.
    func save(_ activity: SampleData.Activity) async throws {
        let steps = activity.steps.map {
            HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: $0.count),
                start: $0.start, end: $0.end
            )
        }
        try await store.save(steps)
        for workout in activity.workouts {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = workout.type
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: workout.start)
            try await builder.endCollection(at: workout.end)
            _ = try await builder.finishWorkout()
        }
    }
}
#endif
