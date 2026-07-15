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
    @Environment(TimelineRegionPlayer.self) private var timelinePlayer
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

    /// Zoom: screen points per quarter-note beat (Stage 3 couples snap to this).
    @State private var pointsPerBeat: CGFloat = 24
    @GestureState private var pinch: CGFloat = 1
    /// Snap resolution — persisted; default 1/16 (research: snap ON by default).
    @AppStorage("timeline.snap") private var snapRaw = SnapResolution.sixteenth.rawValue

    /// Region trim (B11): which region is being resized + its live handle offset.
    /// These re-evaluate the body during an ACTIVE edge-drag only — transient, and
    /// no `.menu` popover can be open under the same finger, so the menu-freeze law
    /// (no CONTINUOUS ancestor churn while a menu is open) is not tripped. Reset on
    /// release; the snapped length is committed to the store in `onEnded`.
    @State private var resizingRegionID: UUID?
    @State private var resizeDeltaX: CGFloat = 0

    private static let laneHeight: CGFloat = 56
    private static let labelWidth: CGFloat = 140
    private static let rulerHeight: CGFloat = 24

    /// One identity colour per content kind — DAW convention, drawn from the
    /// EXISTING palette (Uncodixfy: no new hues): MIDI = instrument green,
    /// audio = material amber, everything without an engine = muted. Used for
    /// the lane's leading stripe and its regions, so a lane and its content
    /// read as one system across the whole Hackbrett.
    private static func kindTint(_ kind: ClipKind?) -> Color {
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
        // K2a lane→engine binding: the roll-slot lane's strip (level/mute/solo)
        // drives the ONE shared Piano-Roll's attack gain. Mute cuts sounding
        // notes immediately (allNotesOff); level/solo apply from the next attack.
        .onChange(of: timeline.document.rollSlotGain, initial: true) { _, gain in
            pianoRoll.mixGain = gain
            if gain <= 0.001 { pianoRoll.allNotesOff() }
        }
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
        .gesture(magnify)
        .sheet(item: $activeModal) { modal in
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

    @ViewBuilder
    private func modalEditor(_ modal: ArrangeModal) -> some View {
        switch modal {
        case .lane(let lane):     editor(forKind: lane.kind,
                                         landingLane: (lane.kind == .audio || lane.kind == .video) ? lane.id : nil)
        case .region(let region): editor(forKind: clips.clip(id: region.clipID)?.kind ?? .midi)
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
            // Play / Stop the TIMELINE's regions over the shared transport (reorg P3).
            // Opt-in and SEPARATE from the instrument's Generate+Play: engaging this
            // takes the roll/pattern over with the placed regions. Reads only the
            // low-frequency `isPlaying` (never `currentTick`) so the toolbar's menus
            // don't churn during playback (render-safe). Disabled with no regions.
            Button {
                if timelinePlayer.isPlaying {
                    timelinePlayer.stop()
                } else {
                    timelinePlayer.play(document: timeline.document, clips: clips,
                                        pattern: beatPlayer.pattern, pianoRoll: pianoRoll)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: timelinePlayer.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(timelinePlayer.isPlaying ? "Stop" : "Play timeline")
                        .font(EchoelTheme.font(12, .medium))
                }
                .foregroundStyle(timelinePlayer.isPlaying ? EchoelTheme.onPrimary : EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(timelinePlayer.isPlaying ? EchoelTheme.accent : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: timelinePlayer.isPlaying ? 0 : 1))
            }
            .buttonStyle(.plain)
            .disabled(timeline.document.regions.isEmpty)
            .accessibilityLabel(timelinePlayer.isPlaying ? "Stop timeline" : "Play timeline")

            // Record: arm the take + start the clock. Every note/bio input on an armed
            // track is captured; Stop drops a Clip + region onto that lane. Reads only
            // the low-frequency `isRecording` bool (render-safe). Disabled until a track
            // is record-armed (its per-track Record dot in the lane strip).
            Button {
                if recordController.isRecording {
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

            // Split at playhead (founder 2026-07-14 "Clips schneiden und
            // zusammenfügen"): the razor — cut EVERY region the playhead crosses into
            // two abutting pieces (audio/video media offset advances so it plays
            // seamlessly; MIDI unaffected). Reads `transport.position` ONLY here in the
            // tap action, never in `body` → no toolbar churn (freeze rule). No-op at a
            // region edge. Merge (join) is the region editor's follow-up.
            Button {
                let tick = TimelineTime.tick(fromAbsoluteStep: transport.position.absoluteStep)
                timeline.splitRegions(atTick: tick, bpm: beatPlayer.pattern.tempo)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Split")
                        .font(EchoelTheme.font(12, .medium))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(timeline.document.regions.isEmpty)
            .accessibilityLabel("Split regions at playhead")

            // Join at playhead — the inverse razor: rejoin same-lane/clip pieces that
            // abut exactly at the playhead (undo of a split). Same tap-only position
            // read as Split. No-op if nothing meets there.
            Button {
                let tick = TimelineTime.tick(fromAbsoluteStep: transport.position.absoluteStep)
                timeline.mergeRegions(atTick: tick, bpm: beatPlayer.pattern.tempo)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Join")
                        .font(EchoelTheme.font(12, .medium))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(timeline.document.regions.isEmpty)
            .accessibilityLabel("Join regions at playhead")

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
                range: 0...2, decimals: 2, boxWidth: 30
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
                .frame(width: 21, height: 18)
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
    private func recordArmButton(_ lane: TimelineLane) -> some View {
        let source = lane.recordSource
        return Button {
            timeline.toggleArm(id: lane.id)
        } label: {
            Image(systemName: lane.isArmed ? "record.circle.fill" : source.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(lane.isArmed ? EchoelTheme.onPrimary : EchoelTheme.dim)
                .frame(width: 21, height: 18)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .fill(lane.isArmed ? EchoelTheme.danger : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Arm \(source.displayName) recording, \(lane.name)")
        .accessibilityValue(lane.isArmed ? "Armed" : "Off")
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
            TimelinePlayhead(pointsPerBeat: ppb)
        }
    }

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
                regionBlock(region)
            }
        }
        .frame(width: gridWidth, height: Self.laneHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
    }

    private func regionBlock(_ region: TimelineRegion) -> some View {
        let x = CGFloat(region.startTick) / CGFloat(TimelineTime.ticksPerBeat) * ppb
        // Live trim (B11): while THIS region's edge is dragged, its width follows
        // the finger; released → snapped + committed to the store.
        let liveDelta = resizingRegionID == region.id ? resizeDeltaX : 0
        let w = max(6, CGFloat(region.lengthTicks) / CGFloat(TimelineTime.ticksPerBeat) * ppb - 2 + liveDelta)
        let clip = clips.clip(id: region.clipID)
        let name = clip?.name ?? "Clip"
        // Tap an AUDIO region = hear its file immediately (founder: "Audio mit
        // direkt die wav Dateien vorhören") — auditions on BeatPlayer's preview
        // voice, so the kit and transport are untouched.
        let auditionURL = clip.flatMap { $0.kind == .audio ? Self.mediaURL($0) : nil }
        // Long-press a region opens its editor (U1, founder: "Lange draufdrücken
        // öffnet ein Fenster, wo man Audio, MIDI, Video etc bearbeiten kann").
        // Only kinds with a real engine offer one.
        let editableKind = clip.map { $0.kind == .midi || $0.kind == .audio } ?? false
        // Region blocks wear their lane's kind colour (V3: "plain grey blocks" →
        // the DAW read: colour = content type, matching the lane-head stripe).
        let tint = Self.kindTint(clip?.kind)
        return RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(0.14))
            .overlay {
                // Audio regions show their waveform (Stage 2) the moment the
                // clip references a real file — recording/import (Stage A/3)
                // feeds this; MIDI/empty regions stay plain blocks.
                if let clip, clip.kind == .audio, let url = Self.mediaURL(clip) {
                    FileWaveformView(url: url, tint: EchoelTheme.text)
                        .padding(.horizontal, 3).padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tint.opacity(0.55), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                // Name at the TOP edge (DAW convention) so the audio waveform
                // below stays unobstructed.
                Text(name)
                    .font(EchoelTheme.font(9, .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.top, 3)
            }
            .overlay(alignment: .trailing) {
                // Trim handle (B11): a fat invisible grab zone at the trailing
                // edge with a thin visible grip. Because the drag starts on this
                // dedicated zone it wins over the horizontal ScrollView (no
                // scroll fight); moving the whole body is a later, device-tuned
                // cycle. Snap-aware via `resizeGesture`.
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: 22)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(resizingRegionID == region.id ? 0.9 : 0.5))
                        .frame(width: 4, height: Self.laneHeight - 20)
                        .padding(.trailing, 3)
                }
                .contentShape(Rectangle())
                .gesture(resizeGesture(region))
            }
            .frame(width: w, height: Self.laneHeight - 8)
            .offset(x: x, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture {
                // A muted (or not-soloed while another solos) lane stays silent —
                // the strip is honest: what you see on M/S is what you hear.
                guard timeline.document.effectiveGain(for: region.laneID) > 0 else { return }
                if let url = auditionURL { beatPlayer.audition(url: url) }
            }
            // Long-press → context menu: Edit (kinds with an engine) + Delete (every
            // kind, incl. video, which has no editor). Replaces the old direct
            // long-press-opens-editor gesture — editing is still one hold away, and
            // the region now has a delete verb (completing Split/Join/Delete). A
            // native contextMenu is NOT a sheet (the metadata chain is untouched) and
            // its content builds on open (no body-time / high-frequency read).
            .contextMenu {
                if editableKind {
                    Button { activeModal = .region(region) } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                }
                // Move to playhead — the arrangement's move verb (drag-move fights the
                // horizontal ScrollView, deferred as device-tuned; playhead-driven is
                // freeze-safe like Split/Join). Reads `transport.position` ONLY in this
                // action closure, never in body. Snaps the region's START to the playhead.
                Button {
                    let tick = TimelineTime.tick(fromAbsoluteStep: transport.position.absoluteStep)
                    timeline.moveRegion(id: region.id, toStartTick: tick)
                } label: {
                    Label("Move to playhead", systemImage: "arrow.right.to.line")
                }
                // Duplicate — the "copy" verb: an identical region right after this one
                // (same clip, no new slot). Completes split/join/delete/move/duplicate.
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
                 "Long-press for options",
                 editableKind ? "Edit" : nil,
                 "Delete region"]
                    .compactMap { $0 }.joined(separator: ". ")
            )
    }

    /// Resolve a clip's `mediaRef` to an existing file (absolute path today;
    /// nothing writes relative refs yet — extend here when import lands).
    private static func mediaURL(_ clip: Clip) -> URL? {
        guard let ref = clip.mediaRef, !ref.isEmpty else { return nil }
        let url = URL(fileURLWithPath: ref)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                pointsPerBeat = min(96, max(8, pointsPerBeat * value))
            }
    }

    /// Trailing-edge trim gesture (B11) — turns a region block into a resizable
    /// clip. Live width tracks the finger via `resizeDeltaX`; on release the new
    /// length is snapped to the current grid (`.off` = stepless) and committed.
    /// Floored at one transport step so a region can't collapse to nothing.
    private func resizeGesture(_ region: TimelineRegion) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                resizingRegionID = region.id
                resizeDeltaX = value.translation.width
            }
            .onEnded { value in
                let deltaTicks = Int((value.translation.width / ppb
                                      * CGFloat(TimelineTime.ticksPerBeat)).rounded())
                let raw = region.lengthTicks + deltaTicks
                let snapped = snap == .off ? raw : TimelineSnap.snap(raw, to: snap)
                timeline.resizeRegion(
                    id: region.id,
                    lengthTicks: max(TimelineTime.ticksPerTransportStep, snapped))
                resizingRegionID = nil
                resizeDeltaX = 0
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
    let pointsPerBeat: CGFloat

    var body: some View {
        let pos = transport.position
        let beats = CGFloat(pos.bar * Transport.stepsPerBar + pos.step)
            / CGFloat(Transport.stepsPerBeat)
        Rectangle()
            .fill(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
            .frame(width: 2)
            .offset(x: beats * pointsPerBeat)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
