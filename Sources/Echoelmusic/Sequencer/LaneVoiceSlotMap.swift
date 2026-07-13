// LaneVoiceSlotMap.swift
// Multi-Roll cycle 1 — the pure slot-assignment logic behind LaneVoicePool.
//
// The pool pre-creates N voices and attaches them to the master mixer ONCE, before
// the engine starts (the attach-before-start law). Lanes then bind to a stable
// slot in that fixed pool at runtime — no runtime attach, no graph mutation. This
// value type owns only the laneID → slot bookkeeping: assign the lowest free slot
// to a new lane, reuse it on every later call, free it on release, and report
// "full" (nil) once every slot is taken (the caller then falls back to the shared
// voice — the honest ">N lanes share one voice" limit). Deterministic, no audio,
// no allocation on any hot path — evaluated only on the @MainActor control plane.

import Foundation

public struct LaneVoiceSlotMap: Sendable, Equatable {

    public let capacity: Int
    private var assignments: [UUID: Int] = [:]

    public init(capacity: Int) {
        self.capacity = Swift.max(0, capacity)
    }

    /// Number of lanes currently holding a slot.
    public var assignedCount: Int { assignments.count }

    /// The slot for `laneID`: its existing slot if already bound (stable), else the
    /// lowest free slot (newly bound), else `nil` when the pool is full.
    public mutating func slot(for laneID: UUID) -> Int? {
        if let existing = assignments[laneID] { return existing }
        guard assignments.count < capacity else { return nil }
        let taken = Set(assignments.values)
        // Lowest free index — deterministic, so reuse after a release is predictable.
        for i in 0..<capacity where !taken.contains(i) {
            assignments[laneID] = i
            return i
        }
        return nil
    }

    /// Free the slot a lane held (no-op if it held none).
    public mutating func release(_ laneID: UUID) {
        assignments[laneID] = nil
    }
}
