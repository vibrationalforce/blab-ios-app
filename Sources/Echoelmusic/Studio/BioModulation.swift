//
//  BioModulation.swift
//  Echoelmusic — Studio (the universal bio-binding spine)
//
//  The founder principle, made into ONE abstraction so it stays stable and
//  consistent across every module: every parameter (synth, sampler, drum machine,
//  breakbeat slicer, piano roll, FX, video, visual, light) can EITHER follow a
//  bio source OR be set to an absolute value by hand — full access, never
//  preset-only. The heartbeat can even BE the clock; BPM-lock turns that off.
//
//  This file is pure value types + deterministic resolution — no audio DSP, no
//  Metal, no SwiftUI. Modules read a resolved Double each control tick; the audio
//  thread can call `resolved(from:)` (allocation-free).
//

import Foundation

// Bio SOURCES are the ONE canonical `ModSource` enum in `Core/ModulationMatrix.swift`
// (Q1 de-duplication 2026-07-11): the former `BioModSource` here was a second, parallel
// bio-source enum. `ModulationMatrix` (routing, matrix-style, keyed destinations) and this
// file (per-control binding + master clock) are COMPLEMENTARY halves of one modulation
// spine — they now share the same source vocabulary so "assign the pulse to this knob"
// means exactly the same thing everywhere. `nil` source = pure manual control.

/// The master clock: a fixed musical tempo (BPM-lock) OR the live heartbeat.
public enum ClockSource: Sendable, Equatable {
    case fixedBPM(Double)
    case heartbeat

    /// Effective tempo in BPM. Heartbeat uses live HR, clamped to a musical range.
    public func effectiveBPM(heartRateBPM: Double) -> Double {
        switch self {
        case .fixedBPM(let bpm): return min(300, max(20, bpm))
        case .heartbeat:         return min(200, max(40, heartRateBPM))
        }
    }

    /// Seconds per beat at the effective tempo.
    public func beatSeconds(heartRateBPM: Double) -> Double {
        60.0 / effectiveBPM(heartRateBPM: heartRateBPM)
    }

    public var isHeartbeat: Bool { if case .heartbeat = self { return true }; return false }
}

/// A bindable parameter: a manual base value (in the parameter's own unit — Hz,
/// ms, semitones, 0…1, …) plus optional bio modulation. The single type every
/// module routes its controls through, so binding behaves identically everywhere.
public struct BoundParameter: Codable, Sendable, Equatable {
    /// The user's absolute value — full manual control, always meaningful.
    public var base: Double
    /// Valid range for this parameter (clamps the resolved result).
    public var range: ClosedRange<Double>
    /// Which body signal modulates it (`nil` = pure manual). The one canonical
    /// `ModSource` enum, shared with the routing matrix.
    public var source: ModSource?
    /// Bipolar modulation depth, -1…1, scaled to the range span. + pushes toward
    /// the maximum as the signal rises, − toward the minimum.
    public var amount: Double

    public init(base: Double,
                range: ClosedRange<Double>,
                source: ModSource? = nil,
                amount: Double = 0) {
        self.base = base
        self.range = range
        self.source = source
        self.amount = clamp(amount, -1, 1)
    }

    /// True when this parameter currently follows the body.
    public var isBound: Bool { source != nil && amount != 0 }

    /// Resolve to a concrete value for the current bio frame. With no source (or
    /// no frame) it returns the clamped manual base — manual control always works.
    public func resolved(from bio: BioSampleFrame?) -> Double {
        let span = range.upperBound - range.lowerBound
        guard let source, amount != 0, let bio, span > 0 else {
            return clamp(base, range.lowerBound, range.upperBound)
        }
        let signal = Double(source.normalizedValue(from: bio))
        let value = base + clamp(amount, -1, 1) * span * signal
        return clamp(value, range.lowerBound, range.upperBound)
    }
}

// MARK: - Pure helpers

private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
