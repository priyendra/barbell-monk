import Engine
import Foundation

/// Where body-weight readings come from: Apple Health in normal use, or
/// generated sample data in dev builds.
protocol WeightSource: Sendable {
    /// True until the user has been shown the Apple Health permission prompt.
    func needsAuthorization() async throws -> Bool
    func requestAuthorization() async throws
    /// Readings in pounds, oldest first.
    func weightReadings(since start: Date) async throws -> [WeightTrend.Reading]
}
