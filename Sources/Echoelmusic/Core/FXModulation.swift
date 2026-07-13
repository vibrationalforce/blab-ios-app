//
//  FXModulation.swift
//  Echoelmusic — bio-reactive FX modulation core.
//
//  The Echoel thesis applied to effects: the body (and free LFOs) continuously
//  sculpt the EchoelFX chain — coherence opening a reverb, the breath sweeping a
//  filter, the heartbeat driving a tremolo. This is the PURE, deterministic core
//  (routes + the value mapping); the control-rate `FXBioModulator` reads the bio
//  snapshot at ~30 Hz and writes the results to the live chain, and the FX view
//  edits the routes. No audio-thread work here — value types only, Linux-testable.
//
//  Reuses `ModSource` (Core/ModulationMatrix) for the body→[0..1] normalisation so
//  there is ONE definition of "what coherence/breath/HR mean" across the app.
//

import Foundation

/// A modulatable EchoelFX parameter. Each carries the natural range used to scale a
/// normalized [0..1] modulation signal into a real parameter offset, plus a label.
public enum FXModTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case filterCutoff
    case filterResonance
    case saturationDrive
    case chorusMix
    case flangerMix
    case phaserMix
    case tremoloDepth
    case delayMix
    case delayFeedback
    case reverbMix
    case reverbSize
    case bitcrushMix
    case stereoWidth

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .filterCutoff:    return "Filter Cutoff"
        case .filterResonance: return "Filter Resonance"
        case .saturationDrive: return "Saturation Drive"
        case .chorusMix:       return "Chorus Mix"
        case .flangerMix:      return "Flanger Mix"
        case .phaserMix:       return "Phaser Mix"
        case .tremoloDepth:    return "Tremolo Depth"
        case .delayMix:        return "Delay Mix"
        case .delayFeedback:   return "Delay Feedback"
        case .reverbMix:       return "Reverb Mix"
        case .reverbSize:      return "Reverb Size"
        case .bitcrushMix:     return "Bitcrush Mix"
        case .stereoWidth:     return "Stereo Width"
        }
    }

    /// The parameter's natural range — the modulation offset is scaled by its span
    /// and the result is clamped here so the audio thread never sees an illegal value.
    public var range: ClosedRange<Float> {
        switch self {
        case .filterCutoff:    return 80...18000
        case .delayFeedback:   return 0...0.95
        case .stereoWidth:     return 0...2
        default:               return 0...1     // mixes/depths/drive/resonance/size
        }
    }
}

/// The signal driving a route: a body channel (reused `ModSource`) or a free LFO.
public enum FXModCarrier: Codable, Sendable, Equatable, Hashable {
    case bio(ModSource)
    case lfo

    /// Short label for the UI / VoiceOver.
    public var displayName: String {
        switch self {
        case .lfo: return "LFO"
        case .bio(let s):
            switch s {
            case .heartRate:   return "Heart rate"
            case .hrv:         return "HRV"
            case .breathRate:  return "Breath rate"
            case .breathPhase: return "Breath"
            case .coherence:   return "Coherence"
            case .motion:      return "Motion"
            }
        }
    }

    /// All carrier choices offered in the picker (every body channel + the LFO).
    public static var allChoices: [FXModCarrier] {
        ModSource.allCases.map { .bio($0) } + [.lfo]
    }
}

/// One carrier → FX-target modulation, with depth and polarity. Codable so a whole
/// modulation scene saves with an FX preset later.
public struct FXModRoute: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var carrier: FXModCarrier
    public var target: FXModTarget
    /// Output amount [0..1] — the fraction of the target's range the modulation can
    /// move it by (bipolar: ±depth·span/2 around base; unipolar: 0…+depth·span).
    public var depth: Float
    /// Bipolar swings both sides of the user's base value; unipolar only adds.
    public var bipolar: Bool
    /// LFO rate in Hz (used when `carrier == .lfo`).
    public var lfoRateHz: Float
    /// Response shaping applied to the [0..1] carrier signal before depth/polarity —
    /// `.exponential` for a slow start then a fast top, `.logarithmic` for the
    /// reverse, `.sCurve` for soft ends. Default `.linear` (identity).
    public var curve: ResponseCurve
    public var enabled: Bool

    public init(id: UUID = UUID(), carrier: FXModCarrier, target: FXModTarget,
                depth: Float = 0.5, bipolar: Bool = true, lfoRateHz: Float = 0.5,
                curve: ResponseCurve = .linear, enabled: Bool = true) {
        self.id = id
        self.carrier = carrier
        self.target = target
        self.depth = FXModulation.clamp01(depth)
        self.bipolar = bipolar
        self.lfoRateHz = Swift.max(0.01, lfoRateHz)
        self.curve = curve
        self.enabled = enabled
    }
}

