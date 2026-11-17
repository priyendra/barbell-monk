import Foundation

/// Smoothed body-weight trend.
///
/// Daily weight swings with water, salt and food, so the app reports a trend
/// rather than single readings: an exponentially weighted moving average where
/// each day's reading moves the trend by `smoothing` (10% by default, as in
/// The Hacker's Diet).
///
/// Weights can be in any unit, as long as all readings use the same one.
public struct WeightTrend: Sendable {
    public struct Reading: Sendable, Equatable {
        public var date: Date
        public var weight: Double
        public var review: Review

        public init(date: Date, weight: Double, review: Review = .unreviewed) {
            self.date = date
            self.weight = weight
            self.review = review
        }
    }

    /// The user's verdict on a reading, e.g. after being asked "was this you?".
    public enum Review: Sendable, Equatable {
        case unreviewed
        case accepted
        case rejected
    }

    public struct Day: Sendable, Equatable {
        /// Start of the calendar day.
        public var date: Date
        /// The day's earliest reading that fits the trend, or its earliest
        /// reading if none do (in which case the day needs review).
        public var reading: Reading
        /// The trend after this day.
        public var trend: Double
        /// True when the reading is far from the trend and hasn't been reviewed.
        /// Such readings don't move the trend until the user accepts them.
        public var needsReview: Bool
    }

    public struct Rate: Sendable, Equatable {
        /// Change per week in the readings' unit. Negative means losing.
        public var perWeek: Double
        /// `perWeek` as a fraction of the current trend, e.g. -0.005 for -0.5%.
        public var fractionPerWeek: Double

        public enum Pace: Sendable, Equatable {
            case slower, onTarget, faster
        }

        /// Losing 0.5–1% of body weight a week loses fat while keeping muscle.
        public static let fatLossTarget = 0.005...0.01

        /// How this rate compares with a target range of weekly loss, given
        /// as fractions of body weight. Gaining counts as slower.
        public func pace(losing target: ClosedRange<Double> = fatLossTarget) -> Pace {
            let loss = -fractionPerWeek
            if loss < target.lowerBound { return .slower }
            if loss > target.upperBound { return .faster }
            return .onTarget
        }
    }

    /// Readings this far from the trend (as a fraction of it) need review.
    public static let outlierThreshold = 0.05
    /// After a gap longer than this, a reading is trusted even if it's far
    /// from the stale trend. Also caps how much weight a post-gap reading gets.
    public static let maxGapDays = 7

    public let days: [Day]
    private let calendar: Calendar

    public init(readings: [Reading], calendar: Calendar, smoothing: Double = 0.1) {
        self.calendar = calendar
        let readingsByDay = Dictionary(
            grouping: readings.filter { $0.review != .rejected },
            by: { calendar.startOfDay(for: $0.date) }
        )
        .mapValues { $0.sorted { $0.date < $1.date } }
        .sorted { $0.key < $1.key }

        var days: [Day] = []
        var trend: Double?
        var trendDate: Date?
        for (date, candidates) in readingsByDay {
            guard let previous = trend, let previousDate = trendDate else {
                let reading = candidates[0]
                trend = reading.weight
                trendDate = date
                days.append(Day(date: date, reading: reading, trend: reading.weight, needsReview: false))
                continue
            }
            let gap = calendar.dateComponents([.day], from: previousDate, to: date).day ?? 1
            // Use the day's earliest reading that fits the trend, so someone
            // else stepping on the scale first doesn't hide the user's reading.
            let fits = { (reading: Reading) in
                reading.review == .accepted || gap > Self.maxGapDays
                    || abs(reading.weight - previous) / previous <= Self.outlierThreshold
            }
            guard let reading = candidates.first(where: fits) else {
                days.append(Day(date: date, reading: candidates[0], trend: previous, needsReview: true))
                continue
            }
            // A reading after skipped days stands in for the missing ones too.
            let weight = 1 - pow(1 - smoothing, Double(min(max(gap, 1), Self.maxGapDays)))
            let updated = previous + weight * (reading.weight - previous)
            trend = updated
            trendDate = date
            days.append(Day(date: date, reading: reading, trend: updated, needsReview: false))
        }
        self.days = days
    }

    /// The latest trend value, or nil when there are no readings.
    public var current: Double? {
        days.last { !$0.needsReview }?.trend
    }

    /// Readings waiting for the user to accept or reject them.
    public var needingReview: [Day] {
        days.filter(\.needsReview)
    }

    /// Weekly rate of change: the least-squares slope of the trend over the
    /// last `window` days. Nil when the counted days span less than a week.
    public func weeklyRate(window: Int = 14) -> Rate? {
        let counted = days.filter { !$0.needsReview }
        guard let last = counted.last else { return nil }
        let points = counted.compactMap { day -> (x: Double, y: Double)? in
            let offset = calendar.dateComponents([.day], from: last.date, to: day.date).day ?? 0
            return offset >= -window ? (Double(offset), day.trend) : nil
        }
        guard let first = points.first, first.x <= -7 else { return nil }

        let n = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        let covariance = points.map { ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +)
        let variance = points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        guard variance > 0 else { return nil }

        let perWeek = covariance / variance * 7
        return Rate(perWeek: perWeek, fractionPerWeek: perWeek / last.trend)
    }
}
