// MultiRollFanout.swift
// Multi-Roll (keystone) — the PURE per-slot decisions the secondary-lane fan-out
// needs but that must be unit-testable OFF the @MainActor player (whose play()
// pulls in the SwiftUI-gated PianoRollModel). Three decisions live here, all
// Foundation-only and deterministic, so the bug-fixes they encode are Linux-tested:
//
//   1. activeLoads(at:)  — which secondary lanes have a region ACTIVE at a tick
//      (the PRIME at play()/seek). Mirrors the primary lane's loadRollRegion(at:),
//      which is onset-INDEPENDENT — fixes the "clip at bar 1 stays silent" trap
//      (laneEvent(0→step) reads .unchanged, so the window fan-out never loads it).
//   2. patch(forSlot:) — the SynthPatch that slot's lane carries (TimelineLane.patch),
//      so each lane sounds with its OWN timbre (nil ⇒ caller falls back to the
//      primary voice's patch, never the bare DDSP default).
//   3. audible(_:laneID:) — the per-lane mute/solo/level gate, identical to the
//      primary roll lane's rollSlotGain→laneAudible rule, so a muted/soloed-away/
//      0-level SECONDARY lane goes silent too (it leaked before).
//
// Slot == priority RANK == index among the non-bio MIDI lanes minus the roll lane,
// EXACTLY as LaneVoiceRackPlan slots them — so these helpers and the reducer agree.

import Foundation

/// Pure per-slot fan-out decisions for the Multi-Roll secondary lanes. No audio,
/// no state, no @MainActor — the device player consumes these to drive rack voices.
public enum MultiRollFanout {

    /// One secondary lane's region that is active at a given tick, resolved to its
    /// physical rack slot and the lane's own patch. `slot` is the lane's priority
    /// rank (< capacity); overflow lanes are omitted (no physical voice).
    public struct SlotLoad: Equatable, Sendable {
        public let slot: Int
        public let laneID: UUID
        public let clipID: UUID
        public let patch: SynthPatch?
        public init(slot: Int, laneID: UUID, clipID: UUID, patch: SynthPatch?) {
            self.slot = slot
            self.laneID = laneID
            self.clipID = clipID
            self.patch = patch
        }
    }

    /// The non-bio MIDI lanes that own physical rack voices — every MIDI lane after
    /// the roll (primary) lane, in document order (= priority rank order). The roll
    /// lane plays the rich PianoRollModel, so it is NOT in the rack.
    public static func secondaryLaneIDs(in document: TimelineDocument, rollLane: UUID?) -> [UUID] {
        document.midiLaneIDs.filter { $0 != rollLane }
    }

    /// Which secondary lanes have a region ACTIVE at `tick`, each mapped to its rank
    /// slot (< `capacity`) and carrying that lane's patch. Used to PRIME the rack at
    /// play()/seek so a lane whose clip is active at the start sounds from the
    /// downbeat — the onset-based window fan-out alone misses it. Pure/deterministic.
    public static func activeLoads(in document: TimelineDocument, at tick: Int,
                                   rollLane: UUID?, capacity: Int) -> [SlotLoad] {
        guard capacity > 0 else { return [] }
        var out: [SlotLoad] = []
        for (rank, laneID) in secondaryLaneIDs(in: document, rollLane: rollLane).enumerated() {
            guard rank < capacity else { break }   // overflow: no physical voice
            guard let region = TimelineScheduling.activeRegion(in: document, laneID: laneID, at: tick) else { continue }
            out.append(SlotLoad(slot: rank, laneID: laneID, clipID: region.clipID,
                                patch: patch(forSlot: rank, in: document, rollLane: rollLane)))
        }
        return out
    }

