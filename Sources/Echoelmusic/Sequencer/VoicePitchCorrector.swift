//
//  VoicePitchCorrector.swift
//  Echoelmusic — DSP (Voice Live VL1+VL2, the Syng legacy)
//
//  Pure pitch-correction ("Autotune") and scale-harmony maths for a live
//  voice/instrument input. PitchTracker (YIN) detects the fundamental; this
//  turns it into a correction RATIO for a pitch shifter and into scale-true
//  harmony intervals for EchoelHarmonizer. No audio I/O, no allocation
//  beyond value types — fully unit-tested on every platform.
//
//  The Echoel edge over every market autotune: the key is not GUESSED from
//  the signal — the instrument KNOWS it (MusicalKey drives the composer),
//  and the correction grid is Kammerton-true (A4 = 432/440/… — the target
//  frequencies move with the session's a4Hz, not a hardcoded 440).
//
//  Retune behaviour: `retuneSpeed` 1 = instant hard snap (the classic
//  quantized-vocal effect), 0 = very slow drift (natural). Smoothing is a
//  one-pole low-pass on the correction in CENTS, stepped with an explicit
//  `dt` so behaviour is deterministic and testable (no wall clock).
//
//  Consumers (VL3, device-gated): mic tap → PitchTracker window →
//  process(detectedHz:dt:) → ratio into a delay-line shifter;
//  harmonyIntervals(...) → EchoelHarmonizer.interval1/2 (control-plane).
//

import Foundation

/// One frame of correction output.
public struct VoicePitchCorrection: Sendable, Equatable {
    /// Multiply the signal's pitch by this (1 = no change).
    public let ratio: Float
    /// The in-key target MIDI note (nil while unvoiced).
    public let targetMidi: Int?
    /// The target frequency in Hz at the session Kammerton (nil while unvoiced).
    public let targetHz: Double?
    /// The correction currently applied, in cents (smoothed).
    public let appliedCents: Double

    public static let bypass = VoicePitchCorrection(ratio: 1, targetMidi: nil,
                                                    targetHz: nil, appliedCents: 0)
}

/// Deterministic, allocation-free pitch-correction state machine (VL1).
public struct VoicePitchCorrector: Sendable {

    /// The key the correction snaps into (the session's Tonart).
    public var key: MusicalKey
    /// Session Kammerton — the A4 reference the target grid is built on.
    public var a4Hz: Double
    /// 0 = off (ratio 1), 1 = full correction to the in-key target.
    public var strength: Double
    /// 1 = instant snap, 0 = slowest drift. See header.
    public var retuneSpeed: Double

    /// Smoothed correction in cents (the one-pole state).
    private var smoothedCents: Double = 0

    public init(key: MusicalKey = MusicalKey(),
                a4Hz: Double = 440,
                strength: Double = 1,
                retuneSpeed: Double = 1) {
        self.key = key
        self.a4Hz = a4Hz.isFinite && a4Hz > 0 ? a4Hz : 440
        self.strength = strength.isFinite ? min(max(strength, 0), 1) : 1
        self.retuneSpeed = retuneSpeed.isFinite ? min(max(retuneSpeed, 0), 1) : 1
        self.key = key
    }

