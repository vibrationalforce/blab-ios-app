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

    public init() {}

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
        isPlaying = true
        loadRollRegion(at: 0)            // whatever is under the playhead at the top
        if !pattern.isPlaying { pattern.play() }
    }

    /// Stop timeline-follow and the transport.
    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        pattern?.stop()
        pianoRoll?.allNotesOff()
    }

    /// Reset follow-state when the transport is stopped from OUTSIDE (the global
    /// Stop calls PatternEngine.stop() directly). Same contract as
    /// ArrangementPlayer.handleTransportStopped — no-op when already stopped.
    public func handleTransportStopped() {
        guard isPlaying else { return }
        isPlaying = false
        pianoRoll?.allNotesOff()
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
        loadedRegionID = region.id
    }

    private func clearRoll() {
        pattern?.clear()
        pianoRoll?.allNotesOff()
        pianoRoll?.load([])
        loadedRegionID = nil
    }
}
