import RTCore
import SwiftUI

/// Right-hand panel: analysis of the latest transmission, or tips while waiting.
struct FeedbackColumn: View {
    @ObservedObject var session: TrainingSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let analysis = session.lastAnalysis {
                    FeedbackView(analysis: analysis, model: session.currentStep?.model)
                } else if session.phase == .finished {
                    Text("Scenario complete").font(.title2.weight(.semibold))
                } else {
                    WaitingTips(step: session.currentStep)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FeedbackView: View {
    let analysis: Analysis
    let model: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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

            section("Heard as") {
                Text(analysis.transcript.isEmpty ? "(nothing)" : analysis.transcript)
                    .italic()
                    .textSelection(.enabled)
            }

            section("Required content") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(analysis.elements) { result in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: result.matched ? "checkmark.circle.fill" : (result.element.required ? "xmark.circle.fill" : "minus.circle"))
                                .foregroundStyle(result.matched ? Color.green : (result.element.required ? Color.red : Color.secondary))
                            Text(result.element.label)
                                .foregroundStyle(result.matched || result.element.required ? Color.primary : Color.secondary)
                            if !result.element.required {
                                Text("optional").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !analysis.findings.isEmpty {
                section("Phraseology") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(analysis.findings) { finding in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: finding.severity.symbol)
                                    .foregroundStyle(finding.severity.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.title).font(.callout.weight(.semibold))
                                    Text(finding.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }

            if let model {
                section("Example") {
                    Text(model)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
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

struct ScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Color.forScore(score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .frame(width: 70, height: 70)
    }
}

struct WaitingTips: View {
    let step: Step?
    @State private var showExpected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CAP 413 reminders").font(.headline)
            tip("Think, press, talk", "Plan the whole call before pressing the transmit key, and don't clip the first word.")
            tip("Initial calls", "Station you're calling, your full callsign, then the message.")
            tip("Readbacks", "Read back clearances, runway, pressure settings, squawks, frequencies and levels, then finish with your callsign.")
            tip("Abbreviating", "Only shorten your callsign (G-CD) after ATC has done so.")
            tip("Numbers", "Say digits individually: \"QNH one zero one three\". Altitudes in thousands and hundreds: \"two thousand four hundred feet\".")

            if let step, step.task != nil {
                Divider()
                DisclosureGroup("What will be checked", isExpanded: $showExpected) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(step.elements) { element in
                            Text("• " + element.label + (element.required ? "" : " (optional)"))
                                .font(.callout)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func tip(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.semibold))
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DebriefView: View {
    @ObservedObject var session: TrainingSession
    let onRestart: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    ScoreRing(score: session.averageScore ?? 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debrief").font(.largeTitle.weight(.semibold))
                        Text("\(session.results.count) of \(session.script.pilotStepCount) calls assessed · average \(session.averageScore ?? 0)%")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(Array(session.script.steps.enumerated()), id: \.offset) { index, step in
                    if let task = step.task {
                        debriefRow(index: index, task: task, step: step)
                    }
                }

                Button {
                    onRestart()
                } label: {
                    Label("Fly it again (new callsign and weather)", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debriefRow(index: Int, task: String, step: Step) -> some View {
        let analysis = session.results[index]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let analysis {
                    ScoreBadge(score: analysis.score)
                } else {
                    Text("skipped").font(.caption2).foregroundStyle(.secondary)
                }
                Text(task).font(.callout.weight(.medium))
            }
            if let analysis {
                Text("You: \(analysis.transcript.isEmpty ? "(nothing heard)" : analysis.transcript)")
                    .font(.callout)
                let issues = analysis.missingRequired.map { "Missing: \($0.label)" } + analysis.findings.filter { $0.severity > .info }.map(\.title)
                if !issues.isEmpty {
                    Text(issues.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let model = step.model {
                Text("Example: \(model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
