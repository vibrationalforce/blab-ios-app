#if canImport(SwiftUI)
import SwiftUI

// AnalysisWavefrontView.swift
// Echoel — #385. Sound as it actually leaves a source: wavefronts spreading in every direction.
//
// ⭐ FOUNDER ASK, 2026-08-02, with the oscilloscope and the Poincaré plot struck out in red:
// *"Gibt es noch eine Möglichkeit das es mehr physikalisch korrekt wie die Schwingung aussieht?
// Schallwellen breiten sich ja in alle Richtungen gleichmäßig aus. Mache davon eine angepasste
// adaptive Version."* The two struck views are lab conventions — a voltage against time, a
// statistic over heartbeat intervals. Correct, and neither looks like anything that happens in a
// room. This one does: a moment of the music leaves the centre as a ring, expands uniformly, and
// gets weaker as it goes because the same energy spreads over a growing circumference.
//
// WHAT EACH DIMENSION MEANS — all three carry data, none is decoration:
//   · RADIUS = age. Under a constant propagation speed that is exactly proportional to distance,
//     so the geometry is honest without this file inventing a room size it cannot know.
//   · COLOUR = the spectral CENTROID of the moment that ring was emitted, through
//     `SpectralColor.visibleColor` — the same frequency→visible-light transform the Field's own
//     colour and the spectrum meter use. A bass moment leaves a red ring, a bright one violet, and
//     you watch the phrase you just played travel outward as a band of colour.
//   · AMPLITUDE = the loudness of that moment, decayed by `WavefrontField.spreadingAmplitude`.
// The physics, its three honest limits (age not metres · envelope fronts not pressure cycles ·
// a dilated clock) and the 1/r-versus-1/r² question are all argued in `WavefrontField`.
//
// ⚠️ NO PRINTED NUMBER ON THIS VIEW, deliberately — but the SPOKEN label carries the live
// measurement, and the first version of this file got that second half wrong. It argued "no
// number at all" because the spectrum meter two rows down already names the loudest partial of
// the same output, and a second printed readout would be a second address for one fact. That
// argument holds for a SIGHTED reader, who gets frequency from the ring colour and loudness from
// its brightness. For a VoiceOver user the picture contributes nothing whatsoever, so a fixed
// label ("Wavefront field") leaves the view empty of content — exactly the class of defect
// `AnalysisViewsSpeakTheirNumbersTests` was written for, and it caught this one on arrival.
// The label is therefore COMPUTED from the live state; the panel stays free of a duplicate
// printed number. (The centroid is also not the spectrum readout's fact: that names the LOUDEST
// partial, this is the centre of mass of the whole spectrum — see `WavefrontField.centroidHz`.)
//
// ⚠️ FLASH SAFETY IS THE REAL RISK IN THIS VIEW, more than in any sibling: a pulsing radial
// field is the textbook seizure trigger. Two things bound it. (1) The whole field's brightness
// is slew-limited as a per-SECOND velocity via `FlashGuard`, never as a per-frame step — a
// per-tick cap lets a faster frame rate sneak extra edges through, which is the defect #370/#372
// closed for the lighting senders. (2) `WavefrontField.advanced` caps `dt` at one second, so a
// stall cannot teleport every ring to the edge in one frame. Reduce Motion freezes the picture
// outright; the last frame stays a legible diagram, which is why the rings fade rather than blink.
//
// LEAF BY CONSTRUCTION (the 10.76.50 freeze law). The `TimelineView`, the `Canvas` and every
// read of `audioEngine` live in THIS struct's body. Never inline it into `signalSection` or any
// ancestor — that would register the whole Studio, and every open `.menu` Picker in it, as a
// 20 Hz observer.
//
// ⚠️ NOT AUDIO-THREAD CODE, said plainly because the arrays below churn once per frame and a
// later reader may reach for a ring buffer out of habit. This runs on the MAIN thread at 20 fps,
// the same place `AnalysisSpectrumView` runs its FFT; the no-allocation law applies to render
// blocks and DSP kernels, not here. Optimising it would trade readability for nothing.

