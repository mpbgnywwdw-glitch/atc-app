import Foundation

/// Remembers your best average score for each scenario (stored in UserDefaults).
@MainActor
final class ProgressStore: ObservableObject {
    private static let key = "bestScores"
    @Published private(set) var best: [String: Int]

    init() {
        best = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
    }

    func record(_ score: Int, for scenarioID: String) {
        guard score > (best[scenarioID] ?? -1) else { return }
        best[scenarioID] = score
        UserDefaults.standard.set(best, forKey: Self.key)
    }

    func reset() {
        best = [:]
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
