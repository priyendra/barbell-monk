import Engine
import Foundation
import Observation

@MainActor @Observable
final class TodayModel {
    enum State {
        case loading
        case needsAuthorization
        case ready(WeightTrend)
        case failed(String)
    }

    private(set) var state: State = .loading
    private let source: any WeightSource
    private let calendar: Calendar

    init(source: any WeightSource, calendar: Calendar = .current) {
        self.source = source
        self.calendar = calendar
    }

    func load() async {
        do {
            if try await source.needsAuthorization() {
                state = .needsAuthorization
                return
            }
            let start = calendar.date(byAdding: .year, value: -1, to: .now)!
            let readings = try await source.weightReadings(since: start)
            state = .ready(WeightTrend(readings: readings, calendar: calendar))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func connect() async {
        do {
            try await source.requestAuthorization()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        await load()
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Writes `SampleData` into Apple Health, for trying the real read path.
    /// Simulator only: the simulator's Health is separate from the phone's,
    /// so this can never write sample data into real health records.
    func addSampleDataToHealth() async {
        guard let health = source as? HealthStore else { return }
        do {
            try await health.save(weights: SampleData.weights())
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        await load()
    }
    #endif
}
