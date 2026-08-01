#if canImport(SwiftUI)
import SwiftUI

// AnalysisScopeView.swift
// Echoel — #347 Slice 1. A REAL oscilloscope of the master output (founder 2026-08-01:
// "Diesen Bereich nochmal erweitern durch osciloscope, fft, spectrum, stereobild").
//
// ⭐ WHAT MAKES IT REAL, stated up front because the app already contains something that
// LOOKS like this and is not: the Metal shader has a "Scope" field (style index 8) and a
// "Lissajous" (6), both retired from the UI by founder curation on 2026-07-08. Their
// signatures are `fieldScope(p, toneHz, phase, coh)` — the NOTE frequency and bio, never
// audio. `MetalBioView` is handed no samples at all. Those are drawn figures. THIS reads
// `AudioEngine.copyLatestOutputSamples`, the lock-free ring the audio tap memcpy's the live
// mix into, so what you see is what is heard. Re-labelling the shader look as an
// oscilloscope would have been a lying control — the #164/#227 class this repo keeps paying
// for — and it is the reason this is a new Canvas view rather than one line in `LookBlendMap`.
//
// LEAF BY CONSTRUCTION (the 10.76.50 freeze law). The `TimelineView` and every read of
// `audioEngine` live in THIS struct's body, so only this view redraws at frame rate. It must
// never be inlined into `visualPanel`'s body or into any ancestor — that would register the
// whole Studio (and with it every open `.menu` Picker) as a 30 Hz observer.
//
// NO DSP ON THE AUDIO THREAD: the ring is copied on the main thread by design
// (`copyLatestOutputSamples` says so in its own doc), and the triggering is pure value maths
// in `ScopeTrigger`. Nothing here touches the render block.

@MainActor
struct AnalysisScopeView: View {

    @Environment(AudioEngine.self) private var audioEngine
    var reduceMotion: Bool = false

    /// Samples drawn across the width. 512 at 48 kHz is ~10.7 ms — two cycles of a low
    /// bass note, a few dozen of a lead. Wide enough to show the waveform's shape, short
    /// enough that the trigger has room to search inside the 2048-sample capture.
    private static let windowLength = 512
    private static let captureLength = 2048

    /// Grows with Dynamic Type rather than sitting at a fixed 88 pt — a trace that stays
    /// the same height while its caption doubles is the "Ökosystem-Schuld" the platform
    /// note in CLAUDE.md names (#292).
    @ScaledMetric(relativeTo: .caption) private var traceHeight: CGFloat = 88

    @State private var state = ScopeState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 30 fps, not 60: the trace is phase-locked, so it does not move between frames
            // the way an untriggered one would — the extra 30 redraws buy nothing and cost
            // battery in a panel the performer leaves open. Reduce Motion freezes it to a
            // still frame (WCAG / the repo's motion law); a locked scope is already almost
            // still, so the frozen version still shows the waveform, just not its evolution.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { _ in
                Canvas { ctx, size in draw(ctx, size) }
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .frame(height: traceHeight)
            // SCIENCE-FIRST: the number before the picture (Uncodixfy). Peak is stated in
            // dBFS because that is the unit the Master panel already uses, so the two
            // surfaces can be compared without conversion in the reader's head.
            ScopePeakLabel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Oscilloscope")
        .accessibilityHint("The master output waveform, triggered so a steady tone stands still.")
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        audioEngine.copyLatestOutputSamples(into: &state.samples, count: Self.captureLength)
        let start = ScopeTrigger.startIndex(in: state.samples, windowLength: Self.windowLength)
        let w = ScopeTrigger.window(state.samples, start: start, count: Self.windowLength)

        let midY = size.height / 2
        // Zero line first, so an empty trace still reads as "a scope showing nothing"
        // rather than as an empty box.
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: midY))
        axis.addLine(to: CGPoint(x: size.width, y: midY))
        ctx.stroke(axis, with: .color(EchoelTheme.border), lineWidth: 1)

        let peak = ScopeTrigger.peak(w)
        guard peak > 0.0005 else { return }          // true silence draws the axis only

        // 0.92 of the half-height, so a full-scale sample stops just short of the frame and
        // clipping is visible as a FLAT TOP against clear air rather than as a trace welded
        // to the border (where it would be indistinguishable from a drawing artefact).
        let amp = midY * 0.92
        let dx = size.width / CGFloat(max(1, w.count - 1))
        var trace = Path()
        for (i, s) in w.enumerated() {
            let p = CGPoint(x: CGFloat(i) * dx, y: midY - CGFloat(s) * amp)
            if i == 0 { trace.move(to: p) } else { trace.addLine(to: p) }
        }
        // One solid stroke, no glow, no gradient (Uncodixfy: no glow effects, ≤8 pt shadow —
        // here, none). Colour is the theme accent so the trace belongs to the app rather
        // than announcing itself as an instrument panel.
        ctx.stroke(trace, with: .color(EchoelTheme.text),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

/// The peak readout, split into its OWN leaf on purpose: it reads `masterLevel`, which the
/// meter timer updates at 60 Hz. Left inside `AnalysisScopeView.body` it would be harmless
/// today (that body already redraws at 30 fps) — but the moment someone reuses this label
/// elsewhere, the read travels with it. Keeping the observation boundary at the value, not
/// at its current host, is what the 10.76.50 lesson actually asks for.
@MainActor
private struct ScopePeakLabel: View {
    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        let level = Swift.max(audioEngine.masterLevel, audioEngine.masterLevelR)
        // −60 dBFS is the floor the Master panel already parks at when there is no signal;
        // using the same floor keeps the two readouts saying the same thing about silence.
        let db = level > 0.001 ? 20 * log10(level) : -60
        return Text(level > 0.001
                    ? String(format: "Peak %.1f dBFS", db)
                    : "Silent")
            .font(EchoelTheme.font(11).monospacedDigit())
            .foregroundStyle(EchoelTheme.dim)
            .accessibilityLabel(level > 0.001
                                ? String(format: "Peak %.1f decibels full scale", db)
                                : "Silent")
    }
}

/// Reference-type frame state so the capture buffer allocates once instead of per draw.
/// Same shape as `SpectralDonutView`'s `DonutState`, for the same reason.
@MainActor
private final class ScopeState {
    var samples = [Float](repeating: 0, count: 2048)
}
#endif
