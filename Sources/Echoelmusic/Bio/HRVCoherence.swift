//
//  HRVCoherence.swift
//  Echoelmusic — Bio
//
//  Frequency-domain HRV: the REAL coherence metric, computed to the HRV
//  measurement standard (Task Force 1996 / ESC-NASPE bands), not the
//  inverse-variance placeholder it replaces.
//
//  Two independent spectral estimators, blendable by a single fader:
//
//    • Lomb–Scargle periodogram (Lomb 1976, Scargle 1982) — estimates the
//      spectrum DIRECTLY from the unevenly-sampled RR tachogram (each beat
//      arrives at its own time), with NO interpolation. This is the method
//      astrophysics developed for irregularly-sampled starlight; it is the
//      most rigorous choice for short HRV records. Default end of the fader.
//
//    • Welch / windowed periodogram — resamples the RR tachogram onto a
//      uniform 4 Hz grid (linear interpolation), removes the mean, applies a
//      Hann window (leakage control, power-compensated), then a direct DFT at
//      the analysis grid. The classic, easy-to-explain Task-Force path.
//
//  The fader (`blend`, 0 = Welch, 1 = Lomb–Scargle) cross-fades the two
//  coherence estimates so the user can hear/see one method validate the other.
//
//  COHERENCE is defined the defensible way (HeartMath / Lehrer): the fraction
//  of total HRV power that concentrates in a narrow window around the dominant
//  peak inside the baroreflex-resonance search band (0.04–0.26 Hz). A body
//  breathing at its resonance (~0.1 Hz, ~6 breaths/min) drives a single tall
//  LF peak → coherence → 1. An erratic spectrum spreads power → coherence → 0.
//
//  Frequency bands (Hz): VLF 0.0033–0.04 · LF 0.04–0.15 · HF 0.15–0.40.
//
//  Pure value type. Deterministic. NOT on the audio render thread — runs in
//  the bio poll (allocation is fine here). Inputs are RR/NN intervals in ms,
//  exactly like `HRVMetrics`. Only feed it RR from a trusted beat-to-beat
//  source (BLE 0x180D / Polar). Averaged-HR-derived RR is NOT valid input.
//

import Foundation

// MARK: - Spectrum

/// A one-sided power spectrum sampled on the analysis grid.
public struct PowerSpectrum: Sendable, Equatable {
    public let frequencies: [Double]   // Hz, ascending
    public let power: [Double]         // power at each frequency (arbitrary units)

    public init(frequencies: [Double], power: [Double]) {
        self.frequencies = frequencies
        self.power = power
    }
}

// MARK: - Method

public enum HRVSpectralMethod: UInt8, Sendable, Equatable {
    /// Direct estimate from the irregular RR tachogram (no interpolation).
    case lombScargle = 0
    /// Resample → Hann window → direct DFT (classic windowed periodogram).
    case welch = 1
}

// MARK: - Reading

/// One coherence reading plus the band powers behind it, and — per the
/// "app as a school" principle — a plain, non-medical explanation of what the
/// number means. No therapeutic, diagnostic, or wellness claims live here.
public struct CoherenceReading: Sendable, Equatable {

    /// 0…1 — share of HRV power concentrated in the dominant resonance peak.
    public let coherence: Float
    /// Frequency of the dominant peak inside the 0.04–0.26 Hz search band (Hz).
    public let peakFrequencyHz: Float
    /// Absolute power in the LF band (0.04–0.15 Hz).
    public let lfPower: Float
    /// Absolute power in the HF band (0.15–0.40 Hz).
    public let hfPower: Float
    /// LF/HF ratio (sympathovagal balance indicator). 0 when HF is empty.
    public let lfHfRatio: Float
    /// Total power across 0.0033–0.40 Hz.
    public let totalPower: Float
    /// True only when there were enough finite intervals to estimate a spectrum.
    public let valid: Bool

