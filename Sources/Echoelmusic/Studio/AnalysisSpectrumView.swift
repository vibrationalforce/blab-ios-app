#if canImport(SwiftUI)
import SwiftUI

// AnalysisSpectrumView.swift
// Echoel — #347 Slice 2. The SPECTRUM half of the founder's 2026-08-01 ask ("erweitern
// durch osciloscope, fft, spectrum, stereobild bzw spatial Analyse").
//
// ⭐ WHAT IT IS AND WHAT IT IS NOT. The scope one row up answers "what shape is the wave";
// this answers "what is in it, and what note is loudest". Both read the SAME lock-free ring
// (`AudioEngine.copyLatestOutputSamples`) that the audio tap memcpy's the live mix into, so
// both describe what is actually heard — timbre, partials, the reverb tail — not the note
// grid the sequencer intended. That distinction is the whole reason these views exist next
// to a generative instrument: the grid can be right while the sound is wrong.
//
// ⛔ THIS IS NOT A SECOND `SpectralDonutView`, and the difference is not cosmetic.
// `SpectralDonutView` is the IMMERSIVE artwork — full-screen, `ignoresSafeArea`, black,
// 60 fps, one animated ring per band. Since #747 it IS reachable — today through the Field
// panel's `Toggle(isOn: $spectralDonuts)` (#1065; ⛔ "then the cover's top-bar donut toggle"
// stood here until #1105, #1069 deleted that cover); this comment said "no reachable door" until then
// and the distinction it drew never depended on that. This is a
// PANEL-SIZED MEASURING INSTRUMENT inside the Field panel: 88 pt tall, 20 fps, a number
// first. They share the pure parts on purpose (`SpectrumAnalysis`, `SpectralColor`,
// `EchoelRealFFT`) and nothing else. Do not "unify" them — one is art, one is a meter, and
// the repo already paid for the reverse mistake (#164/#227: a control that looked like a
// measurement and was not).
//
// COLOUR IS THE APP'S PHYSICAL MAPPING, not decoration: each band is tinted by
// `SpectralColor.visibleColor`, the same frequency→visible-light transform the Field's own
// colour uses (octave-doubled into the visible band, through CIE 1931). So a bass partial
// reads red and a bright one violet, and the meter and the artwork agree about what a
// frequency LOOKS like. Uncodixfy-clean: flat fills, no glow, no gradient, radius 2.
//
// LEAF BY CONSTRUCTION (the 10.76.50 freeze law). The `TimelineView` and every read of
// `audioEngine` live in THIS struct's body. It must never be inlined into `visualPanel` or
// any ancestor — that would register the whole Studio, and every open `.menu` Picker in it,
// as a 20 Hz observer.
//
// NO DSP ON THE AUDIO THREAD: the ring is copied on the main thread by design, and the FFT
// runs here, on the main thread, exactly as `SpectralDonutView` does.

@MainActor
struct AnalysisSpectrumView: View {

    @Environment(AudioEngine.self) private var audioEngine
    var reduceMotion: Bool = false

    /// 24 log-spaced bands over 30 Hz…16 kHz. Enough to separate a fundamental from its
    /// first partials at panel width; more would put bars under 4 pt wide on the narrowest
    /// iPhone, where they stop being readable and become texture.
    private static let bandCount = 24
    private static let fMin = 30.0
    private static let fMax = 16000.0

    /// Grows with Dynamic Type instead of sitting at a fixed height (#292 — a fixed frame
    /// is ecosystem debt, and this view is meant to survive the move to bigger surfaces).
    @ScaledMetric(relativeTo: .caption) private var barsHeight: CGFloat = 88