@MainActor
struct AnalysisWavefrontView: View {

    @Environment(AudioEngine.self) private var audioEngine
    var reduceMotion: Bool = false

    /// Grows with Dynamic Type instead of sitting at a fixed height (#292 — a fixed frame is
    /// ecosystem debt, and this view is meant to survive the move to larger surfaces, where a
    /// radial picture is the one that gains most from the room).
    @ScaledMetric(relativeTo: .caption) private var fieldHeight: CGFloat = 150

    @State private var state = WavefrontState()

    var body: some View {
        // 20 fps, matching the spectrum meter. The rings move continuously rather than in steps,
        // so a faster redraw changes no pixel a human can see and costs battery in a panel a
        // performer leaves open. Reduce Motion freezes it (WCAG / the repo's motion law).
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in draw(ctx, size, at: timeline.date) }
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                // ⚠️ CLIP BEFORE THE BORDER, and the order is load-bearing. The rings are drawn
                // out to half the diagonal, so without a clip they escape the card and paint over
                // the caption below. With the clip applied AFTER the overlay, it would also eat
                // the outer half of the 1 pt border and the card would read a hairline thinner
                // than every sibling in the panel.
                .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
                // ONE element with a real description. `.accessibilityElement()` — never
                // `.combine`, which discards child labels and is the mistake #352 had to undo one
                // file over. A `Canvas` has nothing readable in it, so the label has to carry the
                // measurement itself.
                //
                // ⚠️ INSIDE THE TimelineView CLOSURE ON PURPOSE. Applied outside it, the label
                // would be built once and then never again — a fixed string wearing a function
                // call, which is the shape a source scan cannot tell from an honest one. In here
                // the closure re-evaluates on every tick, so the sentence follows the picture.
                .accessibilityElement()
                .accessibilityLabel(spokenState())
                .accessibilityHint("""
                    Each ring is a moment of the sound spreading outward, fading as it goes, \
                    tinted by the colour that its frequency becomes in visible light.
                    """)
        }
        .frame(height: fieldHeight)
    }

    /// What VoiceOver says about the picture — the live quantity a sighted reader takes from the
    /// colour and the brightness.
    ///
    /// Built from the PREVIOUS frame's measurement: this closure evaluates before `Canvas` draws,
    /// so `state` still holds the values written one tick ago. At 20 fps that is 50 ms, far below
    /// anything a reader can notice, and it is stated rather than hidden because the alternative —
    /// writing SwiftUI state from inside the draw closure — is a modify-during-update hazard.
    private func spokenState() -> String {
        let rings = state.fronts.count
        guard rings > 0 else {
            // Plain words, no dashes or symbols: VoiceOver reads punctuation glyphs aloud, which
            // is the lesson `AnalysisSpectrumView`'s spoken form had to learn the hard way.
            return "Wavefront field. Silent. Nothing is sounding, so no wave is leaving the centre."
        }
        let subject = rings == 1 ? "One wavefront is" : "\(rings) wavefronts are"
        guard let hz = state.lastCentroidHz, hz.isFinite, hz > 0 else {
            return "Wavefront field. \(subject) spreading outward."
        }
        // Whole hertz, and an `Int` interpolation on purpose: a formatter would insert the
        // locale's grouping separator into a spoken number (#267's territory), and a decimal
        // place here would change several times a second without telling anyone anything.
        let hertz = Int(hz.rounded())
        return "Wavefront field. \(subject) spreading outward, the newest centred near \(hertz) hertz."
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, at date: Date) {
        guard size.width > 1, size.height > 1 else { return }
        let dt = state.tick(at: date)

        // --- What is sounding right now: how loud, and what colour ---
        audioEngine.copyLatestOutputSamples(into: &state.samples, count: WavefrontState.fftSize)
        let level = Swift.min(1.0, Double(rms(state.samples)) * 4.0)   // RMS ~0.25 → full
        let (magnitudes, _) = state.fft.forward(state.samples)
        let centroid = WavefrontField.centroidHz(magnitudes: magnitudes,
                                                 sampleRate: audioEngine.sampleRate)
        // Kept for the spoken label only. Held rather than cleared on a silent frame: rings
        // already in flight still carry the colour of the moment that emitted them, so a label
        // that dropped the frequency the instant the input went quiet would contradict what is
        // still on screen.
        if let centroid { state.lastCentroidHz = centroid }

        // --- Advance every front, retire the ones that have left ---
        state.advanceAll(dt: dt)

        // --- Emit at a RATE, not once per frame (see `WavefrontField.emitRateHz`) ---
        state.emit(dt: dt, level: level, centroidHz: centroid)

        // --- Flash safety on the aggregate brightness, as a per-second velocity ---
        //
        // The rate is `FlashGuard.senderLuminancePerSecond`, reused rather than invented. It is
        // the repo's ONE established flash-safe luminance velocity (≈2.4/s, so a full 0→1 swing
        // takes ~0.4 s — about 1.2 Hz for a square wave, comfortably under the 3 Hz WCAG bound).
        // Picking a second number here would be two facts for one safety property, which is the
        // shape of defect this file's siblings keep having to correct.
        state.fieldGain = FlashGuard.limitedLuminance(
            from: state.fieldGain, to: level,
            maxDelta: FlashGuard.maxDelta(perSecond: FlashGuard.senderLuminancePerSecond, dt: dt))

        // --- Draw ---
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        // Half the DIAGONAL, so a front at r = 1 has just cleared the corners. Half the width
        // would make rings vanish at the edge midpoints while still visible in the corners — a
        // wave that stops at a frame, which is the one thing this picture must not show.
        let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
        let maxRadius: CGFloat = diagonal * 0.5
        let gain = Swift.max(0, Swift.min(1, state.fieldGain))

        for front in state.fronts {
            let a = WavefrontField.spreadingAmplitude(emitted: front.level, atRadius: front.radius)
            let opacity = Swift.max(0, Swift.min(1, a * gain))
            guard opacity > 0.01 else { continue }
            // Every geometry value is CGFloat from here on: mixing a `Double` radius into a
            // `CGRect` initialiser next to a `CGPoint` is a compile error, and there is no local
            // compiler in this environment to catch it — so the conversion happens once, here.
            let radius = CGFloat(front.radius) * maxRadius
            guard radius.isFinite, radius > 0.5 else { continue }
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            // Hoisted out of the call: arithmetic inside an argument list is what made an
            // expression too expensive to type-check and took the blocking gate down in #287.
            let width = CGFloat(0.8 + 2.0 * a)
            let rgb = front.rgb
            let colour = Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
            ctx.stroke(Path(ellipseIn: rect), with: .color(colour), lineWidth: width)
        }
    }

    /// Root-mean-square of the window, NaN-safe. A non-finite sample must scale the picture to
    /// nothing, never to `nan` — a `nan` opacity makes `Canvas` skip the ring, which reads as a
    /// rendering bug rather than as a bad audio frame.
    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        var counted = 0
        for s in samples where s.isFinite {
            sum += Double(s) * Double(s)
            counted += 1
        }
        guard counted > 0 else { return 0 }
        return Float((sum / Double(counted)).squareRoot())
    }
}

