#if canImport(SwiftUI)
import SwiftUI

// SpectralDonutView.swift
// Echoel — the immersive spectrum visual. Instead of blending the chord into one
// colour, it translates the WHOLE audible+feelable spectrum into the VISIBLE
// spectrum: each log-spaced frequency band is one concentric DONUT whose THICKNESS
// follows that band's loudness and whose COLOUR is that band's frequency mapped to
// visible light (low/bass → red core, high/treble → violet rim). Fundamentals,
// partials and overtones each read as their own ring — they do not wash together.
//
// Reads the live MusicalFrame off the EngineBus (the same snapshot MetalBioView uses),
// synthesizes the harmonic spectrum (SpectrumAnalysis), and eases each ring so changes
// are smooth — no flashing (WCAG ≤3 Hz; Reduce Motion → a still frame).

@MainActor
struct SpectralDonutView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(AudioEngine.self) private var audioEngine
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

        // Target spectrum from the live music (silent → all zero → fades to black).
        let notes = bus.freshMusical(maxAge: 1.5)?.notes.map { (hz: $0.frequencyHz, amplitude: $0.amplitude) } ?? []
        var target = SpectrumAnalysis.bands(from: notes, count: n, fMin: Self.fMin, fMax: Self.fMax)

        // Track the ACTUAL sound envelope: the band spectrum is shape-only
        // (normalized to its own peak), so the rings would snap on at note start
        // and hold. Modulate the whole visual by the live master RMS (peak-hold
        // with decay) so it SWELLS on attack and FADES on the decay/reverb tail —
        // the donuts breathe with the music, not just the note grid. A small
        // floor keeps a held note faintly visible during quiet sustain.
        let level = Double(max(audioEngine.masterLevel, audioEngine.masterLevelR))
        let env = min(1.0, level * 4.0)               // RMS ~0.25 → full intensity
        let envGain = Float(0.2 + 0.8 * env)
        for i in 0..<n { target[i] *= envGain }

        // Ease toward target (frame-rate independent); freeze when Reduce Motion.
        let dt = reduceMotion ? 0 : min(0.1, max(0, date.timeIntervalSince(state.lastDate)))
        state.lastDate = date
        let k = reduceMotion ? 1 : Float(1 - pow(0.0001, dt))   // ~smooth attack/release
        for i in 0..<n {
            state.values[i] += (target[i] - state.values[i]) * k
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = min(size.width, size.height) / 2 * 0.94
        let gap = maxR / CGFloat(n)

        // Inner ring = lowest band (bass core), outer = highest (treble rim).
        for i in 0..<n {
            let v = CGFloat(max(0, min(1, state.values[i])))
            guard v > 0.012 else { continue }                 // quiet bands stay invisible
            let radius = gap * (CGFloat(i) + 0.5)
            let thickness = gap * v * 0.95                     // ≤ gap → rings never overlap
            guard thickness > 0.5 else { continue }
            let rgb = state.colors[i]
            let color = Color(.sRGBLinear, red: rgb.r, green: rgb.g, blue: rgb.b,
                              opacity: 0.45 + 0.55 * Double(v))
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            ctx.stroke(Circle().path(in: rect), with: .color(color),
                       style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        }
    }

    private static let fMin: Double = 30
    private static let fMax: Double = 16000
}

/// Per-frame eased ring values + the fixed per-band visible colours (computed once).
@MainActor
private final class DonutState {
    var values: [Float] = []
    var colors: [LinearRGB] = []
    var lastDate: Date = .now
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
