#if canImport(SwiftUI)
import SwiftUI
import Foundation

// PianoRollView.swift
// Echoel — polyphonic melodic piano roll driving the live PolySynthVoice.
//
// A real roll, not a step grid: notes have a pitch, a start step, a length in
// steps (legato/sustain across boundaries), and a per-note velocity. Editing is
// tap-to-place / drag-to-stretch on a scrollable, zoomable canvas; the selected
// note gets a velocity + length inspector. Notes drive PolySynthVoice directly
// (chords), and note-offs fire at note END (length), scheduled on the ONE shared
// PatternEngine clock via `pattern.onTick` — drums + melody stay on one transport.

/// The minimal note interface the roll routes through — every voice the roll
/// plays sits behind the ONE `outputVoice(for:)` router.
@MainActor
public protocol NoteVoice: AnyObject {
    func noteOn(pitch: Int, velocity: Float)
    func noteOff(pitch: Int)
    func allNotesOff()
}
extension PolySynthVoice: NoteVoice {}
// S2-W2-6: the rack kind voices also route the PRIMARY roll when its lane is a
// drums / sub-bass instrument. Guarded on Accelerate (LaneDrumKitVoice's extra
// dependency); SubBassVoice needs only AVFoundation, which this SwiftUI file
// already requires (it stores a SubBassVoice). No Apple platform has SwiftUI
// without both, so the flag-ON path compiles on every real target.
extension SubBassVoice: NoteVoice {}
#if canImport(Accelerate)
extension LaneDrumKitVoice: NoteVoice {}
#endif

/// Editable polyphonic melodic pattern + its trigger logic.
@MainActor
@Observable
public final class PianoRollModel {

    public static let stepCount = 16
    /// Lowest displayed pitch (C2) and how many semitone rows are shown (→ C6).
    public static let lowPitch = 36
    public static let pitchCount = 49
    public static var highPitch: Int { lowPitch + pitchCount - 1 }

    /// All notes in the pattern (absolute MIDI pitch).
    public private(set) var notes: [Note] = []

    @ObservationIgnored private weak var voice: PolySynthVoice?
    /// Optional dedicated LEAD instrument voice (multitimbral). When set, notes tagged
    /// `.lead` play through it (its own timbre) while everything else stays on `voice`,
    /// so a take reads as separate instruments instead of one surface. nil → the lead
    /// falls back to `voice` (single-timbre behaviour, unchanged).
    @ObservationIgnored private weak var lead: PolySynthVoice?
    /// Optional sub-bass voice — the lowest notes of each take also drive this an
    /// octave down so the bass can be FELT (sub/headphones/haptics). nil = no sub.
    @ObservationIgnored private weak var subVoice: SubBassVoice?
    /// S2-W2-6 ("Spur = Instrument"): when the PRIMARY roll lane carries a
    /// non-poly instrument (a drums kit / dedicated sub), the app sets this to
    /// that physical kind voice and the WHOLE roll plays through it instead of
    /// the poly `voice`/`lead` — and the mono sub-DOUBLING is skipped (the kind
    /// voice IS the instrument, not something to double). nil ⇒ today's poly
    /// path, bit-identical. Weak like the other voice refs (the rack owns it).
    @ObservationIgnored private weak var kindVoice: (any NoteVoice)?
    /// Optional live MIDI/MPE OUT — mirrors every note the synth plays to the
    /// virtual "Echoelmusic" source so a DAW records the body's take in real time.
    /// nil or disabled = silent (no-op); never affects the audio path.
    @ObservationIgnored private weak var midiOut: MIDIOutput?
    /// Optional song player — when an Arrangement is playing it advances on each
    /// bar boundary and loads the next section's clip BEFORE that bar's notes
    /// trigger. Fed from the same shared `onTick` so the song stays on one clock.
    @ObservationIgnored private weak var arrangement: ArrangementPlayer?
    /// The arrange TIMELINE player (reorg P3) — fed the SAME shared `onTick` as the
    /// arrangement, right beside it, so it loads a region's clip BEFORE that step's
    /// notes trigger (no seam). nil / not-playing = a pure no-op, so the live
    /// Generate+Play instrument path is untouched.
    @ObservationIgnored private weak var timeline: TimelineRegionPlayer?
    /// Optional parameter automation — applied each step on this same shared clock
    /// (writes main-thread-safe params: master level / tempo). nil = no-op.
    @ObservationIgnored private weak var automation: AutomationPlayer?
    /// Notes currently sounding → so we can fire their note-off at end step.
    @ObservationIgnored private var active: [UUID: Note] = [:]
    /// The roll pitch the felt sub is currently reinforcing (octave-down is applied
    /// when sent to the sub voice), or nil = sub silent. The sub is reconciled to the
    /// LOWEST sounding note each tick from `active`, so an evolving pattern can never
    /// strand a wrong sub pitch (the old per-tick `bassCeiling` gate could skip a
    /// note-off when the bass register shifted, leaving a stuck wrong-pitch drone).
    @ObservationIgnored private var currentSubPitch: Int?
    /// Staged next pattern, swapped in seamlessly at the loop boundary (step 0)
    /// so a live re-seed never cuts a sustaining note mid-bar (no click/gap).
    @ObservationIgnored private var pendingNotes: [Note]?

    // MARK: - Multi-bar arrangement (bar-cycling, 1b)
    /// The N distinct 16-step bars of the current take. When count > 1 the roll CYCLES
    /// through them — a different bar each loop — so the composition is "loop-konform und
    /// je nach Loop-Größe umgestellt" (founder). Empty / single = classic 1-bar loop.
    @ObservationIgnored private var arrangementBars: [[Note]] = []
    /// Bars played since transport start — advances at every step-0 wrap, exactly like the
    /// transport's bar counter, so the sounding bar is `arrangementBars[playedBars % N]`,
    /// (see `playedBars` below; `operatorLoopPass` is the OPERATOR clock — it counts
    /// EVERY bar wrap, single-bar loops included, which `playedBars` does not),
    /// keeping the audio IN SYNC with the transport's "bar N/M" loop indicator (no drift,
    /// even across a live re-seed which hot-swaps the bars without resetting the phase).
    @ObservationIgnored private var playedBars = 0
    /// Rotation added to `playedBars` when staging the next arrangement bar, so a
    /// timeline REGION loaded mid-song cycles ITS OWN bars from ITS OWN start
    /// (M1b — `playedBars` is global since Play; a region landing at global bar G
    /// must not start on bar G % N of its content). 0 for the generative path
    /// (loadArrangement/load/clear reset it), computed by `ArrangementLoadPlan`
    /// for region loads (loadRegionArrangement).
    @ObservationIgnored private var arrangementPhaseOffset = 0
    /// The note-operator loop clock: −1 before the first bar, then the 0-based
    /// pass number, incremented at EVERY step-0 wrap (unlike `playedBars`, which
    /// only advances for multi-bar arrangements). Drives chance/occurrence so a
    /// single-bar loop still evolves pass by pass. Reset on stop → a replay is
    /// the IDENTICAL take (deterministic, seeded — the "seed = take" law).
    @ObservationIgnored private var operatorLoopPass = -1
    /// Fixed take seed for operator dice rolls (chance). Constant by design:
    /// same clip + same pass → same outcome, every playthrough, every launch.
    /// A user-facing per-take seed can replace this later without model changes.
    private static let operatorSeed: UInt64 = 0xEC0E1_5EED

    // MARK: - Musical-parameter publishing (DMMW backbone)
    // The roll is the source of "what's sounding now", so it publishes a MusicalFrame
    // on the bus each tick — the music-side mirror of the bio snapshot. Renderers
    // (visual/light/spatial) subscribe and map it to colour/motion. nil bus = no-op.
    // See docs/dev/DMMW_ARCHITECTURE.md and Core/MusicalFrame.swift.
    @ObservationIgnored private weak var bus: EngineBus?
    /// Live musical context for the published frame, pushed by the Studio when the
    /// take re-seeds (key/scale/tempo/concert-pitch). Defaults are inert (root -1).
    @ObservationIgnored public var musicalA4Hz: Double = 440
    @ObservationIgnored public var musicalRootPitchClass: Int = -1
    @ObservationIgnored public var musicalScaleName: String = ""
    @ObservationIgnored public var musicalTempoBPM: Double = 0
    /// K2a lane mix: the Arrange track that owns this roll (first non-bio MIDI
    /// lane until A1 multi-roll) scales every NEW attack — built-in voices, MIDI
    /// out and the hosted AU alike. 0 = muted: attacks are skipped while releases
    /// and bookkeeping keep running, so nothing ever hangs. Set by the timeline
    /// surface from `TimelineDocument.rollSlotGain`; default unity = unchanged.
    @ObservationIgnored public var mixGain: Float = 1.0

    /// ONE-SHOT: "the stop that is about to happen is a PAUSE, not the end of the session."
    ///
    /// ⚠ DORMANT since 2026-07-26. The only producer is `PianoRollView.transport`, and the
    /// founder had the roll's door removed ("Pianoroll soll raus"), so no view mounts it and
    /// this flag can no longer be raised. The mechanism is kept, not deleted, because the
    /// invariant below is the expensive part and would have to be re-derived the moment any
    /// surface can request a playback-only stop again. Retiring it is its own slice (#180).
    ///
    /// The app has ONE Stop by law: whenever the shared transport stops from anywhere, the
    /// Studio ends the bio session too, so nothing is left armed behind a stopped clock. That
    /// is right for the chrome's ■ — and punishing for the roll's own transport button, which
    /// a user presses to hear an edit standing still. It tore down the camera and the pulse
    /// lock, so re-starting cost another finger-on-lens re-lock; the Notes editor was
    /// effectively unusable during a live take (ship gate 2 "Kontrolle").
    ///
    /// The roll therefore RAISES this flag before it stops the transport, and the Studio's stop
    /// cascade CONSUMES it: flag up ⇒ pause playback and keep the body session; flag down ⇒ the
    /// full stop, unchanged.
    ///
    /// THE ONE INVARIANT THAT MATTERS: the consumer must read this UNCONDITIONALLY, ahead of
    /// every guard. The first version of #161 read it after a `guard running`, so a pause
    /// requested with no take live stayed outstanding and turned the next REAL Stop into a
    /// pause — music off but camera and torch still on. `TransportTransition.decide` exists so
    /// that guard sits downstream of the read; `stopEverything` clears the flag as well, for the
    /// stop paths that never pass the observer. Do not reintroduce a condition around the read.
    @ObservationIgnored private var playbackOnlyStopRequested = false

    /// Mark the NEXT transport stop as playback-only (see `playbackOnlyStopRequested`).
    public func requestPlaybackOnlyStop() { playbackOnlyStopRequested = true }

    /// Read AND clear the request. Returns true exactly once per `requestPlaybackOnlyStop()`.
    public func consumePlaybackOnlyStopRequest() -> Bool {
        defer { playbackOnlyStopRequested = false }
        return playbackOnlyStopRequested
    }

    public init() {}

    // MARK: - Undo / Redo (#58 — TimelineStore's proven snapshot-stack pattern)

    /// Whole-pattern snapshots (Note is a small value type; 50 × a bar of notes
    /// is tiny). One snapshot per USER EDIT: add/remove/clear/quantize snapshot
    /// internally; drags snapshot ONCE at gesture-begin via `snapshotForUndo()`
    /// (never per onChanged tick — that would explode the stack).
    @ObservationIgnored private var undoStack: [[Note]] = []
    @ObservationIgnored private var redoStack: [[Note]] = []
    private static let undoDepth = 50
    /// Observable button states (the stacks themselves are @ObservationIgnored).
    public private(set) var canUndo = false
    public private(set) var canRedo = false