    public init(
        coherence: Float,
        peakFrequencyHz: Float,
        lfPower: Float,
        hfPower: Float,
        lfHfRatio: Float,
        totalPower: Float,
        valid: Bool
    ) {
        self.coherence = coherence
        self.peakFrequencyHz = peakFrequencyHz
        self.lfPower = lfPower
        self.hfPower = hfPower
        self.lfHfRatio = lfHfRatio
        self.totalPower = totalPower
        self.valid = valid
    }

    /// A reading that carries no usable spectrum.
    public static let invalid = CoherenceReading(
        coherence: 0, peakFrequencyHz: 0, lfPower: 0, hfPower: 0,
        lfHfRatio: 0, totalPower: 0, valid: false
    )

    /// Short factual headline, e.g. "Coherence 0.62 · peak 0.10 Hz".
    public var headline: String {
        guard valid else { return "Coherence — (collecting beats…)" }
        return String(format: "Coherence %.2f · peak %.2f Hz", coherence, peakFrequencyHz)
    }

    /// One-sentence, science-only lesson — the "school" layer. Never medical.
    public var lesson: String {
        guard valid else {
            return "Need ~20 s of beat-to-beat intervals from a chest strap to estimate the HRV spectrum."
        }
        let peakBpm = peakFrequencyHz * 60.0
        return String(
            format: "Coherence is the share of heart-rate-variability power gathered in one peak. "
                  + "Yours peaks at %.2f Hz (~%.0f cycles/min); breathing near 6/min concentrates power there.",
            peakFrequencyHz, peakBpm
        )
    }
}

// MARK: - HRVCoherence

public enum HRVCoherence {

    // Analysis grid & bands (Hz).
    static let gridStep = 0.0025
    static let gridMax = 0.40
    static let totalLow = 0.0033
    static let lfLow = 0.04, lfHigh = 0.15
    static let hfLow = 0.15, hfHigh = 0.40
    static let peakSearchLow = 0.04, peakSearchHigh = 0.26
    static let peakHalfWidth = 0.015

    /// Minimum intervals before a spectrum is attempted (~enough record length
    /// for a 0.04 Hz resolution at typical RR).
    static let minIntervals = 16

    // MARK: Public entry points

    /// Coherence via a single method.
    public static func compute(rrMs: [Double], method: HRVSpectralMethod) -> CoherenceReading {
        guard let (t, x) = tachogram(rrMs: rrMs) else { return .invalid }
        let freqs = analysisGrid()
        let power: [Double]
        switch method {
        case .lombScargle: power = lombScarglePower(times: t, values: x, freqs: freqs)
        case .welch:       power = welchPower(times: t, values: x, freqs: freqs)
        }
        return reading(from: PowerSpectrum(frequencies: freqs, power: power))
    }

