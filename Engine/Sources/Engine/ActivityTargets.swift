import Foundation

/// Daily movement targets: active minutes, plus a minimum of brisk walking
/// outside sessions. Both start from the user's recent baseline and rise
/// slowly while they're being met. They never drop on their own.
public struct ActivityTargets: Sendable, Equatable, Codable {
    public struct Target: Sendable, Equatable, Codable {
        public var minutes: Int
        /// Start of the day this value took effect.
        public var since: Date

        public init(minutes: Int, since: Date) {
            self.minutes = minutes
            self.since = since
        }
    }

    public var active: Target
    public var walking: Target

    /// Used when there's less than a week of history to start from.
    public static let defaultActiveMinutes = 30
    /// The walking minimum never starts below this.
    public static let minimumWalkingMinutes = 20
    public static let step = 5
    public static let activeCeiling = 120
    public static let walkingCeiling = 60
    /// A target rises after this many days...
    public static let reviewDays = 14
    /// ...if it was met on at least this many of them (5 of 7).
    public static let daysMetToRaise = 10

    public init(active: Target, walking: Target) {
        self.active = active
        self.walking = walking
    }

    /// Targets from the median of the last 30 days before `today`.
    public static func initial(history: [ActiveDay], today: Date, calendar: Calendar) -> ActivityTargets {
        let todayStart = calendar.startOfDay(for: today)
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: todayStart)!
        let recent = history.filter { $0.date >= monthAgo && $0.date < todayStart }

        let active: Int
        let walking: Int
        if recent.count >= 7 {
            active = roundedToStep(median(recent.map(\.activeMinutes)))
            walking = max(minimumWalkingMinutes, roundedToStep(median(recent.map { Double($0.walkingMinutes) })))
        } else {
            active = defaultActiveMinutes
            walking = minimumWalkingMinutes
        }
        return ActivityTargets(
            active: Target(minutes: min(active, activeCeiling), since: todayStart),
            walking: Target(minutes: min(walking, walkingCeiling), since: todayStart)
        )
    }

    /// Raises each target by `step` once it has been in place for
    /// `reviewDays` and was met on at least `daysMetToRaise` of them.
    /// Days missing from `history` count as missed.
    public func updated(history: [ActiveDay], today: Date, calendar: Calendar) -> ActivityTargets {
        let todayStart = calendar.startOfDay(for: today)
        func raised(_ target: Target, ceiling: Int, value: (ActiveDay) -> Double) -> Target {
            let age = calendar.dateComponents([.day], from: target.since, to: todayStart).day ?? 0
            guard age >= Self.reviewDays, target.minutes < ceiling else { return target }
            let windowStart = calendar.date(byAdding: .day, value: -Self.reviewDays, to: todayStart)!
            let daysMet = history.filter {
                $0.date >= windowStart && $0.date < todayStart && value($0) >= Double(target.minutes)
            }.count
            guard daysMet >= Self.daysMetToRaise else { return target }
            return Target(minutes: min(target.minutes + Self.step, ceiling), since: todayStart)
        }
        return ActivityTargets(
            active: raised(active, ceiling: Self.activeCeiling) { $0.activeMinutes },
            walking: raised(walking, ceiling: Self.walkingCeiling) { Double($0.walkingMinutes) }
        )
    }

    /// Minutes of brisk walking that would meet both targets today. Walking
    /// counts toward both, so it's the larger of the two shortfalls.
    public func minutesToWalk(today: ActiveDay) -> Int {
        let activeShort = Double(active.minutes) - today.activeMinutes
        let walkingShort = walking.minutes - today.walkingMinutes
        return max(0, Int(ceil(activeShort)), walkingShort)
    }

    private static func roundedToStep(_ minutes: Double) -> Int {
        Int((minutes / Double(step)).rounded()) * step
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