    /// Push the CURRENT pattern as an undo point. Call before a mutation batch
    /// (the model's own editing methods do this; views call it at drag-begin).
    public func snapshotForUndo() {
        undoStack.append(notes)
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(notes)
        notes = previous
        canUndo = !undoStack.isEmpty
        canRedo = true
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(notes)
        notes = next
        canUndo = true
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Editing

    /// The note (if any) sounding at `pitch` during `step`.
    public func note(atPitch pitch: Int, step: Int) -> Note? {
        notes.first { $0.pitch == pitch && $0.covers(step: step) }
    }

    /// Add a note, clamping its length so it never crosses the loop boundary.
    @discardableResult
    public func add(pitch: Int, startStep: Int, lengthSteps: Int = 1, velocity: Float = 0.8) -> Note {
        snapshotForUndo()
        let maxLen = max(1, Self.stepCount - startStep)
        let note = Note(
            pitch: pitch, startStep: startStep,
            lengthSteps: min(max(1, lengthSteps), maxLen), velocity: velocity
        )
        notes.append(note)
        return note
    }

    /// The WHOLE take flattened to absolute ticks for export (founder: "einen 8/16-Takt-Loop
    /// … in der DAW weiterarbeiten"). When the roll is cycling N distinct bars, each bar `b`
    /// is offset by `b` whole bars so the exported region is really N bars long — not the
    /// single sounding bar. Falls back to the current 1-bar `notes` when not cycling.
    /// Returns `(notes, bars)` so the exporter can anchor the region to exactly N bars.
    public func arrangementForExport() -> (notes: [Note], bars: Int) {
        guard arrangementBars.count > 1 else { return (notes, 1) }
        let barTicks = Self.stepCount * Note.ticksPerStep   // 16 steps × 120 ticks = 1920 / bar
        var out: [Note] = []
        out.reserveCapacity(arrangementBars.reduce(0) { $0 + $1.count })
        for (b, bar) in arrangementBars.enumerated() {
            let offset = b * barTicks
            for n in bar { out.append(n.nudged(byTicks: offset)) }
        }
        return (out, arrangementBars.count)
    }

    public func remove(id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        snapshotForUndo()
        notes.removeAll { $0.id == id }
    }

    /// Remove every note in `ids` (marquee group-delete, #58 Slice 5). Empty set
    /// is a no-op; unknown ids are ignored.
    public func remove(ids: Set<UUID>) {
        guard !ids.isEmpty, notes.contains(where: { ids.contains($0.id) }) else { return }
        snapshotForUndo()
        notes.removeAll { ids.contains($0.id) }
    }

    public func setLength(id: UUID, lengthSteps: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let maxLen = max(1, Self.stepCount - notes[i].startStep)
        notes[i].lengthSteps = min(max(1, lengthSteps), maxLen)
    }

    public func setVelocity(id: UUID, _ velocity: Float) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].velocity = velocity.clamped(to: 0...1)   // NaN-safe — see `Note`'s init
    }

    /// #58 S6b: set a note's per-note MPE overrides from the inspector. Always
    /// routed through NoteMPE's clamping init; a fully transparent result
    /// collapses back to `nil` so the note's JSON stays byte-identical to a
    /// plain note (the seam's backward-compat contract).
    public func setMPE(id: UUID, bend: Float?, slide: Float?, pressure: Float?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let m = NoteMPE(bend: bend, slide: slide, pressure: pressure)
        notes[i].mpe = m.isTransparent ? nil : m
    }

    /// A1 per-note CHANCE (founder "Ableton note chance", 2026-07-17): set the
    /// probability [0…1] that a note plays each loop pass, from the Chance paint-lane.
    /// Preserves any repeats/occurrence/expression the note already carries, routes
    /// through NoteOperators' clamping init, and — like `setMPE` — collapses a
    /// now-default operator bag back to `nil` so the note's JSON stays byte-identical
    /// to a plain note (the backward-compat seam). A live body still bends this
    /// threshold at play time (A4 `bioBentChance`); this sets the base the body bends.
    public func setChance(id: UUID, _ chance: Double) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let base = notes[i].operators ?? NoteOperators()
        let updated = NoteOperators(chance: chance,
                                    repeats: base.repeats,
                                    repeatRamp: base.repeatRamp,
                                    occurrencePeriod: base.occurrencePeriod,
                                    occurrencePhase: base.occurrencePhase,
                                    velocityDepth: base.velocityDepth,
                                    timingDepth: base.timingDepth,
                                    filterDepth: base.filterDepth)
        notes[i].operators = updated.isDefault ? nil : updated
    }

    /// The note's current play chance for the Chance paint-lane (plain note = 1).
    public func chance(id: UUID) -> Double {
        notes.first(where: { $0.id == id })?.operators?.chance ?? 1
    }

    /// OCCURRENCE (A1 R5, founder "Repeats/Occurrence als Lane-Modi"): play this
    /// note only every `period`-th loop pass (1 = every loop, Ableton's 1:N ratio).
    /// Honored at playback via `operatorAllows`→`hits` (occurrence gate); Repeats
    /// (ratchet) is deliberately NOT a lane mode yet — it needs the sample-accurate
    /// sub-step clock (W2) and would be a silent no-op today. Mirrors `setChance`:
    /// preserves the note's other operators, clamps via NoteOperators' init
    /// (periodRange 1…64), and collapses a now-default bag back to `nil` so a plain
    /// note stays byte-identical. Phase stays as-is (paint sets only the period).
    public func setOccurrence(id: UUID, _ period: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let base = notes[i].operators ?? NoteOperators()
        let updated = NoteOperators(chance: base.chance,
                                    repeats: base.repeats,
                                    repeatRamp: base.repeatRamp,
                                    occurrencePeriod: period,
                                    occurrencePhase: base.occurrencePhase,
                                    velocityDepth: base.velocityDepth,
                                    timingDepth: base.timingDepth,
                                    filterDepth: base.filterDepth)
        notes[i].operators = updated.isDefault ? nil : updated
    }

    /// The note's current occurrence PERIOD for the Occurrence paint-lane (plain
    /// note = 1 = plays every loop).
    public func occurrencePeriod(id: UUID) -> Int {
        notes.first(where: { $0.id == id })?.operators?.occurrencePeriod ?? 1
    }

    /// Reposition a note to a new pitch + start step, preserving its length. Pitch
    /// clamps to the roll's range; the start clamps so the note never crosses the
    /// loop boundary (its tail stays inside the bar). The drag-to-move primitive —
    /// #58 Slice 2. No-op if the note was deleted mid-drag.
    /// NON-DESTRUCTIVE (#58, night audit 2026-07-16): moves by whole-step TICK
    /// DELTA instead of the rounding `startStep` setter — a recorded note sitting
    /// 30 ticks behind the grid keeps its feel through any number of drags (the
    /// old path snapped it to the grid on the FIRST touch). Quantizing is an
    /// explicit, separate action (`quantize(ids:)`), never a drag side-effect.
    public func move(id: UUID, toPitch pitch: Int, toStartStep startStep: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let len = notes[i].lengthSteps
        notes[i].pitch = min(max(pitch, Self.lowPitch), Self.highPitch)
        let target = min(max(startStep, 0), max(0, Self.stepCount - len))
        let deltaSteps = target - notes[i].startStep
        guard deltaSteps != 0 else { return }
        let maxStart = max(0, Self.stepCount * Note.ticksPerStep - notes[i].lengthTicks)
        notes[i].startTick = min(max(0, notes[i].startTick + deltaSteps * Note.ticksPerStep),
                                 maxStart)
    }

    /// Quantize note starts to a grid — the door for the previously never-wired
    /// `Note.quantizedStart`. Empty `ids` = the whole pattern. `toTicks` picks
    /// the grid (#58 S7: subdivisions + triplets via `QuantizeDivision`);
    /// default = today's 1/16 behaviour. One undoable edit.
    public func quantize(ids: Set<UUID>, toTicks division: Int = Note.ticksPerStep) {
        guard division > 0 else { return }
        let affected = notes.indices.filter { ids.isEmpty || ids.contains(notes[$0].id) }
        guard !affected.isEmpty else { return }
        snapshotForUndo()
        for i in affected {
            notes[i] = notes[i].quantizedStart(toTicks: division)
        }
    }

    // MARK: - Selection ops (R1 — PLAN_ROLL_PRO.md)

    /// Apply a pure note transform to the selected subset (empty `ids` = ALL
    /// notes) as ONE undoable edit — the same undo law as `quantize`. The
    /// transform receives the affected notes and returns their replacement
    /// (it may add notes — Echo); unaffected notes survive byte-identical.
    /// A transform that changes nothing skips the snapshot (no phantom undo).
    public func applyOp(ids: Set<UUID>, _ transform: ([Note]) -> [Note]) {
        let affected = notes.filter { ids.isEmpty || ids.contains($0.id) }
        guard !affected.isEmpty else { return }
        let replaced = transform(affected)
        guard replaced != affected else { return }
        snapshotForUndo()
        let affectedIDs = Set(affected.map(\.id))
        notes.removeAll { affectedIDs.contains($0.id) }
        notes.append(contentsOf: replaced)
    }

    /// The take's key, reconstructed from the pushed musical context (root
    /// pitch-class + `Scale` rawValue — the same values the Studio pushes on
    /// every re-seed). nil until a real key arrived (root −1 / unknown scale
    /// name), so a context-less clip editor hides its scale tools honestly.
    public var musicalKey: MusicalKey? {
        guard musicalRootPitchClass >= 0,
              let scale = Scale(rawValue: musicalScaleName) else { return nil }
        return MusicalKey(root: musicalRootPitchClass, scale: scale)
    }

    /// Echoel twist (R1): the body's CURRENT HRV loosens the selected notes'
    /// velocities via the H3 core (`BioComposer.hrvHumanize` — reused, not
    /// duplicated). ONE-SHOT read of the control-plane bio snapshot at tap
    /// time — never a 10 Hz read in a view body (freeze law). Seed = stable hash
    /// of the affected notes, so the op is deterministic per (selection state,
    /// hrv); hrv 0 → zero jitter → no-op, no undo step.
    public func bioHumanize(ids: Set<UUID>) {
        // Deliberately RAW and falling back to 0, not `hrvForSound` and not 0.5. This
        // is a discrete operation the user invoked BY NAME, not a continuous mapping
        // that has to keep sounding, so the honest form is available: no HRV measured
        // — or no body at all, including the bus-less clip editor — means nothing is
        // touched. A neutral 0.5 here would apply seeded velocity jitter and present
        // it to the user AS their heart-rate variability. `hrvHumanize` guards
        // `span > 0` and `applyOp` guards `replaced != affected`, so 0 is a true
        // no-op that also pushes no undo step.
        let hrv = bus?.usableBio()?.hrvNormalized ?? 0
        applyOp(ids: ids) { affected in
            BioComposer.hrvHumanize(affected, hrvNormalized: hrv,
                                    seed: RollNoteOps.stableSeed(for: affected))
        }
    }

    /// Echoel twist (R2): stamp a whole VOICE-LED, COHERENCE-CHOSEN chord where the
    /// finger taps — the composition's own harmonic brain (`RollChordStamp` =
    /// ChordSuggest H2 + VoiceLeader H1, reused) placed by hand. ONE-SHOT read of the
    /// control-plane coherence at tap time (never a 10 Hz body read — freeze law); no
    /// usable body falls back to a neutral 0.5. Deterministic per (cell, key,
    /// coherence) via a stable seed. No tonal context → a single note on the tapped
    /// row (honest fallback, same as a plain draw). ONE undo step. The voicing sits
    /// within the visible range: it is rooted at the tapped row and spans upward at
    /// most to `highPitch`, so every chord note stays on-screen and editable.
    @discardableResult
    public func stampChord(atPitch pitch: Int, startStep: Int, lengthSteps: Int = 1) -> [Note] {
        let anchor = min(max(pitch, Self.lowPitch), Self.highPitch)
        let step = max(0, startStep)
        let startTick = step * Note.ticksPerStep
        let maxLenSteps = max(1, Self.stepCount - step)
        let lengthTicks = min(max(1, lengthSteps), maxLenSteps) * Note.ticksPerStep
        guard let key = musicalKey else {
            return [add(pitch: anchor, startStep: startStep, lengthSteps: lengthSteps)]
        }
        // `coherenceForSound`: the `??` catches only a MISSING frame, so a live frame
        // with unmeasured coherence still reached the stamp as 0 = least consonant.
        let coherence = bus?.usableBio()?.coherenceForSound ?? 0.5
        let span = max(1, min(12, Self.highPitch - anchor))
        // Stable per-cell seed so the same body-state stamps the same chord there.
        let seed = UInt64(truncatingIfNeeded: startTick) &* 2_654_435_761
                 &+ UInt64(truncatingIfNeeded: anchor)
        let chord = RollChordStamp.stamp(anchorPitch: anchor, startTick: startTick,
                                         lengthTicks: lengthTicks, velocity: 0.8,
                                         key: key, coherence: coherence,
                                         seed: seed, registerSpan: span)
        guard !chord.isEmpty else { return [] }
        snapshotForUndo()
        notes.append(contentsOf: chord)
        return chord
    }

    /// Echoel twist (R2 + Scaler #4): the body ARPEGGIATES. Pick the coherence-chosen
    /// chord (exactly as `stampChord` does), then let the LIVE breath play it as an
    /// arpeggio across the rest of the bar via `BreathArp`: breath phase = direction,
    /// coherence = density, motion = downbeat accent, pulse = swing. All bio read ONCE
    /// at tap time (never a 10 Hz body read — freeze law). No tonal context → the
    /// tapped note (honest fallback). ONE undo step for the whole figure.
    @discardableResult
    public func stampArp(atPitch pitch: Int, startStep: Int) -> [Note] {
        let anchor = min(max(pitch, Self.lowPitch), Self.highPitch)
        let step = max(0, startStep)
        let startTick = step * Note.ticksPerStep
        guard let key = musicalKey else {
            return [add(pitch: anchor, startStep: startStep)]
        }
        let bio = bus?.usableBio()
        let coherence = bio?.coherenceForSound ?? 0.5   // see `stampChord`
        let span = max(1, min(12, Self.highPitch - anchor))
        let seed = UInt64(truncatingIfNeeded: startTick) &* 2_654_435_761
                 &+ UInt64(truncatingIfNeeded: anchor)
        // The coherence-chosen chord's pitches (computed here, placed as an arp below).
        let chord = RollChordStamp.stamp(anchorPitch: anchor, startTick: startTick,
                                         lengthTicks: Note.ticksPerStep, velocity: 0.8,
                                         key: key, coherence: coherence,
                                         seed: seed, registerSpan: span)
        let pitches = chord.map(\.pitch)
        guard !pitches.isEmpty else { return [] }
        let steps = max(1, Self.stepCount - step)   // fill the tapped cell → bar end
        let arp = BreathArp.pattern(
            chordPitches: pitches, steps: steps,
            breathPhase: Float(bio?.breathPhase ?? 0.25),
            breathDepth: coherence,                          // calmer body → fuller, steadier arp
            startTick: startTick, stepTicks: Note.ticksPerStep, velocity: 0.8,
            motionAccent: Float(bio?.motionEnergy ?? 0),     // movement accents the downbeats
            swing: Self.pulseSwing(bio?.heartRateBPM))       // quicker pulse swings more
        guard !arp.isEmpty else { return [] }
        snapshotForUndo()
        notes.append(contentsOf: arp)
        return arp
    }

    /// Heart rate → swing [0..1]: ~60 bpm (calm) straight, ~120 bpm (lively) full swing.
    static func pulseSwing(_ bpm: Float?) -> Float {
        guard let bpm, bpm.isFinite, bpm > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, (bpm - 60) / 60))
    }

    /// Test seam: plant an off-grid start tick (simulates a recorded note).
    /// Internal on purpose — production paths go through add/move/quantize.
    func setStartTickForTesting(index: Int, tick: Int) {
        guard notes.indices.contains(index) else { return }
        notes[index].startTick = max(0, tick)
    }

    public func clear() {
        guard !notes.isEmpty else { return allNotesOff() }
        snapshotForUndo()
        notes.removeAll()
        pendingNotes = nil   // else a staged bar would resurrect what was just cleared
        arrangementBars = [] // stop cycling — a cleared roll is a single (empty) bar
        arrangementPhaseOffset = 0
        allNotesOff()        // release anything sounding so clearing never hangs a note
    }

    /// Replace all notes (used when launching a melody clip). Flush any notes
    /// currently sounding first, otherwise regenerating mid-playback leaves the
    /// old notes' entries in `active` → stuck/lingering notes. A plain single-bar
    /// load ENDS any multi-bar cycling (a launched clip / loaded project is one bar).
    public func load(_ newNotes: [Note]) {
        allNotesOff()
        pendingNotes = nil
        arrangementBars = []
        arrangementPhaseOffset = 0
        notes = newNotes
    }

    /// Install a fired clip's own automation onto the shared AutomationPlayer
    /// (cycle 4). Clip automation travels + plays WITH the clip, like its notes;
    /// every clip-launch path routes through here (the one place that holds the
    /// automation reference). Passing `[]` — a silent gap or a clip without
    /// automation — clears the previous clip's lanes. No automation wired = no-op.
    public func setClipAutomation(_ lanes: [AutomationLane]) {
        automation?.setClipLanes(lanes)
    }

    /// Install the ARRANGEMENT's song-absolute automation onto the shared
    /// AutomationPlayer (cycle 5). The timeline player calls this on play (with
    /// the document's lanes) and on stop (with `[]`); it holds the same automation
    /// reference as the clip channel. No automation wired = no-op.
    public func setTimelineAutomation(_ lanes: [AutomationLane]) {
        automation?.setTimelineLanes(lanes)
    }

    /// Feed the timeline layer the song-absolute playhead tick each transport step
    /// (cycle 5). Routed through the roll so the timeline player needs no separate
    /// automation reference.
    public func setTimelineAutomationTick(_ tick: Int) {
        automation?.setTimelineTick(tick)
    }

    /// Load an N-bar arrangement that CYCLES one bar per loop (1b). `playing` = the
    /// transport is already running (a live re-seed), so hot-swap the bars and stage the
    /// phase-correct next bar for the upcoming boundary — the sounding bar is never cut.
    /// When stopped, bar 0 loads now so it is present before playback starts.
    public func loadArrangement(_ bars: [[Note]], playing: Bool) {
        guard bars.count > 1 else { load(bars.first ?? []); return }   // 0/1 bar → classic path
        // Generative path is phase-0 by definition — without this reset a stale
        // region rotation (loadRegionArrangement) would permanently skew every
        // Generate/evolve cycle after timeline playback (reviewer M1b MEDIUM).
        arrangementPhaseOffset = 0
        if playing {
            arrangementBars = bars
            // Next boundary already plays NEW content, at the current phase (keeps sync
            // with the transport's loop indicator; playedBars is NOT reset on re-seed).
            pendingNotes = bars[playedBars % bars.count]
        } else {
            allNotesOff()
            pendingNotes = nil
            playedBars = 0
            // `arrangementBars` stays the TRUE bars — every wrap (`trigger`'s
            // `arrangementBars[(playedBars + offset) % count]`) and `arrangementForExport()`
            // read straight from it, so cycling/export are never touched by the line below.
            arrangementBars = bars
            // Task #77 (founder ear-feedback 2026-07-21, "am Anfang ... laute Melodie"):
            // ONLY the note array staged into `notes` right now — what actually sounds
            // the instant Play is pressed after a fresh Generate — gets its lead
            // softened, so the groove has a beat to establish first. This must NOT be
            // baked into `arrangementBars`: an earlier version of this fix did exactly
            // that and the softening then recurred on every wrap back to bar 0 (every
            // `loopBars` bars, forever) — audio-thread-reviewer-caught regression before
            // ship. A stop→replay of the same take re-primes `notes` from
            // `arrangementBars[0]` directly (see `pattern.onStop` below) — the softened
            // entrance is a once-per-fresh-take event, not reapplied on every replay.
            notes = IntroAttenuation.apply(bars[0], isFirstBar: true)
        }
    }

    /// Import externally-authored notes (e.g. a Standard MIDI File) onto the
    /// single-bar roll. The roll is one `stepCount`-step bar with a fixed pitch
    /// window, so we make an imported clip *comprehensible* rather than dropping
    /// most of it: keep the first bar's notes, clamp each length inside the bar,
    /// and octave-fold every pitch into the visible range. Pure/deterministic so
    /// it is unit-testable. Returns the notes actually placed (for a UI count).
    @discardableResult
    public func importNotes(_ newNotes: [Note]) -> [Note] {
        let folded = Self.foldToBar(newNotes)
        load(folded)
        return folded
    }

    /// Fold imported notes into one visible bar: first-bar only, length clamped to
    /// the bar, pitch octave-folded into [lowPitch, highPitch]. Static + pure.
    public static func foldToBar(_ newNotes: [Note]) -> [Note] {
        newNotes.compactMap { n -> Note? in
            guard n.startStep >= 0, n.startStep < stepCount else { return nil }
            let maxLen = max(1, stepCount - n.startStep)
            var pitch = n.pitch
            while pitch < lowPitch { pitch += 12 }
            while pitch > highPitch { pitch -= 12 }
            guard pitch >= lowPitch, pitch <= highPitch else { return nil }
            return Note(pitch: pitch, startStep: n.startStep,
                        lengthSteps: min(max(1, n.lengthSteps), maxLen),
                        velocity: n.velocity)
        }
    }

    /// Load a timeline REGION's bar slices with REGION-RELATIVE cycling (M1b of
    /// the clip-pro healing block, founder 2026-07-15 — audit wf_9c6f33b7: only
    /// bar 1 of a clip ever played). Unlike `loadArrangement` (the generative
    /// re-seed: sounding bar keeps playing, new content from the next boundary,
    /// global phase), a region ONSET applies its bar NOW:
    ///  • playing → seamless hot-swap, NO allNotesOff — sustains from the previous
    ///    region release at their own end (the pro split/region-change behavior;
    ///    windowing already clipped every note at its region's end, so nothing
    ///    outlives its block);
    ///  • stopped → classic full reset, bar sounds when Play starts.
    /// The phase mathematics live in `ArrangementLoadPlan` (pure, tested):
    /// `atStepZero` matters because trigger(0) runs AFTER this call in the same
    /// tick and would immediately consume anything staged.
    public func loadRegionArrangement(_ bars: [[Note]], startBar: Int,
                                      atStepZero: Bool, playing: Bool) {
        guard !bars.isEmpty else { load([]); return }
        let plan = ArrangementLoadPlan.plan(barCount: bars.count, startBar: startBar,
                                            playedBars: playedBars,
                                            atStepZero: atStepZero, playing: playing)
        if playing {
            arrangementBars = bars.count > 1 ? bars : []
            arrangementPhaseOffset = plan.phaseOffset
            notes = bars[plan.nowIndex]
            pendingNotes = plan.pendingIndex.map { bars[$0] }
        } else {
            allNotesOff()
            playedBars = 0
            arrangementBars = bars.count > 1 ? bars : []
            arrangementPhaseOffset = plan.phaseOffset
            notes = bars[plan.nowIndex]
            pendingNotes = nil
        }
    }

    /// Stage a new pattern to swap in seamlessly at the next loop boundary.
    /// Unlike `load`, this does NOT cut sounding notes — held notes ring to their
    /// natural end and the new bar layers in on the downbeat (step 0). This is the
    /// path the live evolution uses while playing, so re-seeding never clicks.
    public func loadAtBoundary(_ newNotes: [Note]) {
        pendingNotes = newNotes
    }

    // MARK: - Transport (shared clock)

    public func start(pattern: PatternEngine, voice: PolySynthVoice,
                      lead: PolySynthVoice? = nil,
                      subVoice: SubBassVoice? = nil, midiOut: MIDIOutput? = nil,
                      arrangement: ArrangementPlayer? = nil, bus: EngineBus? = nil,
                      automation: AutomationPlayer? = nil,
                      timeline: TimelineRegionPlayer? = nil) {
        self.voice = voice
        self.lead = lead
        self.subVoice = subVoice
        self.midiOut = midiOut
        self.arrangement = arrangement
        self.timeline = timeline
        self.automation = automation
        self.bus = bus
        // Advance the song first (loads the next section's clip on a bar wrap), apply
        // automation for this step, THEN trigger this step's notes — so a new section
        // plays from step 0 cleanly and params are set before the notes sound.
        pattern.onTick = { [weak self] step in
            self?.arrangement?.transportStep(step)
            self?.timeline?.transportStep(step)   // reorg P3: no-op unless timeline play is engaged
            self?.automation?.applyStep(step)
            self?.trigger(step)
        }
        // Any stop (from any view) flushes held notes AND resets the loop phase — this hook
        // fires on EVERY stop path (pattern.stop() → onStop), unlike stop(pattern:) which is
        // not wired. Resetting here keeps a replay in sync: the transport rewinds position.bar
        // to 0 on stop, so playedBars must rewind too, or the next Play starts on the wrong
        // bar with a permanent phase offset vs the "bar N/M" indicator.
        pattern.onStop = { [weak self] in
            guard let self else { return }
            self.pendingNotes = nil
            self.playedBars = 0
            self.operatorLoopPass = -1   // replay = the identical deterministic take
            // A stopped roll rewinds to bar 0 of whatever is loaded; a timeline
            // region's phase rotation is stale after the rewind (a fresh Play
            // reloads regions via loadRegionArrangement anyway).
            self.arrangementPhaseOffset = 0
            if self.arrangementBars.count > 1 { self.notes = self.arrangementBars[0] }
            self.allNotesOff()
        }
    }

    public func stop(pattern: PatternEngine) {
        pattern.onTick = nil
        pendingNotes = nil
        allNotesOff()
    }

    public func allNotesOff() {
        endAudition()   // H12: cancel a pending preview note-off + release it
        for note in active.values { outputVoice(for: note.role)?.noteOff(pitch: note.pitch) }
        active.removeAll()
        currentSubPitch = nil
        voice?.allNotesOff()
        lead?.allNotesOff()
        subVoice?.allNotesOff()
        kindVoice?.allNotesOff()   // S2-W2-6: release the kind voice too
        midiOut?.allNotesOff()
    }

    /// The instrument voice a note plays through, by role (multitimbral routing):
    /// `.lead` → the dedicated lead voice when present, else the main voice;
    /// everything else → the main voice. All warm synth (no real instruments).
    private func outputVoice(for role: NoteRole) -> (any NoteVoice)? {
        // S2-W2-6: a non-poly primary lane routes EVERY role through its one kind
        // voice (a kit/sub is single-timbre — no pad/lead split). All the existing
        // active-tracking, wrap-tie and release-grouping logic flows through this
        // one router, so `sameVoice` stays correct (every role → the same voice).
        if let kindVoice { return kindVoice }
        return (role == .lead) ? (lead ?? voice) : voice
    }

    /// S2-W2-6: bind (or clear) the primary roll's kind voice. Releasing every
    /// sounding note first (offs route through the CURRENT `outputVoice`) so a
    /// mid-take swap never strands a gate-held note on the old voice. nil restores
    /// the poly path. Idempotent for an unchanged binding.
    public func setKindVoice(_ v: (any NoteVoice)?) {
        guard kindVoice !== v else { return }
        allNotesOff()
        kindVoice = v
    }

    // MARK: - Tap audition (H12 — kind-true preview in the clip editor)

    /// The voice currently sounding an audition preview + its pitch, so a new
    /// audition (or allNotesOff) can release it. Weak like every voice ref.
    @ObservationIgnored private weak var auditioningVoice: (any NoteVoice)?
    @ObservationIgnored private var auditioningPitch: Int?
    @ObservationIgnored private var auditionOffTask: Task<Void, Never>?

    /// Preview ONE note through its output voice — the clip editor's
    /// tap/draw feedback (H12: an EchoelDrums clip previews the KIT, not the
    /// poly synth). Routed via `outputVoice(for:)`, so a session with no
    /// bound voice stays silent (the honest-silent H11 editor for poly
    /// lanes, unchanged). Monophonic: a new audition releases the previous
    /// one first, so fast sketching never strands a held note. The note-off
    /// is scheduled UI-side (~0.2 s) and captures voice + pitch directly, so
    /// it still fires if this throwaway model is dismissed with its sheet.
    /// Main-actor only — nothing here touches the audio thread (the voices
    /// enqueue their own render-safe events).
    public func audition(pitch: Int, velocity: Float, role: NoteRole) {
        guard let v = outputVoice(for: role) else { return }
        endAudition()
        v.noteOn(pitch: pitch, velocity: velocity.clamped(to: 0.05...1))   // NaN-safe
        auditioningVoice = v
        auditioningPitch = pitch
        auditionOffTask = Task { [weak v] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            v?.noteOff(pitch: pitch)
        }
    }

    /// Release the in-flight audition note. Idempotent — a noteOff for a
    /// pitch that already released is a no-op in every NoteVoice.
    private func endAudition() {
        auditionOffTask?.cancel()
        auditionOffTask = nil
        if let p = auditioningPitch { auditioningVoice?.noteOff(pitch: p) }
        auditioningPitch = nil
        auditioningVoice = nil
    }

    /// Whether two roles play on the SAME underlying voice — used to group
    /// note-offs so a shared pitch on two instruments is released independently
    /// (identity comparison covers synth AND sampler routing).
    private func sameVoice(_ a: NoteRole, _ b: NoteRole) -> Bool {
        outputVoice(for: a) === outputVoice(for: b)
    }

    /// Give the dedicated lead voice its own timbre (multitimbral Step 2b). The
    /// generator picks a factory patch per genre so the lead line reads as a
    /// distinct instrument over the pad/bass, instead of a single fixed lead.
    /// No-op when there is no separate lead voice.
    public func applyLeadPatch(_ patch: SynthPatch) { lead?.apply(patch) }

    /// One wrap-tie: the ending note keeps ringing and the starting note takes
    /// over its bookkeeping instead of firing a fresh attack.
    public struct TiePair: Equatable, Sendable {
        public let endID: UUID
        public let startID: UUID
        public init(endID: UUID, startID: UUID) { self.endID = endID; self.startID = startID }
    }

    /// TIE AT THE WRAP (founder 2026-07-09 "Vermeide stolpern"): pair each note
    /// starting at the loop boundary with a note ending there that has the SAME
    /// pitch on the SAME output voice — that sound simply continues (no release,
    /// no re-attack). Without this the Fläche re-articulated its whole chord every
    /// bar (audible dip/swell) AND doubled the voice load at the seam (5 releasing
    /// + 5 attacking > 8 poly voices → stealing clicks). One-to-one matching via
    /// the used-set so unisons pair off cleanly. Pure + deterministic → unit-tested.
    public static func wrapTies(
        ending: [(id: UUID, pitch: Int, voiceKey: Int)],
        starting: [(id: UUID, pitch: Int, voiceKey: Int)]
    ) -> [TiePair] {
        var used = Set<UUID>()
        var out: [TiePair] = []
        for s in starting {
            // Prefer the same note continuing (a full-bar note meets itself at the
            // wrap), then any same-pitch/same-voice candidate.
            let match = ending.first { $0.id == s.id && !used.contains($0.id) }
                ?? ending.first { !used.contains($0.id) && $0.pitch == s.pitch && $0.voiceKey == s.voiceKey }
            guard let e = match, e.pitch == s.pitch, e.voiceKey == s.voiceKey else { continue }
            used.insert(e.id)
            out.append(TiePair(endID: e.id, startID: s.id))
        }
        return out
    }

    /// Whether a note plays on this loop pass, per its operators (chance +
    /// occurrence). Plain notes (nil/default operators) always play. With a
    /// live body, `coherence` bends the chance threshold (A4 Bio-Operators);
    /// nil keeps the gate fully deterministic. Pure and nonisolated so the
    /// gate law is unit-tested without a transport.
    public nonisolated static func operatorAllows(_ note: Note, loopPass: Int, seed: UInt64,
                                                  coherence: Double? = nil) -> Bool {
        guard let ops = note.operators, !ops.isDefault else { return true }
        return !ops.hits(for: note, loopIndex: loopPass, seed: seed, coherence: coherence).isEmpty
    }

    /// The body's per-note EXPRESSION for this loop pass (A5 bio-per-note). Plain
    /// notes (nil/default operators) and an absent body return the identity (scale 1,
    /// no shift, brightness nil), so plain takes stay byte-identical. Pure + nonisolated
    /// so the law is unit-tested without a transport, exactly like `operatorAllows`.
    public nonisolated static func noteExpression(_ note: Note, loopPass: Int, seed: UInt64,
                                                  coherence: Double? = nil,
                                                  breath: Double? = nil) -> NoteExpression {
        guard let ops = note.operators, !ops.isDefault else { return NoteExpression() }
        return ops.expression(for: note, loopIndex: loopPass, seed: seed,
                              coherence: coherence, breath: breath)
    }

    /// Stable per-voice identity for tie matching — mirrors `sameVoice` exactly:
    /// only two voices exist (main, dedicated lead), so the key is 1 iff the role
    /// routes to a DISTINCT lead voice, else 0.
    private func voiceKey(_ role: NoteRole) -> Int {
        guard let lead, lead !== voice else { return 0 }
        return outputVoice(for: role) === lead ? 1 : 0
    }

    /// Each tick: release notes ending now, then start notes beginning now.
    /// `endStep % stepCount` so a note ending on the bar line releases at the
    /// loop wrap (step 0) — unless an identical note starts there, in which case
    /// the two are TIED and the sound carries straight through (no stumble).
    nonisolated(unsafe) private static var triggerTraced = false
    private func trigger(_ step: Int) {
        if !Self.triggerTraced {
            Self.triggerTraced = true
            EchoelCrashLog.breadcrumb("trigger#1 step=\(step) notes=\(notes.count)")
        }
        // Seamless morph: at the loop boundary, swap in the staged pattern WITHOUT
        // an allNotesOff cut. Sustaining notes from the previous bar keep their
        // entries in `active` and release naturally at their own endStep below; the
        // new pattern's notes start via the normal startStep==step path. No gap.
        if step == 0 {
            // Advance the operator clock FIRST so this bar's gates see the new pass.
            operatorLoopPass += 1
            if let pending = pendingNotes {
                notes = pending
                pendingNotes = nil
            }
            // Bar-cycling (1b): advance the loop counter (mirrors the transport's bar count)
            // and STAGE the next bar for the upcoming boundary, so an N-bar arrangement plays
            // a different bar each loop — seamlessly (same pendingNotes path). Single/empty
            // arrangement leaves this untouched → classic 1-bar loop.
            if arrangementBars.count > 1 {
                playedBars += 1
                // Phase offset keeps a mid-song region's cycle region-relative (M1b);
                // 0 on the generative path, so that staging is byte-identical.
                pendingNotes = arrangementBars[(playedBars + arrangementPhaseOffset)
                                               % arrangementBars.count]
            }
        }
        // Release notes ending now. The engine's noteOff(pitch:) releases EVERY
        // voice of that pitch, so when two notes share a pitch (voice-leading can
        // produce this) we must only release a pitch once no surviving note still
        // holds it — otherwise a short note would cut off a sustained same-pitch one.
        let ending = active.filter { $0.value.endStep % Self.stepCount == step }
        // TIE AT THE WRAP ("Vermeide stolpern"): only at step 0 — the loop is a
        // circle, so a pitch ending on the bar line while the same pitch starts the
        // next pass is ONE continuous sound, not a release + re-attack. Mid-bar a
        // repeated pitch stays two deliberate hits (user-drawn rhythm). This also
        // makes evolve morphs seamless: pitches the new take keeps just keep ringing.
        // Per-note operators (A1): chance + occurrence gate a note per loop pass —
        // deterministic (seeded), so the take is reproducible. A gated-off note
        // simply never enters `starting`: no attack, no tie, its sound (if any)
        // from a previous pass releases normally. Repeats/ratchets need the
        // sample-accurate sub-step clock (W2) and are NOT evaluated here yet.
        // A4 Bio-Operators: a live body bends the chance threshold via
        // coherence (only on notes whose chance the user set below 1) — the
        // player's settling literally fills the pattern out. No bio → nil →
        // the gate stays fully deterministic.
        // Deliberately NOT `coherenceForSound`. This carrier is an Optional, so the
        // honest depth-to-zero form is available here and the neutral-value form is
        // not needed: an unmeasured coherence collapses to nil exactly like no body
        // at all, and the gate stays deterministic. Mapping it to 0 instead would
        // bend every chance threshold to one extreme on a body we have not read.
        let operatorCoherence = bus?.usableBio().flatMap {
            $0.coherence > 0 ? Double($0.coherence) : nil
        }
        // A5 bio-per-note: breath rides the same control-plane snapshot as coherence and
        // shapes each note's velocity (see the `starting` attack loop). nil body → identity.
        let operatorBreath = bus?.usableBio().map { Double($0.breathPhase) }
        let starting = notes.filter {
            $0.startStep == step
                && Self.operatorAllows($0, loopPass: operatorLoopPass, seed: Self.operatorSeed,
                                       coherence: operatorCoherence)
        }
        let ties = step == 0
            ? Self.wrapTies(
                ending: ending.map { (id: $0.key, pitch: $0.value.pitch, voiceKey: voiceKey($0.value.role)) },
                starting: starting.map { (id: $0.id, pitch: $0.pitch, voiceKey: voiceKey($0.role)) })
            : []
        let tiedEnd = Set(ties.map(\.endID))
        let tiedStart = Set(ties.map(\.startID))
        // Carry each tied sound over: bookkeeping follows the NEW note (its endStep
        // schedules the eventual release); the voice + MIDI/AU note keep ringing.
        for tie in ties {
            active[tie.endID] = nil
            if let n = starting.first(where: { $0.id == tie.startID }) { active[n.id] = n }
        }
        for id in ending.keys where !tiedEnd.contains(id) { active[id] = nil }
        for (id, note) in ending where !tiedEnd.contains(id) {
            // Release this pitch on its voice only when no surviving note still holds
            // it ON THE SAME VOICE (two instruments can hold a shared pitch apart —
            // identity grouping covers the synth AND sampler routing).
            if !active.values.contains(where: { $0.pitch == note.pitch && sameVoice($0.role, note.role) }) {
                outputVoice(for: note.role)?.noteOff(pitch: note.pitch)
            }
            // MIDI mirrors the whole song regardless of the internal voice split.
            if !active.values.contains(where: { $0.pitch == note.pitch }) {
                midiOut?.noteOff(pitch: note.pitch)
            }
        }
        // The body's live 5D expression for this note (only when MIDI-out 5D mode is
        // armed and a fresh bio frame exists): coherence→Slide/brightness,
        // breath→Press, HRV→Glide micro-drift. nil → plain note-on (unchanged).
        let expression: MPEExpression? = {
            guard midiOut?.expressionEnabled == true, let bio = bus?.usableBio() else { return nil }
            // Press should SWELL through the breath, not saw-reset at the cycle wrap:
            // shape the 0…1 phase into a smooth hump (0 at the cycle ends, 1 mid-breath).
            let breathSwell = Float(sin(Double(bio.breathPhase) * .pi))
            // Both fields neutral-for-sound: `MPEExpression` declares its own no-body
            // state as slide 64 / bend 0 (`.neutral`), and the raw 0s contradict it in
            // opposite directions. Coherence 0 sends CC74 0 (darkest timbre). And
            // `drift = (hrv·2−1)·(bendCents/100)/range` puts hrv 0 at the negative end
            // of the drift's own range — not a pinned −1 bend, but −0.0104 normalized,
            // which the receiver expands over ±48 semitones to exactly −50 cents. So
            // every note left a quarter-tone flat for the whole pre-measurement window.
            return MPEExpression.from(coherence: bio.coherenceForSound,
                                      breathDepth: breathSwell,
                                      hrvNormalized: bio.hrvForSound)
        }()
        // Tied notes are already carried in `active` and their sound keeps ringing —
        // only genuinely new notes fire an attack. The lane mix scales every attack;
        // a muted lane fires none, but `active` bookkeeping stays intact so releases
        // (note-offs are harmless when nothing played) and un-mute stay consistent.
        let laneGain = max(0, min(2, mixGain))
        let laneAudible = laneGain > 0.001
        for note in starting where !tiedStart.contains(note.id) {
            // A5 bio-per-note EXPRESSION: coherence + breath scale this note's velocity
            // (identity when the note has no expression depth or no body → v unchanged).
            // Timing/brightness are modelled too but not yet wired (sub-tick clock W2 /
            // per-note filter input pending). Clamp is preserved.
            let exp = Self.noteExpression(note, loopPass: operatorLoopPass, seed: Self.operatorSeed,
                                          coherence: operatorCoherence, breath: operatorBreath)
            let v = min(1, note.velocity * laneGain * exp.velocityScale)
            if laneAudible { outputVoice(for: note.role)?.noteOn(pitch: note.pitch, velocity: v) }
            if laneAudible {
                // #58 S6: a note's fixed MPE overrides win per dimension over the
                // body's live 5D; unset dimensions fall through. Same 5D-armed gate
                // as before — with 5D off nothing is sent (behaviour-preserving).
                let noteExpr = midiOut?.expressionEnabled == true
                    ? MPEExpression.merging(bio: expression, override: note.mpe)
                    : nil
                midiOut?.noteOn(pitch: note.pitch, velocity: v, expression: noteExpr)
            }
            active[note.id] = note
        }

        // Felt sub (the "Vibration" dimension): reconcile the mono sub-bass to the
        // LOWEST sounding note an octave down, every tick, from the now-updated
        // `active` set. Stateful + symmetric so a re-seed/register shift can never
        // leave a stranded wrong-pitch sub (the old per-tick bassCeiling gate could).
        // The sub voice octave-folds into its felt band, so the pitch class is kept.
        // S2-W2-6: skip the poly DOUBLING sub when a kind voice is the instrument —
        // a drum kit must not also drive the felt sub, and a sub-bass lane already
        // IS the sub (its notes play through kindVoice at pitch, not octave-doubled).
        // ONE materialisation per tick, shared with the MusicalFrame publish below — that
        // publish is unconditional, so the array is built either way and a second copy here
        // bought nothing.
        let activeNotes = Array(active.values)
        let desiredSub = Self.feltSubPitch(forActive: activeNotes,
                                           laneAudible: laneAudible,
                                           hasKindVoice: kindVoice != nil)
        if desiredSub != currentSubPitch {
            if let p = desiredSub { subVoice?.noteOn(pitch: p) }   // monophonic → retunes
            else { subVoice?.allNotesOff() }
            currentSubPitch = desiredSub
        }

        // Publish the chord sounding NOW as a MusicalFrame so renderers can colour /
        // move with the music (DMMW backbone). 16 steps = 4 beats → beatPhase per beat.
        bus?.publish(musical: Self.musicalFrame(
            forActive: activeNotes,
            a4Hz: musicalA4Hz, rootPitchClass: musicalRootPitchClass,
            scaleName: musicalScaleName, tempoBPM: musicalTempoBPM,
            beatPhase: Double(step % 4) / 4.0))
    }

    /// Below this, a note is INAUDIBLE and must not anchor the felt sub.
    ///
    /// A Mix fader at 0 produces exactly 0, and the composer's humanizers clamp velocity to a
    /// 0.05 floor — but do NOT conclude from that pair that the band between is unreachable.
    /// It is: the fader is continuous on a 0.01 grid, so 0.05 × a 0.85 genre level × a 0.01
    /// fader bakes to 0.000425. (An earlier version of this comment claimed unreachability and
    /// was simply wrong — the humanizer clamp happens BEFORE the fader bake, not after.) The
    /// threshold is therefore justified by AUDIBILITY, not by a gap: 0.001 velocity is about
    /// −60 dB, which nobody follows with a sub, while the softest real note the composer writes
    /// sits 34 dB above it.
    ///
    /// This is a VELOCITY threshold. The 0.001 that recurs across `Timeline.swift`,
    /// `MultiRollFanout.swift` and line 992 above is the codebase's audibility gate for GAINS —
    /// same number, different dimension, deliberately not shared. A future change to either
    /// must not assume it moves the other.
    private static let audibleVelocityFloor: Float = 0.001

    /// Which pitch the felt sub (the "Vibration" dimension) should sound, or nil for none.
    /// Pure, so the three suppressions and the audibility rule are testable without a clock,
    /// an engine or a voice — the same treatment `musicalFrame` already gets below.
    ///
    /// It follows the lowest AUDIBLE note an octave down. "Audible" is the part that was
    /// missing: a Mix fader at 0 bakes velocity 0 into its notes, and those notes still enter
    /// `active` — correctly, because `active` is note bookkeeping (ties, releases, un-mute)
    /// and must not depend on level. Deriving the sub from it without checking level left the
    /// sub droning an octave below a note nobody could hear: a mute that half-muted.
    ///
    /// This only became perceptible with the velocity fix (#174/#177). Before it, the bio
    /// pulse overwrote every voice's amplitude, so a velocity-0 bass note sounded anyway and
    /// the sub matched something real. Making the faders honest is what surfaced this.
    ///
    /// The two pre-existing suppressions are unchanged: a muted LANE fires no attacks, so it
    /// must not drive the sub either; and a bound kind voice (a kit, or a sub-bass lane that
    /// already IS the sub, playing at pitch rather than octave-doubled) must not be doubled.
    ///
    /// TWO CONSEQUENCES, stated because they are behaviour, not implementation detail:
    /// · Muting the Bass fader does not remove the felt sub — it moves UP to the lowest note
    ///   still audible (the pad, usually). That is the existing design applied honestly, not a
    ///   new decision: this function has always followed the lowest sounding note whatever its
    ///   role, and already followed the pad whenever a passage had no bass at all.
    /// · With the bass muted the sub therefore retriggers on the pad's note boundaries instead
    ///   of resting under one long bass note, so the felt layer gets busier. That is a real,
    ///   audible difference and the first thing to listen for if muting Bass feels wrong.
    ///
    /// NaN velocity is excluded (`NaN > x` is false), where it previously anchored the sub.
    /// That is the better behaviour, but it is a change riding along: `Note.velocity`'s clamp
    /// still propagates NaN (task #176), so it is reachable rather than theoretical, and it is
    /// pinned by a test rather than left to be rediscovered.
    public static func feltSubPitch(forActive notes: [Note],
                                    laneAudible: Bool,
                                    hasKindVoice: Bool) -> Int? {
        guard laneAudible, !hasKindVoice else { return nil }
        return notes.lazy
            .filter { $0.velocity > audibleVelocityFloor }
            .map(\.pitch)
            .min()
            .map { $0 - 12 }
    }

    /// Build the live musical snapshot from the notes sounding now. Pure (testable):
    /// pitch → Hz at the given concert pitch, velocity → amplitude, master = the
    /// summed velocities (clamped) so "how much is sounding" tracks the chord density.
    public static func musicalFrame(forActive notes: [Note], a4Hz: Double,
                                    rootPitchClass: Int, scaleName: String,
                                    tempoBPM: Double, beatPhase: Double) -> MusicalFrame {
        let mnotes = notes.map { n -> MusicalNote in
            let hz = a4Hz * pow(2.0, Double(n.pitch - 69) / 12.0)
            return MusicalNote(frequencyHz: hz, amplitude: Double(n.velocity))
        }
        let master = notes.isEmpty ? 0 : Swift.min(1.0, notes.reduce(0.0) { $0 + Double($1.velocity) })
        return MusicalFrame(notes: mnotes, rootPitchClass: rootPitchClass,
                            scaleName: scaleName, tempoBPM: tempoBPM,
                            beatPhase: beatPhase, masterLevel: master)
    }

    // MARK: - Labels

    public func name(forPitch pitch: Int) -> String {
        // Typographic sharp (U+266F ♯), matching the primary Key picker
        // (WorkspaceView), TouchInstrumentView and TuningDetector — the piano-roll
        // pitch labels are display-only (Text(…)), so no identifier/parse depends on
        // an ASCII '#' here (unlike MusicalKey, whose name feeds a "#"→"s" transform).
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let octave = pitch / 12 - 1
        return "\(names[((pitch % 12) + 12) % 12])\(octave)"
    }

    public func isSharp(pitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
    }

    public func isC(pitch: Int) -> Bool { ((pitch % 12) + 12) % 12 == 0 }
}

