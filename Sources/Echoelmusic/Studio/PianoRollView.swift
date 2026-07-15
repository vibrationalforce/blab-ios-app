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
    /// Optional live MIDI/MPE OUT — mirrors every note the synth plays to the
    /// virtual "Echoelmusic" source so a DAW records the body's take in real time.
    /// nil or disabled = silent (no-op); never affects the audio path.
    @ObservationIgnored private weak var midiOut: MIDIOutput?
    /// Optional hosted AUv3 instrument — when the user has loaded one (Tools ▸
    /// Plugins), the live composition plays it too (host-MIDI), so the plugin is
    /// driven by the song, not just the preview keyboard. nil/none = no-op.
    @ObservationIgnored private weak var auHost: AUv3Host?
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

    public init() {}

    // MARK: - Editing

    /// The note (if any) sounding at `pitch` during `step`.
    public func note(atPitch pitch: Int, step: Int) -> Note? {
        notes.first { $0.pitch == pitch && $0.covers(step: step) }
    }

    /// Add a note, clamping its length so it never crosses the loop boundary.
    @discardableResult
    public func add(pitch: Int, startStep: Int, lengthSteps: Int = 1, velocity: Float = 0.8) -> Note {
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

    public func remove(id: UUID) { notes.removeAll { $0.id == id } }

    public func setLength(id: UUID, lengthSteps: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let maxLen = max(1, Self.stepCount - notes[i].startStep)
        notes[i].lengthSteps = min(max(1, lengthSteps), maxLen)
    }

    public func setVelocity(id: UUID, _ velocity: Float) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].velocity = min(max(velocity, 0), 1)
    }

    public func clear() {
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
            arrangementBars = bars
            notes = bars[0]
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
                      auHost: AUv3Host? = nil, automation: AutomationPlayer? = nil,
                      timeline: TimelineRegionPlayer? = nil) {
        self.voice = voice
        self.lead = lead
        self.subVoice = subVoice
        self.midiOut = midiOut
        self.arrangement = arrangement
        self.timeline = timeline
        self.automation = automation
        self.bus = bus
        self.auHost = auHost
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
        for note in active.values { outputVoice(for: note.role)?.noteOff(pitch: note.pitch) }
        active.removeAll()
        currentSubPitch = nil
        voice?.allNotesOff()
        lead?.allNotesOff()
        subVoice?.allNotesOff()
        midiOut?.allNotesOff()
        auHost?.allNotesOff()
    }

    /// The instrument voice a note plays through, by role (multitimbral routing):
    /// `.lead` → the dedicated lead voice when present, else the main voice;
    /// everything else → the main voice. All warm synth (no real instruments).
    private func outputVoice(for role: NoteRole) -> (any NoteVoice)? {
        return (role == .lead) ? (lead ?? voice) : voice
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
        // When a hosted plugin is set to REPLACE Echoel's voice, the song drives only
        // the plugin (no doubling). Note-offs always fire (harmless if it wasn't
        // playing) so toggling mid-play never leaves the built-in voice stuck.
        let suppressBuiltIn = auHost?.suppressesBuiltInVoice ?? false
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
        let operatorCoherence = bus?.usableBio().map { Double($0.coherence) }
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
            // MIDI/AU mirror the whole song regardless of the internal voice split.
            if !active.values.contains(where: { $0.pitch == note.pitch }) {
                midiOut?.noteOff(pitch: note.pitch)
                auHost?.noteOff(midiByte(note.pitch))
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
            return MPEExpression.from(coherence: bio.coherence,
                                      breathDepth: breathSwell,
                                      hrvNormalized: bio.hrvNormalized)
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
            if !suppressBuiltIn, laneAudible { outputVoice(for: note.role)?.noteOn(pitch: note.pitch, velocity: v) }
            if laneAudible {
                midiOut?.noteOn(pitch: note.pitch, velocity: v, expression: expression)
                auHost?.noteOn(midiByte(note.pitch), velocity: velocityByte(v))
            }
            active[note.id] = note
        }

        // Felt sub (the "Vibration" dimension): reconcile the mono sub-bass to the
        // LOWEST sounding note an octave down, every tick, from the now-updated
        // `active` set. Stateful + symmetric so a re-seed/register shift can never
        // leave a stranded wrong-pitch sub (the old per-tick bassCeiling gate could).
        // The sub voice octave-folds into its felt band, so the pitch class is kept.
        let desiredSub = (suppressBuiltIn || !laneAudible)
            ? nil : active.values.map(\.pitch).min().map { $0 - 12 }
        if desiredSub != currentSubPitch {
            if let p = desiredSub { subVoice?.noteOn(pitch: p) }   // monophonic → retunes
            else { subVoice?.allNotesOff() }
            currentSubPitch = desiredSub
        }

        // Publish the chord sounding NOW as a MusicalFrame so renderers can colour /
        // move with the music (DMMW backbone). 16 steps = 4 beats → beatPhase per beat.
        bus?.publish(musical: Self.musicalFrame(
            forActive: Array(active.values),
            a4Hz: musicalA4Hz, rootPitchClass: musicalRootPitchClass,
            scaleName: musicalScaleName, tempoBPM: musicalTempoBPM,
            beatPhase: Double(step % 4) / 4.0))
    }

    /// Clamp a roll pitch into the valid MIDI range for host-MIDI to the AU.
    private func midiByte(_ pitch: Int) -> UInt8 { UInt8(min(127, max(0, pitch))) }
    /// Map a 0…1 velocity to a 1…127 MIDI velocity (0 would read as note-off).
    private func velocityByte(_ v: Float) -> UInt8 { UInt8(min(127, max(1, Int(v * 127)))) }

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
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
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

    @State private var selectedID: UUID?
    @State private var drawLength: Int = 1
    @State private var stepW: CGFloat = 26
    @State private var rowH: CGFloat = 22

    // Live drag state
    @State private var anchor: RollDragAnchor?
    @State private var dragStep: Int?

    private let gutterW: CGFloat = 42
    private let minStepW: CGFloat = 16
    private let maxStepW: CGFloat = 56
    private let minRowH: CGFloat = 14
    private let maxRowH: CGFloat = 34

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
        HStack(spacing: 12) {
            Button {
                if pattern.isPlaying { pattern.stop(); model.allNotesOff() }
                else { pattern.play() }
            } label: {
                Image(systemName: pattern.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 36)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(pattern.isPlaying ? EchoelTheme.danger : EchoelTheme.accent))
            }
            .buttonStyle(.plain)

            // Draw length (steps a new tapped note spans).
            Picker("Length", selection: $drawLength) {
                Text("1").tag(1); Text("2").tag(2); Text("4").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Spacer(minLength: 0)
            Button(role: .destructive) { model.clear(); selectedID = nil } label: {
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
        }
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
        let f: CGFloat = direction > 0 ? 1.2 : 1 / 1.2
        stepW = min(max(stepW * f, minStepW), maxStepW)
        rowH = min(max(rowH * f, minRowH), maxRowH)
    }

    // MARK: - Selected-note inspector

    @ViewBuilder
    private var inspector: some View {
        if let id = selectedID, let note = model.notes.first(where: { $0.id == id }) {
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
                    model.remove(id: id); selectedID = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EchoelTheme.danger)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 30)
        } else {
            Text("Tap to add a note · drag to stretch · tap a note to edit")
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
                gutter
                ScrollView(.horizontal, showsIndicators: true) {
                    canvas
                }
            }
        }
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
            if pattern.isPlaying { playhead }
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
            for (i, pitch) in rowsTopDown.enumerated() {
                let y = CGFloat(i) * rowH
                let rect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                let isRoot = root >= 0 && ((pitch % 12) + 12) % 12 == root
                let alpha = model.isSharp(pitch: pitch) ? 0.045 : (isRoot ? 0.13 : 0.085)
                ctx.fill(Path(rect), with: .color(rowTint(pitch).opacity(alpha)))
                if model.isC(pitch: pitch) {
                    ctx.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                               with: .color(EchoelTheme.border), lineWidth: 0.5)
                }
            }
            // Bar/beat lines every 4 steps.
            for step in 0...PianoRollModel.stepCount {
                let x = CGFloat(step) * stepW
                let strong = step % 4 == 0
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(EchoelTheme.text.opacity(strong ? 0.16 : 0.06)),
                           lineWidth: strong ? 1 : 0.5)
            }
        }
        .frame(width: canvasW, height: canvasH)
    }

    private func noteRect(_ note: Note) -> some View {
        let x = CGFloat(note.startStep) * stepW
        let w = CGFloat(note.lengthSteps) * stepW
        let y = yForPitch(note.pitch)
        let selected = note.id == selectedID
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

    private var playhead: some View {
        Rectangle()
            .fill(EchoelTheme.text.opacity(0.5))
            .frame(width: 1.5, height: canvasH)
            .offset(x: CGFloat(pattern.currentStep) * stepW)
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
                if anchor == nil {
                    anchor = RollDragAnchor(
                        pitch: pitch(atY: value.startLocation.y),
                        startStep: step(atX: value.startLocation.x)
                    )
                }
                dragStep = step(atX: value.location.x)
            }
            .onEnded { value in
                defer { anchor = nil; dragStep = nil }
                guard let anchor else { return }
                let endStep = step(atX: value.location.x)
                let s0 = min(anchor.startStep, endStep)
                let s1 = max(anchor.startStep, endStep)
                let span = s1 - s0 + 1
                if span <= 1 {
                    if let existing = model.note(atPitch: anchor.pitch, step: s0) {
                        selectedID = existing.id
                    } else {
                        let note = model.add(pitch: anchor.pitch, startStep: s0,
                                             lengthSteps: drawLength)
                        selectedID = note.id
                    }
                } else {
                    let note = model.add(pitch: anchor.pitch, startStep: s0, lengthSteps: span)
                    selectedID = note.id
                }
            }
    }
}
#endif
