//
//  BioEventGraph.swift
//  Echoelmusic — Protected DSP Component
//
//  Graph-based discrete-event detection over continuous biosignals.
//  Continuous samples flow in (cleaned heart signal, breath phase,
//  motion energy); discrete timestamped BioEvent values flow out.
//
//  Detector nodes implemented in this first version:
//    - heartbeat        adaptive-threshold peak detector with
//                       refractory period; aux = inter-beat interval (ms)
//    - breath onsets    phase-marker node on the [0..1] breath phase
//                       (0.5 crossing = inhale onset, wrap 1→0 = exhale
//                       onset, per BioSampleFrame phase convention)
//    - motion peak      threshold crossing on motion energy
//
//  eeg.{band}.burst and coherence.shift detectors are reserved for a
//  follow-up sub-cycle (need EEG band power and a coherence trend
//  input the bus does not yet carry).
//
//  Pure value type. process(...) is allocation-light (returns a small
//  fixed-capacity array), lock-free, and safe to call from any thread.
//  Per SKILL.md the component is READ-ONLY after this commit.
//
//  Emits the BioEvent value type defined in EngineBus.swift; callers
//  subscribe via EngineBus.bioEvents — they do not call detector nodes
//  directly.
//

import Foundation

public struct BioEventGraph {

    public let sampleRate: Double

    private var heartbeat: HeartbeatDetector
    private var breath: BreathPhaseDetector
    private var motion: MotionPeakDetector

    public init(sampleRate: Double, mainsFrequency: Double = 50.0) {
        self.sampleRate = sampleRate
        self.heartbeat = HeartbeatDetector(sampleRate: sampleRate)
        self.breath = BreathPhaseDetector()
        self.motion = MotionPeakDetector()
    }

    /// Feed one multi-channel sample. Returns 0+ events detected at this
    /// instant. `cleanedHeart` should be the BioSignalDeconvolver output
    /// (detrended, notched). `breathPhase` is [0..1]. `motionEnergy` is
    /// [0..1]. `timestamp` is the sample's wall/host time in seconds.
    public mutating func process(
        cleanedHeart: Float,
        breathPhase: Float,
        motionEnergy: Float,
        timestamp: TimeInterval
    ) -> [BioEvent] {
        var events: [BioEvent] = []
        if let e = heartbeat.process(sample: cleanedHeart, timestamp: timestamp) {
            events.append(e)
        }
        if let e = breath.process(phase: breathPhase, timestamp: timestamp) {
            events.append(e)
        }
        if let e = motion.process(energy: motionEnergy, timestamp: timestamp) {
            events.append(e)
        }
        return events
    }

    public mutating func reset() {
        heartbeat.reset()
        breath.reset()
        motion.reset()
    }
}

// MARK: - Heartbeat detector (adaptive threshold + refractory)

/// Rising-edge peak detector. Tracks a decaying envelope follower,
/// fires when the signal crosses a fraction of that envelope going up,
/// and enforces a refractory window so one beat = one event.
struct HeartbeatDetector {

    private let sampleRate: Double
    private let refractorySamples: Int
    private let thresholdFraction: Float = 0.5
    private let envelopeDecay: Float

    private var envelope: Float = 0
    private var previous: Float = 0
    private var samplesSinceBeat: Int
    private var lastBeatTime: TimeInterval = -1

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        // 300 ms refractory → max 200 bpm.
        self.refractorySamples = Int(0.3 * sampleRate)
        // Envelope time constant ~2 s.
        self.envelopeDecay = Float(exp(-1.0 / (2.0 * sampleRate)))
        self.samplesSinceBeat = Int(0.3 * sampleRate)
    }

    mutating func process(sample: Float, timestamp: TimeInterval) -> BioEvent? {
        let mag = abs(sample)
        // Envelope follower: fast attack, slow decay.
        envelope = mag > envelope ? mag : envelope * envelopeDecay
        let threshold = envelope * thresholdFraction

        samplesSinceBeat += 1
        defer { previous = sample }

        guard samplesSinceBeat >= refractorySamples else { return nil }
        // Rising-edge crossing of threshold.
        guard previous < threshold, sample >= threshold, threshold > 0 else { return nil }

        let ibiMS: Float
        if lastBeatTime >= 0 {
            ibiMS = Float((timestamp - lastBeatTime) * 1000.0)
        } else {
            ibiMS = 0
        }
        lastBeatTime = timestamp
        samplesSinceBeat = 0

        let confidence = envelope > 0 ? min(sample / envelope, 1) : 0
        return BioEvent(timestamp: timestamp, kind: .heartbeat, confidence: confidence, aux: ibiMS)
    }

    mutating func reset() {
        envelope = 0
        previous = 0
        samplesSinceBeat = refractorySamples
        lastBeatTime = -1
    }
}

// MARK: - Breath phase detector

/// Phase-marker node on the [0..1] breath phase. Emits inhaleOnset when
/// phase crosses 0.5 upward, exhaleOnset when phase wraps 1→0.
struct BreathPhaseDetector {

    private var previous: Float = -1

    mutating func process(phase: Float, timestamp: TimeInterval) -> BioEvent? {
        defer { previous = phase }
        guard previous >= 0 else { return nil }

        // Wrap 1→0 (large downward jump) = exhale onset.
        if previous > 0.8, phase < 0.2 {
            return BioEvent(timestamp: timestamp, kind: .breathExhaleOnset, confidence: 1, aux: 0)
        }
        // Upward crossing of 0.5 = inhale onset.
        if previous < 0.5, phase >= 0.5 {
            return BioEvent(timestamp: timestamp, kind: .breathInhaleOnset, confidence: 1, aux: 0)
        }
        return nil
    }

    mutating func reset() {
        previous = -1
    }
}

// MARK: - Motion peak detector

/// Threshold crossing on motion energy with a small hysteresis so a
/// single burst yields one event, not a chatter of them.
struct MotionPeakDetector {

    private let highThreshold: Float = 0.6
    private let lowThreshold: Float = 0.3
    private var armed = true

    mutating func process(energy: Float, timestamp: TimeInterval) -> BioEvent? {
        if armed, energy >= highThreshold {
            armed = false
            return BioEvent(timestamp: timestamp, kind: .motionPeak, confidence: min(energy, 1), aux: energy)
        }
        if !armed, energy < lowThreshold {
            armed = true
        }
        return nil
    }

    mutating func reset() {
        armed = true
    }
}
