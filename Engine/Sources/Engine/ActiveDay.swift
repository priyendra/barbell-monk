import Foundation

/// One day's active minutes.
///
/// Active time combines sessions and workouts (each a time interval with a
/// credit: 1 for lifting, core or cardio; 0.5 for low-effort work like
/// mobility) with brisk walking, meaning minutes of at least `briskCadence`
/// steps. Each minute counts once, at the highest credit that applies, so
/// walking on the pad during a cardio session isn't double counted.
public struct ActiveDay: Sendable, Equatable {
    public struct Interval: Sendable, Equatable {
        public var start: Date
        public var end: Date
        /// 1 for full effort, 0.5 for low-effort work such as mobility.
        public var credit: Double

        public init(start: Date, end: Date, credit: Double) {
            self.start = start
            self.end = end
            self.credit = credit
        }
    }

    /// About 100 steps a minute is where walking becomes moderate effort.
    public static let briskCadence = 100.0

    /// Active minutes, counting low-effort minutes at their credit.
    public let activeMinutes: Double
    /// Brisk walking minutes outside sessions and workouts. These count
    /// toward the daily walking minimum.
    public let walkingMinutes: Int

    /// - Parameters:
    ///   - day: Any time on the day to count.
    ///   - steps: Step counts per minute, keyed by any time within the minute.
    ///   - intervals: Sessions and workouts; parts outside the day are ignored.
    public init(
        day: Date,
        steps: [(minute: Date, count: Double)],
        intervals: [Interval],
        calendar: Calendar,
        briskCadence: Double = briskCadence
    ) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        // Daylight-saving days have 23 or 25 hours.
        let minuteCount = Int(dayEnd.timeIntervalSince(dayStart) / 60)

        var credit = Array(repeating: 0.0, count: minuteCount)
        var covered = Array(repeating: false, count: minuteCount)
        for interval in intervals {
            let start = max(interval.start, dayStart)
            let end = min(interval.end, dayEnd)
            guard start < end else { continue }
            let first = Int(start.timeIntervalSince(dayStart) / 60)
            let last = min(Int(ceil(end.timeIntervalSince(dayStart) / 60)), minuteCount) - 1
            for minute in first...last {
                let minuteStart = dayStart.addingTimeInterval(Double(minute) * 60)
                let overlap = min(end, minuteStart.addingTimeInterval(60)).timeIntervalSince(max(start, minuteStart))
                let fraction = overlap / 60
                credit[minute] = max(credit[minute], interval.credit * fraction)
                if fraction >= 0.5 { covered[minute] = true }
            }
        }

        var stepsPerMinute: [Int: Double] = [:]
        for (time, count) in steps where time >= dayStart && time < dayEnd {
            stepsPerMinute[Int(time.timeIntervalSince(dayStart) / 60), default: 0] += count
        }
        var walkingMinutes = 0
        for (minute, count) in stepsPerMinute where count >= briskCadence {
            credit[minute] = max(credit[minute], 1)
            if !covered[minute] { walkingMinutes += 1 }
        }

        self.activeMinutes = credit.reduce(0, +)
        self.walkingMinutes = walkingMinutes
    }
}
