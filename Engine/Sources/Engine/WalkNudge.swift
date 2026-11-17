import Foundation

/// The late-day reminder to close the activity gap with a walk.
public enum WalkNudge {
    /// 6 pm.
    public static let hour = 18

    /// When to nudge today: at `hour` if there's still walking to do and
    /// that time hasn't passed. Nil means no nudge today.
    public static func fireDate(
        minutesToWalk: Int, now: Date, calendar: Calendar, hour: Int = hour
    ) -> Date? {
        guard minutesToWalk > 0,
              let nudge = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now),
              nudge > now
        else { return nil }
        return nudge
    }
}
