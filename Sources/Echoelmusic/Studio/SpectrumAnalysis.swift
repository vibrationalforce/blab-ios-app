//
//  SpectrumAnalysis.swift
//  Echoelmusic — Studio
//
//  Turns the sounding notes (MusicalFrame) into a per-band energy spectrum for the
//  concentric-donut visual. Each note contributes its FUNDAMENTAL, its OVERTONES
//  (2f, 3f, … — Obertöne/Teiltöne) and a few SUBHARMONICS (f/2, f/3 — Untertöne,
//  the "feelable" low end), so the whole harmonic structure registers instead of one
//  blended chord colour. Energies are binned into log-spaced bands across the audible
//  + feelable range and normalized to the loudest band.
//
//  Pure value type (Foundation only) → fully unit-testable, no audio thread, no UI.
//

import Foundation

public enum SpectrumAnalysis {

    /// Build `count` log-spaced band energies (0…1, normalized to the loudest band)
    /// from sounding notes. `overtones` harmonics and `undertones` subharmonics are
    /// synthesized per note with a 1/n amplitude rolloff. Bands span `fMin`…`fMax`.
    public static func bands(from notes: [(hz: Double, amplitude: Double)],
                             count: Int = 28,
                             fMin: Double = 30, fMax: Double = 16000,
                             overtones: Int = 6, undertones: Int = 2) -> [Float] {
        let n = max(1, count)
        var energy = [Double](repeating: 0, count: n)
        guard fMax > fMin, fMin > 0 else { return energy.map { Float($0) } }
        let logMin = Foundation.log(fMin), logMax = Foundation.log(fMax)
        let span = logMax - logMin

        @inline(__always) func bandIndex(_ hz: Double) -> Int? {
            guard hz >= fMin, hz <= fMax else { return nil }
            let t = (Foundation.log(hz) - logMin) / span
            return min(n - 1, max(0, Int(t * Double(n))))
        }
        @inline(__always) func add(_ hz: Double, _ amp: Double) {
            guard amp > 0, let i = bandIndex(hz) else { return }
            energy[i] += amp
        }

        for note in notes {
            let f = note.hz, a = note.amplitude
            guard f > 0, f.isFinite, a > 0, a.isFinite else { continue }
            // Fundamental + overtones (harmonic series, 1/h rolloff).
            for h in 1...max(1, overtones) { add(f * Double(h), a / Double(h)) }
            // Subharmonics (the felt low end), gentler weight.
            if undertones >= 1 {
                for s in 2...(undertones + 1) { add(f / Double(s), a / (Double(s) * 1.5)) }
            }
        }

        let peak = energy.max() ?? 0
        guard peak > 0 else { return energy.map { Float($0) } }
        return energy.map { Float(min(1.0, $0 / peak)) }
    }

    /// Build `count` log-spaced band energies (0…1, normalized to the loudest band)
    /// from a real FFT magnitude spectrum (`magnitudes[k]` = bin k, k·sampleRate/fftSize Hz).
    /// Each band takes the PEAK of the bins falling in its log range so a single
    /// strong partial reads as its own ring instead of being averaged away. This is
    /// the live-audio counterpart to `bands(from:notes:)` — the visual reflects what
    /// is actually heard (timbre, overtones, reverb tail), not just the note grid.
    public static func bands(fromMagnitudes magnitudes: [Float], sampleRate: Double,
                             count: Int = 28,
                             fMin: Double = 30, fMax: Double = 16000) -> [Float] {
        let n = max(1, count)
        var energy = [Float](repeating: 0, count: n)
        let bins = magnitudes.count
        guard bins > 1, sampleRate > 0, fMax > fMin, fMin > 0 else { return energy }
        let fftSize = Double(bins * 2)
        let hzPerBin = sampleRate / fftSize
        let logMin = Foundation.log(fMin), logMax = Foundation.log(fMax)
        let span = logMax - logMin
        guard span > 0 else { return energy }

        // Skip DC (bin 0); assign each bin to its log-spaced band, keeping the peak.
        for k in 1..<bins {
            let hz = Double(k) * hzPerBin
            guard hz >= fMin, hz <= fMax else { continue }
            let t = (Foundation.log(hz) - logMin) / span
            let i = min(n - 1, max(0, Int(t * Double(n))))
            if magnitudes[k] > energy[i] { energy[i] = magnitudes[k] }
        }

        let peak = energy.max() ?? 0
        guard peak > 0 else { return energy }
        // Mild compression (sqrt) so quiet partials stay visible without the loud
        // band washing everything out — a perceptual, not linear, magnitude.
        return energy.map { Float((Double($0 / peak)).squareRoot()) }
    }

    /// Center frequency (Hz) of band `i` of `count` — for colouring each donut via
    /// `SpectralColor.visibleColor`. Geometric (log) center, matching the binning.
    public static func centerFrequency(band i: Int, count: Int,
                                       fMin: Double = 30, fMax: Double = 16000) -> Double {
        let n = max(1, count)
        let idx = min(n - 1, max(0, i))
        let logMin = Foundation.log(fMin), logMax = Foundation.log(fMax)
        let t = (Double(idx) + 0.5) / Double(n)
        return Foundation.exp(logMin + t * (logMax - logMin))
    }
}
