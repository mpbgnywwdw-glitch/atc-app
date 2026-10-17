import AppKit
import RTCore
import SwiftUI

/// Default spring for UI state changes: critically damped (no overshoot), quick response.
extension Animation {
    static let ui = Animation.spring(response: 0.35, dampingFraction: 1)
}

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TrainingSession
    @ObservedObject private var recognizer: RadioRecognizer
    @AppStorage(Prefs.showATCText) private var showATCText = true
    @AppStorage("showFeedbackInspector") private var showInspector = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyMonitor: Any?

    init(session: TrainingSession) {
        _session = ObservedObject(wrappedValue: session)
        // The recogniser is shared app-wide; observe it for the live transcript and level meter.
        _recognizer = ObservedObject(wrappedValue: session.recognizerForUI)
    }

    var body: some View {
        Group {
            if session.phase == .finished {
                DebriefView(session: session,
                            onRestart: { model.start(session.scenario) },
                            onClose: { model.endSession() })
            } else {
                conversation
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        .inspector(isPresented: $showInspector) {
            FeedbackColumn(session: session)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 440)
        }
        .toolbar { toolbarContent }
        .navigationTitle(session.scenario.title)
        .navigationSubtitle(subtitle)
        .focusedSceneObject(session)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .alert("Can't transmit", isPresented: Binding(get: { session.errorMessage != nil },
                                                      set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var subtitle: String {
        session.phase == .finished
            ? "Debrief · \(session.context.registration)"
            : "Call \(max(1, session.pilotStepNumber)) of \(session.script.pilotStepCount) · \(session.context.registration)"
    }

    private var entryTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BriefingCard(items: session.script.briefing)
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(session.log) { entry in
                            LogBubble(entry: entry, hidden: session.isHidden(entry, showText: showATCText),
                                      callsign: session.context.registration)
                                .id(entry.id)
                                .transition(entryTransition)
                        }
                        if session.phase == .recording {
                            LiveBubble(text: recognizer.transcript)
                                .id("live")
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .ui, value: session.log.count)
                    .animation(.ui, value: session.phase == .recording)
                }
                .padding(20)
            }
            .onChange(of: session.log.count) {
                if let last = session.log.last?.id {
                    withAnimation(.ui) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .onChange(of: recognizer.transcript) {
                proxy.scrollTo("live", anchor: .bottom)
            }
        }
        // The transmit bar floats over the transcript as a translucent layer.
        .safeAreaInset(edge: .bottom, spacing: 0) { transmitBar }
    }

    // MARK: Transmit bar

    private var transmitBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView(value: Double(max(0, session.pilotStepNumber - (session.phase == .reviewing ? 0 : 1))),
                             total: Double(max(1, session.script.pilotStepCount)))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 140)
                Text("Call \(max(1, session.pilotStepNumber)) of \(session.script.pilotStepCount)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusPill(phase: session.phase)
            }

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(taskText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(session.phase == .atcSpeaking ? .secondary : .primary)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if session.showingExample, let example = session.currentStep?.model {
                        Label {
                            Text(example).textSelection(.enabled)
                        } icon: {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                        }
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .transition(.opacity)
                    }
                }
                .animation(.ui, value: session.showingExample)

                VStack(spacing: 8) {
                    PTTButton(active: session.phase == .recording,
                              enabled: [.awaitingPilot, .reviewing, .recording].contains(session.phase),
                              level: recognizer.level,
                              onDown: { session.pttDown() }, onUp: { session.pttUp() })
                    if session.phase == .reviewing {
                        Button {
                            session.next()
                        } label: {
                            Text("Continue")
                                .frame(minWidth: 90)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                        .help("Next call (Return). Hold Space to try this one again.")
                    } else {
                        Text("Hold to Talk")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 110)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var taskText: String {
        if session.phase == .atcSpeaking, session.currentStep?.atc != nil { return "Listen…" }
        return session.currentStep?.task ?? ""
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                session.replayATC()
            } label: {
                Label("Replay ATC", systemImage: "arrow.counterclockwise")
            }
            .help("Replay the last ATC transmission (⌘R)")
            .disabled(!session.canReplay)

            Toggle(isOn: $session.showingExample) {
                Label("Show Example", systemImage: "lightbulb")
            }
            .help("Show an example of this call (⌘E)")
            .disabled(session.currentStep?.model == nil || session.phase == .finished)

            Button {
                session.skip()
            } label: {
                Label("Skip Call", systemImage: "forward.end")
            }
            .help("Skip this call (⌘K)")
            .disabled(session.phase == .finished)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.endSession()
            } label: {
                Label("End Scenario", systemImage: "xmark.circle")
            }
            .help("End this scenario (⌘.)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInspector.toggle()
            } label: {
                Label("Feedback", systemImage: "sidebar.right")
            }
            .help(showInspector ? "Hide feedback" : "Show feedback")
        }
    }

    // MARK: Space bar push-to-talk

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == 49 else { return event } // space
            // Let text fields (search, Settings) receive spaces normally.
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

