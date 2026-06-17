//
//  BreathGuideView.swift
//  Echoelmusic — Studio
//
//  The visible "active half" of the coherence loop: a resonance-breathing guide.
//  An expanding/contracting circle paces slow breathing (~6/min ≈ 0.1 Hz); the
//  live coherence from the bus is shown beside it so the body closes the loop the
//  app measures (HRVCoherence). Drives the pure BreathPacer model from a UI-rate
//  loop (no audio-clock coupling). Flash-safe by construction: the only motion is
//  the breath circle at ≤0.2 Hz — far under the 3 Hz WCAG limit — and it is
//  disabled entirely under Reduce Motion (textual guidance instead).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BreathGuideView: View {

    @Environment(BreathPacer.self) private var pacer
    @Environment(EngineBus.self) private var bus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                header
                Spacer(minLength: 8)
                breathCircle
                Text(pacer.instruction)
                    .font(EchoelTheme.font(22, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .accessibilityLabel(pacer.instruction)
                coherenceReadout
                Spacer(minLength: 8)
                rateControl
                startStop
                contraindications
            }
            .padding(20)
        }
        .task(id: pacer.isRunning) { await driveTicks() }
        .onDisappear { pacer.stop() }
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
            Text("Resonance Breathing")
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
        let scale = reduceMotion ? 0.75 : (0.45 + 0.55 * pacer.guidance)
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
                Text("\(Int((pacer.guidance * 100).rounded()))%")
                    .font(EchoelTheme.font(26, .bold))
                    .foregroundStyle(EchoelTheme.text)
            }
        }
        .frame(height: 250)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: pacer.guidance)
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

    // MARK: Pace control

    private var rateControl: some View {
        HStack(spacing: 16) {
            rateButton("minus") { pacer.targetRate -= 0.5 }
            VStack(spacing: 2) {
                Text(String(format: "%.1f", pacer.targetRate))
                    .font(EchoelTheme.font(18, .bold))
                    .foregroundStyle(EchoelTheme.text)
                Text("breaths/min")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
            }
            .frame(minWidth: 96)
            rateButton("plus") { pacer.targetRate += 0.5 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pace \(String(format: "%.1f", pacer.targetRate)) breaths per minute")
    }

    private func rateButton(_ systemName: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(EchoelTheme.text)
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    // MARK: Start / Stop

    private var startStop: some View {
        Button {
            if pacer.isRunning {
                pacer.stop()
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

    // MARK: Safety copy (shown before / during the session)

    private var contraindications: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(BreathPacer.contraindications, id: \.self) { line in
                Text("• " + line)
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