/// One enabled route's LIVE effect, for the "which parameters is the body moving"
/// display (Item 2). Pure value type — built deterministically from the routes +
/// the current bio frame, so the leaf view reads a low-rate snapshot instead of
/// the 30 Hz driver (menu-freeze law). `signal01` is the RAW normalized carrier
/// value (pre-curve — the honest "your coherence is at 0.6"); `offset` is the
/// signed amount this route pushes the target by, in the target's own units.
public struct BioModContribution: Sendable, Equatable, Identifiable {
    public var id: UUID            // the route's id (stable across snapshots)
    public var carrierName: String
    public var targetName: String
    public var signal01: Float
    public var offset: Float

    public init(id: UUID, carrierName: String, targetName: String,
                signal01: Float, offset: Float) {
        self.id = id
        self.carrierName = carrierName
        self.targetName = targetName
        self.signal01 = signal01
        self.offset = offset
    }
}

/// Pure mapping helpers — the deterministic heart of the feature.
public enum FXModulation {

    @inline(__always) public static func clamp01(_ x: Float) -> Float {
        Swift.min(Swift.max(x.isFinite ? x : 0, 0), 1)
    }

    /// Whether the ~30 Hz driver should refresh the observable `liveContributions`
    /// snapshot on this tick — `everyN = 3` gives ~10 Hz out of 30, keeping the UI
    /// observation load low. Guards `everyN <= 0` (never divide/modulo by zero).
    public static func shouldPublish(tick: Int, everyN: Int) -> Bool {
        everyN > 0 && tick % everyN == 0
    }

    /// Build the per-route live contributions for the ENABLED routes. Bio carriers
    /// with no frame still appear (signal 0 / offset 0 — the row reads "waiting for
    /// body"); LFO carriers use `now` (seconds) for their phase and ignore the
    /// frame. Order preserved. Deterministic → Linux-testable without the driver.
    public static func contributions(routes: [FXModRoute], frame: BioSampleFrame?,
                                     now: Float) -> [BioModContribution] {
        routes.filter { $0.enabled }.map { route in
            let signal: Float
            switch route.carrier {
            case .bio(let source):
                signal = frame.map { source.normalizedValue(from: $0) } ?? 0
            case .lfo:
                let phase = (now * route.lfoRateHz).truncatingRemainder(dividingBy: 1)
                signal = lfoUnipolar(phase: phase)
            }
            let off = offset(target: route.target, signal: route.curve.apply(signal),
                             depth: route.depth, bipolar: route.bipolar)
            return BioModContribution(id: route.id,
                                      carrierName: route.carrier.displayName,
                                      targetName: route.target.displayName,
                                      signal01: clamp01(signal), offset: off)
        }
    }

    /// A free LFO's unipolar [0..1] value at a phase in turns (1.0 = one cycle).
    public static func lfoUnipolar(phase: Float) -> Float {
        0.5 + 0.5 * sinf(2 * .pi * phase)
    }

    /// The signed offset a single route contributes to `target` for a normalized
    /// carrier `signal` in [0..1]. Lets the driver SUM several routes on one target
    /// before clamping once (so two body channels can sculpt the same parameter).
    ///
    /// - bipolar:  (signal·2−1)·depth·span/2  → swings either side of base
    /// - unipolar: signal·depth·span          → adds upward from base
    public static func offset(target: FXModTarget, signal: Float,
                              depth: Float, bipolar: Bool) -> Float {
        let span = target.range.upperBound - target.range.lowerBound
        let s = clamp01(signal)
        let d = clamp01(depth)
        let o: Float = bipolar ? (s * 2 - 1) * d * span * 0.5 : s * d * span
        return o.isFinite ? o : 0
    }

    /// Combine a base value with summed route offsets, clamped to the target range.
    public static func combine(base: Float, target: FXModTarget, offset: Float) -> Float {
        let r = target.range
        let v = base + offset
        return Swift.min(Swift.max(v.isFinite ? v : base, r.lowerBound), r.upperBound)
    }

    /// The value to WRITE to `target` given the user's `base`, a normalized carrier
    /// `signal` in [0..1], `depth` [0..1] and polarity. Clamped to the target range.
    public static func value(base: Float, target: FXModTarget,
                             signal: Float, depth: Float, bipolar: Bool) -> Float {
        combine(base: base, target: target,
                offset: offset(target: target, signal: signal, depth: depth, bipolar: bipolar))
    }
}
