#if canImport(SwiftUI)
import SwiftUI

// ArrangeTimelineView.swift
// Echoel — the beat-grid Arrange surface (approved plan, Stage 1c): bar ruler,
// horizontal lanes, tick-positioned regions, pinch zoom, live playhead. This is
// the foundation the WAV waveform (Stage 2) and touch editing (Stage 3) land on;
// playback stays with the existing bar-granular ArrangementPlayer for now.
//
// Stage 3a (One-View convergence, founder 2026-07-09/-10: "alles läuft über die
// Spuren"): track headers are DOORS — tap a lane head for its editor (MIDI →
// Piano Roll, Audio → audio editor), rename, delete-if-empty; "+" adds tracks.
// This view owns ONE .sheet + ONE rename alert — safe here (the ~18-modal
// metadata limit is EchoelStudioView's chain, this view had none). Never drive
// both true at once (each menu action sets exactly one).
//
// Render safety: this body reads ONLY low-frequency state (document edits, zoom).
// The moving playhead lives in its own leaf struct (TimelinePlayhead), exactly
// like ArrangementPlayhead — the ~8 Hz Transport read never churns the grid.

@MainActor
struct ArrangeTimelineView: View {
    @Environment(TimelineStore.self) private var timeline
    @Environment(EngineBus.self) private var bus
    @Environment(ArrangementStore.self) private var legacySong
    @Environment(ClipStore.self) private var clips
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll
    // (TimelineRegionPlayer env removed with the "Play timeline" button — the chrome
    //  transport ▶ owns arrangement playback now; founder 2026-07-15 "einer reicht".)
    @Environment(RecordController.self) private var recordController
    // Transport, for the "Split at playhead" razor. Read ONLY in the button's tap
    // action (never in `body`), so `position` (~8 Hz) creates no observation on the
    // toolbar body — the menu-freeze rule stays honored (like the playhead leaf).
    @Environment(Transport.self) private var transport
    // Per-lane sound distribution (founder 2026-07-12: "Teile das sinnvoll in
    // die Spuren auf. Externe AUv3 inbegriffen") — the lane door now opens the
    // lane's OWN sound: the melodic-bus insert (live-applied to the roll's
    // voices) and the AUv3 host. Same stores/voices the Studio menus use — one
    // source of truth, just reachable where the work happens.
    @Environment(TrackFXStore.self) private var trackFX
    @Environment(PolySynthVoice.self) private var synth
    // Adaptive head column: fits the narrowest supported iPhone (360 pt) and lets iPad
    // breathe, replacing the old fixed 140. Read by BOTH the ruler spacer and the lane
    // head so the two columns stay pixel-aligned. Size class changes only on rotation /
    // device — NOT a 10 Hz @Observable, so the menu-freeze law is untouched.
    @Environment(\.horizontalSizeClass) private var hSize
    private var headWidth: CGFloat { hSize == .regular ? 184 : Self.labelWidth }
    /// The rack, used for THREE low-frequency reads, none in `body`:
    ///  · H12 kind-true audition — `kits`/`subs` (the per-lane kit/sub voices the
    ///    clip editor previews through), read only inside door-open handlers.
    ///  · per-track automation gating — `capacity`, to offer per-track targets on
    ///    the SAME rack capacity the playback dispatch uses (placebo law — never
    ///    offer an overflow lane a target that would no-op).
    /// `capacity` is a `let` and `kits`/`subs` are @ObservationIgnored, so this
    /// registers no 10 Hz churn (freeze law).
    @Environment(LaneVoiceRack.self) private var laneVoiceRack
    @Environment(\.leadSynth) private var leadSynth
    // U3b: the AUv3 host, so a track head can SHOW its plugin assignment and
    // record the currently-loaded plugin onto the lane. `loaded`/`loadedEffects`
    // are low-frequency (change only on load/unload) — safe to read in the menu.
    @Environment(AUv3Host.self) private var auHost

    /// The ONE editor sheet this surface owns (U1). A single `.sheet(item:)` over
    /// an enum — a lane head opens `.lane`, a long-pressed region opens `.region`.
    /// Never a second `.sheet` (metadata-SIGSEGV law); EchoelValueField's own keypad
    /// sheet is a SUBVIEW sheet and does not count against this one slot.
    @State private var activeModal: ArrangeModal?
    /// Rename flow: which lane + the draft name (alert, not a second sheet).
    @State private var renameLaneID: UUID?
    @State private var renameText = ""

    /// Multi-select (clip game C3 — founder: "mehrere Clips markiert → combine"). While
    /// `isSelecting`, a TAP on a clip toggles it into the selection instead of
    /// auditioning; Combine/Delete act on the whole set. Tap-frequency state — no churn.
    @State private var isSelecting = false
    @State private var selectedRegions: Set<UUID> = []

    /// T1 inline automation (founder 2026-07-17 "Automations Sektionen … in der
    /// Timeline direkt"): which tracks show their fold-out automation row, and
    /// each track's picked target parameter. Session UI state (like selection);
    /// the CURVES persist in the timeline document. Toggle-frequency — no churn.
    @State private var automationOpen: Set<UUID> = []
    @State private var automationTarget: [UUID: String] = [:]

    /// Performance mode (founder 2026-07-17 "Play Button auf den Clips und
    /// Performance Mode"). OFF = today's arrange behavior byte-identical (no launch
    /// glyphs, region move/trim untouched). ON = every MIDI clip shows a launch
    /// play/stop glyph (`ClipLaunchGlyph`) and that region's move/trim gestures are
    /// suspended so a tap always LAUNCHES instead of scrubbing the clip. Session
    /// UI state (like `isSelecting`) — toggle-frequency, no churn (freeze law).
    @State private var performanceMode = false
    /// The launch quantize grid a clip snaps to when armed in Performance mode
    /// (default Bar — musical, forgiving). Enum picker (EchoelValueField is the
    /// one control for NUMBERS; a grid is an enum, so a compact Menu is correct).
    @State private var launchQuantize: LaunchQuantize = .bar

    /// Zoom: screen points per quarter-note beat (Stage 3 couples snap to this).
    @State private var pointsPerBeat: CGFloat = 24
    @GestureState private var pinch: CGFloat = 1
    /// Snap resolution — persisted; default 1/16 (research: snap ON by default).
    @AppStorage("timeline.snap") private var snapRaw = SnapResolution.sixteenth.rawValue
    /// H12: the active loop window sizes a fresh user MIDI clip's region — same
    /// key/default as the semantic owner EchoelStudioView.loopBars (pattern:
    /// LaneCompositionSection / FloatingVisualWindow).
    @AppStorage(StudioDefaultKeys.loopBars.key) private var loopBars: LoopBarLength = StudioDefaultKeys.loopBars.value

    // (Region trim state moved INTO RegionBlockView — each clip owns its own live
    //  resize @State so a drag re-renders only that clip, not the whole timeline.)

    // fileprivate: the extracted RegionBlockView leaf (same file) reuses laneHeight.
    fileprivate static let laneHeight: CGFloat = 56
    // iPhone floor for the head column. Was a FIXED 140 — but the mix strip's honest
    // footprint (record·M·S·gain·auto with the gain field's real 54 pt) is ~162, so a
    // 140 frame overflowed and (being centre-aligned) shifted the whole head LEFT until
    // "MIDI 1" clipped off the left screen edge. 162 = the honest floor; `headWidth`
    // makes it size-class adaptive so iPad breathes. Read via `headWidth`, never directly.
    private static let labelWidth: CGFloat = 162
    private static let rulerHeight: CGFloat = 24

    /// One identity colour per content kind — DAW convention, drawn from the
    /// EXISTING palette (Uncodixfy: no new hues): MIDI = instrument green,
    /// audio = material amber, everything without an engine = muted. Used for
    /// the lane's leading stripe and its regions, so a lane and its content
    /// read as one system across the whole Hackbrett.
    fileprivate static func kindTint(_ kind: ClipKind?) -> Color {
        switch kind {
        case .midi:  return EchoelTheme.accent
        case .audio: return EchoelTheme.warning
        default:     return EchoelTheme.dim
        }
    }

    private var ppb: CGFloat { min(96, max(8, pointsPerBeat * pinch)) }
    private var snap: SnapResolution { SnapResolution(rawValue: snapRaw) ?? .sixteenth }

