#if canImport(SwiftUI) && canImport(MetalKit) && canImport(UIKit)
import SwiftUI

// FloatingVisualWindow.swift
// Echoel — the immersive visual as a FLOATING, resizable, show/hide window (founder
// 2026-07-02: "als kleines Fenster flexibel groß ein- und ausblendbar machen …
// interessanter aber weniger komplex von den Einstellungen"). The core product is the
// bio-reactive MUSIC; the visual rides along as a calm picture-in-picture you can move,
// grow (S/M/L) and dismiss — no VJ sliders here (the deep controls stay in Studio).
//
// Render safety: this is a LEAF overlay. Its body reads only LOW-frequency @State
// (size, drag position) — never a ~10 Hz bio value — so it can float over any surface
// without rebuilding the surface tree / freezing an open menu (freeze rule). The real
// `MetalBioView` pulls the live bio itself inside its `draw(in:)` loop (off the SwiftUI
// graph). Only ONE `MetalBioView` renders app-wide at a time (GPU rule): this window is
// the single Metal path at the WorkspaceView root.

/// A finished MP4 clip to share (Identifiable so `.sheet(item:)` can present it).
private struct RecordedClip: Identifiable {
    let id = UUID()
    let url: URL
}

/// On-screen recording feedback: a red dot + "REC m:ss" elapsed, ticking once a second.
/// Small rounded chip (not a pill) per Uncodixfy; drawn over the visual while recording.
private struct RecordingBadge: View {
    let start: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, start.map { context.date.timeIntervalSince($0) } ?? 0)
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("REC \(timeString(elapsed))")
                    .font(EchoelTheme.font(10, .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
            .padding(8)
        }
        .accessibilityLabel("Recording")
    }

    private func timeString(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// A COMPACT position/loop readout for the Visual Instrument's TOP BAR (founder 2026-07-07:
/// "sowas in klein" + "Das muss mit nach oben in die Leiste"). Mirrors `TransportPositionView`
/// (bar.beat.step + a slim loop-progress capsule) at a smaller size. Its OWN leaf so the ~10 Hz
/// `transport.position` read stays confined here and never rebuilds the floating window (freeze
/// rule); reads only low-frequency `loopBars` besides.
@MainActor
private struct MiniTransportView: View {
    @Environment(Transport.self) private var transport
    @AppStorage("studio.loopBars") private var loopBars: LoopBarLength = .four

    var body: some View {
        let pos = transport.position
        let bars = max(1, loopBars.rawValue)
        let barInLoop = pos.bar % bars
        let sixteenth = pos.step % Transport.stepsPerBeat
        let loopFraction = Double(barInLoop * Transport.stepsPerBar + pos.step)
            / Double(bars * Transport.stepsPerBar)
        return HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 34, height: 3)
                Capsule().fill(transport.isPlaying ? EchoelTheme.accent : Color.white.opacity(0.5))
                    .frame(width: 34 * max(0.02, loopFraction), height: 3)
            }
            Text(String(format: "%d.%d.%d", barInLoop + 1, pos.beat + 1, sixteenth + 1))
                .font(EchoelTheme.font(10, .medium).monospacedDigit())
                .foregroundStyle(.white)
            Text("\(barInLoop + 1)/\(bars)")
                .font(EchoelTheme.font(9).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loop position")
    }
}

@MainActor
struct FloatingVisualWindow: View {

    /// Show/hide — owned by WorkspaceView (persisted there), toggled from the header.
    @Binding var isPresented: Bool

