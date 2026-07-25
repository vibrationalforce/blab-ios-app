#if canImport(SwiftUI)
import SwiftUI

// SpectralDonutView.swift
// Echoel — the immersive spectrum visual. It translates the WHOLE audible+feelable
// spectrum into the VISIBLE spectrum: each log-spaced frequency band is one concentric
// ring whose COLOUR is that band's frequency mapped to visible light (low/bass → red
// core, high/treble → violet rim). Each ring is an OSCILLATING WAVEFORM — a closed
// loop whose radius wobbles around the circle, amplitude following that band's energy
// and lobe-count rising with frequency — so fundamentals, partials and overtones each
// read as their own animated waveform rather than washing together.
//
// The spectrum is a REAL FFT of the master output: the audio tap memcpy's the live mix
// into a lock-free ring (AudioEngine), and this view pulls the newest window and runs
// the FFT on the main thread (EchoelRealFFT) every frame — no DSP on the audio thread.
// Each ring is eased so changes are smooth and motion is slow (no flashing; WCAG ≤3 Hz;
// Reduce Motion → a still frame).

@MainActor
struct SpectralDonutView: View {

    @Environment(AudioEngine.self) private var audioEngine
    @Environment(EngineBus.self) private var bus
    var reduceMotion: Bool = false
    var bandCount: Int = 28

