// PerTrackAutomationResolver.swift
// Automation-in-Spur L2/L4 S2b-prep (pure). Composes the two pure pieces —
// PerTrackParameterKeyPath.parse (S1) + MultiRollFanout.slot(forLaneID:) (S2a) —
// plus denormalization into ONE tested decision: given a "track.<laneID>.<param>"
// automation keyPath and a normalized [0…1] value, resolve WHICH physical rack
// slot, WHICH base engine parameter, and the denormalized value to write.
//
// This is deliberately the whole safety-critical decision, so the device wiring
// (S2b) becomes a thin shell: call resolve(), then map `base` to the concrete
// LaneVoiceRack slot setter. The no-op cases live HERE and are unit-pinned:
//   • a global (non-namespaced) keyPath → nil (route it globally, not per-track),
//   • a lane with no physical voice — deleted / foreign (roll/bio/audio) /
//     overflow past `capacity` → nil (silent no-op, never a foreign-slot write),
//   • an unknown base parameter → nil.
// laneID→slot is resolved HERE, at dispatch time — slots are rank-unstable
// between plays, so the caller must call this per step, never cache the result.
//
// Foundation-only, Sequencer/ (uses TimelineDocument + ParameterDescriptor);
// NOT DSP/ (which compiles isolated for the AUv3 target). No consumer yet, so
// the global automation path stays byte-identical.

import Foundation

public enum PerTrackAutomationResolver {

    /// A resolved per-track automation write. The device layer maps `base` to the
    /// concrete per-slot setter on the voice rack and applies `value`.
    public struct Resolved: Equatable, Sendable {
        public let slot: Int
        public let base: String
        public let value: Float
        public init(slot: Int, base: String, value: Float) {
            self.slot = slot
            self.base = base
            self.value = value
        }
    }

    /// Resolve a per-track automation keyPath + normalized value against the LIVE
    /// document. Returns nil (silent no-op) for a global keyPath, a lane with no
    /// physical voice (deleted / foreign / overflow), or an unknown base param.
    /// `descriptor` looks up the BASE (un-namespaced) engine parameter — its range
    /// drives denormalization (the per-track descriptor inherits that range).
    public static func resolve(keyPath: String, normalized: Float,
                               document: TimelineDocument, rollLane: UUID?,
                               capacity: Int,
                               descriptor: (String) -> ParameterDescriptor?) -> Resolved? {
        guard let (laneID, base) = PerTrackParameterKeyPath.parse(keyPath) else { return nil }
        guard let slot = MultiRollFanout.slot(forLaneID: laneID, in: document,
                                              rollLane: rollLane, capacity: capacity) else { return nil }
        guard let d = descriptor(base) else { return nil }
        return Resolved(slot: slot, base: base, value: d.denormalized(normalized))
    }
}
