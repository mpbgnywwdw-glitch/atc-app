import RTCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ScenarioStore
    @State private var selection: String?
    @State private var showingGenerator = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ScenarioCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(ScenarioLibrary.all.filter { $0.category == category }) { scenario in
                            Label(scenario.title, systemImage: category.symbol)
                                .tag(Optional(scenario.id))
                        }
                    }
                }
                if !store.downloaded.isEmpty {
                    Section("Downloaded") {
                        ForEach(store.downloaded) { scenario in
                            Label(scenario.title, systemImage: scenario.category.symbol)
                                .tag(Optional(scenario.id))
                        }
                    }
                }
                if !store.generated.isEmpty {
                    Section("Written by Claude") {
                        ForEach(store.generated) { scenario in
                            Label(scenario.title, systemImage: "sparkles")
                                .tag(Optional(scenario.id))
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        if selection == scenario.id { selection = nil }
                                        store.deleteGenerated(id: scenario.id)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
            .safeAreaInset(edge: .bottom) { sidebarActions }
        } detail: {
            detail
        }
        .onChange(of: selection) { _ in
            if model.session?.scenario.id != selection { model.endSession() }
        }
        .task {
            // Test hook used by CI's UI smoke test: RT_AUTOSTART=<scenario id>.
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
    }

    private var sidebarActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { store.statusMessage = nil }
            }
            Button {
                showingGenerator = true
            } label: {
                Label("New scenario with Claude…", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                Task { await store.checkForUpdates() }
            } label: {
                if store.isChecking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Check for new scenarios", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(store.isChecking)
        }
        .padding(12)
        .background(.bar)
        .sheet(isPresented: $showingGenerator) {
            GenerateScenarioView { id in selection = id }
                .environmentObject(store)
        }
    }

    @ViewBuilder private var detail: some View {
        if let session = model.session, session.scenario.id == selection {
            SessionView(session: session)
                .id(ObjectIdentifier(session))
        } else if let id = selection, let scenario = store.scenario(id: id) {
            ScenarioIntroView(scenario: scenario)
        } else {
            WelcomeView()
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
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("UK PPL Radiotelephony Trainer")
                .font(.largeTitle.weight(.semibold))
            Text("Choose a scenario from the sidebar. ATC speaks to you; hold the space bar to transmit, and your call is checked against CAP 413 phraseology.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
        }
        .padding(40)
    }
}

struct ScenarioIntroView: View {
    @EnvironmentObject private var model: AppModel
    let scenario: Scenario

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(scenario.category.rawValue, systemImage: scenario.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(scenario.title)
                    .font(.largeTitle.weight(.semibold))
                Text(scenario.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                GroupBox("How it works") {
                    VStack(alignment: .leading, spacing: 8) {
                        tip("speaker.wave.2", "ATC calls are spoken aloud. Use Replay if you missed one, or transmit \"Say again\".")
                        tip("keyboard", "Hold the space bar (or the on-screen button) while you speak, and release when you've finished.")
                        tip("checklist", "Each call is checked for the required items, readback rules, callsign placement and non-standard words.")
                        tip("dice", "Callsign, runway, QNH and squawk are randomised every time. Set your own registration in Settings.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                Button {
                    model.start(scenario)
                } label: {
                    Label("Start scenario", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
    }
}
