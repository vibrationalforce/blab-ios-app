// TimelineScheduling.swift
// Echoel — the PURE region-playback logic for the arrange timeline (reorg P2).
// Given a TimelineDocument + a transport position (song-absolute ticks), it decides
// which region each lane should be playing and — crucially — WHEN the playhead
// crosses into a new region (the onset that (re)loads that lane's content).
//
// No audio, no clock, no state: the @MainActor TimelineRegionPlayer (P3) rides the
// one shared PatternEngine transport (the SAME clock ArrangementPlayer uses) and
// calls these to load region clips into the live pattern/roll — exactly the launch
// path ArrangementPlayer/the Session grid already use. Pure value logic → fully
// unit-tested on every platform (no AVFoundation).
//
// Granularity: the player samples at each transport 16th-step (120 ticks). A region
// shorter than one step that falls entirely between two steps is not triggered —
// the same step resolution the 16-step sequencer already works at. Regions are
// bar/beat sized in practice, so this is not a real limitation.

import Foundation

public enum TimelineScheduling {

    /// What a lane should do at a playhead transition — the event the player acts on.
    public enum LaneEvent: Equatable {
        /// The active region did not change (still the same region, or still a gap).
        case unchanged
        /// The playhead entered (or switched to) this region → load its clip.
        case load(TimelineRegion)
        /// The playhead fell into a gap (no region) → silence this lane.
        case clear
    }

    /// The region active in `laneID` at song-absolute `tick`: the region whose
    /// half-open span `[startTick, endTick)` contains `tick`. On overlap the
    /// LATEST-starting containing region wins (the most-recently placed / top-most),
    /// so a region dropped over another takes over cleanly. `nil` in a gap.
    ///
    /// Tie-break: when two containing regions share the same `startTick` (a clip
    /// dropped on top at the same bar — common with grid snap), the most-recently
    /// PLACED one must win. Regions are appended in placement order (newest last),
    /// so the tie breaks toward the later array element — hence the lexicographic
    /// `(startTick, offset)` max. Plain `max(by: startTick)` keeps the FIRST
    /// maximal element and would play the stale (older) clip on a tie.
    public static func activeRegion(in document: TimelineDocument,
                                    laneID: UUID, at tick: Int) -> TimelineRegion? {
        document.regions
            .filter { $0.laneID == laneID && tick >= $0.startTick && tick < $0.endTick }
            .enumerated()
            .max(by: { ($0.element.startTick, $0.offset) < ($1.element.startTick, $1.offset) })?
            .element
    }

    /// Whether the lane's active region CHANGED moving from `fromTick` to `toTick` —
    /// the onset that should (re)load content. `.load` when a new region became
    /// active, `.clear` when the playhead left a region into a gap, `.unchanged`
    /// otherwise. Order-independent, so it also handles a loop wrap (end → 0) when
    /// the player passes the real from/to ticks.
    public static func laneEvent(in document: TimelineDocument, laneID: UUID,
                                 fromTick: Int, toTick: Int) -> LaneEvent {
        let before = activeRegion(in: document, laneID: laneID, at: fromTick)
        let after = activeRegion(in: document, laneID: laneID, at: toTick)
        if before?.id == after?.id { return .unchanged }
        if let after { return .load(after) }
        return .clear
    }

    /// One lane's scheduling event — the multi-roll fan-out unit (Equatable so the
    /// whole per-lane list is unit-testable).
    public struct LaneScheduleEvent: Equatable {
        public let laneID: UUID
        public let event: LaneEvent
        public init(laneID: UUID, event: LaneEvent) {
            self.laneID = laneID
            self.event = event
        }
    }

    /// The scheduling event for EVERY non-bio MIDI lane moving `fromTick`→`toTick`,
    /// in lane order — the multi-roll fan-out of `laneEvent`. Today only the single
    /// `rollLaneID` is played; the playback fan-out cycle rides this to drive one
    /// roll+voice per lane. Pure — no audio, no per-lane state yet.
    public static func laneEvents(in document: TimelineDocument,
                                  fromTick: Int, toTick: Int) -> [LaneScheduleEvent] {
        document.midiLaneIDs.map { id in
            LaneScheduleEvent(laneID: id,
                              event: laneEvent(in: document, laneID: id,
                                               fromTick: fromTick, toTick: toTick))
        }
    }

    /// The scheduling event for every VIDEO lane moving `fromTick`→`toTick`, in lane
    /// order — the video analog of `laneEvents`. Pure/additive; no live consumer
    /// today (the video-lane playback engine was removed in the pure-instrument cut;
    /// the residual video-lane model retires with the DAW model in a later slice).
    public static func videoLaneEvents(in document: TimelineDocument,
                                       fromTick: Int, toTick: Int) -> [LaneScheduleEvent] {
        document.videoLaneIDs.map { id in
            LaneScheduleEvent(laneID: id,
                              event: laneEvent(in: document, laneID: id,
                                               fromTick: fromTick, toTick: toTick))
        }
    }
}

public extension TimelineDocument {

    /// The MIDI lane that owns the ONE shared piano-roll/pattern slot: the first
    /// non-bio MIDI lane (mirrors `rollSlotGain`'s ownership rule). `nil` when the
    /// timeline has no MIDI lane. Multi-roll (every MIDI lane its own voice) is the
    /// later A1 step; today one MIDI lane drives the roll, like ArrangementPlayer.
    var rollLaneID: UUID? {
        lanes.first(where: { $0.kind == .midi && !$0.isBio })?.id
    }

    /// The audio lanes (in order) — each plays its audio regions on its own AudioClipPlayer.
    var audioLaneIDs: [UUID] {
        lanes.filter { $0.kind == .audio && !$0.isBio }.map(\.id)
    }

    /// Founder v287/v288 "Es wird kein midi Clip erzeugt": transport ▶ must engage
    /// the ARRANGEMENT engine (TimelineRegionPlayer) only when there is arrangement
    /// content BEYOND the primary roll lane's auto-composer mirror — the visible,
    /// editable MIDI-clip tile that Generate now places on the roll lane. A project
    /// whose ONLY region is that mirror still plays the LIVE bio-generative loop on ▶
    /// (`pattern.play()`), so the core "the music evolves with the body" behaviour is
    /// NEVER replaced by a frozen region. Any real arrangement content — a region on
    /// a secondary lane, an audio/video region, or a USER (non-composer) clip on the
    /// roll lane — engages the arrangement exactly as before. `isComposerOwned` maps a
    /// clipID to its ownership (from ClipStore); an unknown clip counts as content.
    func hasArrangementContent(isComposerOwned: (UUID) -> Bool) -> Bool {
        let roll = rollLaneID
        return regions.contains { region in
            !(region.laneID == roll && isComposerOwned(region.clipID))
        }
    }

    /// The video lanes (in order), mirroring `audioLaneIDs`. Pure/additive; the
    /// video-lane playback engine that read this was removed in the pure-instrument
    /// cut — the residual accessor retires with the DAW model in a later slice.
    var videoLaneIDs: [UUID] {
        lanes.filter { $0.kind == .video && !$0.isBio }.map(\.id)
    }

    /// Every non-bio MIDI lane, in order — the fan-out set for multi-roll playback.
    /// `rollLaneID` (the first) stays the single-slot owner until the fan-out lands,
    /// so this is additive: nothing reads it on the playback path yet.
    var midiLaneIDs: [UUID] {
        lanes.filter { $0.kind == .midi && !$0.isBio }.map(\.id)
    }
}
