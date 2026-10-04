import XCTest
@testable import RTCore

final class NormalizerTests: XCTestCase {
    func testSpokenAndWrittenFormsMatch() {
        let spoken = Normalizer.canonical("Golf Alpha Bravo Charlie Delta, runway two six, QNH one zero one three")
        let written = Normalizer.canonical("G-ABCD runway 26 QNH 1013")
        XCTAssertEqual(spoken, "g a b c d runway 26 qnh 1013")
        XCTAssertEqual(written, spoken)
    }

    func testNumbers() {
        XCTAssertEqual(Normalizer.canonical("two thousand five hundred feet"), "2500 feet")
        XCTAssertEqual(Normalizer.canonical("2,500 ft"), "2500 ft")
        XCTAssertEqual(Normalizer.canonical("one zero thousand"), "10000")
        XCTAssertEqual(Normalizer.canonical("squawk seven thousand"), "squawk 7000")
        XCTAssertEqual(Normalizer.canonical("niner niner eight"), "998")
        XCTAssertEqual(Normalizer.canonical("runway twenty six"), "runway 26")
        XCTAssertEqual(Normalizer.canonical("PA twenty eight, one zero miles"), "pa 28 10 miles")
    }

    func testFrequencies() {
        XCTAssertEqual(Normalizer.canonical("one two four decimal seven five zero"), "124.75")
        XCTAssertEqual(Normalizer.canonical("124.750"), "124.75")
        XCTAssertEqual(Normalizer.canonical("124 point 75"), "124.75")
        XCTAssertEqual(Normalizer.canonical("one two one decimal five"), "121.5")
    }

    func testPhraseVariants() {
        XCTAssertEqual(Normalizer.canonical("Cleared for take-off"), "cleared for takeoff")
        XCTAssertEqual(Normalizer.canonical("cleared for take off"), "cleared for takeoff")
        XCTAssertEqual(Normalizer.canonical("Q N H"), "qnh")
        XCTAssertEqual(Normalizer.canonical("Pan-pan, pan-pan"), "pan pan pan pan")
        XCTAssertEqual(Normalizer.canonical("holding point A1"), "holding point a 1")
        XCTAssertEqual(Normalizer.canonical("Golf CD, wilco."), "g c d wilco")
    }

    func testCommonMishearings() {
        XCTAssertEqual(Normalizer.canonical("will co golf charlie delta"), "wilco g c d")
        XCTAssertEqual(Normalizer.canonical("runway to six"), "runway 26")
        XCTAssertEqual(Normalizer.canonical("Q and H one zero one for"), "qnh 1014")
        XCTAssertEqual(Normalizer.canonical("queue NH one oh one three"), "qnh 1013")
        XCTAssertEqual(Normalizer.canonical("squak four five two one"), "squawk 4521")
        XCTAssertEqual(Normalizer.canonical("Pam Pam Pam Pam"), "pan pan pan pan")
        // Real uses of "to"/"for" are left alone.
        XCTAssertEqual(Normalizer.canonical("cleared to land"), "cleared to land")
        XCTAssertEqual(Normalizer.canonical("descending to two thousand feet"), "descending to 2000 feet")
        XCTAssertEqual(Normalizer.canonical("ready for departure"), "ready for departure")
        XCTAssertEqual(Normalizer.canonical("changing to London Information"), "changing to london information")
    }
}

final class PhoneticTests: XCTestCase {
    func testSpokenForms() {
        XCTAssertEqual(Phonetic.digits(1013), "one zero one three")
        XCTAssertEqual(Phonetic.altitude(2500), "two thousand five hundred")
        XCTAssertEqual(Phonetic.altitude(10000), "one zero thousand")
        XCTAssertEqual(Phonetic.squawk("7000"), "seven thousand")
        XCTAssertEqual(Phonetic.squawk("4521"), "four five two one")
        XCTAssertEqual(Phonetic.frequency("124.750"), "one two four decimal seven five zero")
        XCTAssertEqual(Phonetic.frequency("121.500"), "one two one decimal five")
        XCTAssertEqual(Phonetic.runway("08L"), "zero eight left")
        XCTAssertEqual(Phonetic.spell("9"), "niner")
    }

    func testCallsigns() {
        var g = SplitMix64(seed: 1)
        let ctx = FlightContext.random(using: &g, registration: "g-abcd")
        XCTAssertEqual(ctx.registration, "G-ABCD")
        XCTAssertEqual(ctx.callsign, "Golf Alpha Bravo Charlie Delta")
        XCTAssertEqual(ctx.abbreviatedCallsign, "Golf Charlie Delta")
        XCTAssertEqual(ctx.callsignPattern, "g a b c d")
        XCTAssertNil(FlightContext.normaliseRegistration("N12345"))
    }
}

