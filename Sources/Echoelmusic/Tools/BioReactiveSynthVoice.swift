//
//  BioReactiveSynthVoice.swift
//  Echoelmusic
//
//  First EngineBus subscriber AND first bio-driven audio voice in the
//  master audio graph. Hosts one EchoelDDSP, polls bus.latestBio at
//  10 Hz on MainActor and forwards each fresh frame into the synth's
//  applyBioReactive(...) surface. The same EchoelDDSP also feeds an
//  AVAudioSourceNode that mixes into AudioEngine.masterMixer, so
//  every bio change is now audible: heart rate drives vibrato, HRV
//  drives brightness, coherence drives harmonicity, etc.
//
//  Default state is SILENT and DISARMED. Nothing sounds on launch — not
//  even when a bio source (incl. the auto-demo) is streaming. The user
//  must arm the voice (UI: play toggle on BioStripView) before the breath
//  drives the envelope. An external MIDI/MPE note always plays (explicit
//  performer action) regardless of arm state. releaseNote() closes the
//  envelope; ambient release tail fades over ~2s.
//
//  Threading: the 10 Hz MainActor poll no longer mutates the synth directly.
//  It enqueues bio parameters onto a lock-free SPSC queue; the audio-thread
//  render block drains the queue and calls synth.applyBioReactive(...) itself.
//  This keeps ALL synth state mutation (including the spectral-envelope array
//  rewrite inside applyBioReactive) on the one audio thread, so it never races
//  the render's read of those arrays — the same SPSC discipline PolySynthVoice
//  uses for notes/patches. Scalar note/frequency control (playNote/releaseNote/
//  pitch bend) remains Float-width-atomic and is tolerated as before.
//

#if canImport(Observation)
import Observation
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

@MainActor
@Observable
public final class BioReactiveSynthVoice {

    // MARK: - Synth + audio output

    /// Underlying synthesizer.
    @ObservationIgnored
    nonisolated public let synth: EchoelDDSP

    /// Insert FX chain (delay / modulation / dynamics) applied to this voice's
    /// output on the audio thread. Inert until `setFXEnabled(true)`.
    @ObservationIgnored
    nonisolated public let fxChain: EchoelFXChain

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    /// Whether the note envelope is currently open (audible) or
    /// released (silent / fading).
    public private(set) var isPlayingNote = false

    /// Master arm switch for bio-driven sound. DEFAULT FALSE: until the
    /// user arms the voice (play toggle), bio/breath events never open the
    /// envelope, so the instrument is silent on launch even while the demo
    /// bio source streams. An external MIDI/MPE note bypasses this (explicit
    /// performer action always sounds).
    public private(set) var isArmed = false

    /// When true, breath inhale/exhale onsets from the bus drive the
    /// envelope (the synth breathes with you) whenever the voice is armed
    /// and no external controller note is held.
    ///
    /// ⛔ THIS LINE SAID "Toggle off for pure manual play" AND THERE IS NOTHING TO TOGGLE
    /// IT WITH (#724). Measured across all 369 files under `Sources/`: exactly ONE assignment,
    /// the declaration below, and no read of any other write shape. It is therefore permanently
    /// `true`, and the THREE-condition gate in `consumeBioEventsIfFresh` —
    /// `guard isArmed, breathPlayEnabled, !heldByController` — is effectively two conditions.
    /// (⛔ The first version of this note said "two-condition … effectively one" and quoted the
    /// three-condition guard one clause later, #725.)
    ///
    /// ⭐ THE ENGINE HALF IS REAL AND THAT IS WHY THIS STAYS. The consumer reads it on every
    /// bio event, so wiring a door is one line plus a control; the flag is a knob waiting
    /// for a surface, not dead code. What was wrong is a doc comment describing a capability
    /// ("toggle off") in the present tense when no producer exists — the shape CLAUDE.md
    /// records for the tempo modulation route (engine running, destination registered, no
    /// route ever constructed).
    ///
    /// ⚠️ AND THE SIGN IS THE OPPOSITE OF THE OTHER TWO CASES THAT REGISTER NAMES, which is
    /// why they are not cited here (#725): where a source has no producer, the capability
    /// does not HAPPEN. Here the missing writer means it always happens — breath-play is fully
    /// functional and only the ability to switch it OFF is absent. Read as "same shape", a
    /// later session would treat breath-play as a dormant feature to wire up. It is not.
    ///
    /// ⚠️ NOT a decision that it SHOULD have a door. "Breathe with me / manual only" is a
    /// product question for the founder, next to the Body-voice arm switch (#277) in the
    /// bio panel. This note records the state so that question is asked from facts.
    public var breathPlayEnabled = true

    // MARK: - Bus subscription state

    public private(set) var isSubscribed = false