    /// Bars drawn: song end + breathing room, at least 8.
    private var barCount: Int {
        max(8, timeline.document.endTick / TimelineTime.ticksPerBar + 2)
    }
    private var gridWidth: CGFloat {
        CGFloat(barCount * TimelineTime.beatsPerBar) * ppb
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            // SILENCED-INSTRUMENT GUARD (#22, founder "alles ist still"): the generative
            // melody plays through the roll-slot lane (first MIDI lane); a mute / foreign
            // solo / 0-fader there silences it with no visible reason. When the instrument
            // is armed but that lane is inaudible, say so and offer a one-tap fix — the
            // core instrument must never be silently trapped. Both reads are low-frequency
            // (instrument start/stop · lane edits), so this is freeze-safe in the body.
            if bus.instrumentRunning, let reason = timeline.document.rollSlotSilenceReason {
                rollSilencedBanner(reason)
            }
            Divider().overlay(EchoelTheme.border)
            // Vertical scroll carries BOTH columns (labels + grid) so any number
            // of tracks fits the fixed timeline height of the one main view; the
            // grid keeps its own horizontal scroll (independent axes).
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    laneLabels
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(EchoelTheme.border).frame(width: 1)
                        }
                    ScrollView(.horizontal, showsIndicators: true) {
                        grid
                    }
                }
            }
        }
        .background(EchoelTheme.bg)
        .task { timeline.bootstrapIfNeeded(sections: legacySong.sections) }
        // K2a lane→engine binding, GAIN: moved to the app level (review HIGH,
        // heal cycle): this view unmounts when the timeline is folded
        // (persisted @AppStorage), so an onChange here missed every mixer
        // edit/heal while folded — the roll stayed silent (or stale-loud)
        // despite a healed document. The ONE writer of pianoRoll.mixGain is
        // now the always-mounted onDocumentChanged hook in EchoelmusicApp.
        // B2 lane→engine binding, pan: the roll-slot lane's stereo position
        // drives BOTH melodic voices (pad/harmony + lead) at the mixer — an
        // honest engine path (AVAudioMixing on the source nodes). Sub-bass
        // stays center by design (mono-bass practice); drums are a separate bus.
        .onChange(of: timeline.document.rollSlotPan, initial: true) { _, pan in
            synth.setPan(pan)
            leadSynth?.setPan(pan)
        }
        // Per-instrument Transpose, primary lane (founder 2026-07-14): the roll-slot
        // lane's semitone shift drives BOTH melodic voices live, so an edit is heard
        // right away (not only at the next loop). Secondary lanes apply on load via the
        // player's slotTransposeSink. Document-level read → fires only on an edit, never
        // at 10 Hz (freeze rule safe, like the pan onChange above).
        .onChange(of: timeline.document.rollSlotTranspose, initial: true) { _, semis in
            synth.setTranspose(semitones: semis)
            leadSynth?.setTranspose(semitones: semis)
        }
        // Per-instrument Detune, primary lane (founder 2026-07-14 "transpose detune"):
        // the fine-cents twin of transpose — same live-push discipline (document-level
        // read, fires on edit not at 10 Hz; freeze-rule safe).
        .onChange(of: timeline.document.rollSlotDetune, initial: true) { _, cents in
            synth.setDetune(cents: cents)
            leadSynth?.setDetune(cents: cents)
        }
        // Per-instrument Oktaver, primary lane (founder 2026-07-14 "transpose detune
        // und Oktaver"): octave-double both melodic voices live per the lane's
        // direction — same live-push discipline (document-level read, fires on edit
        // not at 10 Hz; freeze-rule safe). Mix stays the engine's 0.5 default.
        .onChange(of: timeline.document.rollSlotOctave, initial: true) { _, direction in
            synth.setOctaver(direction: direction)
            leadSynth?.setOctaver(direction: direction)
        }
        // H13: transport start cuts any running region audition — the lane sink is
        // about to sound the same lane and a leftover audition would double-sound
        // (the same hazard auditionWindow's nil-while-playing guards at tap time).
        // Start/stop-frequency read (never 10 Hz) — freeze-rule safe.
        .onChange(of: beatPlayer.pattern.isPlaying) { _, playing in
            if playing { beatPlayer.stopAudition() }
        }
        // Review F1: this view is the audition's ONLY kill switch, but it is
        // conditionally mounted (timelineExpanded chevron) — collapsing the
        // timeline mid-audition would leave a minutes-long segment streaming
        // with no watcher and no UI to stop it (and the onChange above would
        // no longer fire on transport start → double-sound). Unmount = stop.
        .onDisappear { beatPlayer.stopAudition() }
        .gesture(magnify)
        .sheet(item: $activeModal, onDismiss: {
            // H11 review MEDIUM (dismiss race): tapping Edit on ANOTHER region
            // during the outgoing sheet's dismissal animation builds a fresh
            // session and re-presents — the OLD sheet's onDismiss then fires
            // and must not nil the fresh session (the fallback would silently
            // reopen the shared roll: the exact pre-H11 bug).
            if activeModal == nil {
                clipEdit = nil
                // #23 S2: persist the lane patch ONCE on a genuine close, only if
                // it changed from the seed. Guarded by `activeModal == nil` like
                // clipEdit above (a re-present leaves patchEdit for the new
                // editor's onAppear to overwrite — no stray persist/clear).
                if let e = patchEdit, e.latest != e.seed {
                    timeline.setLanePatch(e.laneID, patch: e.latest)
                }
                patchEdit = nil
            }
        }) { modal in
            // AnyView per the app-wide sheet pattern (EchoelStudioView) — keeps
            // the host body's generic signature flat (metadata rule).
            AnyView(modalEditor(modal).echoelSheetPanel())
        }
        .alert("Rename track", isPresented: renameAlertShown) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renameLaneID {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { timeline.renameLane(id: id, to: trimmed) }
                }
                renameLaneID = nil
            }
            Button("Cancel", role: .cancel) { renameLaneID = nil }
        }
    }

    // MARK: - Track doors (Stage 3a) + region editor (U1)

    /// The one modal the surface can present: a lane's editor (from its head) or a
    /// region's editor (long-press). Both resolve to the same kind-based editors —
    /// one sheet slot, two entry points.
    enum ArrangeModal: Identifiable {
        case lane(TimelineLane)
        case region(TimelineRegion)
        /// Per-lane sound: the melodic-bus insert editor (roll voices).
        case laneFX(TimelineLane)
        /// The AUv3 host browser — external instruments/effects, ON the track
        /// (founder: "Externe AUv3 inbegriffen"). Same env-driven view as the
        /// menu-bar Plugins chip; this is a second DOOR, not a second system.
        case plugins
        /// E2a (founder: "alles vertikal auf die Spuren"): the synth patch
        /// editor, on the MIDI lane. Re-doors PatchEditorView (its studio
        /// sheet trigger died with the Tools grid — deep audit 2026-07-12).
        /// #23 S2: carries the LANE, so the editor seeds from + persists to
        /// that lane's own `patch` (was global-only before).
        case patch(TimelineLane)
        /// E2a: automation lanes, on the track. Re-doors AutomationView.
        case automation
        /// Automation-in-Spur L1/S2b: DRAW automation INTO a specific clip (the
        /// region's clip), clip-relative. Reuses THIS one sheet slot — never a
        /// second `.sheet` (metadata law).
        case clipAutomation(TimelineRegion)
        /// The Immersive Stage — the Touch surface that places every track in space.
        case spatial
        /// EchoelBodyVibe — the bio-generative INSTRUMENT surface, opened from a
        /// track whose built-in instrument is `.bioVoice` (founder 2026-07-20:
        /// "Man wählt das ganz normal als Instrument aus"). Reuses THIS one sheet
        /// slot — no new `.sheet` (metadata law).
        case bodyVibe(TimelineLane)
        var id: String {
            switch self {
            case .lane(let l):   return "lane-\(l.id)"
            case .region(let r): return "region-\(r.id)"
            case .laneFX(let l): return "lanefx-\(l.id)"
            case .plugins:       return "plugins"
            case .patch(let l):  return "patch-\(l.id)"
            case .automation:    return "automation"
            case .clipAutomation(let r): return "clipautomation-\(r.id)"
            case .spatial:       return "spatial"
            case .bodyVibe(let l): return "bodyvibe-\(l.id)"
            }
        }
    }

    /// H11: one clip-edit session — the throwaway roll model (decoupled from
    /// the shared live-take roll by construction) plus the splice coordinates.
    /// Built BEFORE the sheet presents (stable across sheet re-renders),
    /// cleared on dismiss. `bar` = the clip bar under the region's trim-in.
    private struct ClipEditSession {
        let clipID: UUID
        let bar: Int
        let totalBars: Int
        let model: PianoRollModel
    }
    @State private var clipEdit: ClipEditSession?

    /// #23 S2 — the live per-lane patch edit. `onApply` (per edit tick) updates
    /// only `latest`; the sheet's onDismiss persists it ONCE via
    /// timeline.setLanePatch, and only when `latest != seed` (a mere open of the
    /// door on a nil-patch lane must not commit a stray Init). `seed` is captured
    /// on the first onApply (the editor's onAppear).
    private struct LanePatchEdit {
        let laneID: UUID
        let seed: SynthPatch
        var latest: SynthPatch
    }
    @State private var patchEdit: LanePatchEdit?

    /// Open a region's editor. For MIDI: load THE CLIP's notes (the tapped
    /// bar's slice) into a throwaway roll — never the shared roll (the region
    /// player clobbers that at every onset; pre-H11 this door edited it).
    ///
    /// SCOPE DECISION (documented so no future session "fixes" it blind):
    /// the editor shows CLIP-truth — the clip bar under the region's trim-in,
    /// in clip-bar coordinates ("Bar k/N" = the clip's bars). For a MID-BAR
    /// trim (free split/trim; snap default is 1/16) the region's audible
    /// window straddles two clip bars, so heard-at-region-start ≠ shown-at-
    /// step-0 — the write-back stays correct either way (bar-splice into the
    /// clip). Bars 2..N of a long region are reached by trimming or splitting
    /// (a long-press has no tap coordinate). Region-window-scoped editing is
    /// a later refinement, not a bug.
    private func openRegionEditor(_ region: TimelineRegion) {
        clipEdit = nil
        if let clip = clips.clip(id: region.clipID), clip.kind == .midi {
            let notes = clip.melody?.notes ?? []
            // The bar under the region's trim-in — mirrors the player's offset
            // resolution (ticks authoritative, legacy seconds fallback).
            let rawOffset = region.contentOffsetTicks > 0
                ? region.contentOffsetTicks
                : RegionNoteWindow.offsetTicks(contentOffsetSeconds: region.contentOffsetSeconds,
                                               bpm: beatPlayer.pattern.tempo)
            let bar = RegionNoteWindow.stepAligned(rawOffset) / TimelineTime.ticksPerBar
            let model = PianoRollModel()
            model.load(MelodyBarEdit.slice(bar: bar, of: notes))
            // R1 Scale-Lock: the clip editor inherits the SESSION's key/concert
            // pitch (the same context the Studio pushes to the live roll on
            // every re-seed) — Tonart from the take, not a dropdown. Plain
            // value copies onto @ObservationIgnored fields; the throwaway
            // model stays bus-less (Bio-Humanize falls back to hrv 0.5 there).
            model.musicalA4Hz = pianoRoll.musicalA4Hz
            model.musicalRootPitchClass = pianoRoll.musicalRootPitchClass
            model.musicalScaleName = pianoRoll.musicalScaleName
            // H12 kind-true audition: the session previews through the
            // INSTRUMENT of the lane whose region is edited (drums lane
            // sounds like drums, not the poly synth). The session model is
            // its OWN throwaway PianoRollModel — binding a voice here never
            // touches the shared live-take roll, and nothing needs resetting
            // on close (the binding dies with the session).
            model.setKindVoice(auditionVoice(forLane: region.laneID))
            clipEdit = ClipEditSession(clipID: clip.id, bar: bar,
                                       totalBars: max(MelodyBarEdit.barCount(of: notes), bar + 1),
                                       model: model)
        }
        activeModal = .region(region)
    }

    /// H12: the audition voice for a lane's clip editor, by the lane's built-in
    /// instrument — drums/break → the rack's kit, sub-bass → the rack's sub.
    /// Everything else (polySynth, bioVoice, no instrument) returns nil: the
    /// clip editor keeps today's honest-silent poly path (H11 review HIGH).
    /// Sampler/AU lanes fall back to nil too — SamplerVoice is a one-shot
    /// trigger, not a NoteVoice (known limit, same as the primary-roll
    /// rollKindSink). `kits`/`subs` are empty while
    /// FeatureFlags.voiceKindRouting is OFF, so `.first` is nil-safe.
    private func auditionVoice(forLane laneID: UUID) -> (any NoteVoice)? {
        guard let lane = timeline.document.lanes.first(where: { $0.id == laneID }) else { return nil }
        switch lane.builtinInstrument {
        case .drums, .breakLoop: return laneVoiceRack.kits.first
        case .subBass:           return laneVoiceRack.subs.first
        default:                 return nil
        }
    }

    /// H12: whether this lane is the PRIMARY roll lane — the FIRST non-bio MIDI
    /// lane, which owns the ONE shared live-take roll (same law as
    /// `TimelineDocument.rollSlotGain`). Its door keeps opening the shared roll:
    /// that IS its editor.
    private func isPrimaryRollLane(_ lane: TimelineLane) -> Bool {
        timeline.document.lanes.first(where: { $0.kind == .midi && !$0.isBio })?.id == lane.id
    }

    /// H12 (founder v281 "Wo bleibt Midi Clip?"): open a lane's editor door.
    /// A SECONDARY MIDI lane gets its own user MIDI clip + region (created on
    /// first open via `ensureUserMidiRegion`) and the H11 clip editor — the
    /// old `.lane` route opened the SHARED roll, which plays the poly voice
    /// regardless of the lane's instrument ("keine Drums sondern irgendwelche
    /// Töne"). Grid full / no region ⇒ honest fallback to today's shared-roll
    /// behaviour (the store already logged the warning). Audio/video/primary
    /// MIDI lanes keep their existing `.lane` doors unchanged.
    private func openLaneEditor(_ lane: TimelineLane) {
        if lane.kind == .midi, !lane.isBio, !isPrimaryRollLane(lane),
           let region = timeline.ensureUserMidiRegion(for: lane.id, clipStore: clips,
                                                      loopBars: max(1, loopBars.rawValue)) {
            openRegionEditor(region)
            return
        }
        activeModal = .lane(lane)
    }

    /// H11 write-back (Done only): splice the edited bar into the clip's
    /// CURRENT notes (re-read at commit time, not captured — a concurrent
    /// change elsewhere keeps its other bars). Every note outside the edited
    /// bar survives byte-identical (the multi-bar-safety law); mid-play the
    /// change becomes audible at the next region onset, like any DAW.
    private func commitClipEdit(_ session: ClipEditSession) {
        let current = clips.clip(id: session.clipID)?.melody?.notes ?? []
        let merged = MelodyBarEdit.splice(bar: session.bar,
                                          edited: session.model.notes,
                                          into: current)
        if !clips.updateMelody(id: session.clipID, notes: merged) {
            log.log(.warning, category: .ui, "Clip edit: clip no longer exists — edit dropped")
        }
    }

    /// Founder 2026-07-17 ("Pianoroll macht Sinn, wenn man einen MIDI Clip generiert"): the
    /// clip editor's title names the TRACK whose clip is edited — e.g.
    /// "Drums — Clip", not a generic "Edit Clip" — so the roll always reads as
    /// clip-scoped. Vanished/unnamed lane falls back to the old generic title.
    private func clipEditTitle(_ session: ClipEditSession, region: TimelineRegion) -> String {
        let laneName = timeline.document.lanes
            .first(where: { $0.id == region.laneID })?.name ?? ""
        let base = laneName.isEmpty ? "Edit Clip" : "\(laneName) — Clip"
        return session.totalBars > 1
            ? "\(base) · Bar \(session.bar + 1)/\(session.totalBars)"
            : base
    }

    @ViewBuilder
    private func modalEditor(_ modal: ArrangeModal) -> some View {
        switch modal {
        case .lane(let lane):     editor(forKind: lane.kind,
                                         landingLane: (lane.kind == .audio || lane.kind == .video) ? lane.id : nil)
        case .region(let region):
            // H11: a MIDI region edits ITS CLIP's notes in a throwaway roll —
            // never the shared live-take roll (which the region player clobbers
            // at every onset). Done splices the edited bar back into the clip;
            // swipe-dismiss cancels. Session built in openRegionEditor; the
            // fallback covers the non-MIDI kinds and a vanished session.
            if let session = clipEdit {
                PianoRollView(pattern: beatPlayer.pattern, model: session.model,
                              title: clipEditTitle(session, region: region),
                              onDone: { commitClipEdit(session) })
            } else if clips.clip(id: region.clipID)?.kind == .audio {
                // CLIP-4: Edit on a placed AUDIO region opens ON the clip —
                // file + region window loaded, Done writes the trim back (the
                // blank importer here read as "clip broken/lost").
                AudioClipView(editRegionID: region.id)
            } else {
                editor(forKind: clips.clip(id: region.clipID)?.kind ?? .midi)
            }
        case .laneFX(let lane):   LaneFXEditor(laneName: lane.name, laneID: lane.id)
        case .plugins:            AUv3BrowserView()
        case .patch(let lane):
            // #23 S2 — the patch editor, seeded from THIS lane's own timbre.
            // Secondary lane: nil ⇒ a fresh Init (persisted on change, heard on
            // the next region load via slotPatchSink). Primary roll lane: nil ⇒
            // the current global sound (synth.appliedPatch), so the shared
            // voice's character becomes the lane's persisted patch. `onApply`
            // fires per edit tick (PatchEditorView:92) — here it only captures
            // the latest value into `patchEdit` (cheap, NO persist); the sheet's
            // onDismiss persists ONCE via timeline.setLanePatch, and only if the
            // value changed from the seed (opening without editing commits
            // nothing). The editor still live-applies to the GLOBAL env voice
            // while editing — the honest S2 limit; lane-targeted live preview is
            // the device-gated S3 slice.
            let seed = lane.patch
                ?? (isPrimaryRollLane(lane) ? (synth.appliedPatch ?? SynthPatch(name: "Init"))
                                            : SynthPatch(name: "Init"))
            PatchEditorView(initial: seed, onApply: { edited in
                if patchEdit?.laneID == lane.id {
                    patchEdit?.latest = edited
                } else {
                    // Dismiss-race parity with clipEdit (ui-state review LOW): if a
                    // DIFFERENT lane's edit is still pending — its onDismiss was
                    // skipped by the `activeModal == nil` re-present guard — persist
                    // it before we overwrite, so a fast patch→patch door switch
                    // inside the dismiss animation cannot drop it.
                    if let prev = patchEdit, prev.laneID != lane.id, prev.latest != prev.seed {
                        timeline.setLanePatch(prev.laneID, patch: prev.latest)
                    }
                    patchEdit = LanePatchEdit(laneID: lane.id, seed: seed, latest: edited)
                }
            })
        case .automation:         AutomationView()
        case .clipAutomation(let region):
            // L1/S2b: draw automation INTO the region's clip, clip-relative.
            ClipAutomationView(clipID: region.clipID, spanTicks: clipSpanTicks(region))
        case .spatial:            ImmersiveStageView()
        case .bodyVibe(let lane):
            // EchoelBodyVibe — the body-plays-the-voice surface for this bioVoice
            // track. First slice: live bio strip (leaf) + this lane's own
            // genre/mood/variation. Later slices fold in sound/generate/visual +
            // the Face-camera source. Reads only document-level state here.
            BodyVibeSurfaceView(laneID: lane.id, laneName: lane.name)
        }
    }

    /// Clip span (ticks) for the clip-automation canvas: the MIDI clip's own bar
    /// count (so the drawing spans exactly what the clip plays), else a 4-bar
    /// default. In `AutomationCanvasMath.barTicks` units so the canvas grid aligns.
    private func clipSpanTicks(_ region: TimelineRegion) -> Int {
        let bars: Int
        if let clip = clips.clip(id: region.clipID), clip.kind == .midi {
            bars = max(1, MelodyBarEdit.barCount(of: clip.melody?.notes ?? []))
        } else {
            bars = 4
        }
        return bars * AutomationCanvasMath.barTicks
    }

    /// The editor behind a door/region, by content kind. Only kinds with a real
    /// engine offer one — no placeholder screens.
    @ViewBuilder
    private func editor(forKind kind: ClipKind, landingLane: UUID? = nil) -> some View {
        switch kind {
        case .midi:  PianoRollView(pattern: beatPlayer.pattern, model: pianoRoll)
        case .audio: AudioClipView(landingLaneID: landingLane)
        case .video: VideoClipView(landingLaneID: landingLane)   // import + preview (transport-sync later)
        case .visual: EmptyView()   // no engine yet — no door offered
        }
    }

    private var renameAlertShown: Binding<Bool> {
        Binding(
            get: { renameLaneID != nil },
            set: { if !$0 { renameLaneID = nil } }
        )
    }

    // MARK: - Silenced-instrument guard (#22)

    /// Shown only when the instrument is armed AND its roll-slot lane is inaudible.
    /// Amber (warning) — NOT accent green (that stays reserved for live bio).
    private func rollSilencedBanner(_ reason: TimelineDocument.RollSilenceReason) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EchoelTheme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kein Ton — die Melodie ist stumm")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                Text(Self.silenceReasonText(reason))
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { timeline.unsilenceRollSlot() } label: {
                Text("Ton an")
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.warning.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Turn sound on")
            .accessibilityHint("Unmutes the generative track, clears any solo, and restores its level")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EchoelTheme.warning.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(EchoelTheme.warning.opacity(0.4)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private static func silenceReasonText(_ reason: TimelineDocument.RollSilenceReason) -> String {
        switch reason {
        case .muted:       return "Die Spur \u{201E}MIDI 1\u{201C} ist gemutet \u{2014} tippe \u{201E}Ton an\u{201C} oder das M an der Spur."
        case .otherSoloed: return "Eine andere Spur ist auf Solo \u{2014} MIDI 1 ist deshalb still."
        case .levelZero:   return "Der Pegel von \u{201E}MIDI 1\u{201C} steht auf 0."
        }
    }

    // MARK: - Toolbar (low-frequency only)

    private var toolbar: some View {
        HStack(spacing: 10) {
            // (The "Play timeline" button is GONE — founder 2026-07-15 video: "zu viele
            //  Play Knöpfe, einer reicht." The ONE transport ▶ in the chrome above now
            //  plays the arrangement whenever the timeline has regions [it engages
            //  TimelineRegionPlayer], else the live loop — so this separate button was
            //  redundant. Recording keeps its own arm control below.)

            // Undo / Redo (clip game C2 — fearless editing): every region edit (move,
            // trim, split, join, duplicate, delete, import-add) is one history step in
            // the store. `canUndo`/`canRedo` flip only on edits (low-frequency reads —
            // render-safe in this toolbar).
            Button { timeline.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timeline.canUndo ? EchoelTheme.text : EchoelTheme.dim)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!timeline.canUndo)
            .accessibilityLabel("Undo the last clip edit")

            Button { timeline.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timeline.canRedo ? EchoelTheme.text : EchoelTheme.dim)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!timeline.canRedo)
            .accessibilityLabel("Redo the undone clip edit")

            // Multi-select (clip game C3): toggle select mode; while on, taps mark clips
            // and Combine/Delete act on the whole set (founder: "mehrere Clips markiert
            // soll auch combine gehen"). Leaving the mode clears the selection.
            Button {
                isSelecting.toggle()
                if !isSelecting { selectedRegions.removeAll() }
            } label: {
                Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelecting ? EchoelTheme.onPrimary : EchoelTheme.text)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(isSelecting ? EchoelTheme.text : EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: isSelecting ? 0 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelecting ? "Done selecting clips" : "Select multiple clips")

            if isSelecting {
                Button {
                    timeline.combineRegions(ids: selectedRegions)
                    selectedRegions.removeAll()
                    isSelecting = false
                } label: {
                    Text("Combine")
                        .font(EchoelTheme.font(12, .medium))
                        // H12/M4: enabled ONLY for a lossless combine (one lane, one
                        // clip) — combining different clips would silently discard
                        // every other clip's content from the span.
                        .foregroundStyle(timeline.canCombineRegions(ids: selectedRegions)
                                         ? EchoelTheme.text : EchoelTheme.dim)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!timeline.canCombineRegions(ids: selectedRegions))
                .accessibilityLabel("Combine the selected clips into one (same clip only)")

                Button {
                    timeline.removeRegions(ids: selectedRegions)
                    selectedRegions.removeAll()
                    isSelecting = false
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedRegions.isEmpty ? EchoelTheme.dim : EchoelTheme.danger)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(selectedRegions.isEmpty)
                .accessibilityLabel("Delete the selected clips")
            }

            // Record: arm the take + start the clock. Every note/bio input on an armed
            // track is captured; Stop drops a Clip + region onto that lane. Reads only
            // the low-frequency `isRecording` bool (render-safe). Disabled until a track
            // is record-armed (its per-track Record dot in the lane strip).
            Button {
                if recordController.isRecording {
                    // T1 breadcrumb: this stop cascades into the ONE-Stop door
                    // (EchoelStudioView transport-stopped) — name the finger.
                    EchoelCrashLog.breadcrumb("stop source: record-stop (commit take)")
                    beatPlayer.pattern.stop()          // → transport.stop() → commit take
                } else {
                    recordController.arm()
                    if !beatPlayer.pattern.isPlaying { beatPlayer.pattern.play() }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: recordController.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(recordController.isRecording ? "Stop rec" : "Record")
                        .font(EchoelTheme.font(12, .medium))
                }
                .foregroundStyle(recordController.isRecording ? EchoelTheme.onPrimary : EchoelTheme.danger)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(recordController.isRecording ? EchoelTheme.danger : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: recordController.isRecording ? 0 : 1))
            }
            .buttonStyle(.plain)
            .disabled(!recordController.isRecording && !recordController.hasArmedTarget())
            .accessibilityLabel(recordController.isRecording ? "Stop recording" : "Record armed tracks")

            // Performance mode: launch clips live (founder 2026-07-17). Own leaf
            // helpers keep this HStack's type-check budget flat; the quantize menu
            // shows only while Performance is armed.
            performanceToggle
            if performanceMode { launchQuantizeMenu }

            // Split / Join moved ONTO the clip (founder 2026-07-15: "wenn man lange auf
            // den Clip drückt [hat] man Optionen wie cut"). The razor + rejoin now live
            // in each region's long-press menu (per-region, not a playhead-wide toolbar
            // button the founder found opaque — "Was ist das?"). Toolbar stays lean.

            // Immersive Stage door: the Touch surface that places every track in
            // space. Every non-bio lane is already a positioned SpatialObject; this
            // opens the room map to move them. Reuses the ONE sheet slot (.spatial),
            // never a second `.sheet` (metadata law). Disabled with no real tracks.
            Button { activeModal = .spatial } label: {
                HStack(spacing: 5) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Immersive")
                        .font(EchoelTheme.font(12, .medium))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(timeline.document.lanes.allSatisfy { $0.isBio })
            .accessibilityLabel("Immersive Stage — place tracks in space")

            // U1: no "Arrange" label — this IS the app's one view, not a named tab.
            Spacer(minLength: 0)
            // Add track. Instruments first (founder 2026-07-13: "EchoelDrums,
            // Echoelbreak, EchoelSampler etc" — the app's OWN voices, named on the
            // track), then the plain media kinds (Audio · Video · MIDI).
            Menu {
                Section("Instruments") {
                    ForEach(TrackInstrument.allCases, id: \.self) { inst in
                        Button { timeline.addInstrumentTrack(inst) } label: {
                            Label(inst.displayName, systemImage: inst.systemImage)
                        }
                    }
                }
                Section("Media") {
                    Button { timeline.addLane(kind: .audio) } label: {
                        Label("Audio track", systemImage: ClipKind.audio.systemImage)
                    }
                    Button { timeline.addLane(kind: .video) } label: {
                        Label("Video track", systemImage: ClipKind.video.systemImage)
                    }
                    Button { timeline.addLane(kind: .midi) } label: {
                        Label("Empty MIDI track", systemImage: ClipKind.midi.systemImage)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Add track")
            // Snap resolution — the magnet. "Off" = stufenlos everywhere.
            Menu {
                ForEach(SnapResolution.allCases, id: \.self) { res in
                    Button {
                        snapRaw = res.rawValue
                    } label: {
                        if res == snap { Label(res.displayName, systemImage: "checkmark") }
                        else { Text(res.displayName) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: snap == .off ? "arrow.left.and.right" : "arrow.right.to.line.compact")
                        .font(.system(size: 11, weight: .medium))
                    Text(snap == .off ? "Frei" : "Snap \(snap.displayName)")
                        .font(EchoelTheme.font(12))
                }
                .foregroundStyle(snap == .off ? EchoelTheme.dim : EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Snap resolution")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    // MARK: - Performance mode (clip launch) — toolbar leaves

    /// The Performance-mode toggle. Accent-filled when armed. Reads only the
    /// low-frequency `performanceMode` @State (freeze-safe in the toolbar body).
    private var performanceToggle: some View {
        Button { performanceMode.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: performanceMode ? "play.circle.fill" : "play.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("Performance")
                    .font(EchoelTheme.font(12, .medium))
            }
            .foregroundStyle(performanceMode ? EchoelTheme.onPrimary : EchoelTheme.text)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(performanceMode ? EchoelTheme.accent : EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, lineWidth: performanceMode ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Performance mode")
        .accessibilityValue(performanceMode ? "On" : "Off")
        .accessibilityHint("Shows a launch button on every MIDI clip to trigger it live")
    }

    /// Launch quantization picker (Performance mode only) — the grid a clip launch
    /// snaps to. The current grid is checkmarked; default Bar.
    private var launchQuantizeMenu: some View {
        Menu {
            ForEach(LaunchQuantize.allCases, id: \.self) { q in
                Button {
                    launchQuantize = q
                } label: {
                    if q == launchQuantize { Label(q.displayName, systemImage: "checkmark") }
                    else { Text(q.displayName) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "metronome")
                    .font(.system(size: 11, weight: .medium))
                Text("Quant \(launchQuantize.displayName)")
                    .font(EchoelTheme.font(12))
            }
            .foregroundStyle(EchoelTheme.text)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Launch quantize")
        .accessibilityValue(launchQuantize.displayName)
    }

    // MARK: - Lane labels (fixed column, never scrolls away)

    private var laneLabels: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: headWidth, height: Self.rulerHeight)
            ForEach(timeline.document.lanes) { lane in
                laneHeader(lane)
                // T1: the open automation row's HEAD cell — same height as the
                // grid-side canvas row, so both columns stay line-aligned.
                if automationOpen.contains(lane.id), !lane.isBio {
                    automationHeadCell(lane)
                }
            }
            Spacer(minLength: 0)
        }
        .background(EchoelTheme.bg)
    }

    // MARK: - Inline automation row (T1 — see TimelineAutomationRow.swift)

    /// Label-column cell of an open automation row: target picker + "⋯" into
    /// the EXISTING `.automation` sheet slot (precision editor — no new sheet,
    /// metadata law) + fold-up chevron.
    private func automationHeadCell(_ lane: TimelineLane) -> some View {
        TimelineAutomationHeadCell(
            laneName: lane.name,
            selectedParameter: automationTargetBinding(lane.id),
            // L2/L4: offer per-track targets only for a lane that actually OWNS a
            // rack slot — the SAME slot resolution the playback dispatch uses
            // (MultiRollFanout.slot bounds by rack capacity), so the picker and the
            // audio agree by construction: the roll lane (no slot) and any overflow
            // secondary lane (rank ≥ capacity) are never offered a dead target.
            perTrackLaneID: MultiRollFanout.slot(
                forLaneID: lane.id, in: timeline.document,
                rollLane: timeline.document.rollLaneID, capacity: laneVoiceRack.capacity
            ) != nil ? lane.id : nil,
            onOpenEditor: { activeModal = .automation },
            onClose: { automationOpen.remove(lane.id) },
            // Keep the open-automation-row cell pixel-aligned under the adaptive head.
            columnWidth: headWidth)
    }

    private func automationTargetBinding(_ laneID: UUID) -> Binding<String> {
        Binding(get: { automationTarget[laneID] ?? AutomationTarget.masterLevel.rawValue },
                set: { automationTarget[laneID] = $0 })
    }

    /// Grid-column canvas of an open automation row: the selected parameter's
    /// song-absolute curve on the SAME x-scale as the clips (tick · ppb/480 —
    /// coupled by construction). Edits commit through TimelineStore's
    /// automation API (persisted; playback pulls them in via the region
    /// player's structural refresh). Document-level reads only (freeze law).
    private func automationGridRow(_ lane: TimelineLane) -> some View {
        let parameter = automationTarget[lane.id] ?? AutomationTarget.masterLevel.rawValue
        let points = timeline.automationLane(forParameter: parameter)?.points ?? []
        return TimelineAutomationRow(
            points: points, ppb: ppb, barCount: barCount, snap: snap,
            onAdd: { tick, value in
                _ = timeline.addAutomationPoint(parameter: parameter, tick: tick, value: value)
            },
            onMove: { id, tick, value in
                timeline.moveAutomationPoint(parameter: parameter, id: id,
                                             toTick: tick, normalized: value)
            },
            onDelete: { id in
                timeline.removeAutomationPoint(parameter: parameter, id: id)
            })
    }

    /// One track head — a DOOR (Stage 3a) plus the K2a mixer strip (M · S ·
    /// level). The strip sits BELOW the menu label (buttons inside a Menu label
    /// never receive taps) and only on media lanes — the bio lane has no gain.
    private func laneHeader(_ lane: TimelineLane) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            laneDoor(lane)
            if !lane.isBio { laneMixStrip(lane) }
        }
        // Leading-pin: any residual overflow spills RIGHT under the column border,
        // never off the LEFT screen edge (the old centre default shifted the whole
        // head left until "MIDI 1" clipped). This one alignment is the actual un-clip.
        .frame(width: headWidth, height: Self.laneHeight, alignment: .leading)
        // Kind-identity stripe on the leading edge (DAW convention) — the lane
        // head and its regions share one colour, so the eye pairs them.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Self.kindTint(lane.isBio ? nil : lane.kind).opacity(0.65))
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
    }

    private func laneDoor(_ lane: TimelineLane) -> some View {
        Menu {
            // EchoelBodyVibe (founder 2026-07-20 "Man wählt das ganz normal als
            // Instrument aus"): a track whose built-in instrument is `.bioVoice`
            // opens the bio-generative surface — live body + this lane's own
            // genre/mood. Its own top door so the body-plays-the-voice flow is
            // one tap, not buried under "Open MIDI clip".
            if !lane.isBio, lane.kind == .midi, lane.builtinInstrument == .bioVoice {
                Button { activeModal = .bodyVibe(lane) } label: {
                    Label("Open EchoelBodyVibe", systemImage: TrackInstrument.bioVoice.systemImage)
                }
            }
            if !lane.isBio, lane.kind == .midi {
                // H12: secondary MIDI lanes open THEIR OWN clip (ensure +
                // region editor); the primary roll lane keeps the shared roll.
                Button { openLaneEditor(lane) } label: {
                    Label(isPrimaryRollLane(lane) ? "Open Piano Roll" : "Open MIDI clip",
                          systemImage: ClipKind.midi.systemImage)
                }
            }
            if !lane.isBio, lane.kind == .audio {
                Button { activeModal = .lane(lane) } label: {
                    Label("Open audio editor", systemImage: ClipKind.audio.systemImage)
                }
            }
            if !lane.isBio, lane.kind == .video {
                Button { activeModal = .lane(lane) } label: {
                    Label("Import video…", systemImage: ClipKind.video.systemImage)
                }
            }
            // The built-in Echoel instrument this track plays (founder 2026-07-13:
            // "EchoelDrums, Echoelbreak, EchoelSampler etc") — settable/changeable
            // per track; the current one is checkmarked.
            if !lane.isBio, lane.kind == .midi {
                Menu {
                    ForEach(TrackInstrument.allCases, id: \.self) { inst in
                        Button { timeline.setBuiltinInstrument(id: lane.id, inst) } label: {
                            if lane.builtinInstrument == inst {
                                Label(inst.displayName, systemImage: "checkmark")
                            } else {
                                Label(inst.displayName, systemImage: inst.systemImage)
                            }
                        }
                    }
                    if lane.builtinInstrument != nil {
                        Divider()
                        Button(role: .destructive) {
                            timeline.setBuiltinInstrument(id: lane.id, nil)
                        } label: { Label("Clear instrument", systemImage: "xmark.circle") }
                    }
                } label: {
                    Label(lane.builtinInstrument?.displayName ?? "Instrument…",
                          systemImage: lane.builtinInstrument?.systemImage ?? "pianokeys")
                }
            }
            // The lane's SOUND, on the lane (founder 2026-07-12): the melodic
            // bus insert for MIDI lanes + the AUv3 host for both media kinds.
            if !lane.isBio, lane.kind == .midi {
                Button { activeModal = .laneFX(lane) } label: {
                    Label("Sound & FX (this track)", systemImage: "slider.horizontal.3")
                }
                Button { activeModal = .patch(lane) } label: {
                    Label("Synth patch", systemImage: "waveform.badge.plus")
                }
            }
            if !lane.isBio {
                // U3b: the plugin this track carries — visible + settable per track.
                // The header shows the current assignment; Browse opens the shared
                // AUv3 host; Assign records what's loaded onto THIS lane (persisted
                // intent — per-lane routing waits for multi-roll).
                Section {
                    Button { activeModal = .plugins } label: {
                        Label("Browse AUv3…", systemImage: "puzzlepiece.extension")
                    }
                    if let loaded = auHost.loaded, loaded.isInstrument {
                        Button {
                            timeline.setLaneInstrument(id: lane.id, AUPluginRef(loaded))
                            timeline.setLaneEffects(id: lane.id, auHost.loadedEffects.map { AUPluginRef($0) })
                        } label: {
                            Label("Assign “\(loaded.name)” to this track", systemImage: "arrow.down.circle")
                        }
                    }
                    if lane.instrument != nil || !lane.effects.isEmpty {
                        Button(role: .destructive) {
                            timeline.setLaneInstrument(id: lane.id, nil)
                            timeline.setLaneEffects(id: lane.id, [])
                        } label: {
                            Label("Clear plugin assignment", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text(pluginAssignmentSummary(lane))
                }
                Button { activeModal = .automation } label: {
                    Label("Automation", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            Button {
                renameText = lane.name
                renameLaneID = lane.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if timeline.document.regions(in: lane.id).isEmpty,
               timeline.document.lanes.count > 1 {
                Button(role: .destructive) {
                    timeline.removeLaneIfEmpty(id: lane.id)
                } label: {
                    Label("Delete empty track", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: lane.kind.systemImage)
                    .font(.system(size: 9))
                    .foregroundStyle(EchoelTheme.dim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lane.name)
                        .font(EchoelTheme.font(10, .medium))
                        .foregroundStyle(EchoelTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)   // scales "MIDI 1" down, never "MID…"
                    // Item 3 (founder: "sichtbare Instrument/FX-Belegung pro Spur"):
                    // the track's instrument + FX AT A GLANCE — it was menu-only until
                    // now (the head only carried a binary puzzle icon, never WHICH
                    // instrument, and never the BUILT-IN voice name at all). Uses the
                    // tested LaneInstrumentLabel formatter; a dim single-line caption
                    // that scales down so the 140-pt head never overflows. nil for a
                    // bare/bio lane → the row stays exactly as before.
                    if let belegung = LaneInstrumentLabel.summary(for: lane) {
                        Text(belegung)
                            .font(EchoelTheme.font(8))
                            .foregroundStyle(EchoelTheme.dim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                // U3b at-a-glance cue: this track carries a plugin assignment.
                if lane.instrument != nil || !lane.effects.isEmpty {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(EchoelTheme.accent)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .padding(.trailing, 6)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(lane.name), \(lane.kind.displayName) track. \(pluginAssignmentSummary(lane))")
    }

    /// U3b: the human-readable plugin assignment shown as the menu-section header
    /// (and spoken in the head's a11y label). Honest — reflects the persisted
    /// `TimelineLane.instrument`/`effects`, nothing loaded-but-unassigned.
    private func pluginAssignmentSummary(_ lane: TimelineLane) -> String {
        var parts: [String] = []
        if let inst = lane.instrument {
            // A persisted Apple file-player record is kept (user document data) but
            // never hosted — say so, or the head claims an instrument that the
            // built-in voice is actually playing (silence-trap review LOW).
            parts.append(inst.isAppleGeneratorTrap
                ? "Instrument: \(inst.name) (not playable — built-in voice plays)"
                : "Instrument: \(inst.name)")
        }
        if !lane.effects.isEmpty { parts.append("FX: \(lane.effects.map(\.name).joined(separator: ", "))") }
        return parts.isEmpty ? "No plugin assigned" : parts.joined(separator: " · ")
    }

    /// K2a strip: Mute / Solo toggles + the lane level (EchoelValueField — the
    /// one parameter control app-wide). State lives in TimelineStore (persisted);
    /// audibility flows via `effectiveGain` → engines (roll slot wired today).
    private func laneMixStrip(_ lane: TimelineLane) -> some View {
        HStack(spacing: 3) {
            // Record-arm (founder 2026-07-13: "jede Spur soll ein record Button
            // haben der entsprechend verknüpft ist"). The icon shows THIS track's
            // input source (Audio-in / MIDI-in / Bio); tapping arms it (red). Arm
            // is honest persisted intent — the per-source capture take lands next.
            if lane.recordSource.canRecord {
                recordArmButton(lane)
            }
            mixToggle("M", isOn: lane.isMuted, onTint: EchoelTheme.warning,
                      hint: "Mute \(lane.name)") {
                timeline.toggleMute(id: lane.id)
            }
            mixToggle("S", isOn: lane.isSoloed, onTint: EchoelTheme.accent,
                      hint: "Solo \(lane.name)") {
                timeline.toggleSolo(id: lane.id)
            }
            EchoelValueField(
                label: "",
                value: Binding(
                    get: { timeline.document.lanes.first(where: { $0.id == lane.id })?.level ?? 1 },
                    set: { timeline.setLaneLevel(id: lane.id, $0) }
                ),
                range: 0...2, decimals: 2, boxWidth: 30, boxHeight: 28
            )
            // The strip is too narrow for a visible "Level" caption — restore the
            // context for VoiceOver instead (the box shows the bare number).
            .accessibilityLabel("Level, \(lane.name)")
            // Level 0 = the second confirmed "sound geht nicht" source: warn at the
            // fader itself (edit-frequency read, freeze-safe).
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                .strokeBorder(EchoelTheme.warning,
                              lineWidth: (timeline.document.lanes.first(where: { $0.id == lane.id })?.level ?? 1) <= 0 ? 1 : 0))
            .accessibilityHint((timeline.document.lanes.first(where: { $0.id == lane.id })?.level ?? 1) <= 0
                               ? "Silent — the level is zero" : "")
            // T1: fold-out toggle for the inline automation row — same 21×28
            // chip pattern as M/S. Fits: 114 pt strip + 3 + 21 = 138 ≤ 140.
            automationRowToggle(lane)
        }
        // Fit the whole strip (record-arm · M · S · gain) inside the lane column:
        // leading 8, tight 3 pt gaps, a 30 pt gain box (empty-label field = box only).
        // Founder 2026-07-15: the old 40 pt box + label dead-space overflowed → the
        // record button + colour stripe clipped off the left edge.
        .padding(.leading, 8).padding(.trailing, 4)
        // The chrome chips (record/M/S/auto 21 pt, gain 30 pt) are fixed-size controls,
        // not content — cap Dynamic Type so accessibility text can't overflow them and
        // re-trigger the clip. The door name + panels still scale fully (Edit D).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// T1: the automation-row chevron/glyph on the track head — a mixToggle-
    /// sized chip (the head's established button pattern; the Menu LABEL above
    /// swallows taps, so interactive controls live in this strip). Accent when
    /// the row is open. Bio lanes have no strip → no automation row (their lane
    /// IS a curve already, and every offered target is global).
    private func automationRowToggle(_ lane: TimelineLane) -> some View {
        let isOpen = automationOpen.contains(lane.id)
        return Button {
            if isOpen { automationOpen.remove(lane.id) }
            else { automationOpen.insert(lane.id) }
        } label: {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isOpen ? EchoelTheme.onPrimary : EchoelTheme.dim)
                .frame(width: 21, height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .fill(isOpen ? EchoelTheme.accent : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Automation row, \(lane.name)")
        .accessibilityValue(isOpen ? "Shown" : "Hidden")
    }

    private func mixToggle(_ letter: String, isOn: Bool, onTint: Color,
                           hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(letter)
                .font(EchoelTheme.font(10, .semibold))
                .foregroundStyle(isOn ? EchoelTheme.onPrimary : EchoelTheme.dim)
                .frame(width: 21, height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .fill(isOn ? onTint : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hint)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    /// Per-track record-arm. Shows the track's INPUT source icon (mic / MIDI / bio),
    /// filled red when armed. Wired to `TimelineLane.isArmed` (persisted); arming an
    /// input is honest DAW intent — the capture take rides the shared transport next.
    /// CLIP-2: sources TakeRecorder cannot capture yet (mic/video, task #13) get NO
    /// arm control at all — just the plain source-kind icon (App Store audit
    /// 2026-07-16, Guideline 2.1: a permanently disabled button whose VoiceOver
    /// label says "arrives soon" is placeholder UI on the home surface; the earlier
    /// CLIP-2 disabled-state was the first layer of the same law, this removes the
    /// dead control entirely). The planner (`RecordPlan.targets`) stays the second,
    /// engine-side layer. Same 21×28 frame either way, so the lane head never shifts.
    @ViewBuilder
    private func recordArmButton(_ lane: TimelineLane) -> some View {
        let source = lane.recordSource
        if source.captureImplemented {
            Button {
                timeline.toggleArm(id: lane.id)
            } label: {
                Image(systemName: lane.isArmed ? "record.circle.fill" : source.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(lane.isArmed ? EchoelTheme.onPrimary : EchoelTheme.dim)
                    .frame(width: 21, height: 28)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                        .fill(lane.isArmed ? EchoelTheme.danger : EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arm \(source.displayName) recording, \(lane.name)")
            .accessibilityValue(lane.isArmed ? "Armed" : "Off")
        } else {
            // Identity icon only — informative, not interactive (no dead button).
            Image(systemName: source.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(EchoelTheme.dim.opacity(0.45))
                .frame(width: 21, height: 28)
                .accessibilityLabel("\(source.displayName) track, \(lane.name)")
        }
    }

    // MARK: - Grid (ruler + lanes + regions + playhead)

    private var grid: some View {
        VStack(spacing: 0) {
            ruler
            ForEach(timeline.document.lanes) { lane in
                laneRow(lane)
                // T1: the open automation row's CANVAS — same width + x-scale
                // as the clip row above it (time axes coupled by construction).
                if automationOpen.contains(lane.id), !lane.isBio {
                    automationGridRow(lane)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: gridWidth, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            TimelinePlayhead(pointsPerBeat: ppb, snap: snap, coordinateSpace: Self.playheadSpace)
        }
        // Absolute x reference for the playhead drag → tick mapping (scroll-invariant).
        .coordinateSpace(name: Self.playheadSpace)
    }

    /// Name of the grid's coordinate space (playhead drag → tick; region drags —
    /// jitter audit C1 — measure in it too, so a clip's own re-layout can never
    /// feed back into its gesture translation). Fileprivate like `laneHeight`:
    /// RegionBlockView lives in this file.
    fileprivate static let playheadSpace = "echoel.timeline.grid"

    /// Beat subdivisions appear once a beat is wide enough to read (≥ 18 pt) —
    /// zoomed out, only bars; zoomed in, the working grid a DAW shows.
    private var showBeatTicks: Bool { ppb >= 18 }

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            EchoelTheme.fill
            // Bar numbers + real tick marks (V3: the old ruler was bare tiny
            // numbers floating on a strip — no ticks, no rhythm to the eye).
            ForEach(0..<barCount, id: \.self) { bar in
                let barX = CGFloat(bar * TimelineTime.beatsPerBar) * ppb
                Rectangle()
                    .fill(EchoelTheme.text.opacity(0.35))
                    .frame(width: 1, height: 8)
                    .offset(x: barX, y: Self.rulerHeight - 8)
                Text("\(bar + 1)")
                    .font(EchoelTheme.font(10, .medium).monospacedDigit())
                    .foregroundStyle(EchoelTheme.dim)
                    .offset(x: barX + 4, y: 2)
                if showBeatTicks {
                    ForEach(1..<TimelineTime.beatsPerBar, id: \.self) { beat in
                        Rectangle()
                            .fill(EchoelTheme.text.opacity(0.18))
                            .frame(width: 1, height: 4)
                            .offset(x: barX + CGFloat(beat) * ppb, y: Self.rulerHeight - 4)
                    }
                }
            }
        }
        .frame(width: gridWidth, height: Self.rulerHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
    }

    private func laneRow(_ lane: TimelineLane) -> some View {
        // Silence made VISIBLE (night audit): a muted / soloed-away / level-0 lane
        // draws its clips dimmed + desaturated — several founder "Sound geht nicht"
        // reports were a silent mixer state with no visual trace on the grid.
        // Document-level read: changes on mixer EDITS only, never at 10 Hz (freeze rule).
        let audible = lane.isBio || timeline.document.effectiveGain(for: lane.id) > 0
        // #56 MEDIUM #2: the drop-acceptance facts as plain values for the region
        // leaves (edit-frequency read here in the PARENT; the leaf never touches
        // the document during a drag — freeze law).
        let laneIndex = timeline.document.lanes.firstIndex(where: { $0.id == lane.id }) ?? 0
        let laneGates = timeline.document.lanes.map {
            TimelineDragMath.LaneGate(kind: $0.kind, isBio: $0.isBio)
        }
        return ZStack(alignment: .topLeading) {
            // Bar lines + (zoomed in) lighter beat lines — the working grid a
            // DAW shows, mirroring the ruler's ticks (V3 design pass).
            ForEach(0..<barCount, id: \.self) { bar in
                let barX = CGFloat(bar * TimelineTime.beatsPerBar) * ppb
                Rectangle()
                    .fill(EchoelTheme.text.opacity(0.14))
                    .frame(width: 1, height: Self.laneHeight)
                    .offset(x: barX)
                if showBeatTicks {
                    ForEach(1..<TimelineTime.beatsPerBar, id: \.self) { beat in
                        Rectangle()
                            .fill(EchoelTheme.text.opacity(0.05))
                            .frame(width: 1, height: Self.laneHeight)
                            .offset(x: barX + CGFloat(beat) * ppb)
                    }
                }
            }
            Group {
                let laneRegions = timeline.document.regions(in: lane.id)
                ForEach(laneRegions) { region in
                    // Each region is its OWN leaf view that owns its live gesture deltas
                    // (@GestureState since #56 slice 1) — so a trim drag re-renders ONLY
                    // that clip, never the whole timeline (the old root-@State resize made
                    // every drag frame rebuild all lanes + ruler + playhead, 2026-07-15).
                    // #56 C6: this region's neighbour edge ticks, captured here in the
                    // PARENT (edit-rate) so the leaf can preview edge magnetism without a
                    // per-frame store read (freeze law) — self excluded, exactly the
                    // candidates the move commit builds.
                    let neighbourEdges = laneRegions
                        .filter { $0.id != region.id }
                        .flatMap { [$0.startTick, $0.endTick] }
                    RegionBlockView(region: region, ppb: ppb, snap: snap,
                                    selectMode: isSelecting,
                                    isSelected: selectedRegions.contains(region.id),
                                    onSelectToggle: {
                                        if selectedRegions.contains(region.id) {
                                            selectedRegions.remove(region.id)
                                        } else {
                                            selectedRegions.insert(region.id)
                                        }
                                    },
                                    laneIndex: laneIndex,
                                    laneGates: laneGates,
                                    neighbourEdges: neighbourEdges,
                                    performanceMode: performanceMode,
                                    launchQuantize: launchQuantize,
                                    laneIsBio: lane.isBio,
                                    onEdit: { openRegionEditor(region) },
                                    onAutomation: { activeModal = .clipAutomation(region) })
                }
            }
            .opacity(audible ? 1 : 0.35)
            .saturation(audible ? 1 : 0)
        }
        .frame(width: gridWidth, height: Self.laneHeight, alignment: .topLeading)
        // Long-press the EMPTY lane body = "import on the spot" (founder 2026-07-15:
        // "Lange gedrückt halten auf die Spur = Import on the spot für alle Spurarten").
        // Opens the SAME kind-routed importer/editor as the lane-head menu (`.lane`):
        // audio → import audio, video → import video, midi → the roll. A long-press on a
        // REGION still hits that region's own menu (it's drawn on top with its own
        // contextMenu); this outer menu only answers empty space. contentShape makes the
        // gaps between clips hittable. contextMenu builds on open (freeze-safe, no sheet
        // added — it just sets the existing `.sheet(item:)` binding).
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                // H12: same kind-routed door as the lane head — a secondary
                // MIDI lane lands in its own clip's editor, not the shared roll.
                openLaneEditor(lane)
            } label: {
                Label(Self.laneImportLabel(lane.kind), systemImage: Self.laneImportIcon(lane.kind))
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
    }

    /// Menu label for the empty-lane import gesture, by track kind.
    private static func laneImportLabel(_ kind: ClipKind) -> String {
        switch kind {
        case .audio:  return "Import audio\u{2026}"
        case .video:  return "Import video\u{2026}"
        case .midi:   return "Open MIDI editor\u{2026}"
        case .visual: return "Open\u{2026}"
        }
    }

    private static func laneImportIcon(_ kind: ClipKind) -> String {
        switch kind {
        case .audio:  return "waveform"
        case .video:  return "film"
        case .midi:   return "pianokeys"
        case .visual: return "sparkles"
        }
    }

    /// Resolve a clip's `mediaRef` to an existing file — delegates to the ONE
    /// resolver (H6: MediaLibrary.resolveRef re-roots refs whose container
    /// prefix changed on an app update; this private twin used to die on them).
    fileprivate static func mediaURL(_ clip: Clip) -> URL? {
        MediaLibrary.resolveRef(clip.mediaRef)
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                pointsPerBeat = min(96, max(8, pointsPerBeat * value))
            }
    }

}

/// One region block — its OWN leaf view so a trim drag re-renders only THIS clip,
/// not the whole timeline (fixes the founder's "Clip zittert" 2026-07-15). Owns the
/// live gesture deltas locally as @GestureState (#56 slice 1: stable grid-space
/// measurement + auto-reset on cancelled drags); commits snapped values on release.
@MainActor
private struct RegionBlockView: View {
    let region: TimelineRegion
    let ppb: CGFloat
    let snap: SnapResolution
    /// Multi-select (C3): while the toolbar's select mode is on, a TAP toggles this
    /// clip in/out of the selection instead of auditioning.
    var selectMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: () -> Void = {}
    /// #56 MEDIUM #2: this clip's lane INDEX + every row's drop-acceptance facts,
    /// as plain VALUES (never the document — freeze law), so the vertical move
    /// preview seats only on rows the store will actually accept.
    var laneIndex: Int = 0
    var laneGates: [TimelineDragMath.LaneGate] = []
    /// Raw start/end ticks of the OTHER regions in this lane (self excluded),
    /// captured by the parent lane row at build time (#56 C6). A user-rate value
    /// — the leaf uses it for edge-magnetism preview without ever reading the
    /// document during a drag (freeze law). Empty ⇒ pure grid preview.
    var neighbourEdges: [Int] = []
    /// Performance mode (founder 2026-07-17): draws the launch glyph on MIDI clips
    /// and SUSPENDS this region's move/trim gestures (a tap must launch, not scrub).
    var performanceMode: Bool = false
    /// The launch grid the glyph arms to (Performance mode only).
    var launchQuantize: LaunchQuantize = .bar
    /// Whether this region's lane is a BIO lane — those never launch (the P0 core
    /// guards `!lane.isBio`), so they get no glyph even in Performance mode.
    var laneIsBio: Bool = false
    /// Opens this region's editor (the parent owns the one sheet slot).
    let onEdit: () -> Void
    /// L1/S2b: opens the clip-automation DRAW editor for this region's clip
    /// (same one sheet slot, parent-owned). Default no-op for callers that
    /// don't offer it.
    var onAutomation: () -> Void = {}

    @Environment(ClipStore.self) private var clips
    @Environment(TimelineStore.self) private var timeline
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(Transport.self) private var transport

    // Live gesture deltas — @GestureState, not @State (jitter audit #56 C2): when
    // the surrounding ScrollView steals a drag mid-gesture, SwiftUI CANCELS it and
    // `.onEnded` never fires — a plain @State delta then sticks and the clip
    // renders displaced from its store truth until the next successful drag
    // ("clips twitch/jump between grabs"). @GestureState auto-resets on cancel.
    // Still leaf-local (#44): only this clip re-renders while dragging.
    /// Live trailing-trim offset for THIS clip only.
    @GestureState private var resizeDelta: CGFloat = 0
    /// Live LEADING-trim offset (founder 2026-07-15 "auch vorne"): moving the left
    /// edge shifts x AND shrinks/grows the width, holding the right edge fixed.
    @GestureState private var frontDelta: CGFloat = 0
    /// Live DRAG-TO-MOVE offset (clip game C1, founder 2026-07-15 "seamless
    /// workflow"): grab the clip BODY and slide it — horizontally in time,
    /// vertically to another same-kind lane.
    @GestureState private var moveDelta: CGSize = .zero
    // Grip/float emphasis derives from the live deltas (the old separate bool
    // @States could also stick on cancellation — same C2 class).
    private var isResizing: Bool { resizeDelta != 0 }
    private var isFrontResizing: Bool { frontDelta != 0 }
    private var isMoving: Bool { moveDelta != .zero }
    /// Increments whenever a drop actually SNAPPED (grid or neighbour edge) — drives
    /// the `.sensoryFeedback` light tick (clip game C4: fühlbares Einrasten).
    @State private var snapPulse = 0
    /// #56 C5: `MediaLibrary.resolveRef` probes the file system (up to ~5 exists
    /// checks + a directory-creation side effect per MISS) — body used to call it
    /// TWICE per frame while a drag's @GestureState churns this leaf at display
    /// rate (main-thread micro-hitches = stutter under the finger, worst for a
    /// vanished/re-rooted ref). Resolved ONCE per mediaRef here; body reads the
    /// cached URL only.
    @State private var resolvedMediaURL: URL?

    private var laneHeight: CGFloat { ArrangeTimelineView.laneHeight }

    var body: some View {
        // Leading trim moves the left edge and adjusts width the opposite way so the
        // RIGHT edge stays put; trailing trim adds to the width; a move shifts the
        // whole clip (rows snap live). #56 C4: the raw finger deltas are transformed
        // through pure TimelineDragMath so the clip PREVIEWS at the exact snapped/
        // clamped position its release will commit — letting go is a visual no-op
        // instead of a half-grid jump. (Neighbour-edge magnetism stays commit-only:
        // its candidates would need per-frame store reads — freeze law.)
        let frontX = isFrontResizing ? TimelineDragMath.frontTrimPreviewDeltaX(
            rawDeltaX: frontDelta, startTick: region.startTick, endTick: region.endTick,
            contentOffsetTicks: region.contentOffsetTicks,
            contentOffsetSeconds: region.contentOffsetSeconds, ppb: ppb, snap: snap,
            neighbourEdges: neighbourEdges) : 0   // #56 C8 butt-join (left edge)
        let resizeW = isResizing ? TimelineDragMath.trailingTrimPreviewDeltaW(
            rawDeltaX: resizeDelta, lengthTicks: region.lengthTicks, ppb: ppb, snap: snap,
            neighbourEdges: neighbourEdges, startTick: region.startTick) : 0   // #56 C7 butt-join
        // Gate-aware (#56 MEDIUM #2): a row the store refuses (kind mismatch /
        // out of bounds / bio) previews as NO shift — release is a visual no-op
        // instead of a jump-back. Computed FIRST because the horizontal preview
        // below suppresses edge magnetism on a lane change (commit parity).
        let rowShift = isMoving ? TimelineDragMath.gatedLaneShift(
            fromPoints: moveDelta.height, laneHeight: laneHeight,
            laneIndex: laneIndex, gates: laneGates) : 0
        // #56 C6: preview the SAME neighbour-edge magnetism the release commits,
        // fed by the parent-captured `neighbourEdges` (no store read in this leaf).
        // On a lane change the commit uses plain grid, so drop the edges here too.
        let moveX = isMoving ? TimelineDragMath.movePreviewDeltaX(
            rawDeltaX: moveDelta.width, startTick: region.startTick, ppb: ppb, snap: snap,
            neighbourEdges: rowShift == 0 ? neighbourEdges : [],
            lengthTicks: region.lengthTicks) : 0
        let x = CGFloat(region.startTick) / CGFloat(TimelineTime.ticksPerBeat) * ppb + frontX + moveX
        let w = max(6, CGFloat(region.lengthTicks) / CGFloat(TimelineTime.ticksPerBeat) * ppb - 2 + resizeW - frontX)
        let clip = clips.clip(id: region.clipID)
        let name = clip?.name ?? "Clip"
        // Tap an AUDIO region = hear ITS window immediately (founder: "Audio mit direkt
        // die wav Dateien vorhören") — H13: streams via the audition sink from the
        // region's contentOffset for the region's length (pro-DAW), not file-start.
        let auditionURL = clip?.kind == .audio ? resolvedMediaURL : nil   // C5: cached, no per-frame probe
        // Long-press a region opens its editor (only kinds with a real engine offer one).
        let editableKind = clip.map { $0.kind == .midi || $0.kind == .audio } ?? false
        let tint = ArrangeTimelineView.kindTint(clip?.kind)
        // TYPE-CHECK BUDGET (v280 deploy red, exit 65 "unable to type-check this
        // expression in reasonable time" HERE): this body was ONE ~140-line generic
        // expression carrying every closure (waveform, ring, grips, tap, context
        // menu, a11y). It sat exactly at the compiler's limit — green on one runner,
        // red on the next. The heavy closures now live in named helpers below; the
        // chain stays, the inference load per expression collapses. Behavior-identical.
        return RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(0.14))
            .overlay { audioWaveformOverlay(isAudio: clip?.kind == .audio) }
            .overlay(selectionRing(tint: tint))
            .overlay(alignment: .topLeading) { nameTag(name) }
            .overlay(alignment: .leading) { frontTrimHandle(tint: tint) }
            .overlay(alignment: .trailing) { trailingTrimHandle(tint: tint) }
            .frame(width: w, height: laneHeight - 8)
            // Vertical move previews ROW-snapped (the lane the release will land on),
            // not free-floating — the drop target is visible while dragging (#56 C4).
            .offset(x: x, y: 4 + CGFloat(rowShift) * laneHeight)
            // While dragging, float this clip above its lane siblings so it never
            // slides "under" a neighbouring region.
            .zIndex(isMoving ? 10 : 0)
            // C4: a light haptic tick when a drop actually snapped (grid or neighbour
            // edge). Leaf modifier — the root sheet chain is untouched (metadata law).
            .sensoryFeedback(.impact(weight: .light), trigger: snapPulse)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            // Performance mode (founder 2026-07-17): a launch play/stop glyph on
            // every launchable clip — MIDI and, since S3b, AUDIO (the override
            // backend S1–S3a is wired + reviewed). Drawn on top so its Button wins
            // taps in its 28 pt circle; the state lives in the ClipLaunchGlyph LEAF
            // (freeze law — launchGeneration is read there, never here). EmptyView
            // otherwise, so Performance OFF is behavior-identical.
            .overlay(alignment: .center) {
                launchGlyphOverlay(isLaunchable: clip?.kind == .midi || clip?.kind == .audio)
            }
            // Drag-to-move on the clip BODY (clip game C1 — founder: "seamless workflow,
            // kein unbeholfenes Rumdrücken"): grab and slide. The trim grips are child
            // overlays drawn on top, so they keep winning their 22 pt edge zones; an
            // 8 pt minimum distance keeps a plain TAP falling through to audition and a
            // stationary long-press opening the context menu. Same dedicated-drag
            // pattern the trim handles proved against the scrolling grid (device-
            // verified) — the store call is the ONE command EchoelAI will also use.
            // Performance mode suspends this move (`.subviews` mask) so the launch
            // glyph tap is unambiguous — the clip is a trigger, not a draggable then.
            .gesture(moveGesture, including: performanceMode ? .subviews : .all)
            .onTapGesture { handleTap(auditionURL: auditionURL) }
            .contextMenu { regionMenu(editableKind: editableKind) }
            .accessibilityLabel("\(name), bar \(region.startTick / TimelineTime.ticksPerBar + 1)")
            .accessibilityHint(
                [auditionURL != nil ? "Tap to play this audio clip" : nil,
                 "Drag to move",
                 "Long-press for options",
                 editableKind ? "Edit" : nil,
                 "Delete region"]
                    .compactMap { $0 }.joined(separator: ". ")
            )
            // C5: resolve once per mediaRef (re-runs when an import swaps the ref;
            // nil id for non-audio clips resolves to nil). Leaf modifier — the root
            // sheet chain is untouched.
            .task(id: clip?.kind == .audio ? clip?.mediaRef : nil) {
                resolvedMediaURL = clip?.kind == .audio
                    ? clip.flatMap(ArrangeTimelineView.mediaURL) : nil
            }
    }

    // MARK: body helpers (type-check budget — see the note at the top of `body`)

    /// Performance-mode launch glyph — for launchable clips: MIDI and (S3b) AUDIO.
    /// Video/bio do NOT launch (no override backend; bio also barred by `laneIsBio`).
    /// Own leaf so the launch-state observation stays out of this block's body
    /// (freeze law). The glyph is spur-agnostic — it only reads `launchState` and
    /// calls `launchRegion`/`stopLaunched`, both of which handle audio lanes.
    @ViewBuilder
    private func launchGlyphOverlay(isLaunchable: Bool) -> some View {
        if performanceMode, isLaunchable, !laneIsBio {
            ClipLaunchGlyph(regionID: region.id, laneID: region.laneID,
                            quantize: launchQuantize)
        }
    }

    @ViewBuilder
    private func audioWaveformOverlay(isAudio: Bool) -> some View {
        if isAudio, let url = resolvedMediaURL {
            FileWaveformView(url: url, tint: EchoelTheme.text)
                .padding(.horizontal, 3).padding(.vertical, 8)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Selected (C3) = accent ring; moving = full-strength tint; idle = subtle.
    private func selectionRing(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isSelected ? EchoelTheme.accent : tint.opacity(isMoving ? 1.0 : 0.55),
                          lineWidth: isSelected ? 2 : 1)
    }

    private func nameTag(_ name: String) -> some View {
        Text(name)
            .font(EchoelTheme.font(9, .medium))
            .foregroundStyle(EchoelTheme.text)
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.top, 3)
    }

    /// Leading trim handle (founder 2026-07-15 "auch vorne"): mirror of the
    /// trailing grip. Moves the front edge; the right edge stays fixed, media
    /// stays put. Released → snapped + committed via trimRegionStart.
    private func frontTrimHandle(tint: Color) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: 22)
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.opacity(isFrontResizing ? 0.9 : 0.5))
                .frame(width: 4, height: laneHeight - 20)
                .padding(.leading, 3)
        }
        .contentShape(Rectangle())
        // Performance mode suspends trimming (`.subviews` mask) — the clip is a
        // live trigger then, not an editable region.
        .gesture(frontResizeGesture, including: performanceMode ? .subviews : .all)
    }

    /// Trailing trim handle (B11): a fat invisible grab zone + a thin grip.
    /// The drag starts on this dedicated zone so it wins over the horizontal
    /// ScrollView. Live width tracks the finger; released → snapped + committed.
    private func trailingTrimHandle(tint: Color) -> some View {
        ZStack(alignment: .trailing) {
            Color.clear.frame(width: 22)
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.opacity(isResizing ? 0.9 : 0.5))
                .frame(width: 4, height: laneHeight - 20)
                .padding(.trailing, 3)
        }
        .contentShape(Rectangle())
        // Performance mode suspends trimming (`.subviews` mask) — see frontTrimHandle.
        .gesture(resizeGesture, including: performanceMode ? .subviews : .all)
    }

    /// Select mode (C3): tap marks/unmarks; otherwise tap auditions audio.
    private func handleTap(auditionURL: URL?) {
        if selectMode { onSelectToggle(); return }
        guard timeline.document.effectiveGain(for: region.laneID) > 0 else { return }
        if let url = auditionURL,
           let window = AudioRegionPlayback.auditionWindow(
               for: region, bpm: beatPlayer.pattern.tempo,
               transportPlaying: beatPlayer.pattern.isPlaying) {
            beatPlayer.audition(url: url, fromSeconds: window.fromSeconds,
                                lengthSeconds: window.lengthSeconds)
        }
    }

    /// The clip's long-press menu. Split / Join, ON THE CLIP (founder 2026-07-15).
    /// Both read transport.position / the document ONLY here (menu builds on open).
    /// Split cuts at the playhead when it sits INSIDE this clip; otherwise it
    /// halves the clip. Without the fallback, re-splitting a piece "ging nicht"
    /// (founder 2026-07-15): after a cut the playhead rests on the new boundary,
    /// where `split(at:)` is a no-op for both pieces — so "Split" did nothing.
    /// Now it always divides the clip the founder long-pressed.
    @ViewBuilder
    private func regionMenu(editableKind: Bool) -> some View {
        if editableKind {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            Button { onAutomation() } label: {
                Label("Automation", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
            }
        }
        Button {
            let playTick = TimelineTime.tick(fromAbsoluteStep: transport.position.absoluteStep)
            let inside = playTick > region.startTick && playTick < region.endTick
            let cut = inside ? playTick : region.startTick + region.lengthTicks / 2
            timeline.splitRegion(id: region.id, atTick: cut, bpm: beatPlayer.pattern.tempo)
        } label: {
            Label("Split", systemImage: "scissors")
        }
        Button {
            timeline.mergeRegionWithNext(id: region.id, bpm: beatPlayer.pattern.tempo)
        } label: {
            Label("Join with next", systemImage: "arrow.triangle.merge")
        }
        .disabled(!timeline.canMergeRegionWithNext(id: region.id, bpm: beatPlayer.pattern.tempo))
        Button {
            let tick = TimelineTime.tick(fromAbsoluteStep: transport.position.absoluteStep)
            timeline.moveRegion(id: region.id, toStartTick: tick,
                                bpm: beatPlayer.pattern.tempo)   // C5 overlap rule
        } label: {
            Label("Move to playhead", systemImage: "arrow.right.to.line")
        }
        Button {
            timeline.duplicateRegion(id: region.id)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            timeline.removeRegion(id: region.id)
        } label: {
            Label("Delete region", systemImage: "trash")
        }
    }

    /// Trailing-edge trim (B11) — live width tracks the finger via this clip's OWN
    /// `resizeDelta` (leaf-local, no root churn); on release the new length is
    /// snapped to the grid (`.off` = stepless) and committed. Floored at one step.
    /// Jitter audit #56 C1: the drag measures in the STABLE grid space — the live
    /// width change is a `.frame(width:)` LAYOUT shift that moves this trailing
    /// handle's own `.local` space every frame, so a local-space translation fed
    /// back into itself (r(n+1) = d − r(n)) and the right edge vibrated at display
    /// rate under a resting finger. Grid-space translation is pure finger delta.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 3,
                    coordinateSpace: .named(ArrangeTimelineView.playheadSpace))
            .updating($resizeDelta) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let raw = region.lengthTicks + deltaTicks
                // #56 C7: the trailing edge magnetizes to neighbour clip edges
                // (butt-join), same feel as the move edge-magnet — candidates read
                // here in the action (never body — freeze rule), each expressed as
                // a length from our start so OUR end lands on the edge. Parity with
                // trailingTrimPreviewDeltaW (same neighbourEdges, minus startTick).
                let magnetTicks = Int((8.0 / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let candidates = timeline.document.regions(in: region.laneID)
                    .filter { $0.id != region.id }
                    .flatMap { [$0.startTick, $0.endTick] }
                    .map { $0 - region.startTick }
                let snapped = TimelineSnap.snapWithEdges(raw, to: snap,
                                                         edges: candidates, magnetTicks: magnetTicks)
                timeline.resizeRegion(
                    id: region.id,
                    lengthTicks: max(TimelineTime.ticksPerTransportStep, snapped))
                if snapped != raw { snapPulse += 1 }   // fühlbares Einrasten (C7)
            }
    }

    /// Drag-to-move (clip game C1) — the whole clip follows the finger live via this
    /// clip's OWN `moveDelta` (leaf-local, no root churn); on release the new start tick is
    /// snapped (`.off` = stepless) and a vertical pull of ≥ half a lane row moves the
    /// clip to that same-kind lane (the store enforces the kind check). ONE store
    /// command — the same call the context menu's "Move to playhead" and, later, the
    /// EchoelAI edit tools use.
    private var moveGesture: some Gesture {
        // Grid space + @GestureState (jitter audit C1/C2) — see resizeGesture.
        DragGesture(minimumDistance: 8,
                    coordinateSpace: .named(ArrangeTimelineView.playheadSpace))
            .updating($moveDelta) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let rawStart = Swift.max(0, region.startTick + deltaTicks)
                // Same gate as the live preview (parity: preview == commit) — an
                // illegal vertical pull commits as a pure time move AND therefore
                // correctly takes the same-lane edge-magnetism branch below.
                let laneShift = TimelineDragMath.gatedLaneShift(
                    fromPoints: value.translation.height,
                    laneHeight: ArrangeTimelineView.laneHeight,
                    laneIndex: laneIndex, gates: laneGates)
                let committed: Int
                if laneShift == 0 {
                    // C4 edge magnetism: within ~8 screen-points, the drop kisses a
                    // neighbour clip's edge — start-to-edge AND end-to-edge (candidate
                    // `edge - length` lands OUR end on the edge). Grid still applies;
                    // the nearer pull wins. Neighbours read here in the action (never
                    // in body — freeze rule).
                    let magnetTicks = Int((8.0 / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                    let candidates = timeline.document.regions(in: region.laneID)
                        .filter { $0.id != region.id }
                        .flatMap { [$0.startTick, $0.endTick] }
                        .flatMap { [$0, $0 - region.lengthTicks] }
                    committed = TimelineSnap.snapWithEdges(rawStart, to: snap,
                                                           edges: candidates,
                                                           magnetTicks: magnetTicks)
                } else {
                    // Lane change: plain grid snap (edge candidates of another lane are
                    // a later refinement).
                    committed = snap == .off ? rawStart : TimelineSnap.snap(rawStart, to: snap)
                }
                // bpm engages the C5 overlap rule: the dropped clip wins — neighbours
                // trim/split/vanish to make room, all in this one undo step.
                timeline.moveRegion(id: region.id, toStartTick: committed,
                                    laneOffset: laneShift, bpm: beatPlayer.pattern.tempo)
                if committed != rawStart { snapPulse += 1 }   // fühlbares Einrasten (C4)
            }
    }

    /// Leading-edge trim (founder 2026-07-15 "auch vorne") — live x/width track the
    /// finger via this clip's OWN `frontDelta` (leaf-local, no root churn); on release the new
    /// start tick is snapped and committed via `trimRegionStart`, which holds the end
    /// fixed and shifts the media offset so content stays put (clamped in the model).
    private var frontResizeGesture: some Gesture {
        // Grid space + @GestureState (jitter audit C1/C2) — see resizeGesture.
        // (The front handle rode `.offset`, a render transform that does NOT move
        // layout space, so it never self-oscillated — but the stable space also
        // protects it against future layout changes, and cancel-reset applies.)
        DragGesture(minimumDistance: 3,
                    coordinateSpace: .named(ArrangeTimelineView.playheadSpace))
            .updating($frontDelta) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let rawStart = region.startTick + deltaTicks
                // #56 C8: the leading edge magnetizes to neighbour clip edges
                // (butt-join), same feel as move/trailing — candidates read here in
                // the action (never body — freeze rule). trimRegionStart still applies
                // the media/end clamp, so preview == commit for any proposed start.
                let magnetTicks = Int((8.0 / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let candidates = timeline.document.regions(in: region.laneID)
                    .filter { $0.id != region.id }
                    .flatMap { [$0.startTick, $0.endTick] }
                let snapped = TimelineSnap.snapWithEdges(rawStart, to: snap,
                                                         edges: candidates, magnetTicks: magnetTicks)
                timeline.trimRegionStart(id: region.id, toTick: max(0, snapped),
                                         bpm: beatPlayer.pattern.tempo)
                if snapped != rawStart { snapPulse += 1 }   // fühlbares Einrasten (C8)
            }
    }
}

/// Per-lane Sound & FX (founder 2026-07-12: settings live ON the tracks). Edits
/// the MELODIC bus insert via the same TrackFXStore the Mix menu uses, applied
/// LIVE to ALL melodic voices on every change: primary synth+leadSynth AND every
/// Multi-Roll rack slot voice (S2-W1) — so it reaches the very lane this editor
/// opened for. One source of truth, two doors; still ONE shared melodic bus.
@MainActor
private struct LaneFXEditor: View {
    let laneName: String
    /// B2: the lane whose persisted pan this editor adjusts (TimelineStore).
    let laneID: UUID
    @Environment(TrackFXStore.self) private var trackFX
    @Environment(PolySynthVoice.self) private var synth
    @Environment(\.leadSynth) private var leadSynth
    /// S2-W1: the Multi-Roll slot voices — this track's own voice IS a rack
    /// voice for secondary lanes, so the insert must reach the rack too.
    @Environment(LaneVoiceRack.self) private var laneVoiceRack
    @Environment(TimelineStore.self) private var timeline
    /// S2-W3: the EchoelSampler track's sample picker — a sheet ON this already-
    /// presented editor (its own modifier on the sheet CONTENT, so the root modal
    /// chain does not grow — the metadata law).
    @State private var showSampleBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sound & FX — \(laneName)")
                    .font(EchoelTheme.font(15, .semibold)).foregroundStyle(EchoelTheme.text)
                Text("Filter + drive on the melodic bus — the roll's voices, live")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }

            Picker("Filter", selection: filterBinding) {
                ForEach(ChannelInsertFX.FilterType.allCases, id: \.self) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)

            EchoelValueField(label: "Cutoff",
                             value: floatBinding(\.cutoffHz),
                             range: 40...18_000, unit: "Hz", decimals: 0)
            EchoelValueField(label: "Resonance",
                             value: floatBinding(\.resonance),
                             range: Float(0.3)...Float(4), decimals: 2)
            EchoelValueField(label: "Drive",
                             value: floatBinding(\.drive),
                             range: Float(0)...Float(1), decimals: 2)
            // B2 stereo position: persisted on the LANE (TimelineStore); the
            // Arrange surface's rollSlotPan binding pushes it into both melodic
            // voices at the mixer. −1 = left, 0 = center, +1 = right.
            EchoelValueField(label: "Pan",
                             value: panBinding,
                             range: Float(-1)...Float(1), decimals: 2)
            // Per-instrument TRANSPOSE (founder 2026-07-14): shift THIS track's pitch in
            // whole semitones (e.g. bass −12, a layer +7). Per-lane + saved with the song,
            // like Pan; the voice is pitched on load. The keypad's −/+ sign keys make it
            // easy to go below/above 0.
            EchoelValueField(label: "Transpose",
                             value: transposeBinding,
                             range: Float(-48)...Float(48), unit: "st", decimals: 0)
            // Per-instrument DETUNE (founder 2026-07-14 "transpose detune"): fine cents
            // offset — sit this track a few cents sharp/flat for analog thickening or a
            // beating detune against another track. Per-lane, saved with the song.
            EchoelValueField(label: "Detune",
                             value: detuneBinding,
                             range: Float(-100)...Float(100), unit: "¢", decimals: 0)
            // Per-instrument OKTAVER (founder 2026-07-14 "transpose detune und Oktaver"):
            // double this track's notes an octave up (+1) or down (−1). Per-lane, saved
            // with the song; the doubled voice plays at half level (engine default).
            EchoelValueField(label: "Octave",
                             value: octaveBinding,
                             range: Float(-1)...Float(1), decimals: 0)

            // EchoelSampler track (S2-W3): the ONE sample this lane's sampler unit
            // plays. Opens the SAME browser as the B5 drum-pad door, in lane mode
            // (the completion returns a persistable ref → TimelineStore). Document-
            // level reads only — this sheet never touches a 10 Hz observable
            // (freeze law); the picker sheet stacks on THIS sheet's content.
            if timeline.document.lanes.first(where: { $0.id == laneID })?.builtinInstrument == .sampler {
                HStack {
                    Text("Sample")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    Spacer()
                    Button {
                        showSampleBrowser = true
                    } label: {
                        Text(BeatPlayer.sampleRefDisplayName(
                            timeline.document.lanes.first(where: { $0.id == laneID })?.samplePath)
                            ?? "No sample")
                            .font(EchoelTheme.font(13, .semibold))
                            .foregroundStyle(EchoelTheme.accent)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sample for \(laneName)")
                }
                .sheet(isPresented: $showSampleBrowser) {
                    AnyView(SampleBrowserView(track: 0, onUse: { ref in
                        timeline.setLaneSample(laneID, path: ref)
                    }).echoelSheetPanel())
                }
            }

            // A2 "alles in ein Instrument" (founder 2026-07-17): per-track
            // COMPOSITION — genre / mood / variation overrides. Secondary MIDI
            // lanes only: the FIRST MIDI lane IS the primary take (the roll),
            // its composition is the song's global Composition panel. Own leaf
            // struct (type-check budget) with document-level reads only.
            if isSecondaryMidiLane {
                LaneCompositionSection(laneName: laneName, laneID: laneID)
            }

            Text("Filter/drive: same setting as Mix › Melodic — changed here, it changes there. Full-open cutoff with filter Off and drive 0 means: untouched sound. Pan, Transpose, Detune and Octave are this track's own and are saved with the song (Pan 0 = center, Transpose 0 = no pitch shift, Detune 0 = in tune, Octave −1/+1 = add a doubled voice an octave down/up, 0 = off).")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EchoelTheme.bg)
    }

    /// A SECONDARY MIDI lane: MIDI, not bio, and not the roll slot (the FIRST
    /// non-bio MIDI lane — that one is the primary take; `applyLaneOverrides`
    /// excludes it, so its panel must not offer per-track composition either).
    /// Document-level read only (freeze law).
    private var isSecondaryMidiLane: Bool {
        let lanes = timeline.document.lanes
        guard let lane = lanes.first(where: { $0.id == laneID }),
              lane.kind == .midi, !lane.isBio else { return false }
        return lanes.first(where: { $0.kind == .midi && !$0.isBio })?.id != laneID
    }

    /// Write-through: store (persists + Mix panel follows) AND all live melodic
    /// voices — primary synth+lead plus every rack slot voice (S2-W1), so the
    /// edit audibly reaches the very lane whose editor this is.
    private func apply(_ fx: TrackFX) {
        trackFX.set(fx, for: .melodic)
        synth.setInsert(fx)
        leadSynth?.setInsert(fx)
        laneVoiceRack.setInsert(fx)
    }

    private var filterBinding: Binding<ChannelInsertFX.FilterType> {
        Binding(get: { trackFX.melodic.filter },
                set: { t in
                    var fx = trackFX.melodic
                    fx.filter = t
                    apply(fx)
                })
    }

    private func floatBinding(_ key: WritableKeyPath<TrackFX, Float>) -> Binding<Float> {
        Binding(get: { trackFX.melodic[keyPath: key] },
                set: { v in
                    var fx = trackFX.melodic
                    fx[keyPath: key] = v
                    apply(fx)
                })
    }

    /// B2: lane pan lives in the timeline document (per-lane, persisted); the
    /// engine follows via the surface's rollSlotPan onChange — no direct voice
    /// write here, ONE push path.
    private var panBinding: Binding<Float> {
        Binding(get: { timeline.document.lanes.first(where: { $0.id == laneID })?.pan ?? 0 },
                set: { timeline.setLanePan(id: laneID, $0) })
    }

    /// Per-instrument transpose (semitones) lives on the lane (persisted, ±48). The
    /// region player pitches this lane's voice on load — one push path, like pan.
    /// Bridged through Float for EchoelValueField (the app's one parameter control),
    /// rounded back to a whole semitone on write.
    private var transposeBinding: Binding<Float> {
        Binding(get: { Float(timeline.document.lanes.first(where: { $0.id == laneID })?.transposeSemitones ?? 0) },
                set: { timeline.setLaneTranspose(id: laneID, Int($0.rounded())) })
    }

    /// Per-instrument detune (cents) lives on the lane (persisted, ±100). The region
    /// player detunes this lane's voice on load — one push path, like transpose/pan.
    private var detuneBinding: Binding<Float> {
        Binding(get: { timeline.document.lanes.first(where: { $0.id == laneID })?.detuneCents ?? 0 },
                set: { timeline.setLaneDetune(id: laneID, $0) })
    }

    /// Per-instrument Oktaver direction lives on the lane (persisted, −1/0/+1). The
    /// region player octaves this lane's voice on load — one push path, like detune.
    /// Bridged through Float for EchoelValueField, rounded back to a whole step.
    private var octaveBinding: Binding<Float> {
        Binding(get: { Float(timeline.document.lanes.first(where: { $0.id == laneID })?.octaveDouble ?? 0) },
                set: { timeline.setLaneOctave(id: laneID, Int($0.isFinite ? $0.rounded() : 0)) })
    }
}

/// A2 "Composition (this track)" (founder 2026-07-17 "Genre, Sound, Mix, FX,
/// Mood, Synth kommt alles in ein Instrument"): per-track genre / mood /
/// variation overrides for a SECONDARY MIDI lane. Setting an override is the
/// EXPLICIT act that also creates this lane's composer-owned "Composed" clip +
/// region (ensureComposerRegion) — from then on every Generate/Evolve rewrites
/// that clip in this lane's own character (Slice A fan-out), never a user clip.
///
/// Own leaf struct: keeps LaneFXEditor's body inside the type-check budget
/// (ArrangeTimelineView exit-65 history) and reads ONLY document-level state —
/// no 10 Hz observable anywhere near this sheet (freeze law). Mood offers the
/// curated MoodPreset.factory names (pick a feeling, not 8 dials — per-dimension
/// fine-tuning is a deliberate later slice).
///
/// Internal (not private): re-hosted by `BodyVibeSurfaceView` so the bioVoice
/// track's own genre/mood/variation live there too (founder 2026-07-20 "Genre
/// Auswahl kommt auch in EchoelBodyVibe"). Same leaf, two hosts — one control.
@MainActor
struct LaneCompositionSection: View {
    let laneName: String
    let laneID: UUID
    @Environment(TimelineStore.self) private var timeline
    @Environment(ClipStore.self) private var clips
    /// The active loop window the composer cycles — same key/default as the
    /// semantic owner EchoelStudioView.loopBars (pattern: FloatingVisualWindow).
    @AppStorage(StudioDefaultKeys.loopBars.key) private var loopBars: LoopBarLength = StudioDefaultKeys.loopBars.value
    /// Honest feedback when the 8-slot clip grid is full (ensureComposerRegion
    /// refuses rather than displacing a user clip).
    @State private var gridFullWarning = false
    /// REIHENFOLGE #4 "alles in die Spur": the full 8-dial mood fine-tune is
    /// collapsed by default so the composition rows stay compact.
    @State private var showMoodDials = false

    private static let songTag = "song"
    private static let customTag = "custom"

    private var lane: TimelineLane? {
        timeline.document.lanes.first(where: { $0.id == laneID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(EchoelTheme.dim.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Composition (this track)")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                Text("Own genre, mood and variation — \"Song\" follows the global take")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
            genreRow
            moodRow
            moodFineTune
            variationRow
            if gridFullWarning {
                Text("Clip grid full (\(ClipStore.slotCount) slots) — clear a slot so this track can get its own \"Composed\" clip.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Changes sound from the next Generate/Evolve. The track gets its own \"Composed\" clip for this — the composer rewrites only that clip, never your own clips.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Rows

    private var genreRow: some View {
        HStack {
            Text("Genre")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            Spacer()
            Picker("Genre", selection: genreBinding) {
                Text("Song").tag(MusicStyle?.none)
                // Same grouped roster as the global Genre picker (WorkspaceView).
                ForEach(MusicStyle.Category.allCases) { cat in
                    Section(cat.title) {
                        ForEach(cat.genres) { s in
                            Text(s.displayName).tag(MusicStyle?.some(s))
                        }
                    }
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.accent)
            .accessibilityLabel("Genre for \(laneName)")
        }
    }

    private var moodRow: some View {
        HStack {
            Text("Mood")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            Spacer()
            Picker("Mood", selection: moodBinding) {
                Text("Song").tag(Self.songTag)
                ForEach(MoodPreset.factory) { p in
                    Text(p.name).tag(p.id.uuidString)
                }
                // A stored profile that matches no factory preset (e.g. set by a
                // future fine-tune slice) still renders a valid selection.
                if moodSelection == Self.customTag {
                    Text("Custom").tag(Self.customTag)
                }
            }
            .pickerStyle(.menu).tint(EchoelTheme.accent)
            .accessibilityLabel("Mood for \(laneName)")
        }
    }

    /// Per-track FULL mood fine-tune (REIHENFOLGE #4 "alles in die Spur"): the same
    /// 8 dimensions the global Mood panel edits, now on the lane itself via
    /// `EchoelValueField` (the one parameter control). Collapsed by default. Editing
    /// any dial gives THIS lane its own `MoodProfile` — `moodRow` then reads "Custom",
    /// and its "Song" option reverts to following the global take. Lane fields are not
    /// in undo history, so a dial drag persists without spamming it.
    private var moodFineTune: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showMoodDials.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showMoodDials ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Fine-tune mood").font(EchoelTheme.font(12, .semibold))
                    Spacer()
                }
                .foregroundStyle(EchoelTheme.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fine-tune the eight mood dimensions for \(laneName)")
            if showMoodDials {
                moodDial("Liveliness", \.liveliness)
                moodDial("Darkness", \.darkness)
                moodDial("Tension", \.tension)
                moodDial("Romance", \.romance)
                moodDial("Weird", \.weird)
                moodDial("Virtuosity", \.virtuosity)
                moodDial("Syncopation", \.syncopation)
                moodDial("Humanize", \.humanize)
            }
        }
    }

    /// A live binding to ONE dimension of this lane's mood. Reads fall back to a
    /// neutral `MoodProfile()` while the lane still follows the song (`mood == nil`);
    /// writing any dial gives the lane its own profile.
    private func moodDial(_ label: String, _ keyPath: WritableKeyPath<MoodProfile, Float>) -> some View {
        let binding = Binding<Float>(
            get: { (lane?.mood ?? MoodProfile())[keyPath: keyPath] },
            set: { v in
                var profile = lane?.mood ?? MoodProfile()
                profile[keyPath: keyPath] = v
                timeline.setLaneMood(laneID, mood: profile)
            }
        )
        // On release (or keypad commit) guarantee this lane owns a composer clip+
        // region so the mood is audible — the SAME explicit-override contract the
        // genre / mood-preset / variation setters follow. Done on commit, not per
        // drag delta, so a scrub doesn't re-run ensureComposerRegion each tick.
        return EchoelValueField(label: label, value: binding, range: 0...1,
                                onCommit: { ensureComposedClip() })
    }

    private var variationRow: some View {
        HStack(spacing: 10) {
            Text("Variation")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            Spacer()
            if let seed = lane?.variationSeed {
                Text(Self.seedLabel(seed))
                    .font(EchoelTheme.font(12, .semibold).monospaced())
                    .foregroundStyle(EchoelTheme.text)
                Button("Song") { timeline.setLaneVariationSeed(laneID, seed: nil) }
                    .font(EchoelTheme.font(12))
                    .buttonStyle(.plain).foregroundStyle(EchoelTheme.dim)
                    .accessibilityLabel("Variation follows the song")
            } else {
                Text("Song")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            }
            Button { rollVariationSeed() } label: {
                Image(systemName: "dice")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Roll a new variation for \(laneName)")
        }
    }

    // MARK: Bindings + actions

    private var genreBinding: Binding<MusicStyle?> {
        Binding(get: { timeline.document.lanes.first(where: { $0.id == laneID })?.genreOverride },
                set: { newValue in
                    timeline.setLaneGenreOverride(laneID, genre: newValue)
                    if newValue != nil { ensureComposedClip() }
                })
    }

    /// Current mood as a stable picker tag: "song" (nil), a factory preset's id,
    /// or "custom" for a stored profile no factory preset matches.
    private var moodSelection: String {
        guard let mood = lane?.mood else { return Self.songTag }
        return MoodPreset.factory.first(where: { $0.profile == mood })?.id.uuidString
            ?? Self.customTag
    }

    private var moodBinding: Binding<String> {
        Binding(get: { moodSelection },
                set: { sel in
                    if sel == Self.songTag {
                        timeline.setLaneMood(laneID, mood: nil)
                    } else if let preset = MoodPreset.factory.first(where: { $0.id.uuidString == sel }) {
                        timeline.setLaneMood(laneID, mood: preset.profile)
                        ensureComposedClip()
                    }
                    // Re-selecting "Custom" keeps the stored profile untouched.
                })
    }

    /// Dice: a fresh random seed for THIS lane. UI-initiated randomness is fine —
    /// the ENGINE stays deterministic because the rolled seed is persisted on the
    /// lane and every Generate/Evolve replays it bit-identically.
    private func rollVariationSeed() {
        timeline.setLaneVariationSeed(laneID, seed: UInt64.random(in: UInt64.min...UInt64.max))
        ensureComposedClip()
    }

    /// The explicit override act also guarantees the composer-owned clip+region
    /// exists in the loop window (idempotent; honest refusal on a full grid).
    private func ensureComposedClip() {
        gridFullWarning = !timeline.ensureComposerRegion(for: laneID, clipStore: clips,
                                                         loopBars: max(1, loopBars.rawValue))
    }

    /// Short, stable seed display (8 hex digits of the high word) — enough to see
    /// "it changed" without spilling a 20-digit number into the row.
    private static func seedLabel(_ seed: UInt64) -> String {
        String(format: "%08X", UInt32(truncatingIfNeeded: seed >> 32))
    }
}

/// The moving playhead — its OWN leaf so the ~8 Hz Transport read rebuilds only
/// this 2-pt line, never the grid (freeze rule; pattern: ArrangementPlayhead).
@MainActor
private struct TimelinePlayhead: View {
    @Environment(Transport.self) private var transport
    /// CLIP-5: dropping the head while the SONG plays relocates the audio too.
    /// Read only in the drag's onEnded closure — never in body (freeze rule).
    @Environment(TimelineRegionPlayer.self) private var timelinePlayer
    let pointsPerBeat: CGFloat
    /// The active snap grid — the drag lands the playhead on bar/beat/8th/16th/off,
    /// the same magnet the regions use (founder 2026-07-15: "beim Schieben verbunden
    /// mit snap bar, Beat, 1/16, etc / off").
    let snap: SnapResolution
    /// Absolute x-name of the scrolling grid, so a drag's location maps to a tick
    /// regardless of horizontal scroll.
    let coordinateSpace: String

    /// While dragging the handle: the local override tick (lag-free visual, independent
    /// of the clock). nil = follow the transport.
    @State private var scrubTick: Int?

    /// Smooth-glide anchor (founder 2026-07-15 "läuft etwas unflüssig"): the transport
    /// advances only in 16th steps, so the head jumps. Between steps a 60 fps TimelineView
    /// interpolates from the wall-clock moment the CURRENT step began (`anchorAt`) toward
    /// the next step. Reset on every step change / play-start; at a loop wrap the step
    /// resets to 0 and the head snaps (no backward sweep — each frame draws the computed x).
    @State private var anchorStep: Int = 0
    @State private var anchorAt: Date = .distantPast

    /// Ticks per transport step (16th) — the seek granularity. 480 / 4 = 120.
    private static var ticksPerStep: Int { TimelineTime.ticksPerBeat / Transport.stepsPerBeat }
    /// Handle band height — matches the ruler so the grab tab sits in the ruler zone.
    private static let handleHeight: CGFloat = 26   // touch-target height (HIG)
    private static let markerWidth: CGFloat = 20    // visible flag width
    private static let markerHeight: CGFloat = 16   // visible flag height (tip meets the line)

    private var liveTick: Int { transport.position.absoluteStep * Self.ticksPerStep }

    /// One 16th-step in seconds at the live tempo — the glide window between steps.
    private var stepSeconds: Double { 60.0 / Swift.max(1, transport.tempo) / Double(Transport.stepsPerBeat) }

    /// The playhead tick to draw at `date`: the exact scrub/live tick when dragging or
    /// stopped; while playing, the anchor step plus the fraction of `stepSeconds` elapsed
    /// (clamped 0…1 so it never runs past the next step).
    private func glideTick(at date: Date) -> Double {
        if let s = scrubTick { return Double(s) }
        guard transport.isPlaying else { return Double(liveTick) }
        let frac = Swift.min(1.0, Swift.max(0.0, date.timeIntervalSince(anchorAt) / stepSeconds))
        return (Double(anchorStep) + frac) * Double(Self.ticksPerStep)
    }

    var body: some View {
        // Smooth playhead: a 60 fps TimelineView slides the head between 16th steps
        // (paused when not gliding, so idle it costs nothing). Only THIS leaf redraws —
        // the grid/menus never subscribe (freeze rule).
        let gliding = transport.isPlaying && scrubTick == nil
        let active = scrubTick != nil || transport.isPlaying
        let handleColor = scrubTick != nil ? EchoelTheme.accent
                                           : (transport.isPlaying ? EchoelTheme.accent : EchoelTheme.text)
        return TimelineView(.animation(paused: !gliding)) { tl in
            let x = CGFloat(glideTick(at: tl.date)) / CGFloat(TimelineTime.ticksPerBeat) * pointsPerBeat
            ZStack(alignment: .topLeading) {
                // The line — full height, thin, NON-hittable so it never blocks a region tap.
                Rectangle()
                    .fill(active ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
                // The grab handle — a flat-topped downward triangle sitting FLUSH at the very
                // top (y = 0), its tip meeting the line so the line drops straight out of the
                // point with NO gap (founder 2026-07-15 "Diese Lücke schließen"; the old
                // SF-Symbol left a stub of line above the glyph — that float was the gap).
                // A 44 pt clear frame stays the HIG touch target; the drawn marker is the
                // visible flag, centered on the 2 pt line. Only THIS is hittable → it wins
                // over the grid's horizontal ScrollView (dedicated-zone drag).
                ZStack(alignment: .top) {
                    Color.clear.frame(width: 44, height: Self.handleHeight)
                    PlayheadMarker()
                        .fill(handleColor)
                        .frame(width: Self.markerWidth, height: Self.markerHeight)
                }
                .contentShape(Rectangle())
                .offset(x: 1 - 22)   // center the 44-wide target on the 2 pt line (line centre x = 1)
                .gesture(dragGesture)
                .accessibilityLabel("Playhead — drag to move")
            }
            .offset(x: x)
        }
        // Re-anchor the glide on every step boundary and on play-start / appearance, so
        // interpolation always measures from the moment the current step actually began.
        .onChange(of: transport.position.absoluteStep) { _, s in
            anchorStep = s
            anchorAt = Date()
        }
        .onChange(of: transport.isPlaying) { _, playing in
            if playing { anchorStep = transport.position.absoluteStep; anchorAt = Date() }
        }
        .onAppear { anchorStep = transport.position.absoluteStep; anchorAt = Date() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
            .onChanged { g in
                let rawTick = Int((g.location.x / pointsPerBeat) * CGFloat(TimelineTime.ticksPerBeat))
                let snapped = TimelineSnap.snap(Swift.max(0, rawTick), to: snap)
                scrubTick = snapped
                seek(toTick: snapped)
            }
            .onEnded { _ in
                if let t = scrubTick {
                    seek(toTick: t)
                    // CLIP-5: while the arrangement plays, the DROP relocates the
                    // audio (bar-granular; no-op when stopped — play() picks the
                    // parked head up). Drag END only, never per drag frame — a
                    // continuous scrub through the relocate path is a voice-flush
                    // storm (HARNESS_LEDGER 2026-07-16).
                    timelinePlayer.relocate(toTick: t)
                    if timelinePlayer.isPlaying {
                        // Align the transport with the bar-granular jump (review
                        // MEDIUM): the seek above left lastStep at the snapped
                        // step, so a drop landing right before the pattern's
                        // 15→0 tick would count a PHANTOM wrap — visual head one
                        // bar ahead of the audio until Stop. Re-seek to the
                        // folded bar (step 0 ⇒ wrap accounting agrees in every
                        // phase; the next tick adopts the pattern phase anyway).
                        transport.seek(toBar: timelinePlayer.currentTick / TimelineTime.ticksPerBar)
                    }
                }
                scrubTick = nil
            }
    }

    /// Seek the transport to the nearest 16th step of `tick` (the clock is 16th-quantized).
    private func seek(toTick tick: Int) {
        let step = Int((Double(tick) / Double(Self.ticksPerStep)).rounded())
        transport.seek(toBar: step / Transport.stepsPerBar,
                       step: step % Transport.stepsPerBar)
    }
}

/// The playhead's grab flag — a flat-topped downward triangle. The flat edge sits at the
/// top (y = 0) and the tip at the bottom centre, so the playhead line drops straight out
/// of the tip with no gap between marker and line.
private struct PlayheadMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
#endif