final class AnalyzerTests: XCTestCase {
    private func context() -> FlightContext {
        var g = SplitMix64(seed: 42)
        var ctx = FlightContext.random(using: &g, registration: "G-ABCD")
        ctx.runway = "26"
        ctx.qnh = 1013
        return ctx
    }

    private var taxiReadback: Step {
        .readback("Bramley Tower", atc: "Golf Charlie Delta, taxi to holding point Alpha One, runway two six, QNH one zero one three.",
                  elements: [.phrase("Holding point Alpha One", "a 1"), .runway("26"), .pressure("QNH", 1013)],
                  model: "")
    }

    func testGoodReadback() {
        let a = Analyzer.analyze(transcript: "Taxi holding point Alpha 1 runway 26 QNH 1013 Golf Charlie Delta",
                                 step: taxiReadback, context: context(), abbreviationAllowed: true)
        XCTAssertEqual(a.score, 100, "\(a.findings)")
        XCTAssertTrue(a.findings.isEmpty)
    }

    func testRogerIsNotAReadback() {
        let a = Analyzer.analyze(transcript: "Roger, Golf Charlie Delta", step: taxiReadback,
                                 context: context(), abbreviationAllowed: true)
        XCTAssertTrue(a.findings.contains { $0.severity == .major && $0.title.contains("Roger") })
        XCTAssertLessThan(a.score, 40)
        XCTAssertEqual(a.missingRequired.count, 3)
    }

    func testCallsignPlacementAndAbbreviation() {
        let a = Analyzer.analyze(transcript: "Golf Charlie Delta taxi holding point alpha one runway two six QNH one zero one three",
                                 step: taxiReadback, context: context(), abbreviationAllowed: false)
        let titles = a.findings.map(\.title)
        XCTAssertTrue(titles.contains("Callsign goes at the end of a readback"))
        XCTAssertTrue(titles.contains("Callsign abbreviated too early"))
    }

    func testNonStandardWords() {
        let step = Step.readback("Bramley Tower", atc: "", elements: [.phrase("Wilco", "wilco")], model: "")
        let a = Analyzer.analyze(transcript: "Copy that, okay, Golf Alpha Bravo Charlie Delta",
                                 step: step, context: context(), abbreviationAllowed: false)
        let titles = a.findings.map(\.title)
        XCTAssertTrue(titles.contains("\"Copy\" is not standard phraseology"))
        XCTAssertTrue(titles.contains("Avoid \"okay\""))
    }

    func testMergedNumbersStillCount() {
        let a = Analyzer.analyze(transcript: "Taxi holding point Alpha one runway two six one zero one three Golf Charlie Delta",
                                 step: taxiReadback, context: context(), abbreviationAllowed: true)
        XCTAssertTrue(a.elements.allSatisfy(\.matched), "\(a.canonical)")
    }

    func testSayAgain() {
        XCTAssertTrue(Analyzer.isSayAgainRequest("Golf Charlie Delta, say again"))
        XCTAssertFalse(Analyzer.isSayAgainRequest("Taxi holding point Alpha One runway two six QNH one zero one three Golf Charlie Delta say again"))
    }

    func testNothingHeard() {
        let a = Analyzer.analyze(transcript: "  ", step: taxiReadback, context: context(), abbreviationAllowed: true)
        XCTAssertEqual(a.score, 0)
    }
}

final class ScenarioLibraryTests: XCTestCase {
    /// Every model answer must score 100 with no findings, across many random flights.
    func testModelAnswersAreFlawless() {
        var g = SplitMix64(seed: 2024)
        for scenario in ScenarioLibrary.all {
            for _ in 0..<40 {
                let ctx = FlightContext.random(using: &g)
                let script = scenario.make(ctx)
                XCTAssertGreaterThan(script.pilotStepCount, 0)
                for (i, step) in script.steps.enumerated() where step.task != nil {
                    guard let model = step.model else {
                        XCTFail("\(scenario.id) step \(i) has no model answer")
                        continue
                    }
                    let a = Analyzer.analyze(transcript: model, step: step, context: ctx,
                                             abbreviationAllowed: script.abbreviationAllowed(at: i, context: ctx))
                    let missing = a.elements.filter { !$0.matched }.map(\.element.label)
                    XCTAssertEqual(a.score, 100, "\(scenario.id) step \(i) [\(ctx.registration)]: \(model)\n→ \(a.canonical)\nmissing: \(missing)")
                    XCTAssertTrue(a.findings.isEmpty, "\(scenario.id) step \(i): \(a.findings.map(\.title)) — \(a.canonical)")
                    XCTAssertTrue(missing.isEmpty, "\(scenario.id) step \(i): missing \(missing) — \(a.canonical)")
                }
            }
        }
    }

    func testScenarioIDsAreUnique() {
        XCTAssertEqual(Set(ScenarioLibrary.all.map(\.id)).count, ScenarioLibrary.all.count)
    }
}
