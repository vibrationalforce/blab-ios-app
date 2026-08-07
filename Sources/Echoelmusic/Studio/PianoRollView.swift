#if canImport(SwiftUI)
import SwiftUI
import Foundation

// PianoRollView.swift
// Echoel — the polyphonic melodic NOTE ENGINE. The editor it was named after is gone.
//
// ⭐ READ THE NAME AS HISTORY, NOT AS CONTENTS (#475). The founder removed the note
// editor on 2026-07-26 ("Pianoroll soll raus"); #178 took its door, and #475 deleted the
// 987-line `PianoRollView` struct itself, which by then had no caller of ANY kind — the
// last one was a test reaching for its static `occurrencePeriod(forUnit:)`, and #470
// hoisted that into `RollHitTest`. The file keeps its name because renaming it is a
// separate, reviewable move; what it CONTAINS is `PianoRollModel`.
//
// ⛔ AND `PianoRollModel` IS LOAD-BEARING — this is the sentence that has to survive.
// It is the note engine AND the `MusicalFrame` publisher: its tick handler publishes the
// chord sounding NOW onto the bus, and `EchoelmusicApp` installs that handler once at
// launch (`pianoRoll.start(pattern:…)`), view or no view. Visual, light (Art-Net/sACN)
// and space (ADM-OSC) all hang off that publish. Deleting "the piano roll file" would
// take the entire output stage with it. CLAUDE.md says the same thing in its own words:
// *"`PianoRollView` = the editor, removed. `PianoRollModel` = the note engine +
// `MusicalFrame` publisher, KEPT" — that one is genuinely load-bearing.*
//
// ⚠️ WHAT THE DELETION LEFT BEHIND, said plainly rather than discovered later. SIX
// `PianoRollModel` members had the view as their only caller and are now callerless:
// `audition(pitch:velocity:role:)` · `stampChord` · `stampArp` ·
// `bioHumanize` · `isSharp(pitch:)` · `isC(pitch:)`. They are NOT removed here, for
// #470's reason — changing what a deletion commit deletes is how a scoped claim stops
// being true. Retiring them is its own pass.
//
// ⛔ AND HOW THAT COUNT WAS MADE MATTERS MORE THAN THE COUNT — twice over, because the
// first version got it wrong in BOTH directions. A `\b<name>\b` sweep over-counted:
// `audition` alone showed 37 hits across `Sources`, all of them unrelated prose about
// `BeatPlayer`'s sample-audition path, and `musicalKey` showed six that are a LOCAL
// VARIABLE in `NoteNamingTests`. Each member was therefore re-checked on its literal
// CALL form (`audition(pitch:`, `stampChord(`, …), and the one remaining `isSharp(` hit
// turned out to be a test METHOD NAME
// (`BioHapticsTests.testBreathPulse_lowCoherence_isSharp`), not a caller. A name-shaped
// grep answers a question about NAMES; "does anyone call this" is a different question.
//
// ⛔ AND THEN THAT SAME DISCIPLINE UNDER-COUNTED ON THE ONE MEMBER IT DOES NOT FIT.
// The list said SEVEN and included `pitchCount`. `pitchCount` is a stored `let`, not a
// func — it has no "call form" — and it is READ, one line below its own declaration, by
// `public static var highPitch: Int { lowPitch + pitchCount - 1 }`. `highPitch` is very
// much alive: `move`, `stampChord`, `stampArp` and `foldToBar` all read it, and
// `foldToBar` is on the LIVE MIDI-import path (`EchoelStudioView.importMIDI`), plus
// `RollHitTest`, `RollNoteOps` and three test files. Found by the #475 reviewer, verified
// here with `git grep -c highPitch`. **The lesson is not "count more carefully" — it is
// that a rule tuned against over-counting produces false negatives on the members it was
// not designed for. A property is not a function; measure it as a property.**
//
// ⚠️ AND THE ORPHANING REACHES THREE NEIGHBOURING FILES, which is the part a
// file-local header would have missed. `Studio/RollHitTest.swift` and
// `Studio/RollFitMath.swift` were the view's pure geometry, and both now have **zero
// production callers**. `Studio/RollNoteOps.swift` is the exception and survives with
// one: `PianoRollModel` calls `RollNoteOps.stableSeed(for:)` at `bioHumanize`.
// ⛔ A GREP RECIPE STOOD HERE AND THIS COMMIT FALSIFIED IT IN THE ACT OF WRITING IT:
// `git grep -n "RollHitTest\.\|RollFitMath\." -- Sources` "returns only their own
// declarations". It returns four lines, and not ONE of them is a declaration — two are
// these very header lines, two are the `// RollFitMath.swift` filename banners. A
// declaration reads `public enum RollHitTest {` and does not contain the dot. Exactly the
// `EchoelModalBank` trap CLAUDE.md records — a note that QUOTES a grep ages faster than
// one that states a fact, because the note corrupts its own evidence — and here it did
// not survive its own commit. The FACT is stated above; to re-measure it, exclude prose:
// `git grep -n "RollHitTest\.\|RollFitMath\." -- Sources | grep -v '://'`.
// None of the three is deleted here, and the reason is not caution:
//   · `RollHitTest` holds `occurrencePeriod(forUnit:)`, the law #470 hoisted OUT of the
//     deleted view precisely so a deletion could not take it by accident, and
//     `Tests/CISmoke/TheUnitToPeriodLawSurvivesTheViewTests` pins it in the BLOCKING
//     bundle. #475 is the deletion that hoist was insuring against; removing the core in
//     the same breath would spend the insurance on the accident it prevented.
//   · Deleting files is a founder-visible slice, not a side effect of deleting a struct.
// ⚠️ And `RollNoteOps`' one surviving caller is itself ONE HOP FROM DEAD: `stableSeed` is
// called from `bioHumanize`, which the list above records as callerless. So the natural
// next cleanup — "retire the callerless members" — silently orphans a third file. Said
// here so that pass starts knowing it, instead of discovering it afterwards (#472).
// `enum RollSelection` at the bottom of THIS file is in the same position: nothing in
// `Sources/` reads it since the view went, and it stays because `Tests/EchoelmusicTests/
// NoteTests.swift` makes eight assertions on it — the `WaveformReducer` shape (#132
// Slice 5), test-only with the reason written down rather than inferred. (⛔ "nine" stood
// here and in CLAUDE.md; nine is `grep -c RollSelection`, which counts the
// `func testRollSelection_…` name as well. Counting the assertions gives eight.)
//
// The model itself is unchanged: notes have a pitch, a start step, a length in steps
// (legato/sustain across boundaries) and a per-note velocity; note-offs fire at note END,
// scheduled on the ONE shared PatternEngine clock via `pattern.onTick`.

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
// sub-bass instrument. SubBassVoice needs only AVFoundation, which this SwiftUI
// file already requires (it stores a SubBassVoice).
// ⛔ `extension LaneDrumKitVoice: NoteVoice {}` stood here behind an Accelerate guard and
// went with #167. It was the last thing keeping the kit type reachable from the roll; the
// `.drums` LANE KIND still exists (persisted rawValue) and now routes to a poly voice.
extension SubBassVoice: NoteVoice {}

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
    /// ⛔ THIS CARRIED A "⚠ DORMANT since 2026-07-26" NOTE UNTIL THE #475 REVIEW, AND IT WAS
    /// FALSE — the exact defect CLAUDE.md warns about, in the exact shape it warns about it.
    /// The note said "the only producer is `PianoRollView.transport` … this flag can no longer
    /// be raised". BOTH halves were wrong by the time #475 read them: `PianoRollView` does not
    /// exist any more, so it produces nothing, and the flag has had a LIVE producer since
    /// #234/#179 — `WorkspaceView`'s `PlaybackToggleButton` calls `requestPlaybackOnlyStop()`
    /// on the ⏸ path. `EchoelStudioView`'s consumer says so in its own words ("That instant is
    /// now"); this declaration never got the memo. A note naming a DELETED producer as the
    /// current one is worse than no note: the next session reads "cannot be raised" and treats
    /// the ordering invariant below as dead weight it may reorder freely.
    ///
    /// ⚠️ SO READ THE INVARIANT AS LIVE, not as archaeology. The mechanism is not kept "in case
    /// a surface returns" — a surface HAS returned. Retiring it (#180) would mean removing a
    /// working pause.
    ///
    /// The app has ONE Stop by law: whenever the shared transport stops from anywhere, the
    /// Studio ends the bio session too, so nothing is left armed behind a stopped clock. That
    /// is right for the labelled Stop — and punishing for a PAUSE, which a user presses to
    /// drop the music without dropping the body. It tore down the camera and the pulse lock, so
    /// resuming cost another finger-on-lens re-lock (~19 s, #415).
    /// ⚠️ THE ORIGINAL MOTIVATING CASE WAS THE ROLL'S OWN TRANSPORT BUTTON — "the Notes editor
    /// was unusable during a live take (ship gate 2)". That editor is gone (#178/#475), so the
    /// SENTENCE is history; the LAW is not. The cost it names is what the chrome ⏸ would pay
    /// today if this flag stopped working.
    ///
    /// The producer therefore RAISES this flag before it stops the transport, and the Studio's
    /// stop cascade CONSUMES it: flag up ⇒ pause playback and keep the body session; flag down
    /// ⇒ the full stop, unchanged. Today's producer is `WorkspaceView.PlaybackToggleButton`.
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

    /// Swap the arrangement's NOTES for the same notes at new LEVELS, without ever
    /// cutting something that is sounding (#174 — the mixer re-bake).
    ///
    /// `loadArrangement(_:playing:)` cannot be reused for this, and the reason is a trap
    /// worth naming: its `guard bars.count > 1` sends the SINGLE-bar case down `load(_:)`,
    /// which opens with `allNotesOff()`. Re-balancing through it would therefore chop
    /// every sounding note each time a fader settled, which is a worse artefact than the
    /// bug being fixed. (The default loop length is EIGHT bars — `StudioDefaultKeys` — so
    /// one bar is the edge case; an earlier version of this comment called it the common
    /// one, which is exactly backwards and would misdirect the next reader.)
    ///
    /// The two branches deliberately differ, because the EXPORT reads a different array
    /// in each case and #174 is ultimately about the export telling the truth:
    /// · multi-bar — `arrangementBars` is both the cycle and `arrangementForExport()`'s
    ///   source, so writing it makes the export correct at once; the sounding bar swaps
    ///   at the next boundary through `pendingNotes` (consumed by `trigger` at
    ///   `step == 0`), leaving the current bar's notes to release naturally.
    /// · single bar — `arrangementForExport()` returns `(notes, 1)`, so `notes` IS the
    ///   arrangement and is written directly. Safe mid-bar: a note already started keeps
    ///   its voice (releases come from `active`, not from `notes`) and one whose
    ///   `startStep` has passed cannot retrigger, so only notes still to come in this bar
    ///   pick up the new level — which is what a level control should do. Staging it
    ///   instead would have left an export taken within the same bar on the old levels —
    ///   and would have LOST the re-bake entirely on "move fader → Stop within the bar",
    ///   because `pattern.onStop` clears `pendingNotes` and only refreshes `notes` when
    ///   `arrangementBars.count > 1`, which this branch deliberately leaves empty.
    ///
    /// While PLAYING nothing here calls `allNotesOff` and `playedBars` keeps counting.
    /// Stopped, the ordinary load path is delegated to unchanged — which does reset
    /// `playedBars` and does apply `IntroAttenuation`, but ONLY on its multi-bar branch;
    /// a stopped single-bar re-bake goes through `load(_:)` and gets neither. Both are
    /// exactly what a stopped `generate()` already does, so this introduces no new
    /// behaviour — but an earlier version of this comment claimed the opposite on both
    /// counts, so it is spelled out rather than summarised.
    ///
    /// `arrangementPhaseOffset` is deliberately NOT touched: `loadArrangement` zeroes it
    /// because it INSTALLS an arrangement, whereas this method promises the same notes at
    /// new levels, and zeroing a region-installed rotation would change which bar plays
    /// next — a compositional side effect in a level-only call.
    public func rebakeArrangement(_ bars: [[Note]], playing: Bool) {
        guard let firstBar = bars.first else { return }
        guard playing else { loadArrangement(bars, playing: false); return }
        if bars.count > 1 {
            arrangementBars = bars
            // The offset is CARRIED, not zeroed (see above), so the staged index must
            // include it — this is the exact expression `trigger` uses to stage the next
            // bar, which is what keeps the re-bake level-only.
            pendingNotes = bars[(playedBars + arrangementPhaseOffset) % bars.count]
        } else {
            // A one-bar arrangement is the classic loop: `arrangementBars` stays empty so
            // `trigger`'s cycling branch is untouched, exactly as `load(_:)` leaves it.
            arrangementBars = []
            notes = firstBar
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
    /// tap/draw feedback. (H12 originally read "an EchoelDrums clip previews the
    /// KIT, not the poly synth" — there is no kit any more since #167, so a
    /// `.drums` lane previews the poly voice like every other kind.)
    /// Routed via `outputVoice(for:)`, so a session with no
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

    #if DEBUG
    /// TEST SEAM (Debug-only; same `#if DEBUG` + `internal` intent as
    /// `PolySynthVoice.lastTuningForTests`, though that one is a stored property): the felt
    /// sub and the published `MusicalFrame` must apply the SAME audibility rule. Exposing
    /// the threshold lets a test pin that against the real constant instead of retyping
    /// `0.001` — a second literal is exactly how the two would silently drift apart.
    internal static var audibleVelocityFloorForTests: Float { audibleVelocityFloor }
    #endif

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
    /// TWO CONSEQUENCES, stated because they are behaviour, not implementation detail.
    /// ⛔ REWRITTEN 2026-07-27 — the previous text said "muting the Bass fader does NOT remove
    /// the felt sub, it moves UP to the pad". That was true only for the ~two days between the
    /// velocity fix (#174/#177) and the Bass fader reaching the sub at all. `SubBassVoice`
    /// now carries the mixer's Bass position as its own `mixLevel`, so Bass at 0 SILENCES the
    /// felt sub outright. Left as it stood, this block would have taught the next session the
    /// opposite of what the code does — on the one function you consult to understand the sub.
    /// · Muting the Bass fader now removes the felt sub. Which is what "mute the bass" means.
    /// · The PITCH selection is unchanged and still role-blind: the sub follows the lowest
    ///   audible note whatever its role, so in a passage with no bass at all it doubles the
    ///   PAD — and the BASS fader scales and mutes it there. That cross-role coupling is real
    ///   and is the first thing to check if the Bass fader ever seems to affect the pad.
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
    ///
    /// INAUDIBLE NOTES ARE EXCLUDED, by the same `audibleVelocityFloor` the felt sub uses.
    /// This frame answers "what is SOUNDING", and a note nobody can hear is not sounding.
    /// `active` deliberately still holds them — that map is note bookkeeping (ties,
    /// releases, un-mute) and must not depend on level — but publishing them was a real
    /// device symptom: log 2472 (v10.79.355) shows `mfNotes=5 mfAmp=0.000 level=0.00`,
    /// five active notes every one at ≈0, reachable exactly as `audibleVelocityFloor`'s
    /// doc describes (0.05 humanizer floor × 0.85 genre level × 0.01 fader = 0.000425).
    ///
    /// WHY HERE AND NOT IN EACH RENDERER — and what the gate actually was. The Art-Net,
    /// sACN and ADM-OSC senders were NOT ungated: all three ask `isSounding` before they
    /// map music to a fixture. Their gate was INSUFFICIENT, which is a different and more
    /// interesting fault: `isSounding` is `!notes.isEmpty && masterLevel > 0`, and five
    /// notes at 0.000425 sum to `masterLevel` 0.002 — greater than zero, so a chord at
    /// about −54 dBFS read as live. Worse, `SpectralColor.physicalColor` normalises by
    /// summed weight, so amplitude magnitude does not dim the result at all: the two
    /// header tiles rendered a FULLY SATURATED chord colour off those velocities. Two
    /// further consumers (`HeaderMonitors` tile + light colour) have no floor of their
    /// own. Fixing it per-renderer would mean three more constants and three more chances
    /// to drift; one filter at the publisher is strictly less surface.
    ///
    /// THE DOWNSTREAM CHANGE TO KNOW ABOUT (do not read this as "nothing else happens"):
    /// with `isSounding` now false, the three senders leave the music source. Where they go
    /// depends on `BioEgressPolicy.allowsEgress` — with bio egress allowed they fall through
    /// to the BIO colour; without it, Art-Net and sACN HOLD their last channels and ADM-OSC
    /// stops sending. That is their documented intent and it is not a new mechanism (a
    /// genuine rest has always done exactly this at every phrase boundary), but it is a
    /// real, visible change on a lighting rig and it is the part that wants a device look.
    ///
    /// The handover RAMPS, it does not snap: Art-Net and sACN slew the dimmer AND the R/G/B
    /// channels, both through `FlashGuard.slewedDimmer` (`ArtNetSender.applySlewedColour`).
    /// ⛔ An earlier version of this line claimed colour was NOT slewed. It is — and that
    /// claim was the one a session would act on, either by re-adding a slew that exists or
    /// by refusing to ship for fear of a hue snap that cannot happen.
    ///
    /// `MetalBioView` is deliberately NOT cited as the victim here. It is the one consumer
    /// already immune — its own 0.02/0.01 amplitude floor sends an all-silent chord to the
    /// release branch — and in log 2472 its frame branch never even ran (`touch=1`, so a
    /// finger drove the colour). Its floor stays load-bearing for the band between 0.001
    /// and 0.02 and must not be deleted as redundant on the strength of this filter.
    public static func musicalFrame(forActive notes: [Note], a4Hz: Double,
                                    rootPitchClass: Int, scaleName: String,
                                    tempoBPM: Double, beatPhase: Double) -> MusicalFrame {
        let audible = notes.filter { $0.velocity > audibleVelocityFloor }
        let mnotes = audible.map { n -> MusicalNote in
            let hz = a4Hz * pow(2.0, Double(n.pitch - 69) / 12.0)
            return MusicalNote(frequencyHz: hz, amplitude: Double(n.velocity))
        }
        let master = audible.isEmpty ? 0 : Swift.min(1.0, audible.reduce(0.0) { $0 + Double($1.velocity) })
        return MusicalFrame(notes: mnotes, rootPitchClass: rootPitchClass,
                            scaleName: scaleName, tempoBPM: tempoBPM,
                            beatPhase: beatPhase, masterLevel: master,
                            inaudibleNoteCount: notes.count - audible.count)
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

#endif