    /// Advance one analysis frame. `detectedHz` nil/<=0 = unvoiced (the
    /// correction relaxes toward bypass); `dt` = seconds since last frame.
    public mutating func process(detectedHz: Double?, dt: Double) -> VoicePitchCorrection {
        let safeDt = (dt.isFinite && dt > 0) ? dt : 0.01
        guard let f = detectedHz, f.isFinite, f > 0,
              a4Hz.isFinite, a4Hz > 0 else {
            // Unvoiced: relax the applied correction toward zero so the next
            // voiced onset doesn't inherit a stale bend.
            smoothedCents += smoothingAlpha(dt: safeDt) * (0 - smoothedCents)
            if abs(smoothedCents) < 0.01 { smoothedCents = 0 }
            return VoicePitchCorrection(ratio: ratioFromCents(smoothedCents),
                                        targetMidi: nil, targetHz: nil,
                                        appliedCents: smoothedCents)
        }

        // Hz → fractional MIDI on the session's Kammerton grid.
        let fracMidi = 69.0 + 12.0 * log2(f / a4Hz)
        guard fracMidi.isFinite, fracMidi > 0, fracMidi < 128 else {
            return VoicePitchCorrection(ratio: 1, targetMidi: nil, targetHz: nil,
                                        appliedCents: smoothedCents)
        }

        let target = Self.nearestInKeyMidi(to: fracMidi, key: key)
        let desiredCents = (Double(target) - fracMidi) * 100.0 * strength
        smoothedCents += smoothingAlpha(dt: safeDt) * (desiredCents - smoothedCents)

        let targetHz = a4Hz * pow(2.0, (Double(target) - 69.0) / 12.0)
        return VoicePitchCorrection(ratio: ratioFromCents(smoothedCents),
                                    targetMidi: target,
                                    targetHz: targetHz,
                                    appliedCents: smoothedCents)
    }

    /// Reset the smoothing state (e.g. when the input source changes).
    public mutating func reset() { smoothedCents = 0 }

    // MARK: - Pure helpers (exposed for tests)

    /// The in-key MIDI note nearest to a fractional MIDI pitch. Ties resolve
    /// to the LOWER note (deterministic, mirrors MusicalKey.quantize).
    public static func nearestInKeyMidi(to fracMidi: Double, key: MusicalKey) -> Int {
        let center = Int(fracMidi.rounded())
        var best = center
        var bestDist = Double.infinity
        // ±7 semitones always contains an in-key note for every shipped scale.
        for candidate in (center - 7)...(center + 7) where key.contains(candidate) {
            let dist = abs(Double(candidate) - fracMidi)
            if dist < bestDist - 1e-9 ||
               (abs(dist - bestDist) <= 1e-9 && candidate < best) {
                best = candidate
                bestDist = dist
            }
        }
        return best
    }

    private func smoothingAlpha(dt: Double) -> Double {
        if retuneSpeed >= 1 { return 1 }
        // Time constant: speed 0 → ~350 ms drift, approaching 0 s at speed 1.
        let tau = 0.35 * (1.0 - retuneSpeed) + 0.002
        return 1.0 - exp(-dt / tau)
    }

    private func ratioFromCents(_ cents: Double) -> Float {
        let r = pow(2.0, cents / 1200.0)
        return r.isFinite ? Float(r) : 1
    }
}

// MARK: - VL2: scale-true harmony intervals (feeds EchoelHarmonizer)

/// Diatonic harmony maths: given the note a performer is singing, what are
/// the semitone offsets to the voices N scale-degrees above? Unlike the
/// fixed-interval harmonizer default (always +4/+7), these intervals breathe
/// with the key — a third above E in C major is G (+3), not G# (+4).
public enum VoiceHarmony {

    /// Semitone offset to the note `degreesUp` scale degrees above `midi`,
    /// in `key`. `midi` is quantized into the key first and the offset is
    /// measured FROM THE QUANTIZED note (in the VL3 chain the corrector
    /// snaps the voice before the harmonizer reads these intervals).
    /// `degreesUp` may be negative (harmony below).
    public static func interval(from midi: Int, degreesUp: Int, key: MusicalKey) -> Int {
        let snapped = key.quantize(midi)
        guard let index = degreeIndex(of: snapped, key: key) else { return 0 }
        // Recover the octave so that key.degree(index, octave:) == snapped,
        // then step the degree ladder. (snapped − root − interval) is an
        // exact multiple of 12 by construction.
        let rel = key.scale.intervals[index]
        let octave = (snapped - key.root - rel) / 12 - 1
        return key.degree(index + degreesUp, octave: octave) - snapped
    }

    /// Degree index (0-based, octave-relative) of an in-key MIDI note, or nil
    /// when the note's pitch class is outside the key.
    static func degreeIndex(of midi: Int, key: MusicalKey) -> Int? {
        let pc = ((midi % 12) + 12) % 12
        let relative = ((pc - key.root) % 12 + 12) % 12
        return key.scale.intervals.firstIndex(of: relative)
    }
}
