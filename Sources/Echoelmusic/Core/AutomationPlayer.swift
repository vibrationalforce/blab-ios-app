// AutomationPlayer.swift
// Echoel — plays parameter automation back over the live transport, the founder's
// "arrangiert … mit automationen". Like ArrangementPlayer it does NOT own a clock:
// it rides the one shared PatternEngine and is fed each transport step (via
// PianoRollModel's onTick). For every enabled lane it reads the keyframe value at
// the current tick and writes it to the live parameter.
//
// v1 scope (deliberately SAFE): targets are MAIN-THREAD-safe parameters only —
// master level (mixer output volume) and tempo (the transport's own BPM). It never
// touches DSP voice/render state, so automation can't destabilise the audio thread.
// Timing is per-bar (the 16-step loop), so a lane is a repeating shape over the bar
// — musical for swells / tempo moves. Song-position automation across an arrangement
// arrives once the arrangement exposes an absolute-bar counter.

import Foundation
import Observation

/// A parameter automation can drive. Normalized lane values [0...1] map to each
/// target's real range; the consumer applies the mapped value live.
public enum AutomationTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case masterLevel
    case tempo
    case filterCutoff

    public var id: String { rawValue }

    /// Registry-style stable identity ("modul.sektion.parameter") — cycle 2 of the
    /// automation-in-track plan. The enum's rawValue stays the PERSISTED legacy
    /// identity (saved lanes are never rewritten); this alias lets new code address
    /// the same target through the EchoelParameterRegistry keyPath convention.
    /// NOTE: filterCutoff is the ×0.25…×4 log MULTIPLIER on the voice's cutoff
    /// (setCutoffScale), not the absolute-Hz "ddsp.filter.cutoff" descriptor.
    public var keyPath: String {
        switch self {
        case .masterLevel:  return "master.amp.level"
        case .tempo:        return "transport.tempo.bpm"
        case .filterCutoff: return "ddsp.filter.cutoffScale"
        }
    }

    /// Resolve EITHER identity — the legacy rawValue ("masterLevel") or the keyPath
    /// alias — to the enum target. nil = not an enum target (a free keyPath lane).
    public static func forParameter(_ parameter: String) -> AutomationTarget? {
        if let t = AutomationTarget(rawValue: parameter) { return t }
        return allCases.first { $0.keyPath == parameter }
    }

    public var displayName: String {
        switch self {
        case .masterLevel:  return "Master Level"
        case .tempo:        return "Tempo"
        case .filterCutoff: return "Filter Cutoff"
        }
    }

    public var unit: String {
        switch self {
        case .masterLevel:  return ""
        case .tempo:        return "BPM"
        case .filterCutoff: return "×"
        }
    }

    /// Real-world value range the normalized lane maps onto.
    public var minValue: Double {
        switch self {
        case .tempo:        return 40
        case .filterCutoff: return 0.25
        case .masterLevel:  return 0
        }
    }
    public var maxValue: Double {
        switch self {
        case .tempo:        return 220
        case .filterCutoff: return 4
        case .masterLevel:  return 1
        }
    }
    public var decimals: Int { self == .tempo ? 0 : 2 }

    /// Neutral value (no audible effect) when a lane is empty / automation off.
    public var neutralValue: Double {
        switch self {
        case .filterCutoff: return 1        // ×1 = unchanged cutoff
        case .masterLevel:  return 1
        case .tempo:        return 120
        }
    }

    /// Map a normalized [0...1] lane value to the real parameter value. Filter cutoff
    /// uses a log (octave) curve so 0.5 sits at ×1; the rest are linear.
    public func value(forNormalized n: Double) -> Double {
        let c = Swift.min(1, Swift.max(0, n))
        if self == .filterCutoff {
            return minValue * pow(maxValue / minValue, c)   // 0.25…4, ×1 at c=0.5
        }
        return minValue + c * (maxValue - minValue)
    }

    /// Inverse: real value → normalized [0...1] (for editing in real units).
    public func normalized(forValue v: Double) -> Double {
        if self == .filterCutoff {
            let cv = Swift.min(maxValue, Swift.max(minValue, v))
            return Swift.min(1, Swift.max(0, Foundation.log(cv / minValue) / Foundation.log(maxValue / minValue)))
        }
        let span = maxValue - minValue
        guard span > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, (v - minValue) / span))
    }
}

/// Persisted automation document: the on/off state plus one lane per target.
private struct AutomationState: Codable, Sendable {
    var enabled: Bool
    var lanes: [AutomationLane]
}