    /// The MIDI notes physically under a finger, oldest first — the LAST one is what sounds.
    ///
    /// ⭐ #943 — THIS REPLACED A SINGLE `Bool`, AND THE BOOL HAD A BUG ANY KEYBOARD HITS.
    /// `.noteOff` cleared it without asking WHICH key was lifted, so holding C and E and then
    /// lifting C went silent while a finger was still on E. Worse than the silence: this same
    /// flag is the gate that hands the voice back to the BREATH envelope
    /// (`guard isArmed, breathPlayEnabled, !heldByController`), so a mis-cleared latch let the
    /// body start playing the voice UNDERNEATH a key that is physically down.
    ///
    /// ⚠️ ONE ENTRY PER NOTE NUMBER, deliberately. This voice never reads `event.channel`
    /// (`TheMPEInputHasNoZonesTests` claim 2 pins that), so two MPE fingers on the same pitch
    /// arrive indistinguishable; a second entry would become a ghost that no single note-off
    /// can clear, and the voice would sound with nothing under a finger.
    ///
    /// ⚠️ BOUNDED, and the bound is the point rather than tidiness: a note-off that never
    /// arrives (cable pulled mid-note, event dropped under SPSC flood) leaves an entry behind.
    /// Unbounded, those accumulate into a voice that can never be released — a WORSE failure
    /// than the one this fixes. The OLDEST is dropped, because it is the one least likely to
    /// still be under a finger, and `panic()` throws the whole stack away.
    @ObservationIgnored
    private var heldNotes: [UInt8] = []

    /// Capacity of `heldNotes`. Ten fingers plus headroom for a sustained roll; the exact
    /// number is not musical, only the existence of a ceiling is.
    private static let maxHeldNotes = 16

    /// Unchanged in meaning: is a controller key down? It is now DERIVED rather than latched,
    /// which is the whole repair — a derived flag cannot disagree with the keys.
    private var heldByController: Bool { !heldNotes.isEmpty }

    @ObservationIgnored
    private var lastBioEventTimestamp: TimeInterval = -1

    public private(set) var lastApplied: BioSampleFrame?

    /// Diagnostic counter, bumped once per NEW bio frame (~1 Hz today — the poll is 10 Hz
    /// but the apply at `:415` dedupes on `frame.timestamp`, and every wired publisher emits
    /// at ~1 Hz). The twin of `PolySynthVoice.framesApplied`, and it said "~10 Hz" for a
    /// month AFTER that one was corrected, because #341 edited this file 400 lines below and
    /// did not look up — the reviewer caught it. MUST stay `@ObservationIgnored` regardless
    /// of the rate: as a tracked `@Observable` it would invalidate any view reading it on
    /// every frame (the "menus freeze while playing" class), and the 10 Hz poll is a CEILING
    /// a faster publisher would reach without this line changing.
    @ObservationIgnored public private(set) var framesApplied: UInt64 = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private let loop = PollingLoop()

    /// BodyVibe B1: invoked once per 10 Hz poll tick, AFTER this voice's own
    /// bio/controller work. Lets the app fan the SAME tick into the rack's lane
    /// bio units (LaneVoiceRack.feedBio) without a second timer — the "no new
    /// timer, no per-frame MainActor hop" law. nil (default) ⇒ zero cost.
    @ObservationIgnored
    public var onPollTick: (@MainActor () -> Void)?

    /// Lock-free bio-modulation queue: produced on the MainActor 10 Hz poll,
    /// consumed (applied to `synth`) on the audio thread in the render block.
    /// Bio modulation rewrites the synth's spectral-envelope arrays; doing that
    /// on the audio thread (not the MainActor poll) keeps it from racing the
    /// render's read of those same arrays. Same discipline PolySynthVoice uses
    /// for notes/patches. SPSC: one producer (main), one consumer (audio).
    @ObservationIgnored
    nonisolated(unsafe) private let bioCommands = SPSCQueue<BioParams>(capacity: 8)

    @ObservationIgnored
    private var lastTimestamp: TimeInterval = -1

    // MARK: - Audio render scratch (audio-thread only after attach)

    @ObservationIgnored
    nonisolated private static let maxBlockFrames = 4096

    @ObservationIgnored
    private static let sampleRate: Double = 48_000

    /// Pre-allocated mono buffer, sized to the max plausible block.
    /// Audio thread writes into this via `synth.render(...)` and then
    /// memcpys into the AudioBufferList. Never re-allocated after init.
    @ObservationIgnored
    nonisolated(unsafe) private var scratchBuffer: [Float]

    /// Hard launch-silence guarantee: the render block emits PURE ZERO until the
    /// user triggers the voice for the first time (arm / MIDI note). This makes
    /// "nothing sounds on app open" true at the audio-thread level, independent
    /// of envelope state — set once on the first `playNote`, never reset, so it
    /// never cuts a release tail. Bool is atomic-width; written on the main
    /// thread, read on the audio thread.
    @ObservationIgnored
    nonisolated(unsafe) private var hasEverSounded = false

    /// Master FX gate. DEFAULT FALSE → the FX chain is fully inert (true bypass,
    /// zero cost in the render block) until the user enables it, so existing
    /// builds sound bit-identical. Atomic-width Bool: written on the main thread,
    /// read on the audio thread (same contract as `hasEverSounded`).
    @ObservationIgnored
    nonisolated(unsafe) private var fxEnabled = false

    /// Observable mirror of `fxEnabled` for SwiftUI binding.
    public private(set) var isFXEnabled = false

    public init() {
        self.synth = EchoelDDSP(sampleRate: Float(Self.sampleRate))
        self.fxChain = EchoelFXChain(sampleRate: Float(Self.sampleRate))
        self.scratchBuffer = Array(repeating: 0, count: Self.maxBlockFrames)
    }