    @State private var state = SpectrumBarsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 20 fps, not 60: the bars are already eased over ~120 ms, so a faster redraw
            // changes no pixel a human can see and costs battery in a panel a performer
            // leaves open. Reduce Motion freezes the picture (WCAG / the repo's motion law) —
            // the last frame stays legible, which is the point of easing rather than
            // snapping.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
                Canvas { ctx, size in draw(ctx, size, at: timeline.date) }
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .frame(height: barsHeight)
            // ⛔ THIS WAS `.accessibilityElement(children: .combine)` ON THE WHOLE `VStack`,
            // with the label and hint below it — and that is a regression I shipped in this
            // very slice (#347 Slice 2 → #352), while the OSCILLOSCOPE one row up already
            // carried a comment explaining why it must not be done that way. `.combine`
            // folds the children into a single element and DISCARDS their labels; an
            // explicit `.accessibilityLabel` on the same element then replaces whatever
            // survived. So a VoiceOver user heard "Spectrum analyser" and NEVER
            // "220.1 Hz · A2 +5 ct" — the one piece of actual data on the view, and the
            // number the sighted layout puts front and centre under the science-first rule.
            // The bars are the part that legitimately wants a summary label, because a
            // Canvas has nothing readable in it; the readout beside them never did.
            //
            // LEHRE, weil sie sich von der üblichen unterscheidet: the correct pattern
            // existed, in a sibling file, with a comment naming this exact mistake — and I
            // reproduced the mistake anyway, one slice later, because I wrote the second
            // view from the shape of the first rather than from its reasons.
            .accessibilityElement()
            .accessibilityLabel("Spectrum analyser")
            .accessibilityHint("The frequencies present in the master output, low on the left, high on the right.")
            // SCIENCE-FIRST: the number before the picture (Uncodixfy). Its own leaf, its
            // own slower clock, and now its own accessibility element — see the type's note.
            SpectrumPeakLabel()
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, at date: Date) {
        guard size.width > 1, size.height > 1 else { return }
        state.ensure(count: Self.bandCount, fMin: Self.fMin, fMax: Self.fMax)

        audioEngine.copyLatestOutputSamples(into: &state.samples, count: SpectrumBarsState.fftSize)
        let (magnitudes, _) = state.fft.forward(state.samples)
        var target = SpectrumAnalysis.bands(fromMagnitudes: magnitudes,
                                            sampleRate: audioEngine.sampleRate,
                                            count: Self.bandCount, fMin: Self.fMin, fMax: Self.fMax)

        // The band spectrum is SHAPE only (each frame is normalised to its own loudest
        // band), so on its own it would show a full-height picture in near-silence. Scale it
        // by loudness so quiet is visibly quiet.
        //
        // ⚠️ THE LOUDNESS COMES FROM THE SAME WINDOW, not from `audioEngine.masterLevel` —
        // and that is a deliberate divergence from `SpectralDonutView`, for two reasons.
        // (1) `masterLevel` is an `@Observable` property the meter timer writes at 60 Hz;
        // reading it inside this draw would register THIS view as a 60 Hz observer and
        // silently undo the 20 fps budget the TimelineView above sets. (2) It is measured at
        // a different moment than the window the FFT just read, so on a fast transient the
        // shape and its scaling would disagree by a frame. The RMS of the buffer in hand
        // cannot drift from the picture it scales.
        let envelope = Float(Swift.min(1.0, Double(rms(state.samples)) * 4.0))  // RMS ~0.25 → full
        for i in target.indices { target[i] *= envelope }

        state.ease(toward: target, at: date)

        // Bars from the bottom. `spacing` is a fixed 1 pt rather than a fraction of the
        // width so the gaps stay hairlines at every size instead of growing into the bars.
        let spacing: CGFloat = 1
        let slot = size.width / CGFloat(Self.bandCount)
        let barWidth = Swift.max(1, slot - spacing)
        for i in 0..<Self.bandCount {
            let v = CGFloat(Swift.min(1, Swift.max(0, state.values[i])))
            // A floor of 1.5 pt so an empty band still draws a baseline tick: an all-blank
            // box cannot be told apart from a view that failed to render.
            let h = Swift.max(1.5, v * (size.height - 4))
            let rect = CGRect(x: CGFloat(i) * slot + spacing / 2,
                              y: size.height - h - 2,
                              width: barWidth, height: h)
            let rgb = state.colors[i]
            // Dimmer when quiet, so the colour reads as intensity too and a silent band is
            // not a bright stub of colour. Hoisted out of the call: arithmetic inside an
            // argument list is what makes an expression expensive to type-check, and this
            // repo has already taken a blocking gate down for exactly that (#287).
            let opacity: Double = 0.35 + 0.65 * Double(v)
            let fill = Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill))
        }
    }

    /// Root-mean-square of the window, NaN-safe. A non-finite sample from a bad frame must
    /// scale the picture to nothing, never to `nan` — a `nan` height makes `Canvas` skip the
    /// bar entirely, which looks like a rendering bug rather than a bad input.
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

