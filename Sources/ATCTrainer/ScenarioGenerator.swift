import Foundation
import RTCore

/// Generates new scenarios with Claude (Anthropic Messages API over HTTPS).
///
/// Claude returns a `ScenarioDefinition` as JSON (structured output against `scenarioSchema`). The app then runs
/// `validate()`; if any example call fails its own checks, the problems go back to Claude for one repair attempt.
struct ScenarioGenerator {
    static let model = "claude-opus-5-5"
    static let keychainAccount = "anthropic-api-key"

    enum GeneratorError: LocalizedError {
        case missingKey
        case http(Int, String)
        case refusal
        case truncated
        case badResponse(String)
        case invalid([String])

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Add your Anthropic API key first."
            case .http(401, _): return "The Anthropic API key was rejected. Check it in Settings."
            case .http(429, _): return "Anthropic's rate limit was reached. Wait a minute and try again."
            case .http(let code, let message): return "The Claude API returned an error (\(code)): \(message)"
            case .refusal: return "Claude declined to write that scenario. Try describing it differently."
            case .truncated: return "Claude's response was cut off. Try a shorter or simpler scenario."
            case .badResponse(let detail): return "Claude's response couldn't be read: \(detail)"
            case .invalid(let problems):
                return "Claude's scenario didn't pass the app's checks, so it wasn't added:\n• " + problems.prefix(4).joined(separator: "\n• ")
            }
        }
    }

    let apiKey: String

    /// - Parameters:
    ///   - request: what the student asked for (may be empty: Claude chooses).
    ///   - existingTitles: titles to avoid repeating.
    func generate(request: String, category: ScenarioCategory?, existingTitles: [String],
                  progress: @escaping @MainActor (String) -> Void) async throws -> ScenarioDefinition {
        guard !apiKey.isEmpty else { throw GeneratorError.missingKey }
        var messages: [[String: Any]] = [["role": "user", "content": userPrompt(request, category, existingTitles)]]

        for attempt in 1...2 {
            await progress(attempt == 1 ? "Claude is writing your scenario. This usually takes under a minute…"
                                        : "Claude is fixing problems the checks found…")
            let (content, text) = try await send(messages)

            var problems: [String]
            var definition: ScenarioDefinition?
            do {
                var d = try ScenarioDefinition.decode(Data(text.utf8))
                d.id = "gen-" + String(UUID().uuidString.lowercased().prefix(8))
                definition = d
                await progress("Checking every example call against the analyser…")
                let candidate = d
                problems = await Task.detached(priority: .userInitiated) { candidate.validate(runs: 20) }.value
            } catch {
                problems = ["The response wasn't valid scenario JSON (\(error.localizedDescription))."]
            }
            if let definition, problems.isEmpty { return definition }
            if attempt == 2 { throw GeneratorError.invalid(problems) }

            // Keep the assistant turn exactly as returned, then ask for a corrected version.
            messages.append(["role": "assistant", "content": content])
            messages.append(["role": "user", "content":
                "The app's automatic checks rejected that scenario:\n- " + problems.joined(separator: "\n- ")
                + "\n\nFix every problem and return the complete corrected scenario."])
        }
        throw GeneratorError.invalid([])
    }

    private func userPrompt(_ request: String, _ category: ScenarioCategory?, _ existing: [String]) -> String {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = "Write a new practice scenario.\n\n"
        prompt += "Student's request: " + (trimmed.isEmpty
            ? "your choice. Pick a realistic exercise a UK PPL student preparing for the FRTOL would benefit from."
            : trimmed) + "\n"
        if let category { prompt += "Category: \(category.key).\n" }
        prompt += "\nThe app already has these scenarios, so make something different:\n- " + existing.joined(separator: "\n- ")
        return prompt
    }

    /// Sends one Messages API request; returns the raw content blocks and the concatenated text.
    private func send(_ messages: [[String: Any]]) async throws -> ([Any], String) {
        let schema = try JSONSerialization.jsonObject(with: Data(Self.scenarioSchema.utf8))
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "system": Self.systemPrompt,
            "messages": messages,
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": schema]],
            "fallbacks": "default",
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = GeneratorError.badResponse("no response")
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(attempt) * 4_000_000_000) }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                continue
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard status == 200, let json else {
                let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
                lastError = GeneratorError.http(status, message)
                if status == 429 || status >= 500 { continue }  // retry overloads and server errors
                throw lastError
            }
            switch json["stop_reason"] as? String {
            case "refusal": throw GeneratorError.refusal
            case "max_tokens": throw GeneratorError.truncated
            default: break
            }
            let content = json["content"] as? [Any] ?? []
            let text = content.compactMap { block -> String? in
                guard let b = block as? [String: Any], b["type"] as? String == "text" else { return nil }
                return b["text"] as? String
            }.joined()
            guard !text.isEmpty else { throw GeneratorError.badResponse("no text in the response") }
            return (content, text)
        }
        throw lastError
    }

    // MARK: - Prompt

    static var systemPrompt: String {
        let placeholderList = Template.placeholders.map { "- {\($0.0)}: \($0.1)" }.joined(separator: "\n")
        return """
        You write practice scenarios for RT Trainer, a macOS app for UK student pilots practising PPL radiotelephony \
        (CAP 413 phraseology) for the FRTOL. The app speaks each ATC transmission aloud, the student replies by voice, \
        and every reply is checked automatically against the elements you define. Return one scenario as JSON matching \
        the schema.

        ## Realism
        - Follow current UK CAP 413 phraseology exactly: "ready for departure" (never "ready for take-off"), "affirm", \
        "QNH", "squawk", "Basic Service", "Traffic Service", "freecall", "wilco", conditional clearances with the \
        condition first, and so on.
        - Write numbers in ATC text and example calls as spoken RT: digits individually ("QNH one zero one three", \
        "squawk four five two one", "runway two six", "heading three six zero", "one two four decimal seven five zero"), \
        altitudes in thousands and hundreds ("two thousand four hundred feet"), and phonetic letters for taxiways and \
        ATIS ("holding point Alpha One", "information Charlie").
        - Use fictional places only: Bramley (controlled aerodrome with a Class D zone: Bramley Tower, Ground, Approach, \
        Radar), Ashwell (AFIS: "Ashwell Information"), Hadley (Air/Ground: "Hadley Radio"), Westbury Radar (LARS), \
        Northfield Zone (MATZ), or similar invented English names. The real units "London Information" (124.750) and \
        "London Centre" (121.500, distress and diversion) may be used. Never use real aerodromes or other real frequencies.
        - One coherent flight in 4 to 10 steps. Put frequencies, positions and plans the student needs into "briefing" \
        and into each task.

        ## Placeholders
        The app randomises each flight and replaces these placeholders before use. Never hard-code a callsign, \
        registration, runway, QNH, QFE, squawk, ATIS letter or wind; use the placeholders. Write values you choose \
        yourself (frequencies, altitudes, headings, positions, taxiways) literally.
        \(placeholderList)

        ## Steps
        - "station": the ATC unit transmitting or being called, e.g. "Bramley Tower". Required on every step.
        - "atc": the ATC transmission played before the pilot's turn, or "" if the pilot calls first.
        - "task": plain-English instructions telling the student what call to make, with any facts they need, without \
        giving the exact words.
        - "model": the correct pilot transmission.
        - kind "call": a pilot-initiated call or report. Initial contact is "Station, {cs}, message" (station first, then \
        callsign); later calls are "{ab}, message". The callsign must come before everything that's checked.
        - kind "readback": a reply to ATC. Read back the items, then the callsign LAST.
        - kind "emergency": a MAYDAY or PAN message (callsign position isn't checked).
        - kind "atc": ATC speaks and no reply is expected (use for a closing transmission).
        - Callsign: the pilot uses {cs} until ATC has used {ab} in that step's or an earlier step's ATC text; after \
        that the pilot uses {ab}. Controllers normally switch to {ab} after the first exchange. The callsign is checked \
        automatically on call, readback and emergency steps, so never add a callsign element.

        ## Elements (what each reply must contain)
        Before checking, the student's words are normalised: lower-case; punctuation removed; phonetic alphabet words \
        become single letters ("alpha one" -> "a 1", "information charlie" -> "information c"); numbers become digit \
        strings ("one zero one three" -> "1013", "two thousand four hundred" -> "2400", "one two four decimal seven five \
        zero" -> "124.75"); "take-off" -> "takeoff"; "Q N H" -> "qnh".
        - "phrase": "patterns" are regular expressions matched on word boundaries against the normalised text. Keep them \
        short and lenient, with alternatives: ["cleared to land|clear to land"], ["line up and wait|line up wait"], \
        ["a 1"] for holding point Alpha One, ["information {atisLower}"] for the ATIS letter, ["{circuit} hand"].
        - "number", "pressure", "altitude", "squawk", "runway": put the value in "value", as digits or a placeholder \
        ("{qnhValue}", "{squawkCode}", "{runway}", "2000", "118.330"); leave "patterns" empty.
        - "aircraftType": checks the type was stated; "value" "".
        - "station": "value" is the station name; use it only on initial contact.
        - Readbacks must require everything CAP 413 says must be read back: clearances, runway, pressure settings, \
        squawks, frequencies, levels and altitudes, headings, and the condition of a conditional clearance.
        - Every required element must be satisfied by the model answer. Mark nice-to-have items "required": false.

        ## Cautions
        Use "takeoffWord" on ready-for-departure calls, "lineUpOnly" on line-up-and-wait readbacks, and "noClearances" \
        on calls to AFIS or Air/Ground stations. Otherwise leave "cautions" empty.

        ## Model answers must not contain
        "over", "copy", "okay", "yes", "no" at the start, "repeat", "affirmative" or "roger wilco".

        ## Example
        \(exampleScenario)
        """
    }

    static let exampleScenario = #"{"id":"pack-go-around","category":"controlled","title":"Go-around and second approach","summary":"An instructed go-around from final at Bramley, then a second circuit to land.","briefing":[{"label":"Callsign","value":"{reg} — {cs}"},{"label":"Aircraft","value":"{typeCode}"},{"label":"Bramley Tower","value":"118.330"},{"label":"Circuit","value":"Runway {runway} · {Circuit}-hand · QNH {qnhValue} · 1,000 ft"}],"steps":[{"kind":"call","station":"Bramley Tower","atc":"","task":"You're on the downwind leg at Bramley and intend to land. Make your downwind call.","model":"{cs}, downwind to land.","elements":[{"type":"phrase","label":"Downwind","value":"","patterns":["downwind"],"required":true},{"type":"phrase","label":"Intentions (to land)","value":"","patterns":["land|full stop"],"required":false}],"cautions":[]},{"kind":"call","station":"Bramley Tower","atc":"{ab}, number one, report final.","task":"You're turning final. Make your final call.","model":"{ab}, final.","elements":[{"type":"phrase","label":"Final","value":"","patterns":["final"],"required":true}],"cautions":[]},{"kind":"readback","station":"Bramley Tower","atc":"{ab}, go around, I say again, go around, acknowledge.","task":"Acknowledge the go-around instruction.","model":"Going around, {ab}.","elements":[{"type":"phrase","label":"Going around","value":"","patterns":["going around|go around"],"required":true}],"cautions":[]},{"kind":"readback","station":"Bramley Tower","atc":"{ab}, vehicle on the runway, climb straight ahead to one thousand feet, report downwind.","task":"","model":"Straight ahead, climbing to one thousand feet, wilco, {ab}.","elements":[{"type":"phrase","label":"Straight ahead","value":"","patterns":["straight ahead"],"required":false},{"type":"altitude","label":"Climb to one thousand feet","value":"1000","patterns":[],"required":true},{"type":"phrase","label":"Wilco (report downwind)","value":"","patterns":["wilco|report downwind"],"required":true}],"cautions":[]},{"kind":"call","station":"Bramley Tower","atc":"","task":"You're back on the downwind leg. Report downwind.","model":"{ab}, downwind.","elements":[{"type":"phrase","label":"Downwind","value":"","patterns":["downwind"],"required":true}],"cautions":[]},{"kind":"call","station":"Bramley Tower","atc":"{ab}, runway now clear, number one, report final.","task":"You're on final again. Make your final call.","model":"{ab}, final.","elements":[{"type":"phrase","label":"Final","value":"","patterns":["final"],"required":true}],"cautions":[]},{"kind":"readback","station":"Bramley Tower","atc":"{ab}, runway {rw}, cleared to land, surface wind {wind}.","task":"Read back the landing clearance.","model":"Cleared to land, runway {rw}, {ab}.","elements":[{"type":"phrase","label":"Cleared to land","value":"","patterns":["cleared to land|clear to land"],"required":true},{"type":"runway","label":"Runway {rw}","value":"{runway}","patterns":[],"required":true}],"cautions":[]},{"kind":"readback","station":"Bramley Tower","atc":"{ab}, vacate left at Charlie.","task":"","model":"Vacate left at Charlie, {ab}.","elements":[{"type":"phrase","label":"Vacate","value":"","patterns":["vacate|vacating"],"required":true},{"type":"phrase","label":"At Charlie","value":"","patterns":["at c|via c|left c"],"required":true}],"cautions":[]}]}"#

    static let scenarioSchema = #"{"type":"object","additionalProperties":false,"required":["id","title","summary","category","briefing","steps"],"properties":{"id":{"type":"string"},"title":{"type":"string"},"summary":{"type":"string"},"category":{"type":"string","enum":["controlled","uncontrolled","enRoute","emergency"]},"briefing":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["label","value"],"properties":{"label":{"type":"string"},"value":{"type":"string"}}}},"steps":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["kind","station","atc","task","model","elements","cautions"],"properties":{"kind":{"type":"string","enum":["call","readback","emergency","atc"]},"station":{"type":"string"},"atc":{"type":"string"},"task":{"type":"string"},"model":{"type":"string"},"elements":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["type","label","value","patterns","required"],"properties":{"type":{"type":"string","enum":["phrase","number","pressure","altitude","squawk","runway","aircraftType","station"]},"label":{"type":"string"},"value":{"type":"string"},"patterns":{"type":"array","items":{"type":"string"}},"required":{"type":"boolean"}}}},"cautions":{"type":"array","items":{"type":"string","enum":["takeoffWord","lineUpOnly","noClearances"]}}}}}}}"#
}
