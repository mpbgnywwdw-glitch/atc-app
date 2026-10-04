import Foundation

public struct Finding: Hashable, Identifiable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case info, minor, major
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

        var penalty: Double {
            switch self {
            case .info: return 0
            case .minor: return 7
            case .major: return 20
            }
        }
    }

    public var id: String { title }
    public let severity: Severity
    public let title: String
    public let detail: String

    public init(_ severity: Severity, _ title: String, _ detail: String) {
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

public struct ElementResult: Hashable, Identifiable, Sendable {
    public var id: String { element.id }
    public let element: Element
    public let matched: Bool
}

public struct Analysis: Sendable {
    public enum Grade: String, Sendable {
        case good = "Good"
        case satisfactory = "Satisfactory"
        case needsWork = "Needs work"
    }

    public let transcript: String
    public let canonical: String
    public let elements: [ElementResult]
    public let findings: [Finding]
    public let score: Int
    public let wordsPerMinute: Double?

    public var grade: Grade {
        switch score {
        case 85...: return .good
        case 60..<85: return .satisfactory
        default: return .needsWork
        }
    }

    public var missingRequired: [Element] { elements.filter { !$0.matched && $0.element.required }.map(\.element) }
}

public enum Analyzer {
    /// "Say again" on its own (optionally with a callsign) asks ATC to repeat rather than being a reply.
    public static func isSayAgainRequest(_ transcript: String) -> Bool {
        let canon = Normalizer.canonical(transcript)
        return canon.contains("say again") && canon.split(separator: " ").count <= 8
    }

    public static func analyze(transcript: String, step: Step, context: FlightContext,
                               abbreviationAllowed: Bool, speechDuration: TimeInterval? = nil) -> Analysis {
        let canon = Normalizer.canonical(transcript)
        let tokens = canon.split(separator: " ").map(String.init)

        guard !tokens.isEmpty else {
            return Analysis(transcript: transcript, canonical: canon,
                            elements: step.elements.map { ElementResult(element: $0, matched: false) },
                            findings: [Finding(.major, "Nothing heard",
                                               "No speech was recognised. Hold the transmit key for the whole call and speak clearly into the microphone.")],
                            score: 0, wordsPerMinute: nil)
        }

        var results: [ElementResult] = []
        var findings: [Finding] = []
        var contentLocations: [Int] = []
        var callsignFirst: Int?
        var callsignLast: Int?
        var stationFirst: Int?

        for element in step.elements {
            switch element.kind {
            case .callsign:
                let full = matches(context.callsignPattern, in: canon)
                let abbreviated = matches(context.abbreviatedCallsignPattern, in: canon)
                let all = (full + abbreviated).sorted()
                results.append(ElementResult(element: element, matched: !all.isEmpty))
                callsignFirst = all.first
                callsignLast = all.last
                if full.isEmpty && !abbreviated.isEmpty && !abbreviationAllowed {
                    findings.append(Finding(.minor, "Callsign abbreviated too early",
                                            "You may only abbreviate to \(context.abbreviatedCallsign) after ATC has abbreviated it first. Use the full callsign, \(context.callsign)."))
                }
                if all.isEmpty, tokens.contains("g") || canon.contains(context.abbreviatedCallsignPattern.dropFirst(2)) {
                    findings.append(Finding(.info, "Callsign not recognised",
                                            "Your callsign is \(context.callsign) (\(context.registration)). Say every letter using the phonetic alphabet."))
                }
            case .station, .content:
                var locations = element.patterns.flatMap { matches($0, in: canon) }
                if locations.isEmpty, let value = element.numericValue, let merged = mergedNumberLocation(value, tokens: tokens, canonical: canon) {
                    locations = [merged]
                    findings.append(Finding(.info, "Numbers run together",
                                            "\"\(element.label)\" was heard joined to another number. Say the designator (QNH, runway, squawk…) before each value so they can't be confused."))
                }
                results.append(ElementResult(element: element, matched: !locations.isEmpty))
                if let first = locations.min() {
                    if element.kind == .station { stationFirst = first } else { contentLocations.append(first) }
                }
            }
        }

        // Callsign placement.
        switch step.callsignPosition {
        case .end:
            if let last = callsignLast, let latest = contentLocations.max(), last < latest {
                findings.append(Finding(.minor, "Callsign goes at the end of a readback",
                                        "Read back the items first, then finish with your callsign, e.g. \"…, \(abbreviationAllowed ? context.abbreviatedCallsign : context.callsign)\"."))
            }
        case .start:
            if let first = callsignFirst, let earliest = contentLocations.min(), first > earliest {
                findings.append(Finding(.minor, "Start with your callsign",
                                        "For a call or report, identify yourself first: \"[station], callsign, message\"."))
            }
            if let first = callsignFirst, let station = stationFirst, station > first {
                findings.append(Finding(.minor, "Station name comes first",
                                        "On initial contact, call the station before giving your callsign: \"\(step.station), \(context.callsign)…\"."))
            }
        case .any:
            break
        }

        // "Roger" used in place of a readback.
        let missingRequiredContent = results.contains { !$0.matched && $0.element.required && $0.element.kind == .content }
        if step.isReadback && missingRequiredContent && tokens.contains("roger") {
            findings.append(Finding(.major, "\"Roger\" is not a readback",
                                    "Clearances, runway, pressure settings, squawks, frequencies and level instructions must be read back. \"Roger\" only means \"I have received all of your last transmission\"."))
        }

        for caution in step.cautions where !matches(caution.pattern, in: canon).isEmpty {
            findings.append(Finding(caution.severity, caution.title, caution.detail))
        }

        for rule in phraseologyRules where !matches(rule.pattern, in: canon).isEmpty {
            findings.append(rule.finding)
        }

        // Rate of speech.
        var wpm: Double?
        if let duration = speechDuration, duration > 1.0 {
            let spokenWords = tokens.reduce(0) { count, t in
                Normalizer.isNumeral(t) ? count + t.filter { $0 != "." }.count : count + 1
            }
            if spokenWords >= 4 {
                let rate = Double(spokenWords) / duration * 60
                wpm = rate
                if rate > 170 {
                    findings.append(Finding(.minor, "Speaking too fast",
                                            "About \(Int(rate)) words per minute. Aim for an even pace of roughly 100–120 wpm so the controller doesn't need to ask you to say again."))
                }
            }
        }

        // Score.
        var total = 0.0, achieved = 0.0
        for r in results {
            let weight = r.element.required ? 1.0 : 0.5
            total += weight
            if r.matched { achieved += weight }
        }
        let content = total > 0 ? achieved / total * 100 : 100
        let penalty = findings.reduce(0) { $0 + $1.severity.penalty }
        let score = Int(max(0, min(100, (content - penalty).rounded())))

        let uniqueFindings = findings.reduce(into: [Finding]()) { acc, f in
            if !acc.contains(where: { $0.title == f.title }) { acc.append(f) }
        }.sorted { $0.severity > $1.severity }

        return Analysis(transcript: transcript, canonical: canon, elements: results,
                        findings: uniqueFindings, score: score, wordsPerMinute: wpm)
    }

    // MARK: - Helpers

    /// Start offsets of every match of `pattern` (with word boundaries) in `text`.
    static func matches(_ pattern: String, in text: String) -> [Int] {
        guard let re = try? NSRegularExpression(pattern: "(?<![a-z0-9.])(?:" + pattern + ")(?![a-z0-9])") else { return [] }
        return re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range.location)
    }

    /// Finds `value` inside a longer all-digit token, e.g. QNH "1013" inside "261013" when the pilot said
    /// "runway two six one zero one three".
    static func mergedNumberLocation(_ value: String, tokens: [String], canonical: String) -> Int? {
        guard value.count >= 2 else { return nil }
        var offset = 0
        for t in tokens {
            if t.count >= value.count + 2, t.allSatisfy(\.isNumber), t.hasPrefix(value) || t.hasSuffix(value) {
                return offset
            }
            offset += (t as NSString).length + 1
        }
        return nil
    }

    struct Rule {
        let pattern: String
        let finding: Finding
    }

    static let phraseologyRules: [Rule] = [
        Rule(pattern: "repeat", finding: Finding(.minor, "Use \"Say again\", not \"Repeat\"",
             "\"Say again\" asks for a repetition. \"Repeat\" is not used for this in civil RT.")),
        Rule(pattern: "over and out", finding: Finding(.minor, "\"Over and out\" is not used",
             "\"Over\" invites a reply and \"out\" ends the exchange, so together they contradict each other. Normally neither is needed on VHF.")),
        Rule(pattern: "over(?! and out)", finding: Finding(.info, "\"Over\" is rarely needed",
             "On VHF, \"over\" is normally left out; the end of your transmission is obvious.")),
        Rule(pattern: "copy|copied|copy that", finding: Finding(.minor, "\"Copy\" is not standard phraseology",
             "Use \"Roger\" to acknowledge information, \"Wilco\" for an instruction, or read back the items that need it.")),
        Rule(pattern: "affirmative", finding: Finding(.minor, "Say \"Affirm\"",
             "UK phraseology uses \"Affirm\" for yes, not \"affirmative\".")),
        Rule(pattern: "yes|yeah|yep|yup", finding: Finding(.minor, "Say \"Affirm\" instead of \"yes\"",
             "Use \"Affirm\" for yes and \"Negative\" for no.")),
        Rule(pattern: "^(?:no|nope)", finding: Finding(.minor, "Say \"Negative\" instead of \"no\"",
             "Use \"Negative\" for no.")),
        Rule(pattern: "okay|alright|all right", finding: Finding(.minor, "Avoid \"okay\"",
             "\"Okay\" isn't standard phraseology. Use \"Roger\", \"Wilco\" or a readback.")),
        Rule(pattern: "roger wilco", finding: Finding(.info, "\"Roger wilco\" is redundant",
             "\"Wilco\" already means you've understood and will comply, so leave out \"roger\".")),
        Rule(pattern: "um+|uh+|uhm|erm?|ah+|hmm+", finding: Finding(.info, "Hesitation",
             "Work out what you'll say before you press the button: think, press, talk.")),
        Rule(pattern: "ten four|10 4|104", finding: Finding(.minor, "\"Ten-four\" is not RT phraseology",
             "Use \"Roger\" or \"Wilco\".")),
    ]
}
