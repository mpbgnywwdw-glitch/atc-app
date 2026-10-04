import AppKit
import OSLog
import RTCore
import SwiftUI

let appLog = Logger(subsystem: "uk.rttrainer.ATCTrainer", category: "app")

enum Prefs {
    static let voiceRate = "atcVoiceRate"
    static let voiceID = "atcVoiceID"
    static let radioEffect = "radioEffect"
    static let showATCText = "showATCText"
    static let onDeviceRecognition = "onDeviceRecognition"
    static let registration = "registration"
    static let aircraftType = "aircraftType"

    static func register() {
        UserDefaults.standard.register(defaults: [
            voiceRate: 0.5,
            voiceID: "",
            radioEffect: true,
            showATCText: true,
            onDeviceRecognition: true,
            registration: "",
            aircraftType: "",
        ])
    }
}

@MainActor
final class AppModel: ObservableObject {
    let voice = ATCVoice()
    let recognizer = RadioRecognizer()
    @Published var session: TrainingSession?
    @Published var permissionError: String?

    func requestPermissions() async {
        permissionError = await RadioRecognizer.requestPermissions()
    }

    func start(_ scenario: Scenario) {
        session?.end()
        let defaults = UserDefaults.standard
        let typeCode = defaults.string(forKey: Prefs.aircraftType) ?? ""
        let context = FlightContext.random(
            registration: defaults.string(forKey: Prefs.registration),
            aircraft: typeCode.isEmpty ? nil : AircraftType.named(typeCode))
        appLog.notice("Starting scenario \(scenario.id, privacy: .public) as \(context.registration, privacy: .public)")
        let session = TrainingSession(scenario: scenario, context: context, voice: voice, recognizer: recognizer)
        self.session = session
        session.start()
    }

    func endSession() {
        session?.end()
        session = nil
    }
}

@main
struct ATCTrainerApp: App {
    @StateObject private var model = AppModel()

    init() {
        Prefs.register()
        // Lets `swift run` show a normal windowed app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("RT Trainer") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if ProcessInfo.processInfo.environment["RT_SKIP_PERMISSIONS"] == nil {
                        await model.requestPermissions()
                    }
                }
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
