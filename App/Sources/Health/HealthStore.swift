import Engine
import Foundation
import HealthKit

/// Reads from and writes to Apple Health, which stays the source of truth
/// for weight, body measurements and activity.
struct HealthStore: WeightSource {
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

    /// Weights the user tells the app are saved to Apple Health.
    private static let shareTypes: Set<HKSampleType> = [bodyMass]

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