    /// Coherence as a fader cross-fade between Welch (`blend` 0) and
    /// Lomb–Scargle (`blend` 1). Both spectra are estimated; the scalar
    /// outputs are linearly blended. The peak frequency follows the dominant
    /// method (blend ≥ 0.5 → Lomb–Scargle).
    ///
    /// ⛔ THE SHIPPED BLEND IS PERMANENTLY 1.0 ON BOTH BIO PATHS (#923): the camera passes the
    /// literal, and the strap passes `PolarH10BioPublisher.coherenceBlend`, which nothing under
    /// `Sources/` writes. So `mix` returns the Lomb–Scargle term alone on every shipped window.
    ///
    /// ⚠️ AND WELCH IS STILL NOT INERT, which is the half a reader skips. The `guard` below
    /// returns the WHOLE Welch reading when Lomb–Scargle is invalid and Welch is not — reachable
    /// by construction, because both go through `reading(from:)`, whose `total > 0` test is
    /// evaluated on DIFFERENT spectra of the same tachogram. Not demonstrated by any test here;
    /// "possible" is not "happens", and building a divergent RR series is its own slice.
    ///
    /// ⚠️ SO DO NOT SKIP THE WELCH ESTIMATE WHEN `b == 1` AS FREE PERFORMANCE. It is real work
    /// on the bio path and it is real waste on almost every window — but removing it also
    /// removes the rescue, which turns an occasional Welch answer into no answer. What an
    /// invalid Lomb–Scargle should produce is a DSP decision, not a tidy-up.
    /// Guard: `Tests/CISmoke/TheCoherenceBlendHasNoFaderTests`.
    public static func compute(rrMs: [Double], blend: Double = 1.0) -> CoherenceReading {
        let b = min(1.0, max(0.0, blend))
        let welch = compute(rrMs: rrMs, method: .welch)
        let lomb = compute(rrMs: rrMs, method: .lombScargle)
        guard welch.valid, lomb.valid else { return welch.valid ? welch : lomb }
        func mix(_ a: Float, _ c: Float) -> Float { a * Float(1.0 - b) + c * Float(b) }
        return CoherenceReading(
            coherence: mix(welch.coherence, lomb.coherence),
            peakFrequencyHz: b >= 0.5 ? lomb.peakFrequencyHz : welch.peakFrequencyHz,
            lfPower: mix(welch.lfPower, lomb.lfPower),
            hfPower: mix(welch.hfPower, lomb.hfPower),
            lfHfRatio: mix(welch.lfHfRatio, lomb.lfHfRatio),
            totalPower: mix(welch.totalPower, lomb.totalPower),
            valid: true
        )
    }

    /// Exposed for tests/visualisation: the raw spectrum for one method.
    public static func spectrum(rrMs: [Double], method: HRVSpectralMethod) -> PowerSpectrum? {
        guard let (t, x) = tachogram(rrMs: rrMs) else { return nil }
        let freqs = analysisGrid()
        let power: [Double]
        switch method {
        case .lombScargle: power = lombScarglePower(times: t, values: x, freqs: freqs)
        case .welch:       power = welchPower(times: t, values: x, freqs: freqs)
        }
        return PowerSpectrum(frequencies: freqs, power: power)
    }

    // MARK: Tachogram

    /// Build (time[s], value[ms]) from RR intervals: each RR value is sampled
    /// at the time that beat completes (cumulative sum). Drops non-finite and
    /// physiologically impossible intervals (RR outside 250–2000 ms = 30–240 bpm).
    static func tachogram(rrMs: [Double]) -> (times: [Double], values: [Double])? {
        var t = [Double]()
        var x = [Double]()
        var clock = 0.0
        t.reserveCapacity(rrMs.count)
        x.reserveCapacity(rrMs.count)
        for rr in rrMs where rr.isFinite && rr >= 250 && rr <= 2000 {
            clock += rr / 1000.0
            t.append(clock)
            x.append(rr)
        }
        guard x.count >= minIntervals else { return nil }
        return (t, x)
    }

    static func analysisGrid() -> [Double] {
        let count = Int((gridMax / gridStep).rounded())
        var f = [Double]()
        f.reserveCapacity(count)
        for k in 1...count { f.append(Double(k) * gridStep) }
        return f
    }

    // MARK: Lomb–Scargle

    static func lombScarglePower(times t: [Double], values x: [Double], freqs: [Double]) -> [Double] {
        let n = Double(x.count)
        let mean = x.reduce(0, +) / n
        let xc = x.map { $0 - mean }

        var power = [Double](repeating: 0, count: freqs.count)
        for (k, f) in freqs.enumerated() {
            let w = 2.0 * Double.pi * f
            guard w > 0 else { continue }

            var sumSin2 = 0.0, sumCos2 = 0.0
            for tj in t {
                sumSin2 += sin(2.0 * w * tj)
                sumCos2 += cos(2.0 * w * tj)
            }
            let tau = atan2(sumSin2, sumCos2) / (2.0 * w)

            var xcCos = 0.0, xsSin = 0.0, cc = 0.0, ss = 0.0
            for j in 0..<x.count {
                let arg = w * (t[j] - tau)
                let c = cos(arg), s = sin(arg)
                xcCos += xc[j] * c
                xsSin += xc[j] * s
                cc += c * c
                ss += s * s
            }
            let term1 = cc > 0 ? (xcCos * xcCos) / cc : 0
            let term2 = ss > 0 ? (xsSin * xsSin) / ss : 0
            power[k] = 0.5 * (term1 + term2)
        }
        return power
    }

