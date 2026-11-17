import Engine
import Foundation
import UserNotifications

/// Keeps today's 6 pm walk reminder in line with the latest activity:
/// scheduled with the minutes still needed, or removed once both targets
/// are met.
struct WalkNudgeScheduler: Sendable {
    private static let identifier = "walk-nudge"
    private var center: UNUserNotificationCenter { .current() }

    /// Asks for notification permission the first time; later calls do nothing.
    func requestAuthorization() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func update(minutesToWalk: Int, now: Date, calendar: Calendar) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard let fireDate = WalkNudge.fireDate(minutesToWalk: minutesToWalk, now: now, calendar: calendar) else {
            return
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        try? await center.add(UNNotificationRequest(
            identifier: Self.identifier, content: Self.content(minutesToWalk: minutesToWalk), trigger: trigger
        ))
    }

    private static func content(minutesToWalk: Int) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time for a walk"
        content.body = "About \(minutesToWalk) minutes of brisk walking closes today's targets."
        content.sound = .default
        return content
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Shows the nudge in 5 seconds instead of waiting until 6 pm.
    func preview(minutesToWalk: Int) async {
        try? await center.add(UNNotificationRequest(
            identifier: "walk-nudge-preview",
            content: Self.content(minutesToWalk: minutesToWalk),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        ))
    }
    #endif
}
