// TimelineRegionPlayer.swift
// Echoel — plays the arrange TIMELINE back over the live transport (reorg P3).
// Like ArrangementPlayer it does NOT own a clock: it rides the one shared
// PatternEngine (16 steps = 1 bar). The host feeds every transport step into
// `transportStep(_:)`; the player tracks the absolute song position (a pure
// TimelinePlaybackCursor), asks TimelineScheduling which region the roll lane is
// in, and on each region onset LOADS that region's clip into the live pattern +
// piano roll — EXACTLY the proven ArrangementPlayer/Session-grid launch path.
//
// Additive + opt-in: nothing calls `play()` until the timeline's own Play control
// (P3b) does, so the existing Generate+Play instrument path is untouched — this
// cannot regress the launching instrument. Multi-lane MIDI (every lane its own
// voice) is the later A1 step; today the roll lane plays, mirroring rollSlotGain.
//
// The position math lives in the PURE `TimelinePlaybackCursor` so it's unit-tested
// without audio; the audio side (loadClip) mirrors ArrangementPlayer.loadCurrentSection.

import Foundation
import Observation

/// Pure absolute-position tracker for timeline playback. Converts the host's
/// within-bar transport steps (0…15) into a song-absolute tick, counting bar
/// wraps itself (the transport publishes only the within-bar step). No audio, no
/// loop policy — the player owns loop-vs-stop; this just advances the tick.
public struct TimelinePlaybackCursor: Equatable {
    private var barsCompleted = 0
    private var lastStep = 0
    private var started = false

    public init() {}

    /// Consume the next within-bar step (0…15) and return the new absolute tick.
    /// A bar completes only on a real wrap back to step 0 (15→0), matching
    /// ArrangementPlayer's bar-boundary detection.
    public mutating func advance(step: Int) -> Int {
        let s = min(max(step, 0), 15)
        if started, s == 0, lastStep != 0 { barsCompleted += 1 }
        started = true
        lastStep = s
        return (barsCompleted * 16 + s) * TimelineTime.ticksPerTransportStep
    }
}

@MainActor
@Observable
public final class TimelineRegionPlayer {

    /// Whether the timeline is currently chaining regions.
    public private(set) var isPlaying = false
    /// Absolute song tick sounding now (can drive a playhead).
    public private(set) var currentTick = 0
    /// The region loaded on the roll lane now (nil = a gap / silence). Lets the UI
    /// and tests observe what is playing.
    public private(set) var loadedRegionID: UUID?
    /// Loop the whole song (rounded up to whole bars) when it reaches the end.
    public var loopEnabled = true

    @ObservationIgnored private var cursor = TimelinePlaybackCursor()
    @ObservationIgnored private var doc = TimelineDocument()
    @ObservationIgnored private var rollLane: UUID?
    /// Song length rounded UP to whole bars — the loop point. 0 = no bound.
    @ObservationIgnored private var loopTicks = 0
    @ObservationIgnored private var lastTick = 0

    @ObservationIgnored private weak var pattern: PatternEngine?
    @ObservationIgnored private weak var pianoRoll: PianoRollModel?
    @ObservationIgnored private weak var clips: ClipStore?

    // MARK: - Multi-roll fan-out (B08) — SECONDARY lanes play their own rack voice.
    // The PRIMARY lane keeps the rich PianoRollModel above; every ADDITIONAL non-bio
    // MIDI lane gets a pure LaneNotePump routed to its rack slot via `slotNoteSink`.
    // Disabled (capacity 0) ⇒ single-roll only, bit-identical. The app turns it on
    // once the flag-gated LaneVoiceRack is attached (FeatureFlags.multiRoll).
    @ObservationIgnored private var multiRollCapacity = 0
    /// Applies one slot's note events to that slot's rack voice. Injected so this
    /// file stays Foundation-only (the rack is AVFoundation). nil ⇒ no fan-out.
    @ObservationIgnored public var slotNoteSink: ((_ slot: Int, _ events: [LaneNotePump.Event]) -> Void)?
    @ObservationIgnored private var lanePool = LaneVoicePool(capacity: 0)
    @ObservationIgnored private var pumps: [Int: LaneNotePump] = [:]