    /// Enable or bypass the insert FX chain. Updates both the audio-thread gate
    /// and the observable mirror. Individual stages are toggled directly on
    /// `fxChain` (e.g. `fxChain.delayEnabled = true`).
    /// The stale-glide problem this gate creates is handled on the RENDER side — see
    /// `fxChain.noteRenderSkipped()` in `renderOnAudioThread`. (Today that is defensive
    /// rather than live: nothing in `Sources/` calls this method, so this voice's chain
    /// never runs, and `FXBioModulator` is attached to `PolySynthVoice.fxChain` only.
    /// Stated plainly because the first draft of this comment claimed the opposite —
    /// "this is the body-driven voice, so the drift is largest here" — which was false in
    /// both halves and is exactly the kind of line a later session cites as evidence.)
    /// The #397 drain below is defensive here for the SAME reason and by the same evidence:
    /// with no caller this chain never processes a sample, so it can hold nothing to burst.
    /// It is written anyway so the two voices' gates cannot drift — the day someone wires
    /// this method, the hole would reappear silently, and a reader comparing the two files
    /// would have to work out from scratch which asymmetry was deliberate.
    public func setFXEnabled(_ on: Bool) {
        if on && !fxEnabled { fxChain.noteRenderSleeping() }
        fxEnabled = on
        isFXEnabled = on
    }

    // MARK: - Audio engine attachment