/// The peak readout — "220.1 Hz · A2 +5 ct".
///
/// ⚠️ ITS OWN LEAF AND ITS OWN, SLOWER CLOCK (4 Hz), and both halves are deliberate. Own
/// leaf: the freeze law — an observation boundary belongs at the value, not at whatever
/// happens to host it today. Slower clock: a frequency that changes twenty times a second
/// is not a readout, it is a blur; 4 Hz is the tuner convention and the fastest a person
/// can actually read. It is NOT paused by Reduce Motion, because a changing NUMBER is data,
/// not motion — freezing it would show a stale frequency with no sign that it is stale.
///
/// The cost is a second 1024-point FFT of the same buffer, four times a second. That is a
/// few dozen microseconds and it buys the leaf boundary; stated rather than hidden, because
/// "it also computes the FFT" is exactly the kind of thing a later reader deserves to know
/// before adding a third one.
@MainActor
private struct SpectrumPeakLabel: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(SessionContext.self) private var session
    @AppStorage(StudioDefaultKeys.noteNaming.key) private var noteNamingRaw = StudioDefaultKeys.noteNaming.value

    @State private var state = SpectrumReadoutState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: false)) { _ in
            // Computed ONCE per tick and used for both strings — the same reason
            // `AnalysisPoincareView` hoists its readout: calling this again for the
            // accessibility label would run a second 1024-point FFT four times a second
            // purely to say the same thing differently.
            let r = readout()
            Text(r.display)
                .font(EchoelTheme.font(11).monospacedDigit())
                .foregroundStyle(EchoelTheme.dim)
                // A SPOKEN variant, not the printed one. VoiceOver reads "·" as "middle dot"
                // and U+2212 as "minus sign" mid-number, so the printed form arrives as
                // "220.1 Hz middle dot A2 plus 5 ct" — technically the same characters, and
                // not a sentence anybody can follow while playing. Sharp/flat is also the
                // word a musician actually uses for the sign of a cent offset.
                .accessibilityLabel(r.spoken)
        }
    }

    /// `display` is what the panel prints; `spoken` is what VoiceOver says. They are built
    /// together so they cannot drift — two functions reading the same FFT would be two places
    /// to update when the format changes, and the silent-case wording is easy to fix in one.
    private func readout() -> (display: String, spoken: String) {
        audioEngine.copyLatestOutputSamples(into: &state.samples, count: SpectrumReadoutState.fftSize)
        let (magnitudes, _) = state.fft.forward(state.samples)
        guard let peak = SpectrumReadout.peak(magnitudes, sampleRate: audioEngine.sampleRate) else {
            // The one case where both strings are identical: it is already a sentence.
            return ("No dominant tone", "No dominant tone")
        }
        let hz = EchoelDecimalText.string(peak.hz, decimals: 1)
        // The reference pitch is the session's, not 440 — a performer tuned to 432 must not
        // be told every note they play is 32 cents flat.
        guard let note = SpectrumReadout.nearestNote(hz: peak.hz, a4Hz: session.a4Hz) else {
            return ("\(hz) Hz", "Loudest tone \(hz) hertz")
        }
        // Spelled in the reader's own system (#232 E): A/H/C, Do/Re/Mi or Sa/Re/Ga, the
        // same setting the Key picker two panels up obeys. A readout that spelled B where
        // the picker says H is the inconsistency that setting exists to remove.
        let naming = NoteNaming(stored: noteNamingRaw)
        let name = naming.name(pitchClass: note.midi)
        let octave = note.midi / 12 - 1                     // MIDI 60 = C4, scientific pitch
        let cents = Int(note.cents.rounded())
        let display = "\(hz) Hz · \(name)\(octave) \(cents >= 0 ? "+" : "−")\(abs(cents)) ct"
        // "sharp"/"flat" rather than "+"/"−", and the word "cents" rather than "ct". Exactly
        // zero cents gets neither word: "A2, in tune" is what a musician says, and "A2 plus
        // zero cents sharp" is what a naive sign test would produce.
        let spoken: String
        if cents == 0 {
            spoken = "Loudest tone \(hz) hertz, \(name)\(octave), in tune"
        } else {
            let direction = cents > 0 ? "sharp" : "flat"
            spoken = "Loudest tone \(hz) hertz, \(name)\(octave), \(abs(cents)) cents \(direction)"
        }
        return (display, spoken)
    }
}

/// Eased band values plus the per-band colours and the reusable FFT, held across frames so
/// nothing allocates per draw. Same shape as `SpectralDonutView`'s `DonutState`.
@MainActor
private final class SpectrumBarsState {
    static let fftSize = 1024                              // matches the tap buffer size

    let fft = EchoelRealFFT(size: SpectrumBarsState.fftSize)
    var samples = [Float](repeating: 0, count: SpectrumBarsState.fftSize)
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

    /// Rate-based easing, not a fixed per-frame fraction. The repo law is that a slew is
    /// defined in SECONDS and derived from the measured frame interval — a per-frame
    /// constant silently changes its meaning the moment the frame rate does (thermal
    /// throttling, Low Power Mode, a slower device), which is the #315/#332 class.
    ///
    /// ~120 ms to close the gap: fast enough that a note onset does not lag visibly, slow
    /// enough that the picture never strobes. Rising is not smoothed harder than falling on
    /// purpose — a meter that attacks slower than it releases under-reports transients.
    func ease(toward target: [Float], at date: Date) {
        guard target.count == values.count else { return }
        let dt = lastDate.map { Swift.min(0.25, Swift.max(0.001, date.timeIntervalSince($0))) } ?? 0.05
        lastDate = date
        let alpha = Float(1 - exp(-dt / 0.12))
        for i in values.indices {
            let t = target[i].isFinite ? target[i] : 0
            values[i] += (t - values[i]) * alpha
        }
    }
}

/// The readout's own buffer + FFT. Separate from `SpectrumBarsState` because the two views
/// are separate leaves and sharing a mutable buffer between them would couple their clocks.
@MainActor
private final class SpectrumReadoutState {
    static let fftSize = 1024
    let fft = EchoelRealFFT(size: SpectrumReadoutState.fftSize)
    var samples = [Float](repeating: 0, count: SpectrumReadoutState.fftSize)
}
#endif
