// SpectrumReadout.swift
// Echoel — the NUMBER that belongs above a spectrum picture (#347 Slice 2).
//
// ⭐ WHY A PEAK PICKER IS ITS OWN FILE, and why "just take the biggest bin" is not enough.
// At the 1024-point FFT this app already runs (`SpectralDonutView`'s `DonutState.fftSize`)
// and 48 kHz, one bin is 46.9 Hz WIDE. A 110 Hz bass note lands in the bin centred on
// 93.75 Hz. Reading the bin centre back as "the frequency" is off by up to half a bin —
// measured against a real DFT of a Blackman-windowed sine, the raw-bin error over
// 110…1235 Hz ranges from −20.0 to +19.6 Hz. That is a quarter-tone to a minor third: the
// readout would name the WRONG NOTE, which is worse than showing no number at all
// (#164/#227, the lying-control class).
//
// The fix is the standard three-point parabolic interpolation, done on LOG magnitudes.
// Measured on the same DFT, the same frequencies: error ≤ 0.32 Hz. Interpolating on LINEAR
// magnitudes — the version most people write first — lands at ~2 Hz, six times worse,
// because a windowed peak's main lobe is close to a parabola in dB and not in amplitude.
// Those three numbers are measurements, not estimates; `SpectrumReadoutTests` re-derives
// them from an actual `EchoelRealFFT` so they cannot quietly age.
//
// Pure value maths, Foundation only, so the blocking bundle can test it without a view,
// a renderer or an audio graph. In `Studio/` next to `ScopeTrigger` and `SpectrumAnalysis`
// rather than `DSP/`, which keeps a Foundation-only hygiene rule of its own and is where
// the FFT itself lives — this is the READING of a spectrum, not the making of one.

import Foundation

enum SpectrumReadout {

    /// A resolved peak: where the strongest partial actually sits, and how sure we are.
    struct Peak: Equatable {
        /// Interpolated frequency in Hz — not a bin centre.
        let hz: Double
        /// The winning bin's magnitude, for a "is this worth showing" gate upstream.
        let magnitude: Float
    }

    /// Strongest partial in `magnitudes`, interpolated to sub-bin accuracy.
    ///
    /// `magnitudes[k]` is bin `k` of a real FFT, i.e. `k * sampleRate / fftSize` Hz, with
    /// `fftSize == magnitudes.count * 2` — the convention `SpectrumAnalysis` already uses,
    /// so both readers of the same array agree about which frequency a bin means.
    ///
    /// Returns `nil` rather than a fabricated number when there is nothing to report:
    /// silence, a degenerate array, non-finite input, or a peak sitting on the very first
    /// or last bin (where the three points the interpolation needs do not exist, and where
    /// a "peak" is far more likely to be DC drift or the Nyquist corner than a note).
    ///
    /// `fMin`/`fMax` bound the SEARCH. 25 Hz is below the lowest note this instrument
    /// produces and still above the DC/rumble region; 5 kHz is above the fundamental of
    /// anything playable here, so a bright partial cannot outvote the note that produced it.
    static func peak(_ magnitudes: [Float],
                     sampleRate: Double,
                     fMin: Double = 25,
                     fMax: Double = 5000) -> Peak? {
        let bins = magnitudes.count
        guard bins > 2, sampleRate > 0, fMax > fMin, fMin > 0 else { return nil }
        let hzPerBin = sampleRate / Double(bins * 2)
        guard hzPerBin > 0 else { return nil }

        // Skip bin 0 (DC) and the last bin: both lack a neighbour on one side, and the
        // interpolation below reads k−1 and k+1 unconditionally.
        let lo = Swift.max(1, Int((fMin / hzPerBin).rounded(.up)))
        let hi = Swift.min(bins - 2, Int(fMax / hzPerBin))
        guard lo <= hi else { return nil }

        var best = lo
        var bestValue: Float = -1
        for k in lo...hi {
            let v = magnitudes[k]
            guard v.isFinite else { continue }
            if v > bestValue { bestValue = v; best = k }
        }
        guard bestValue > 0 else { return nil }

        let hz = (Double(best) + subBinOffset(magnitudes, at: best)) * hzPerBin
        guard hz.isFinite, hz > 0 else { return nil }
        return Peak(hz: hz, magnitude: bestValue)
    }

    /// Three-point parabolic vertex offset in BINS, in −0.5…+0.5, computed on log
    /// magnitudes. Zero when the three points are flat, symmetric, or unusable — a
    /// degenerate group must fall back to the bin centre, never to a division by zero.
    static func subBinOffset(_ magnitudes: [Float], at k: Int) -> Double {
        guard k >= 1, k + 1 < magnitudes.count else { return 0 }
        let raw = [magnitudes[k - 1], magnitudes[k], magnitudes[k + 1]]
        guard raw.allSatisfy({ $0.isFinite }) else { return 0 }
        // Floor before the log so a zero neighbour (silence next to a partial) yields a
        // very negative but FINITE value instead of −inf poisoning the arithmetic.
        let floorValue = 1e-20
        let y = raw.map { Foundation.log(Swift.max(Double($0), floorValue)) }
        let denominator = y[0] - 2 * y[1] + y[2]
        guard abs(denominator) > 1e-12 else { return 0 }
        let offset = 0.5 * (y[0] - y[2]) / denominator
        guard offset.isFinite else { return 0 }
        // Clamp, not trust: a peak whose vertex lies outside its own bin means the
        // neighbours were not a single main lobe, and following it would move the readout
        // further from the truth rather than closer.
        return Swift.min(0.5, Swift.max(-0.5, offset))
    }

    /// Nearest equal-tempered note to `hz`, and how far off it is in cents (−50…+50).
    ///
    /// The reference pitch is a parameter because this instrument does not assume 440 —
    /// `TuningReference.a4Hz` is user-settable, and a readout that silently assumed 440
    /// would tell a performer tuned to 432 that every note they play is 32 cents flat.
    static func nearestNote(hz: Double, a4Hz: Double) -> (midi: Int, cents: Double)? {
        guard hz > 0, hz.isFinite, a4Hz > 0, a4Hz.isFinite else { return nil }
        let exact = 69 + 12 * Foundation.log2(hz / a4Hz)
        guard exact.isFinite, exact >= 0, exact <= 127 else { return nil }
        let midi = Int(exact.rounded())
        return (midi, (exact - Double(midi)) * 100)
    }
}
