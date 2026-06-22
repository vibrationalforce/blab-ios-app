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

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .masterLevel: return "Master Level"
        case .tempo:       return "Tempo"
        }
    }

    public var unit: String {
        switch self {
        case .masterLevel: return ""
        case .tempo:       return "BPM"
        }
    }

    /// Real-world value range the normalized lane maps onto.
    public var minValue: Double { self == .tempo ? 40 : 0 }
    public var maxValue: Double { self == .tempo ? 220 : 1 }
    public var decimals: Int { self == .tempo ? 0 : 2 }

    /// Map a normalized [0...1] lane value to the real parameter value.
    public func value(forNormalized n: Double) -> Double {
        let c = Swift.min(1, Swift.max(0, n))
        return minValue + c * (maxValue - minValue)
    }

    /// Inverse: real value → normalized [0...1] (for editing in real units).
    public func normalized(forValue v: Double) -> Double {
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

    /// Ensure exactly one lane exists per target (preserving any saved points).
    private static func completed(_ existing: [AutomationLane]) -> [AutomationLane] {
        AutomationTarget.allCases.map { target in
            existing.first { $0.parameter == target.rawValue }
                ?? AutomationLane(parameter: target.rawValue)
        }
    }

    // MARK: - Wiring

    /// Connect the live transport + master so applied values land somewhere.
    public func wire(pattern: PatternEngine, audioEngine: AudioEngine) {
        self.pattern = pattern
        self.audioEngine = audioEngine
    }

    // MARK: - Playback (called each transport step on the shared clock)

    /// Apply every enabled lane's value at `step` to its live parameter. Per-bar:
    /// the step maps to a tick within one bar, so the lane repeats each loop.
    public func applyStep(_ step: Int) {
        guard enabled else { return }
        for target in AutomationTarget.allCases {
            guard let real = appliedValue(for: target, atStep: step) else { continue }
            switch target {
            case .masterLevel: audioEngine?.masterVolume = Float(real)
            case .tempo:       pattern?.setTempo(real)
            }
        }
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
        lanes.first { $0.parameter == target.rawValue } ?? AutomationLane(parameter: target.rawValue)
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

    public func clear(target: AutomationTarget) {
        guard let i = index(of: target) else { return }
        lanes[i].clear()
        persist()
    }

    private func index(of target: AutomationTarget) -> Int? {
        lanes.firstIndex { $0.parameter == target.rawValue }
    }

    private func persist() {
        store.save(AutomationState(enabled: enabled, lanes: lanes), name: Self.fileName)
    }
}
