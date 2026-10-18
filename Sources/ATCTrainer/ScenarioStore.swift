import Foundation
import RTCore

/// Scenarios beyond the built-in library: the packs bundled inside the app, plus any newer packs downloaded
/// from the repository. Downloads are stored as validated `ScenarioDefinition` JSON files in Application Support.
@MainActor
final class ScenarioStore: ObservableObject {
    static let defaultPackURL = "https://raw.githubusercontent.com/mpbgnywwdw-glitch/atc-app/main/scenario-packs/index.json"

    /// Scenario packs shipped inside the app, so every scenario works offline.
    let bundled: [Scenario]
    /// Downloaded scenarios that aren't already bundled.
    @Published private(set) var downloaded: [Scenario] = []
    @Published private(set) var isChecking = false
    @Published var statusMessage: String?

    private var byID: [String: Scenario] = [:]

    init() {
        bundled = Self.loadBundled()
        load()
    }

    func scenario(id: String) -> Scenario? { ScenarioLibrary.scenario(id: id) ?? byID[id] }

    /// Built-in and bundled scenarios in one category, in library order.
    func scenarios(in category: ScenarioCategory) -> [Scenario] {
        (ScenarioLibrary.all + bundled).filter { $0.category == category }
    }

    /// The `scenario-packs` folder in the app bundle, or in the working directory under `swift run`.
    private static var bundledDirectory: URL? {
        if let url = Bundle.main.url(forResource: "scenario-packs", withExtension: nil) { return url }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scenario-packs")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    private static func loadBundled() -> [Scenario] {
        guard let dir = bundledDirectory,
              let data = try? Data(contentsOf: dir.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode(ScenarioPackIndex.self, from: data) else { return [] }
        return index.scenarios.compactMap { file in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let definition = try? ScenarioDefinition.decode(data),
                  ScenarioLibrary.scenario(id: definition.id) == nil else { return nil }
            return definition.makeScenario()
        }
    }

    // MARK: Storage

    private static func directory(_ name: String) -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("RT Trainer/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var downloadedDirectory: URL? { directory("Downloaded Scenarios") }

    private static func loadDefinitions(in dir: URL?) -> [(ScenarioDefinition, Date)] {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let d = try? ScenarioDefinition.decode(data) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (d, date)
        }
    }

    func load() {
        let bundledIDs = Set(bundled.map(\.id))
        downloaded = Self.loadDefinitions(in: Self.downloadedDirectory)
            .filter { !bundledIDs.contains($0.0.id) }
            .sorted { $0.0.title < $1.0.title }.map { $0.0.makeScenario() }
        byID = Dictionary((bundled + downloaded).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Scenario packs

    /// Downloads the scenario pack index and every scenario it lists, keeping only scenarios that validate.
    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let configured = UserDefaults.standard.string(forKey: Prefs.packURL) ?? ""
        guard let indexURL = URL(string: configured.isEmpty ? Self.defaultPackURL : configured) else {
            statusMessage = "The scenario pack address in Settings isn't a valid URL."
            return
        }
        do {
            let index = try JSONDecoder().decode(ScenarioPackIndex.self, from: try await fetch(indexURL))
            let base = indexURL.deletingLastPathComponent()
            var accepted: [(String, Data)] = []
            var rejected: [String] = []
            for file in index.scenarios {
                guard file.hasSuffix(".json"), !file.contains("/"), !file.contains("..") else { continue }
                let data = try await fetch(base.appendingPathComponent(file))
                guard let definition = try? ScenarioDefinition.decode(data),
                      ScenarioLibrary.scenario(id: definition.id) == nil else {
                    rejected.append(file)
                    continue
                }
                let problems = await Task.detached(priority: .userInitiated) { definition.validate(runs: 10) }.value
                if problems.isEmpty { accepted.append((file, data)) } else { rejected.append(file) }
            }

            guard let dir = Self.downloadedDirectory else { return }
            let previous = Set(downloaded.map(\.id))
            for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: old)
            }
            for (file, data) in accepted { try data.write(to: dir.appendingPathComponent(file), options: .atomic) }
            load()

            let newCount = downloaded.filter { !previous.contains($0.id) }.count
            var message = newCount > 0
                ? "\(newCount) new scenario\(newCount == 1 ? "" : "s") added."
                : "You have every scenario. No new ones yet."
            if !rejected.isEmpty { message += " Skipped \(rejected.count) that failed checks." }
            statusMessage = message
        } catch {
            statusMessage = "Couldn't check for new scenarios: \(error.localizedDescription)"
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.fileDoesNotExist, userInfo: [NSLocalizedDescriptionKey:
                http.statusCode == 404 ? "No scenario pack was found at \(url.absoluteString)." : "The server returned HTTP \(http.statusCode)."])
        }
        return data
    }
}
