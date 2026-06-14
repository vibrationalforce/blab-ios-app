//
//  EchoelReverb.swift
//  Echoelmusic — DSP
//
//  Compact stereo algorithmic reverb (Freeverb topology: 8 parallel damped
//  comb filters → 4 series all-pass filters, per channel, with a stereo spread
//  offset on the right channel so the two channels decorrelate into a wide,
//  lush tail). This is the *bus* reverb: one shared, wide space for the whole
//  polyphonic mix, replacing the old per-voice mono convolution (which was both
//  narrow and CPU-wasteful — one convolution per active voice).
//
//  Audio-thread rules (CLAUDE.md): all delay lines are pre-allocated in `init`;
//  `processStereo` only does index access + arithmetic on Float storage — no
//  allocation, no locks, no ObjC, no I/O. Parameters are Float/Int atomic-width
//  so the control plane may set them while the audio thread reads them (worst
//  case: one block of slightly-stale coefficients).
//

import Foundation

/// Stereo Freeverb-style reverb. Set `mix`/`roomSize`/`damping`/`width` from the
/// control plane; call `processStereo` per sample on the audio thread.
public final class EchoelReverb: @unchecked Sendable {

    // Freeverb tuning (samples @ 44.1 kHz); scaled to the actual sample rate.
    private static let combTuning: [Int] = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTuning: [Int] = [556, 441, 341, 225]
    private static let stereoSpread = 23
    private static let fixedGain: Float = 0.015

    // MARK: - Parameters (control plane → audio thread; atomic-width)

    /// Wet/dry blend [0…1]. 0 = fully dry (the stage still costs nothing extra
    /// when `mix <= 0` — the chain skips it).
    public var mix: Float = 0.25
    /// Tail length [0…1]. Maps to comb feedback (longer = more sustain).
    public var roomSize: Float = 0.72 { didSet { updateFeedback() } }
    /// High-frequency absorption [0…1]. Higher = darker, more natural tail.
    public var damping: Float = 0.45 { didSet { updateDamping() } }
    /// Stereo width of the wet signal [0…1]. 1 = fully decorrelated L/R.
    public var width: Float = 1.0

    // MARK: - Comb filters (8 per channel)

    private final class Comb {
        var buffer: [Float]
        var index: Int = 0
        var filterStore: Float = 0
        var feedback: Float = 0.84
        var damp1: Float = 0.2
        var damp2: Float = 0.8
        init(size: Int) { buffer = [Float](repeating: 0, count: max(1, size)) }

        @inline(__always)
        func process(_ input: Float) -> Float {
            let output = buffer[index]
            // One-pole low-pass in the feedback path (the "damping").
            filterStore = output * damp2 + filterStore * damp1
            buffer[index] = input + filterStore * feedback
            index += 1
            if index >= buffer.count { index = 0 }
            return output
        }
        func reset() { for i in 0..<buffer.count { buffer[i] = 0 }; filterStore = 0; index = 0 }
    }

    // MARK: - All-pass filters (4 per channel)

    private final class Allpass {
        var buffer: [Float]
        var index: Int = 0
        let feedback: Float = 0.5
        init(size: Int) { buffer = [Float](repeating: 0, count: max(1, size)) }

        @inline(__always)
        func process(_ input: Float) -> Float {
            let bufout = buffer[index]
            let output = -input + bufout
            buffer[index] = input + bufout * feedback
            index += 1
            if index >= buffer.count { index = 0 }
            return output
        }
        func reset() { for i in 0..<buffer.count { buffer[i] = 0 }; index = 0 }
    }

    private var combsL: [Comb]
    private var combsR: [Comb]
    private var allpassL: [Allpass]
    private var allpassR: [Allpass]

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        let scale = sampleRate / 44100.0
        func s(_ n: Int) -> Int { max(1, Int(Float(n) * scale)) }

        combsL = Self.combTuning.map { Comb(size: s($0)) }
        combsR = Self.combTuning.map { Comb(size: s($0 + Self.stereoSpread)) }
        allpassL = Self.allpassTuning.map { Allpass(size: s($0)) }
        allpassR = Self.allpassTuning.map { Allpass(size: s($0 + Self.stereoSpread)) }

        updateFeedback()
        updateDamping()
    }

    private func updateFeedback() {
        let fb = roomSize * 0.28 + 0.7   // Freeverb: 0.7…0.98
        for c in combsL { c.feedback = fb }
        for c in combsR { c.feedback = fb }
    }

    private func updateDamping() {
        let d1 = damping * 0.4            // Freeverb scales damping by 0.4
        let d2 = 1.0 - d1
        for c in combsL { c.damp1 = d1; c.damp2 = d2 }
        for c in combsR { c.damp1 = d1; c.damp2 = d2 }
    }

    // MARK: - Process (audio thread)

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let m = mix
        if m <= 0 { return (inL, inR) }

        // Mono send into the reverb (Freeverb sums the input).
        let input = (inL + inR) * Self.fixedGain

        var wetL: Float = 0
        var wetR: Float = 0
        // Parallel damped combs.
        for i in 0..<combsL.count {
            wetL += combsL[i].process(input)
            wetR += combsR[i].process(input)
        }
        // Series all-pass diffusion.
        for i in 0..<allpassL.count {
            wetL = allpassL[i].process(wetL)
            wetR = allpassR[i].process(wetR)
        }

        // Stereo width: blend each channel toward the other as width → 0.
        let w = width
        let wet1 = w * 0.5 + 0.5          // this-channel gain
        let wet2 = (1.0 - w) * 0.5        // cross-feed gain
        let outWetL = wetL * wet1 + wetR * wet2
        let outWetR = wetR * wet1 + wetL * wet2

        let dry = 1.0 - m
        return (inL * dry + outWetL * m, inR * dry + outWetR * m)
    }

    public func reset() {
        for c in combsL { c.reset() }
        for c in combsR { c.reset() }
        for a in allpassL { a.reset() }
        for a in allpassR { a.reset() }
    }
}