    /// Reference-type smoother held across frames (eased ring values + cached colours).
    @State private var state = DonutState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                draw(ctx, size, date: timeline.date)
            }
            .background(.black)
        }
        .ignoresSafeArea()
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, date: Date) {
        let n = max(4, bandCount)
        state.ensure(count: n, fMin: Self.fMin, fMax: Self.fMax)

        // Target spectrum from a REAL FFT of the master output. The audio tap
        // memcpy's the live mix into a lock-free ring; we pull the newest window
        // and run the FFT HERE on the main thread (never on the audio thread). The
        // visual therefore reflects what is actually heard — timbre, overtones and
        // the reverb tail — not just the note grid. Silent → zeros → fades to black.
        audioEngine.copyLatestOutputSamples(into: &state.samples, count: DonutState.fftSize)
        let (mags, _) = state.fftEngine.forward(state.samples)
        var target = SpectrumAnalysis.bands(fromMagnitudes: mags, sampleRate: audioEngine.sampleRate,
                                            count: n, fMin: Self.fMin, fMax: Self.fMax)

        // The band spectrum is shape-only (normalized to its own peak), so modulate
        // by the live master level so the rings SWELL on attack and FADE on the
        // decay/reverb tail, and vanish in true silence (no held full-scale rings).
        let level = Double(max(audioEngine.masterLevel, audioEngine.masterLevelR))
        let env = Float(min(1.0, level * 4.0))        // RMS ~0.25 → full intensity
        for i in 0..<n { target[i] *= env }

        // IDLE so the look is never a dead-black screen when there is no audio yet (e.g.
        // the synth is armed-silent, or the user opens the visual before playing): a
        // faint, slow breathing baseline across the bands. Real signal overrides it the
        // instant there is output, so this only ever shows during true silence.
        let totalEnergy = target.reduce(0, +)
        if totalEnergy < 0.02 {
            let idle = Float(0.06 + 0.02 * sin(date.timeIntervalSinceReferenceDate * 0.3))
            for i in 0..<n { target[i] = idle }
        }

        // Ease toward target (frame-rate independent); freeze when Reduce Motion.
        let dt = reduceMotion ? 0 : min(0.1, max(0, date.timeIntervalSince(state.lastDate)))
        state.lastDate = date
        let k = reduceMotion ? 1 : Float(1 - pow(0.0001, dt))   // ~smooth attack/release
        for i in 0..<n {
            state.values[i] += (target[i] - state.values[i]) * k
        }

        let maxR = min(size.width, size.height) / 2 * 0.94
        let gap = maxR / CGFloat(n)
        let t = date.timeIntervalSinceReferenceDate

        // SWING ("schwingen"): the whole ring system sways through space like a slow
        // pendulum, bound to the body — breath drives the horizontal azimuth, HRV the
        // vertical lift — so the rings move WHERE the spatial object is. The pendulum
        // runs at ~0.1 Hz (resonance breath rate), the bob at ~0.13 Hz; both are far
        // under the 3 Hz flash ceiling. Sway amplitude follows loudness (silent →
        // still, centred) so it breathes with the sound. Reduce Motion → no sway.
        var center = CGPoint(x: size.width / 2, y: size.height / 2)
        // `usableBio()`, NOT a hand-rolled maxAge: the camera publisher republishes the
        // last good frame for up to 4 s while it recovers from a stall, so any window
        // SHORTER than that hold expires mid-grace and snaps these rings back to the
        // `?? 0.5` defaults — the exact bio↔idle jump the hold exists to prevent. The
        // per-source window (`BioSource.freshnessWindow`) is the one place that stays
        // in step with the publishers.
        let bio = bus.usableBio()
        let breath = Double(bio?.breathPhase ?? 0.5)             // 0…1
        let hrv = Double(bio?.hrvForSound ?? 0.5)                // 0 = unmeasured → neutral
        let coh = Double(bio?.coherenceForSound ?? 0.5)          // ditto — coh drives depth
        // DEPTH cues (slow, bounded — not flashing, so applied even under Reduce
        // Motion): coherence pulls the whole field CLOSE (larger) — the spatial
        // "distance" dimension — and HRV LIFTS it into a taller ellipse (elevation).
        let radiusScale = 1.0 + 0.12 * (coh * 2 - 1)            // 0.88…1.12 (close↔far)
        let squashY = 1.0 + 0.10 * (hrv * 2 - 1)               // 0.90…1.10 (lift)
        if !reduceMotion {
            let level = Double(max(audioEngine.masterLevel, audioEngine.masterLevelR))
            let swayAmp = min(1.0, level * 3.0)
            let azimuth = breath * 2 - 1                          // -1…1 with breath
            let elevation = hrv * 2 - 1                           // -1…1 with HRV
            let pendulumX = sin(t * 0.10 * 2 * .pi)
            let pendulumY = sin(t * 0.13 * 2 * .pi)
            center.x += CGFloat(maxR * 0.16 * swayAmp * (0.6 * pendulumX + 0.4 * azimuth))
            center.y -= CGFloat(maxR * 0.10 * swayAmp * (0.5 * pendulumY + 0.5 * elevation))
        }

        // Each band is an OSCILLATING WAVEFORM ring: a closed loop whose radius
        // wobbles around the circle. The wobble AMPLITUDE follows the band's energy,
        // the LOBE COUNT rises with frequency (inner = smooth bass, outer = busy
        // treble), and the PHASE advances over time (alternating direction per ring
        // for an interference look). Inner ring = lowest band, outer = highest.
        // Motion is continuous and slow (≪3 Hz, no luminance flashing); Reduce
        // Motion freezes the phase so the FFT shape is still shown, just still.
        let segs = 128
        for i in 0..<n {
            let v = Double(max(0, min(1, state.values[i])))
            guard v > 0.012 else { continue }                 // quiet bands stay invisible
            let baseRadius = Double(gap) * (Double(i) + 0.5)
            let lobes = Double(3 + i)                          // higher band → more lobes
            let wobble = Double(gap) * 0.42 * v               // stays within the ring's gap
            let speed = reduceMotion ? 0 : (0.5 + 0.1 * Double(i))
            let dir: Double = (i % 2 == 0) ? 1 : -1
            let phase = t * speed * dir

            var path = Path()
            for s in 0...segs {
                let a = Double(s) / Double(segs) * 2 * .pi
                let r = (baseRadius + wobble * sin(lobes * a + phase)) * radiusScale
                let p = CGPoint(x: center.x + CGFloat(cos(a) * r),
                                y: center.y + CGFloat(sin(a) * r * squashY))
                if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()

            let rgb = state.colors[i]
            let color = Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b,
                              opacity: 0.45 + 0.55 * v)
            let lineWidth = max(0.8, Double(gap) * (0.14 + 0.32 * v))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private static let fMin: Double = 30
    private static let fMax: Double = 16000
}

/// Per-frame eased ring values + the fixed per-band visible colours (computed once),
/// plus the reusable FFT engine and sample window for the live spectrum.
@MainActor
private final class DonutState {
    static let fftSize = 1024                          // matches the tap buffer size
    var values: [Float] = []
    var colors: [LinearRGB] = []
    var lastDate: Date = .now
    /// Held across frames so the FFT setup + windowed buffers allocate once.
    let fftEngine = EchoelRealFFT(size: DonutState.fftSize)
    var samples = [Float](repeating: 0, count: DonutState.fftSize)
    private var configuredCount = 0

    func ensure(count: Int, fMin: Double, fMax: Double) {
        guard configuredCount != count else { return }
        configuredCount = count
        values = [Float](repeating: 0, count: count)
        colors = (0..<count).map { i in
            let hz = SpectrumAnalysis.centerFrequency(band: i, count: count, fMin: fMin, fMax: fMax)
            return SpectralColor.visibleColor(forFrequency: hz, fMin: fMin, fMax: fMax)
        }
    }
}
#endif
