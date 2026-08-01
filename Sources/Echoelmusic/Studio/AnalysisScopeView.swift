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

    /// Samples drawn across the width. 512 at 48 kHz is ~10.7 ms — ONE cycle of a 94 Hz
    /// bass note, a few dozen of a lead. (The first version of this line said "two cycles
    /// of a low bass note", which would put the fundamental at 187 Hz — an F♯3, not a bass
    /// note. Corrected rather than deleted because the window length is picked FROM this
    /// reasoning, so the next person to change 512 needs the arithmetic to be right.)
    /// Wide enough to show the waveform's shape, short enough that the trigger has room to
    /// search inside the 2048-sample capture.
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
            // battery in a panel the performer leaves open.
            //
            // REDUCE MOTION freezes it (WCAG / the repo's motion law). Say what that
            // actually means, because the first version of this comment claimed the frozen
            // version "still shows the waveform, just not its evolution" and that is only
            // half true: `paused: true` stops the schedule, so the Canvas draws whenever
            // SwiftUI next lays it out and then never again. What you get is ONE frame from
            // an arbitrary instant — if the panel opened during silence it stays an empty
            // axis until something else invalidates the view. That is an honest still, not
            // a live-but-slow trace, and the caption below the picture is what carries the
            // information in that mode.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { _ in
                Canvas { ctx, size in draw(ctx, size) }
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .frame(height: traceHeight)
            // The PICTURE is one accessibility element; the NUMBER is its own. The first
            // version put `.accessibilityElement(children: .combine)` on the whole VStack,
            // which folds the children into one element and DISCARDS their labels — so a
            // VoiceOver user heard "Oscilloscope" and never the peak value, i.e. exactly
            // the science-first number the sighted layout puts front and centre. A picture
            // a screen reader cannot read is the one element that legitimately wants a
            // summary label; the readout beside it never did.
            .accessibilityElement()
            .accessibilityLabel("Oscilloscope")
            .accessibilityHint("The master output waveform, triggered so a steady tone stands still.")
            // SCIENCE-FIRST: the number before the picture (Uncodixfy).
            ScopePeakLabel()
        }
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
        // here, none). Colour is the theme's TEXT colour — not an accent, which is what this
        // comment used to say while the code below said `EchoelTheme.text`. A trace drawn in
        // the same ink as the labels around it belongs to the app rather than announcing
        // itself as an instrument panel; an accent would do the opposite.
        ctx.stroke(trace, with: .color(EchoelTheme.text),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

/// The peak readout, split into its OWN leaf on purpose: it reads a value the meter timer
/// updates at 60 Hz. Left inside `AnalysisScopeView.body` it would be harmless today (that
/// body already redraws at 30 fps) — but the moment someone reuses this label elsewhere,
/// the read travels with it. Keeping the observation boundary at the value, not at its
/// current host, is what the 10.76.50 lesson actually asks for. (The trace is capped at
/// 30 fps for battery; this leaf genuinely rebuilds at 60. That is a stated decision, not
/// an oversight: it is one `Text`, and throttling it would mean sampling a peak with a
/// duty cycle — a peak meter that only looks part of the time is not a peak meter.)
///
/// ⛔ WHAT THIS READ USED TO BE, and why it was the very defect the file above says it
/// exists to avoid. The first version rendered
/// `20·log10(max(masterLevel, masterLevelR))` as "Peak … dBFS". `masterLevel` is
/// `vDSP_rmsqv(…) × 3.0` hard-clamped to 1.0 (`AudioEngine.swift`), measured on
/// `masterMixer` BEFORE the master chain. Three separate errors compounded:
///   · it is an RMS, not a peak — for a sine, 3 dB low before anything else;
///   · the ×3 is a contract with `AutoMixChain.updateLUFS`, not a display scale, so the
///     number is ~9.5 dB HIGH;
///   · the clamp to 1.0 means everything above ≈ −6.5 dBFS renders as "0.0 dBFS" — a
///     readout that pins at zero while the mix gets louder.
/// At a real −20 dBFS peak it read −13.5. And the comment beside it claimed comparability
/// with the Master panel, which shows dBTP from a POST-chain, trim-corrected value. That is
/// #164/#227, the lying-control class, inside a commit whose whole thesis was "not a lying
/// control" — which is the useful lesson: the claim in a header does not audit the code
/// under it.
///
/// The value now is `masterOutputTruePeakDb` — the meter's own decaying true-peak hold,
/// measured on the audio thread over every block at the chain output and carrying
/// `outputTrimDb`. Same measurement point and same unit as the Master panel's "True peak";
/// that one is the session MAX-hold ("did it ever clip"), this one falls back ("how loud
/// right now"). Two different questions, deliberately both answered.
@MainActor
private struct ScopePeakLabel: View {
    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        let db = audioEngine.masterOutputTruePeakDb
        // The same silence convention as `MasterLoudnessGrid.dbText` — a value within 1 dB
        // of the −120 floor is not a measurement, it is the absence of one. That grid draws
        // "—" inside a labelled table; here the label IS the sentence, so it says the word.
        let silent = db <= EchoelMeter.floorDb + 1
        // #267: no user-visible readout formats its own decimals. A German reader who sets
        // a comma everywhere else must not meet a lone "−8.3" here.
        let value = EchoelDecimalText.string(db, decimals: 1)
        return Text(silent ? "Silent" : "Peak \(value) dBTP")
            .font(EchoelTheme.font(11).monospacedDigit())
            .foregroundStyle(EchoelTheme.dim)
            .accessibilityLabel(silent
                                ? "Silent"
                                : "Peak \(value) decibels true peak")
    }
}

/// Reference-type frame state so the capture buffer allocates once instead of per draw.
/// Same shape as `SpectralDonutView`'s `DonutState`, for the same reason.
@MainActor
private final class ScopeState {
    var samples = [Float](repeating: 0, count: 2048)
}
#endif
