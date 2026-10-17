import RTCore
import SwiftUI

/// Inspector: analysis of the latest transmission, or reminders while waiting.
struct FeedbackColumn: View {
    @ObservedObject var session: TrainingSession

    var body: some View {
        Group {
            if let analysis = session.lastAnalysis {
                FeedbackView(analysis: analysis, model: session.currentStep?.model)
            } else if session.phase == .finished {
                ContentUnavailableView("Scenario Complete", systemImage: "flag.checkered",
                                       description: Text("Your debrief is on the left."))
            } else {
                WaitingTips(step: session.currentStep)
            }
        }
        .animation(.ui, value: session.lastAnalysis?.transcript)
    }
}

struct FeedbackView: View {
    let analysis: Analysis
    let model: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ScoreRing(score: analysis.score)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(analysis.grade.rawValue)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.forScore(analysis.score))
                        if let wpm = analysis.wordsPerMinute {
                            Text("≈ \(Int(wpm)) words per minute")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Heard As") {
                Text(analysis.transcript.isEmpty ? "(nothing)" : "“\(analysis.transcript)”")
                    .italic()
                    .textSelection(.enabled)
            }

            Section("Required Items") {
                ForEach(analysis.elements) { result in
                    Label {
                        HStack {
                            Text(result.element.label)
                                .foregroundStyle(result.matched || result.element.required ? .primary : .secondary)
                            if !result.element.required {
                                Spacer()
                                Text("Optional").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    } icon: {
                        Image(systemName: symbol(for: result))
                            .foregroundStyle(color(for: result))
                    }
                }
            }

            if !analysis.findings.isEmpty {
                Section("Phraseology") {
                    ForEach(analysis.findings) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(finding.title, systemImage: finding.severity.symbol)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(finding.severity.color)
                            Text(finding.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let model {
                Section("Example") {
                    Text(model).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func symbol(for r: ElementResult) -> String {
        r.matched ? "checkmark.circle.fill" : (r.element.required ? "xmark.circle.fill" : "minus.circle")
    }

    private func color(for r: ElementResult) -> Color {
        r.matched ? .green : (r.element.required ? .red : .secondary)
    }
}

extension Finding.Severity {
    var symbol: String {
        switch self {
        case .major: return "exclamationmark.octagon.fill"
        case .minor: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .major: return .red
        case .minor: return .orange
        case .info: return .blue
        }
    }
}

/// Circular score gauge. The ring fills with a critically damped spring (or instantly with Reduce Motion).
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 70
    @State private var shown: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Color.forScore(score).gradient, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .onChange(of: score) { animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score) percent")
    }

    private func animate() {
        let target = CGFloat(score) / 100
        if reduceMotion { shown = target } else { withAnimation(.spring(response: 0.6, dampingFraction: 1)) { shown = target } }
    }
}

struct WaitingTips: View {
    let step: Step?

    var body: some View {
        Form {
            Section("CAP 413 Reminders") {
                tip("brain.head.profile", "Think, press, talk", "Plan the whole call before pressing the transmit key, and don't clip the first word.")
                tip("antenna.radiowaves.left.and.right", "Initial calls", "Station you're calling, your full callsign, then the message.")
                tip("arrow.uturn.backward", "Readbacks", "Clearances, runway, pressure settings, squawks, frequencies and levels, then your callsign.")
                tip("textformat.abc", "Abbreviating", "Only shorten your callsign (G-CD) after ATC has done so.")
                tip("number", "Numbers", "Digits individually: “QNH one zero one three”. Altitudes in thousands and hundreds.")
            }
            if let step, step.task != nil {
                Section("What Will Be Checked") {
                    DisclosureGroup("Show checklist") {
                        ForEach(step.elements) { element in
                            HStack {
                                Text(element.label)
                                if !element.required {
                                    Spacer()
                                    Text("Optional").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

struct DebriefView: View {
    @ObservedObject var session: TrainingSession
    let onRestart: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    private var assessed: [(index: Int, step: Step, analysis: Analysis?)] {
        session.script.steps.enumerated().compactMap { i, step in
            step.task == nil ? nil : (i, step, session.results[i])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 24) {
                    ScoreRing(score: session.averageScore ?? 0, size: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scenario Complete")
                            .font(.largeTitle.weight(.bold))
                        Text(session.scenario.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button {
                                onRestart()
                            } label: {
                                Label("Fly Again", systemImage: "arrow.clockwise")
                                    .frame(minWidth: 110)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            Button("Done") { onClose() }
                                .controlSize(.large)
                        }
                        .padding(.top, 6)
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: "Average", value: "\(session.averageScore ?? 0)%")
                    StatTile(title: "Calls assessed", value: "\(session.results.count) of \(session.script.pilotStepCount)")
                    StatTile(title: "Best call", value: session.results.values.map(\.score).max().map { "\($0)%" } ?? "—")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your Calls").font(.headline)
                    ForEach(assessed, id: \.index) { item in
                        DebriefRow(task: item.step.task ?? "", model: item.step.model, analysis: item.analysis)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DebriefRow: View {
    let task: String
    let model: String?
    let analysis: Analysis?
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let analysis {
                    LabeledContent("You said") {
                        Text(analysis.transcript.isEmpty ? "(nothing heard)" : analysis.transcript)
                            .textSelection(.enabled)
                    }
                    let issues = analysis.missingRequired.map { "Missing: \($0.label)" }
                        + analysis.findings.filter { $0.severity > .info }.map(\.title)
                    if !issues.isEmpty {
                        LabeledContent("To improve") {
                            Text(issues.joined(separator: "\n")).foregroundStyle(.orange)
                        }
                    }
                }
                if let model {
                    LabeledContent("Example") { Text(model).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            .font(.callout)
            .padding(.top, 6)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let analysis {
                    ScoreBadge(score: analysis.score)
                } else {
                    Text("Skipped").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(task).lineLimit(2)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