/// Drag anchor captured at the start of a create/select gesture.
private struct RollDragAnchor { let pitch: Int; let startStep: Int }

/// What the in-flight canvas drag is doing, decided at touch-down by the pure
/// `RollHitTest`: an empty-grid drag creates/selects (the anchor), a drag that
/// began on a note body moves that note (#58 Slice 2), and a drag on a note's
/// right edge resizes its length (#58 Slice 3).
private enum RollDrag {
    case create(RollDragAnchor)
    /// The moving note's id, the cell first grabbed, and its original position —
    /// so the note follows the finger by a clamped delta, not by absolute cell.
    case move(id: UUID, grabPitch: Int, grabStep: Int, origPitch: Int, origStep: Int)
    /// The resizing note's id and its (fixed) start step — the right edge tracks
    /// the finger's step, so length = fingerStep − start + 1.
    case resize(id: UUID, origStart: Int)
    /// An empty-space drag became a marquee (rubber-band multi-select), anchored
    /// at the touch-down point (#58 Slice 5). Promoted from `.create` once the
    /// finger leaves the anchor cell, so a zero-distance tap still creates/selects.
    case marquee(startX: CGFloat, startY: CGFloat)
    /// Dragging a note that is part of the marquee group moves the WHOLE group by
    /// one shape-preserving delta (#58 Slice 5b). `orig` snapshots each selected
    /// note's position at grab time so the delta applies from the original layout.
    case groupMove(grabPitch: Int, grabStep: Int, orig: [Note])
}

