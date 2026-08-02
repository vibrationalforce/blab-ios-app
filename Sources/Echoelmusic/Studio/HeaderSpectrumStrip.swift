#if canImport(SwiftUI)
import SwiftUI

// HeaderSpectrumStrip.swift
// Echoel — #384. The colour bars, adapted, at the top-left of the brand header.
//
// ⭐ FOUNDER ASK, 2026-08-02, with the Field panel's spectrum circled in red and an arrow to
// the header: *"Echoelmusic wieder in die Mitte. Die Farbbalken links oben neben Echoelmusic
// in angepasster Form."* So this is the SAME measurement as `AnalysisSpectrumView` — the same
// ring, the same bands, the same frequency→visible-light colours — in the smallest honest form
// that fits a 50 pt chrome bar.
//
// ⭐ AND IT ANSWERS A QUESTION THAT WAS LEFT OPEN ONE DAY EARLIER. On 2026-08-01 the founder
// circled the empty space left of the wordmark and asked *"Was kann hier jetzt noch hin?"*; the
// answer recorded in `WorkspaceView.topBar` was **nothing** — no decorative tile, because the UI
// rules ban exactly that and every status a performer needs already had a home. That reasoning
// still holds and this does not break it: a live spectrum of the master output is not a
// decorative tile, it is the one thing in the header that is neither a control nor a label but a
// MEASUREMENT, which is what the science-first rule asks for. The wordmark moved left to close
// the gap; it moves back to the centre now because the gap has real content.
//
// ⚠️ ADAPTED, not shrunk — the differences from the panel meter are each a decision:
//   · 12 bands, not 24. At ~110 pt of chrome width, 24 bands are 3.5 pt apart and stop being
//     separable; they become texture, which is decoration by another name.
//   · 12 fps, not 20. This runs whenever the app is on screen, not only while a panel is open.
//     The bars are eased over ~120 ms anyway, so the slower clock costs no visible smoothness.
//   · No box, no border, no fill. The header is already a surface; a bordered card inside it is
//     the banned panel-in-panel. The bars sit directly on the bar.
//   · No peak readout. The number belongs to the instrument in the Field panel, where there is
//     room to read it; repeating it here would be a second address for one fact.
//
// LEAF BY CONSTRUCTION, and this is the highest-stakes instance of that law in the app. The
// 10.76.50 freeze was caused by exactly this shape — a live read that had leaked into
// `WorkspaceView.topBar` — and it tore down every open `.menu` Picker in the surface below,
// once per frame. This view reads `audioEngine` in ITS OWN body and nowhere else, so only this
// 18 pt strip redraws. It must NEVER be inlined into `topBar`, and no value it computes may be
// passed down from there.
//
// REDUCE MOTION freezes the picture (the repo's motion law). A frozen last frame is still a
// legible spectrum, which is why the bars are eased rather than snapped.

@MainActor
struct HeaderSpectrumStrip: View {

    @Environment(AudioEngine.self) private var audioEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same range as the Field panel's meter, deliberately: the colour of a partial has to mean
    /// the same thing in both places, and `SpectralColor` maps a frequency to a hue RELATIVE to
    /// this window. Narrowing it here would tint the same bass note differently in the header
    /// than in the panel — two pictures disagreeing about one sound.
    private static let bandCount = 12
    private static let fMin = 30.0
    private static let fMax = 16000.0

    /// Grows with Dynamic Type rather than sitting at a fixed height (#292 — a fixed frame is
    /// ecosystem debt). The chrome is capped at `.accessibility1` since #262, so this cannot run
    /// away; it can only track the wordmark beside it.
    @ScaledMetric(relativeTo: .caption) private var stripHeight: CGFloat = 18