@MainActor
@Observable
public final class AutomationPlayer {

    /// One bar = 16 steps = 4 quarter-note beats.
    public static let beatsPerBar = 4

    /// Master switch — when off, automation never writes a parameter.
    public var enabled: Bool { didSet { persist() } }

    /// One lane per target (created lazily, kept for the lifetime of the doc).
    public private(set) var lanes: [AutomationLane]

    @ObservationIgnored private weak var pattern: PatternEngine?
    @ObservationIgnored private weak var audioEngine: AudioEngine?
    @ObservationIgnored private weak var voice: PolySynthVoice?
    /// Cycle-2 wire: extra keyPath lanes (beyond the three enum targets) apply
    /// through this router (registry-denormalized → live setter). Optional —
    /// without it the player behaves exactly as before.
    @ObservationIgnored private weak var router: ParameterApplyRouter?
    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Automation")
    @ObservationIgnored private static let fileName = "automation"

    public init() {
        if let saved = store.load(AutomationState.self, name: Self.fileName) {
            self.enabled = saved.enabled
            self.lanes = AutomationPlayer.completed(saved.lanes)
        } else {
            self.enabled = false
            self.lanes = AutomationPlayer.completed([])
        }
    }

    /// Ensure exactly one lane exists per enum target (matched under EITHER
    /// identity — legacy rawValue or keyPath alias, saved names untouched) and
    /// PRESERVE every additional keyPath lane instead of dropping it (cycle 2:
    /// unknown lanes are future registry-parameter automation, not junk).
    private static func completed(_ existing: [AutomationLane]) -> [AutomationLane] {
        let enumLanes = AutomationTarget.allCases.map { target in
            existing.first { AutomationTarget.forParameter($0.parameter) == target }
                ?? AutomationLane(parameter: target.rawValue)
        }
        let extras = existing.filter { AutomationTarget.forParameter($0.parameter) == nil }
        return enumLanes + extras
    }

    // MARK: - Wiring

    /// Connect the live transport + master + synth so applied values land somewhere.
    public func wire(pattern: PatternEngine, audioEngine: AudioEngine, voice: PolySynthVoice? = nil) {
        self.pattern = pattern
        self.audioEngine = audioEngine
        self.voice = voice
    }

    /// Connect the keyPath→setter router for extra (non-enum) lanes. Separate from
    /// the transport wire so pure tests can wire only this.
    public func wire(router: ParameterApplyRouter) {
        self.router = router
    }

    // MARK: - Playback (called each transport step on the shared clock)

    /// Apply every enabled lane's value at `step` to its live parameter. Per-bar:
    /// the step maps to a tick within one bar, so the lane repeats each loop.
    public func applyStep(_ step: Int) {
        // When automation is off, release the hidden multiplier so the synth isn't
        // left filtered; master/tempo stay where they are (user-visible).
        guard enabled else { voice?.setCutoffScale(1); return }
        for target in AutomationTarget.allCases {
            let real = appliedValue(for: target, atStep: step)
            switch target {
            case .masterLevel: if let r = real { audioEngine?.masterVolume = Float(r) }
            case .tempo:       if let r = real { pattern?.setTempo(r) }
            // Filter cutoff is a hidden multiplier → reset to neutral (×1) when its
            // lane is empty, so an unused lane never leaves the sound filtered.
            case .filterCutoff: voice?.setCutoffScale(Float(real ?? target.neutralValue))
            }
        }
        // Extra keyPath lanes (cycle 2): registry-denormalize + dispatch through the
        // router. No router / unbound keyPath = safe no-op (never a dead crash).
        for lane in lanes where AutomationTarget.forParameter(lane.parameter) == nil {
            if let n = lane.value(atTick: step * Note.ticksPerStep) {
                router?.applyNormalized(lane.parameter, Float(n))
            }
        }
    }

    /// The real-world value an ENUM target would take at `step`, addressed by either
    /// identity (legacy rawValue or keyPath alias). nil for non-enum keyPaths — their
    /// curve lives in the registry descriptor, applied via the router, not guessed here.
    public func appliedValue(forKeyPath keyPath: String, atStep step: Int) -> Double? {
        guard let target = AutomationTarget.forParameter(keyPath) else { return nil }
        return appliedValue(for: target, atStep: step)
    }

