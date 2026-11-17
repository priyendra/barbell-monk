#if DEBUG
import Engine
import Foundation
import HealthKit

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

    struct Activity {
        /// Step samples as Health stores them: a count spread over a span.
        var steps: [(start: Date, end: Date, count: Double)]
        var workouts: [(type: HKWorkoutActivityType, start: Date, end: Date)]
    }

    /// A month of activity following the planned week: lifting Mon/Wed/Fri,
    /// core + cardio Tue/Sat, cycling then yoga Thu/Sun, with some sessions
    /// skipped. Most days add a midday brisk walk; background steps through
    /// the day are too slow to count.
    static func activity(
        days: Int = 31, endingAt end: Date = .now, calendar: Calendar = .current
    ) -> Activity {
        var rng = SplitMix64(seed: 7)
        let today = calendar.startOfDay(for: end)
        var activity = Activity(steps: [], workouts: [])
        for daysAgo in stride(from: days - 1, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            for hour in 8...21 {
                let count = Double(Int.random(in: 150...450, using: &rng))
                activity.steps.append((at(hour), at(hour + 1), count))
            }
            if Double.random(in: 0..<1, using: &rng) < 0.75 {
                let minutes = Double(Int.random(in: 15...35, using: &rng))
                let cadence = Double.random(in: 105...120, using: &rng)
                activity.steps.append((at(12, 15), at(12, 15).addingTimeInterval(minutes * 60), cadence * minutes))
            }
            guard Double.random(in: 0..<1, using: &rng) >= 0.15 else { continue }
            let start = at(7)
            func minutes(_ n: Double, after date: Date) -> Date { date.addingTimeInterval(n * 60) }
            switch calendar.component(.weekday, from: day) {
            case 2, 4, 6:  // Mon, Wed, Fri
                activity.workouts.append((.traditionalStrengthTraining, start, minutes(60, after: start)))
            case 3, 7:  // Tue, Sat
                activity.workouts.append((.coreTraining, start, minutes(60, after: start)))
            default:  // Thu, Sun
                let yogaStart = minutes(25, after: start)
                activity.workouts.append((.cycling, start, yogaStart))
                activity.workouts.append((.yoga, yogaStart, minutes(35, after: yogaStart)))
            }
        }
        // Only what has already happened by `end`.
        activity.steps.removeAll { $0.end > end }
        activity.workouts.removeAll { $0.end > end }
        return activity
    }
}

/// Serves `SampleData` without touching Apple Health. Selected with the
/// `-sampleData` launch argument, so screens can be checked without the
/// permission prompt.
struct SampleHealthSource: HealthSource {
    func needsAuthorization() async throws -> Bool { false }
    func requestAuthorization() async throws {}

    func weightReadings(since start: Date) async throws -> [WeightTrend.Reading] {
        SampleData.weights()
            .filter { $0.date >= start }
            .map { WeightTrend.Reading(date: $0.date, weight: $0.pounds) }
    }

    /// Spreads each step sample evenly over its minutes, the way Health's
    /// per-minute statistics do.
    func activity(from start: Date, to end: Date) async throws -> ActivityData {
        let sample = SampleData.activity()
        var steps: [(minute: Date, count: Double)] = []
        for span in sample.steps where span.end > start && span.start < end {
            let minutes = Int(span.end.timeIntervalSince(span.start) / 60)
            for offset in 0..<minutes {
                let minute = span.start.addingTimeInterval(Double(offset) * 60)
                if minute >= start && minute < end {
                    steps.append((minute, span.count / Double(minutes)))
                }
            }
        }
        let intervals = sample.workouts
            .filter { $0.end > start && $0.start < end }
            .compactMap { workout in
                HealthStore.credit(for: workout.type).map {
                    ActiveDay.Interval(start: workout.start, end: workout.end, credit: $0)
                }
            }
        return ActivityData(steps: steps, intervals: intervals)
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
