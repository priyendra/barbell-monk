import Engine
import Foundation

/// Keeps the activity targets between launches.
struct TargetStore {
    private let defaults: UserDefaults
    private static let key = "activityTargets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ActivityTargets? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ActivityTargets.self, from: $0) }
    }

    func save(_ targets: ActivityTargets) {
        defaults.set(try? JSONEncoder().encode(targets), forKey: Self.key)
    }
}
