//
//  BreathGuideView.swift
//  Echoelmusic — Studio
//
//  The visible "active half" of the coherence loop: a breathing guide. An
//  expanding/contracting circle paces the chosen BreathPattern; live coherence from
//  the bus is shown beside it so the body closes the loop the app measures
//  (HRVCoherence). Resonance (~6/min, no holds) is the default and recommended
//  technique; opt-in hold patterns (Box, 4-7-8) require acknowledging their
//  contraindications first. Drives the pure BreathPacer from a UI-rate loop (no
//  audio-clock coupling). Flash-safe by construction: the only motion is the breath
//  circle at ≤0.2 Hz — far under the 3 Hz WCAG limit — and it is disabled entirely
//  under Reduce Motion (textual guidance instead).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BreathGuideView: View {

    @Environment(BreathPacer.self) private var pacer
    @Environment(EngineBus.self) private var bus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Once the user acknowledges the hold-safety card, don't re-prompt this session.
    @State private var acknowledgedHolds = false
    @State private var showHoldWarning = false
    /// True biofeedback: drive the ball from the camera-measured breath, not the pace.
    @State private var followMyBreath = false

    var body: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                header
                Spacer(minLength: 8)
                breathCircle
                Text(followingMeasured ? "Breathe naturally" : pacer.instruction)
                    .font(EchoelTheme.font(22, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .accessibilityLabel(followingMeasured ? "Breathe naturally" : pacer.instruction)
                coherenceReadout
                Spacer(minLength: 8)
                patternControl
                followControl
                startStop
                contraindications
            }
            .padding(20)
        }
        .task(id: pacer.isRunning) { await driveTicks() }
        .onDisappear { pacer.stop() }
        .sheet(isPresented: $showHoldWarning) { holdWarningSheet }
    }

    // MARK: Tick driver (UI-rate; not the audio/pattern clock)

    private func driveTicks() async {
        guard pacer.isRunning else { return }
        var last = Date()
        while !Task.isCancelled && pacer.isRunning {
            try? await Task.sleep(for: .milliseconds(33))
            let now = Date()
            pacer.tick(now.timeIntervalSince(last))
            last = now
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Breathing Guide")
                .font(EchoelTheme.font(16, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(EchoelTheme.dim)
            }
            .accessibilityLabel("Close breathing guide")
        }
    }

    // MARK: Breath circle

    private var breathCircle: some View {
        // 0.45…1.0 of the guide ring; fixed mid-size under Reduce Motion.
        let scale = reduceMotion ? 0.75 : (0.45 + 0.55 * ballAmplitude)
        return ZStack {
            Circle()
                .strokeBorder(EchoelTheme.border, lineWidth: 1)
                .frame(width: 240, height: 240)
            Circle()
                .fill(EchoelTheme.accent.opacity(0.18))
                .overlay(Circle().strokeBorder(EchoelTheme.accent, lineWidth: 2))
                .frame(width: 220, height: 220)
                .scaleEffect(scale)
            if reduceMotion {
                Text("\(Int((ballAmplitude * 100).rounded()))%")
                    .font(EchoelTheme.font(26, .bold))
                    .foregroundStyle(EchoelTheme.text)
            }
        }
        .frame(height: 250)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: ballAmplitude)
        .accessibilityHidden(true)
    }

    // MARK: Live coherence (the measured half of the loop)

    private var coherenceReadout: some View {
        let c = bus.freshBio()?.coherence ?? 0
        return VStack(spacing: 4) {
            Text(c > 0 ? String(format: "Coherence %.2f", c) : "Coherence —")
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(c > 0 ? EchoelTheme.accent : EchoelTheme.dim)
            Text("Breathe with the circle. With a chest strap, watch coherence rise.")
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Pattern picker (resonance default; holds opt-in)

    private var patternControl: some View {
        VStack(spacing: 8) {
            Picker("Breathing pattern", selection: patternSelection) {
                ForEach(BreathPattern.curated) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.segmented)
            .disabled(pacer.isRunning)   // change pattern only while stopped
            HStack(spacing: 6) {
                Text(pacer.pattern.evidence)
                if pacer.pattern.hasHolds {
                    Text("• includes holds")
                        .foregroundStyle(EchoelTheme.accent)
                }
            }
            .font(EchoelTheme.font(11))
            .foregroundStyle(EchoelTheme.dim)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var patternSelection: Binding<String> {
        Binding(
            get: { pacer.pattern.id },
            set: { newID in
                guard let p = BreathPattern.curated.first(where: { $0.id == newID }) else { return }
                pacer.pattern = p
            }
        )
    }

    // MARK: True biofeedback — drive the ball from the measured breath

    /// A fresh camera breath measurement, if the rPPG is running and its respiratory
    /// signal is clear. CameraRPPGBioPublisher only reports breathRate > 0 when the
    /// RSA-derived breath passes its confidence gate, so this doubles as "available".
    private var measuredBreath: BioSampleFrame? {
        guard let f = bus.freshBio(), f.source == .cameraPPG, f.breathRate > 0 else { return nil }
        return f
    }

    /// True when we are actually showing the user's measured breath (toggle on AND a
    /// clear signal present), as opposed to the paced guide.
    private var followingMeasured: Bool { followMyBreath && measuredBreath != nil }

    /// Ball amplitude [0,1]: the MEASURED breath when following, else the paced guide.
    private var ballAmplitude: Double {
        followingMeasured ? Double(measuredBreath?.breathPhase ?? 0.5) : pacer.guidance
    }

    private var followControl: some View {
        VStack(spacing: 4) {
            Toggle(isOn: $followMyBreath) {
                Text("Follow my breath (camera)")
                    .font(EchoelTheme.font(13))
                    .foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            if followMyBreath && measuredBreath == nil {
                Text("Start the camera to measure your breath.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .multilineTextAlignment(.center)
            } else if followingMeasured {
                Text("Following your breath — let it slow and even out.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.accent)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Start / Stop (holds gated behind acknowledgement)

    private var startStop: some View {
        Button {
            if pacer.isRunning {
                pacer.stop()
            } else if pacer.pattern.hasHolds && !acknowledgedHolds {
                showHoldWarning = true       // must acknowledge hold safety first
            } else {
                pacer.reset()
                pacer.start()
            }
        } label: {
            Text(pacer.isRunning ? "Stop" : "Start")
                .font(EchoelTheme.font(16, .semibold))
                .foregroundStyle(pacer.isRunning ? EchoelTheme.text : EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(pacer.isRunning ? EchoelTheme.fill : EchoelTheme.text))
        }
    }

    // MARK: Safety copy (hold patterns show the stricter card)

    private var contraindications: some View {
        let lines = pacer.pattern.hasHolds
            ? BreathPattern.holdContraindications
            : BreathPacer.contraindications
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { line in
                Text("• " + line)
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hold-safety acknowledgement (required before a hold session)

    private var holdWarningSheet: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Before breath-holds")
                    .font(EchoelTheme.font(18, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                ForEach(BreathPattern.holdContraindications, id: \.self) { line in
                    Text("• " + line)
                        .font(EchoelTheme.font(13))
                        .foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    acknowledgedHolds = true
                    showHoldWarning = false
                    pacer.reset()
                    pacer.start()
                } label: {
                    Text("I understand — start")
                        .font(EchoelTheme.font(16, .semibold))
                        .foregroundStyle(EchoelTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(EchoelTheme.text))
                }
                Button { showHoldWarning = false } label: {
                    Text("Cancel")
                        .font(EchoelTheme.font(15))
                        .foregroundStyle(EchoelTheme.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(20)
        }
    }
}
#endif
