# RT Trainer: UK PPL radiotelephony practice for macOS

A macOS app for practising UK radio calls (CAP 413 phraseology) for the PPL FRTOL.
ATC transmissions are spoken aloud in a British voice, optionally with a VHF radio effect. You hold the space bar to transmit, and the app transcribes your call and analyses it.

## What it checks

Each transmission is scored against the items it must contain, plus general RT rules:

- **Required content**: runway, QNH/QFE/regional pressure, squawk, holding point, clearance wording, frequencies, ATIS letter, position and altitude, MAYDAY/PAN content, and so on.
- **Readbacks**: whether you read back what's required, and whether you used "Roger" where a readback is needed.
- **Callsign rules**: full callsign until ATC abbreviates it first; station name then callsign on initial contact; callsign at the end of a readback.
- **Non-standard words**: "repeat", "copy", "affirmative", "yes/no", "okay", "over and out", "ten-four", "roger wilco", and saying "take-off" when you aren't cleared for it.
- **Delivery**: hesitations, and speaking too fast (words per minute).

You get a score, a ✓/✗ checklist, explanations of any phraseology problems, and an example call. At the end of each scenario there's a debrief.

Numbers are compared by value, so the recogniser can write "1013", "one zero one three" or "niner niner eight" and still match. Phonetic letters, registrations ("G-ABCD") and RT pronunciations ("tree", "fife", "niner") are normalised in the same way.

## Scenarios

| Category | Scenario |
|---|---|
| Controlled aerodrome | Departure (radio check, taxi with ATIS, line up, take-off, leaving the zone) |
| Controlled aerodrome | Rejoin and circuit (join, downwind, sequencing, landing clearance, vacating) |
| AFIS & Air/Ground | AFIS departure ("take off at your discretion") |
| AFIS & Air/Ground | Air/Ground arrival with an overhead join |
| En route | Basic Service from London Information |
| En route | Traffic Service from a LARS unit (squawk, identification, traffic information, freecall) |
| En route | MATZ penetration (QFE, squawk, reporting clear) |
| Emergencies | MAYDAY: engine failure (London Centre 121.500) |
| Emergencies | PAN PAN: rough-running engine |

The callsign, runway, wind, QNH, squawk and ATIS letter are randomised on every run. You can set your own registration and aircraft type in **Settings** (⌘,).
Bramley, Ashwell, Hadley, Westbury and Northfield are fictional, so nobody mistakes their frequencies for real ones.

## More scenarios

**Check for new scenarios** (sidebar button, or File › Check for New Scenarios) downloads the free scenario packs published in [`scenario-packs/`](scenario-packs) of this repository and lists them under **Downloaded** in the sidebar. It needs no account or API key. New packs are added on request, for example by asking Claude Code to write some.

Every downloaded scenario is checked by the app before it's added: each example call has to pass its own checks across many random flights, so a broken scenario never marks you wrong unfairly.

### Scenario file format

Scenarios are JSON files (see [`scenario-packs/go-around.json`](scenario-packs/go-around.json)). Text can use placeholders such as `{cs}`, `{ab}`, `{rw}`, `{qnh}`, `{squawk}` and `{atis}`, which are filled from the randomised flight. The full list is `Template.placeholders` in `Sources/RTCore/ScenarioDefinition.swift`. To publish a scenario, add its file to `scenario-packs/` and list it in `index.json`. `make test` validates every published scenario.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later, or the Command Line Tools with Swift 5.9+
- A microphone. A headset reduces echo from the ATC voice.

## Build and run

```bash
make run        # same as: scripts/build-app.sh --open
```

This builds `build/RT Trainer.app`. It needs to be an app bundle so that macOS will ask for microphone and speech-recognition permission. Allow both when prompted. If you deny either one by mistake, re-enable it in System Settings › Privacy & Security.

Other targets:

```bash
make test       # run the RTCore unit tests
make app        # build the .app without launching
```

A zipped app is also attached to each CI run as the `RT-Trainer-app` artifact. Because it is only ad-hoc signed, macOS will block it the first time: right-click it and choose **Open**, or run `xattr -dr com.apple.quarantine "RT Trainer.app"`.

### Tips

- **Speech recognition:** on macOS 14+ the app builds an on-device language model trained on RT phraseology the first time it runs, which takes about a minute in the background. The microphone stays open while a scenario is running (you'll see the orange mic indicator), so the first word of each call isn't clipped. Recording continues for half a second after you release Space. If recognition is still poor with your accent, try turning off **Aviation-tuned recognition** in Settings to use Apple's server recognition.

- For a more realistic controller, download an **enhanced/premium British voice**. Go to System Settings › Accessibility › Spoken Content › System Voice › Manage Voices, then pick it in Settings.
- Turn off **Show ATC transmissions as text** to practise listening only.
- Transmit "Say again" to have ATC repeat the last call.
- After feedback, press **Return** to continue or hold **Space** to try the call again.

## Project layout

```
Sources/RTCore/        Platform-independent core (Foundation only)
  Phonetic.swift         Values → RT spoken form (altitudes, squawks, frequencies…)
  Normalizer.swift       Transcript → canonical tokens (numbers, phonetics, variants)
  Scenario.swift         Step / Element / Script model
  ScenarioLibrary.swift  The scenarios
  Analyzer.swift         Scoring and phraseology rules
Sources/ATCTrainer/    SwiftUI macOS app
  ATCVoice.swift         AVSpeechSynthesizer + radio effect (EQ, distortion, static)
  RadioRecognizer.swift  Push-to-talk SFSpeechRecognizer (en-GB, contextual vocabulary)
  TrainingSession.swift  Scenario flow
  *View.swift            UI
Tests/RTCoreTests/     Includes a test that every example call scores 100%
```

To add a scenario, write a new `Scenario` in `ScenarioLibrary.swift` and add it to `all`. The test suite checks that every example answer passes its own checks across many random flights.

## Disclaimer

This is a practice aid, not an approved training device. CAP 413 and your instructor are the authority on phraseology. Speech recognition can mishear, so if a result looks wrong, check the "Heard as" text.
