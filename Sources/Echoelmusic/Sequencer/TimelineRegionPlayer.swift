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

    /// Start the cursor at the top of `startBar` (CLIP-5: play from the playhead /
    /// relocate). Like a fresh cursor, the FIRST advance() never counts as a wrap —
    /// it lands within `startBar` at the incoming step's phase.
    public init(startBar: Int) {
        barsCompleted = max(0, startBar)
    }

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
    /// Absolute song tick sounding now. Updated every transport step (~8 Hz while
    /// playing). `@ObservationIgnored` (audit LOW, freeze-law): today every reader is
    /// an imperative one-shot (play/seek handlers in WorkspaceView; ⛔ "/ArrangeTimelineView"
    /// stood here until #1107 — that view went with #121 Slice 4),
    /// so nothing observes it — shielding is behavior-identical AND removes the
    /// landmine where a future body read (e.g. a naive playhead) would register the
    /// whole view as an 8 Hz observer and tear down any open `.menu` Picker (the
    /// recurring menu-freeze ship-blocker). A playhead MUST self-drive in its own leaf
    /// (`TimelineView(.animation)`), never observe this. Direct/test reads are unaffected.
    @ObservationIgnored public private(set) var currentTick = 0
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
    /// Applies a lane's SynthPatch to its slot's rack voice on region load, so each
    /// lane sounds with its OWN timbre (TimelineLane.patch). Injected (AVFoundation
    /// stays in the app). `patch == nil` ⇒ the app falls back to the primary voice's
    /// patch, never the bare DDSP default. nil sink ⇒ per-lane patch simply unset.
    @ObservationIgnored public var slotPatchSink: ((_ slot: Int, _ patch: SynthPatch?) -> Void)?
    /// Applies a SECONDARY lane's whole-semitone TRANSPOSE to its slot's rack voice on
    /// region load (founder 2026-07-14, per-instrument Transpose), alongside the patch.
    /// Injected (AVFoundation stays in the app). nil ⇒ no per-lane transpose applied.
    @ObservationIgnored public var slotTransposeSink: ((_ slot: Int, _ semitones: Int) -> Void)?
    /// Applies the PRIMARY roll lane's whole-semitone TRANSPOSE to the roll voice when its
    /// region loads (the roll lane plays the rich PianoRollModel, not a rack slot, so it
    /// needs its own hook). nil ⇒ no transpose applied.
    @ObservationIgnored public var rollTransposeSink: ((_ semitones: Int) -> Void)?
    /// Applies a SECONDARY lane's fine DETUNE (cents) to its slot's rack voice on region
    /// load (founder 2026-07-14, per-instrument Detune), alongside patch + transpose.
    @ObservationIgnored public var slotDetuneSink: ((_ slot: Int, _ cents: Float) -> Void)?
    /// Applies the PRIMARY roll lane's fine DETUNE (cents) to the roll voice on region
    /// load (the roll lane plays PianoRollModel, not a rack slot). nil ⇒ no detune.
    @ObservationIgnored public var rollDetuneSink: ((_ cents: Float) -> Void)?
    /// Applies a SECONDARY lane's OKTAVER direction (−1/0/+1) to its slot's rack voice
    /// on region load AND live per step (founder 2026-07-14 "transpose detune und
    /// Oktaver"), alongside transpose + detune. nil ⇒ no octave doubling.
    @ObservationIgnored public var slotOctaveSink: ((_ slot: Int, _ direction: Int) -> Void)?
    /// Applies the PRIMARY roll lane's OKTAVER direction to the roll voice (the roll
    /// lane plays PianoRollModel, not a rack slot). nil ⇒ no octave doubling.
    @ObservationIgnored public var rollOctaveSink: ((_ direction: Int) -> Void)?
    /// S2-W2-6: the voice KIND the PRIMARY roll lane plays through. Fired at roll-
    /// region load (before the clip's notes) and reset to `.poly` on clear, so a
    /// drums / sub-bass primary lane routes the whole roll to that kind voice.
    /// Structural (an instrument change rides refreshStructure → loadRollRegion),
    /// so it is NOT re-pushed in refreshMixer. nil ⇒ poly, bit-identical.
    @ObservationIgnored public var rollKindSink: ((_ kind: LaneVoiceKind) -> Void)?
    /// #23 S2b: applies the PRIMARY roll lane's own SynthPatch to the roll voice when
    /// its region loads (the roll lane plays the global PolySynthVoice, so it needs its
    /// own hook — the secondary lanes use `slotPatchSink`). CRITICAL asymmetry vs the
    /// transpose/detune/octave sinks: those always fire with a neutral 0 default, but
    /// this one is CALLED ONLY WHEN the lane actually carries a patch — a nil primary
    /// patch must NOT clobber the live-edited global sound back to a default (that would
    /// wipe the user's current timbre on every region load). Golden gate: nil patch ⇒
    /// sink never called ⇒ the global voice is byte-identical to today.
    @ObservationIgnored public var rollPatchSink: ((_ patch: SynthPatch) -> Void)?
    /// Applies a SECONDARY lane's stereo PAN (−1…1) to its slot's rack voice — on
    /// region load AND live on a mid-play mixer edit (H4, healing wave 1: pan was
    /// silently inert for rack voices). Injected (AVFoundation stays in the app).
    @ObservationIgnored public var slotPanSink: ((_ slot: Int, _ pan: Float) -> Void)?
    /// Applies a SECONDARY lane's continuous GAIN (effectiveGain: mute/solo/level)
    /// to its slot's rack voice — load + live (H4; closes the B09 binary-gate gap:
    /// a 0.5 fader now sounds half, and a mid-take mute silences ringing notes at
    /// the mixer instead of letting them ring out). Injected like the pan sink.
    @ObservationIgnored public var slotGainSink: ((_ slot: Int, _ gain: Float) -> Void)?
    /// Pulls the CURRENT document from the store each transport step, so mid-play
    /// mixer edits (mute/solo/level/pan) reach playback — the play() snapshot alone
    /// froze them until the next region boundary (H4). Only the mixer fields are
    /// merged (see `TimelineDocument.mergeMixer`); structure stays snapshot-stable.
    @ObservationIgnored public var liveDocument: (() -> TimelineDocument?)?
    /// H5b: publishes which LANE a slot currently plays (from the playback
    /// snapshot — the one source whose ranks match the pumps), at region load/
    /// prime; nil on clear/silence/stop. The app binds it into the per-lane AU
    /// host so the note sink can route a slot to its lane's hosted instrument.
    @ObservationIgnored public var slotLaneSink: ((_ slot: Int, _ laneID: UUID?) -> Void)?
    /// S2-W2-4 ("Spur = Instrument"): publishes the voice KIND a slot should play
    /// through (from MultiRollFanout.voiceKind), so the app can rebind the slot's
    /// physical voice (drums kit / sub / poly) via LaneVoiceRack.setKind. Fired at
    /// exactly the sibling-sink sites (prime, window load, live merge) and reset to
    /// `.poly` on clear/silence/stop — a slot never keeps a stale kind. nil sink ⇒
    /// every slot stays poly (bit-identical to today, and the flag-OFF shape).
    @ObservationIgnored public var slotKindSink: ((_ slot: Int, _ kind: LaneVoiceKind) -> Void)?
    /// S2-W3 ("EchoelSampler klingt"): publishes the sample REF a slot's lane
    /// carries (TimelineLane.samplePath via MultiRollFanout.samplePath), so the
    /// app can load it into the slot's bound sampler unit
    /// (LaneVoiceRack.setSample). Fired at EXACTLY the slotKindSink sites, always
    /// AFTER the kind — the binding must land first so the sample loads into the
    /// unit the slot now plays. nil on clear/silence/stop, so a reused slot never
    /// keeps a stale sample memo. nil sink ⇒ sampler lanes stay unloaded (their
    /// unit renders silence until a sample arrives; routing is unaffected).
    @ObservationIgnored public var slotSampleSink: ((_ slot: Int, _ path: String?) -> Void)?
    @ObservationIgnored private var lanePool = LaneVoicePool(capacity: 0)
    @ObservationIgnored private var pumps: [Int: LaneNotePump] = [:]

    /// AUDIO lanes (A1, healing wave 1): the tested `AudioLanePlayer` coordinator,
    /// injected by the app with its device sink factory (`TimelineAudioSink`) —
    /// this file stays Foundation-only. nil ⇒ audio lanes stay silent (pre-A1).
    /// Primed on play, driven per transport window, released on every stop path.
    @ObservationIgnored public var audioLanes: AudioLanePlayer?

    // MARK: - Clip-Launch (P0 performance core — PLAN_TIMELINE_AUTOMATION_PERFORMANCE)

    /// The pure launch layer OVER the arrangement (Ableton lane-override): a lane
    /// with a LAUNCHED region plays that region's window looping instead of its
    /// arrangement regions; lanes without a launch play the arrangement untouched
    /// (while the engine `isIdle`, every path below is byte-identical to the
    /// pre-launch code — the golden gate). RUNTIME-ONLY state: never persisted,
    /// reset on play/stop/relocate. @ObservationIgnored deliberately — `tick`
    /// runs every transport step and must not register ~8 Hz observation churn;
    /// the UI observes `launchGeneration` instead.
    @ObservationIgnored private var launch = ClipLaunchEngine()

    /// Observation hook for the (P1) launch UI: bumps on every launch request and
    /// every fired boundary transition — low-frequency by construction (user taps
    /// + quantize boundaries), never per-tick, so a leaf view may read it.
    public private(set) var launchGeneration = 0

    /// Queue a MIDI or AUDIO region to LAUNCH on its lane at the next `quantize`
    /// boundary (`.off` = immediate, i.e. the next transport tick). The launched
    /// clip overrides its lane's arrangement and LOOPS over its own length until
    /// `stopLaunched`. No-op while stopped (P0: launch rides the running transport)
    /// and for bio/video lanes. S2 (audio-lane launch): the ClipLaunchEngine is
    /// spur-agnostic; an audio lane's transitions are dispatched to `audioLanes`
    /// (setLaunchOverride/clearLaunchOverride) in `applyLaunchTransitions`, which
    /// re-triggers the one-shot segment at each loop boundary (S1 golden gate).
    public func launchRegion(_ regionID: UUID, quantize: LaunchQuantize) {
        guard isPlaying else { return }
        let live = liveDocument?() ?? doc
        guard let region = live.regions.first(where: { $0.id == regionID })
                ?? doc.regions.first(where: { $0.id == regionID }) else { return }
        guard let lane = live.lanes.first(where: { $0.id == region.laneID })
                ?? doc.lanes.first(where: { $0.id == region.laneID }),
              (lane.kind == .midi || lane.kind == .audio), !lane.isBio else { return }
        launch.requestLaunch(laneID: region.laneID, regionID: regionID,
                             atTick: currentTick, quantize: quantize)
        launchGeneration &+= 1
    }

    /// Queue the lane's launched clip to STOP at the next `quantize` boundary —
    /// the lane returns to its arrangement content. A queued-but-unstarted
    /// launch is simply cancelled. No-op while stopped or idle.
    public func stopLaunched(laneID: UUID, quantize: LaunchQuantize) {
        guard isPlaying else { return }
        launch.requestStop(laneID: laneID, atTick: currentTick, quantize: quantize)
        launchGeneration &+= 1
    }

    /// The lane's launch state (`.idle` when nothing is launched) — the (P1) UI
    /// reads this to render play/queued/playing/stopping glyphs.
    public func launchState(laneID: UUID) -> LaneLaunchState {
        launch.state(laneID: laneID)
    }

    public init() {}

    /// Enable secondary-lane fan-out over a fixed rack of `capacity` voices. Called
    /// once by the app after the LaneVoiceRack is attached + started (flag-gated).
    /// The primary lane is unaffected; additional MIDI lanes route through `sink`.
    public func enableMultiRoll(
        capacity: Int,
        sink: @escaping (_ slot: Int, _ events: [LaneNotePump.Event]) -> Void,
        patchSink: ((_ slot: Int, _ patch: SynthPatch?) -> Void)? = nil
    ) {
        let cap = max(0, capacity)
        multiRollCapacity = cap
        lanePool = LaneVoicePool(capacity: cap)
        slotNoteSink = sink
        slotPatchSink = patchSink
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

    /// Start playing `document` from the bar containing `fromTick` (CLIP-5: the
    /// playhead the user parked — 0 = the top, the old behavior). No-op if the
    /// document has no MIDI (roll) lane or no regions — nothing to chain.
    /// GRANULARITY: the start folds to the BAR — the shared PatternEngine always
    /// starts its 16-step phase at 0, so a mid-bar start tick is not representable
    /// at the transport layer (the within-bar phase belongs to the pattern; exact
    /// mid-bar locate is the same M2-class refinement as mid-bar region phase).
    /// A tick beyond the song end folds to the top, like the loop wrap.
    public func play(
        document: TimelineDocument,
        clips: ClipStore,
        pattern: PatternEngine,
        pianoRoll: PianoRollModel,
        fromTick: Int = 0
    ) {
        // A song is playable when ANY playable lane has content — a MIDI (roll)
        // lane, or an audio lane (A1: a pure-audio arrangement must sound too;
        // the old rollLaneID-only guard silenced it).
        guard document.rollLaneID != nil || !document.audioLaneIDs.isEmpty,
              !document.regions.isEmpty else { return }
        self.doc = document
        self.clips = clips
        self.pattern = pattern
        self.pianoRoll = pianoRoll
        self.rollLane = document.rollLaneID
        self.loopTicks = Self.loopTicks(for: document)
        let startTick = Self.barStartTick(for: fromTick, loopTicks: loopTicks)
        self.cursor = TimelinePlaybackCursor(startBar: startTick / TimelineTime.ticksPerBar)
        self.lastTick = startTick
        self.currentTick = startTick
        // Fresh multi-roll state: release any lingering take (symmetric with stop —
        // never drop a sounding pitch without its note-off), clear slots, rebuild pool.
        flushPumps()
        launch.removeAll()   // launch state never survives a transport reset (P0)
        audioLanes?.clearAllLaunchOverrides()   // S2: pair the audio override reset (prime re-arms the arrangement below)
        isPlaying = true
        pianoRoll.setTimelineAutomation(document.automation)   // arrangement automation (cycle 5)
        pianoRoll.setTimelineAutomationTick(startTick)
        loadRollRegion(at: startTick)            // whatever is under the playhead
        primeSecondaryLanes(at: startTick)       // secondary lanes active at the start bar
        audioLanes?.prime(in: document, atTick: startTick, bpm: pattern.tempo)   // audio lanes (A1)
        if !pattern.isPlaying { pattern.play(cause: .timelineRegion) }
    }

    /// The song-absolute BAR-start tick for a requested locate tick: floors to the
    /// bar, folds a beyond-end tick back into the song (like the loop wrap). Pure.
    nonisolated static func barStartTick(for tick: Int, loopTicks: Int) -> Int {
        var t = (max(0, tick) / TimelineTime.ticksPerBar) * TimelineTime.ticksPerBar
        if loopTicks > 0 { t %= loopTicks } else { t = 0 }
        return t
    }

    /// CLIP-5: jump the PLAYING session to the bar containing `tick` (playhead
    /// drag-drop). A locate is a hard cut — sounding voices are released (a jump
    /// must not smear old-position sustains into the new bar), then every layer
    /// re-primes through the SAME paths play()/refreshStructure use — at the
    /// PHASE-CONSISTENT anchor tick, not the bar downbeat: the shared pattern's
    /// 16-step phase keeps running through a jump, so the next transport step
    /// lands at `bar + patternPhase`. Anchoring the audio-lane files (and the
    /// window edge) there keeps audio and MIDI in lockstep (review HIGH: a
    /// downbeat anchor lagged audio behind MIDI by up to 15/16 bar until the
    /// next onset) — the exact recipe refreshStructure (lastTick) and the loop
    /// wrap (newTick) already follow. Bar-granular target (see play(fromTick:)).
    /// No-op while stopped — the parked playhead is picked up by play(fromTick:).
    /// NEVER call this per drag frame — drag END only (a continuous scrub through
    /// this path is a relocate storm; HARNESS_LEDGER 2026-07-16).
    public func relocate(toTick tick: Int) {
        guard isPlaying else { return }
        let target = Self.barStartTick(for: tick, loopTicks: loopTicks)
        // PatternEngine.currentStep is the NEXT step its timer fires (advance()
        // plays `currentStep`, then increments) — exactly the phase the next
        // transportStep will carry. A stopped/absent pattern anchors at 0.
        let nextStep = (pattern?.isPlaying == true) ? (pattern?.currentStep ?? 0) : 0
        let anchor = Self.relocateAnchorTick(targetBarTick: target, nextPatternStep: nextStep)
        pianoRoll?.allNotesOff()   // hard locate: cut the primary roll's ringing notes
        flushPumps()               // offs through current bindings (H5b), slots released
        launch.removeAll()         // P0 policy: a locate is a hard cut — launches do not
                                   // survive it (their boundaries reference the old
                                   // position); the arrangement re-primes below.
        audioLanes?.clearAllLaunchOverrides()   // S2: audio override dies with the locate; prime re-arms below
        cursor = TimelinePlaybackCursor(startBar: target / TimelineTime.ticksPerBar)
        lastTick = anchor
        currentTick = anchor
        loadedRegionID = nil       // force a fresh region decision at the target
        loadRollRegion(at: anchor)
        pianoRoll?.setTimelineAutomationTick(anchor)
        primeSecondaryLanes(at: anchor)
        audioLanes?.prime(in: doc, atTick: anchor, bpm: pattern?.tempo ?? 120)
        log.log(.info, category: .audio, "timeline: relocate to tick \(anchor)")
    }

    /// The phase-consistent tick a relocate must anchor at: the target bar's
    /// downbeat plus the pattern phase the NEXT transport step will carry
    /// (clamped 0…15). Pure — the seeded cursor's next advance(step:) produces
    /// exactly this tick, so the post-relocate window (lastTick → newTick] is
    /// empty and nothing double-fires.
    nonisolated static func relocateAnchorTick(targetBarTick: Int, nextPatternStep: Int) -> Int {
        let phase = min(max(nextPatternStep, 0), 15)
        return targetBarTick + phase * TimelineTime.ticksPerTransportStep
    }

    /// Stop timeline-follow and the transport.
    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        pattern?.stop()
        pianoRoll?.allNotesOff()
        launch.removeAll()                     // launches die with the transport (P0)
        audioLanes?.clearAllLaunchOverrides()  // S2: audio override reset paired with stopAll below
        flushPumps()                           // release every secondary-lane voice
        audioLanes?.stopAll()                  // release every audio lane (A1)
        pianoRoll?.setTimelineAutomation([])   // release the arrangement layer (cycle 5)
    }

    /// Reset follow-state when the transport is stopped from OUTSIDE (the global
    /// Stop calls PatternEngine.stop() directly). Same contract as
    /// ArrangementPlayer.handleTransportStopped — no-op when already stopped.
    public func handleTransportStopped() {
        guard isPlaying else { return }
        isPlaying = false
        pianoRoll?.allNotesOff()
        launch.removeAll()                     // launches die with the transport (P0)
        audioLanes?.clearAllLaunchOverrides()  // S2: audio override reset paired with stopAll below
        flushPumps()                           // release every secondary-lane voice
        audioLanes?.stopAll()                  // release every audio lane (A1)
        pianoRoll?.setTimelineAutomation([])   // release the arrangement layer (cycle 5)
    }

    /// Fed every transport step (0…15) by the host. Advances the absolute position,
    /// loops at the song's whole-bar end (or stops), and (re)loads the roll lane's
    /// clip on each region onset.
    public func transportStep(_ step: Int) {
        guard isPlaying else { return }
        // H4: pull live mixer state (mute/solo/level/pan) into the playback snapshot
        // BEFORE this step's gates run, so a mid-region mixer edit is heard now —
        // not at the next region boundary.
        refreshMixer()
        // CLIP-3: pull STRUCTURE edits (region move/trim/split/delete/add, lane
        // add/remove/reorder, automation) in as well — pre-fix the song played the
        // play()-time snapshot until Stop+Play while the UI showed a different
        // arrangement. Runs BEFORE this step's window so the edit sounds this step.
        refreshStructure()
        var newTick = cursor.advance(step: step)
        var wrapped = false
        if loopTicks > 0, newTick >= loopTicks {
            if loopEnabled {
                cursor = TimelinePlaybackCursor()
                newTick = cursor.advance(step: step)   // restart within bar 0
                wrapped = true
            } else {
                stop()
                return
            }
        }
        // P0 Clip-Launch: the launch layer rides the SAME transport tick — no
        // second clock. On a song-loop wrap the whole launch timebase folds back
        // by the loop length FIRST (boundaries and loopTicks are whole bars, so
        // grid alignment survives), then due boundaries fire. An idle engine
        // emits nothing and every path below is byte-identical (golden gate).
        if wrapped, !launch.isIdle { launch.shift(by: -loopTicks) }
        // S3: fold the AUDIO override timebase with the same wrap, so a launched
        // audio clip keeps looping across the song wrap (the wrap re-prime below now
        // skips overridden lanes, so it no longer clobbers the launch).
        if wrapped { audioLanes?.shiftLaunchOverrides(by: -loopTicks) }
        let launchTransitions: [LaunchTransition] = launch.isIdle ? [] : launch.tick(now: newTick)
        if !launchTransitions.isEmpty {
            applyLaunchTransitions(launchTransitions, atTick: newTick, step: step)
            launchGeneration &+= 1
        }
        // A roll-lane transition this tick already made the region decision at
        // newTick (launched load / back-to-arrangement) — skip the incremental
        // arrangement event; an OVERRIDDEN roll lane skips it every tick.
        let rollLaunchDecided = launchTransitions.contains { $0.laneID == rollLane }
        if let lane = rollLane, !rollLaunchDecided, !launch.isOverriding(laneID: lane) {
            switch TimelineScheduling.laneEvent(in: doc, laneID: lane, fromTick: lastTick, toTick: newTick) {
            case .unchanged: break
            case .load(let region): loadClip(region, atTick: newTick, step: step)
            case .clear: clearRoll()
            }
        }
        // Multi-roll: fan the SAME tick window out over the additional MIDI lanes so
        // they sound simultaneously on their own rack voices (no-op when capacity 0
        // or the song has only the one primary lane).
        if multiRollCapacity > 0 {
            fanOutSecondaryLanes(fromTick: lastTick, toTick: newTick, step: step)
        }
        // AUDIO lanes ride the same tick window (A1): region onsets start their
        // file segment, gaps stop the lane — the tested AudioLanePlayer decides.
        // On a SONG-LOOP WRAP a region active on both sides reads `.unchanged`,
        // but its scheduled one-shot segment is finite/out of phase — the lane
        // must be force-restarted at the wrapped position (audio review HIGH 1).
        if wrapped {
            audioLanes?.prime(in: doc, atTick: newTick, bpm: pattern?.tempo ?? 120)
            // S3a: `prime` warms every lane's files but SKIPS overridden lanes, so a
            // launched audio loop whose boundary coincides with the song wrap would
            // lose its re-trigger there (one silent bar per song loop, audio/MIDI out
            // of lockstep). Drive the overrides across the wrap in the folded frame the
            // anchors were just shifted into — `loopWrapped` re-fires a boundary-aligned
            // segment and leaves a spanning one playing (audio-thread review).
            audioLanes?.applyWrappedOverrides(in: doc, fromTick: lastTick - loopTicks,
                                              toTick: newTick, bpm: pattern?.tempo ?? 120)
        } else {
            audioLanes?.apply(in: doc, fromTick: lastTick, toTick: newTick,
                              bpm: pattern?.tempo ?? 120)
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
        // Per-instrument transpose/detune/octave + KIND for the PRIMARY lane —
        // pushed BEFORE its notes load (extracted so the launch path applies the
        // same lane voice; see applyRollLaneVoice).
        applyRollLaneVoice()
        loadClip(region, atTick: tick, step: 0)
    }

    /// Load a region's clip WINDOWED to the region (M1b, audit wf_9c6f33b7 — the
    /// old flat `pianoRoll.load(melody)` played only bar 1 of every clip, ignored
    /// front-trim/split offsets, and cut sustains with an allNotesOff at every
    /// boundary). Now: contentOffset → tick window → per-bar slices → region-
    /// relative bar cycling via `loadRegionArrangement` (seamless while playing).
    /// `tick` = the song-absolute onset/seek tick; `step` = the within-bar
    /// transport step it lands on (0 ⇒ the roll's trigger(0) still runs this tick).
    /// KNOWN CONSTRAINT (reviewer M1b): the roll is bar-locked to the GLOBAL grid,
    /// so a region starting mid-bar plays its content pinned to global bar lines
    /// (content ticks before the first global line are skipped) — not phase-shifted
    /// to the region start. Bar-aligned regions (the default snap) are exact; the
    /// region-relative phase for free placements is the M2 cycle.
    private func loadClip(_ region: TimelineRegion, atTick tick: Int, step: Int) {
        guard let clip = clips?.clip(id: region.clipID) else {
            clearRoll()
            return
        }
        if let drums = clip.drums {
            pattern?.load(steps: drums.steps, accents: drums.accents)
        } else {
            pattern?.clear()
        }
        // Trim-in: the TICK offset is authoritative for MIDI (exact at any tempo —
        // reviewer HIGH: the seconds field re-converted at play-time tempo shifts
        // the window when the tempo changed since the edit). Legacy regions
        // (pre-M1b, ticks == 0 but seconds set) fall back to the conversion at the
        // current tempo. Step-aligned either way: the roll is a step-grid
        // instrument, an off-grid window would shift every note off the trigger grid.
        let bpm = pattern?.tempo ?? 120
        let rawOffset = region.contentOffsetTicks > 0
            ? region.contentOffsetTicks
            : RegionNoteWindow.offsetTicks(contentOffsetSeconds: region.contentOffsetSeconds,
                                           bpm: bpm)
        let offset = RegionNoteWindow.stepAligned(rawOffset)
        let windowed = RegionNoteWindow.windowed(notes: clip.melody?.notes ?? [],
                                                 offsetTicks: offset,
                                                 lengthTicks: region.lengthTicks)
        let bars = RegionNoteWindow.barSlices(notes: windowed,
                                              regionLengthTicks: region.lengthTicks)
        let startBar = max(0, tick - region.startTick) / TimelineTime.ticksPerBar
        pianoRoll?.loadRegionArrangement(bars, startBar: startBar,
                                         atStepZero: step == 0,
                                         playing: pattern?.isPlaying ?? false)
        pianoRoll?.setClipAutomation(clip.automation)   // this region's clip lanes (cycle 4)
        loadedRegionID = region.id
    }

    private func clearRoll() {
        pattern?.clear()
        pianoRoll?.allNotesOff()
        pianoRoll?.load([])
        pianoRoll?.setClipAutomation([])
        rollKindSink?(.poly)   // S2-W2-6: no region ⇒ back to the poly voice
        loadedRegionID = nil
    }

    /// M1c (CLIP-1): the region's windowed, bar-sliced melody for a SECONDARY lane
    /// pump — the EXACT windowing `loadClip` applies to the primary roll (tick-
    /// authoritative offset, legacy seconds fallback, step-aligned, region-length
    /// bar slices). Pre-fix, secondary lanes loaded the FULL clip melody flat and
    /// the pump's %16 fold superimposed every bar of a multi-bar clip.
    private func windowedBars(for region: TimelineRegion) -> [[Note]] {
        let clipNotes = clips?.clip(id: region.clipID)?.melody?.notes ?? []
        let bpm = pattern?.tempo ?? 120
        let rawOffset = region.contentOffsetTicks > 0
            ? region.contentOffsetTicks
            : RegionNoteWindow.offsetTicks(contentOffsetSeconds: region.contentOffsetSeconds,
                                           bpm: bpm)
        let offset = RegionNoteWindow.stepAligned(rawOffset)
        let windowed = RegionNoteWindow.windowed(notes: clipNotes,
                                                 offsetTicks: offset,
                                                 lengthTicks: region.lengthTicks)
        return RegionNoteWindow.barSlices(notes: windowed,
                                          regionLengthTicks: region.lengthTicks)
    }

    // MARK: - Multi-roll fan-out (B08)

    /// Advance every SECONDARY lane's pump this tick and route its note events to the
    /// matching rack slot. Region onsets (`.load`) swap that slot's loop; gaps/overflow
    /// (`.clear`/`.silence`) release it; `.unchanged` lanes keep playing. Pure decision
    /// via `LaneVoiceScheduling.plan` → `LaneVoiceRackPlan.commands`; the primary lane is
    /// filtered out (the PianoRollModel plays it richly, so it must not double here).
    // INVARIANT: `pumps` is keyed by a lane's priority rank/slot, which is stable only
    // while `doc.midiLaneIDs` is unchanged. Since CLIP-3 the doc IS mutable during
    // play — refreshStructure() upholds the invariant conservatively: any structural
    // change (incl. lane add/remove/re-type) flushes ALL pumps (offs through the OLD
    // ranks/bindings) BEFORE the snapshot swap, then re-primes on the new ranks. No
    // pump ever survives a rank shift.
    private func fanOutSecondaryLanes(fromTick: Int, toTick: Int, step: Int) {
        guard let sink = slotNoteSink else { return }
        // P0 Clip-Launch: a LAUNCHED secondary lane ignores ARRANGEMENT onsets/
        // gaps — its pump keeps the launched clip until the stop transition
        // restores the arrangement. The step keeps its POSITION in the array
        // (rank == slot in LaneVoiceRackPlan.commands, which enumerates by
        // index): filtering the lane OUT would shift every later lane one slot
        // up mid-play. Idle engine ⇒ the map is the identity (golden).
        let steps = LaneVoiceScheduling
            .plan(in: doc, fromTick: fromTick, toTick: toTick, pool: &lanePool)
            .filter { $0.laneID != rollLane }
            .map { s -> LanePlaybackStep in
                guard !launch.isIdle, launch.isOverriding(laneID: s.laneID) else { return s }
                return LanePlaybackStep(laneID: s.laneID, event: .unchanged, slot: s.slot)
            }
        for command in LaneVoiceRackPlan.commands(steps: steps, capacity: multiRollCapacity) {
            switch command {
            case .load(let slot, let clipID):
                // ORDER LAW (H5b): release the OLD take through the slot's OLD
                // binding BEFORE re-binding/re-timbring — offs sent after the
                // re-bind would land in the NEW lane's AU and hang the old one.
                var pump = pumps[slot] ?? LaneNotePump()
                if !pump.isEmpty { sink(slot, pump.reset()) }
                slotLaneSink?(slot, MultiRollFanout.laneID(forSlot: slot, in: doc, rollLane: rollLane))
                // S2-W2-4: bind the slot's KIND (drums/sub/poly) BEFORE patch/gain/
                // notes — the app's facade routes every following per-slot sink by the
                // CURRENT binding, so the kind must land first (else patch/notes hit
                // the old physical voice). Rebinding releases the old voice internally.
                slotKindSink?(slot, MultiRollFanout.voiceKind(forSlot: slot, in: doc, rollLane: rollLane))
                // S2-W3: the lane's sample ref, AFTER the kind (binding first, then
                // the sample lands in the bound sampler unit).
                slotSampleSink?(slot, MultiRollFanout.samplePath(forSlot: slot, in: doc, rollLane: rollLane))
                // Per-lane timbre: set this slot's voice to its lane's own patch BEFORE
                // its first notes (apply() enqueues ahead of the notes in the voice's
                // render drain, so timbre precedes attack). nil ⇒ app falls back.
                slotPatchSink?(slot, MultiRollFanout.patch(forSlot: slot, in: doc, rollLane: rollLane))
                slotTransposeSink?(slot, MultiRollFanout.transpose(forSlot: slot, in: doc, rollLane: rollLane))
                slotDetuneSink?(slot, MultiRollFanout.detune(forSlot: slot, in: doc, rollLane: rollLane))
                slotOctaveSink?(slot, MultiRollFanout.octave(forSlot: slot, in: doc, rollLane: rollLane))
                // H4: the slot voice may be reused from another lane — reset its
                // mixer position/level to THIS lane's values before its first notes.
                slotPanSink?(slot, MultiRollFanout.pan(forSlot: slot, in: doc, rollLane: rollLane))
                slotGainSink?(slot, MultiRollFanout.gain(forSlot: slot, in: doc, rollLane: rollLane))
                // M1c: window + bar-slice the region's melody exactly like the
                // primary roll (loadClip). Defensive flat fallback when the lane's
                // active region can't be resolved (should not happen: the .load
                // command IS this tick's onset).
                if let laneID = MultiRollFanout.laneID(forSlot: slot, in: doc, rollLane: rollLane),
                   let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: toTick),
                   region.clipID == clipID {
                    pump.load(bars: windowedBars(for: region),
                              startBar: max(0, toTick - region.startTick) / TimelineTime.ticksPerBar)
                } else {
                    pump.load(clips?.clip(id: clipID)?.melody?.notes ?? [])
                }
                pumps[slot] = pump
            case .clear(let slot), .silence(let slot):
                if var pump = pumps[slot] {
                    sink(slot, pump.reset())
                    pumps[slot] = nil
                }
                slotLaneSink?(slot, nil)   // offs above went through the old binding
                slotKindSink?(slot, .poly) // reset kind so a reused slot never keeps a stale drum/sub voice
                slotSampleSink?(slot, nil) // and the sample memo (same reuse law)
            }
        }
        // Fire this step on every live slot pump (offs before ons, per pump). A
        // muted/soloed-away/0-level secondary lane is gated like the primary roll
        // lane (rollSlotGain→laneAudible): drop its note-ONs but still deliver
        // note-OFFs so nothing hangs when a lane is muted mid-take. Already-ringing
        // notes are handled by the CONTINUOUS gain path (H4/B09: refreshMixer →
        // slotGainSink → voice mixer volume), which lands 0 on a mute — the mixer
        // silences them immediately without a hard note-cut.
        for slot in pumps.keys.sorted() {
            guard var pump = pumps[slot] else { continue }
            let events = pump.step(step)
            pumps[slot] = pump
            guard !events.isEmpty else { continue }
            if slotAudible(slot) {
                sink(slot, events)
            } else {
                let offs = events.filter { !$0.isOn }
                if !offs.isEmpty { sink(slot, offs) }
            }
        }
    }

    /// Prime the secondary lanes whose region is ACTIVE at `tick` (play()/seek), so a
    /// lane with a clip at the downbeat sounds from step 0. The onset-based window
    /// fan-out reads `.unchanged` for a region already active at the start and would
    /// never load it — the primary lane avoids this via loadRollRegion(at:); this is
    /// its secondary-lane twin. Pure decision via MultiRollFanout.activeLoads.
    private func primeSecondaryLanes(at tick: Int) {
        guard multiRollCapacity > 0, let sink = slotNoteSink else { return }
        for load in MultiRollFanout.activeLoads(in: doc, at: tick,
                                                rollLane: rollLane, capacity: multiRollCapacity) {
            // P0 Clip-Launch: a launched lane keeps its launched clip through
            // re-primes — reapplyLaunched (structure path) reloads it; the
            // arrangement must not overwrite it here.
            guard !launch.isOverriding(laneID: load.laneID) else { continue }
            // Same ORDER LAW as the window fan-out: old take out through the
            // old binding, THEN re-bind + re-timbre (H5b).
            var pump = pumps[load.slot] ?? LaneNotePump()
            if !pump.isEmpty { sink(load.slot, pump.reset()) }
            slotLaneSink?(load.slot, load.laneID)
            // S2-W2-4: kind before patch/gain/notes (same ordering law as the fan-out).
            slotKindSink?(load.slot, MultiRollFanout.voiceKind(forSlot: load.slot, in: doc, rollLane: rollLane))
            // S2-W3: sample after kind (same ordering law as the fan-out).
            slotSampleSink?(load.slot, MultiRollFanout.samplePath(forSlot: load.slot, in: doc, rollLane: rollLane))
            slotPatchSink?(load.slot, load.patch)
            slotTransposeSink?(load.slot, MultiRollFanout.transpose(forSlot: load.slot, in: doc, rollLane: rollLane))
            slotDetuneSink?(load.slot, MultiRollFanout.detune(forSlot: load.slot, in: doc, rollLane: rollLane))
            slotOctaveSink?(load.slot, MultiRollFanout.octave(forSlot: load.slot, in: doc, rollLane: rollLane))
            slotPanSink?(load.slot, MultiRollFanout.pan(forSlot: load.slot, in: doc, rollLane: rollLane))
            slotGainSink?(load.slot, MultiRollFanout.gain(forSlot: load.slot, in: doc, rollLane: rollLane))
            // M1c: same windowing as the fan-out — and the PRIME case is exactly
            // where startBar matters (seek / region already active mid-way).
            if let region = TimelineScheduling.activeRegion(in: doc, laneID: load.laneID, at: tick),
               region.clipID == load.clipID {
                pump.load(bars: windowedBars(for: region),
                          startBar: max(0, tick - region.startTick) / TimelineTime.ticksPerBar)
            } else {
                pump.load(clips?.clip(id: load.clipID)?.melody?.notes ?? [])
            }
            pumps[load.slot] = pump
        }
    }

    /// H4 (live mixer): merge the store's CURRENT mixer-like fields into the playback
    /// snapshot and — only when something actually changed — re-push every live
    /// lane's sink-applied voice values. Runs once per transport step (~8 Hz);
    /// the merge is a small value compare, the push fires only on real edits.
    /// CLIP-3 review: transpose/detune ride this SAME path (they are voice-sink
    /// fields exactly like pan) — a Transpose/Detune scrub during playback lands
    /// live here instead of triggering refreshStructure's relocate at ~8 Hz, and
    /// this closes the old gap where a secondary lane's transpose only landed on
    /// its next region load. Covers `pumps.keys` (loaded slots) only: a slot
    /// cleared this bar has had its note-offs sent, so at most its envelope
    /// RELEASE TAIL rings at the old values — accepted; the next `.load`
    /// re-pushes that slot's values anyway.
    private func refreshMixer() {
        guard let fresh = liveDocument?() else { return }
        guard doc.mergeMixer(from: fresh) else { return }
        if let lane = rollLane, let live = doc.lanes.first(where: { $0.id == lane }) {
            rollTransposeSink?(live.transposeSemitones)
            rollDetuneSink?(live.detuneCents)
            rollOctaveSink?(live.octaveDouble)
        }
        guard multiRollCapacity > 0 else { return }
        for slot in pumps.keys.sorted() {
            slotGainSink?(slot, MultiRollFanout.gain(forSlot: slot, in: doc, rollLane: rollLane))
            slotPanSink?(slot, MultiRollFanout.pan(forSlot: slot, in: doc, rollLane: rollLane))
            slotTransposeSink?(slot, MultiRollFanout.transpose(forSlot: slot, in: doc, rollLane: rollLane))
            slotDetuneSink?(slot, MultiRollFanout.detune(forSlot: slot, in: doc, rollLane: rollLane))
            slotOctaveSink?(slot, MultiRollFanout.octave(forSlot: slot, in: doc, rollLane: rollLane))
        }
    }

    /// The per-lane mute/solo/level gate for a slot's lane (rank→lane), matching the
    /// primary roll lane. Unknown slot ⇒ audible (never silence on a mapping gap).
    private func slotAudible(_ slot: Int) -> Bool {
        guard let laneID = MultiRollFanout.laneID(forSlot: slot, in: doc, rollLane: rollLane) else { return true }
        return MultiRollFanout.audible(doc, laneID: laneID)
    }

    /// CLIP-3: relocate the playing session onto an edited document. Gate is the
    /// pure `structurallyEqual` — mixer-only edits never land here (refreshMixer's
    /// merge is cheaper and never re-attacks a voice). Relocation is the honest
    /// DAW "chase": flush the secondary voices (offs through the OLD ranks/
    /// bindings — the H5b order law; ranks may have shifted with the lane set),
    /// swap the snapshot, and re-drive every layer at the current position via
    /// the SAME prime paths play() and the song-loop wrap already exercise.
    /// The primary roll reloads only when ITS active region actually changed —
    /// an edit on another lane must not restage the sounding melody.
    private func refreshStructure() {
        guard let fresh = liveDocument?() else { return }
        guard !TimelineDocument.structurallyEqual(doc, fresh) else { return }
        let oldActive = rollLane.flatMap {
            TimelineScheduling.activeRegion(in: doc, laneID: $0, at: lastTick)
        }
        // P0 Clip-Launch: remember whether the (old) roll lane was overridden —
        // if its launch gets pruned below, the roll still holds LAUNCHED content
        // and must be handed back to the arrangement even when the arrangement's
        // active region did not change.
        let oldRollOverridden = rollLane.map { launch.isOverriding(laneID: $0) } ?? false
        flushPumps()
        doc = fresh
        rollLane = fresh.rollLaneID
        loopTicks = Self.loopTicks(for: fresh)   // grew/shrank: the wrap logic reads it next step
        pianoRoll?.setTimelineAutomation(fresh.automation)
        // P0 Clip-Launch: the edit may have deleted a launched region or lane —
        // prune those states silently (voices were flushed above; the prime
        // paths below cover the freed lanes). Surviving launches are re-applied
        // after the prime so their content reflects the EDITED document.
        if !launch.isIdle {
            launch.prune(validLaneIDs: Set(fresh.lanes.map(\.id)),
                         validRegionIDs: Set(fresh.regions.map(\.id)))
        }
        // S3: prune AUDIO overrides for a deleted launched region/lane too (its audio
        // is stopped here); the prime below re-arms freed lanes, and skips surviving
        // overridden lanes so an edit on another lane never clobbers a live launch.
        audioLanes?.pruneLaunchOverrides(validLaneIDs: Set(fresh.lanes.map(\.id)),
                                         validRegionIDs: Set(fresh.regions.map(\.id)))
        let newActive = rollLane.flatMap {
            TimelineScheduling.activeRegion(in: doc, laneID: $0, at: lastTick)
        }
        if let lane = rollLane, launch.isOverriding(laneID: lane) {
            reapplyLaunched(laneID: lane, atTick: lastTick)   // launched roll re-windows
        } else if oldRollOverridden || oldActive != newActive {
            loadedRegionID = nil                 // force a fresh region decision
            loadRollRegion(at: lastTick)         // loadClip or clearRoll, mid-region aware
        }
        primeSecondaryLanes(at: lastTick)        // skips overridden lanes (see guard there)
        for laneID in launch.overriddenLaneIDs where laneID != rollLane {
            reapplyLaunched(laneID: laneID, atTick: lastTick)
        }
        audioLanes?.prime(in: doc, atTick: lastTick, bpm: pattern?.tempo ?? 120)
        log.log(.info, category: .audio, "timeline: structure edit pulled into playback at tick \(lastTick)")
    }

    /// Release every sounding secondary voice and clear the fan-out state (stop/reset).
    private func flushPumps() {
        for slot in pumps.keys.sorted() {
            if let sink = slotNoteSink, var pump = pumps[slot] {
                sink(slot, pump.reset())   // offs through the still-current binding
                pumps[slot] = nil
            }
            slotLaneSink?(slot, nil)       // then release the slot's lane binding
            slotKindSink?(slot, .poly)     // and reset the kind so a restart starts poly-clean
            slotSampleSink?(slot, nil)     // and the sample memo (stale-sample reuse law)
        }
        pumps.removeAll()
        lanePool = LaneVoicePool(capacity: multiRollCapacity)
    }

    // MARK: - Clip-Launch application (P0 — the AUDIO side of ClipLaunchEngine)
    //
    // ClipLaunchEngine is pure state; these helpers are its ONLY audio effect. They
    // reuse the SAME load paths the arrangement uses (loadClip for the roll lane, the
    // secondary-slot sink+pump sequence for rack lanes) so a LAUNCHED region sounds
    // byte-identical to that region playing from the arrangement — the launch layer
    // only changes WHICH region a lane windows, never HOW it is rendered. While the
    // engine `isIdle` none of these run (the golden gate): launch adds zero cost to
    // plain arrangement playback.
    //
    // PHASE CAVEAT (P0, documented): a launched clip is loaded as a normal region
    // window. The SECONDARY path anchors the loop phase to the launch timebase
    // (`LaunchedRegion.startedAtTick` → whole-bar phase), so a launch fires from the
    // clip's top at its boundary and re-windows at the right whole bar after edits.
    // The ROLL path reuses `loadClip`, whose startBar is the ARRANGEMENT phase
    // (tick − region.startTick). Both loop correctly in WHOLE BARS; exact clip-internal
    // (sub-bar) phase offset is a follow-up slice — `ClipLaunchEngine.loopedContentTick`
    // is the pure reference for it.

    /// Apply this tick's launch transitions to the audio side. `.started`/`.switched`
    /// window the launched region onto its lane (a switch loads exactly ONCE — the new
    /// region — never a double load); `.stopped` hands the lane back to its arrangement
    /// at `tick`. Roll lane (== rollLane) vs. a secondary rack slot are dispatched
    /// separately; a region that vanished between request and boundary falls silently
    /// back to the arrangement.
    private func applyLaunchTransitions(_ transitions: [LaunchTransition], atTick tick: Int, step: Int) {
        let bpm = pattern?.tempo ?? 120
        for t in transitions {
            // S2 (audio-lane launch): an AUDIO lane's transition drives the
            // AudioLanePlayer override (loop the launched segment / hand back to the
            // arrangement), NOT the roll/rack MIDI path. The launched region is a
            // TIMELINE region, already file-primed on that lane at play()/refresh —
            // so setLaunchOverride's play() cannot trigger a mid-song node attach
            // (obligation from PLAN_AUDIO_CLIP_LAUNCH: off-timeline clips would need
            // an explicit preload, not launchable today).
            if doc.lanes.first(where: { $0.id == t.laneID })?.kind == .audio {
                // Anchor on the transition's BOUNDARY tick (t.atTick), not the sampled
                // `tick`, so the launched loop's phase aligns to the musical bar (the
                // segment still starts playing now; only its loop timebase is anchored).
                switch t.kind {
                case .started(let regionID), .switched(_, let regionID):
                    if let region = doc.regions.first(where: { $0.id == regionID }) {
                        // START: anchor the loop timebase on the BOUNDARY (t.atTick).
                        audioLanes?.setLaunchOverride(region, laneID: t.laneID,
                                                      atTick: t.atTick, in: doc, bpm: bpm)
                    } else {
                        // Vanished ⇒ hand back to the arrangement at the CURRENT playhead
                        // (tick), matching the MIDI .stopped path + apply's convention.
                        audioLanes?.clearLaunchOverride(laneID: t.laneID, atTick: tick,
                                                        in: doc, bpm: bpm)
                    }
                case .stopped:
                    // Hand back at the current playhead (tick), not the boundary — the
                    // arrangement resumes at the honest song position (MIDI-consistent).
                    audioLanes?.clearLaunchOverride(laneID: t.laneID, atTick: tick, in: doc, bpm: bpm)
                }
                continue
            }
            let isRoll = (t.laneID == rollLane)
            switch t.kind {
            case .started(let regionID), .switched(_, let regionID):
                guard let region = doc.regions.first(where: { $0.id == regionID }) else {
                    if isRoll {
                        loadedRegionID = nil
                        loadRollRegion(at: tick)
                    } else if let slot = secondarySlot(forLane: t.laneID) {
                        restoreSecondaryArrangement(laneID: t.laneID, slot: slot, at: tick)
                    }
                    continue
                }
                if isRoll {
                    applyRollLaneVoice()
                    loadClip(region, atTick: tick, step: step)
                } else if let slot = secondarySlot(forLane: t.laneID) {
                    loadSecondaryWindow(region, laneID: t.laneID, slot: slot,
                                        startBar: launchedStartBar(laneID: t.laneID, atTick: tick))
                }
            case .stopped:
                if isRoll {
                    loadedRegionID = nil
                    loadRollRegion(at: tick)          // arrangement region at this tick (mid-region aware)
                } else if let slot = secondarySlot(forLane: t.laneID) {
                    restoreSecondaryArrangement(laneID: t.laneID, slot: slot, at: tick)
                }
            }
        }
    }

    /// Push the PRIMARY roll lane's per-instrument voice params (transpose/detune/
    /// octave + KIND) for the CURRENT rollLane — extracted from `loadRollRegion` so the
    /// launch path applies the identical lane voice before a launched roll region's
    /// notes load. No roll lane (or a missing lane object) ⇒ no effect.
    private func applyRollLaneVoice() {
        guard let lane = rollLane else { return }
        // Byte-identical to the extracted loadRollRegion inline block: a MISSING
        // lane object still resets the voice to neutral (0/0/0/.poly) via the
        // `?? default` fallbacks — not an early return — so the golden gate holds
        // literally even on an inconsistent document (rollLane set, lane absent).
        let laneObj = doc.lanes.first(where: { $0.id == lane })
        rollTransposeSink?(laneObj?.transposeSemitones ?? 0)
        rollDetuneSink?(laneObj?.detuneCents ?? 0)
        rollOctaveSink?(laneObj?.octaveDouble ?? 0)
        rollKindSink?(laneObj?.builtinInstrument?.voiceKind ?? .poly)
        // #23 S2b: apply the primary lane's OWN patch AFTER the kind binds the voice
        // (so timbre lands on the correct poly/kind voice) and BEFORE the clip's notes
        // (apply() enqueues ahead of the attack in the voice's render drain, like the
        // secondary slotPatchSink). Guarded on non-nil: nil ⇒ keep the live global
        // sound untouched (the golden gate — see rollPatchSink's doc).
        if let patch = laneObj?.patch { rollPatchSink?(patch) }
    }

    /// Re-window the region currently LAUNCHED on `laneID` after a structural edit +
    /// re-prime (`refreshStructure`): reload the launched region as a fresh window at
    /// `tick` so its content reflects the EDITED document. Region gone ⇒ fall silently
    /// back to the arrangement (the launch was pruned; this is its defensive twin).
    private func reapplyLaunched(laneID: UUID, atTick tick: Int) {
        let isRoll = (laneID == rollLane)
        guard let launched = launch.soundingRegion(laneID: laneID),
              let region = doc.regions.first(where: { $0.id == launched.regionID }) else {
            if isRoll {
                loadedRegionID = nil
                loadRollRegion(at: tick)
            } else if let slot = secondarySlot(forLane: laneID) {
                restoreSecondaryArrangement(laneID: laneID, slot: slot, at: tick)
            }
            return
        }
        if isRoll {
            applyRollLaneVoice()
            loadClip(region, atTick: tick, step: 0)
        } else if let slot = secondarySlot(forLane: laneID) {
            loadSecondaryWindow(region, laneID: laneID, slot: slot,
                                startBar: launchedStartBar(laneID: laneID, atTick: tick))
        }
    }

    // MARK: Clip-Launch secondary-lane load helpers (shared arrangement/launch path)

    /// The physical rack slot (priority rank) a SECONDARY MIDI lane owns, or nil when
    /// the lane isn't a rack secondary or the rack has no room for it (`multiRollCapacity`).
    /// The roll lane has no slot (it plays the rich PianoRollModel), so it never resolves.
    private func secondarySlot(forLane laneID: UUID) -> Int? {
        guard multiRollCapacity > 0 else { return nil }
        let secondaries = MultiRollFanout.secondaryLaneIDs(in: doc, rollLane: rollLane)
        guard let rank = secondaries.firstIndex(of: laneID), rank < multiRollCapacity else { return nil }
        return rank
    }

    /// The whole-bar loop phase a launched lane resumes at: bars elapsed since the
    /// launch boundary (`LaunchedRegion.startedAtTick`), which the pump folds into the
    /// region length. At the boundary (`.started`) this is 0 → the clip plays from its
    /// top; on a re-window after edits it resumes at the right whole bar. Sub-bar phase
    /// is the documented follow-up.
    private func launchedStartBar(laneID: UUID, atTick tick: Int) -> Int {
        guard let launched = launch.soundingRegion(laneID: laneID) else { return 0 }
        let elapsed = max(0, tick - launched.startedAtTick)
        return elapsed / TimelineTime.ticksPerBar
    }

    /// Window a region onto a SECONDARY lane's rack slot via the SAME sink+pump
    /// sequence as the arrangement fan-out's `.load` case (H5b order law: release the
    /// old take through the old binding, THEN rebind lane → kind → sample → patch →
    /// pitch → mix, then load the windowed bars). `startBar` is the loop entry bar —
    /// the launch timebase for a launched clip, the arrangement phase for a restore.
    private func loadSecondaryWindow(_ region: TimelineRegion, laneID: UUID,
                                     slot: Int, startBar: Int) {
        guard let sink = slotNoteSink else { return }
        var pump = pumps[slot] ?? LaneNotePump()
        if !pump.isEmpty { sink(slot, pump.reset()) }
        slotLaneSink?(slot, laneID)
        slotKindSink?(slot, MultiRollFanout.voiceKind(forSlot: slot, in: doc, rollLane: rollLane))
        slotSampleSink?(slot, MultiRollFanout.samplePath(forSlot: slot, in: doc, rollLane: rollLane))
        slotPatchSink?(slot, MultiRollFanout.patch(forSlot: slot, in: doc, rollLane: rollLane))
        slotTransposeSink?(slot, MultiRollFanout.transpose(forSlot: slot, in: doc, rollLane: rollLane))
        slotDetuneSink?(slot, MultiRollFanout.detune(forSlot: slot, in: doc, rollLane: rollLane))
        slotOctaveSink?(slot, MultiRollFanout.octave(forSlot: slot, in: doc, rollLane: rollLane))
        slotPanSink?(slot, MultiRollFanout.pan(forSlot: slot, in: doc, rollLane: rollLane))
        slotGainSink?(slot, MultiRollFanout.gain(forSlot: slot, in: doc, rollLane: rollLane))
        pump.load(bars: windowedBars(for: region), startBar: startBar)
        pumps[slot] = pump
    }

    /// Hand a secondary lane's slot BACK to its arrangement at `tick` (a launch
    /// `.stopped` or a pruned launch): window the arrangement region active at `tick`,
    /// or release the slot when the lane sits in a gap. Needed because the per-step
    /// fan-out reads `.unchanged` for a region that started earlier and would otherwise
    /// leave the launched clip in the pump.
    private func restoreSecondaryArrangement(laneID: UUID, slot: Int, at tick: Int) {
        if let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick) {
            loadSecondaryWindow(region, laneID: laneID, slot: slot,
                                startBar: max(0, tick - region.startTick) / TimelineTime.ticksPerBar)
        } else if let sink = slotNoteSink {
            if var pump = pumps[slot] {
                sink(slot, pump.reset())
                pumps[slot] = nil
            }
            slotLaneSink?(slot, nil)
            slotKindSink?(slot, .poly)
            slotSampleSink?(slot, nil)
        }
    }
}