/// The roll's ONE selection state (#58 Slice 5) — a single value so the illegal
/// "both a single note AND a group are selected" state is unrepresentable. A
/// marquee catching exactly one note collapses to `.single` (no editor-less
/// dead state); `.group` therefore always holds ≥2. Internal (not private) so
/// the collapse invariant is unit-tested.
enum RollSelection: Equatable {
    case none
    case single(UUID)
    case group(Set<UUID>)

    /// Build from a marquee hit-list, collapsing 0→none and 1→single.
    init(ids: [UUID]) {
        switch ids.count {
        case 0: self = .none
        case 1: self = .single(ids[0])
        default: self = .group(Set(ids))
        }
    }
    func contains(_ id: UUID) -> Bool {
        switch self {
        case .none: return false
        case .single(let s): return s == id
        case .group(let g): return g.contains(id)
        }
    }
    var single: UUID? { if case .single(let s) = self { return s }; return nil }
    var group: Set<UUID>? { if case .group(let g) = self { return g }; return nil }
}

/// Piano-roll editor surface. Presented from the Tools tab; drives the synth.
@MainActor
struct PianoRollView: View {

    let pattern: PatternEngine
    @Bindable var model: PianoRollModel
    /// H11: title + Done hook for the clip-scoped editor door. The defaults
    /// keep every existing call site (the live-take roll) unchanged. `onDone`
    /// runs on the explicit Done tap ONLY — a swipe-dismiss never calls it,
    /// which is the editor's cancel semantics (throwaway model, no write-back).
    var title: String = "Piano Roll"
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// H11 review HIGH: in clip-edit mode the throwaway model has no voice and
    /// is not clocked — the shared transport would sound the LIVE TAKE while
    /// the playhead sweeps the edited notes (an actively lying preview, and
    /// Play mid-song would stop the global transport). A silent editor is the
    /// honest v1: no Play button, no playhead. A wired preview voice is a
    /// later refinement.
    private var isClipScoped: Bool { onDone != nil }