    public init() {}

    /// Enable secondary-lane fan-out over a fixed rack of `capacity` voices. Called
    /// once by the app after the LaneVoiceRack is attached + started (flag-gated).
    /// The primary lane is unaffected; additional MIDI lanes route through `sink`.
    public func enableMultiRoll(
        capacity: Int,
        sink: @escaping (_ slot: Int, _ events: [LaneNotePump.Event]) -> Void
    ) {
        let cap = max(0, capacity)
        multiRollCapacity = cap
        lanePool = LaneVoicePool(capacity: cap)
        slotNoteSink = sink
    }

    /// Song length rounded up to whole bars (the loop point). 0 for an empty song.
    /// Pure — `nonisolated` so it's unit-testable off the main actor.
    nonisolated static func loopTicks(for document: TimelineDocument) -> Int {
        let end = document.endTick
        guard end > 0 else { return 0 }
        let bars = (end + TimelineTime.ticksPerBar - 1) / TimelineTime.ticksPerBar
        return max(1, bars) * TimelineTime.ticksPerBar
    }

    // MARK: - Transport

    /// Start playing `document` from the top. No-op if it has no MIDI (roll) lane
    /// or no regions — nothing to chain.
    public func play(
        document: TimelineDocument,
        clips: ClipStore,
        pattern: PatternEngine,
        pianoRoll: PianoRollModel
    ) {
        guard document.rollLaneID != nil, !document.regions.isEmpty else { return }
        self.doc = document
        self.clips = clips
        self.pattern = pattern
        self.pianoRoll = pianoRoll
        self.rollLane = document.rollLaneID
        self.loopTicks = Self.loopTicks(for: document)
        self.cursor = TimelinePlaybackCursor()
        self.lastTick = 0
        self.currentTick = 0
        // Fresh multi-roll state: release any lingering take (symmetric with stop —
        // never drop a sounding pitch without its note-off), clear slots, rebuild pool.
        flushPumps()
        isPlaying = true
        pianoRoll.setTimelineAutomation(document.automation)   // arrangement automation (cycle 5)
        pianoRoll.setTimelineAutomationTick(0)
        loadRollRegion(at: 0)            // whatever is under the playhead at the top
        if !pattern.isPlaying { pattern.play() }
    }