/// The fronts in flight, the reusable FFT, and the frame clock.
///
/// Its own buffer, not `AnalysisSpectrumView`'s: that file already records why two separate
/// leaves must not share one mutable buffer — it would couple their clocks. This is the fourth
/// FFT of the same ring in the app (spectrum bars, spectrum readout, header strip, this), and
/// that count is stated rather than hidden, because it is what a later reader deserves to know
/// before adding a fifth.
@MainActor
private final class WavefrontState {
    static let fftSize = 1024                              // matches the tap buffer size

    struct Front {
        var radius: Double                                 // normalised 0…1
        let level: Double                                  // amplitude at emission
        let rgb: LinearRGB
    }

    let fft = EchoelRealFFT(size: WavefrontState.fftSize)
    var samples = [Float](repeating: 0, count: WavefrontState.fftSize)
    var fronts: [Front] = []
    var fieldGain: Double = 0
    /// The last spectral centroid that was measurable, for the spoken label. `nil` until the
    /// first sounding frame — never a fabricated number, for the same reason `centroidHz`
    /// returns `nil` in silence rather than 0 Hz.
    var lastCentroidHz: Double?

    private var emitAccumulator: Double = 0
    private var lastDate: Date?

    /// Seconds since the previous frame. Measured, never assumed — the #315/#332/#337 law. The
    /// first frame reports 1/20 s rather than zero so nothing divides by an empty interval.
    func tick(at date: Date) -> Double {
        defer { lastDate = date }
        guard let last = lastDate else { return 1.0 / 20.0 }
        let dt = date.timeIntervalSince(last)
        return (dt.isFinite && dt > 0) ? dt : 1.0 / 20.0
    }

