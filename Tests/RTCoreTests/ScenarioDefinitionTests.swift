import XCTest
@testable import RTCore

final class ScenarioDefinitionTests: XCTestCase {
    private var packsDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scenario-packs")
    }

    /// Every scenario published in scenario-packs/ must decode and pass validation (example calls score 100%).
    func testPublishedPacksAreValid() throws {
        let indexData = try Data(contentsOf: packsDirectory.appendingPathComponent("index.json"))
        let index = try JSONDecoder().decode(ScenarioPackIndex.self, from: indexData)
        XCTAssertFalse(index.scenarios.isEmpty)
        var ids = Set<String>()
        for file in index.scenarios {
            let data = try Data(contentsOf: packsDirectory.appendingPathComponent(file))
            let definition = try ScenarioDefinition.decode(data)
            let problems = definition.validate(runs: 40)
            XCTAssertTrue(problems.isEmpty, "\(file):\n" + problems.joined(separator: "\n"))
            XCTAssertTrue(ids.insert(definition.id).inserted, "duplicate id \(definition.id)")
            XCTAssertNil(ScenarioLibrary.scenario(id: definition.id), "\(definition.id) clashes with a built-in scenario")
        }
    }

    func testPlaceholdersAndBuilding() throws {
        var g = SplitMix64(seed: 7)
        let ctx = FlightContext.random(using: &g, registration: "G-ABCD")
        XCTAssertEqual(Template.fill("{ab}, runway {rw}", Template.values(for: ctx)),
                       "Golf Charlie Delta, runway \(Phonetic.runway(ctx.runway))")
        XCTAssertEqual(Template.unknownPlaceholders(in: "{cs} {nope} (pan ){5}"), ["nope"])

        let definition = ScenarioDefinition(
            id: "t", title: "Test", summary: "", category: "controlled", briefing: [],
            steps: [
                .init(kind: "readback", station: "Bramley Tower", atc: "{ab}, runway {rw}, cleared to land.",
                      model: "Cleared to land, runway {rw}, {ab}.",
                      elements: [.init(type: "phrase", label: "Cleared to land", patterns: ["cleared to land"]),
                                 .init(type: "runway", label: "Runway")]),
            ])
        XCTAssertEqual(definition.validate(runs: 10), [])
        let script = definition.makeScenario().make(ctx)
        XCTAssertEqual(script.steps.first?.isReadback, true)
    }

    func testValidationCatchesBrokenScenarios() {
        let bad = ScenarioDefinition(
            id: "bad", title: "Bad", summary: "", category: "space", briefing: [],
            steps: [
                .init(kind: "readback", station: "Bramley Tower", atc: "{ab}, squawk {squawk}.",
                      task: "Read back.", model: "Roger, {ab}.",
                      elements: [.init(type: "squawk", label: "Squawk", value: "{squawkCode}")]),
            ])
        XCTAssertTrue(bad.validate().contains { $0.contains("Unknown category") })

        var fixedCategory = bad
        fixedCategory.category = "enRoute"
        let problems = fixedCategory.validate(runs: 3)
        XCTAssertTrue(problems.contains { $0.contains("fails its own checks") }, "\(problems)")

        var badRegex = fixedCategory
        badRegex.steps[0].elements = [.init(type: "phrase", label: "x", patterns: ["(unclosed"])]
        XCTAssertTrue(badRegex.validate().contains { $0.contains("not a valid regular expression") })
    }

    func testDecodingIsLenientAboutMissingOptionalFields() throws {
        let json = #"{"id":"x","title":"X","summary":"","category":"controlled","briefing":[],"steps":[{"kind":"atc","station":"Bramley Tower","atc":"Hello"}]}"#
        let d = try ScenarioDefinition.decode(Data(json.utf8))
        XCTAssertEqual(d.steps.first?.elements, [])
    }
}