    /// Attach the voice's source node to the master audio graph.
    /// MUST be called BEFORE `audioEngine.start()` to avoid the
    /// build-1363 hot-attach launch crash documented in CLAUDE.md.
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachSourceNode(sourceNode)
    }

    // MARK: - Note gating (UI control plane)

    /// Open the envelope at the synth's current frequency (or, if
    /// supplied, retune to `frequency` first). Re-entrant: a second
    /// `playNote` while already playing retriggers — monophonic,
    /// last-note-wins.
    public func playNote(frequency: Float? = nil) {
        hasEverSounded = true
        synth.noteOn(frequency: frequency)
        isPlayingNote = true
    }

    public func releaseNote() {
        guard isPlayingNote else { return }
        synth.noteOff()
        isPlayingNote = false
    }

    /// PERFORMANCE PANIC — release the note AND clear the controller-held latch.
    ///
    /// `releaseNote()` alone is not enough for a panic. `heldByController` is set on an
    /// external `.noteOn` and cleared by any later `.noteOff` (unmatched — the first key
    /// release of a chord already clears it). But if that note-off never arrives at all —
    /// controller unplugged mid-note, or an event dropped because `bus.controllerEvents` is a
    /// bounded SPSC queue under flood — the latch stays true and `consumeBioEventsIfFresh`
    /// refuses every breath onset. Breath play is then dead for the rest of the session and
    /// no UI control can clear it (`disarm()` does not touch it); only a later controller
    /// `.noteOff`, which by construction is exactly what is missing. Panic is the natural
    /// place to break the latch, so this exists and is what the panic button calls.
    ///
    /// `isArmed` is deliberately NOT cleared: this is a RELEASE, not a mute. The bio arm
    /// re-opens on the next inhale — just as every sequenced voice re-attacks on its next
    /// step, since the panic does not stop the transport either. Clearing `isArmed` would
    /// make this one voice behave unlike the other seven and would silently switch the
    /// instrument's bio arm off from a button reached for a stuck note. `disarm()` ends bio
    /// sound by mechanism; Stop ends it in effect, by starving the source.
    ///
    /// One accepted delta: a performer physically holding a MIDI key across a Stop loses
    /// performer priority, so breath can open the voice while the key is down and the
    /// eventual real `.noteOff` then cuts that breath note mid-phrase. Narrow enough to live
    /// with — recorded here so it is not rediscovered as a bug.
    public func panic() {
        // #943 — the whole stack, not one entry. Panic means "forget every key"; a straggling
        // note-off afterwards then finds nothing to release rather than re-opening the voice.
        heldNotes.removeAll(keepingCapacity: true)
        // #939 — the press latch is exactly as sticky as the note latch above, and for the same
        // two reasons this doc block already names (controller unplugged mid-note, event dropped
        // under queue flood). Without this line a stuck press survives every Stop.
        synth.expressionGain = 1
        synth.renderCutoffScale = 1   // #942 — the slide latch is as sticky as the press latch
        releaseNote()
    }

    /// Arm the bio-reactive voice and give immediate audible feedback. Once
    /// armed, breath onsets (if `breathPlayEnabled`) drive the envelope.
    public func arm() {
        isArmed = true
        playNote()
    }

    /// Disarm and silence the voice (closes the envelope; bio events ignored).
    public func disarm() {
        isArmed = false
        releaseNote()
    }

    /// Concert pitch (Kammerton), A4 in Hz. The mono `EchoelDDSP` this voice drives has
    /// no tuning field (only `EchoelPolyDDSP` does), and `playNote(frequency:)` sets the
    /// oscillator to an explicit Hz, so the voice resolves the note→Hz itself from this
    /// value. Control-path only (written in `setTuning`, read in `soundingFrequency`, both
    /// on the MainActor) — never touched by the render block, so no atomic needed.
    @ObservationIgnored private var tuningA4Hz: Float = 440

    /// Per-pitch-class (0=C…11=B) cent deviation from 12-TET — the SELECTED TONE SYSTEM's
    /// intonation, the same table `EchoelPolyDDSP`/`SubBassVoice` get.
    ///
    /// ⭐ WHY THIS VOICE NEEDS IT (#338, the #312 gap one level down). Two reachable paths
    /// already play this type's notes today, and both went through `soundingFrequency`,
    /// which knew only the Kammerton: external MIDI note-on on the GLOBAL instance
    /// (`apply(controller:)` — NOT gated by `isArmed`, the performer always leads), and the
    /// sequencer gate on every RACK bio unit (`LaneVoiceRack.noteOn`). So with a non-12-TET
    /// system selected, every
    /// other pitched voice moved and these played plain 12-TET against them — the founder's
    /// "Bass teilweise nicht in tune" (#312), same shape, different voice.
    ///
    /// ⚠️ THE TWO PATHS ARE NOT EQUALLY UNCONDITIONAL, and the first draft of this block said
    /// they were ("live because `feature.multiRoll` is registered ON"). The GLOBAL instance
    /// needs nothing but a plugged-in keyboard. A RACK bio unit needs `multiRoll` AND
    /// `voiceKindRouting` (both registered ON, but it is two flags, `LaneVoiceRack.attachAll`)
    /// AND a track whose instrument the user set to `TrackInstrument.bioVoice` — `EchoelDDSP`
    /// states that user-assignment condition and this block had dropped it. The poly/sub half
    /// of the rack fan is the genuinely default-install one.
    ///
    /// ⛔ AND THE COMMENT IN `applyTuning()` CALLED THAT ABSENCE CORRECT, on the ground that
    /// "THIS VIEW's `bioVoice` instance never sounds — nothing calls `arm()` on it (#277)".
    /// The `arm()` half is true and the CONCLUSION does not follow: `arm()` gates only the
    /// BREATH trigger (`consumeBioEventsIfFresh`), never the MIDI path.
    ///
    /// ⛔ AND THE FIRST DRAFT OF THIS SENTENCE MISCOUNTED, in three files at once: it said
    /// "the THIRD time in this one fan that a fact stood in for a reason — API surface for the
    /// LEAD, API surface for the sub, and a latch for this voice." The lead half is FALSE and
    /// the excuse it cites says so: "exists on exactly three reachable objects (all
    /// `PolySynthVoice`)" — `leadSynth` IS a `PolySynthVoice?`, so it was INSIDE that set, not
    /// excluded by it, and `PolySynthVoice.setTuningCents` has always existed. The lead was an
    /// omission with NO stated reason at all. Honest count: TWO — API surface (which covered
    /// sub, this voice and the rack together), and this latch. Written down because a session
    /// that greps for the lead's supposed excuse finds nothing and then discounts the whole
    /// block, including the half that is true.
    ///
    /// CONTROL-PATH ONLY, exactly like `tuningA4Hz` above: written in `setTuningCents`, read
    /// in `soundingFrequency`, both on the MainActor. The render block never sees it (the
    /// mono `EchoelDDSP` is handed a finished Hz), so unlike `SubBassVoice.tuningCents` this
    /// needs no `nonisolated(unsafe)` and no in-place-mutation discipline.
    @ObservationIgnored private var tuningCents: [Float] = Array(repeating: 0, count: 12)

    /// This voice's SOUNDING frequency for a MIDI note, honoring the concert pitch
    /// (Kammerton) set via `setTuning`, so external-MIDI and lane-gate notes stay in tune
    /// with the rest of the instrument instead of pinning to 440. (Was a hardcoded-440
    /// static that made the bio voices ignore the user's Kammerton.)
    ///
    /// Since #338 it also honors the tone system's per-pitch-class retune. 12-TET is an
    /// all-zero table, so the default is bit-identical — which is what makes the fan in
    /// `applyTuning()` safe to apply unconditionally.
    public func soundingFrequency(forMIDINote note: UInt8) -> Float {
        // Defensive on SIZE as well as on the setter. ⛔ The reason first written here was
        // "this is the branch a future caller could reach without going through
        // `setTuningCents` at all (the lesson `SubBassFollowsTheToneSystemTests` pins for the
        // sub)" — and that parallel does NOT hold, which matters because in this repo the
        // stated reason is what a later session cites. `SubBassVoice.feltFrequency` is a
        // STATIC taking `cents` as a parameter, so an arbitrary caller really can hand it a
        // 3-entry array, and its test drives exactly that. Here `tuningCents` is `private`
        // with one writer, itself size-guarded, so the false arm is dead by construction.
        // The ternary stays because it is free and a `private` field can gain a second writer
        // in one edit; the honest scope is "cheap belt on a MainActor read", not "a caller
        // can reach this today" — and a trap here would be a main-thread trap, not the
        // render-thread crash the sub's version guards.
        let deviation = tuningCents.count == 12 ? tuningCents[Int(note) % 12] : 0
        return tuningA4Hz * powf(2, (Float(note) - 69) / 12) * exp2f(deviation / 1200)
    }

    /// Set the concert pitch (Kammerton) this voice tunes to — A4 in Hz, clamped to a
    /// musical range so a stray value can't detune into inaudibility. Read at the next
    /// note (same discipline as `PolySynthVoice.setTuning`); safe while a loop plays.
    public func setTuning(a4Hz: Double) {
        // Sanitize the tuning boundary: a NaN slips through min/max (NaN comparisons are
        // false) and would poison the frequency → a stuck, silent oscillator (same
        // failure class as the pitch-bend isFinite guard).
        guard a4Hz.isFinite else { return }
        tuningA4Hz = Float(Swift.min(Swift.max(a4Hz, 380), 500))
    }

    /// Install the tone system's 12-entry pitch-class retune table (#338). All zeros
    /// (12-TET, the default) leaves playback bit-identical. Concert pitch and tone system
    /// are INDEPENDENT axes and compose — this never touches `tuningA4Hz`.
    ///
    /// No-op if the table is not exactly 12 entries, and no-op on a non-finite entry: a
    /// partial apply would retune the wrong pitch classes, and a NaN cent value would make
    /// `soundingFrequency` return NaN → the stuck-silent-oscillator failure class the
    /// `setTuning` guard above exists for. Staying on the last good tuning beats both.
    ///
    /// ⚠️ COPIED IN PLACE, not reseated — the same discipline as `SubBassVoice` and
    /// `EchoelPolyDDSP`, and deliberately so even though nothing needs it TODAY. Reseating an
    /// array is an ARC retain/release on the storage; that is harmless while every reader is
    /// on the MainActor (it is — see the field doc), and it becomes an audio-thread race the
    /// moment someone marks `soundingFrequency` `nonisolated`, which is exactly what
    /// `SubBassVoice.frequency(forMIDINote:)` is. Three identical shapes cost nothing; one
    /// that is "fine for now" is an invitation with a doc comment next to it.
    public func setTuningCents(_ cents: [Float]) {
        guard cents.count == 12, cents.allSatisfy({ $0.isFinite }) else { return }
        for i in 0..<12 { tuningCents[i] = cents[i] }
    }

    // MARK: - Lane mixer stage (BodyVibe B1 — rack-unit use)

    /// Lane gain: this voice's whole-output level at the mixer, 0…2 (1 = unity —
    /// the default, so the global voice is bit-identical). Control-plane only,
    /// exactly the PolySynthVoice pattern: `sourceNode` conforms to
    /// `AVAudioMixing`, the ENGINE scales downstream of the render block.
    /// Non-finite fails SILENT (0) per app convention.
    public func setGain(_ gain: Float) {
        sourceNode.volume = Swift.max(0, Swift.min(2, gain.isFinite ? gain : 0))
    }

    /// Lane pan, −1…1 (0 = center — the default). Same AVAudioMixing engine
    /// path as `setGain`; non-finite is ignored as center.
    public func setPan(_ pan: Float) {
        sourceNode.pan = Swift.max(-1, Swift.min(1, pan.isFinite ? pan : 0))
    }

    // MARK: - Bus subscription

    /// Begin polling bus.latestBio at 10 Hz and forwarding fresh
    /// frames into synth.applyBioReactive(...). Idempotent.
    ///
    /// ⭐ MIDI DOES NOT WAIT FOR THIS LOOP ANY MORE (#317). Bio is a 10 Hz signal and a
    /// 100 ms tick is right for it; a NOTE is an event and 100 ms is not a rate, it is a
    /// delay — plus 100 ms of jitter, because where in the tick a note landed decided how
    /// late it sounded. `bus.onControllerEventEnqueued` now drains as soon as an event is
    /// published, and the tick's drain below STAYS as the backstop for anything enqueued
    /// while nothing was subscribed. Two call sites, still ONE consumer (this object), both
    /// on the main actor — the SPSC single-consumer contract is untouched.
    public func start(subscribing bus: EngineBus) {
        guard !isSubscribed else { return }
        self.bus = bus
        isSubscribed = true
        // `[weak self, weak bus]`: the bus stores this closure, so a strong capture of
        // either end would keep both alive forever. The voice is the consumer, not the owner.
        bus.onControllerEventEnqueued = { [weak self, weak bus] in
            guard let self, let bus else { return }
            self.drainControllerEvents(from: bus)
        }
        loop.start(interval: .milliseconds(100)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            self.applyLatestIfFresh(from: bus)
            self.drainControllerEvents(from: bus)
            self.consumeBioEventsIfFresh(from: bus)
            self.onPollTick?()
        }
    }

    /// BodyVibe B1 — the LANE-UNIT bio feed: forward the bus's latest bio
    /// snapshot into this voice's timbre WITHOUT subscribing. A rack bio unit
    /// must never call `start(subscribing:)`: that would (a) spin a second
    /// PollingLoop and (b) drain the SHARED `bus.controllerEvents` SPSC queue —
    /// single-consumer contract; a second consumer steals MIDI events from the
    /// global armed voice — and (c) let breath onsets open the envelope outside
    /// the sequencer gate. This method is timbre-only: the envelope stays owned
    /// by the caller (playNote/releaseNote from the sequencer note gate).
    /// Called from the global voice's existing 10 Hz tick via `onPollTick`.
    public func applyBioFrame(from bus: EngineBus) {
        applyLatestIfFresh(from: bus)
    }

    /// Pulls every queued ControllerEvent since the last tick and
    /// applies the music-meaningful ones to the synth envelope:
    ///   .noteOn      → playNote(frequency: midiNote→Hz)
    ///   .noteOff     → releaseNote()
    ///   .pitchBend   → instantaneous frequency offset (±2 semitones)
    ///   .channelPressure → `synth.expressionGain` (MPE PRESS, #939) — additive from
    ///                       nominal, so a controller at rest changes nothing
    ///   .slide           → `synth.renderCutoffScale` (MPE SLIDE / CC 74, #942) — same shape,
    ///                       a per-sample multiplier on the filter cutoff
    /// .airCC is still reserved; nothing consumes it. It is NOT an MPE dimension (CC 21–31),
    /// so its absence says nothing about MPE either way.
    private func drainControllerEvents(from bus: EngineBus) {
        while let event = bus.controllerEvents.dequeue() {
            apply(controller: event)
        }
    }

    #if DEBUG
    /// TEST SEAM (Debug-only): apply ONE controller event and read the held latch, so the
    /// panic's latch-clearing can be pinned without an `EngineBus` poll task or an engine.
    /// The production path is `drainControllerEvents(from:)` above; this is the same call.
    internal func applyControllerForTests(_ event: ControllerEvent) { apply(controller: event) }
    internal var heldByControllerForTests: Bool { heldByController }
    /// #943 — the stack's SIZE, so the bound can be asserted without exposing the keys.
    internal var heldNoteCountForTests: Int { heldNotes.count }
    #endif

    /// How much louder full press is than no press (#939). +50 % ≈ +3.5 dB — a swell a player
    /// can lean into, well short of slamming the master limiter. Named rather than inlined so
    /// the founder's ear can move ONE number.
    /// NEEDS-FOUNDER-VERIFY: MPE-Controller anschließen, eine Note halten und in die Taste
    /// LEHNEN — schwillt sie musikalisch an, oder zu wenig / zu viel? Eine Zahl, `pressDepth`.
    private static let pressDepth: Float = 0.5

    /// How far full slide opens the filter (#942). ×4 is two octaves of cutoff — the sweep an
    /// MPE player expects from the Y axis, and small enough that the existing 2 ms glide keeps
    /// it smooth. Named rather than inlined so the founder's ear can move ONE number.
    /// NEEDS-FOUNDER-VERIFY: MPE-Controller anschließen, eine Note halten und den Finger
    /// SENKRECHT bewegen — ist der Klangfarben-Sweep musikalisch, oder zu weit / zu eng?
    /// Eine Zahl, `slideDepth`.
    private static let slideDepth: Float = 3.0

    private func apply(controller event: ControllerEvent) {
        switch event.kind {
        case .noteOn:
            // Re-pressing a pitch that is already down moves it to the top rather than adding
            // a second entry — see the dedupe note on `heldNotes`.
            heldNotes.removeAll { $0 == event.note }
            heldNotes.append(event.note)
            if heldNotes.count > Self.maxHeldNotes { heldNotes.removeFirst() }
            // Note-ON priority is UNCHANGED by #943: a new key re-attacks, which is what
            // shipped and what a player expects from pressing a key.
            playNote(frequency: soundingFrequency(forMIDINote: event.note))
        case .noteOff:
            let wasTop = heldNotes.last == event.note
            heldNotes.removeAll { $0 == event.note }
            if let top = heldNotes.last {
                // A key is still down. If the one lifted was not the sounding one, nothing
                // audible changes at all; if it was, fall back LEGATO — write the frequency
                // directly instead of `playNote`, because `playNote` runs `synth.noteOn`, which
                // re-arms the attack, the filter envelope, the onset chiff and the drift
                // counters. Hearing a fresh transient because you LIFTED a finger is its own
                // wrong answer; the render's `smoothedFreq` one-pole (~2 ms) glides the pitch.
                if wasTop { synth.frequency = soundingFrequency(forMIDINote: top) }
            } else {
                releaseNote()
            }
        case .pitchBend:
            let semis = event.value * 2.0
            // ⚠️ PRE-EXISTING SHAPE, newly consequential since #338: note 0 falls back to 69,
            // so a bend that arrives without a note now picks up pitch class A's deviation
            // rather than none. Left alone deliberately — choosing the right fallback (last
            // sounding note? no deviation?) is a decision, not a tidy-up, and this slice is
            // about fanning the table, not about redefining the bend base.
            let base = soundingFrequency(forMIDINote: event.note > 0 ? event.note : 69)
            let bent = base * powf(2, semis / 12)
            // A NaN/inf controller value would set synth.frequency to NaN, which the
            // audio thread reads in render() → a permanently stuck/silent oscillator
            // (same failure class the bio-param accessors on `BioSampleFrame` guard —
            // `heartRateForSound` / `breathPhaseForSound`). Ignore a bend that isn't a
            // finite pitch rather than poison the voice.
            if bent.isFinite { synth.frequency = bent }
        case .channelPressure:
            // ⭐ #939 — MPE's PRESS dimension reaches a voice for the first time. It ADDS to
            // the nominal level rather than replacing it: a controller at rest sends 0, so a
            // replacing map would mute the instrument the moment a keyboard is plugged in,
            // and every existing recording/test would change. At 0 this is exactly 1.0 —
            // bit-identical to every build before it — and full press lifts the note by
            // `pressDepth`.
            //
            // ⚠️ NaN/inf is ignored rather than clamped, the shape one case above: a poisoned
            // gain would leave the master-gain smoother stuck at 0, i.e. silent while every
            // control reads healthy. `expressionGain`'s own `didSet` is a second net, not the
            // first one — a door at each end, because this value comes off the wire.
            // `clamped(to:)` is the house NaN-safe form (`min(max(v, 0), 1)` passes NaN
            // through — CLAUDE.md's shipped-silence rule). NaN maps to the lower bound, i.e.
            // "not pressing", which is also the right musical answer to a garbage byte.
            let press = event.value.clamped(to: 0...1)
            synth.expressionGain = 1 + press * Self.pressDepth
        case .slide:
            // ⭐ #942 — MPE's SLIDE (Y / timbre) dimension, the LAST of the three continuous
            // ones to reach the sound (bend has always played, press arrived at #939).
            // It multiplies the filter cutoff rather than writing `brightness`: the bio
            // path owns `brightness` and rewrites it every frame (~1 Hz), and writing it also
            // triggers a full harmonic recompute through its `didSet` — a CC 74 stream would
            // run that hundreds of times a second. `renderCutoffScale` is read per SAMPLE and
            // already sits inside the cutoff's one-pole, so this glides in ~2 ms.
            //
            // Neutral at 0 for the same reason as press: a controller at rest sends 0, so a
            // replacing map would clamp the filter shut the moment a keyboard is plugged in.
            // At 0 this is exactly 1.0 — bit-identical to every build before it.
            //
            // Sanitised AT THE WRITER, through the one clamp `EchoelPolyDDSP` has always used
            // for this property and which #942 moved onto `EchoelDDSP` so both writers can
            // share it (#416). The property itself stays a plain Float: a `didSet` there would
            // turn the poly path's per-voice-per-block store into a read-modify-write on the
            // audio thread, and would contradict the "aligned-word atomic" discipline its own
            // doc states. Belt and braces here — `clamped(to: 0...1)` is already NaN-safe
            // (NaN → 0 → a scale of exactly 1), so the outer clamp is for the NEXT writer.
            synth.renderCutoffScale = EchoelDDSP.clampExpressionScale(
                1 + event.value.clamped(to: 0...1) * Self.slideDepth)
        case .airCC:
            break
        }
    }

    /// When no external controller note is held, the breath drives the
    /// envelope: inhale onset opens it, exhale onset releases it — the
    /// synth breathes with you. A held MIDI/MPE note takes priority and
    /// suppresses breath triggering so the performer always leads.
    private func consumeBioEventsIfFresh(from bus: EngineBus) {
        guard let event = bus.latestBioEvent else { return }
        guard event.timestamp != lastBioEventTimestamp else { return }
        lastBioEventTimestamp = event.timestamp
        // Silent until the user arms the voice — this is what stops a tone
        // from appearing on launch while the demo bio source streams.
        guard isArmed, breathPlayEnabled, !heldByController else { return }

        switch event.kind {
        case .breathInhaleOnset:
            playNote()
        case .breathExhaleOnset:
            releaseNote()
        case .heartbeat, .motionPeak, .coherenceShift, .eegBurst:
            break
        }
    }

    public func stop() {
        loop.stop()
        // Hand the drain hook back (#317). Leaving it installed would keep this voice
        // consuming events after it stopped, and would make the next subscriber's `start`
        // the SECOND setter of a single-consumer hook.
        //
        // ⛔ THE FIRST VERSION PROVED THE WRONG CASE. It argued that no `isSubscribed` guard
        // was needed because `self.bus` is assigned in exactly ONE place
        // (`start(subscribing:)`, still true), so a rack bio unit — which must never
        // subscribe and gets its frames through `applyBioFrame(from:)`, where the bus is a
        // PARAMETER and is not stored — has a nil `bus` and cannot clear the global voice's
        // hook. That much holds. What it did NOT cover is the sequence its own next sentence
        // set up: a voice that HAS subscribed and stopped kept a live `bus`, so a second
        // `stop()` on it would unconditionally nil whatever hook was installed by then —
        // possibly someone else's. Releasing the reference below makes the claim true by
        // construction instead of by argument.
        bus?.onControllerEventEnqueued = nil
        bus = nil
        // ⚠️ AND THE HONEST FRAME: `BioReactiveSynthVoice.stop()` has ZERO production callers
        // (`EchoelmusicApp` starts the one subscriber and never stops it). This is correct
        // hygiene for a path nothing walks today — do not cite it as a live invariant.
        isSubscribed = false
    }

    // MARK: - Bio → Synth mapping


    /// #813 — one per voice, main-actor only. Two independent trackers over the same frame
    /// sequence produce the same output, which is why the trend is NOT a field on
    /// `BioSampleFrame`: keeping it here leaves the six frame construction sites, the OSC
    /// egress and the wire contract untouched.
    private var coherenceTrend = CoherenceTrend()

    private func applyLatestIfFresh(from bus: EngineBus) {
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastTimestamp else { return }
        lastTimestamp = frame.timestamp
        lastApplied = frame
        framesApplied &+= 1

        // Hand the parameters to the AUDIO thread instead of mutating the synth
        // here. Previously this ran `synth.applyBioReactive(...)` on the MainActor
        // poll, which rewrote the synth's spectral-envelope Swift arrays while the
        // audio thread read them in render() — a cross-thread array data race (the
        // same class fixed for notes/patches in PolySynthVoice). The render block
        // drains this queue and applies it on the one audio thread.
        // #813 — the coherence TREND, which had no producer until now. `applyBioReactive`'s
        // rising/falling spectral morph reads it and every construction site passed the literal
        // 0, so the whole else-branch was unreachable (#496). Fed from the RAW `frame.coherence`
        // and the house measured-test, NOT from `coherenceForSound`: substituting a neutral for
        // an unmeasured channel is right for a LEVEL and wrong for a DERIVATIVE, because the
        // substitution itself would read as movement. Computed HERE, on the main actor, for the
        // same reason the rest of this value is — only the drain is on the audio thread.
        let trend = coherenceTrend.update(coherence: frame.coherence,
                                          measured: BioModulationMap.isMeasured(.coherence, in: frame),
                                          source: frame.source,
                                          at: frame.timestamp)

        _ = bioCommands.tryEnqueue(BioParams(
            coherence: frame.coherenceForSound,   // 0 = unmeasured → neutral
            hrv: frame.hrvForSound,               // ditto; both on BioSampleFrame
            // ⛔ These two used to be `clampUnit((frame.heartRateBPM - 40) / 160)` and
            // `clampUnit(frame.breathPhase)` — RAW reads, so an UNMEASURED channel handed
            // the engine an EXTREME instead of the neutral the engine declares (#497).
            // No lock → vibrato 25 % under the patch; no respiration → the whole voice
            // 0.92 dB under it. The neutral now lives on the frame, next to its twins
            // `hrvForSound` / `coherenceForSound`, which is where it always belonged.
            // NaN-safety is unchanged, it just moved: `hasMeasuredHeartRate` is
            // `heartRateBPM > 0` (false for NaN) and `breathPhaseForSound` guards
            // `isFinite`, so a bad frame still fails to a neutral instead of poisoning
            // the render state — the reason `clampUnit` existed at all.
            heartRate: frame.heartRateForSound,
            breathPhase: frame.breathPhaseForSound,
            breathDepth: 0.5,
            lfHf: 0.5,
            coherenceTrend: trend
        ))
    }

    // ⛔ `private func clampUnit(_:)` lived here and is DELETED with #497. It had exactly
    // two callers — the heart-rate and breath-phase arguments above — and both now read
    // `BioSampleFrame.heartRateForSound` / `.breathPhaseForSound`, which carry the same
    // NaN-safety plus the neutral-when-unmeasured rule it never had. Its doc claimed
    // "fail quiet (0)"; for these two channels 0 is not quiet, it is the BOTTOM of the
    // scale — which is precisely the defect #497 removes. Do not reintroduce a local
    // unit clamp for a bio channel: the frame owns that decision (#416).

    // MARK: - Source node (audio thread)

    private func makeSourceNode() -> AVAudioSourceNode {
        // Capture self weakly to keep the render closure from retaining the
        // MainActor-bound voice. nonisolated(unsafe) is acceptable because
        // the render closure runs on the audio thread and only touches
        // the synth (Float-atomic params) and the scratch buffer
        // (audio-thread-only after first render).
        nonisolated(unsafe) let weakSelf = WeakBox(self)
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            guard let voice = weakSelf.value else {
                BioReactiveSynthVoice.silence(audioBufferList: audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            voice.renderOnAudioThread(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        // A constant sample rate always yields a valid format; if the OS ever
        // returns nil, use the format-inferring initializer rather than the no-arg
        // AVAudioFormat() (an invalid 0 Hz/0 ch format that crashes the node init).
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }

    /// Audio thread. Reads (potentially racy) synth params and writes
    /// `frameCount` mono samples into the first channel of `abl`.
    /// nonisolated(unsafe) — see threading note in the file header.
    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        // Apply any pending bio modulation HERE (audio thread) so the synth's
        // spectral-envelope array rewrite happens on this one thread and never
        // races the render's read below. Drain to the latest queued frame; the
        // queue is empty in most blocks (params update ~1 Hz — the poll is 10 Hz but
        // dedupes on `frame.timestamp`, and every wired publisher emits at ~1 Hz), so this
        // is a cheap check. Runs even while silent so the timbre is current when armed.
        var latestBio: BioParams?
        while let p = bioCommands.dequeue() { latestBio = p }
        if let p = latestBio {
            synth.applyBioReactive(
                coherence: p.coherence,
                hrvVariability: p.hrv,
                heartRate: p.heartRate,
                breathPhase: p.breathPhase,
                breathDepth: p.breathDepth,
                lfHfRatio: p.lfHf,
                coherenceTrend: p.coherenceTrend
            )
        }
        // Launch-silence guarantee: never emit anything until the first
        // user-initiated trigger. Pure zero out of this node on app open.
        guard hasEverSounded else {
            // #138 Slice 2: the chain is skipped here, so its tone-filter glide must LAND
            // on resume instead of sweeping out of a pre-session value.
            fxChain.noteRenderSkipped()
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }
        let count = min(frameCount, Self.maxBlockFrames)
        synth.render(buffer: &scratchBuffer, frameCount: count, stereo: false)
        // Insert FX (mono, in place). Gated so it is a true no-op until enabled.
        if fxEnabled {
            fxChain.processBufferMono(&scratchBuffer, frameCount: count)
        } else {
            fxChain.noteRenderSkipped()
        }
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        scratchBuffer.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            // Same source-node-output sweep as `PolySynthVoice.copy`; this voice runs
            // the same FX chain and the same bio path. See `AudioOutputGuard`.
            AudioOutputGuard.copySilencingNonFinite(from: base, to: dst, count: count)
        }
        if frameCount > count {
            // Defensive: zero-fill anything past our scratch window.
            (dst + count).update(repeating: 0, count: frameCount - count)
        }
    }

    nonisolated private static func silence(
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count > 0, let raw = abl[0].mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        dst.update(repeating: 0, count: frameCount)
    }
}

/// Trivial weak holder so the audio-thread render closure can capture
/// a reference to a MainActor-bound class without retaining it.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Bio-modulation parameters handed from the MainActor poll to the audio thread
/// via a lock-free queue. Trivial value type (no ARC, no heap) → safe to cross
/// threads. Applying it on the audio thread keeps the synth's spectral-array
/// rewrite off the main thread, so it never races render()'s read of that array.
private struct BioParams: Sendable {
    let coherence: Float
    let hrv: Float
    let heartRate: Float
    let breathPhase: Float
    let breathDepth: Float
    let lfHf: Float
    let coherenceTrend: Float
}
