// TuningDetector.swift
// Echoel — hear the room, find the tuning. Given a set of detected fundamental
// frequencies (Hz) from the mic/voice (MicrophoneManager.pitch / .frequency), this
// pure analysis estimates:
//   • the Kammerton (concert-pitch A4) the source is tuned to, from the circular
//     mean of each note's cents-deviation to the nearest 12-TET pitch, and
//   • the musical key (root + major/minor) via Krumhansl–Kessler key-finding
//     (Pearson correlation of a pitch-class histogram against the 24 key profiles).
//
// Pure value math (no AVFoundation/Accelerate) so it is fully unit-tested on every
// platform — the trustworthy brain behind "listen → suggest tuning + key", mirroring
// how PulsePeriodEstimator backs the rPPG path. Genre/style/character are NOT guessed
// from audio here (that would be a stub); the UI lets the user confirm those when
// saving a preset.

import Foundation

public struct DetectedTuning: Sendable, Equatable {
    /// Best-fit concert pitch (A4) in Hz, e.g. ≈432 or ≈440.
    public var a4Hz: Double
    /// Tonic pitch class, 0 = C … 11 = B.
    public var keyRoot: Int
    /// Major vs natural-minor key.
    public var isMinor: Bool
    /// Key-finding correlation strength, 0…1 (higher = clearer key).
    public var confidence: Double
    /// Global tuning offset vs A4=440, in cents (informational; −31.8 ≈ 432 Hz).
    public var centsOffset: Double
    /// How many valid pitches informed the estimate.
    public var sampleCount: Int

    public init(a4Hz: Double, keyRoot: Int, isMinor: Bool,
                confidence: Double, centsOffset: Double, sampleCount: Int) {
        self.a4Hz = a4Hz; self.keyRoot = keyRoot; self.isMinor = isMinor
        self.confidence = confidence; self.centsOffset = centsOffset; self.sampleCount = sampleCount
    }

    /// "A minor", "C♯ major" … from keyRoot + isMinor.
    public var keyName: String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let r = ((keyRoot % 12) + 12) % 12
        return "\(names[r]) \(isMinor ? "minor" : "major")"
    }

    /// Snap a4 to the nearest standard Kammerton preset when within `tolHz`, else keep.
    public func snappedA4(tolHz: Double = 1.5) -> Double {
        let nearest = TuningReference.presets.min(by: { abs($0 - a4Hz) < abs($1 - a4Hz) }) ?? a4Hz
        return abs(nearest - a4Hz) <= tolHz ? nearest : a4Hz
    }
}

public struct TuningDetector {

    public init() {}

    // Krumhansl–Kessler probe-tone profiles (tonic-relative).
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Analyse detected fundamentals. Returns nil if there isn't enough evidence.
    public func analyze(frequencies: [Double], minHz: Double = 50, maxHz: Double = 2000,
                        minSamples: Int = 8) -> DetectedTuning? {
        let valid = frequencies.filter { $0.isFinite && $0 >= minHz && $0 <= maxHz }
        guard valid.count >= minSamples else { return nil }

        // 1) Kammerton: each pitch's signed cents-deviation to the nearest 12-TET note
        //    at A4=440, then the CIRCULAR mean (period = 100 cents) so the estimate is
        //    robust near the ±50-cent wrap.
        var sumSin = 0.0, sumCos = 0.0
        for f in valid {
            let midiCont = 69.0 + 12.0 * log2(f / 440.0)
            let cents = (midiCont - midiCont.rounded()) * 100.0     // (−50, 50]
            let theta = cents / 100.0 * 2.0 * .pi
            sumSin += sin(theta); sumCos += cos(theta)
        }
        let meanTheta = atan2(sumSin, sumCos)
        let offsetCents = meanTheta / (2.0 * .pi) * 100.0           // (−50, 50]
        let a4 = 440.0 * pow(2.0, offsetCents / 1200.0)

        // 2) Pitch-class histogram at the DETECTED tuning, so off-tuning notes still
        //    land in the correct class.
        var hist = [Double](repeating: 0, count: 12)
        for f in valid {
            let midiCont = 69.0 + 12.0 * log2(f / a4)
            let pc = ((Int(midiCont.rounded()) % 12) + 12) % 12
            hist[pc] += 1
        }

        // 3) Krumhansl key-finding: best Pearson correlation over the 24 keys.
        var bestRoot = 0, bestMinor = false, bestCorr = -2.0
        for root in 0..<12 {
            let cMaj = Self.correlation(hist, Self.rotated(Self.majorProfile, by: root))
            if cMaj > bestCorr { bestCorr = cMaj; bestRoot = root; bestMinor = false }
            let cMin = Self.correlation(hist, Self.rotated(Self.minorProfile, by: root))
            if cMin > bestCorr { bestCorr = cMin; bestRoot = root; bestMinor = true }
        }

        return DetectedTuning(
            a4Hz: (a4 * 100).rounded() / 100,
            keyRoot: bestRoot, isMinor: bestMinor,
            confidence: max(0, min(1, bestCorr)),
            centsOffset: (offsetCents * 10).rounded() / 10,
            sampleCount: valid.count
        )
    }

    // MARK: - Pure helpers

    /// profile rotated so its tonic (index 0) lands on pitch class `root`.
    static func rotated(_ profile: [Double], by root: Int) -> [Double] {
        (0..<12).map { profile[(($0 - root) % 12 + 12) % 12] }
    }

    /// Pearson correlation of two 12-length vectors (0 when either is flat).
    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            let xa = a[i] - ma, xb = b[i] - mb
            num += xa * xb; da += xa * xa; db += xb * xb
        }
        let denom = (da * db).squareRoot()
        return denom > 1e-9 ? num / denom : 0
    }
}
