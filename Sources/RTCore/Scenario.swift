import Foundation

/// Something the analyser expects to find in the pilot's transmission.
public struct Element: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case content
        /// The aircraft callsign. Matched against the flight context, including abbreviation rules.
        case callsign
        /// The name of the ground station being called ("Bramley Tower").
        case station
    }

    public var id: String { label }
    public let label: String
    /// Regexes matched (with word boundaries) against `Normalizer.canonical` output.
    public let patterns: [String]
    public let required: Bool
    public let kind: Kind
    /// For numeric items: the canonical digit string, used to detect numbers run together.
    public let numericValue: String?

    public init(label: String, patterns: [String], required: Bool = true, kind: Kind = .content, numericValue: String? = nil) {
        self.label = label
        self.patterns = patterns
        self.required = required
        self.kind = kind
        self.numericValue = numericValue
    }

    public static func phrase(_ label: String, _ patterns: String..., required: Bool = true) -> Element {
        Element(label: label, patterns: patterns, required: required)
    }

    /// A number that must be present, written however the pilot likes ("1013", "one zero one three").
    public static func number(_ label: String, _ value: Int, required: Bool = true) -> Element {
        number(label, String(value), required: required)
    }

    public static func number(_ label: String, _ value: String, required: Bool = true) -> Element {
        let canonical = Normalizer.canonical(value)
        return Element(label: label, patterns: [NSRegularExpression.escapedPattern(for: canonical)],
                       required: required, numericValue: canonical)
    }

    /// Runway designator; leading zero optional ("08" or "8").
    public static func runway(_ runway: String, required: Bool = true) -> Element {
        let digits = runway.filter(\.isNumber)
        let pattern = digits.hasPrefix("0") ? "0?" + String(digits.dropFirst()) : digits
        return Element(label: "Runway " + Phonetic.runway(runway), patterns: [pattern], required: required, numericValue: digits)
    }

    public static func callsign(required: Bool = true) -> Element {
        Element(label: "Callsign", patterns: [], required: required, kind: .callsign)
    }

    public static func station(_ name: String) -> Element {
        let canonical = Normalizer.canonical(name)
        var patterns = [NSRegularExpression.escapedPattern(for: canonical)]
        if let suffix = canonical.split(separator: " ").last, canonical.contains(" ") {
            // Be forgiving if the recogniser mangles the place name but gets "Tower"/"Information" etc.
            patterns.append("[a-z]+ " + String(suffix))
        }
        return Element(label: "Station called (\(name))", patterns: patterns, kind: .station)
    }

    public static func pressure(_ label: String, _ value: Int, required: Bool = true) -> Element {
        number(label + " " + Phonetic.digits(value), value, required: required)
    }

    public static func altitude(_ feet: Int, required: Bool = true) -> Element {
        number("Altitude " + Phonetic.altitude(feet) + " feet", feet, required: required)
    }

    public static func squawk(_ code: String, required: Bool = true) -> Element {
        number("Squawk " + Phonetic.squawk(code), code, required: required)
    }

    public static func type(_ aircraft: AircraftType, required: Bool = true) -> Element {
        Element(label: "Aircraft type (\(aircraft.code))", patterns: aircraft.patterns, required: required)
    }
}

/// A phrase that should *not* appear in a particular transmission.
public struct Caution: Hashable, Sendable {
    public let pattern: String
    public let severity: Finding.Severity
    public let title: String
    public let detail: String

    public init(_ pattern: String, severity: Finding.Severity = .minor, title: String, detail: String) {
        self.pattern = pattern
        self.severity = severity
        self.title = title
        self.detail = detail
    }

    public static let takeoffWord = Caution(
        "takeoff", title: "Don't say \"take-off\" here",
        detail: "Use \"ready for departure\". The words \"take-off\" are only used when a take-off clearance is given, cancelled or read back.")

    public static let noClearances = Caution(
        "cleared", title: "No clearance is given at this aerodrome",
        detail: "AFIS and Air/Ground stations don't issue clearances in the air, so don't read one back or ask for one.")
}

public enum CallsignPosition: Sendable {
    /// Initial calls and reports: "[Station], G-ABCD, ..."
    case start
    /// Readbacks: "..., G-ABCD"
    case end
    case any
}

public struct Step: Identifiable, Sendable {
    public let id = UUID()
    /// The ATC station transmitting `atc` (shown in the transcript).
    public var station: String
    /// What ATC says before the pilot's turn. `nil` when the pilot calls first.
    public var atc: String?
    /// Instruction shown to the student. `nil` means an ATC-only step that needs no reply.
    public var task: String?
    public var elements: [Element]
    public var model: String?
    public var callsignPosition: CallsignPosition
    public var isReadback: Bool
    public var cautions: [Caution]

    public init(station: String, atc: String?, task: String?, elements: [Element] = [], model: String? = nil,
                callsignPosition: CallsignPosition = .any, isReadback: Bool = false, cautions: [Caution] = []) {
        self.station = station
        self.atc = atc
        self.task = task
        self.elements = elements
        self.model = model
        self.callsignPosition = callsignPosition
        self.isReadback = isReadback
        self.cautions = cautions
    }

    /// ATC transmits; no reply expected.
    public static func atcOnly(_ station: String, _ text: String) -> Step {
        Step(station: station, atc: text, task: nil)
    }

    /// A pilot-initiated call or report (callsign near the start).
    public static func call(_ station: String, atc: String? = nil, task: String, elements: [Element], model: String,
                            callsignPosition: CallsignPosition = .start, cautions: [Caution] = []) -> Step {
        Step(station: station, atc: atc, task: task, elements: [.callsign()] + elements, model: model,
             callsignPosition: callsignPosition, cautions: cautions)
    }

    /// A readback of an ATC instruction (callsign at the end).
    public static func readback(_ station: String, atc: String, task: String = "Read back the instruction.",
                                elements: [Element], model: String, cautions: [Caution] = []) -> Step {
        Step(station: station, atc: atc, task: task, elements: elements + [.callsign()], model: model,
             callsignPosition: .end, isReadback: true, cautions: cautions)
    }
}

public struct BriefingItem: Hashable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

public struct Script: Sendable {
    public var briefing: [BriefingItem]
    public var steps: [Step]
    /// Extra words to bias the speech recogniser towards (station names etc).
    public var vocabulary: [String]

    public init(briefing: [BriefingItem], steps: [Step], vocabulary: [String] = []) {
        self.briefing = briefing
        self.steps = steps
        self.vocabulary = vocabulary
    }

    /// CAP 413: a pilot may abbreviate their callsign only after ATC has done so.
    public func abbreviationAllowed(at index: Int, context: FlightContext) -> Bool {
        steps.prefix(index + 1).contains { $0.atc?.contains(context.abbreviatedCallsign) == true }
    }

    public var pilotStepCount: Int { steps.filter { $0.task != nil }.count }
}

public enum ScenarioCategory: String, CaseIterable, Sendable {
    case controlled = "Controlled aerodrome"
    case uncontrolled = "AFIS & Air/Ground"
    case enRoute = "En route services"
    case emergency = "Emergencies"
}

public struct Scenario: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let category: ScenarioCategory
    public let make: @Sendable (FlightContext) -> Script

    public init(id: String, title: String, summary: String, category: ScenarioCategory,
                make: @escaping @Sendable (FlightContext) -> Script) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.make = make
    }
}
