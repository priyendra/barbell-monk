import Engine
import Foundation

/// Where health data comes from: Apple Health in normal use, or generated
/// sample data in dev builds.
protocol HealthSource: Sendable {
    /// True until the user has been shown the Apple Health permission prompt.
    func needsAuthorization() async throws -> Bool
    func requestAuthorization() async throws
    /// Readings in pounds, oldest first.
    func weightReadings(since start: Date) async throws -> [WeightTrend.Reading]
    func activity(from start: Date, to end: Date) async throws -> ActivityData
}

/// Raw activity for a span of days, ready to be split into `ActiveDay`s.
struct ActivityData: Sendable {
    /// Step counts per minute; minutes without steps are left out.
    var steps: [(minute: Date, count: Double)]
    /// Sessions and workouts, with how much each counts toward active time.
    var intervals: [ActiveDay.Interval]
}
