#if DEBUG
import Engine
import Foundation

/// Realistic-looking history for dev builds: 90 days of slow loss with daily
/// water swings, skipped days, a few evening weigh-ins, and one morning where
/// someone else stepped on the scale first. Seeded, so screenshots are stable.
enum SampleData {
    static func weights(
        days: Int = 90, endingAt end: Date = .now, calendar: Calendar = .current
    ) -> [(date: Date, pounds: Double)] {
        var rng = SplitMix64(seed: 42)
        let today = calendar.startOfDay(for: end)
        var weights: [(date: Date, pounds: Double)] = []
        for daysAgo in stride(from: days - 1, through: 0, by: -1) {
            let skipped = Double.random(in: 0..<1, using: &rng) < 0.12
            let noise = Double.random(in: -1.2...1.2, using: &rng)
            let minute = Int.random(in: 30...59, using: &rng)
            guard !skipped || daysAgo == 0 else { continue }

            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let elapsed = Double(days - 1 - daysAgo)
            let pounds = 195 - elapsed * 0.75 / 7 + 0.8 * sin(elapsed / 3) + noise
            let morning = calendar.date(bySettingHour: 6, minute: minute, second: 0, of: day)!
            weights.append((morning, rounded(pounds)))

            if daysAgo % 17 == 5 {
                let evening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day)!
                weights.append((evening, rounded(pounds + 2.5)))
            }
            if daysAgo == 10 {
                let someoneElse = calendar.date(bySettingHour: 6, minute: 5, second: 0, of: day)!
                weights.append((someoneElse, 142.6))
            }
        }
        return weights
    }

    private static func rounded(_ pounds: Double) -> Double {
        (pounds * 10).rounded() / 10
    }
}

/// Serves `SampleData` without touching Apple Health. Selected with the
/// `-sampleData` launch argument, so screens can be checked without the
/// permission prompt.
struct SampleWeightSource: WeightSource {
    func needsAuthorization() async throws -> Bool { false }
    func requestAuthorization() async throws {}

    func weightReadings(since start: Date) async throws -> [WeightTrend.Reading] {
        SampleData.weights()
            .filter { $0.date >= start }
            .map { WeightTrend.Reading(date: $0.date, weight: $0.pounds) }
    }
}

/// Small seeded generator (SplitMix64), so sample data is the same every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