/// What the app is doing right now: a small coloured capsule.
struct StatusPill: View {
    let phase: TrainingSession.Phase

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .animation(.ui, value: phase)
            .contentTransition(.opacity)
    }

    private var text: String {
        switch phase {
        case .ready: return "Starting"
        case .atcSpeaking: return "ATC transmitting"
        case .awaitingPilot: return "Your call"
        case .recording: return "Transmitting"
        case .analysing: return "Analysing"
        case .reviewing: return "Review"
        case .finished: return "Complete"
        }
    }

    private var symbol: String {
        switch phase {
        case .ready: return "hourglass"
        case .atcSpeaking: return "speaker.wave.2.fill"
        case .awaitingPilot: return "mic"
        case .recording: return "dot.radiowaves.left.and.right"
        case .analysing: return "waveform"
        case .reviewing: return "checkmark.bubble"
        case .finished: return "flag.checkered"
        }
    }

    private var color: Color {
        switch phase {
        case .ready, .analysing: return .secondary
        case .atcSpeaking: return .blue
        case .awaitingPilot: return .accentColor
        case .recording: return .red
        case .reviewing, .finished: return .green
        }
    }
}

/// Flight details for the scenario, as a quiet card at the top of the transcript.
struct BriefingCard: View {
    let items: [BriefingItem]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(items) { item in
                GridRow {
                    Text(item.label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(item.value)
                        .font(.callout.monospacedDigit())
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LogBubble: View {
    let entry: TrainingSession.LogEntry
    let hidden: Bool
    let callsign: String
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isPilot { Spacer(minLength: 60) } else { avatar }
            VStack(alignment: isPilot ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(speakerName).font(.caption.weight(.semibold))
                    if let a = entry.analysis { ScoreBadge(score: a.score) }
                }
                .foregroundStyle(.secondary)

                Group {
                    if hidden && !revealed {
                        Button {
                            revealed = true
                        } label: {
                            Label("Hidden. Click to reveal", systemImage: "eye.slash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(entry.text)
                            .textSelection(.enabled)
                            .foregroundStyle(isPilot ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isPilot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if isPilot { avatar } else { Spacer(minLength: 60) }
        }
    }

    private var avatar: some View {
        Image(systemName: isPilot ? "person.fill" : "antenna.radiowaves.left.and.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(isPilot ? Color.accentColor.gradient : Color.gray.gradient, in: Circle())
    }

    private var isPilot: Bool { entry.speaker == .pilot }

    private var speakerName: String {
        switch entry.speaker {
        case .atc(let station): return station
        case .pilot: return "You · \(callsign)"
        }
    }
}

struct LiveBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Label {
                Text(text.isEmpty ? "Listening…" : text)
            } icon: {
                Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.red.opacity(0.6), lineWidth: 1.5))
        }
    }
}

/// Push-to-talk button. Feedback starts the instant it's pressed, not on release.
struct PTTButton: View {
    let active: Bool
    let enabled: Bool
    let level: Float
    let onDown: @MainActor () -> Void
    let onUp: @MainActor () -> Void
    @State private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.3), lineWidth: 8)
                .scaleEffect(1 + CGFloat(active ? level : 0) * 0.3)
                .opacity(active ? 1 : 0)
            Circle()
                .fill(fill.gradient)
                .shadow(color: fill.opacity(enabled ? 0.35 : 0), radius: active ? 10 : 6, y: 3)
            Image(systemName: active ? "mic.fill" : "mic")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 76, height: 76)
        .scaleEffect(pressing || active ? 0.94 : 1)
        .animation(reduceMotion ? nil : .ui, value: pressing || active)
        .animation(.easeOut(duration: 0.08), value: level)
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
        .accessibilityLabel("Push to talk")
        .accessibilityHint("Hold to transmit, or hold the space bar")
        .help("Hold to transmit (or hold the space bar)")
    }

    private var fill: Color {
        active ? .red : (enabled ? .accentColor : .gray.opacity(0.5))
    }
}

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)%")
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.forScore(score).opacity(0.18), in: Capsule())
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
