//
//  MeditationView.swift
//  Echoelmusic — Studio (DMMW pillar: "zentrierte Meditation")
//
//  A centered meditation session built entirely from Echoel's existing, tested
//  bio core: it paces resonance breathing (BreathPacer, ~6/min exhale-emphasis,
//  the Grade-A HRV technique), shows live coherence (HRVCoherence on the bus),
//  runs a chosen duration, and RECORDS the session (SessionRecorder — averages +
//  peak coherence) so progress accrues across days. On completion it shows a
//  summary; recent sessions are listed for a sense of practice over time.
//
//  Science-first, not wellness fluff: the number (coherence) leads, the breath
//  circle supports. Flash-safe by construction (only the breath circle moves, at
//  ≤0.2 Hz, frozen under Reduce Motion). No audio-thread coupling — a UI-rate loop
//  drives the pure pacer; the recorder samples the bus snapshot at 1 Hz.
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct MeditationView: View {

    @Environment(BreathPacer.self) private var pacer
    @Environment(EngineBus.self) private var bus
    @Environment(SessionRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable { case setup, running, summary }
    @State private var phase: Phase = .setup
    @State private var minutes: Int = 10
    @State private var endDate: Date = .now
    @State private var remaining: Int = 0
    @State private var lastSummary: BioSessionSummary?
    @State private var acknowledgedHolds = false
    @State private var showHoldWarning = false

    private static let durations = [5, 10, 15, 20]

    var body: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                header
                switch phase {
                case .setup:   setupBody
                case .running: runningBody
                case .summary: summaryBody
                }
            }
            .padding(20)
        }
        .task(id: phase) { await drive() }
        .onDisappear { if phase == .running { endSession() } }
        .sheet(isPresented: $showHoldWarning) { holdWarningSheet }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Coherence Session").font(EchoelTheme.font(16, .semibold)).foregroundStyle(EchoelTheme.text)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(EchoelTheme.dim)
            }
            .accessibilityLabel("Close coherence session")
        }
    }

    // MARK: Setup

    private var setupBody: some View {
        VStack(spacing: 18) {
            Text("Breathe with the circle. Your coherence is measured live.")
                .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Duration").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                Picker("Duration", selection: $minutes) {
                    ForEach(Self.durations, id: \.self) { Text("\($0) min").tag($0) }
                }.pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Breathing").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                Picker("Breathing pattern", selection: patternSelection) {
                    ForEach(BreathPattern.curated) { Text($0.name).tag($0.id) }
                }.pickerStyle(.segmented)
                Text(pacer.pattern.evidence).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                // Same honesty line as the guide: two of the four curated patterns are paced
                // outside `RespirationEstimator.reportableRange`, so the live breath readout
                // cannot follow them. Derived from the arithmetic, never hand-written (#435).
                if let note = pacer.pattern.measurementNote {
                    Text(note).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            primaryButton("Begin") { beginPressed() }

            if !recorder.sessions.isEmpty {
                streakBanner
                historyList
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Running

    private var runningBody: some View {
        VStack(spacing: 16) {
            Text(timeString(remaining))
                .font(EchoelTheme.font(40, .bold)).foregroundStyle(EchoelTheme.text)
                .monospacedDigit()
                .accessibilityLabel("\(remaining / 60) minutes \(remaining % 60) seconds remaining")
            Spacer(minLength: 4)
            breathCircle
            Text(pacer.instruction).font(EchoelTheme.font(22, .semibold)).foregroundStyle(EchoelTheme.text)
            coherenceReadout
            Spacer(minLength: 4)
            Button { endSession() } label: {
                Text("End").font(EchoelTheme.font(16, .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
        }
    }

    // MARK: Summary

    private var summaryBody: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44))
                .foregroundStyle(EchoelTheme.accent)
            Text("Session complete").font(EchoelTheme.font(20, .semibold)).foregroundStyle(EchoelTheme.text)
            let streak = SessionStats.streakDays(recorder.sessions)
            if streak > 1 {
                Label("\(streak)-day streak", systemImage: "flame.fill")
                    .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.accent)
            }
            if let s = lastSummary, s.sampleCount > 0 {
                VStack(spacing: 10) {
                    statRow("Duration", timeString(s.durationSeconds))
                    statRow("Avg coherence", EchoelDecimalText.string(s.avgCoherence, decimals: 2))
                    statRow("Peak coherence", EchoelDecimalText.string(s.peakCoherence, decimals: 2))
                    if s.avgHeartRate > 0 { statRow("Avg heart rate", "\(Int(s.avgHeartRate.rounded())) bpm") }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            } else {
                Text("No live bio was recorded. Start the camera (cover the rear lens) or a heart-rate strap to track coherence next time.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            primaryButton("Again") { phase = .setup }
            Button { dismiss() } label: {
                Text("Done").font(EchoelTheme.font(15)).foregroundStyle(EchoelTheme.dim)
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
        }
    }

    // MARK: Streak + trend (habit reward, pure SessionStats)

    private var streakBanner: some View {
        let streak = SessionStats.streakDays(recorder.sessions)
        let trend = SessionStats.coherenceTrend(recorder.sessions)
        return HStack(spacing: 12) {
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame.fill")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.accent)
            } else {
                Text("Practice daily to build a streak")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            }
            Spacer()
            if abs(trend) >= 0.01 {
                let up = trend > 0
                // `%+.2f` had no direct equivalent: `EchoelDecimalText` deliberately does not
                // own the sign (see its header — a localized minus renders and then fails to
                // parse, so signs stay the caller's business). The "+" is added here and only
                // for the positive branch; a negative number already carries its own "-".
                Label("\(up ? "+" : "")\(EchoelDecimalText.string(trend, decimals: 2)) coherence",
                      systemImage: up ? "arrow.up.right" : "arrow.down.right")
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(up ? EchoelTheme.accent : EchoelTheme.dim)
                    .accessibilityLabel("coherence trend \(up ? "up" : "down") "
                                        + EchoelDecimalText.string(abs(trend), decimals: 2))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
    }

    // MARK: History

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent sessions").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
            ForEach(recorder.sessions.prefix(5)) { s in
                HStack {
                    Text(s.date, format: .dateTime.month().day().hour().minute())
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    Spacer()
                    Text(timeString(s.durationSeconds)).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    Text(verbatim: "coh " + EchoelDecimalText.string(s.avgCoherence, decimals: 2))
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.accent)
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
        }
    }

    // MARK: Pieces reused from the breathing guide

    private var breathCircle: some View {
        let scale = reduceMotion ? 0.75 : (0.45 + 0.55 * pacer.guidance)
        return ZStack {
            Circle().strokeBorder(EchoelTheme.border, lineWidth: 1).frame(width: 240, height: 240)
            Circle().fill(EchoelTheme.accent.opacity(0.18))
                .overlay(Circle().strokeBorder(EchoelTheme.accent, lineWidth: 2))
                .frame(width: 220, height: 220).scaleEffect(scale)
        }
        .frame(height: 250)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: pacer.guidance)
        .accessibilityHidden(true)
    }

    private var coherenceReadout: some View {
        let c = bus.freshBio()?.coherence ?? 0
        return Text(verbatim: c > 0
                    ? "Coherence " + EchoelDecimalText.string(c, decimals: 2)
                    : "Coherence —")
            .font(EchoelTheme.font(15, .semibold))
            .foregroundStyle(c > 0 ? EchoelTheme.accent : EchoelTheme.dim)
    }

    private var patternSelection: Binding<String> {
        Binding(get: { pacer.pattern.id },
                set: { id in if let p = BreathPattern.curated.first(where: { $0.id == id }) { pacer.pattern = p } })
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
            Spacer()
            Text(value).font(EchoelTheme.font(15, .semibold)).foregroundStyle(EchoelTheme.text)
        }
    }

    private func primaryButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EchoelTheme.font(16, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
        }
    }

    // MARK: Session lifecycle

    private func beginPressed() {
        if pacer.pattern.hasHolds && !acknowledgedHolds { showHoldWarning = true; return }
        startSession()
    }

    private func startSession() {
        pacer.reset(); pacer.start()
        recorder.start(subscribing: bus)
        remaining = minutes * 60
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        phase = .running
    }

    private func endSession() {
        guard phase == .running else { return }
        pacer.stop()
        let name = "Coherence \(minutes) min"
        lastSummary = recorder.stop(name: name)
        phase = .summary
    }

    // One UI-rate loop while running: paces the breath AND counts down (derived from
    // endDate so it stays correct even if a tick is missed). Ends at zero.
    private func drive() async {
        guard phase == .running else { return }
        var last = Date()
        while !Task.isCancelled && phase == .running {
            try? await Task.sleep(for: .milliseconds(33))
            let now = Date()
            pacer.tick(now.timeIntervalSince(last))
            last = now
            remaining = max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
            if remaining == 0 { endSession(); break }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Hold-safety acknowledgement (opt-in hold patterns only)

    private var holdWarningSheet: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Before breath-holds").font(EchoelTheme.font(18, .semibold)).foregroundStyle(EchoelTheme.text)
                ForEach(BreathPattern.holdContraindications, id: \.self) { line in
                    Text("• " + line).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                primaryButton("I understand — start") {
                    acknowledgedHolds = true; showHoldWarning = false; startSession()
                }
                Button { showHoldWarning = false } label: {
                    Text("Cancel").font(EchoelTheme.font(15)).foregroundStyle(EchoelTheme.dim)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
            }
            .padding(20)
        }
    }
}
#endif
