import SwiftUI

@main
struct BarbellMonkApp: App {
    @State private var today = Self.makeTodayModel()

    var body: some Scene {
        WindowGroup {
            TodayView(model: today)
        }
    }

    private static func makeTodayModel() -> TodayModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleData") {
            // Fresh targets each run, kept apart from the real ones.
            let suite = "sampleData"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return TodayModel(source: SampleHealthSource(), targetStore: TargetStore(defaults: defaults))
        }
        #endif
        return TodayModel(source: HealthStore(), targetStore: TargetStore())
    }
}
