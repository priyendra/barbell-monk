import Foundation
import Testing
@testable import Engine

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: hour, minute: minute))!
}

@Suite struct WalkNudgeTests {
    @Test func nudgesAtSixWhenShort() {
        #expect(WalkNudge.fireDate(minutesToWalk: 20, now: at(14, 30), calendar: calendar) == at(18))
    }

    @Test func noNudgeWhenTargetsAreMet() {
        #expect(WalkNudge.fireDate(minutesToWalk: 0, now: at(14, 30), calendar: calendar) == nil)
    }

    @Test func noNudgeOnceSixHasPassed() {
        #expect(WalkNudge.fireDate(minutesToWalk: 20, now: at(18), calendar: calendar) == nil)
        #expect(WalkNudge.fireDate(minutesToWalk: 20, now: at(21, 15), calendar: calendar) == nil)
    }

    @Test func nudgeHourCanBeChanged() {
        #expect(WalkNudge.fireDate(minutesToWalk: 5, now: at(9), calendar: calendar, hour: 17) == at(17))
    }
}
