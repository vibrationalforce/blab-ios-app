//
//  BioSignalDeconvolver.swift
//  Echoelmusic — Protected DSP Component
//
//  First DSP block that touches raw biosignal samples. Performs:
//    1. Detrend  — single biquad highpass to remove DC offset and
//                  slow baseline drift
//    2. Notch    — single biquad bandstop at the mains frequency
//                  (50 Hz EU / 60 Hz US, configurable per init)
//    3. Validate — marks each output sample as .recovering during
//                  the warmup window, .corrupt on saturation, .valid
//                  otherwise
//
//  Per-sensor bandpass shaping (PPG 0.5-4 Hz, ECG 0.5-40 Hz, EEG
//  1-45 Hz, accelerometer 0.1 Hz) is a follow-up sub-cycle —
//  detrend + notch is the bedrock the SKILL.md contract anchors on.
//
//  Pure value type. All members nonisolated. process(_:) is
//  allocation-free and lock-free; safe to call from any thread
//  including the audio render thread.
//
//  See .claude/skills/BioSignalDeconvolver/SKILL.md for caller-side
//  conventions, validity-flag handling, and the do/do-not list.
//

import Foundation

// MARK: - Sensor presets

public enum BioSensorPreset: Sendable {
    /// Photoplethysmography — fingertip / wrist optical HR.
    case ppg
    /// Electrocardiography — chest strap (e.g. Polar H10).
    case ecg
    /// Electroencephalography — scalp electrodes.
    case eeg
    /// Accelerometer — motion energy channel.
    case accelerometer
}

// MARK: - Validity

public enum BioValidity: UInt8, Sendable, Equatable {
    /// Filter is still settling. Output may not be trustworthy.
    case recovering = 0
    /// Output is within expected range, no saturation, post-warmup.
    case valid = 1
    /// Saturated input, electrode dropout, or out-of-range value.
    case corrupt = 2
}

// MARK: - Cleaned sample

public struct CleanedSample: Sendable, Equatable {
    public let value: Float
    public let validity: BioValidity

    public init(value: Float, validity: BioValidity) {
        self.value = value
        self.validity = validity
    }
}

// MARK: - Deconvolver

public struct BioSignalDeconvolver {

    public let preset: BioSensorPreset
    public let sampleRate: Double
    public let mainsFrequency: Double

    /// Threshold above which an input sample is flagged corrupt.
    /// Input is expected in roughly normalized units; 0.95 leaves
    /// headroom for ECG R-spikes.
    public let saturationThreshold: Float

    private var detrendStage: BiquadStage
    private var notchStage: BiquadStage

    private var samplesSeen: UInt64 = 0
    private let warmupSamples: UInt64

    public init(
        preset: BioSensorPreset,
        sampleRate: Double,
        mainsFrequency: Double = 50.0,
        saturationThreshold: Float = 0.95
    ) {
        self.preset = preset
        self.sampleRate = sampleRate
        self.mainsFrequency = mainsFrequency
        self.saturationThreshold = saturationThreshold

        // 1 s warmup is enough for a 0.3 Hz HP biquad to settle to
        // ~0.4 % residual; pick the larger of 1 s or 4 cycles of the
        // detrend cutoff.
        let detrendCutoff = Self.detrendCutoff(for: preset)
        let warmup = max(sampleRate, 4.0 / detrendCutoff)
        self.warmupSamples = UInt64(warmup.rounded())

        self.detrendStage = .highpass(
            cutoff: detrendCutoff,
            sampleRate: sampleRate,
            q: 0.707
        )
        self.notchStage = .notch(
            center: mainsFrequency,
            sampleRate: sampleRate,
            q: 30.0
        )
    }

    /// Single-sample processing. Returns the cleaned value plus a
    /// per-sample validity flag. Idempotent in the sense that two
    /// `process` calls with the same input on the same state
    /// produce the same output — but the deconvolver is stateful;
    /// you cannot replay a sample.
    public mutating func process(_ x: Float) -> CleanedSample {
        samplesSeen &+= 1

        // 1. Detrend (HP) and 2. mains notch in series.
        let detrended = detrendStage.process(x)
        let cleaned = notchStage.process(detrended)

        // 3. Validity flag.
        let validity: BioValidity
        if samplesSeen < warmupSamples {
            validity = .recovering
        } else if !x.isFinite || abs(x) > saturationThreshold {
            validity = .corrupt
        } else {
            validity = .valid
        }

        return CleanedSample(value: cleaned, validity: validity)
    }

    public mutating func reset() {
        detrendStage.reset()
        notchStage.reset()
        samplesSeen = 0
    }

    // MARK: - Preset-driven cutoffs

    /// Detrend high-pass cutoff per sensor type. Tight enough to
    /// strip electrode drift, loose enough to preserve the
    /// fundamental of the physiological signal.
    public static func detrendCutoff(for preset: BioSensorPreset) -> Double {
        switch preset {
        case .ppg:           return 0.5
        case .ecg:           return 0.5
        case .eeg:           return 1.0
        case .accelerometer: return 0.1
        }
    }
}

// MARK: - Biquad (Direct Form II Transposed, RBJ Audio EQ Cookbook)

/// Single biquad section. Public for tests; the contract for
/// callers is `BioSignalDeconvolver.process(_:)`.
public struct BiquadStage: Sendable, Equatable {

    // Normalized coefficients (a0 == 1).
    public let b0: Float
    public let b1: Float
    public let b2: Float
    public let a1: Float
    public let a2: Float

    // Internal state for Direct Form II Transposed.
    public var z1: Float = 0
    public var z2: Float = 0

    public init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }

    // MARK: - RBJ designs

    public static func highpass(cutoff: Double, sampleRate: Double, q: Double) -> BiquadStage {
        let omega = 2 * .pi * cutoff / sampleRate
        let cosO = cos(omega)
        let sinO = sin(omega)
        let alpha = sinO / (2 * q)
        let a0 = 1 + alpha
        let b0 = Float((1 + cosO) / 2 / a0)
        let b1 = Float(-(1 + cosO) / a0)
        let b2 = Float((1 + cosO) / 2 / a0)
        let a1 = Float(-2 * cosO / a0)
        let a2 = Float((1 - alpha) / a0)
        return BiquadStage(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    public static func notch(center: Double, sampleRate: Double, q: Double) -> BiquadStage {
        let omega = 2 * .pi * center / sampleRate
        let cosO = cos(omega)
        let sinO = sin(omega)
        let alpha = sinO / (2 * q)
        let a0 = 1 + alpha
        let b0 = Float(1 / a0)
        let b1 = Float(-2 * cosO / a0)
        let b2 = Float(1 / a0)
        let a1 = Float(-2 * cosO / a0)
        let a2 = Float((1 - alpha) / a0)
        return BiquadStage(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
}