    @State private var state = HeaderSpectrumState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in draw(ctx, size, at: timeline.date) }
        }
        .frame(height: stripHeight)
        // ONE element, one label, no hint. `.accessibilityElement()` — never `.combine`, which
        // discards child labels and is the mistake #352 had to undo one file over. There is no
        // number to speak here on purpose (see the header note); the Field panel's readout is
        // where a VoiceOver user gets the frequency, and duplicating it in always-on chrome
        // would put a live, ever-changing stop in front of every swipe through the header.
        .accessibilityElement()
        .accessibilityLabel("Output spectrum")
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, at date: Date) {
        // A strip narrower than this cannot show 12 separable bars, so it shows none rather than
        // a smear. This is the accessibility-size escape hatch: when the wordmark grows, the
        // flanks give way, and a compressed strip must fail to nothing instead of to noise.
        guard size.width >= 36, size.height > 1 else { return }
        state.ensure(count: Self.bandCount, fMin: Self.fMin, fMax: Self.fMax)

        audioEngine.copyLatestOutputSamples(into: &state.samples, count: HeaderSpectrumState.fftSize)
        let (magnitudes, _) = state.fft.forward(state.samples)
        var target = SpectrumAnalysis.bands(fromMagnitudes: magnitudes,
                                            sampleRate: audioEngine.sampleRate,
                                            count: Self.bandCount, fMin: Self.fMin, fMax: Self.fMax)

        // Band values are SHAPE only (normalised per frame), so silence would otherwise draw a
        // full-height picture. Scaled by the RMS of the very window the FFT just read — never by
        // `audioEngine.masterLevel`, which is written at 60 Hz and whose read here would quietly
        // re-register this leaf as a 60 Hz observer, undoing the 12 fps budget above.
        let envelope = Float(Swift.min(1.0, Double(rms(state.samples)) * 4.0))
        for i in target.indices { target[i] *= envelope }

        state.ease(toward: target, at: date)

        let spacing: CGFloat = 1
        let slot = size.width / CGFloat(Self.bandCount)
        let barWidth = Swift.max(1, slot - spacing)
        for i in 0..<Self.bandCount {
            let v = CGFloat(Swift.min(1, Swift.max(0, state.values[i])))
            // A 1.5 pt floor so silence still draws a baseline: an empty strip and a strip that
            // failed to render look identical, and this one is always on screen.
            let h = Swift.max(1.5, v * (size.height - 2))
            let rect = CGRect(x: CGFloat(i) * slot + spacing / 2,
                              y: size.height - h,
                              width: barWidth, height: h)
            let rgb = state.colors[i]
            // Hoisted out of the call: arithmetic inside an argument list is what made an
            // expression too expensive to type-check and took the blocking gate down in #287.
            let opacity: Double = 0.30 + 0.70 * Double(v)
            let fill = Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(fill))
        }
    }

    /// Root-mean-square of the window, NaN-safe. A non-finite sample must scale the picture to
    /// nothing, never to `nan` — a `nan` height makes `Canvas` skip the bar, which reads as a
    /// rendering bug rather than as bad input.
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

/// Eased band values, the per-band colours and the reusable FFT, held across frames so nothing
/// allocates per draw.
///
/// ⚠️ ITS OWN BUFFER, not `AnalysisSpectrumView`'s. That file already records why: two separate
/// leaves sharing one mutable buffer would couple their clocks, and these two run at 12 and 20
/// fps. The cost is one extra 1024-point FFT twelve times a second — tens of microseconds, and
/// stated here rather than hidden, because "there is a third FFT now" is what a later reader
/// deserves to know before adding a fourth.
@MainActor
private final class HeaderSpectrumState {
    static let fftSize = 1024                              // matches the tap buffer size

    let fft = EchoelRealFFT(size: HeaderSpectrumState.fftSize)
    var samples = [Float](repeating: 0, count: HeaderSpectrumState.fftSize)
    var values: [Float] = []
    var colors: [LinearRGB] = []
    private var configuredCount = 0
    private var lastDate: Date?

    func ensure(count: Int, fMin: Double, fMax: Double) {
        guard configuredCount != count else { return }
        configuredCount = count
        values = [Float](repeating: 0, count: count)
        colors = (0..<count).map { i in
            let hz = SpectrumAnalysis.centerFrequency(band: i, count: count, fMin: fMin, fMax: fMax)
            return SpectralColor.visibleColor(forFrequency: hz, fMin: fMin, fMax: fMax)
        }
    }

    /// Rate-based easing, not a per-frame fraction. The repo law (#315/#332/#337): a slew is
    /// defined in SECONDS and derived from the MEASURED interval, because a per-frame constant
    /// silently changes meaning the moment the frame rate does — thermal throttling, Low Power
    /// Mode, a slower device. That matters more here than in the panel: this strip runs at 12 fps
    /// by design and would be the first thing the system slows down.
    func ease(toward target: [Float], at date: Date) {
        guard target.count == values.count else { return }
        let dt = lastDate.map { Swift.min(0.25, Swift.max(0.001, date.timeIntervalSince($0))) } ?? 0.08
        lastDate = date
        let alpha = Float(1 - exp(-dt / 0.12))
        for i in values.indices {
            let t = target[i].isFinite ? target[i] : 0
            values[i] += (t - values[i]) * alpha
        }
    }
}
#endif