    // MARK: Welch (resample → Hann → DFT)

    static func welchPower(times t: [Double], values x: [Double], freqs: [Double], fs: Double = 4.0) -> [Double] {
        guard let t0 = t.first, let tEnd = t.last, tEnd > t0 else {
            return [Double](repeating: 0, count: freqs.count)
        }
        let dt = 1.0 / fs
        let m = Int((tEnd - t0) / dt) + 1
        guard m >= 8 else { return [Double](repeating: 0, count: freqs.count) }

        // Linear interpolation onto the uniform grid.
        var ux = [Double](repeating: 0, count: m)
        var idx = 0
        for i in 0..<m {
            let tt = t0 + Double(i) * dt
            while idx < t.count - 2 && t[idx + 1] < tt { idx += 1 }
            let ta = t[idx], tb = t[idx + 1]
            let frac = tb > ta ? (tt - ta) / (tb - ta) : 0
            ux[i] = x[idx] + (x[idx + 1] - x[idx]) * frac
        }

        // Remove mean (detrend DC; the Hann window handles edge leakage).
        let mean = ux.reduce(0, +) / Double(m)
        for i in 0..<m { ux[i] -= mean }

        // Hann window + its power for PSD normalization.
        var win = [Double](repeating: 0, count: m)
        var winPow = 0.0
        let denom = Double(m - 1)
        for i in 0..<m {
            let wv = 0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / denom)
            win[i] = wv
            winPow += wv * wv
        }
        let norm = fs * winPow

        var power = [Double](repeating: 0, count: freqs.count)
        for (k, f) in freqs.enumerated() {
            let w = 2.0 * Double.pi * f
            var re = 0.0, im = 0.0
            for i in 0..<m {
                let arg = w * Double(i) * dt
                let v = ux[i] * win[i]
                re += v * cos(arg)
                im -= v * sin(arg)
            }
            power[k] = norm > 0 ? (re * re + im * im) / norm : 0
        }
        return power
    }

    // MARK: Bands → reading

    static func reading(from spectrum: PowerSpectrum) -> CoherenceReading {
        let f = spectrum.frequencies, p = spectrum.power
        guard f.count == p.count, !f.isEmpty else { return .invalid }

        func bandSum(_ lo: Double, _ hi: Double) -> Double {
            var s = 0.0
            for i in 0..<f.count where f[i] >= lo && f[i] < hi { s += p[i] }
            return s
        }

        let total = bandSum(totalLow, gridMax + gridStep)
        guard total > 0, total.isFinite else { return .invalid }

        let lf = bandSum(lfLow, lfHigh)
        let hf = bandSum(hfLow, hfHigh)

        var peakF = 0.1, peakP = -1.0
        for i in 0..<f.count where f[i] >= peakSearchLow && f[i] <= peakSearchHigh {
            if p[i] > peakP { peakP = p[i]; peakF = f[i] }
        }

        let peakBand = bandSum(peakF - peakHalfWidth, peakF + peakHalfWidth + gridStep)
        let coh = max(0.0, min(1.0, peakBand / total))
        let lfhf = hf > 0 ? lf / hf : 0

        return CoherenceReading(
            coherence: Float(coh),
            peakFrequencyHz: Float(peakF),
            lfPower: Float(lf),
            hfPower: Float(hf),
            lfHfRatio: Float(lfhf),
            totalPower: Float(total),
            valid: true
        )
    }
}
