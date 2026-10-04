import Foundation
import RTCore
import Speech

/// An on-device custom language model trained on UK RT phraseology (macOS 14+).
///
/// Training phrases are generated from every scenario's example calls across many random flights, plus
/// phonetic letters and digit sequences, so the recogniser expects "Golf Alpha Bravo…", "QNH one zero one
/// three", "wilco" and so on rather than everyday dictation.
@available(macOS 14, *)
@MainActor
final class RTLanguageModel {
    static let shared = RTLanguageModel()

    /// Bump when the phrase generation changes, to rebuild the cached model.
    private static let version = "3"
    private static let clientIdentifier = "uk.rttrainer.ATCTrainer"

    private(set) var configuration: SFSpeechLanguageModel.Configuration?
    private var preparing = false

    /// Builds (or loads the cached) model in the background. Safe to call repeatedly.
    func prepare() {
        guard configuration == nil, !preparing else { return }
        guard SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))?.supportsOnDeviceRecognition == true else { return }
        preparing = true
        Task.detached(priority: .utility) {
            let result = await Self.build()
            await MainActor.run {
                self.configuration = result
                self.preparing = false
            }
        }
    }

    private nonisolated static func build() async -> SFSpeechLanguageModel.Configuration? {
        do {
            let fm = FileManager.default
            let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("RT Trainer/LanguageModel-v\(version)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let asset = dir.appendingPathComponent("rt.bin")
            let configuration = SFSpeechLanguageModel.Configuration(languageModel: dir.appendingPathComponent("rt-model"))

            if !fm.fileExists(atPath: asset.path) {
                let data = SFCustomLanguageModelData(locale: Locale(identifier: "en-GB"),
                                                     identifier: clientIdentifier, version: version)
                for (phrase, count) in trainingPhrases() {
                    data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count))
                }
                try await data.export(to: asset)
            }
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, clientIdentifier: clientIdentifier,
                                                                        configuration: configuration)
            appLog.notice("RT language model ready")
            return configuration
        } catch {
            appLog.error("RT language model unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Example pilot calls and readbacks from all scenarios, plus RT building blocks.
    nonisolated static func trainingPhrases() -> [(String, Int)] {
        var counts: [String: Int] = [:]
        func add(_ s: String, _ n: Int = 1) {
            let phrase = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !phrase.isEmpty else { return }
            counts[phrase, default: 0] += n
        }

        var g = SplitMix64(seed: 413)
        for scenario in ScenarioLibrary.all {
            for _ in 0..<25 {
                let ctx = FlightContext.random(using: &g)
                for step in scenario.make(ctx).steps {
                    if let model = step.model { add(model, 4) }
                    if let atc = step.atc { add(atc, 1) }
                }
                add(ctx.callsign, 3)
                add(ctx.abbreviatedCallsign, 3)
            }
        }

        let letters = Phonetic.letters.values.sorted()
        for l in letters { add(l, 5) }
        for _ in 0..<300 {
            let reg = (0..<4).map { _ in letters.randomElement(using: &g)! }.joined(separator: " ")
            add("Golf " + reg, 2)
        }
        for qnh in 980...1040 { add("QNH " + Phonetic.digits(qnh), 2); add("QFE " + Phonetic.digits(qnh - 10)) }
        for rw in 1...36 { add("runway " + Phonetic.spell(String(format: "%02d", rw)), 2) }
        for alt in stride(from: 1000, through: 6000, by: 500) { add(Phonetic.altitude(alt) + " feet", 2) }
        for _ in 0..<200 {
            let code = (0..<4).map { _ in String(Int.random(in: 0...7, using: &g)) }.joined()
            add("squawk " + Phonetic.squawk(code), 2)
        }
        for phrase in ["Roger", "Wilco", "Affirm", "Negative", "Say again", "Standby", "ready for departure",
                       "cleared for take-off", "cleared to land", "line up and wait", "request taxi", "request join",
                       "downwind", "final", "overhead", "descending deadside", "Basic Service", "Traffic Service",
                       "request MATZ penetration", "Mayday Mayday Mayday", "Pan Pan Pan Pan Pan Pan", "radio check",
                       "readability five", "traffic in sight", "looking", "vacated", "freecall", "holding point"] {
            add(phrase, 6)
        }
        return counts.map { ($0.key, $0.value) }
    }
}