    /// The real-world value a target would take at `step` (per-bar tick), or nil if
    /// its lane is empty. Pure — the core of `applyStep`, exposed for testing.
    public func appliedValue(for target: AutomationTarget, atStep step: Int) -> Double? {
        let lane = lane(for: target)
        guard let n = lane.value(atTick: step * Note.ticksPerStep) else { return nil }
        return target.value(forNormalized: n)
    }

    // MARK: - Lane access + editing

    public func lane(for target: AutomationTarget) -> AutomationLane {
        lanes.first { AutomationTarget.forParameter($0.parameter) == target }
            ?? AutomationLane(parameter: target.rawValue)
    }

    /// Add or replace a lane by parameter identity (alias-aware: a lane named by an
    /// enum target's keyPath lands in that enum slot, never as a duplicate). This is
    /// the door future registry-parameter automation walks through.
    public func adoptLane(_ lane: AutomationLane) {
        if let i = lanes.firstIndex(where: {
            $0.parameter == lane.parameter ||
            (AutomationTarget.forParameter($0.parameter) != nil &&
             AutomationTarget.forParameter($0.parameter)
                == AutomationTarget.forParameter(lane.parameter))
        }) {
            // Keep the slot's PERSISTED identity — an alias-named adopt must never
            // rewrite a saved legacy name (migration invariant; review 2026-07-13).
            var adopted = lane
            adopted.parameter = lanes[i].parameter
            lanes[i] = adopted
        } else {
            lanes.append(lane)
        }
        persist()
    }

    /// Remove an EXTRA keyPath lane. Enum-target lanes are structural (one per
    /// target, kept by `completed`) — clearing their points is `clear(target:)`.
    public func removeLane(parameter: String) {
        guard AutomationTarget.forParameter(parameter) == nil else { return }
        lanes.removeAll { $0.parameter == parameter }
        persist()
    }

    public func points(for target: AutomationTarget) -> [AutomationPoint] {
        lane(for: target).points
    }

    /// Tick for a beat position (0…beatsPerBar) within the bar.
    public static func tick(forBeat beat: Double) -> Int {
        Int((beat * Double(Note.ticksPerQuarter)).rounded())
    }
    public static func beat(forTick tick: Int) -> Double {
        Double(tick) / Double(Note.ticksPerQuarter)
    }

    @discardableResult
    public func addPoint(target: AutomationTarget, beat: Double, value: Double,
                         curve: AutomationCurve = .linear) -> AutomationPoint? {
        guard let i = index(of: target) else { return nil }
        let p = lanes[i].addPoint(tick: AutomationPlayer.tick(forBeat: beat), value: value, curve: curve)
        persist()
        return p
    }

    public func removePoint(target: AutomationTarget, id: UUID) {
        guard let i = index(of: target) else { return }
        lanes[i].removePoint(id: id)
        persist()
    }

    public func movePoint(target: AutomationTarget, id: UUID, toBeat beat: Double) {
        guard let i = index(of: target) else { return }
        lanes[i].movePoint(id: id, toTick: AutomationPlayer.tick(forBeat: beat))
        persist()
    }

    public func setValue(target: AutomationTarget, id: UUID, normalized value: Double) {
        guard let i = index(of: target) else { return }
        lanes[i].setValue(id: id, value)
        persist()
    }

    public func setCurve(target: AutomationTarget, id: UUID, _ curve: AutomationCurve) {
        guard let i = index(of: target) else { return }
        lanes[i].setCurve(id: id, curve)
        persist()
    }

    /// Bend the segment leaving a keyframe (the canvas' vertical segment-drag).
    public func setCurvature(target: AutomationTarget, id: UUID, _ curvature: Double) {
        guard let i = index(of: target) else { return }
        lanes[i].setCurvature(id: id, curvature)
        persist()
    }

    /// Move + revalue a keyframe in one gesture step (canvas point-drag).
    public func movePoint(target: AutomationTarget, id: UUID, toBeat beat: Double,
                          normalized value: Double) {
        guard let i = index(of: target) else { return }
        lanes[i].movePoint(id: id, toTick: AutomationPlayer.tick(forBeat: beat))
        lanes[i].setValue(id: id, value)
        persist()
    }

    public func clear(target: AutomationTarget) {
        guard let i = index(of: target) else { return }
        lanes[i].clear()
        persist()
    }

    private func index(of target: AutomationTarget) -> Int? {
        lanes.firstIndex { AutomationTarget.forParameter($0.parameter) == target }
    }

    private func persist() {
        store.save(AutomationState(enabled: enabled, lanes: lanes), name: Self.fileName)
    }
}
