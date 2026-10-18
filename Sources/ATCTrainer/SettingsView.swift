import AVFoundation
import RTCore
import SwiftUI

/// Standard macOS Settings window with toolbar tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            VoiceSettings()
                .tabItem { Label("ATC Voice", systemImage: "speaker.wave.2") }
            RecognitionSettings()
                .tabItem { Label("Recognition", systemImage: "mic") }
            ScenarioSettings()
                .tabItem { Label("Scenarios", systemImage: "square.stack") }
        }
        .frame(width: 540, height: 420)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.registration) private var registration = ""
    @AppStorage(Prefs.aircraftType) private var aircraftType = ""
    @AppStorage(Prefs.showATCText) private var showATCText = true

    var body: some View {
        Form {
            Section {
                TextField("Registration", text: $registration, prompt: Text("Random"))
                Picker("Aircraft type", selection: $aircraftType) {
                    Text("Random").tag("")
                    Divider()
                    ForEach(AircraftType.all) { type in
                        Text(type.code).tag(type.code)
                    }
                }
            } header: {
                Text("Your Aircraft")
            } footer: {
                if !registration.isEmpty && FlightContext.normaliseRegistration(registration) == nil {
                    Text("Enter a UK registration like G-ABCD. A random one is used until then.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Leave blank to fly a different registration each time.")
                }
            }

            Section {
                Toggle("Show ATC transmissions as text", isOn: $showATCText)
            } header: {
                Text("Practice")
            } footer: {
                Text("Turn off to practise listening. Hidden transmissions can still be revealed with a click.")
            }

            Section {
                Text(Disclaimer.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }
}

private struct VoiceSettings: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.voiceRate) private var voiceRate = 0.5
    @AppStorage(Prefs.voiceID) private var voiceID = ""
    @AppStorage(Prefs.radioEffect) private var radioEffect = true
    private let voices = ATCVoice.britishVoices

    var body: some View {
        Form {
            Section {
                Picker("Voice", selection: $voiceID) {
                    Text("Automatic").tag("")
                    Divider()
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name)\(voice.quality == .enhanced || voice.quality == .premium ? " (Enhanced)" : "")")
                            .tag(voice.identifier)
                    }
                }
                LabeledContent("Speed") {
                    Slider(value: $voiceRate, in: 0.35...0.62) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
                Toggle("VHF radio effect", isOn: $radioEffect)
                LabeledContent("Preview") {
                    Button("Play Sample") {
                        Task { await model.voice.speak("Golf Alpha Bravo Charlie Delta, Bramley Tower, readability five.") }
                    }
                }
            } footer: {
                Text("For a more natural controller, download an Enhanced or Premium British voice in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct RecognitionSettings: View {
    @AppStorage(Prefs.onDeviceRecognition) private var onDevice = true

    var body: some View {
        Form {
            Section {
                Toggle("Aviation-tuned recognition on this Mac", isOn: $onDevice)
            } footer: {
                Text("Uses on-device English (UK) recognition with a language model trained on RT phraseology. Turn off to use Apple's server recognition instead, which may cope better with a strong accent.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScenarioSettings: View {
    @EnvironmentObject private var store: ScenarioStore
    @EnvironmentObject private var progress: ProgressStore
    @AppStorage(Prefs.packURL) private var packURL = ""
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Included") { Text("\(ScenarioLibrary.all.count + store.bundled.count) scenarios") }
                LabeledContent("Downloaded") { Text("\(store.downloaded.count) scenarios") }
                Button("Check for New Scenarios") { Task { await store.checkForUpdates() } }
                    .disabled(store.isChecking)
                TextField("Pack address", text: $packURL, prompt: Text("Default"))
            } header: {
                Text("Scenario Packs")
            } footer: {
                Text("Every scenario is included and works offline. New scenarios are added free of charge when you check for updates. Leave the address blank to use the default.")
            }

            Section {
                LabeledContent("Completed") { Text("\(progress.best.count) scenarios") }
                Button("Reset Best Scores…", role: .destructive) { confirmReset = true }
                    .disabled(progress.best.isEmpty)
            } header: {
                Text("Progress")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all best scores?", isPresented: $confirmReset) {
            Button("Reset Best Scores", role: .destructive) { progress.reset() }
        } message: {
            Text("This can't be undone.")
        }
    }
}
