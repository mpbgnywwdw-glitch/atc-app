import AppKit
import RTCore
import SwiftUI

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TrainingSession
    @ObservedObject private var recognizer: RadioRecognizer
    @AppStorage(Prefs.showATCText) private var showATCText = true
    @State private var keyMonitor: Any?
    @State private var showModel = false

    init(session: TrainingSession) {
        _session = ObservedObject(wrappedValue: session)
        // The recogniser is shared app-wide; observe it for the live transcript and level meter.
        _recognizer = ObservedObject(wrappedValue: session.recognizerForUI)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                BriefingBar(items: session.script.briefing)
                Divider()
                if session.phase == .finished {
                    DebriefView(session: session) { model.start(session.scenario) }
                } else {
                    transcript
                    Divider()
                    controls
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FeedbackColumn(session: session)
                .frame(width: 320)
        }
        .toolbar { toolbarButtons }
        .navigationTitle(session.scenario.title)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: session.index) { _ in showModel = false }
        .alert("Can't transmit", isPresented: Binding(get: { session.errorMessage != nil },
                                                      set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.log) { entry in
                        LogBubble(entry: entry, hidden: session.isHidden(entry, showText: showATCText),
                                  callsign: session.context.registration)
                            .id(entry.id)
                    }
                    if session.phase == .recording {
                        LiveBubble(text: recognizer.transcript)
                            .id("live")
                    }
                }
                .padding(20)
            }
            .onChange(of: session.log.count) { _ in
                if let last = session.log.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .onChange(of: recognizer.transcript) { _ in
                proxy.scrollTo("live", anchor: .bottom)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Call \(max(1, session.pilotStepNumber)) of \(session.script.pilotStepCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                statusLabel
            }

            if let task = session.currentStep?.task, session.phase != .atcSpeaking || session.currentStep?.atc == nil {
                Text(task)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if session.phase == .atcSpeaking {
                Text("Listen…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if showModel, let modelAnswer = session.currentStep?.model {
                Text(modelAnswer)
                    .font(.body.italic())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
            }

            HStack(alignment: .center, spacing: 16) {
                PTTButton(active: session.phase == .recording,
                          enabled: [.awaitingPilot, .reviewing, .recording].contains(session.phase),
                          level: recognizer.level,
                          onDown: { session.pttDown() }, onUp: { session.pttUp() })

                if session.phase == .reviewing {
                    Button {
                        session.next()
                    } label: {
                        Label("Continue", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    Text("or hold Space to try again")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .background(.bar)
    }

    @ToolbarContentBuilder private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                session.replayATC()
            } label: {
                Label("Replay ATC", systemImage: "arrow.counterclockwise")
            }
            .help("Replay the last ATC transmission")
            .disabled(session.currentStep?.atc == nil || ![.awaitingPilot, .reviewing].contains(session.phase))

            Button {
                showModel.toggle()
            } label: {
                Label(showModel ? "Hide example" : "Show example", systemImage: "lightbulb")
            }
            .help("Show an example of this call")
            .disabled(session.currentStep?.model == nil || session.phase == .finished)

            Button {
                session.skip()
            } label: {
                Label("Skip", systemImage: "forward")
            }
            .help("Skip this call")
            .disabled(session.phase == .finished)

            Button {
                model.endSession()
            } label: {
                Label("End", systemImage: "xmark.circle")
            }
            .help("End this scenario")
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .ready: Label("Starting", systemImage: "hourglass").foregroundStyle(.secondary)
        case .atcSpeaking: Label("ATC transmitting", systemImage: "speaker.wave.3.fill").foregroundStyle(.blue)
        case .awaitingPilot: Label("Your call: hold Space", systemImage: "mic").foregroundStyle(.primary)
        case .recording: Label("Transmitting", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.red)
        case .analysing: Label("Analysing", systemImage: "waveform").foregroundStyle(.secondary)
        case .reviewing: Label("Review your call", systemImage: "checkmark.bubble").foregroundStyle(.green)
        case .finished: Label("Complete", systemImage: "flag.checkered").foregroundStyle(.green)
        }
    }

    // MARK: Space bar push-to-talk

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == 49 else { return event } // space
            // Let text fields (e.g. Settings) receive spaces normally.
            if let responder = event.window?.firstResponder, responder is NSText { return event }
            if event.type == .keyDown {
                if !event.isARepeat { session.pttDown() }
            } else {
                session.pttUp()
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - Pieces

struct BriefingBar: View {
    let items: [BriefingItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.callout.monospacedDigit())
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

struct LogBubble: View {
    let entry: TrainingSession.LogEntry
    let hidden: Bool
    let callsign: String
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .top) {
            if isPilot { Spacer(minLength: 80) }
            VStack(alignment: isPilot ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isPilot ? "person.wave.2" : "antenna.radiowaves.left.and.right")
                    Text(speakerName).font(.caption.weight(.semibold))
                    if let a = entry.analysis { ScoreBadge(score: a.score) }
                }
                .foregroundStyle(.secondary)

                Group {
                    if hidden && !revealed {
                        Button("Transmission hidden (click to reveal)") { revealed = true }
                            .buttonStyle(.link)
                    } else {
                        Text(entry.text).textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(isPilot ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
            }
            if !isPilot { Spacer(minLength: 80) }
        }
    }

    private var isPilot: Bool { entry.speaker == .pilot }

    private var speakerName: String {
        switch entry.speaker {
        case .atc(let station): return station
        case .pilot: return "You (\(callsign))"
        }
    }
}

struct LiveBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(text.isEmpty ? "Listening…" : text)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5))
        }
    }
}

struct PTTButton: View {
    let active: Bool
    let enabled: Bool
    let level: Float
    let onDown: @MainActor () -> Void
    let onUp: @MainActor () -> Void
    @State private var pressing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(active ? Color.red : (enabled ? Color.accentColor : Color.gray.opacity(0.4)))
            Circle()
                .stroke(Color.red.opacity(0.35), lineWidth: 6)
                .scaleEffect(1 + CGFloat(active ? level : 0) * 0.35)
            VStack(spacing: 2) {
                Image(systemName: active ? "mic.fill" : "mic")
                    .font(.system(size: 22, weight: .semibold))
                Text("PTT").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .animation(.easeOut(duration: 0.1), value: level)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressing else { return }
                    pressing = true
                    onDown()
                }
                .onEnded { _ in
                    guard pressing else { return }
                    pressing = false
                    onUp()
                }
        )
        .help("Hold to transmit (or hold the space bar)")
    }
}

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)%")
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.forScore(score).opacity(0.2)))
            .foregroundStyle(Color.forScore(score))
    }
}

extension Color {
    static func forScore(_ score: Int) -> Color {
        switch score {
        case 85...: return .green
        case 60..<85: return .orange
        default: return .red
        }
    }
}