    /// Honour the system Reduce Motion setting here too (the fullscreen path already did) —
    /// otherwise the floating visual keeps animating for a user who asked motion to stop.
    /// Accessibility + consistency parity fix (visuals audit 2026-07-03).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MP4 capture (founder 2026-07-02: "WAV und MP4 sind die Formate der Wahl"). The
    // window's MetalBioView is the single Metal path, so it is the one capture instance;
    // tapping record writes the bio-reactive visual (+ the live audio) to an .mp4 to share.
    #if canImport(AVFoundation)
    @Environment(VisualRecorder.self) private var recorder
    @Environment(AudioEngine.self) private var audioEngine
    /// For idle-tone colour + entrainment pulse parity with the fullscreen visual (audit #5:
    /// the floating window fell back to C4 and ignored an ARMED entrainment). Both reads are
    /// LOW-frequency (user-set toggles/keys) — safe in this leaf body per the freeze rule.
    @Environment(PolySynthVoice.self) private var synth
    // For a fitting MP4 name (founder: "Session Recording für video und auch passender
    // Name") — same convention as the WAV: Echoel_<date>_<Key>_<bpm>_A440_<Genre>.mp4.
    @Environment(SessionContext.self) private var session
    @Environment(Transport.self) private var transport
    @AppStorage("studio.genre") private var genre: MusicStyle = .vaporwave
    @State private var recordedClip: RecordedClip?
    /// When recording started — drives the on-screen REC elapsed time.
    @State private var recordStart: Date?

    // WAV audio capture (founder 2026-07-07: "ein wav Aufnahme Knopf wäre auch im Visual
    // Instrument gut" + "Video und wav Aufnahme muss Natürlichkeit erkennbar sein"). The MP4
    // above muxes lossy AAC audio; this writes a LOSSLESS WAV of the same performance so the
    // organic, natural character of the bio-generative take survives (WAV = PCM; only a LUFS
    // gain is applied, never a lossy codec). Independent of the MP4 path — the MP4 grabs the
    // ring at stop, this uses RetroCapture's live-file write — so you can arm BOTH for one take.
    @State private var wavRecording = false
    @State private var wavRecordStart: Date?
    @State private var wavClip: RecordedClip?
    @State private var wavExporting = false
    #endif

    // Visual DESIGN (founder: "Visual Design muss möglich sein" + "Feinschliff, alles
    // User-optimiert"). EVERY design control the Visual panel exposes is now SHARED
    // (@AppStorage), so each live tweak shows in this window immediately — Look/blend and
    // the six energy/palette params. Single source of truth; no drift between panel + window.
    // Defaults: a rich look (Aurora, index 5) out of the box — "interessanter" than flat
    // Rings — and saturation 0.82 (professional, not neon; keeps the physical tone→colour
    // readable). Kept IDENTICAL to EchoelStudioView's declarations so an absent key resolves
    // to the same value in both views (no drift before the user touches a control).
    @AppStorage("visual.style") private var visualStyle = 5
    @AppStorage("visual.styleB") private var visualStyleB = 0
    @AppStorage("visual.blend") private var visualBlend = 0.0
    @AppStorage("visual.intensity") private var visualIntensity = 1.0
    @AppStorage("visual.detail") private var visualDetail = 40.0
    @AppStorage("visual.motion") private var visualMotion = 1.0
    @AppStorage("visual.spread") private var visualSpread = 1.0
    @AppStorage("visual.hue") private var visualHue = 0.0
    @AppStorage("visual.saturation") private var visualSaturation = 0.82

    /// The Studio's key root — same key + default as EchoelStudioView, so the IDLE tint of
    /// this window matches the fullscreen visual's tonic instead of a hardcoded C4.
    @AppStorage("studio.rootIndex") private var rootIndex = 0
    /// The Studio's scale — the fullscreen play surface quantizes touches into
    /// this key (same key + default as EchoelStudioView). Low-frequency reads.
    @AppStorage("studio.scale") private var touchScale: Scale = .minor

    /// Snap size, persisted so the window reopens the size you left it.
    @AppStorage("visual.floating.size") private var sizeRaw = WindowSize.small.rawValue
    private var windowSize: WindowSize { WindowSize(rawValue: sizeRaw) ?? .medium }

    /// Card CENTRE in the parent's coordinate space. `nil` until first layout → defaults
    /// to the bottom-trailing dock (above the transport / bottom bar). Kept in @State
    /// (per-launch) — a low-frequency value, safe to read in this leaf's body.
    @State private var center: CGPoint?
    /// Drag anchor so a move continues from where the card currently sits.
    @State private var dragAnchor: CGPoint?

