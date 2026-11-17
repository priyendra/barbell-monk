import SwiftUI

@main
struct BarbellMonkApp: App {
    @State private var today = TodayModel(source: Self.makeWeightSource())

    var body: some Scene {
        WindowGroup {
            TodayView(model: today)
        }
    }

    private static func makeWeightSource() -> any WeightSource {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleData") {
            return SampleWeightSource()
        }
        #endif
        return HealthStore()
    }
}
