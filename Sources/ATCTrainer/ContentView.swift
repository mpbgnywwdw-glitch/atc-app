import RTCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ScenarioStore
    @EnvironmentObject private var progress: ProgressStore
    @State private var selection: String?
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onChange(of: selection) { _, newValue in
            if model.session?.scenario.id != newValue { model.endSession() }
        }
        .task {
            // Test hooks used by CI's UI smoke test: RT_SELECT / RT_AUTOSTART=<scenario id>.
            if let id = ProcessInfo.processInfo.environment["RT_SELECT"] { selection = id }
            if let id = ProcessInfo.processInfo.environment["RT_AUTOSTART"],
               let scenario = store.scenario(id: id) {
                selection = id
                model.start(scenario)
            }
        }
        .alert("Permissions needed", isPresented: Binding(get: { model.permissionError != nil },
                                                          set: { if !$0 { model.permissionError = nil } })) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.permissionError ?? "")
        }
        .alert("Scenario packs", isPresented: Binding(get: { store.statusMessage != nil },
                                                      set: { if !$0 { store.statusMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.statusMessage ?? "")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(ScenarioCategory.allCases, id: \.self) { category in
                let items = filtered(ScenarioLibrary.all.filter { $0.category == category })
                if !items.isEmpty {
                    Section(category.rawValue) {
                        ForEach(items) { ScenarioRow(scenario: $0, best: progress.best[$0.id]).tag(Optional($0.id)) }
                    }
                }
            }
            let downloaded = filtered(store.downloaded)
            if !downloaded.isEmpty {
                Section("Downloaded") {
                    ForEach(downloaded) { ScenarioRow(scenario: $0, best: progress.best[$0.id]).tag(Optional($0.id)) }
                }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search scenarios")
        .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.checkForUpdates() }
                } label: {
                    if store.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check for New Scenarios", systemImage: "arrow.down.circle")
                    }
                }
                .help("Check for new scenarios")
                .disabled(store.isChecking)
            }
        }
    }

    private func filtered(_ scenarios: [Scenario]) -> [Scenario] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return scenarios }
        return scenarios.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let session = model.session, session.scenario.id == selection {
            SessionView(session: session)
                .id(ObjectIdentifier(session))
        } else if let id = selection, let scenario = store.scenario(id: id) {
            ScenarioIntroView(scenario: scenario, best: progress.best[scenario.id])
                .id(scenario.id)
        } else {
            ContentUnavailableView {
                Label("Choose a Scenario", systemImage: "headphones")
            } description: {
                Text("Pick a flight from the sidebar. ATC speaks to you; hold the space bar to transmit, and each call is checked against CAP 413 phraseology.")
            }
            .navigationTitle("Scenarios")
        }
    }
}

extension ScenarioCategory {
    var symbol: String {
        switch self {
        case .controlled: return "building.columns"
        case .uncontrolled: return "antenna.radiowaves.left.and.right"
        case .enRoute: return "airplane"
        case .emergency: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .controlled: return .blue
        case .uncontrolled: return .teal
        case .enRoute: return .indigo
        case .emergency: return .red
        }
    }
}

/// Sidebar row: symbol, title, and your best score once you've completed the scenario.
struct ScenarioRow: View {
    let scenario: Scenario
    let best: Int?

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(scenario.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let best {
                    Text("\(best)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("Your best score")
                }
            }
        } icon: {
            Image(systemName: scenario.category.symbol)
        }
    }
}

/// Overview shown before a scenario starts.
struct ScenarioIntroView: View {
    @EnvironmentObject private var model: AppModel
    let scenario: Scenario
    let best: Int?
    @State private var preview: Script

    init(scenario: Scenario, best: Int?) {
        self.scenario = scenario
        self.best = best
        _preview = State(initialValue: scenario.make(FlightContext.random()))
    }

    private var calls: [String] {
        preview.steps.compactMap(\.task).map { task in
            // First sentence only: enough to show what each call is about.
            task.split(separator: ".", maxSplits: 1).first.map { String($0) + "." } ?? task
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calls in this scenario")
                        .font(.headline)
                    ForEach(Array(calls.enumerated()), id: \.offset) { index, call in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)
                            Text(call)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("How it works")
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        tip("speaker.wave.2.fill", "ATC calls are spoken aloud. Replay one with ⌘R, or transmit “Say again”.")
                        tip("mic.fill", "Hold the space bar while you speak, and let go when you've finished.")
                        tip("checklist", "Each call is checked for required items, readback rules, callsign placement and non-standard words.")
                        tip("dice.fill", "Callsign, runway, QNH and squawk change every time. Set your own registration in Settings.")
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(scenario.title)
        .navigationSubtitle(scenario.category.rawValue)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.start(scenario)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Start this scenario")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(scenario.category.tint.gradient)
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: scenario.category.symbol)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(scenario.title)
                    .font(.largeTitle.weight(.bold))
                Text(scenario.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Chip(text: scenario.category.rawValue, symbol: scenario.category.symbol)
                    Chip(text: "\(preview.pilotStepCount) calls", symbol: "bubble.left.and.bubble.right")
                    if let best { Chip(text: "Best \(best)%", symbol: "star.fill") }
                }
                Button {
                    model.start(scenario)
                } label: {
                    Text("Start Scenario")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        GridRow {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// Small capsule label used for metadata.
struct Chip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}
