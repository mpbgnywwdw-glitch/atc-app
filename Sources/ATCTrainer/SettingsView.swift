import AVFoundation
import RTCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.voiceRate) private var voiceRate = 0.5
    @AppStorage(Prefs.voiceID) private var voiceID = ""
    @AppStorage(Prefs.radioEffect) private var radioEffect = true
    @AppStorage(Prefs.showATCText) private var showATCText = true
    @AppStorage(Prefs.onDeviceRecognition) private var onDevice = true
    @AppStorage(Prefs.registration) private var registration = ""
    @AppStorage(Prefs.aircraftType) private var aircraftType = ""
    @AppStorage(Prefs.packURL) private var packURL = ""
    @State private var apiKey = Keychain.read(ScenarioGenerator.keychainAccount) ?? ""

    private let voices = ATCVoice.britishVoices

    var body: some View {
        Form {
            Section("ATC voice") {
                Picker("Voice", selection: $voiceID) {
                    Text("Automatic (best British voice)").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name)\(voice.quality == .enhanced || voice.quality == .premium ? " (enhanced)" : "")")
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
                Toggle("Show ATC transmissions as text", isOn: $showATCText)
                Button("Test voice") {
                    Task { await model.voice.speak("Golf Alpha Bravo Charlie Delta, Bramley Tower, readability five.") }
                }
                Text("For a more natural controller, download an enhanced or premium British voice in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Your aircraft") {
                TextField("Registration", text: $registration, prompt: Text("Random (e.g. G-ABCD)"))
                if !registration.isEmpty && FlightContext.normaliseRegistration(registration) == nil {
                    Text("Enter a UK registration like G-ABCD. A random one will be used until then.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker("Aircraft type", selection: $aircraftType) {
                    Text("Random").tag("")
                    ForEach(AircraftType.all) { type in
                        Text(type.code).tag(type.code)
                    }
                }
            }

            Section("New scenarios") {
                SecureField("Anthropic API key", text: $apiKey)
                    .onSubmit { Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: ScenarioGenerator.keychainAccount) }
                HStack {
                    Button("Save key") {
                        Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: ScenarioGenerator.keychainAccount)
                    }
                    Button("Remove key", role: .destructive) {
                        apiKey = ""
                        Keychain.delete(ScenarioGenerator.keychainAccount)
                    }
                    Spacer()
                    Link("Get a key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                Text("Used by \"New scenario with Claude\". Each scenario is one or two paid requests to Claude on your Anthropic account. The key is stored in your Mac's Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Scenario pack address", text: $packURL, prompt: Text("Default (RT Trainer on GitHub)"))
                Text("Where \"Check for new scenarios\" downloads from. Leave blank for the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speech recognition") {
                Toggle("Aviation-tuned recognition on this Mac (recommended)", isOn: $onDevice)
                Text("Uses on-device English (UK) recognition with a language model trained on RT phraseology (macOS 14 or later). Turn off to use Apple's server recognition instead, which may do better with a strong accent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .padding(.vertical, 8)
    }
}