    @State private var drawLength: Int = 1
    @State private var stepW: CGFloat = 26
    @State private var rowH: CGFloat = 22
    /// A1 per-note operator paint-lane: the SAME bottom lane paints either the
    /// note velocity (today) or its play CHANCE (Ableton-style), toggled by the
    /// lane's left label. No new always-on lane, no sheet — just a mode switch.
    @State private var laneMode: RollLaneMode = .velocity
    /// Adaptive fit (founder 2026-07-17 "Piano Roll passt immer noch nicht in den
    /// Bildschirm"): on first layout — and on rotation/size change — the cell
    /// metrics are FIT to the measured roll size (`RollFitMath`) so the whole
    /// 16-step bar is visible without blind horizontal scrolling. A manual
    /// zoom latches `userZoomed` and wins permanently; the Fit button clears
    /// the latch. Auto-fit NEVER fires mid-gesture — the drag/marquee/velocity
    /// paths convert finger→cell through stepW/rowH live, so shifting them
    /// under a finger would teleport notes (see `applyAutoFit` guards).
    @State private var userZoomed = false
    /// One-shot open-centering latch (founder 2026-07-17): scroll to the take's median pitch
    /// once the first real size is known, then never fight the user's scroll.
    @State private var didAutoCenter = false
    @State private var rollSize: CGSize = .zero
    /// Width of the last applied fit — a re-fit keys on WIDTH change only
    /// (open/rotation/split-view), so transient HEIGHT wobble (the selected-
    /// note inspector growing, keyboard) never visibly re-scales the grid.
    @State private var lastFitWidth: CGFloat = 0
    @State private var rollScroll = ScrollPosition(edge: .top)

