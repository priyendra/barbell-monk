import Engine
import Foundation
import Observation

@MainActor @Observable
final class TodayModel {
    struct Activity {
        var today: ActiveDay
        var stepsToday: Int
        var targets: ActivityTargets
    }

    enum State {
        case loading
        case needsAuthorization
        case ready(weight: WeightTrend, activity: Activity)
        case failed(String)
    }

    private(set) var state: State = .loading
    private let source: any HealthSource
    private let targetStore: TargetStore
    private let calendar: Calendar

    init(source: any HealthSource, targetStore: TargetStore, calendar: Calendar = .current) {
        self.source = source
        self.targetStore = targetStore
        self.calendar = calendar
    }

    func load() async {
        do {
            if try await source.needsAuthorization() {
                state = .needsAuthorization
                return
            }
            let now = Date.now
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            let weight = WeightTrend(readings: try await source.weightReadings(since: yearAgo), calendar: calendar)
            state = .ready(weight: weight, activity: try await loadActivity(now: now))
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

    /// Today's active time plus the last 30 days, which set and raise the targets.
    private func loadActivity(now: Date) async throws -> Activity {
        let todayStart = calendar.startOfDay(for: now)
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: todayStart)!
        let data = try await source.activity(from: monthAgo, to: now)
        let days = (0...30).map { offset in
            ActiveDay(
                day: calendar.date(byAdding: .day, value: offset, to: monthAgo)!,
                steps: data.steps, intervals: data.intervals, calendar: calendar
            )
        }
        let history = Array(days.dropLast())
        let targets = targetStore.load()?.updated(history: history, today: now, calendar: calendar)
            ?? ActivityTargets.initial(history: history, today: now, calendar: calendar)
        targetStore.save(targets)

        let stepsToday = data.steps.filter { $0.minute >= todayStart }.reduce(0) { $0 + $1.count }
        return Activity(today: days[days.count - 1], stepsToday: Int(stepsToday), targets: targets)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Writes `SampleData` into Apple Health for whatever is missing, for
    /// trying the real read path. Simulator only: the simulator's Health is
    /// separate from the phone's, so this never touches real records.
    func addSampleDataToHealth() async {
        guard let health = source as? HealthStore else { return }
        do {
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: .now)!
            if try await health.weightReadings(since: yearAgo).isEmpty {
                try await health.save(weights: SampleData.weights())
            }
            let monthAgo = calendar.date(byAdding: .day, value: -31, to: .now)!
            if try await health.activity(from: monthAgo, to: .now).steps.isEmpty {
                try await health.save(SampleData.activity())
            }
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        await load()
    }
    #endif
}
