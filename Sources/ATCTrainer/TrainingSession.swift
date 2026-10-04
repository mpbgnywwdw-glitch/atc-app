import Foundation
import RTCore

/// Runs one scenario: plays ATC calls, records the pilot's replies and keeps the analysis for each step.
@MainActor
final class TrainingSession: ObservableObject {
    enum Phase: Equatable {
        case ready, atcSpeaking, awaitingPilot, recording, analysing, reviewing, finished
    }

    enum Speaker: Equatable {
        case atc(String)
        case pilot
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let stepIndex: Int
        let speaker: Speaker
        let text: String
        var analysis: Analysis?
    }

    let scenario: Scenario
    let context: FlightContext
    let script: Script

    @Published private(set) var index = 0
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var lastAnalysis: Analysis?
    @Published private(set) var results: [Int: Analysis] = [:]
    @Published var errorMessage: String?

    private let voice: ATCVoice
    private let recognizer: RadioRecognizer
    var recognizerForUI: RadioRecognizer { recognizer }

    init(scenario: Scenario, context: FlightContext, voice: ATCVoice, recognizer: RadioRecognizer) {
        self.scenario = scenario
        self.context = context
        self.script = scenario.make(context)
        self.voice = voice
        self.recognizer = recognizer
    }

    var currentStep: Step? { script.steps.indices.contains(index) ? script.steps[index] : nil }

    /// 1-based number of the current pilot transmission, for "Call 3 of 8".
    var pilotStepNumber: Int { script.steps.prefix(index + 1).filter { $0.task != nil }.count }

    var averageScore: Int? {
        guard !results.isEmpty else { return nil }
        return results.values.map(\.score).reduce(0, +) / results.count
    }

    var vocabulary: [String] {
        var words = [context.callsign, context.abbreviatedCallsign, context.aircraft.spoken]
        words += script.vocabulary
        words += Phonetic.letters.values.sorted()
        words += ["QNH", "QFE", "Roger", "Wilco", "Affirm", "Negative", "Say again", "squawk", "holding point",
                  "readability", "downwind", "final", "deadside", "overhead", "cleared for take-off", "cleared to land",
                  "line up and wait", "ready for departure", "request", "niner", "decimal", "thousand", "hundred", "feet",
                  "Basic Service", "Traffic Service", "freecall", "vacate", "taxi", "Mayday", "Pan Pan"]
        return words
    }

    // MARK: - Flow

    func start() {
        index = 0
        log = []
        results = [:]
        Task { await enterStep() }
    }

    func end() {
        voice.stop()
        recognizer.cancel()
    }

    private func enterStep() async {
        guard let step = currentStep else {
            phase = .finished
            return
        }
        lastAnalysis = nil
        if let atc = step.atc {
            log.append(LogEntry(stepIndex: index, speaker: .atc(step.station), text: atc))
            phase = .atcSpeaking
            await voice.speak(atc)
            guard currentStep?.id == step.id, phase == .atcSpeaking else { return }
        }
        if step.task == nil {
            index += 1
            await enterStep()
        } else {
            phase = .awaitingPilot
        }
    }

    /// Transmit key pressed.
    func pttDown() {
        guard phase == .awaitingPilot || phase == .reviewing else { return }
        lastAnalysis = nil
        do {
            try recognizer.start(contextualStrings: vocabulary)
            phase = .recording
        } catch {
            errorMessage = error.localizedDescription
            phase = .awaitingPilot
        }
    }

    /// Transmit key released.
    func pttUp() {
        guard phase == .recording else { return }
        phase = .analysing
        Task {
            let heard = await recognizer.stop()
            guard let step = currentStep, phase == .analysing else { return }

            if Analyzer.isSayAgainRequest(heard.text), let atc = step.atc {
                log.append(LogEntry(stepIndex: index, speaker: .pilot, text: heard.text))
                log.append(LogEntry(stepIndex: index, speaker: .atc(step.station), text: atc))
                phase = .atcSpeaking
                await voice.speak(atc)
                if phase == .atcSpeaking { phase = .awaitingPilot }
                return
            }

            let analysis = Analyzer.analyze(transcript: heard.text, step: step, context: context,
                                            abbreviationAllowed: script.abbreviationAllowed(at: index, context: context),
                                            speechDuration: heard.speechDuration)
            let text = heard.text.trimmingCharacters(in: .whitespaces)
            log.append(LogEntry(stepIndex: index, speaker: .pilot, text: text.isEmpty ? "(nothing heard)" : text, analysis: analysis))
            results[index] = analysis
            lastAnalysis = analysis
            phase = .reviewing
        }
    }

    /// Move on after reviewing feedback.
    func next() {
        guard phase == .reviewing else { return }
        advance()
    }

    func skip() {
        guard phase != .finished else { return }
        voice.stop()
        recognizer.cancel()
        advance()
    }

    private func advance() {
        index += 1
        Task { await enterStep() }
    }

    func replayATC() {
        guard let atc = currentStep?.atc, let station = currentStep?.station,
              phase == .awaitingPilot || phase == .reviewing else { return }
        let resume = phase
        log.append(LogEntry(stepIndex: index, speaker: .atc(station), text: atc))
        phase = .atcSpeaking
        Task {
            await voice.speak(atc)
            if phase == .atcSpeaking { phase = resume }
        }
    }

    /// Whether an ATC transmission's text should be hidden (listening practice).
    func isHidden(_ entry: LogEntry, showText: Bool) -> Bool {
        guard !showText, case .atc(_) = entry.speaker else { return false }
        return entry.stepIndex == index && [.atcSpeaking, .awaitingPilot, .recording, .analysing].contains(phase)
    }
}
