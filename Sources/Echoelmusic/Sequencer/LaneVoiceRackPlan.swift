// LaneVoiceRackPlan.swift
// Multi-Roll (keystone P1) — the PURE reducer from per-lane playback steps to
// deterministic slot commands for a FIXED N-voice rack.
//
// `LaneVoiceScheduling.plan` produces one `LanePlaybackStep` per active MIDI lane
// (laneID + scheduling event + advisory pool slot), in PRIORITY order (top lane
// first — the same order `LaneVoicePool.reconcile` binds slots in). This reducer
// turns that per-lane list into the exact commands a fixed pre-attached rack of
// `capacity` voice slots must apply this tick.
//
// AUTHORITATIVE, RANK-BASED SLOTTING
// ----------------------------------
// The reducer OWNS physical slot assignment; it does NOT read `step.slot` (that
// value is the pool's advisory binding and may come from a differently-sized pool).
// A lane's "slot" here is its PRIORITY RANK = its index in `steps` (0 = top). The
// fixed rack has physical voices for ranks `0 ..< capacity`; a lane whose rank is
// `>= capacity` OVERFLOWS — it has no physical voice and is silenced.
//
// This makes the mapping uniform and deterministic: `load`/`clear` slots are always
// `< capacity`, `silence` slots are always `>= capacity`, and identical ordered
// input always yields byte-identical output — no Date/UUID/random in the logic.
//
// No audio, no allocation on any hot path. Pure Foundation value logic → unit-tested
// on every platform; the device-gated `LaneVoiceRack` consumes these commands.

import Foundation

/// One instruction for a single voice slot of the fixed rack. `slot` is the lane's
/// PRIORITY RANK (its index in the reduced `steps`): ranks `0 ..< capacity` are
/// physical voices, ranks `>= capacity` are overflow (silenced — no physical voice).
public enum SlotCommand: Equatable, Sendable {
    /// The lane entered/switched region → load `clipID` into physical voice `slot`
    /// (`slot < capacity`).
    case load(slot: Int, clipID: UUID)
    /// The lane fell into a gap → unload physical voice `slot` (`slot < capacity`).
    case clear(slot: Int)
    /// The lane overflowed the rack (its rank `>= capacity`) → it produces no sound.
    /// Emitted once per overflow lane, in ascending rank order, so the drop set is
    /// deterministic and inspectable.
    case silence(slot: Int)
}

/// Pure reducer: per-lane playback steps → fixed-rack slot commands.
public enum LaneVoiceRackPlan {

    /// Reduce `steps` (one per active lane, in PRIORITY order — top lane first) to the
    /// slot commands a fixed `capacity`-voice rack must apply this tick.
    ///
    /// Each lane's slot is its priority rank (index in `steps`). For rank `k`:
    /// - `k < capacity` (a physical voice):
    ///   - `.load(region)` → `.load(slot: k, clipID: region.clipID)`
    ///   - `.clear`        → `.clear(slot: k)`
    ///   - `.unchanged`    → no command (the voice keeps playing what it had)
    /// - `k >= capacity` (OVERFLOW): `.silence(slot: k)`, regardless of event — the
    ///   lane has no physical voice, so it cannot sound.
    ///
    /// OVERFLOW POLICY: when there are more active lanes than `capacity`, the TOP
    /// `capacity` lanes (lowest ranks) keep the physical voices; every lower-priority
    /// lane (rank `>= capacity`, i.e. the largest indices) is silenced. Overflow
    /// `.silence` commands appear in ascending rank order.
    ///
    /// `capacity <= 0` (guarded → clamped to 0) means the rack has no physical voices,
    /// so every lane overflows and is silenced. Empty `steps` → empty output.
    ///
    /// Deterministic and pure: output depends only on the ordered `steps` and
    /// `capacity` — the same input always yields the same commands.
    public static func commands(steps: [LanePlaybackStep], capacity: Int) -> [SlotCommand] {
        let voiceCount = Swift.max(0, capacity)
        guard !steps.isEmpty else { return [] }

        var out: [SlotCommand] = []
        out.reserveCapacity(steps.count)

        for (rank, step) in steps.enumerated() {
            if rank >= voiceCount {
                // Overflow: no physical voice for this lane — silence it.
                out.append(.silence(slot: rank))
                continue
            }
            switch step.event {
            case .load(let region):
                out.append(.load(slot: rank, clipID: region.clipID))
            case .clear:
                out.append(.clear(slot: rank))
            case .unchanged:
                break   // voice keeps playing — no command
            }
        }
        return out
    }
}
