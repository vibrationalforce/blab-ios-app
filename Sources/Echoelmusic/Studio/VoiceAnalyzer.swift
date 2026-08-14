//
//  VoiceAnalyzer.swift
//  Echoelmusic — Studio (voice → audiovisual)
//
//  The pure analyser that turns a mono audio window into one `VoiceFrame` — the
//  missing INPUT half of the audiovisual vocoder (VocoderCore holds the mapping,
//  this finds pitch / loudness / timbre). Kept pure (Foundation only, no AVFoundation,
//  no Accelerate) so it is fully unit-tested on every platform and stays trustworthy;
//  the mic wiring EXISTS since #592a: `VoiceCaptureEngine` constructs this analyser
//  and feeds it real 4096-sample windows behind the Voice-timbre door. (⛔ This line
//  called that wiring a future "thin step on top" for months after it shipped.)
//
//  Method (robust + cheap enough for a ~30–60 Hz control-rate call OFF the audio
//  thread — never call this from a render block):
//   • Pitch (F0) via normalized autocorrelation over the vocal band, with parabolic
//     interpolation for sub-sample lag resolution; voicing decided by the
//     autocorrelation strength AND an energy gate (so silence/noise read unvoiced).
//   • Loudness via RMS mapped from dBFS to 0…1 over a musical window.
//   • Brightness via zero-crossing rate as a spectral-centroid PROXY (honest: a true
//     centroid needs an FFT; ZCR tracks brightness well and stays Accelerate-free so
//     the core is Linux-testable). Normalised against a vocal brightness ceiling.
//

import Foundation

public struct VoiceAnalyzer: Sendable {

    /// dBFS at which loudness reads 0 (quiet floor) and 1 (full). Mapping is linear
    /// in dB between them — perceptually even, unlike raw RMS.
    public var floorDB: Double = -50
    public var ceilDB: Double = -10
    /// Brightness ceiling in Hz for the zero-crossing proxy (≈ a bright vocal/sibilant).
    public var brightnessCeilingHz: Double = 4000
    /// Minimum autocorrelation strength (peak ÷ zero-lag energy) to call a window voiced.
    public var voicingStrength: Double = 0.30

    public init() {}

    /// Analyse a mono window → `VoiceFrame`. `samples` need not be DC-free (the mean
    /// is removed here). `sampleRate` is the TRUE audio rate (44100/48000…).
    public func analyze(_ samples: [Float], sampleRate: Double,
                        minF0: Double = 70, maxF0: Double = 500,
                        timestamp: Double = 0) -> VoiceFrame {
        let n = samples.count
        guard n >= 32, sampleRate > 1, maxF0 > minF0 else { return .silent }

        // — Loudness (RMS → dBFS → 0…1) —
        var sumSq = 0.0
        for v in samples { sumSq += Double(v) * Double(v) }
        let rms = (sumSq / Double(n)).squareRoot()
        let energy = energy01(rms)

        // — Mean-remove for pitch + brightness (a DC bias skews both) —
        var mean = 0.0
        for v in samples { mean += Double(v) }
        mean /= Double(n)
        let x = samples.map { Double($0) - mean }

        // — Brightness (zero-crossing rate proxy) —
        let brightness = brightness01(x, sampleRate: sampleRate)

        // — Pitch (normalized autocorrelation over the vocal band) —
        let pitch = dominantF0(x, sampleRate: sampleRate, minF0: minF0, maxF0: maxF0)

        // Voicing: a clear periodicity AND enough energy. Either alone is unreliable
        // (loud noise has energy but no period; a quiet hum has period but no level).
        let voiced = pitch != nil && energy > clamp01(energyForGate)
        return VoiceFrame(pitchHz: pitch?.hz ?? 0, voiced: voiced,
                          energy: energy, brightness: brightness, timestamp: timestamp)
    }

    // MARK: - Pure stages

    /// dBFS → 0…1 over [floorDB, ceilDB]; 0 for silence.
    func energy01(_ rms: Double) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20.0 * log10(rms)
        return clamp01((db - floorDB) / (ceilDB - floorDB))
    }

    /// The energy a window must exceed to be considered voiced — a hair above the
    /// floor so room tone alone never voices.
    private var energyForGate: Double { 0.04 }

    /// Zero-crossing rate → approximate spectral brightness, normalised 0…1.
    func brightness01(_ x: [Double], sampleRate: Double) -> Double {
        guard x.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<x.count where (x[i] >= 0) != (x[i - 1] >= 0) { crossings += 1 }
        // crossings over the window → crossings/sec; a sinusoid crosses twice per cycle,
        // so freq ≈ rate/2.
        let seconds = Double(x.count) / sampleRate
        guard seconds > 0 else { return 0 }
        let approxHz = (Double(crossings) / seconds) / 2.0
        return clamp01(approxHz / brightnessCeilingHz)
    }

    /// Dominant fundamental via normalized autocorrelation, or nil if the window is
    /// flat / aperiodic / out of band. Mirrors PulsePeriodEstimator but in the audio
    /// (Hz) band rather than the pulse (BPM) band.
    func dominantF0(_ x: [Double], sampleRate: Double,
                    minF0: Double, maxF0: Double) -> (hz: Double, strength: Double)? {
        let n = x.count
        var energy = 0.0
        for v in x { energy += v * v }
        guard energy > 1e-12 else { return nil }

        let minLag = max(1, Int(sampleRate / maxF0))
        let maxLag = min(n - 1, Int(sampleRate / minF0))
        guard maxLag > minLag else { return nil }

        var corr = [Double](repeating: 0, count: maxLag + 1)
        var bestLag = -1
        var bestCorr = 0.0
        for lag in minLag...maxLag {
            var c = 0.0
            var i = lag
            while i < n { c += x[i] * x[i - lag]; i += 1 }
            corr[lag] = c
            if c > bestCorr { bestCorr = c; bestLag = lag }
        }
        guard bestLag > 0, bestCorr > 0 else { return nil }

        let strength = clamp01(bestCorr / energy)
        guard strength >= voicingStrength else { return nil }

        // Parabolic interpolation around the peak (one lag step is several Hz).
        var lagF = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            let ym = corr[bestLag - 1], y0 = corr[bestLag], yp = corr[bestLag + 1]
            let denom = ym - 2 * y0 + yp
            if denom != 0 { lagF = Double(bestLag) + 0.5 * (ym - yp) / denom }
        }
        guard lagF > 0 else { return nil }

        let hz = sampleRate / lagF
        guard hz >= minF0 && hz <= maxF0 else { return nil }
        return (hz, strength)
    }
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