    enum WindowSize: Int, CaseIterable {
        case small, medium, large, fullscreen
        var next: WindowSize { WindowSize(rawValue: (rawValue + 1) % WindowSize.allCases.count) ?? .small }
        /// Width / height as a fraction of the available space. Fullscreen fills everything
        /// (handled specially in `size(in:)`), so its fraction is unused.
        var fraction: (w: CGFloat, h: CGFloat) {
            switch self {
            case .small:      return (0.38, 0.30)
            case .medium:     return (0.62, 0.42)
            case .large:      return (0.92, 0.62)
            case .fullscreen: return (1.0, 1.0)
            }
        }
        var label: String {
            switch self {
            case .small:      return "Small"
            case .medium:     return "Medium"
            case .large:      return "Large"
            case .fullscreen: return "Fullscreen"
            }
        }
        var isFullscreen: Bool { self == .fullscreen }
    }

    private let margin: CGFloat = 12
    private let handleHeight: CGFloat = 30

    /// Calm liquid looks the top-bar slider scrubs (Water · Aurora · Depth · Plasma) — the
    /// same set the removed Look button cycled. MUST match EchoelStudioView.calmMetalStyles.
    private static let calmLooks = [3, 5, 7, 2]

    /// Slider position ⇄ current look. Scrubbing snaps `visual.style` to a calm look, live
    /// (founder 2026-07-07: "die visuals oben in der Leiste mit einem slider geändert …
    /// während des Spielens" — better handling than tap-cycling).
    private var lookScrub: Binding<Double> {
        Binding(
            get: { Double(Self.calmLooks.firstIndex(of: visualStyle) ?? 0) },
            set: { v in
                let i = min(Self.calmLooks.count - 1, max(0, Int(v.rounded())))
                if Self.calmLooks[i] != visualStyle { visualStyle = Self.calmLooks[i] }
            }
        )
    }

    /// Tonic frequency for the IDLE tint (when nothing sounds the renderer falls back to this;
    /// while music plays it pulls the live tone itself from the bus). Mirrors the fullscreen
    /// visual's mapping minus the per-take transpose (a @State there, irrelevant while idle).
    private var idleToneHz: Double {
        #if canImport(AVFoundation)
        return session.a4Hz * pow(2.0, (Double(60 + rootIndex) - 69.0) / 12.0)
        #else
        return 261.63
        #endif
    }

    /// Armed brainwave-entrainment visual pulse — same LOW-frequency guard as the fullscreen
    /// path (never the 10 Hz auto target), so the floating picture breathes with an armed
    /// entrainment exactly like the fullscreen one. 0 = none.
    private var entrainmentPulse: Double {
        #if canImport(AVFoundation)
        guard synth.entrainmentEnabled, let band = synth.entrainmentManualBand else { return 0 }
        return BioEntrainmentDirector.visualHz(for: band)
        #else
        return 0
        #endif
    }


    var body: some View {
        GeometryReader { geo in
            let full = windowSize.isFullscreen
            let sz = size(in: geo.size)
            // Fullscreen: pin to the exact centre (no drag/clamp). Else: the dragged/docked spot.
            let c = full
                ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                : clamp(center ?? defaultCenter(in: geo.size, card: sz), in: geo.size, card: sz)
            card(size: sz, in: geo.size)
                .frame(width: sz.width, height: sz.height)
                .position(c)
        }
        // Fullscreen bleeds to the sides + under the home indicator, but KEEPS the top safe
        // area so the toolbar (change-look / record / exit) never hides under the notch —
        // you must still be able to manipulate the visual (founder). Floating sizes: no bleed.
        .ignoresSafeArea(edges: windowSize.isFullscreen ? [.bottom, .horizontal] : [])
        .transition(.opacity)
        #if canImport(AVFoundation)
        .sheet(item: $recordedClip) { clip in ShareSheet(url: clip.url) }
        .sheet(item: $wavClip) { clip in ShareSheet(url: clip.url) }
        #endif
    }