    /// Stop timeline-follow and the transport.
    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        pattern?.stop()
        pianoRoll?.allNotesOff()
        flushPumps()                           // release every secondary-lane voice
        pianoRoll?.setTimelineAutomation([])   // release the arrangement layer (cycle 5)
    }

    /// Reset follow-state when the transport is stopped from OUTSIDE (the global
    /// Stop calls PatternEngine.stop() directly). Same contract as
    /// ArrangementPlayer.handleTransportStopped — no-op when already stopped.
    public func handleTransportStopped() {
        guard isPlaying else { return }
        isPlaying = false
        pianoRoll?.allNotesOff()
        flushPumps()                           // release every secondary-lane voice
        pianoRoll?.setTimelineAutomation([])   // release the arrangement layer (cycle 5)
    }

    /// Fed every transport step (0…15) by the host. Advances the absolute position,
    /// loops at the song's whole-bar end (or stops), and (re)loads the roll lane's
    /// clip on each region onset.
    public func transportStep(_ step: Int) {
        guard isPlaying else { return }
        var newTick = cursor.advance(step: step)
        if loopTicks > 0, newTick >= loopTicks {
            if loopEnabled {
                cursor = TimelinePlaybackCursor()
                newTick = cursor.advance(step: step)   // restart within bar 0
            } else {
                stop()
                return
            }
        }
        if let lane = rollLane {
            switch TimelineScheduling.laneEvent(in: doc, laneID: lane, fromTick: lastTick, toTick: newTick) {
            case .unchanged: break
            case .load(let region): loadClip(region)
            case .clear: clearRoll()
            }
        }
        // Multi-roll: fan the SAME tick window out over the additional MIDI lanes so
        // they sound simultaneously on their own rack voices (no-op when capacity 0
        // or the song has only the one primary lane).
        if multiRollCapacity > 0 {
            fanOutSecondaryLanes(fromTick: lastTick, toTick: newTick, step: step)
        }
        // Feed the arrangement automation the absolute playhead BEFORE the roll's
        // onTick chain reaches AutomationPlayer.applyStep (cycle 5). loadClip above
        // may have installed a clip's own lanes; the timeline layer applies last.
        pianoRoll?.setTimelineAutomationTick(newTick)
        lastTick = newTick
        currentTick = newTick
    }

    // MARK: - Loading (mirrors ArrangementPlayer.loadCurrentSection — the proven path)

    private func loadRollRegion(at tick: Int) {
        guard let lane = rollLane,
              let region = TimelineScheduling.activeRegion(in: doc, laneID: lane, at: tick) else {
            clearRoll()
            return
        }
        loadClip(region)
    }

    private func loadClip(_ region: TimelineRegion) {
        guard let clip = clips?.clip(id: region.clipID) else {
            clearRoll()
            return
        }
        if let drums = clip.drums {
            pattern?.load(steps: drums.steps, accents: drums.accents)
        } else {
            pattern?.clear()
        }
        pianoRoll?.allNotesOff()
        pianoRoll?.load(clip.melody?.notes ?? [])
        pianoRoll?.setClipAutomation(clip.automation)   // this region's clip lanes (cycle 4)
        loadedRegionID = region.id
    }

    private func clearRoll() {
        pattern?.clear()
        pianoRoll?.allNotesOff()
        pianoRoll?.load([])
        pianoRoll?.setClipAutomation([])
        loadedRegionID = nil
    }

    // MARK: - Multi-roll fan-out (B08)

    /// Advance every SECONDARY lane's pump this tick and route its note events to the
    /// matching rack slot. Region onsets (`.load`) swap that slot's loop; gaps/overflow
    /// (`.clear`/`.silence`) release it; `.unchanged` lanes keep playing. Pure decision
    /// via `LaneVoiceScheduling.plan` → `LaneVoiceRackPlan.commands`; the primary lane is
    /// filtered out (the PianoRollModel plays it richly, so it must not double here).
    // INVARIANT: `pumps` is keyed by a lane's priority rank/slot, which is stable only
    // while `doc.midiLaneIDs` is immutable for the session (doc is captured once in
    // play()). Live lane add/remove/re-type mid-playback would shift ranks and strand a
    // slot-keyed pump (hung note / wrong voice) — if the timeline doc ever becomes
    // mutable during play, migrate `pumps` on the lane-set change before shipping it.
    private func fanOutSecondaryLanes(fromTick: Int, toTick: Int, step: Int) {
        guard let sink = slotNoteSink else { return }
        let steps = LaneVoiceScheduling
            .plan(in: doc, fromTick: fromTick, toTick: toTick, pool: &lanePool)
            .filter { $0.laneID != rollLane }
        for command in LaneVoiceRackPlan.commands(steps: steps, capacity: multiRollCapacity) {
            switch command {
            case .load(let slot, let clipID):
                var pump = pumps[slot] ?? LaneNotePump()
                if !pump.isEmpty { sink(slot, pump.reset()) }   // release the old take first
                pump.load(clips?.clip(id: clipID)?.melody?.notes ?? [])
                pumps[slot] = pump
            case .clear(let slot), .silence(let slot):
                if var pump = pumps[slot] {
                    sink(slot, pump.reset())
                    pumps[slot] = nil
                }
            }
        }
        // Fire this step on every live slot pump (offs before ons, per pump).
        for slot in pumps.keys.sorted() {
            guard var pump = pumps[slot] else { continue }
            let events = pump.step(step)
            pumps[slot] = pump
            if !events.isEmpty { sink(slot, events) }
        }
    }

    /// Release every sounding secondary voice and clear the fan-out state (stop/reset).
    private func flushPumps() {
        if let sink = slotNoteSink {
            for slot in pumps.keys.sorted() {
                if var pump = pumps[slot] {
                    sink(slot, pump.reset())
                    pumps[slot] = nil
                }
            }
        }
        pumps.removeAll()
        lanePool = LaneVoicePool(capacity: multiRollCapacity)
    }
}
