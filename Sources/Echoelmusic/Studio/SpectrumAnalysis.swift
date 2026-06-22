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
