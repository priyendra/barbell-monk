import Foundation
import Testing
@testable import Engine

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

/// A reading on day `n` after `start`, at 7am by default.
private func reading(
    _ n: Int, _ weight: Double, hour: Int = 7, review: WeightTrend.Review = .unreviewed
) -> WeightTrend.Reading {
    let day = calendar.date(byAdding: .day, value: n, to: start)!
    let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    return WeightTrend.Reading(date: date, weight: weight, review: review)
}

private func isClose(_ a: Double?, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tolerance
}

@Suite struct WeightTrendTests {
    @Test func noReadingsHasNoTrend() {
        let trend = WeightTrend(readings: [], calendar: calendar)
        #expect(trend.days.isEmpty)
        #expect(trend.current == nil)
        #expect(trend.weeklyRate() == nil)
    }

    @Test func firstReadingSeedsTheTrend() {
        let trend = WeightTrend(readings: [reading(0, 200)], calendar: calendar)
        #expect(trend.current == 200)
    }

    @Test func eachReadingMovesTheTrendTenPercent() {
        let trend = WeightTrend(readings: [reading(0, 200), reading(1, 198)], calendar: calendar)
        #expect(isClose(trend.current, 199.8))
    }

    @Test func readingOrderDoesNotMatter() {
        let readings = [reading(2, 197), reading(0, 200), reading(1, 198)]
        let shuffled = WeightTrend(readings: readings, calendar: calendar)
        let sorted = WeightTrend(readings: readings.sorted { $0.date < $1.date }, calendar: calendar)
        #expect(shuffled.days == sorted.days)
    }

    @Test func usesFirstReadingOfTheDay() {
        let trend = WeightTrend(
            readings: [reading(0, 203, hour: 21), reading(0, 200, hour: 7)],
            calendar: calendar
        )
        #expect(trend.days.count == 1)
        #expect(trend.current == 200)
    }

    @Test func readingAfterSkippedDayCountsMore() {
        // Two days since the last reading: weight is 1 - 0.9^2 = 0.19.
        let trend = WeightTrend(readings: [reading(0, 200), reading(2, 198)], calendar: calendar)
        #expect(isClose(trend.current, 200 - 0.19 * 2))
    }

    @Test func farOffReadingIsSetAsideForReview() {
        let readings = (0..<6).map { reading($0, 200) } + [reading(6, 220)]
        let trend = WeightTrend(readings: readings, calendar: calendar)
        #expect(trend.current == 200)
        #expect(trend.needingReview.map(\.reading.weight) == [220])
    }

    @Test func acceptedReadingCountsEvenIfFarOff() {
        let readings = (0..<6).map { reading($0, 200) } + [reading(6, 220, review: .accepted)]
        let trend = WeightTrend(readings: readings, calendar: calendar)
        #expect(isClose(trend.current, 202))
        #expect(trend.needingReview.isEmpty)
    }

    @Test func rejectedReadingIsIgnored() {
        // Someone else stepped on the scale first; the user's own reading came later.
        let trend = WeightTrend(
            readings: [
                reading(0, 200),
                reading(1, 150, hour: 6, review: .rejected),
                reading(1, 202, hour: 7),
            ],
            calendar: calendar
        )
        #expect(trend.days.map(\.reading.weight) == [200, 202])
        #expect(isClose(trend.current, 200.2))
    }

    @Test func readingAfterLongGapIsTrusted() {
        // Back from two weeks away, 7.5% lighter: not an outlier, and it
        // gets the capped post-gap weight of 1 - 0.9^7.
        let trend = WeightTrend(readings: [reading(0, 200), reading(14, 185)], calendar: calendar)
        #expect(trend.needingReview.isEmpty)
        #expect(isClose(trend.current, 200 - (1 - pow(0.9, 7)) * 15))
    }

    @Test func weeklyRateNeedsAtLeastAWeekOfData() {
        let trend = WeightTrend(readings: (0..<5).map { reading($0, 200) }, calendar: calendar)
        #expect(trend.weeklyRate() == nil)
    }

    @Test func weeklyRateMatchesSteadyLoss() {
        // Losing exactly 1 lb a week for 60 days. The trend lags the latest
        // reading (191.57) by about 9 days' worth of loss, so it sits near 192.86.
        let readings = (0..<60).map { reading($0, 200 - Double($0) / 7) }
        let trend = WeightTrend(readings: readings, calendar: calendar)
        let rate = trend.weeklyRate()
        #expect(isClose(trend.current, 192.86, tolerance: 0.01))
        #expect(isClose(rate?.perWeek, -1.0, tolerance: 0.02))
        #expect(isClose(rate?.fractionPerWeek, -1.0 / 192.86, tolerance: 0.0001))
    }

    @Test func weeklyRateIgnoresReadingsAwaitingReview() {
        let readings = (0..<20).map { reading($0, 200) } + [reading(20, 230)]
        let rate = WeightTrend(readings: readings, calendar: calendar).weeklyRate()
        #expect(isClose(rate?.perWeek, 0))
    }

    @Test func dayBoundariesFollowTheCalendarAcrossDaylightSaving() {
        // US clocks spring forward on 2026-03-08. Readings at 7am on the 7th
        // and 9th are two calendar days apart.
        let trend = WeightTrend(readings: [reading(65, 200), reading(67, 198)], calendar: calendar)
        #expect(isClose(trend.current, 200 - 0.19 * 2))
    }
}
