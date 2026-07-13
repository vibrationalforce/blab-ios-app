// LaneVoicePool.swift
// Multi-Roll (keystone P1) — the PURE per-lane voice-allocation contract.
//
// LaneVoiceSlotMap owns the primitive laneID→slot bookkeeping. LaneVoicePool wraps
// it and adds the two things multi-roll playback needs and the primitive lacks:
//   1. RECONCILIATION — bind exactly the currently-active MIDI lanes, releasing any
//      lane that disappeared (a deleted/re-typed lane frees its slot for reuse).
//   2. OVERFLOW — lanes beyond `capacity` bind to `slot == nil`, the documented
//      "share the one fallback voice" limit. Priority for scarce slots = lane order
//      (top lanes win), so assignment is deterministic and intuitive.
// No audio, no allocation on any hot path — evaluated only on the @MainActor control
// plane, but pure value semantics so it is unit-tested on every platform. The
// device-gated LaneVoiceRack (a fixed pre-attached pool of PianoRollModel+voice
// pairs) consumes these bindings; that layer is measured on-device (CPU/memory).

import Foundation

/// One lane's resolved voice binding. `slot == nil` ⇒ overflow ⇒ shared fallback voice.
public struct LaneVoiceBinding: Sendable, Equatable, Identifiable {
    public var id: UUID { laneID }
    public let laneID: UUID
    public let slot: Int?
    public var usesFallback: Bool { slot == nil }
    public init(laneID: UUID, slot: Int?) {
        self.laneID = laneID
        self.slot = slot
    }
}

public struct LaneVoicePool: Sendable, Equatable {

    public let capacity: Int
    private var slots: LaneVoiceSlotMap
    /// Mirror of the currently-bound lanes (laneID → slot). Needed because
    /// LaneVoiceSlotMap does not expose its keys, so reconcile diffs against this
    /// to release lanes that are no longer active.
    private var bound: [UUID: Int] = [:]

    public init(capacity: Int) {
        let cap = Swift.max(0, capacity)
        self.capacity = cap
        self.slots = LaneVoiceSlotMap(capacity: cap)
    }

    /// Lanes currently holding a dedicated slot.
    public var boundCount: Int { bound.count }

    /// Bind exactly `activeLaneIDs` (order = priority). Releases any previously-bound
    /// lane not in the set, keeps existing bindings STABLE (a lane never changes slot
    /// while it stays active), assigns the lowest free slot to newly-active lanes in
    /// order, and returns `slot == nil` for lanes beyond capacity (fallback). The
    /// returned array is in `activeLaneIDs` order — deterministic for identical input.
    public mutating func reconcile(activeLaneIDs: [UUID]) -> [LaneVoiceBinding] {
        let activeSet = Set(activeLaneIDs)
        // 1. Release slots held by lanes that are gone.
        for laneID in bound.keys where !activeSet.contains(laneID) {
            slots.release(laneID)
        }
        // 2. Reuse-or-assign in priority order; record overflow as nil.
        var table: [LaneVoiceBinding] = []
        table.reserveCapacity(activeLaneIDs.count)
        var next: [UUID: Int] = [:]
        for laneID in activeLaneIDs {
            let s = slots.slot(for: laneID)   // stable reuse, else lowest free, else nil (full)
            if let s { next[laneID] = s }
            table.append(LaneVoiceBinding(laneID: laneID, slot: s))
        }
        bound = next
        return table
    }

    /// Read a lane's current slot without mutating (nil = fallback or unbound).
    public func slot(for laneID: UUID) -> Int? { bound[laneID] }
}

/// One lane's playback step: what its region scheduler wants AND which voice slot it
/// plays through — the exact tuple `TimelineRegionPlayer` needs to load a region into
/// the right per-lane roll. Pure; Equatable so the whole per-tick fan-out is testable.
public struct LanePlaybackStep: Equatable {
    public let laneID: UUID
    public let event: TimelineScheduling.LaneEvent
    public let slot: Int?
    public init(laneID: UUID, event: TimelineScheduling.LaneEvent, slot: Int?) {
        self.laneID = laneID
        self.event = event
        self.slot = slot
    }
}

public enum LaneVoiceScheduling {

    /// The per-lane playback plan moving `fromTick`→`toTick`: for EVERY non-bio MIDI
    /// lane, its scheduling event (load/clear/unchanged) joined to its voice slot.
    /// Reconciles `pool` to the document's current MIDI lanes first (so added/removed
    /// lanes take/free slots), then maps each lane's `laneEvent`. Pure — the audio side
    /// (`TimelineRegionPlayer`) applies the result; this decides nothing about sound.
    public static func plan(in document: TimelineDocument,
                            fromTick: Int, toTick: Int,
                            pool: inout LaneVoicePool) -> [LanePlaybackStep] {
        let bindings = pool.reconcile(activeLaneIDs: document.midiLaneIDs)
        var slotByLane: [UUID: Int?] = [:]
        for b in bindings { slotByLane[b.laneID] = b.slot }
        return TimelineScheduling
            .laneEvents(in: document, fromTick: fromTick, toTick: toTick)
            .map { e in
                LanePlaybackStep(laneID: e.laneID, event: e.event,
                                 slot: slotByLane[e.laneID] ?? nil)
            }
    }
}
