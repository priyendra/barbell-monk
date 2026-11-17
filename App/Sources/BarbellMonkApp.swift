import SwiftUI
import UIKit
import UserNotifications

@main
struct BarbellMonkApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            TodayView(model: appDelegate.today)
        }
    }
}

/// Owns the app's models, so they exist when iOS launches the app in the
/// background for new Health data, before any screen appears.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let today: TodayModel
    private let health: HealthStore?

    override init() {
        (today, health) = Self.makeModels()
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // New activity refreshes today's numbers and the 6 pm nudge.
        let today = today
        health?.observeActivity { await today.load() }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    private static func makeModels() -> (TodayModel, HealthStore?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleData") {
            // Fresh targets each run, kept apart from the real ones; no notifications.
            let suite = "sampleData"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let model = TodayModel(
                source: SampleHealthSource(), targetStore: TargetStore(defaults: defaults), nudges: nil
            )
            return (model, nil)
        }
        #endif
        let health = HealthStore()
        let model = TodayModel(source: health, targetStore: TargetStore(), nudges: WalkNudgeScheduler())
        return (model, health)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show the walk nudge even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
