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

    /// Zoom: screen points per quarter-note beat (Stage 3 couples snap to this).
    @State private var pointsPerBeat: CGFloat = 24
    @GestureState private var pinch: CGFloat = 1
    /// Snap resolution — persisted; default 1/16 (research: snap ON by default).
    @AppStorage("timeline.snap") private var snapRaw = SnapResolution.sixteenth.rawValue

    // (Region trim state moved INTO RegionBlockView — each clip owns its own live
    //  resize @State so a drag re-renders only that clip, not the whole timeline.)

    // fileprivate: the extracted RegionBlockView leaf (same file) reuses laneHeight.
    fileprivate static let laneHeight: CGFloat = 56
    private static let labelWidth: CGFloat = 140
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
            if activeModal == nil { clipEdit = nil }
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
        case patch
        /// E2a: automation lanes, on the track. Re-doors AutomationView.
        case automation
        /// The Immersive Stage — the Touch surface that places every track in space.
        case spatial
        var id: String {
            switch self {
            case .lane(let l):   return "lane-\(l.id)"
            case .region(let r): return "region-\(r.id)"
            case .laneFX(let l): return "lanefx-\(l.id)"
            case .plugins:       return "plugins"
            case .patch:         return "patch"
            case .automation:    return "automation"
            case .spatial:       return "spatial"
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
            clipEdit = ClipEditSession(clipID: clip.id, bar: bar,
                                       totalBars: max(MelodyBarEdit.barCount(of: notes), bar + 1),
                                       model: model)
        }
        activeModal = .region(region)
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
                              title: session.totalBars > 1
                                  ? "Edit Clip — Bar \(session.bar + 1)/\(session.totalBars)"
                                  : "Edit Clip",
                              onDone: { commitClipEdit(session) })
            } else {
                editor(forKind: clips.clip(id: region.clipID)?.kind ?? .midi)
            }
        case .laneFX(let lane):   LaneFXEditor(laneName: lane.name, laneID: lane.id)
        case .plugins:            AUv3BrowserView()
        case .patch:
            // Opens on the sound that is actually playing (the voice's patch
            // memory). No onApply closure: the editor's env voice IS this
            // synth instance and already live-applies every change — a
            // closure here would double-enqueue each edit tick (review note).
            // Honest limit (multi-roll pending): this edits THE melodic
            // instrument all MIDI lanes share today.
            PatchEditorView(initial: synth.appliedPatch ?? SynthPatch(name: "Init"))
        case .automation:         AutomationView()
        case .spatial:            ImmersiveStageView()
        }
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
                        .fill(isSelecting ? EchoelTheme.accent : EchoelTheme.fill))
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

    // MARK: - Lane labels (fixed column, never scrolls away)

    private var laneLabels: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: Self.labelWidth, height: Self.rulerHeight)
            ForEach(timeline.document.lanes) { lane in
                laneHeader(lane)
            }
            Spacer(minLength: 0)
        }
        .background(EchoelTheme.bg)
    }

    /// One track head — a DOOR (Stage 3a) plus the K2a mixer strip (M · S ·
    /// level). The strip sits BELOW the menu label (buttons inside a Menu label
    /// never receive taps) and only on media lanes — the bio lane has no gain.
    private func laneHeader(_ lane: TimelineLane) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            laneDoor(lane)
            if !lane.isBio { laneMixStrip(lane) }
        }
        .frame(width: Self.labelWidth, height: Self.laneHeight)
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
            if !lane.isBio, lane.kind == .midi {
                Button { activeModal = .lane(lane) } label: {
                    Label("Open Piano Roll", systemImage: ClipKind.midi.systemImage)
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
                Button { activeModal = .patch } label: {
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
                Text(lane.name)
                    .font(EchoelTheme.font(10, .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
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
        if let inst = lane.instrument { parts.append("Instrument: \(inst.name)") }
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
        }
        // Fit the whole strip (record-arm · M · S · gain) inside the 140 pt lane
        // column: leading 8, tight 3 pt gaps, a 30 pt gain box (empty-label field =
        // box only now). Founder 2026-07-15: the old 40 pt box + label dead-space
        // overflowed → the record button + colour stripe clipped off the left edge.
        .padding(.leading, 8).padding(.trailing, 4)
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
    /// CLIP-2: sources TakeRecorder cannot capture yet (mic/video, task #13) render
    /// DISABLED with a "soon" hint — pre-fix the arm lit red, Record ran, and Stop
    /// silently committed nothing (a sung take was simply gone). The planner
    /// (`RecordPlan.targets`) is the second, engine-side layer of the same law.
    private func recordArmButton(_ lane: TimelineLane) -> some View {
        let source = lane.recordSource
        let capturable = source.captureImplemented
        return Button {
            timeline.toggleArm(id: lane.id)
        } label: {
            Image(systemName: (lane.isArmed && capturable) ? "record.circle.fill" : source.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle((lane.isArmed && capturable) ? EchoelTheme.onPrimary
                                 : EchoelTheme.dim.opacity(capturable ? 1 : 0.45))
                .frame(width: 21, height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .fill((lane.isArmed && capturable) ? EchoelTheme.danger : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!capturable)
        .accessibilityLabel(capturable
            ? "Arm \(source.displayName) recording, \(lane.name)"
            : "\(source.displayName) recording arrives soon, \(lane.name)")
        .accessibilityValue((lane.isArmed && capturable) ? "Armed" : "Off")
    }

    // MARK: - Grid (ruler + lanes + regions + playhead)

    private var grid: some View {
        VStack(spacing: 0) {
            ruler
            ForEach(timeline.document.lanes) { lane in
                laneRow(lane)
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

    /// Name of the grid's coordinate space (playhead drag → tick).
    private static let playheadSpace = "echoel.timeline.grid"

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
        ZStack(alignment: .topLeading) {
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
            ForEach(timeline.document.regions(in: lane.id)) { region in
                // Each region is its OWN leaf view that owns its live-resize @State —
                // so a trim drag re-renders ONLY that clip, never the whole timeline
                // (the old root-@State resize made every drag frame rebuild all lanes +
                // ruler + playhead → the "zittern" the founder saw, 2026-07-15).
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
                                onEdit: { openRegionEditor(region) })
            }
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
                activeModal = .lane(lane)
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
/// live-resize @State locally; commits the snapped length to the store on release.
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
    /// Opens this region's editor (the parent owns the one sheet slot).
    let onEdit: () -> Void

    @Environment(ClipStore.self) private var clips
    @Environment(TimelineStore.self) private var timeline
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(Transport.self) private var transport

    /// Live trailing-trim offset for THIS clip only (root no longer churns).
    @State private var resizeDelta: CGFloat = 0
    @State private var isResizing = false
    /// Live LEADING-trim offset for THIS clip (founder 2026-07-15 "auch vorne"): moving
    /// the left edge shifts x AND shrinks/grows the width, holding the right edge fixed.
    @State private var frontDelta: CGFloat = 0
    @State private var isFrontResizing = false
    /// Live DRAG-TO-MOVE offset (clip game C1, founder 2026-07-15 "seamless workflow"):
    /// grab the clip BODY and slide it — horizontally in time, vertically to another
    /// same-kind lane. Leaf state, so only this clip re-renders while dragging.
    @State private var moveDelta: CGSize = .zero
    @State private var isMoving = false
    /// Increments whenever a drop actually SNAPPED (grid or neighbour edge) — drives
    /// the `.sensoryFeedback` light tick (clip game C4: fühlbares Einrasten).
    @State private var snapPulse = 0

    private var laneHeight: CGFloat { ArrangeTimelineView.laneHeight }

    var body: some View {
        // Leading trim moves the left edge (x += frontDelta) and adjusts width the
        // opposite way so the RIGHT edge stays put; trailing trim adds to the width.
        // Drag-to-move shifts the WHOLE clip live (x + moveDelta.width, y follows the
        // finger toward another lane); width is untouched by a move.
        let x = CGFloat(region.startTick) / CGFloat(TimelineTime.ticksPerBeat) * ppb + frontDelta + moveDelta.width
        let w = max(6, CGFloat(region.lengthTicks) / CGFloat(TimelineTime.ticksPerBeat) * ppb - 2 + resizeDelta - frontDelta)
        let clip = clips.clip(id: region.clipID)
        let name = clip?.name ?? "Clip"
        // Tap an AUDIO region = hear ITS window immediately (founder: "Audio mit direkt
        // die wav Dateien vorhören") — H13: streams via the audition sink from the
        // region's contentOffset for the region's length (pro-DAW), not file-start.
        let auditionURL = clip.flatMap { $0.kind == .audio ? ArrangeTimelineView.mediaURL($0) : nil }
        // Long-press a region opens its editor (only kinds with a real engine offer one).
        let editableKind = clip.map { $0.kind == .midi || $0.kind == .audio } ?? false
        let tint = ArrangeTimelineView.kindTint(clip?.kind)
        return RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(0.14))
            .overlay {
                if let clip, clip.kind == .audio, let url = ArrangeTimelineView.mediaURL(clip) {
                    FileWaveformView(url: url, tint: EchoelTheme.text)
                        .padding(.horizontal, 3).padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                // Selected (C3) = accent ring; moving = full-strength tint; idle = subtle.
                .strokeBorder(isSelected ? EchoelTheme.accent : tint.opacity(isMoving ? 1.0 : 0.55),
                              lineWidth: isSelected ? 2 : 1))
            .overlay(alignment: .topLeading) {
                Text(name)
                    .font(EchoelTheme.font(9, .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.top, 3)
            }
            .overlay(alignment: .leading) {
                // Leading trim handle (founder 2026-07-15 "auch vorne"): mirror of the
                // trailing grip. Moves the front edge; the right edge stays fixed, media
                // stays put. Released → snapped + committed via trimRegionStart.
                ZStack(alignment: .leading) {
                    Color.clear.frame(width: 22)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(isFrontResizing ? 0.9 : 0.5))
                        .frame(width: 4, height: laneHeight - 20)
                        .padding(.leading, 3)
                }
                .contentShape(Rectangle())
                .gesture(frontResizeGesture)
            }
            .overlay(alignment: .trailing) {
                // Trailing trim handle (B11): a fat invisible grab zone + a thin grip.
                // The drag starts on this dedicated zone so it wins over the horizontal
                // ScrollView. Live width tracks the finger; released → snapped + committed.
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: 22)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(isResizing ? 0.9 : 0.5))
                        .frame(width: 4, height: laneHeight - 20)
                        .padding(.trailing, 3)
                }
                .contentShape(Rectangle())
                .gesture(resizeGesture)
            }
            .frame(width: w, height: laneHeight - 8)
            .offset(x: x, y: 4 + moveDelta.height)
            // While dragging, float this clip above its lane siblings so it never
            // slides "under" a neighbouring region.
            .zIndex(isMoving ? 10 : 0)
            // C4: a light haptic tick when a drop actually snapped (grid or neighbour
            // edge). Leaf modifier — the root sheet chain is untouched (metadata law).
            .sensoryFeedback(.impact(weight: .light), trigger: snapPulse)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            // Drag-to-move on the clip BODY (clip game C1 — founder: "seamless workflow,
            // kein unbeholfenes Rumdrücken"): grab and slide. The trim grips are child
            // overlays drawn on top, so they keep winning their 22 pt edge zones; an
            // 8 pt minimum distance keeps a plain TAP falling through to audition and a
            // stationary long-press opening the context menu. Same dedicated-drag
            // pattern the trim handles proved against the scrolling grid (device-
            // verified) — the store call is the ONE command EchoelAI will also use.
            .gesture(moveGesture)
            .onTapGesture {
                // Select mode (C3): tap marks/unmarks; otherwise tap auditions audio.
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
            .contextMenu {
                if editableKind {
                    Button { onEdit() } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                }
                // Split / Join, ON THE CLIP (founder 2026-07-15). Both read
                // transport.position / the document ONLY here (menu builds on open).
                // Split cuts at the playhead when it sits INSIDE this clip; otherwise it
                // halves the clip. Without the fallback, re-splitting a piece "ging nicht"
                // (founder 2026-07-15): after a cut the playhead rests on the new boundary,
                // where `split(at:)` is a no-op for both pieces — so "Split" did nothing.
                // Now it always divides the clip the founder long-pressed.
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
            .accessibilityLabel("\(name), bar \(region.startTick / TimelineTime.ticksPerBar + 1)")
            .accessibilityHint(
                [auditionURL != nil ? "Tap to play this audio clip" : nil,
                 "Drag to move",
                 "Long-press for options",
                 editableKind ? "Edit" : nil,
                 "Delete region"]
                    .compactMap { $0 }.joined(separator: ". ")
            )
    }

    /// Trailing-edge trim (B11) — live width tracks the finger via this clip's OWN
    /// `resizeDelta` @State (no root churn → no jitter); on release the new length is
    /// snapped to the grid (`.off` = stepless) and committed. Floored at one step.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                isResizing = true
                resizeDelta = value.translation.width
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let raw = region.lengthTicks + deltaTicks
                let snapped = snap == .off ? raw : TimelineSnap.snap(raw, to: snap)
                timeline.resizeRegion(
                    id: region.id,
                    lengthTicks: max(TimelineTime.ticksPerTransportStep, snapped))
                isResizing = false
                resizeDelta = 0
            }
    }

    /// Drag-to-move (clip game C1) — the whole clip follows the finger live via this
    /// clip's OWN `moveDelta` @State (no root churn); on release the new start tick is
    /// snapped (`.off` = stepless) and a vertical pull of ≥ half a lane row moves the
    /// clip to that same-kind lane (the store enforces the kind check). ONE store
    /// command — the same call the context menu's "Move to playhead" and, later, the
    /// EchoelAI edit tools use.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                isMoving = true
                moveDelta = value.translation
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let rawStart = Swift.max(0, region.startTick + deltaTicks)
                let laneShift = Int((value.translation.height / ArrangeTimelineView.laneHeight).rounded())
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
                isMoving = false
                moveDelta = .zero
            }
    }

    /// Leading-edge trim (founder 2026-07-15 "auch vorne") — live x/width track the
    /// finger via this clip's OWN `frontDelta` @State (no root churn); on release the new
    /// start tick is snapped and committed via `trimRegionStart`, which holds the end
    /// fixed and shifts the media offset so content stays put (clamped in the model).
    private var frontResizeGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                isFrontResizing = true
                frontDelta = value.translation.width
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let rawStart = region.startTick + deltaTicks
                let snapped = snap == .off ? rawStart : TimelineSnap.snap(rawStart, to: snap)
                timeline.trimRegionStart(id: region.id, toTick: max(0, snapped),
                                         bpm: beatPlayer.pattern.tempo)
                isFrontResizing = false
                frontDelta = 0
            }
    }
}

/// Per-lane Sound & FX (founder 2026-07-12: settings live ON the tracks). Edits
/// the MELODIC bus insert — the piano roll's voices (pad/harmony + lead) — via
/// the same TrackFXStore the Mix menu uses, applied LIVE to both voices on every
/// change. One source of truth, two doors. Honest scope: all MIDI lanes share
/// the one roll slot today (multi-roll = A4), so this edits THE melodic sound.
@MainActor
private struct LaneFXEditor: View {
    let laneName: String
    /// B2: the lane whose persisted pan this editor adjusts (TimelineStore).
    let laneID: UUID
    @Environment(TrackFXStore.self) private var trackFX
    @Environment(PolySynthVoice.self) private var synth
    @Environment(\.leadSynth) private var leadSynth
    @Environment(TimelineStore.self) private var timeline

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

            Text("Filter/drive: same setting as Mix › Melodic — changed here, it changes there. Full-open cutoff with filter Off and drive 0 means: untouched sound. Pan, Transpose and Detune are this track's own and are saved with the song (Pan 0 = center, Transpose 0 = no pitch shift, Detune 0 = in tune).")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EchoelTheme.bg)
    }

    /// Write-through: store (persists + Mix panel follows) AND both live voices.
    private func apply(_ fx: TrackFX) {
        trackFX.set(fx, for: .melodic)
        synth.setInsert(fx)
        leadSynth?.setInsert(fx)
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
