import RTCore
import SwiftUI

/// Sheet for asking Claude to write a new scenario.
struct GenerateScenarioView: View {
    @EnvironmentObject private var store: ScenarioStore
    @Environment(\.dismiss) private var dismiss
    /// Called with the new scenario's id once it has been saved.
    let onCreated: (String) -> Void

    @State private var request = ""
    @State private var category: ScenarioCategory?
    @State private var apiKey = Keychain.read(ScenarioGenerator.keychainAccount) ?? ""
    @State private var status: String?
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var isWorking: Bool { task != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("New scenario from Claude", systemImage: "sparkles")
                .font(.title2.weight(.semibold))
            Text("Describe the flight you want to practise, or leave it blank and Claude will choose. Every scenario is checked by the app before it's added.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("e.g. \"Rejoin at an AFIS aerodrome with other traffic in the circuit\"", text: $request, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)

            Picker("Category", selection: $category) {
                Text("Any").tag(ScenarioCategory?.none)
                ForEach(ScenarioCategory.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(ScenarioCategory?.some(c))
                }
            }
            .disabled(isWorking)

            if Keychain.read(ScenarioGenerator.keychainAccount) == nil {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Get a key at console.anthropic.com. Each scenario is a paid API request on your account. The key is stored in your Mac's Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let status, isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status).foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(isWorking ? "Stop" : "Cancel") {
                    if let task { task.cancel(); self.task = nil } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func generate() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(key, account: ScenarioGenerator.keychainAccount)
        error = nil
        status = "Contacting Claude…"
        let generator = ScenarioGenerator(apiKey: key)
        let request = self.request
        let category = self.category
        let titles = store.allTitles
        task = Task {
            do {
                let definition = try await generator.generate(request: request, category: category, existingTitles: titles) { message in
                    status = message
                }
                try Task.checkCancellation()
                try store.addGenerated(definition)
                task = nil
                onCreated(definition.id)
                dismiss()
            } catch is CancellationError {
                task = nil
            } catch {
                self.error = error.localizedDescription
                task = nil
            }
        }
    }
}