    func advanceAll(dt: Double) {
        for i in fronts.indices {
            fronts[i].radius = WavefrontField.advanced(radius: fronts[i].radius, dt: dt)
        }
        fronts.removeAll { $0.radius >= 1 || !$0.radius.isFinite }
    }

    /// Emits fronts at `WavefrontField.emitRateHz`, carrying over the fractional remainder so the
    /// long-run rate is exact regardless of how the frames fall.
    ///
    /// ⚠️ AFTER A STALL, RINGS ARE DROPPED — NOT STACKED, and not carried over either. Two
    /// separate caps do that, and both are deliberate:
    ///   · `dt` is capped at one second here, the same cap `WavefrontField.advanced` applies, so
    ///     the two halves of one frame cannot disagree about how much time passed.
    ///   · the accumulator is then fully consumed (`-= due`) while at most FOUR rings are
    ///     actually created. A one-second gap would otherwise put twelve rings at radius zero in
    ///     a single frame — a bright stack at the centre, which is exactly the luminance edge the
    ///     flash bound exists to prevent, and a debt the next frames would keep paying off.
    /// Losing a few rings after a stall is invisible; a flash is not.
    ///
    /// The accumulator is also guarded against non-finite drift before `Int(...)` sees it:
    /// `Int(Double.nan)` traps, and a trap in a view that redraws twenty times a second is a
    /// crash, not a glitch. Nothing above can produce one today — that is the point of a guard.
    func emit(dt: Double, level: Double, centroidHz: Double?) {
        let safeDt = (dt.isFinite && dt > 0) ? Swift.min(dt, 1.0) : 0.05
        emitAccumulator += safeDt * WavefrontField.emitRateHz
        guard emitAccumulator.isFinite else { emitAccumulator = 0; return }
        let due = Int(emitAccumulator)
        guard due > 0 else { return }
        emitAccumulator -= Double(due)

        let usableLevel = level.isFinite ? Swift.max(0, Swift.min(1, level)) : 0
        // Silence emits nothing. A ring with no sound in it would still be a ring — a wave from
        // a source that did not sound, which is the picture claiming something untrue.
        guard usableLevel > 0.005, let hz = centroidHz else { return }
        let rgb = SpectralColor.visibleColor(forFrequency: hz)

        for _ in 0..<Swift.min(due, 4) {
            fronts.append(Front(radius: 0, level: usableLevel, rgb: rgb))
        }
        if fronts.count > WavefrontField.maxFronts {
            fronts.removeFirst(fronts.count - WavefrontField.maxFronts)
        }
    }
}
#endif