    // MARK: - Toolbar controls (position readout + WAV record)

    #if canImport(AVFoundation)
    /// Lossless-WAV record button + live elapsed time, sized to sit in the top bar next to the
    /// video button. Distinct waveform glyph so it reads as AUDIO vs. the video glyph (founder:
    /// both recorders must be recognizable).
    @ViewBuilder private var wavRecordControl: some View {
        HStack(spacing: 5) {
            if wavRecording {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, wavRecordStart.map { context.date.timeIntervalSince($0) } ?? 0)
                    Text("WAV \(recTimeString(elapsed))")
                        .font(EchoelTheme.font(10, .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            } else if wavExporting {
                Text("WAV …")
                    .font(EchoelTheme.font(10, .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Button { toggleWavRecording() } label: {
                Image(systemName: wavRecording ? "stop.circle.fill" : "waveform.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(wavRecording ? Color.red : (wavExporting ? EchoelTheme.dim : EchoelTheme.text))
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(wavExporting)
            .accessibilityLabel(wavRecording ? "Stop WAV audio recording" : "Record lossless WAV audio")
        }
    }

    private func recTimeString(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
    #endif

    // MARK: - Card

    @ViewBuilder
    private func card(size: CGSize, in bounds: CGSize) -> some View {
        VStack(spacing: 0) {
            handleBar(in: bounds, card: size)
            // `capturesVideo: true` → this instance feeds the shared VisualRecorder when
            // recording (it is the only Metal path, so no double-capture). The look params
            // are the SHARED design keys (style/blend + the six energy/palette params), so
            // every tweak in the Visual panel shows here live.
            MetalBioView(capturesVideo: true, reduceMotion: reduceMotion, toneHz: idleToneHz,
                         intensity: Float(visualIntensity), ringDensity: Float(visualDetail),
                         motion: Float(visualMotion), spread: Float(visualSpread),
                         hueShift: Float(visualHue), saturation: Float(visualSaturation),
                         style: visualStyle, styleB: visualStyleB, blend: Float(visualBlend),
                         entrainmentPulseHz: entrainmentPulse)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                #if canImport(UIKit) && canImport(AVFoundation)
                // PLAY SURFACE at EVERY size (founder 2026-07-07: "das Visual in ein
                // Multi-Touch Instrument umwandeln … wie mit den Fingern durchs Wasser" +
                // "in den anderen kleinen Ansichten auch spielbar"). Touches become
                // scale-quantized notes on the take's own synth patch (coherent by
                // construction) + water rings under the fingers — no dead-touch state to
                // explain, so no "only in fullscreen" hint is needed. Was fullscreen-only,
                // but the window is moved by the LOGO handle (not the visual body), so the
                // play layer never competes with drag/resize. UIKit-gated: the multi-touch
                // layer is a UIView (macOS CI has none).
                .overlay {
                    TouchInstrumentView(key: MusicalKey(root: rootIndex, scale: touchScale),
                                        synth: synth,
                                        reduceMotion: reduceMotion)
                }
                #endif
                #if canImport(AVFoundation)
                // Recording feedback — a red REC pill with elapsed time, top-leading over
                // the visual so it's clear a clip is being captured.
                .overlay(alignment: .topLeading) {
                    if recorder.isRecording { RecordingBadge(start: recordStart) }
                }
                #endif
        }
        .background(Color.black)
        // No rounded corners / border in fullscreen — a true edge-to-edge picture.
        .clipShape(RoundedRectangle(cornerRadius: windowSize.isFullscreen ? 0 : 12))
        .overlay {
            if !windowSize.isFullscreen {
                RoundedRectangle(cornerRadius: 12).strokeBorder(EchoelTheme.border, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating visual")
    }

    /// The only chrome: a drag handle + a size cycle + a close button. Deliberately no
    /// sliders (founder: fewer settings).
    private func handleBar(in bounds: CGSize, card: CGSize) -> some View {
        HStack(spacing: 8) {
            // Drag ONLY by this handle — NOT the whole bar. A DragGesture spanning the whole
            // bar competed with the buttons: a tap with the slightest finger move started a
            // drag and cancelled the button tap, so "die Farbpalette ist nicht anklickbar"
            // (founder). Confining the drag here frees every toolbar button to receive taps.
            // The Echoel LOGO is the drag handle now (founder 2026-07-07: "im Visual
            // Fenster soll man das Logo sehen, oben links — anstatt das Burgermenü,
            // das keinen Nutzen hat"). Same 40-wide hit target + drag gesture as the
            // old ≡, so move-by-handle still works; the window is just branded now.
            EchoelLogoMark()
                .frame(width: 20, height: 20)
                .frame(width: 40, height: handleHeight)
                .contentShape(Rectangle())
                .gesture(
                    // MUST be `.global`: the default `.local` space measures the drag inside
                    // the handle's OWN frame, which MOVES as the window follows the drag — so
                    // the reported translation feeds back on itself and the window trembles
                    // while you move it (founder: "zittert, wenn man es verschiebt"). A fixed
                    // (screen) space gives a stable translation → smooth drag.
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            let base = dragAnchor ?? (center ?? defaultCenter(in: bounds, card: card))
                            if dragAnchor == nil { dragAnchor = base }
                            center = CGPoint(x: base.x + value.translation.width,
                                             y: base.y + value.translation.height)
                        }
                        .onEnded { _ in dragAnchor = nil }
                )
                .accessibilityLabel("Echoel — drag to move the visual")
            Spacer(minLength: 0)
            // Live LOOK slider (founder 2026-07-07: "die visuals oben in der Leiste mit einem
            // slider geändert … während des Spielens" — better handling than the tap-cycle Look
            // button that was here). Scrubs the calm looks. The founder's explicit "slider" ask
            // overrides the EchoelValueField default: this is a live VJ control over the visual,
            // not a Studio parameter row. Fullscreen only — that's where the bar has the width.
            if windowSize.isFullscreen {
                Slider(value: lookScrub, in: 0...Double(Self.calmLooks.count - 1), step: 1)
                    .tint(EchoelTheme.accent)
                    .frame(width: 72)
                    .accessibilityLabel("Visual look")
            }
            // The transport-position readout + WAV control live UP HERE in the bar now
            // (founder 2026-07-07: "Das muss mit nach oben in die Leiste") — not floating over
            // the picture. Position is its own leaf (`MiniTransportView` reads Transport itself)
            // so its ~10 Hz updates never rebuild this window (freeze rule); display-only, so it
            // never steals a touch from the play surface.
            // The position readout needs a little width to stay legible — show it from Medium
            // up (and fullscreen). On the Small window it would crowd the record/resize buttons.
            if windowSize != .small {
                MiniTransportView()
                    .allowsHitTesting(false)
            }
            #if canImport(AVFoundation)
            wavRecordControl
            // MP4 VIDEO capture. Distinct "video" glyph (vs. the WAV button's waveform)
            // so the two recorders are recognizable at a glance (founder: "Video
            // und wav Aufnahme muss … erkennbar sein").
            Button { toggleRecording() } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "video.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(recorder.isRecording ? Color.red : EchoelTheme.text)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "Stop video recording" : "Record MP4 video")
            #endif
            Button { cycleSize() } label: {
                // Cycles Small → Medium → Large → Fullscreen → Small. Shows a "contract"
                // glyph in fullscreen so it's obvious the next tap leaves fullscreen.
                Image(systemName: windowSize.isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(windowSize.isFullscreen ? "Exit fullscreen" : "Resize visual")
            .accessibilityValue(windowSize.label)
            Button { withAnimation(.easeInOut(duration: 0.15)) { isPresented = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide visual")
        }
        .padding(.horizontal, 10)
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .background(EchoelTheme.bg.opacity(0.92))
        // NOTE: the move-drag lives on the ≡ handle only (see above), NOT the whole bar, so it
        // can never swallow a toolbar-button tap.
    }

    private func cycleSize() {
        withAnimation(.easeInOut(duration: 0.18)) { sizeRaw = windowSize.next.rawValue }
    }

    #if canImport(AVFoundation)
    /// Start/stop MP4 capture of the visual (with live audio). On stop, present the share
    /// sheet. Tip: size the window up (L) before recording for a higher-resolution clip —
    /// the video is rendered at the window's on-screen size.
    private func toggleRecording() {
        if recorder.isRecording {
            recordStart = nil
            Task { @MainActor in
                if let url = await recorder.stop() {
                    recordedClip = RecordedClip(url: renamedForShare(url))
                }
            }
        } else {
            recordStart = Date()
            recorder.start(audio: audioEngine)
        }
    }

    /// Start/stop a LOSSLESS WAV recording of the live performance. Uses RetroCapture's
    /// live-file write (independent of the MP4 path, which snapshots the ring at stop — so
    /// both can be armed for one take), then converts the float32 CAF to a .wav via
    /// SingleExport (PCM out, LUFS gain only — the natural character is preserved, founder:
    /// "Natürlichkeit … erkennbar"). On stop, present the share sheet.
    private func toggleWavRecording() {
        if wavRecording {
            wavRecording = false
            wavRecordStart = nil
            audioEngine.retroCapture.stopRecording { url in
                Task { @MainActor in await exportWav(from: url) }
            }
        } else {
            // A studio export (LoopExporter) also drives RetroCapture's live file; if one is
            // mid-capture, don't start a second (it would no-op in RetroCapture anyway).
            guard !audioEngine.retroCapture.isRecording else { return }
            audioEngine.retroCapture.startRecording(preRoll: 0)   // live from NOW, arbitrary length
            wavRecording = true
            wavRecordStart = Date()
        }
    }

    /// Convert the captured CAF to a shareable, naturally-preserved .wav.
    private func exportWav(from cafURL: URL) async {
        wavExporting = true
        defer { wavExporting = false }
        let ex = audioEngine.singleExport
        ex.reset()
        ex.outputFormat = .wav          // lossless PCM — no codec artifacts
        ex.targetLUFS = -14             // loudness match only (gain), character intact
        ex.trimLengthSeconds = nil      // keep the WHOLE take (no bar-grid trim here)
        await ex.export(sourceURL: cafURL)
        if let url = ex.exportState.exportedURL {
            wavClip = RecordedClip(url: renamedForShare(url))
        }
    }

    /// Give the recorded clip a fitting name — same convention as the WAV export:
    /// `Echoel_<date>_<Key>_<bpm>_A440_<Genre>.mp4` (key + tempo + tuning + genre). Copies
    /// to a temp file with that name for the share sheet; falls back to the original on
    /// failure so a recording is never lost.
    private func renamedForShare(_ url: URL) -> URL {
        let raw = "\(session.sessionName(bpm: transport.tempo))_\(genre.displayName)"
        let safe = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>| "))
            .filter { !$0.isEmpty }.joined(separator: "-")
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }
    #endif

    // MARK: - Geometry

    private func size(in bounds: CGSize) -> CGSize {
        if windowSize.isFullscreen { return bounds }   // edge-to-edge, no margin
        let f = windowSize.fraction
        let w = max(140, bounds.width * f.w)
        let h = max(120, bounds.height * f.h)
        return CGSize(width: min(w, bounds.width - 2 * margin),
                      height: min(h, bounds.height - 2 * margin))
    }

    private func defaultCenter(in bounds: CGSize, card: CGSize) -> CGPoint {
        CGPoint(x: bounds.width - card.width / 2 - margin,
                y: bounds.height - card.height / 2 - margin)
    }

    /// Keep the whole card on screen (with the margin) whatever the size/drag.
    private func clamp(_ p: CGPoint, in bounds: CGSize, card: CGSize) -> CGPoint {
        let minX = card.width / 2 + margin
        let maxX = bounds.width - card.width / 2 - margin
        let minY = card.height / 2 + margin
        let maxY = bounds.height - card.height / 2 - margin
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)),
                       y: min(max(p.y, minY), max(minY, maxY)))
    }
}
#endif
