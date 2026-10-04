import Foundation

public struct AircraftType: Hashable, Identifiable, Sendable {
    public var id: String { code }
    /// ICAO-style designator as written, e.g. "PA28".
    public let code: String
    /// How a pilot would normally say it on the radio.
    public let spoken: String
    /// Canonical-form patterns that count as the pilot stating the type.
    public let patterns: [String]

    public static let all: [AircraftType] = [
        AircraftType(code: "PA28", spoken: "PA twenty eight", patterns: ["pa 28", "p a 28", "piper", "cherokee", "warrior", "archer"]),
        AircraftType(code: "C152", spoken: "Cessna one five two", patterns: ["cessna", "152"]),
        AircraftType(code: "C172", spoken: "Cessna one seven two", patterns: ["cessna", "172", "skyhawk"]),
        AircraftType(code: "DA40", spoken: "Diamond DA forty", patterns: ["diamond", "da 40", "d a 40"]),
        AircraftType(code: "DR400", spoken: "Robin DR four hundred", patterns: ["robin", "dr 400", "d r 400"]),
        AircraftType(code: "AT3", spoken: "Aero AT3", patterns: ["aero", "at 3", "a t 3"]),
    ]

    public static func named(_ code: String) -> AircraftType {
        all.first { $0.code == code } ?? all[0]
    }
}

/// The randomised details of one practice flight.
public struct FlightContext: Sendable {
    /// UK registration, e.g. "G-ABCD".
    public var registration: String
    public var aircraft: AircraftType
    public var qnh: Int
    /// Aerodrome elevation expressed in hPa (QFE = QNH − this).
    public var qfeOffset: Int
    public var runway: String
    /// "left" or "right" hand circuit.
    public var circuit: String
    public var squawk: String
    public var atis: Character
    public var windDirection: Int
    public var windSpeed: Int
    public var regionName: String
    public var regionalPressure: Int
    public var personsOnBoard: Int

    public init(registration: String, aircraft: AircraftType, qnh: Int, qfeOffset: Int, runway: String,
                circuit: String, squawk: String, atis: Character, windDirection: Int, windSpeed: Int,
                regionName: String, regionalPressure: Int, personsOnBoard: Int) {
        self.registration = registration
        self.aircraft = aircraft
        self.qnh = qnh
        self.qfeOffset = qfeOffset
        self.runway = runway
        self.circuit = circuit
        self.squawk = squawk
        self.atis = atis
        self.windDirection = windDirection
        self.windSpeed = windSpeed
        self.regionName = regionName
        self.regionalPressure = regionalPressure
        self.personsOnBoard = personsOnBoard
    }

    // MARK: Callsigns

    public var registrationLetters: [Character] { Array(registration.dropFirst(2)) }

    /// "Golf Alpha Bravo Charlie Delta"
    public var callsign: String { "Golf " + registrationLetters.map { Phonetic.letters[$0] ?? String($0) }.joined(separator: " ") }

    /// "Golf Charlie Delta" (first character and last two, CAP 413).
    public var abbreviatedCallsign: String {
        "Golf " + registrationLetters.suffix(2).map { Phonetic.letters[$0] ?? String($0) }.joined(separator: " ")
    }

    /// Abbreviated written form, e.g. "G-CD".
    public var abbreviatedRegistration: String { "G-" + String(registrationLetters.suffix(2)) }

    /// Canonical-form regex for the full callsign ("g a b c d").
    public var callsignPattern: String { "g " + registrationLetters.map { String($0).lowercased() }.joined(separator: " ") }

    /// Canonical-form regex for the abbreviated callsign ("g c d").
    public var abbreviatedCallsignPattern: String {
        "g " + registrationLetters.suffix(2).map { String($0).lowercased() }.joined(separator: " ")
    }

    public var qfe: Int { qnh - qfeOffset }

    // MARK: Randomisation

    static let registrationAlphabet = Array("ABCDEFGHIJKLMNOPRSTUVWXYZ")
    static let runways = ["26", "08", "24", "06", "22", "04", "34", "16", "27", "09", "21", "03", "31", "13"]
    static let regions = ["Chatham", "Portland", "Cotswold", "Yarmouth", "Barnsley", "Wessex", "Humber", "Scillies"]

    /// Normalises a user-entered UK registration ("gabcd", "G-ABCD", "g abcd") to "G-ABCD".
    public static func normaliseRegistration(_ input: String) -> String? {
        let letters = input.uppercased().filter(\.isLetter)
        guard letters.count == 5, letters.first == "G", letters.allSatisfy(\.isASCII) else { return nil }
        let tail = letters.dropFirst()
        // Avoid registrations whose abbreviation is ambiguous with the full form (e.g. G-CDCD).
        guard tail.prefix(2) != tail.suffix(2) else { return nil }
        return "G-" + String(tail)
    }

    public static func random<G: RandomNumberGenerator>(using g: inout G,
                                                        registration: String? = nil,
                                                        aircraft: AircraftType? = nil) -> FlightContext {
        var reg = registration.flatMap(normaliseRegistration)
        while reg == nil {
            let letters = String((0..<4).map { _ in registrationAlphabet.randomElement(using: &g)! })
            reg = normaliseRegistration("G" + letters)
        }
        let runway = runways.randomElement(using: &g)!
        let heading = Int(runway)! * 10
        var windDirection = (heading + Int.random(in: -3...3, using: &g) * 10 + 360) % 360
        if windDirection == 0 { windDirection = 360 }
        let qnh = Int.random(in: 996...1031, using: &g)
        var squawk = String(Int.random(in: 1...6, using: &g))
        for _ in 0..<3 { squawk += String(Int.random(in: 0...7, using: &g)) }
        if squawk.hasSuffix("000") { squawk = String(squawk.dropLast()) + "1" }
        let atisLetters = Array("ABCDEFGHIJKLMNOPRSTUVWXYZ")

        return FlightContext(
            registration: reg!,
            aircraft: aircraft ?? AircraftType.all.randomElement(using: &g)!,
            qnh: qnh,
            qfeOffset: Int.random(in: 2...9, using: &g),
            runway: runway,
            circuit: Bool.random(using: &g) ? "left" : "right",
            squawk: squawk,
            atis: atisLetters.randomElement(using: &g)!,
            windDirection: windDirection,
            windSpeed: Int.random(in: 4...16, using: &g),
            regionName: regions.randomElement(using: &g)!,
            regionalPressure: qnh - Int.random(in: 1...4, using: &g),
            personsOnBoard: Int.random(in: 1...3, using: &g)
        )
    }

    public static func random(registration: String? = nil, aircraft: AircraftType? = nil) -> FlightContext {
        var g = SystemRandomNumberGenerator()
        return random(using: &g, registration: registration, aircraft: aircraft)
    }
}

/// Deterministic generator for tests and reproducible flights.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