    // Live drag state — one in-flight gesture (create-or-move), decided at touch-down.
    @State private var drag: RollDrag?
    /// The ONE selection (#58 Slice 5) — none / a single note / a group. Replaces
    /// the old `selectedID` + `selectedIDs` pair so the two can never disagree.
    @State private var selection: RollSelection = .none
    /// The live rubber-band rect while a marquee drag is in flight.
    @State private var marqueeRect: CGRect?
    /// One undo snapshot per velocity-paint gesture (reset on gesture end).
    @State private var velDragSnapshotTaken = false
    /// Scale-Lock (R1): ON = out-of-key rows dim in the grid and newly DRAWN
    /// notes snap to the take's key (the session Tonart — no dropdown). Only
    /// offered while `model.musicalKey` resolves; existing notes are never
    /// touched implicitly ("Snap to Scale" in the Ops menu is the explicit op).
    @State private var scaleLock = false
    /// R2 chord-stamp mode: when on, a tap on an empty cell drops a whole
    /// coherence-chosen, voice-led chord instead of one note. A plain `@State`
    /// bool read in the chrome — never a live-bio read (freeze law); the body's
    /// coherence is read once, inside the tap handler, by `model.stampChord`.
    @State private var chordStampMode = false
    /// Arp-stamp mode (Scaler #4): a tap arpeggiates the coherence-chosen chord with
    /// the live breath (`model.stampArp`). Mutually exclusive with chord mode; same
    /// freeze-safe one-shot bio read in the handler, never in the chrome.
    @State private var arpStampMode = false

    private let gutterW: CGFloat = 42
    private let minStepW: CGFloat = 16
    private let maxStepW: CGFloat = 56
    private let minRowH: CGFloat = 14
    private let maxRowH: CGFloat = 34
    /// Width of the right-edge grab zone (points) handed to `RollHitTest`. Resize
    /// lives there from Slice 3; today it just decides body-vs-edge classification.
    private let edgeSlopPt: Double = 9
    /// Height of the velocity paint-lane under the canvas (#58 Slice 4).
    private let laneH: CGFloat = 46
    /// Height of the beat ruler above the grid (founder 2026-07-17).
    private let rulerH: CGFloat = 16
    /// Auto-fit clamps TIGHTER than the manual zoom range: rows stay readable
    /// (≥16pt) without wasting height (≤26pt); ~2 octaves visible on a phone.
    private let fitMinRowH: CGFloat = 16
    private let fitMaxRowH: CGFloat = 26
    private let fitTargetRows = 25