    /// The lane bound to physical slot `slot` (its priority rank), or nil if the slot
    /// exceeds the secondary-lane count. Lets the fan-out gate/patch a slot by its lane.
    public static func laneID(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> UUID? {
        let secondaries = secondaryLaneIDs(in: document, rollLane: rollLane)
        guard slot >= 0, slot < secondaries.count else { return nil }
        return secondaries[slot]
    }

    /// The patch slot `slot`'s lane carries (nil ⇒ caller uses the primary fallback).
    public static func patch(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> SynthPatch? {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return nil }
        return document.lanes.first(where: { $0.id == id })?.patch
    }

    /// The whole-semitone TRANSPOSE slot `slot`'s lane carries (0 ⇒ no shift, and 0 for
    /// an out-of-range slot). Per-instrument Transpose (founder 2026-07-14); mirrors
    /// `patch(forSlot:)` so each rack voice can be pitched to its own lane.
    public static func transpose(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> Int {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return 0 }
        return document.lanes.first(where: { $0.id == id })?.transposeSemitones ?? 0
    }

    /// The fine DETUNE in cents slot `slot`'s lane carries (0 ⇒ no offset, and 0 for an
    /// out-of-range slot). Per-instrument Detune (founder 2026-07-14); mirrors
    /// `transpose(forSlot:)` so each rack voice can be detuned to its own lane.
    public static func detune(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> Float {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return 0 }
        return document.lanes.first(where: { $0.id == id })?.detuneCents ?? 0
    }

    /// The lane's OKTAVER direction for a rack slot (0 = off for an unset lane /
    /// out-of-range slot). Third pitch twin (founder 2026-07-14 "transpose detune
    /// und Oktaver"); mirrors `detune(forSlot:)` exactly.
    public static func octave(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> Int {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return 0 }
        return document.lanes.first(where: { $0.id == id })?.octaveDouble ?? 0
    }

    /// Whether a secondary lane is audible this tick — mute/foreign-solo/0-level all
    /// silence it, matching the primary roll lane's rollSlotGain→laneAudible gate.
    public static func audible(_ document: TimelineDocument, laneID: UUID) -> Bool {
        document.effectiveGain(for: laneID) > 0.001
    }

    /// The AU INSTRUMENT ref slot `slot`'s lane carries (nil ⇒ built-in voice —
    /// the fallback is always the internal PolySynthVoice, never silence). H5:
    /// mirrors `patch(forSlot:)`; the app resolves the ref to a per-LANE hosted
    /// AVAudioUnit (laneID-keyed — slots are rank-unstable between plays).
    public static func instrument(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> AUPluginRef? {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return nil }
        return document.lanes.first(where: { $0.id == id })?.instrument
    }

    /// The voice KIND slot `slot`'s lane plays through (S2-W2: "Spur = Instrument").
    /// Reads the lane's `builtinInstrument?.voiceKind`; a lane without an instrument
    /// — and an out-of-range slot — resolves to `.poly` (today's voice, never a
    /// surprise). Mirrors `patch(forSlot:)`; the KindVoiceAllocator turns this into
    /// a physical voice binding at the rack boundary.
    public static func voiceKind(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> LaneVoiceKind {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return .poly }
        return document.lanes.first(where: { $0.id == id })?.builtinInstrument?.voiceKind ?? .poly
    }

    /// The stereo PAN slot `slot`'s lane carries, clamped −1…1 (0 = center, and 0
    /// for an out-of-range slot). H4 (healing wave 1, "Pan silently inert"): mirrors
    /// `transpose(forSlot:)` so each rack voice sits at its own lane's position.
    public static func pan(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> Float {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return 0 }
        let p = document.lanes.first(where: { $0.id == id })?.pan ?? 0
        return Swift.max(-1, Swift.min(1, p))
    }

    /// The continuous GAIN slot `slot`'s lane plays at — the full mute/foreign-solo/
    /// level rule (`effectiveGain`), so a half fader is HALF loud, not binary-gated
    /// (closes the B09 gap: the note-ON gate alone made 0.5 sound like 1.0). Unknown
    /// slot ⇒ unity — never silence on a mapping gap, matching `audible`'s stance.
    public static func gain(forSlot slot: Int, in document: TimelineDocument, rollLane: UUID?) -> Float {
        guard let id = laneID(forSlot: slot, in: document, rollLane: rollLane) else { return 1 }
        return document.effectiveGain(for: id)
    }
}
