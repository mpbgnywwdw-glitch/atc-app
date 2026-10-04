import Foundation

/// Practice scenarios. Aerodromes and radar units (Bramley, Ashwell, Hadley, Westbury, Northfield) are
/// fictional so their frequencies and procedures can't be mistaken for real ones; London Information and
/// London Centre (121.500) behave as their UK counterparts.
public enum ScenarioLibrary {
    public static let all: [Scenario] = [
        controlledDeparture, controlledRejoin, afisDeparture, airGroundArrival,
        basicService, trafficService, matzCrossing, mayday, panPan,
    ]

    public static func scenario(id: String) -> Scenario? { all.first { $0.id == id } }

    // MARK: - Frequencies

    static let bramleyTower = ("Bramley Tower", "118.330")
    static let ashwellInfo = ("Ashwell Information", "123.505")
    static let hadleyRadio = ("Hadley Radio", "129.830")
    static let londonInfo = ("London Information", "124.750")
    static let westburyRadar = ("Westbury Radar", "127.880")
    static let northfieldZone = ("Northfield Zone", "123.300")
    static let londonCentre = ("London Centre", "121.500")

    static let baseVocabulary = [
        "Bramley", "Ashwell", "Hadley", "Westbury", "Northfield", "Tower", "Information", "Radio", "Radar", "Zone",
    ]

    // MARK: - Shared wording

    /// Spoken-form shortcuts for a flight context.
    struct Words {
        let c: FlightContext
        var cs: String { c.callsign }
        var ab: String { c.abbreviatedCallsign }
        var rw: String { Phonetic.runway(c.runway) }
        var qnh: String { Phonetic.digits(c.qnh) }
        var qfe: String { Phonetic.digits(c.qfe) }
        var rps: String { Phonetic.digits(c.regionalPressure) }
        var type: String { c.aircraft.spoken }
        var atis: String { Phonetic.letters[c.atis] ?? String(c.atis) }
        var atisPattern: String {
            let l = String(c.atis).lowercased()
            return "information \(l)|info \(l)"
        }
        var wind: String { Phonetic.wind(direction: c.windDirection, speed: c.windSpeed) }
        var sq: String { Phonetic.squawk(c.squawk) }
        var pob: String { Phonetic.digitWords[c.personsOnBoard] }
        func freq(_ f: String) -> String { Phonetic.frequency(f) }

        var callsignItem: BriefingItem { BriefingItem("Callsign", "\(c.registration) — \(c.callsign)") }
        var aircraftItem: BriefingItem { BriefingItem("Aircraft", c.aircraft.code) }
        var windText: String { String(format: "%03d° / %d kt", c.windDirection, c.windSpeed) }
    }

    static let alreadyCleared = Caution(
        "takeoff", title: "You haven't been cleared for take-off",
        detail: "This was a line-up instruction only. Don't use the word \"take-off\" until you are cleared.")

    // MARK: - Controlled aerodrome

