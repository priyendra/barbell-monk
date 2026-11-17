import Foundation
import Testing
@testable import Engine

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

/// 2026-03-03, an ordinary 24-hour day.
private let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3))!

private func at(_ hour: Int, _ minute: Int = 0, second: Int = 0, on base: Date = day) -> Date {
    calendar.date(bySettingHour: hour, minute: minute, second: second, of: base)!
}

/// `count` steps in each minute from `start` for `minutes` minutes.
private func walk(from start: Date, minutes: Int, stepsPerMinute count: Double) -> [(minute: Date, count: Double)] {
    (0..<minutes).map { (start.addingTimeInterval(Double($0) * 60), count) }
}

private func session(_ start: Date, minutes: Double, credit: Double = 1) -> ActiveDay.Interval {
    ActiveDay.Interval(start: start, end: start.addingTimeInterval(minutes * 60), credit: credit)
}

@Suite struct ActiveDayTests {
    @Test func emptyDayHasNoActiveTime() {
        let active = ActiveDay(day: day, steps: [], intervals: [], calendar: calendar)
        #expect(active.activeMinutes == 0)
        #expect(active.walkingMinutes == 0)
    }

    @Test func sessionCountsInFull() {
        let active = ActiveDay(day: day, steps: [], intervals: [session(at(7), minutes: 60)], calendar: calendar)
        #expect(active.activeMinutes == 60)
        #expect(active.walkingMinutes == 0)
    }

    @Test func lowEffortWorkCountsAtItsCredit() {
        let active = ActiveDay(
            day: day, steps: [], intervals: [session(at(7), minutes: 30, credit: 0.5)], calendar: calendar
        )
        #expect(active.activeMinutes == 15)
    }

    @Test func briskWalkingCountsTowardBoth() {
        let active = ActiveDay(
            day: day, steps: walk(from: at(12), minutes: 20, stepsPerMinute: 115), intervals: [], calendar: calendar
        )
        #expect(active.activeMinutes == 20)
        #expect(active.walkingMinutes == 20)
    }

    @Test func slowWalkingDoesNotCount() {
        let active = ActiveDay(
            day: day, steps: walk(from: at(12), minutes: 30, stepsPerMinute: 70), intervals: [], calendar: calendar
        )
        #expect(active.activeMinutes == 0)
        #expect(active.walkingMinutes == 0)
    }

    @Test func walkingDuringASessionIsNotDoubleCounted() {
        // Cardio on the walking pad inside a session.
        let active = ActiveDay(
            day: day,
            steps: walk(from: at(7), minutes: 30, stepsPerMinute: 110),
            intervals: [session(at(7), minutes: 30)],
            calendar: calendar
        )
        #expect(active.activeMinutes == 30)
        #expect(active.walkingMinutes == 0)
    }

    @Test func briskWalkingRaisesLowEffortMinutesToFullCredit() {
        let active = ActiveDay(
            day: day,
            steps: walk(from: at(7), minutes: 10, stepsPerMinute: 110),
            intervals: [session(at(7), minutes: 30, credit: 0.5)],
            calendar: calendar
        )
        #expect(active.activeMinutes == 10 + 20 * 0.5)
        #expect(active.walkingMinutes == 0)
    }

    @Test func overlappingIntervalsCountOnce() {
        // A Watch workout recorded during a barbellmonk session.
        let active = ActiveDay(
            day: day,
            steps: [],
            intervals: [session(at(7), minutes: 60), session(at(7, 30), minutes: 60)],
            calendar: calendar
        )
        #expect(active.activeMinutes == 90)
    }

    @Test func stepsInTheSameMinuteAreAddedTogether() {
        // Two partial samples in one minute: 60 + 50 steps is brisk.
        let active = ActiveDay(
            day: day,
            steps: [(at(12, 0, second: 5), 60), (at(12, 0, second: 40), 50)],
            intervals: [],
            calendar: calendar
        )
        #expect(active.walkingMinutes == 1)
    }

    @Test func partialMinutesAtSessionEdgesCountProportionally() {
        // 07:00:30 to 07:10:30 is exactly ten minutes spread over eleven.
        let start = at(7, 0, second: 30)
        let active = ActiveDay(day: day, steps: [], intervals: [session(start, minutes: 10)], calendar: calendar)
        #expect(abs(active.activeMinutes - 10) < 1e-9)
    }

    @Test func onlyTheGivenDayCounts() {
        // A session from 23:30 to 00:30 counts 30 minutes on each day.
        let lateSession = session(at(23, 30), minutes: 60)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let today = ActiveDay(day: day, steps: [], intervals: [lateSession], calendar: calendar)
        let tomorrow = ActiveDay(day: next, steps: [], intervals: [lateSession], calendar: calendar)
        #expect(today.activeMinutes == 30)
        #expect(tomorrow.activeMinutes == 30)
    }

    @Test func handlesShortDaylightSavingDay() {
        // 2026-03-08 has 23 hours; walking at 23:50 must still land in range.
        let shortDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let active = ActiveDay(
            day: shortDay,
            steps: walk(from: at(23, 50, on: shortDay), minutes: 10, stepsPerMinute: 110),
            intervals: [],
            calendar: calendar
        )
        #expect(active.walkingMinutes == 10)
    }
}