    private var canvasW: CGFloat { stepW * CGFloat(PianoRollModel.stepCount) }
    private var canvasH: CGFloat { rowH * CGFloat(PianoRollModel.pitchCount) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                transport.padding(.horizontal, 16).padding(.top, 8)
                inspector.padding(.horizontal, 16)
                rollScroller
            }
            .background(EchoelTheme.bg)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // One dismiss control only — a single "Done". "Clear" used to sit in the
            // cancellation slot, where it read as "Cancel/back" but silently destroyed
            // every note; it now lives in the transport row as an explicit destructive
            // button (see `transport`).
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone?(); dismiss() }
                }
            }
        }
    }

    // MARK: - Transport + tools

    private var transport: some View {
        // H12 (founder v281 "links abgeschnitten"): this row's rigid minimum
        // (Play 44 + Picker 120 + EIGHT 34-pt buttons + 8×12 spacing ≈ 532 pt,
        // ~496 pt with the caller's padding) exceeds every iPhone width since
        // the #58 batch added undo/redo + the Q menu. An overflowing fixed
        // HStack widens the WHOLE roll VStack, which the sheet then clips
        // CENTERED — cutting the LEFT edge (Play button AND the pitch
        // gutter/key rail) off-screen. Horizontal scroll makes the row fit
        // any width; precedent: the single-note inspector (retro-review
        // MEDIUM-1). The Spacer collapses inside a scroll view — the row
        // packs leading, which is the correct reading order anyway.
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
            if !isClipScoped {
                Button {
                    if pattern.isPlaying {
                        // PAUSE, not the end of the session (#161). Order WITHIN this closure is
                        // irrelevant — `.onChange` runs on the next view-update pass, not inside
                        // `pattern.stop()`; the flag only has to be up before that pass. (An
                        // earlier comment here claimed the cascade reads it "in the same turn",
                        // which is not how SwiftUI delivers onChange.) See
                        // PianoRollModel.playbackOnlyStopRequested for the invariant that IS
                        // load-bearing: the consumer must read the flag unconditionally.
                        model.requestPlaybackOnlyStop()
                        EchoelCrashLog.breadcrumb("stop source: roll-pause")
                        pattern.stop(); model.allNotesOff()
                    } else {
                        // Any unconsumed flag is stale the moment we play again — drop it so
                        // it can never turn a LATER real stop into a pause.
                        _ = model.consumePlaybackOnlyStopRequest()
                        pattern.play(cause: .pianoRoll)
                    }
                } label: {
                    Image(systemName: pattern.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(pattern.isPlaying ? EchoelTheme.danger : EchoelTheme.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pattern.isPlaying ? "Pause" : "Play")
                // "without ending" rather than "keeps running": if the user is auditioning the
                // pattern with no take live, there is no session to keep, and the hint must not
                // claim one. Either way this button never ends a body session.
                .accessibilityHint(pattern.isPlaying
                                   ? "Stops the clock without ending the body session"
                                   : "Plays the pattern")
            }

            // Draw length (steps a new tapped note spans).
            Picker("Length", selection: $drawLength) {
                Text("1").tag(1); Text("2").tag(2); Text("4").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Spacer(minLength: 0)
            // Undo / Redo (#58 — every edit incl. a whole drag is one step back).
            zoomButton(systemName: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.35)
                .accessibilityLabel("Undo")
            zoomButton(systemName: "arrow.uturn.forward") { model.redo() }
                .disabled(!model.canRedo)
                .opacity(model.canRedo ? 1 : 0.35)
                .accessibilityLabel("Redo")
            // Quantize: selection if present, else the whole pattern. Explicit —
            // dragging never snaps recorded feel (tick-delta move law). #58 S7:
            // the Q door is a MENU of grids (straight + triplet); each entry
            // quantizes immediately. Menu content builds on open and reads only
            // edit-frequency state — no live bio in this subtree (freeze law).
            Menu {
                ForEach(QuantizeDivision.allCases, id: \.self) { division in
                    Button(division.rawValue) {
                        model.quantize(
                            ids: selection.group ?? selection.single.map { Set([$0]) } ?? [],
                            toTicks: division.ticks)
                    }
                }
            } label: {
                Text("Q")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quantize")
            .accessibilityHint("Choose a grid — straight or triplet — to snap the selected notes")
            opsMenu
            // R2: chord-stamp mode toggle. On → an empty-cell tap stamps a
            // coherence-chosen, voice-led chord. Same chrome, no new sheet.
            Button { chordStampMode.toggle(); if chordStampMode { arpStampMode = false } } label: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chordStampMode ? EchoelTheme.accent : EchoelTheme.text)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(chordStampMode ? EchoelTheme.accent : EchoelTheme.border,
                                      lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chord stamp")
            .accessibilityHint("When on, tapping an empty cell stamps a coherence-chosen chord")
            // Scaler #4: arp-stamp mode. On → a tap arpeggiates the coherence-chosen
            // chord with the live breath. Mutually exclusive with chord mode.
            Button { arpStampMode.toggle(); if arpStampMode { chordStampMode = false } } label: {
                Image(systemName: "wind")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(arpStampMode ? EchoelTheme.accent : EchoelTheme.text)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(arpStampMode ? EchoelTheme.accent : EchoelTheme.border,
                                      lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Breath arp stamp")
            .accessibilityHint("When on, tapping an empty cell arpeggiates a coherence-chosen chord with your breath")
            Button(role: .destructive) { model.clear(); selection = .none } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EchoelTheme.danger)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear all notes")
            zoomButton(systemName: "minus.magnifyingglass") { zoom(-1) }
            zoomButton(systemName: "plus.magnifyingglass") { zoom(1) }
            // Fit (founder 2026-07-17): clear the manual-zoom latch and re-fit the whole bar
            // to the current screen. Reuses the zoomButton chrome — no new
            // surface, no sheet.
            zoomButton(systemName: "arrow.down.right.and.arrow.up.left") {
                userZoomed = false
                applyAutoFit()
            }
            .accessibilityLabel("Fit to screen")
        }
        }
    }

    // MARK: - Ops menu (R1 — DAW selection tools + Echoel twist)

    /// The nine selection operators, menu order = musical workflow order.
    /// A plain enum keeps the Menu builder one small ForEach (type-check budget).
    private enum RollOpChoice: String, CaseIterable {
        case reverse = "Reverse"
        case invert = "Invert"
        case legato = "Legato"
        case doubleTime = "Double Time"
        case halfTime = "Half Time"
        case rampUp = "Ramp ↑"
        case rampDown = "Ramp ↓"
        case echo = "Echo"
        case bioHumanize = "Bio-Humanize"
    }

    /// The selection as an id-set for the ops/quantize paths — empty = whole
    /// pattern (the model treats empty ids as "all", like `quantize`).
    private var selectedIDs: Set<UUID> {
        selection.group ?? selection.single.map { Set([$0]) } ?? []
    }

    /// "Ops" — DAW-grade selection tools in the SAME chrome as the Q menu
    /// (a Menu on the transport row: NO new sheet, modal ceiling untouched).
    /// Ops act on the selection; with nothing selected, on ALL notes. Every
    /// entry is one undoable edit via the model (`applyOp` — Quantize's law).
    /// Content builds on open and reads only edit-frequency state — no live
    /// bio in this subtree (freeze law); Bio-Humanize reads its snapshot
    /// ONCE inside the tap handler, model-side.
    private var opsMenu: some View {
        Menu {
            ForEach(RollOpChoice.allCases, id: \.self) { op in
                Button(op.rawValue) { performOp(op) }
            }
            // Scale tools only when the take's key is known (session Tonart).
            if model.musicalKey != nil {
                Divider()
                Toggle("Scale Lock", isOn: $scaleLock)
                Button("Snap to Scale") { snapAllToScale() }
            }
        } label: {
            Text("Ops")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(scaleLock ? EchoelTheme.accent : EchoelTheme.text)
                .frame(width: 38, height: 34)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(scaleLock ? EchoelTheme.accent : EchoelTheme.border,
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note operations")
        .accessibilityHint("Reverse, invert, legato, time-scale, ramp, echo, bio-humanize the selected notes")
    }

    /// Route one Ops entry to its pure core (`RollNoteOps`) through the model's
    /// one undoable-edit door. Fixed, documented parameters — ramps span the
    /// musical 0.3…1.0 window, Echo = 2 decaying copies at 0.6.
    private func performOp(_ op: RollOpChoice) {
        let ids = selectedIDs
        let lo = PianoRollModel.lowPitch
        let hi = PianoRollModel.highPitch
        switch op {
        case .reverse:
            model.applyOp(ids: ids) { RollNoteOps.reverse($0) }
        case .invert:
            model.applyOp(ids: ids) { RollNoteOps.invertPitch($0, lowPitch: lo, highPitch: hi) }
        case .legato:
            model.applyOp(ids: ids) { RollNoteOps.legato($0) }
        case .doubleTime:
            model.applyOp(ids: ids) { RollNoteOps.doubleTime($0) }
        case .halfTime:
            model.applyOp(ids: ids) { RollNoteOps.halfTime($0) }
        case .rampUp:
            model.applyOp(ids: ids) { RollNoteOps.velocityRamp($0, from: 0.3, to: 1.0) }
        case .rampDown:
            model.applyOp(ids: ids) { RollNoteOps.velocityRamp($0, from: 1.0, to: 0.3) }
        case .echo:
            model.applyOp(ids: ids) { RollNoteOps.echo($0, times: 2, decay: 0.6) }
        case .bioHumanize:
            model.bioHumanize(ids: ids)
        }
    }

    /// Explicit "Snap to Scale" (selection, else all) — the only path that
    /// moves EXISTING notes into the key; Scale-Lock alone never rewrites.
    private func snapAllToScale() {
        guard let key = model.musicalKey else { return }
        model.applyOp(ids: selectedIDs) {
            RollNoteOps.snapToScale($0, key: key,
                                    lowPitch: PianoRollModel.lowPitch,
                                    highPitch: PianoRollModel.highPitch)
        }
    }

    /// Scale-Lock draw snap: the pitch a NEWLY DRAWN note actually lands on.
    /// Lock off / no key → the tapped pitch, unchanged.
    private func placedPitch(_ pitch: Int) -> Int {
        guard scaleLock, let key = model.musicalKey else { return pitch }
        return RollNoteOps.snapPitch(pitch, key: key,
                                     lowPitch: PianoRollModel.lowPitch,
                                     highPitch: PianoRollModel.highPitch)
    }

    private func zoomButton(systemName: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func zoom(_ direction: Int) {
        userZoomed = true   // manual zoom wins over auto-fit until the Fit button
        let f: CGFloat = direction > 0 ? 1.2 : 1 / 1.2
        stepW = min(max(stepW * f, minStepW), maxStepW)
        rowH = min(max(rowH * f, minRowH), maxRowH)
    }

    // MARK: - Adaptive fit (founder 2026-07-17)

    /// Fit the cell metrics to the measured roll size (`RollFitMath` — pure,
    /// tested). Skipped once the user zoomed manually, and NEVER while a
    /// gesture is in flight: canvas drag, marquee, and velocity paint all map
    /// finger→cell through the live stepW/rowH.
    private func applyAutoFit() {
        guard !userZoomed, drag == nil, marqueeRect == nil, !velDragSnapshotTaken,
              rollSize.width > 0, rollSize.height > 0 else { return }
        lastFitWidth = rollSize.width
        // stepCount is 16 (ONE bar) — the whole loop fits every iPhone width
        // at ≥ minStepW, so the fit target is always the full bar.
        stepW = CGFloat(RollFitMath.fittedStepW(
            availableWidth: Double(rollSize.width), gutterWidth: Double(gutterW),
            stepCount: PianoRollModel.stepCount,
            minStepW: Double(minStepW), maxStepW: Double(maxStepW)))
        rowH = CGFloat(RollFitMath.fittedRowH(
            availableHeight: Double(rollSize.height - rulerH - laneH),
            targetRows: fitTargetRows,
            minRowH: Double(fitMinRowH), maxRowH: Double(fitMaxRowH)))
    }

    /// One-shot on open: scroll vertically so the take's median pitch (empty
    /// clip → C4 region) sits mid-viewport — the roll never opens "irgendwo
    /// im Nichts" above or below the notes.
    private func autoCenterIfNeeded() {
        guard !didAutoCenter, rollSize.height > 0 else { return }
        didAutoCenter = true
        let pitch = min(max(RollFitMath.medianPitch(of: model.notes.map(\.pitch),
                                                    fallback: 60),
                            PianoRollModel.lowPitch), PianoRollModel.highPitch)
        let offset = RollFitMath.centeredOffsetY(
            targetCenterY: Double(rulerH + yForPitch(pitch) + rowH / 2),
            visibleHeight: Double(rollSize.height),
            contentHeight: Double(rulerH + canvasH + laneH))
        rollScroll.scrollTo(y: CGFloat(offset))
    }

    // MARK: - Selected-note inspector

    @ViewBuilder
    private var inspector: some View {
        if let ids = selection.group {
            // Marquee group selection: count + group-delete (#58 Slice 5).
            HStack(spacing: 12) {
                Text("\(ids.count) selected")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                Button {
                    model.remove(ids: ids); selection = .none
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EchoelTheme.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete selected notes")
            }
            .frame(height: 30)
        } else if let id = selection.single, let note = model.notes.first(where: { $0.id == id }) {
            // Retro-review MEDIUM-1: the rows' rigid minimum (value boxes are fixed
            // frames) exceeds a 390 pt iPhone — without this scroll the trailing
            // controls (delete / the MPE reset chip, the ONLY way back to
            // body-driven) clip off-screen. Precedent: the draw-length row below.
            ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text(model.name(forPitch: note.pitch))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 46, alignment: .leading)

                    EchoelValueField(label: "Len", value: Binding(
                        get: { Float(note.lengthSteps) },
                        set: { model.setLength(id: id, lengthSteps: Swift.max(1, Int($0.rounded()))) }
                    ), range: Float(1)...Float(PianoRollModel.stepCount), decimals: 0)

                    EchoelValueField(label: "Vel", value: Binding(
                        get: { note.velocity },
                        set: { model.setVelocity(id: id, $0) }
                    ), range: Float(0)...Float(1))

                    Button {
                        model.remove(id: id); selection = .none
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EchoelTheme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 30)

                // #58 S6b — the MPE station's door: fixed per-note 5D overrides.
                // A set dimension WINS over the live bio expression at trigger
                // time; the reset chip returns the note to fully body-driven.
                // Same captured-note Binding pattern as Len/Vel above.
                HStack(spacing: 12) {
                    Text("MPE")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EchoelTheme.dim)
                        .frame(width: 46, alignment: .leading)

                    EchoelValueField(label: "Bend", value: Binding(
                        get: { note.mpe?.bend ?? 0 },
                        set: { model.setMPE(id: id, bend: $0,
                                            slide: note.mpe?.slide, pressure: note.mpe?.pressure) }
                    ), range: Float(-1)...Float(1), decimals: 2, boxWidth: 64)

                    EchoelValueField(label: "Slide", value: Binding(
                        get: { note.mpe?.slide ?? 0.5 },
                        set: { model.setMPE(id: id, bend: note.mpe?.bend,
                                            slide: $0, pressure: note.mpe?.pressure) }
                    ), range: Float(0)...Float(1), decimals: 2, boxWidth: 64)

                    EchoelValueField(label: "Press", value: Binding(
                        get: { note.mpe?.pressure ?? 0 },
                        set: { model.setMPE(id: id, bend: note.mpe?.bend,
                                            slide: note.mpe?.slide, pressure: $0) }
                    ), range: Float(0)...Float(1), decimals: 2, boxWidth: 64)

                    if note.mpe != nil {
                        Button {
                            // One tap destroys up to three authored values — a
                            // discrete destructive edit, so it snapshots like
                            // remove/clear/quantize (scrub writes stay unsnapshotted).
                            model.snapshotForUndo()
                            model.setMPE(id: id, bend: nil, slide: nil, pressure: nil)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(EchoelTheme.dim)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear MPE overrides — note follows the body again")
                    }
                }
                .frame(height: 30)
            }
            }
        } else {
            Text("Tap to add · drag a note to move · its edge to resize · empty to select")
                .font(.caption2)
                .foregroundStyle(EchoelTheme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30)
        }
    }

    // MARK: - Scrollable roll (pinned pitch gutter + horizontally-scrolling canvas)

    private var rollScroller: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) { rulerCorner; gutter; velLabel }
                ScrollView(.horizontal, showsIndicators: true) {
                    // Ruler + canvas + velocity lane share ONE horizontal scroll
                    // so their time axes stay locked (no offset syncing).
                    VStack(spacing: 0) { beatRuler; canvas; velocityLane }
                }
            }
        }
        .scrollPosition($rollScroll)
        // Adaptive fit (founder 2026-07-17): measure the roll viewport (fires on first layout
        // AND on rotation/size change), fit the cell metrics, then center the
        // vertical scroll on the take ONCE. Size changes at layout frequency,
        // not bio/playhead frequency — no churn-law risk here.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            rollSize = newSize
            if abs(newSize.width - lastFitWidth) > 0.5 { applyAutoFit() }
            autoCenterIfNeeded()
        }
    }

    /// Top-left corner above the pitch gutter, so the beat ruler and the grid
    /// start on the same x. Carries the ruler's bottom border across.
    private var rulerCorner: some View {
        Color.clear
            .frame(width: gutterW, height: rulerH)
            .overlay(Rectangle().frame(height: 0.5)
                .foregroundStyle(EchoelTheme.border), alignment: .bottom)
    }

    /// Beat ruler above the grid (founder 2026-07-17): tick + number at every beat (4 steps),
    /// stronger tick on the bar edge. The roll is ONE 16-step bar — bar-in-clip
    /// context lives in the editor title ("… Bar k/N") — so the ruler numbers
    /// the bar-internal beats 1…4. Monospaced, thin, no decoration; scrolls
    /// horizontally WITH the canvas (same VStack in the one horizontal scroll).
    private var beatRuler: some View {
        Canvas { ctx, size in
            for step in stride(from: 0, through: PianoRollModel.stepCount, by: 4) {
                let x = CGFloat(step) * stepW
                let isBar = step % PianoRollModel.stepCount == 0
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - (isBar ? 8 : 5)))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(EchoelTheme.text.opacity(isBar ? 0.3 : 0.16)),
                   lineWidth: isBar ? 1.5 : 1)
                if step < PianoRollModel.stepCount {
                    ctx.draw(Text("\(step / 4 + 1)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EchoelTheme.dim),
                        at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                }
            }
        }
        .frame(width: canvasW, height: rulerH)
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundStyle(EchoelTheme.border), alignment: .bottom)
    }

    /// Which parameter the bottom paint-lane edits.
    enum RollLaneMode { case velocity, chance, occurrence
        var label: String {
            switch self { case .velocity: return "Vel"; case .chance: return "Cha"; case .occurrence: return "Occ" }
        }
        var next: RollLaneMode {
            switch self { case .velocity: return .chance; case .chance: return .occurrence; case .occurrence: return .velocity }
        }
        var accessibilityLabel: String {
            switch self {
            case .velocity: return "Velocity lane"
            case .chance: return "Note-chance lane"
            case .occurrence: return "Occurrence lane"
            }
        }
    }

    /// Left-margin label for the paint lane — TAP to cycle Vel → Cha → Occ. Aligned
    /// under the pitch gutter. A plain Button toggling `@State` (no sheet, no bio read).
    private var velLabel: some View {
        Button { laneMode = laneMode.next } label: {
            Text(laneMode.label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(laneMode == .velocity ? EchoelTheme.dim : EchoelTheme.accent)
                .frame(width: gutterW, height: laneH, alignment: .trailing)
                .padding(.trailing, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundStyle(EchoelTheme.border), alignment: .top)
        .accessibilityLabel(laneMode.accessibilityLabel)
        .accessibilityHint("Tap to cycle between velocity, note-chance and occurrence painting")
    }

    /// The paint-lane value [0…1] the lane draws for `note`, per `laneMode` (read
    /// straight off the note — O(1), no lookup in the render loop). Occurrence draws
    /// as the 1:N ratio (period 1 = full bar = every loop, 1:2 = half, …).
    private func laneValue(_ note: Note) -> CGFloat {
        switch laneMode {
        case .velocity:   return CGFloat(note.velocity)
        case .chance:     return CGFloat(note.operators?.chance ?? 1)
        case .occurrence: return CGFloat(1.0 / Double(note.operators?.occurrencePeriod ?? 1))
        }
    }

    /// Map a paint-lane unit [0…1] to an occurrence PERIOD (1…): the bar draws the
    /// 1:N ratio, so the inverse recovers N (top = 1:1 = every loop, half = 1:2, …).
    /// Clamped again by NoteOperators' init (periodRange). A unit at/near 0 → the
    /// sparsest period the range allows.
    static func occurrencePeriod(forUnit unit: Double) -> Int {
        guard unit > 0.02 else { return NoteOperators.periodRange.upperBound }
        return Int((1.0 / unit).rounded())
    }

    /// Paint-lane: one bar per note (height = the active parameter), drag vertically
    /// to set that parameter for the note under the finger (#58 Slice 4; A1 adds the
    /// chance mode). Reuses the pure `RollHitTest` laws + the existing setters; no bio
    /// read here, so no menu-freeze risk. Bars wear the note's physical tone colour.
    private var velocityLane: some View {
        Canvas { ctx, size in
            for note in model.notes {
                let x = CGFloat(note.startStep) * stepW
                let w = Swift.max(3, CGFloat(note.lengthSteps) * stepW - 2)
                let h = Swift.max(1, laneValue(note) * size.height)
                let rect = CGRect(x: x + 1, y: size.height - h, width: w, height: h)
                let selected = selection.contains(note.id)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                         with: .color(rowTint(note.pitch).opacity(selected ? 0.95 : 0.5)))
            }
        }
        .frame(width: canvasW, height: laneH)
        .background(EchoelTheme.bg)
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundStyle(EchoelTheme.border), alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: "vel")
        .gesture(velocityDrag)
    }

    private var velocityDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("vel"))
            .onChanged { value in
                let s = step(atX: value.location.x)
                guard let id = RollHitTest.noteToPaint(atStep: s, notes: model.notes) else { return }
                // ONE undo point per paint gesture (not per tick).
                if !velDragSnapshotTaken {
                    velDragSnapshotTaken = true
                    model.snapshotForUndo()
                }
                // Both parameters live in 0…1 → the same Y→unit map serves each.
                let unit = RollHitTest.velocity(forY: Double(value.location.y), laneHeight: Double(laneH))
                switch laneMode {
                case .velocity:   model.setVelocity(id: id, unit)
                case .chance:     model.setChance(id: id, Double(unit))
                case .occurrence: model.setOccurrence(id: id, Self.occurrencePeriod(forUnit: Double(unit)))
                }
                selection = .single(id)
            }
            .onEnded { _ in velDragSnapshotTaken = false }
    }

    private var gutter: some View {
        VStack(spacing: 0) {
            ForEach(rowsTopDown, id: \.self) { pitch in
                Text(model.isC(pitch: pitch) ? model.name(forPitch: pitch) : "")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.dim)
                    .frame(width: gutterW, height: rowH, alignment: .trailing)
                    .padding(.trailing, 3)
                    // Gutter carries the same physical row tint (very subtle) so the
                    // pitch ladder reads as ONE coloured raster with the canvas.
                    .background(rowTint(pitch)
                        .opacity(model.isSharp(pitch: pitch) ? 0.03 : 0.07))
                    .overlay(Rectangle().frame(height: 0.5)
                        .foregroundStyle(EchoelTheme.border), alignment: .bottom)
            }
        }
        .frame(width: gutterW)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            gridBackground
            ForEach(model.notes) { note in noteRect(note) }
            if let r = marqueeRect {
                Rectangle()
                    .fill(EchoelTheme.accent.opacity(0.12))
                    .overlay(Rectangle().strokeBorder(EchoelTheme.accent, lineWidth: 1))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .allowsHitTesting(false)
            }
            // isPlaying = start/stop-frequency (fine here); currentStep churns at
            // step rate and is confined to the leaf (retro-review HIGH-1).
            if pattern.isPlaying && !isClipScoped {
                RollPlayheadView(pattern: pattern, stepW: stepW, canvasH: canvasH)
            }
        }
        .frame(width: canvasW, height: canvasH, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "roll")
        .gesture(canvasDrag)
    }

    private var gridBackground: some View {
        Canvas { ctx, size in
            // Row stripes in each pitch's PHYSICAL tone colour (CIE fit of the actual
            // sounding frequency at the take's Kammerton — founder 2026-07-12: "Je nach
            // Kammerton müsste sich auch die Farbe des Notenrasters ändern"). Sharps
            // stay darker; the root row is anchored a touch stronger, like the touch
            // fretboard marks its tonal home. Subtle alphas — legible numbers first.
            let root = model.musicalRootPitchClass
            // Scale-Lock (R1): out-of-key rows recede — a subtle dark veil over
            // the row stripe (no glow/neon; the numbers/notes stay legible).
            // `musicalKey` reads @ObservationIgnored context — no churn.
            let lockedKey = scaleLock ? model.musicalKey : nil
            for (i, pitch) in rowsTopDown.enumerated() {
                let y = CGFloat(i) * rowH
                let rect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                let isRoot = root >= 0 && ((pitch % 12) + 12) % 12 == root
                let alpha = model.isSharp(pitch: pitch) ? 0.045 : (isRoot ? 0.13 : 0.085)
                ctx.fill(Path(rect), with: .color(rowTint(pitch).opacity(alpha)))
                if let key = lockedKey, !key.contains(pitch) {
                    ctx.fill(Path(rect), with: .color(Color.black.opacity(0.22)))
                }
                if model.isC(pitch: pitch) {
                    ctx.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                               with: .color(EchoelTheme.border), lineWidth: 0.5)
                }
            }
            // Grid verticals — three-level hierarchy Bar > Beat > Step (founder 2026-07-17):
            // the bar edges frame the loop strongest, beats carry the pulse,
            // steps recede. Subtle opacities only — no decoration.
            for step in 0...PianoRollModel.stepCount {
                let x = CGFloat(step) * stepW
                let isBar = step % PianoRollModel.stepCount == 0
                let isBeat = step % 4 == 0
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(EchoelTheme.text.opacity(isBar ? 0.28 : (isBeat ? 0.15 : 0.06))),
                           lineWidth: isBar ? 1.5 : (isBeat ? 1 : 0.5))
            }
        }
        .frame(width: canvasW, height: canvasH)
    }

    private func noteRect(_ note: Note) -> some View {
        let x = CGFloat(note.startStep) * stepW
        let w = CGFloat(note.lengthSteps) * stepW
        let y = yForPitch(note.pitch)
        let selected = selection.contains(note.id)
        // A note block wears ITS OWN physical tone colour (same CIE mapping as the
        // grid rows and the touch fretboard), velocity → opacity as before.
        let tint = rowTint(note.pitch)
        return RoundedRectangle(cornerRadius: 3)
            .fill(tint.opacity(0.35 + 0.6 * Double(note.velocity)))
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(selected ? EchoelTheme.text : tint, lineWidth: selected ? 1.5 : 0.75))
            .frame(width: max(4, w - 2), height: max(6, rowH - 2))
            .offset(x: x + 1, y: y + 1)
    }

    // (Retro-review HIGH-1) The playhead lives in its OWN leaf struct: reading
    // `pattern.currentStep` (16th-note rate, 8–16 Hz while playing) in a computed
    // var of THIS body registered the whole roll — transport row included — as a
    // step-rate observer, and every rebuild tore down the open Q Menu popover
    // (freeze law 10.76.41/50: a computed var is NOT an observation boundary).
    private struct RollPlayheadView: View {
        let pattern: PatternEngine
        let stepW: CGFloat
        let canvasH: CGFloat
        var body: some View {
            Rectangle()
                .fill(EchoelTheme.text.opacity(0.5))
                .frame(width: 1.5, height: canvasH)
                .offset(x: CGFloat(pattern.currentStep) * stepW)
        }
    }

    // MARK: - Geometry helpers

    /// Pitches from highest (top) to lowest (bottom) for top-down layout.
    private var rowsTopDown: [Int] {
        Array(stride(from: PianoRollModel.highPitch, through: PianoRollModel.lowPitch, by: -1))
    }

    /// The row's physical tone colour at the take's ACTUAL concert pitch — the
    /// same CIE tone→light mapping as the touch fretboard, so changing the
    /// Kammerton recolours this grid identically ("Je nach Kammerton … die Farbe
    /// des Notenrasters"). `musicalA4Hz` is @ObservationIgnored on the model
    /// (no churn); the grid redraws on present/zoom/edit, which is when it matters.
    private func rowTint(_ pitch: Int) -> Color {
        let hz = model.musicalA4Hz * pow(2.0, (Double(pitch) - 69.0) / 12.0)
        let c = SpectralColor.displayComponents(forToneHz: hz)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    private func yForPitch(_ pitch: Int) -> CGFloat {
        CGFloat(PianoRollModel.highPitch - pitch) * rowH
    }

    private func pitch(atY y: CGFloat) -> Int {
        let row = Int(y / rowH)
        return min(max(PianoRollModel.highPitch - row, PianoRollModel.lowPitch), PianoRollModel.highPitch)
    }

    private func step(atX x: CGFloat) -> Int {
        min(max(Int(x / stepW), 0), PianoRollModel.stepCount - 1)
    }

    // MARK: - Gesture

    private var canvasDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("roll"))
            .onChanged { value in
                if drag == nil {
                    // Decide the gesture ONCE, at touch-down, from the pure hit-test.
                    switch RollHitTest.classify(
                        x: Double(value.startLocation.x), y: Double(value.startLocation.y),
                        notes: model.notes,
                        stepW: Double(stepW), rowH: Double(rowH),
                        highPitch: PianoRollModel.highPitch, lowPitch: PianoRollModel.lowPitch,
                        stepCount: PianoRollModel.stepCount, edgeSlop: edgeSlopPt
                    ) {
                    case let .body(id):
                        if let g = selection.group, g.contains(id) {
                            // Grabbing a note in the marquee group → move all of them.
                            model.snapshotForUndo()   // ONE undo point per gesture
                            drag = .groupMove(grabPitch: pitch(atY: value.startLocation.y),
                                              grabStep: step(atX: value.startLocation.x),
                                              orig: model.notes.filter { g.contains($0.id) })
                        } else if let n = model.notes.first(where: { $0.id == id }) {
                            model.snapshotForUndo()
                            drag = .move(id: id,
                                         grabPitch: pitch(atY: value.startLocation.y),
                                         grabStep: step(atX: value.startLocation.x),
                                         origPitch: n.pitch, origStep: n.startStep)
                            selection = .single(id)   // single-select replaces any group
                        }
                    case let .rightEdge(id):
                        if let n = model.notes.first(where: { $0.id == id }) {
                            model.snapshotForUndo()
                            drag = .resize(id: id, origStart: n.startStep)
                            selection = .single(id)
                        }
                    case let .empty(pitch, step):
                        drag = .create(RollDragAnchor(pitch: pitch, startStep: step))
                    }
                }
                // An empty-space drag that leaves the anchor cell becomes a marquee
                // (rubber-band multi-select). A zero-distance tap never leaves the
                // cell, so `.create` survives to onEnded → the tap path is intact.
                if case let .create(anchor) = drag,
                   step(atX: value.location.x) != anchor.startStep
                    || pitch(atY: value.location.y) != anchor.pitch {
                    drag = .marquee(startX: value.startLocation.x, startY: value.startLocation.y)
                }
                // Live-follow so the note tracks the finger (move) / the edge tracks
                // the finger's step (resize) / the marquee tracks the drag (select).
                switch drag {
                case let .move(id, grabPitch, grabStep, origPitch, origStep):
                    let dPitch = pitch(atY: value.location.y) - grabPitch
                    let dStep = step(atX: value.location.x) - grabStep
                    model.move(id: id, toPitch: origPitch + dPitch, toStartStep: origStep + dStep)
                case let .resize(id, origStart):
                    let len = RollHitTest.resizedLengthSteps(
                        fingerStep: step(atX: value.location.x), startStep: origStart)
                    model.setLength(id: id, lengthSteps: len)
                case let .groupMove(grabPitch, grabStep, orig):
                    // One shape-preserving delta for the whole group, applied from
                    // each note's ORIGINAL position so the layout can't drift.
                    let d = RollHitTest.clampedGroupDelta(
                        dPitch: pitch(atY: value.location.y) - grabPitch,
                        dStep: step(atX: value.location.x) - grabStep, selected: orig,
                        lowPitch: PianoRollModel.lowPitch, highPitch: PianoRollModel.highPitch,
                        stepCount: PianoRollModel.stepCount)
                    for n in orig {
                        model.move(id: n.id, toPitch: n.pitch + d.dPitch,
                                   toStartStep: n.startStep + d.dStep)
                    }
                case let .marquee(sx, sy):
                    marqueeRect = CGRect(x: min(sx, value.location.x), y: min(sy, value.location.y),
                                         width: abs(value.location.x - sx),
                                         height: abs(value.location.y - sy))
                    // 0 notes → .none, 1 → .single (no editor-less dead state),
                    // ≥2 → .group. The whole selection is this one value.
                    selection = RollSelection(ids: RollHitTest.notesInRect(
                        x0: Double(sx), y0: Double(sy),
                        x1: Double(value.location.x), y1: Double(value.location.y),
                        notes: model.notes, stepW: Double(stepW), rowH: Double(rowH),
                        highPitch: PianoRollModel.highPitch))
                case .create, .none:
                    break
                }
            }
            .onEnded { _ in
                defer { drag = nil; marqueeRect = nil }
                switch drag {
                case let .create(anchor):
                    // A tap (the finger never left the anchor cell — any movement
                    // would have promoted this to a marquee). Select the note there,
                    // or create one — a fresh single selection replaces any group.
                    if let existing = model.note(atPitch: anchor.pitch, step: anchor.startStep) {
                        selection = .single(existing.id)
                        // H12: kind-true tap preview — CLIP editor only. The
                        // live roll's sound is the transport; auditioning it
                        // here would double-trigger while playing.
                        if isClipScoped {
                            model.audition(pitch: existing.pitch,
                                           velocity: existing.velocity, role: existing.role)
                        }
                    } else if arpStampMode {
                        // Scaler #4: the tap arpeggiates the coherence-chosen chord with
                        // the live breath, filling the bar from here. ONE undo step;
                        // select + audition the arp's first (lowest-tick) note.
                        let arp = model.stampArp(atPitch: placedPitch(anchor.pitch),
                                                 startStep: anchor.startStep)
                        if let first = arp.min(by: { $0.startTick < $1.startTick }) {
                            selection = .single(first.id)
                            if isClipScoped {
                                model.audition(pitch: first.pitch,
                                               velocity: first.velocity, role: first.role)
                            }
                        }
                    } else if chordStampMode {
                        // R2 chord stamp: the same tap drops a whole coherence-chosen,
                        // voice-led chord (rooted at the scale-locked tapped row). ONE
                        // undo step; select + audition the chord's lowest voice.
                        let chord = model.stampChord(atPitch: placedPitch(anchor.pitch),
                                                     startStep: anchor.startStep,
                                                     lengthSteps: drawLength)
                        if let root = chord.min(by: { $0.pitch < $1.pitch }) {
                            selection = .single(root.id)
                            if isClipScoped {
                                model.audition(pitch: root.pitch,
                                               velocity: root.velocity, role: root.role)
                            }
                        }
                    } else {
                        // Scale-Lock (R1): a newly DRAWN note snaps to the
                        // nearest in-key pitch (lock off = tapped pitch).
                        let note = model.add(pitch: placedPitch(anchor.pitch),
                                             startStep: anchor.startStep,
                                             lengthSteps: drawLength)
                        selection = .single(note.id)
                        if isClipScoped {
                            model.audition(pitch: note.pitch,
                                           velocity: note.velocity, role: note.role)
                        }
                    }
                case .move, .resize, .groupMove, .marquee, .none:
                    break   // move/resize already set .single; groupMove/marquee
                            // applied live; the rubber-band rect is cleared in `defer`.
                }
            }
    }
}
#endif