    static let controlledDeparture = Scenario(
        id: "controlled-departure",
        title: "Departure from a controlled aerodrome",
        summary: "Radio check, taxi with ATIS, line up, take-off clearance and leaving the zone with Bramley Tower.",
        category: .controlled
    ) { c in
        let w = Words(c: c)
        let tower = bramleyTower.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Bramley Tower", bramleyTower.1),
                BriefingItem("ATIS", "Information \(w.atis) · runway \(c.runway) · QNH \(c.qnh) · wind \(w.windText)"),
                BriefingItem("Position", "Flying club apron, \(c.personsOnBoard) POB, local VFR flight to the north"),
                BriefingItem("Next frequency", "London Information \(londonInfo.1)"),
            ],
            steps: [
                .call(tower,
                      task: "You're parked at the flying club with the engine running. Make a radio check with Bramley Tower on \(bramleyTower.1).",
                      elements: [.station(tower), .phrase("Radio check", "radio check"),
                                 .number("Frequency \(bramleyTower.1)", bramleyTower.1, required: false)],
                      model: "Bramley Tower, \(w.cs), radio check \(w.freq(bramleyTower.1))."),
                .call(tower, atc: "\(w.cs), Bramley Tower, readability five.",
                      task: "Request taxi for a local VFR flight. You're at the flying club and have information \(w.atis).",
                      elements: [.type(c.aircraft, required: false),
                                 .phrase("Position (flying club)", "flying club|club|apron|parking|hangars?|stand", required: false),
                                 .phrase("ATIS information \(w.atis)", w.atisPattern),
                                 .phrase("Request taxi", "taxi"),
                                 .phrase("Intentions (local VFR)", "local|vfr", required: false)],
                      model: "Bramley Tower, \(w.cs), \(w.type), at the flying club, information \(w.atis), request taxi for a local VFR flight."),
                .readback(tower, atc: "\(w.ab), taxi to holding point Alpha One, runway \(w.rw), QNH \(w.qnh).",
                          elements: [.phrase("Holding point Alpha One", "a 1"), .runway(c.runway), .pressure("QNH", c.qnh)],
                          model: "Taxi holding point Alpha One, runway \(w.rw), QNH \(w.qnh), \(w.ab)."),
                .call(tower,
                      task: "Power checks are complete at holding point Alpha One. Tell Tower you're ready.",
                      elements: [.phrase("Ready for departure", "ready")],
                      model: "\(w.ab), ready for departure.",
                      cautions: [.takeoffWord]),
                .readback(tower, atc: "\(w.ab), line up and wait, runway \(w.rw).",
                          elements: [.phrase("Line up and wait", "line up and wait|line up wait|lining up and waiting"), .runway(c.runway)],
                          model: "Line up and wait, runway \(w.rw), \(w.ab).",
                          cautions: [alreadyCleared]),
                .readback(tower, atc: "\(w.ab), surface wind \(w.wind), runway \(w.rw), cleared for take-off.",
                          task: "Read back the take-off clearance.",
                          elements: [.phrase("Cleared for take-off", "cleared for takeoff|cleared takeoff|clear for takeoff"), .runway(c.runway)],
                          model: "Runway \(w.rw), cleared for take-off, \(w.ab)."),
                .readback(tower, atc: "\(w.ab), report leaving the zone.",
                          task: "Acknowledge the instruction.",
                          elements: [.phrase("Wilco", "wilco")],
                          model: "Wilco, \(w.ab)."),
                .call(tower,
                      task: "You're leaving the zone to the north at 2,000 feet. Report this and tell Tower you're changing to London Information on \(londonInfo.1).",
                      elements: [.phrase("Leaving the zone", "leaving"), .altitude(2000, required: false),
                                 .phrase("Next unit / frequency", "london information|124.75|changing|freecall", required: false)],
                      model: "\(w.ab), leaving the zone to the north, two thousand feet, changing to London Information \(w.freq(londonInfo.1))."),
                .atcOnly(tower, "\(w.ab), frequency change approved."),
            ],
            vocabulary: baseVocabulary
        )
    }

    static let controlledRejoin = Scenario(
        id: "controlled-rejoin",
        title: "Rejoin and circuit to land",
        summary: "Join, downwind and final calls, sequencing and landing clearance with Bramley Tower.",
        category: .controlled
    ) { c in
        let w = Words(c: c)
        let tower = bramleyTower.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Bramley Tower", bramleyTower.1),
                BriefingItem("ATIS", "Information \(w.atis) · runway \(c.runway) · QNH \(c.qnh) · wind \(w.windText)"),
                BriefingItem("Position", "10 nm north of Bramley, 2,000 ft on QNH \(c.qnh), returning to land"),
            ],
            steps: [
                .call(tower,
                      task: "You're 10 miles north of Bramley at 2,000 feet, returning to land, with information \(w.atis). Make initial contact with Bramley Tower on \(bramleyTower.1).",
                      elements: [.station(tower), .phrase("Request join", "join|rejoin|inbound", required: false)],
                      model: "Bramley Tower, \(w.cs), request join."),
                .call(tower, atc: "\(w.cs), Bramley Tower, pass your message.",
                      task: "Pass your message: aircraft type, position, altitude and pressure setting, ATIS letter and your request.",
                      elements: [.type(c.aircraft, required: false),
                                 .phrase("Position (10 miles north)", "10 miles|north"),
                                 .altitude(2000), .pressure("QNH", c.qnh, required: false),
                                 .phrase("ATIS information \(w.atis)", w.atisPattern),
                                 .phrase("Request join", "join|rejoin")],
                      model: "\(w.cs), \(w.type), one zero miles north of Bramley, two thousand feet, QNH \(w.qnh), information \(w.atis), request join."),
                .readback(tower, atc: "\(w.ab), join \(c.circuit) hand downwind, runway \(w.rw), QNH \(w.qnh).",
                          elements: [.phrase("Join downwind", "downwind"),
                                     .phrase("\(c.circuit.capitalized) hand circuit", "\(c.circuit) hand|\(c.circuit)"),
                                     .runway(c.runway), .pressure("QNH", c.qnh)],
                          model: "Join \(c.circuit) hand downwind, runway \(w.rw), QNH \(w.qnh), \(w.ab)."),
                .call(tower,
                      task: "You're established on the downwind leg and intend to land. Make your downwind call.",
                      elements: [.phrase("Downwind", "downwind"), .phrase("Intentions (to land)", "land|full stop", required: false)],
                      model: "\(w.ab), downwind to land."),
                .readback(tower, atc: "\(w.ab), number two, follow the Cessna on base.",
                          task: "Acknowledge. You can see the Cessna.",
                          elements: [.phrase("Number two", "number 2"),
                                     .phrase("Traffic in sight", "in sight|visual|traffic sighted|have the traffic|got the traffic")],
                          model: "Number two, traffic in sight, \(w.ab)."),
                .call(tower,
                      task: "You're turning onto final approach. Make your final call.",
                      elements: [.phrase("Final", "final")],
                      model: "\(w.ab), final."),
                .readback(tower, atc: "\(w.ab), runway \(w.rw), cleared to land, surface wind \(w.wind).",
                          task: "Read back the landing clearance.",
                          elements: [.phrase("Cleared to land", "cleared to land|clear to land"), .runway(c.runway)],
                          model: "Cleared to land, runway \(w.rw), \(w.ab)."),
                .readback(tower, atc: "\(w.ab), vacate left at Charlie, taxi to the flying club.",
                          elements: [.phrase("Vacate", "vacate|vacating"), .phrase("At Charlie", "at c|via c|left c"),
                                     .phrase("Taxi to the club", "taxi", required: false)],
                          model: "Vacate left at Charlie, taxi to the flying club, \(w.ab)."),
            ],
            vocabulary: baseVocabulary
        )
    }

    // MARK: - AFIS and Air/Ground

    static let afisDeparture = Scenario(
        id: "afis-departure",
        title: "AFIS departure",
        summary: "Taxi and departure at an aerodrome with a Flight Information Service (Ashwell Information).",
        category: .uncontrolled
    ) { c in
        let w = Words(c: c)
        let afis = ashwellInfo.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Ashwell Information", ashwellInfo.1),
                BriefingItem("Weather", "Runway \(c.runway) · QNH \(c.qnh) · wind \(w.windText)"),
                BriefingItem("Plan", "Depart to the west, then London Information \(londonInfo.1)"),
            ],
            steps: [
                .call(afis,
                      task: "You're at the Ashwell flying club, about to depart to the west. Call Ashwell Information on \(ashwellInfo.1) and request taxi.",
                      elements: [.station(afis), .type(c.aircraft, required: false), .phrase("Request taxi", "taxi")],
                      model: "Ashwell Information, \(w.cs), \(w.type), at the flying club, request taxi."),
                .readback(afis, atc: "\(w.cs), Ashwell Information, runway \(w.rw), taxi to holding point Bravo, QNH \(w.qnh).",
                          elements: [.runway(c.runway), .phrase("Holding point Bravo", "point b|to b"), .pressure("QNH", c.qnh)],
                          model: "Runway \(w.rw), taxi holding point Bravo, QNH \(w.qnh), \(w.cs)."),
                .call(afis,
                      task: "Checks are complete at holding point Bravo. Tell the AFISO you're ready.",
                      elements: [.phrase("Ready for departure", "ready")],
                      model: "\(w.cs), ready for departure.",
                      cautions: [.takeoffWord]),
                .readback(afis, atc: "\(w.ab), no reported traffic, surface wind \(w.wind), take off at your discretion.",
                          task: "Reply to the AFISO. You're going now.",
                          elements: [.phrase("Taking off", "taking off|takeoff|lining up")],
                          model: "Taking off, \(w.ab)."),
                .call(afis,
                      task: "You're airborne and leaving the ATZ to the west. Tell Ashwell you're changing to London Information on \(londonInfo.1).",
                      elements: [.phrase("Leaving / changing frequency", "leaving|changing|freecall"),
                                 .phrase("Next unit", "london information|124.75", required: false)],
                      model: "\(w.ab), leaving the ATZ to the west, changing to London Information \(w.freq(londonInfo.1))."),
                .atcOnly(afis, "\(w.ab), roger."),
            ],
            vocabulary: baseVocabulary
        )
    }

    static let airGroundArrival = Scenario(
        id: "air-ground-arrival",
        title: "Air/Ground arrival and overhead join",
        summary: "Arriving at a farm strip with an Air/Ground radio service (Hadley Radio). No clearances: you report your intentions.",
        category: .uncontrolled
    ) { c in
        let w = Words(c: c)
        let radio = hadleyRadio.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Hadley Radio", hadleyRadio.1),
                BriefingItem("Position", "5 nm south of Hadley, 2,000 ft on QNH \(c.qnh), inbound to land"),
                BriefingItem("Join", "Standard overhead join"),
            ],
            steps: [
                .call(radio,
                      task: "You're 5 miles south of Hadley at 2,000 feet on QNH \(c.qnh), inbound to land. Call Hadley Radio on \(hadleyRadio.1) for airfield information.",
                      elements: [.station(radio), .type(c.aircraft, required: false),
                                 .phrase("Position", "5 miles|south", required: false),
                                 .altitude(2000, required: false),
                                 .phrase("Intentions (inbound to land)", "inbound|landing|to land|join", required: false),
                                 .phrase("Request airfield information", "airfield information|airfield details|information|details|runway in use")],
                      model: "Hadley Radio, \(w.cs), \(w.type), five miles south, two thousand feet, QNH \(w.qnh), inbound to land, request airfield information."),
                .readback(radio, atc: "\(w.cs), Hadley Radio, runway \(w.rw), \(c.circuit) hand, QNH \(w.qnh), no known traffic.",
                          task: "Read back the runway and pressure setting.",
                          elements: [.runway(c.runway), .phrase("\(c.circuit.capitalized) hand circuit", "\(c.circuit) hand|\(c.circuit)", required: false),
                                     .pressure("QNH", c.qnh)],
                          model: "Runway \(w.rw), \(c.circuit) hand, QNH \(w.qnh), \(w.cs)."),
                .call(radio,
                      task: "You're overhead at 2,000 feet. Report overhead, descending on the deadside.",
                      elements: [.phrase("Overhead", "overhead"), .phrase("Descending deadside", "deadside|descending", required: false)],
                      model: "\(w.cs), overhead, descending deadside."),
                .call(radio, atc: "\(w.cs), roger.",
                      task: "You're now downwind. Report downwind.",
                      elements: [.phrase("Downwind", "downwind")],
                      model: "\(w.cs), downwind."),
                .call(radio, atc: "\(w.ab), roger.",
                      task: "You're on final. Make your final call.",
                      elements: [.phrase("Final", "final")],
                      model: "\(w.ab), final.",
                      cautions: [.noClearances]),
                .atcOnly(radio, "\(w.ab), roger, surface wind \(w.wind)."),
            ],
            vocabulary: baseVocabulary
        )
    }

    // MARK: - En route

    static let basicService = Scenario(
        id: "basic-service",
        title: "Basic Service from London Information",
        summary: "Initial call, passing your message, regional pressure setting readback and changing frequency.",
        category: .enRoute
    ) { c in
        let w = Words(c: c)
        let fis = londonInfo.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("London Information", londonInfo.1),
                BriefingItem("Route", "Bramley to Ashwell, VFR"),
                BriefingItem("Position", "5 nm north of Bramley, 2,400 ft on QNH \(c.qnh)"),
                BriefingItem("Next frequency", "Ashwell Information \(ashwellInfo.1)"),
            ],
            steps: [
                .call(fis,
                      task: "You're en route from Bramley to Ashwell. Make initial contact with London Information on \(londonInfo.1) and ask for a Basic Service.",
                      elements: [.station(fis), .phrase("Basic Service", "basic service")],
                      model: "London Information, \(w.cs), request Basic Service."),
                .call(fis, atc: "\(w.cs), London Information, pass your message.",
                      task: "Pass your message: type, departure and destination, position, altitude and pressure setting, flight rules, request.",
                      elements: [.type(c.aircraft),
                                 .phrase("Departure and destination", "bramley.*ashwell|ashwell"),
                                 .phrase("Position", "north|miles"),
                                 .altitude(2400), .pressure("QNH", c.qnh, required: false),
                                 .phrase("Flight rules (VFR)", "vfr", required: false),
                                 .phrase("Request Basic Service", "basic service")],
                      model: "\(w.cs), \(w.type), from Bramley to Ashwell, five miles north of Bramley, two thousand four hundred feet, QNH \(w.qnh), VFR, request Basic Service."),
                .readback(fis, atc: "\(w.cs), Basic Service, \(c.regionName) pressure \(w.rps).",
                          task: "Read back the type of service and the regional pressure setting.",
                          elements: [.phrase("Basic Service", "basic service"), .pressure("\(c.regionName) pressure", c.regionalPressure)],
                          model: "Basic Service, \(c.regionName) \(w.rps), \(w.cs)."),
                .call(fis,
                      task: "You're approaching Ashwell. Tell London Information you're changing to Ashwell Information on \(ashwellInfo.1).",
                      elements: [.phrase("Changing frequency", "changing|leaving|freecall|frequency"),
                                 .phrase("Next unit", "ashwell|123.505", required: false)],
                      model: "\(w.cs), changing to Ashwell Information \(w.freq(ashwellInfo.1))."),
                .atcOnly(fis, "\(w.cs), Basic Service terminated, frequency change approved."),
            ],
            vocabulary: baseVocabulary + ["Basic Service", c.regionName]
        )
    }

    static let trafficService = Scenario(
        id: "traffic-service",
        title: "Traffic Service from a LARS unit",
        summary: "Squawk, identification, Traffic Service, traffic information and freecall with Westbury Radar.",
        category: .enRoute
    ) { c in
        let w = Words(c: c)
        let radar = westburyRadar.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Westbury Radar", westburyRadar.1),
                BriefingItem("Route", "Bramley to Ashwell, VFR"),
                BriefingItem("Position", "8 nm west of Westbury, 3,000 ft on QNH \(c.qnh)"),
                BriefingItem("Next frequency", "Ashwell Information \(ashwellInfo.1)"),
            ],
            steps: [
                .call(radar,
                      task: "Make initial contact with Westbury Radar on \(westburyRadar.1) and ask for a Traffic Service.",
                      elements: [.station(radar), .phrase("Traffic Service", "traffic service")],
                      model: "Westbury Radar, \(w.cs), request Traffic Service."),
                .call(radar, atc: "\(w.cs), Westbury Radar, pass your message.",
                      task: "Pass your message: type, departure and destination, position, altitude and pressure setting, request.",
                      elements: [.type(c.aircraft),
                                 .phrase("Departure and destination", "bramley.*ashwell|ashwell"),
                                 .phrase("Position", "west|miles"),
                                 .altitude(3000), .pressure("QNH", c.qnh, required: false),
                                 .phrase("Request Traffic Service", "traffic service")],
                      model: "\(w.cs), \(w.type), from Bramley to Ashwell, eight miles west of Westbury, three thousand feet, QNH \(w.qnh), request Traffic Service."),
                .readback(radar, atc: "\(w.cs), squawk \(w.sq).",
                          elements: [.squawk(c.squawk)],
                          model: "Squawk \(w.sq), \(w.cs)."),
                .readback(radar, atc: "\(w.ab), identified eight miles west of Westbury, Traffic Service, QNH \(w.qnh).",
                          task: "Read back the type of service and pressure setting.",
                          elements: [.phrase("Traffic Service", "traffic service"), .pressure("QNH", c.qnh)],
                          model: "Traffic Service, QNH \(w.qnh), \(w.ab)."),
                .readback(radar, atc: "\(w.ab), traffic, eleven o'clock, four miles, crossing left to right, indicating one thousand feet above.",
                          task: "Respond. You haven't spotted the traffic yet.",
                          elements: [.phrase("Looking / traffic in sight", "looking|in sight|visual|negative contact|not sighted")],
                          model: "Looking, \(w.ab)."),
                .call(radar, atc: "\(w.ab), previously reported traffic no longer a factor.",
                      task: "You're approaching Ashwell. Ask to leave the frequency for Ashwell Information.",
                      elements: [.phrase("Request frequency change", "frequency change|freecall|leave the frequency|changing")],
                      model: "\(w.ab), request frequency change to Ashwell Information."),
                .readback(radar, atc: "\(w.ab), Traffic Service terminated, squawk seven thousand, freecall Ashwell Information \(w.freq(ashwellInfo.1)).",
                          elements: [.squawk("7000"), .number("Frequency \(ashwellInfo.1)", ashwellInfo.1),
                                     .phrase("Ashwell Information", "ashwell", required: false)],
                          model: "Squawk seven thousand, freecall Ashwell Information \(w.freq(ashwellInfo.1)), \(w.ab)."),
            ],
            vocabulary: baseVocabulary + ["Traffic Service", "squawk", "identified"]
        )
    }

    static let matzCrossing = Scenario(
        id: "matz-crossing",
        title: "MATZ penetration",
        summary: "Crossing a Military Aerodrome Traffic Zone: squawk, QFE and reporting clear with Northfield Zone.",
        category: .enRoute
    ) { c in
        let w = Words(c: c)
        let zone = northfieldZone.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Northfield Zone", northfieldZone.1),
                BriefingItem("Route", "Bramley to Ashwell, VFR"),
                BriefingItem("Position", "10 nm south of Northfield, 2,000 ft on QNH \(c.qnh)"),
            ],
            steps: [
                .call(zone,
                      task: "Your route crosses the Northfield MATZ. Call Northfield Zone on \(northfieldZone.1) and request a MATZ penetration.",
                      elements: [.station(zone), .phrase("MATZ penetration", "matz penetration|penetration|matz")],
                      model: "Northfield Zone, \(w.cs), request MATZ penetration."),
                .call(zone, atc: "\(w.cs), Northfield Zone, pass your message.",
                      task: "Pass your message: type, departure and destination, position, altitude and pressure setting, request.",
                      elements: [.type(c.aircraft),
                                 .phrase("Departure and destination", "bramley.*ashwell|ashwell"),
                                 .phrase("Position", "south|miles"),
                                 .altitude(2000), .pressure("QNH", c.qnh, required: false),
                                 .phrase("Request MATZ penetration", "penetration|matz")],
                      model: "\(w.cs), \(w.type), from Bramley to Ashwell, one zero miles south of Northfield, two thousand feet, QNH \(w.qnh), request MATZ penetration."),
                .readback(zone, atc: "\(w.cs), squawk \(w.sq).",
                          elements: [.squawk(c.squawk)],
                          model: "Squawk \(w.sq), \(w.cs)."),
                .readback(zone, atc: "\(w.ab), identified, cleared to cross the MATZ not above two thousand feet, Northfield QFE \(w.qfe), report leaving the MATZ.",
                          task: "Read back the clearance.",
                          elements: [.phrase("Cleared to cross", "cleared"), .number("Not above two thousand feet", 2000),
                                     .pressure("QFE", c.qfe), .phrase("Wilco (report leaving)", "wilco|report leaving", required: false)],
                          model: "Cleared to cross the MATZ not above two thousand feet, QFE \(w.qfe), wilco, \(w.ab)."),
                .call(zone,
                      task: "You've left the MATZ to the north. Report leaving.",
                      elements: [.phrase("Leaving the MATZ", "leaving|clear of")],
                      model: "\(w.ab), leaving the MATZ to the north."),
                .readback(zone, atc: "\(w.ab), squawk seven thousand, QNH \(w.qnh), frequency change approved.",
                          elements: [.squawk("7000"), .pressure("QNH", c.qnh)],
                          model: "Squawk seven thousand, QNH \(w.qnh), \(w.ab)."),
            ],
            vocabulary: baseVocabulary + ["MATZ", "penetration", "QFE"]
        )
    }

    // MARK: - Emergencies

    static let mayday = Scenario(
        id: "mayday",
        title: "MAYDAY: engine failure",
        summary: "A full distress message to London Centre on 121.500, the squawk and cancelling the MAYDAY.",
        category: .emergency
    ) { c in
        let w = Words(c: c)
        let centre = londonCentre.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Frequency", "London Centre \(londonCentre.1)"),
                BriefingItem("Situation", "Engine failure passing 2,500 ft, 6 nm south of Bramley, heading 360"),
                BriefingItem("You", "PPL holder, \(c.personsOnBoard) POB"),
            ],
            steps: [
                Step(station: centre, atc: nil,
                     task: "Your engine has failed passing 2,500 feet, 6 miles south of Bramley, heading 360. You'll make a forced landing in a field. Make a MAYDAY call to London Centre on 121.500 with: type, nature of emergency, intentions, position, altitude, heading, qualification and persons on board.",
                     elements: [.phrase("MAYDAY ×3", "mayday mayday mayday"),
                                Element(label: "Station called (London Centre)", patterns: ["london centre"], required: false, kind: .station),
                                .callsign(), .type(c.aircraft),
                                .phrase("Nature of emergency", "engine"),
                                .phrase("Intentions", "forced landing|force land|landing|land"),
                                .phrase("Position", "south|miles"),
                                .altitude(2500),
                                .number("Heading three six zero", 360, required: false),
                                .phrase("Pilot qualification", "ppl|private pilot|student|licence|qualification", required: false),
                                .phrase("Persons on board", "pob|on board|persons|people|souls", required: false)],
                     model: "Mayday, Mayday, Mayday, London Centre, \(w.cs), \(w.type), engine failure, making a forced landing, six miles south of Bramley, passing two thousand five hundred feet, heading three six zero, PPL holder, \(w.pob) persons on board."),
                .readback(centre, atc: "Mayday \(w.cs), London Centre, roger Mayday, squawk seven seven zero zero.",
                          elements: [.squawk("7700")],
                          model: "Squawk seven seven zero zero, \(w.cs)."),
                .call(centre, atc: "\(w.cs), identified, report when on the ground.",
                      task: "You've landed safely in the field and nobody is hurt. Cancel the MAYDAY.",
                      elements: [.phrase("Cancel MAYDAY", "cancel mayday|cancel( my)? distress|mayday cancel"),
                                 .phrase("Landed safely", "landed|on the ground|safe", required: false)],
                      model: "London Centre, \(w.cs), cancel Mayday, landed safely in a field, no injuries."),
                .atcOnly(centre, "\(w.cs), London Centre, roger, Mayday cancelled."),
            ],
            vocabulary: baseVocabulary + ["Mayday", "London Centre", "forced landing", "PPL"]
        )
    }

    static let panPan = Scenario(
        id: "pan-pan",
        title: "PAN PAN: rough-running engine",
        summary: "An urgency message, diverting, and cancelling the PAN with London Centre.",
        category: .emergency
    ) { c in
        let w = Words(c: c)
        let centre = londonCentre.0
        return Script(
            briefing: [
                w.callsignItem, w.aircraftItem,
                BriefingItem("Frequency", "London Centre \(londonCentre.1)"),
                BriefingItem("Situation", "Rough-running engine at 3,000 ft, 8 nm west of Ashwell, heading 090"),
                BriefingItem("You", "PPL holder, \(c.personsOnBoard) POB"),
            ],
            steps: [
                Step(station: centre, atc: nil,
                     task: "Your engine is running rough at 3,000 feet, 8 miles west of Ashwell, heading 090. You decide to divert to Ashwell. Make a PAN PAN call to London Centre on 121.500.",
                     elements: [.phrase("PAN PAN ×3", "pan pan pan pan pan pan"),
                                Element(label: "Station called (London Centre)", patterns: ["london centre"], required: false, kind: .station),
                                .callsign(), .type(c.aircraft),
                                .phrase("Nature of the problem", "rough|engine"),
                                .phrase("Intentions", "divert|diverting|ashwell"),
                                .phrase("Position", "west|miles"),
                                .altitude(3000),
                                Element(label: "Heading zero niner zero", patterns: ["0?90"], required: false, numericValue: "090"),
                                .phrase("Pilot qualification", "ppl|private pilot|student|licence|qualification", required: false),
                                .phrase("Persons on board", "pob|on board|persons|people|souls", required: false)],
                     model: "Pan Pan, Pan Pan, Pan Pan, London Centre, \(w.cs), \(w.type), rough running engine, diverting to Ashwell, eight miles west of Ashwell, three thousand feet, heading zero niner zero, PPL holder, \(w.pob) persons on board."),
                .readback(centre, atc: "Pan Pan \(w.cs), London Centre, roger Pan, squawk seven seven zero zero, Ashwell bears zero niner zero degrees, eight miles.",
                          task: "Read back the squawk.",
                          elements: [.squawk("7700")],
                          model: "Squawk seven seven zero zero, \(w.cs)."),
                .call(centre, atc: "\(w.cs), identified, report Ashwell in sight.",
                      task: "Ashwell is in sight and the engine is running smoothly again. Cancel the PAN.",
                      elements: [.phrase("Cancel PAN", "cancel pan|cancel( my)? urgency|pan cancel")],
                      model: "London Centre, \(w.cs), cancel Pan, Ashwell in sight, engine running normally."),
                .readback(centre, atc: "\(w.cs), Pan cancelled, squawk seven thousand, freecall Ashwell Information \(w.freq(ashwellInfo.1)).",
                          elements: [.squawk("7000"), .number("Frequency \(ashwellInfo.1)", ashwellInfo.1)],
                          model: "Squawk seven thousand, freecall Ashwell Information \(w.freq(ashwellInfo.1)), \(w.cs)."),
            ],
            vocabulary: baseVocabulary + ["Pan Pan", "London Centre", "PPL"]
        )
    }
}
