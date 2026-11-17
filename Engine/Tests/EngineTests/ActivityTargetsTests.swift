import Foundation
import Testing
@testable import Engine

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private let today = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 18))!

private func daysAgo(_ n: Int) -> Date {
    calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: today))!
}

/// History for the `count` days before today, with values chosen per day.
private func history(
    days count: Int, active: (Int) -> Double, walking: (Int) -> Int = { _ in 0 }
) -> [ActiveDay] {
    (1...count).map { ActiveDay(date: daysAgo($0), activeMinutes: active($0), walkingMinutes: walking($0)) }
}

private func targets(active: Int, walking: Int, setDaysAgo: Int) -> ActivityTargets {
    ActivityTargets(
        active: .init(minutes: active, since: daysAgo(setDaysAgo)),
        walking: .init(minutes: walking, since: daysAgo(setDaysAgo))
    )
}

@Suite struct ActivityTargetsTests {
    @Test func startsFromTheMedianOfTheLastMonth() {
        // Active minutes 21...50 (median 35.5 → 35); walking median 33 → 35.
        let past = history(days: 30, active: { Double(20 + $0) }, walking: { _ in 33 })
        let initial = ActivityTargets.initial(history: past, today: today, calendar: calendar)
        #expect(initial.active.minutes == 35)
        #expect(initial.walking.minutes == 35)
        #expect(initial.active.since == calendar.startOfDay(for: today))
    }

    @Test func walkingMinimumStartsAtTwentyMinutes() {
        let past = history(days: 30, active: { _ in 40 }, walking: { _ in 8 })
        let initial = ActivityTargets.initial(history: past, today: today, calendar: calendar)
        #expect(initial.walking.minutes == 20)
    }

    @Test func usesDefaultsWithLessThanAWeekOfHistory() {
        let past = history(days: 5, active: { _ in 80 }, walking: { _ in 40 })
        let initial = ActivityTargets.initial(history: past, today: today, calendar: calendar)
        #expect(initial.active.minutes == ActivityTargets.defaultActiveMinutes)
        #expect(initial.walking.minutes == ActivityTargets.minimumWalkingMinutes)
    }

    @Test func ignoresHistoryOlderThanAMonthAndToday() {
        let old = history(days: 60, active: { $0 > 30 ? 200 : 40 })
        let todaySoFar = ActiveDay(date: calendar.startOfDay(for: today), activeMinutes: 0, walkingMinutes: 0)
        let initial = ActivityTargets.initial(history: old + [todaySoFar], today: today, calendar: calendar)
        #expect(initial.active.minutes == 40)
    }

    @Test func raisesAfterTwoWeeksMetOnTenDays() {
        let current = targets(active: 40, walking: 20, setDaysAgo: 14)
        let past = history(days: 14, active: { $0 <= 10 ? 45 : 10 }, walking: { $0 <= 10 ? 25 : 0 })
        let next = current.updated(history: past, today: today, calendar: calendar)
        #expect(next.active.minutes == 45)
        #expect(next.walking.minutes == 25)
        #expect(next.active.since == calendar.startOfDay(for: today))
    }

    @Test func holdsWhenMetOnFewerThanTenDays() {
        let current = targets(active: 40, walking: 20, setDaysAgo: 14)
        let past = history(days: 14, active: { $0 <= 9 ? 45 : 10 }, walking: { $0 <= 9 ? 25 : 0 })
        #expect(current.updated(history: past, today: today, calendar: calendar) == current)
    }

    @Test func holdsUntilTwoWeeksHavePassed() {
        let current = targets(active: 40, walking: 20, setDaysAgo: 13)
        let past = history(days: 14, active: { _ in 90 }, walking: { _ in 50 })
        #expect(current.updated(history: past, today: today, calendar: calendar) == current)
    }

    @Test func missingDaysCountAsMissed() {
        // Only 9 days of data in the window, all met: not enough.
        let current = targets(active: 40, walking: 20, setDaysAgo: 14)
        let past = history(days: 9, active: { _ in 90 }, walking: { _ in 50 })
        #expect(current.updated(history: past, today: today, calendar: calendar) == current)
    }

    @Test func targetsRiseIndependently() {
        let current = targets(active: 40, walking: 20, setDaysAgo: 14)
        let past = history(days: 14, active: { _ in 90 }, walking: { _ in 5 })
        let next = current.updated(history: past, today: today, calendar: calendar)
        #expect(next.active.minutes == 45)
        #expect(next.walking == current.walking)
    }

    @Test func stopsAtTheCeiling() {
        let current = targets(active: 118, walking: ActivityTargets.walkingCeiling, setDaysAgo: 14)
        let past = history(days: 14, active: { _ in 200 }, walking: { _ in 90 })
        let next = current.updated(history: past, today: today, calendar: calendar)
        #expect(next.active.minutes == ActivityTargets.activeCeiling)
        #expect(next.walking == current.walking)
    }

    @Test(arguments: [
        // (active so far, walking so far, minutes to walk)
        (60.0, 20, 0),   // both met
        (60.0, 5, 15),   // walking short by 15
        (30.0, 25, 30),  // active short by 30
        (52.5, 12, 8),   // active short 7.5 → 8; walking short 8
    ])
    func minutesToWalkCoversBothShortfalls(active: Double, walking: Int, expected: Int) {
        let current = targets(active: 60, walking: 20, setDaysAgo: 3)
        let soFar = ActiveDay(date: calendar.startOfDay(for: today), activeMinutes: active, walkingMinutes: walking)
        #expect(current.minutesToWalk(today: soFar) == expected)
    }
}
