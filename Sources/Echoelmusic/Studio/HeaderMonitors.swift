// HeaderMonitors.swift
// Echoel — the persistent header's two live monitors (founder idea, 2026-06-23):
// LEFT a small EKG-style control trace of the live pulse, RIGHT a monitor of the
// immersive visualisation. Both live in WorkspaceView.topBar (above every surface)
// and tap-expand to full screen — the first building block of the DMMW multiscreen /
// livestream / projection-mapping output.
//
// Design: the EKG is pure SwiftUI Canvas (no GPU, flash-safe); the immersive monitor
// reuses the REAL MetalBioView (not a placeholder), rendered only while a bio session
// is live to bound GPU cost. Uncodixfy: solid fills, 1px borders, ≤12px radius, no
// glow, opacity-only feedback. Fully VoiceOver-labelled.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - EKG pulse trace (left)

/// The EKG line: normalized [-1,1] samples drawn as a centred trace. Cheap vector
/// drawing; a flat baseline shows when there is no signal yet.
@MainActor
struct PulseTrace: View {
    let samples: [Float]
    var color: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            guard samples.count > 1 else {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: midY))
                base.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(base, with: .color(color.opacity(0.45)), lineWidth: 1)
                return
            }
            let n = samples.count
            let amp = midY - 1
            var path = Path()
            for (i, s) in samples.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(n - 1)
                let clamped = CGFloat(Swift.max(-1, Swift.min(1, s)))
                let y = midY - clamped * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }
}

/// Compact header pulse monitor: live EKG trace + BPM. Accessible as one element.
///
/// MOUNTED in WorkspaceView.topBar between logo and title since 2026-07-12 (founder:
/// "Der Pulsmonitor kommt nach oben zwischen Logo und Echoelmusic") — this SUPERSEDES
/// the 2026-07-03 "eine BPM-Anzeige reicht" unmount. Do not remove it again without a
/// fresh founder ask.
@MainActor
struct PulseMonitorMini: View {
    let waveform: [Float]
    let bpm: Double
    let locked: Bool
    /// Live coherence [0…1] — the BioStrip's key metric in "vereinfachter Form"
    /// (founder 2026-07-12: the bio row lands simplified up here). nil hides it.
    var coherence: Double? = nil

    var body: some View {
        HStack(spacing: 6) {
            PulseTrace(samples: waveform, color: locked ? EchoelTheme.accent : EchoelTheme.dim)
                .frame(width: 50, height: 24)
            Text(locked && bpm > 0 ? "\(Int(bpm))" : "—")
                .font(EchoelTheme.font(11, .semibold)).monospacedDigit()
                .foregroundStyle(locked ? EchoelTheme.text : EchoelTheme.dim)
                .frame(minWidth: 22, alignment: .leading)
            if let coh = coherence {
                Text(String(format: "%.2f", coh))
                    .font(EchoelTheme.font(10)).monospacedDigit()
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
        .padding(.horizontal, 6).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoelTheme.border, lineWidth: 1))
        // This leaf owns the pulse element (it reads the live BPM; WorkspaceView can't,
        // per the freeze rule).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live pulse")
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        guard locked && bpm > 0 else { return "No pulse lock" }
        if let coh = coherence {
            return "\(Int(bpm)) beats per minute, coherence \(String(format: "%.2f", coh))"
        }
        return "\(Int(bpm)) beats per minute"
    }
}

#if canImport(AVFoundation)
/// Live wrapper that reads the ~10 Hz pulse publisher in ITS OWN body, so the churn
/// stays in this leaf. Reading `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly
/// in `WorkspaceView.topBar` subscribed `WorkspaceView` — the PARENT of every surface —
/// to a 10 Hz signal, so the whole surface tree (including the active surface's Compose/
/// Mood/Effects `.menu` Pickers) rebuilt 10×/s during biofeedback and tore down any open
/// dropdown ("kann nicht mehr auswählen während Biofeedback", 10.76.50). Confining the
/// reads here keeps WorkspaceView still; only this 30 pt monitor refreshes.
@MainActor
struct PulseMonitorMiniLive: View {
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    @Environment(EngineBus.self) private var bus
    var body: some View {
        // `displayBPM` is the CALM value (holds the last confident reading through noisy
        // patches) so the glanceable number doesn't bounce; the waveform/lock stay live.
        // Coherence comes from the bus snapshot — read HERE in the leaf (freeze rule),
        // never in WorkspaceView. Shown only while a fresh bio frame exists, so idle
        // the leaf stays the compact trace + "—".
        PulseMonitorMini(waveform: cameraRPPG.waveform,
                         bpm: cameraRPPG.displayBPM,
                         locked: cameraRPPG.isLocked,
                         coherence: bus.freshBio().map { Double($0.coherence) })
            // E-Bio (founder 2026-07-12: "Diese Leiste soll in vereinfachter Form da
            // oben landen"): the header leaf now CARRIES the strip's key action —
            // tap = Read pulse / stop, via the same notification the transport pulse
            // button uses (chrome posts; the receiver stays anchored on an inner
            // studio row, never on the root modifier chain).
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .echoelToggleBio, object: nil)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(cameraRPPG.isRunning ? "Stops the pulse reading"
                                                    : "Starts reading your pulse")
    }
}
#endif

// MARK: - Immersive monitor (right)

/// Compact header monitor of the immersive visual. Shows the VISUAL'S OWN colours
/// (founder 2026-07-12: "Der Monitor … soll auch die Visuals anzeigen und nicht nur
/// blaues Blinken"): the sounding chord's physical tone colour via `SpectralColor`
/// — the exact Swift twin of the shader's CIE wavelength fit, so this tile carries
/// the same hue the big visual paints — swelling with the live music level and
/// pulsing at the heart rate. Deliberately SwiftUI, NOT a second MetalBioView:
/// running two MTKViews at once (this tile + the immersive) starved the GPU and
/// made the full immersive render black for seconds (device video, 2026-06-23).
/// Tapping toggles the real Metal visual, so only ONE ever renders at a time.
@MainActor
struct ImmersiveMonitorMini: View {
    let active: Bool
    @Environment(EngineBus.self) private var bus

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    // Colour work lives in the pure helper below — inlining the
                    // Double/Float mix here sent the type-checker into "unable to
                    // type-check in reasonable time" (Xcode gate, d41c13d).
                    RadialGradient(colors: [Self.tileColor(bio: bus.freshBio(),
                                                           mf: bus.freshMusical(maxAge: 1.0),
                                                           date: tl.date),
                                            .black],
                                   center: .center, startRadius: 1, endRadius: 28)
                }
            } else {
                ZStack {
                    EchoelTheme.fill
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                }
            }
        }
        .frame(width: 54, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Immersive visual monitor")
        .accessibilityValue(active ? "Live" : "Idle")
        .accessibilityHint("Shows or hides the floating visual window")
        .accessibilityAddTraits(.isButton)
    }

    /// The tile's live colour — the sounding chord's physical tone colour
    /// (SpectralColor, the Swift twin of the shader's CIE fit), brightness
    /// breathing with the music level and pulsing at the heart rate. PURE with
    /// explicit Double types so the ViewBuilder above stays type-checker-cheap;
    /// silent input → SpectralColor's neutral grey (an honest "nothing sounds").
    static func tileColor(bio: BioSampleFrame?, mf: MusicalFrame?, date: Date) -> Color {
        let hr: Double = max(40.0, Double(bio?.heartRateBPM ?? 60))
        let phase: Double = (date.timeIntervalSinceReferenceDate * hr / 60.0)
            .truncatingRemainder(dividingBy: 1.0)
        let pulse: Double = 0.5 - 0.5 * cos(phase * 2.0 * .pi)       // 0…1 per beat
        let chord: [(hz: Double, amplitude: Double)] =
            (mf?.notes ?? []).map { ($0.frequencyHz, $0.amplitude) }
        let rgb = SpectralColor.color(forChord: chord)
        let level: Double = mf?.masterLevel ?? 0
        let energy: Double = 0.35 + 0.30 * pulse + 0.35 * level
        // Gamma-encode the linear mix for display (simple 1/2.2 — a 54 pt tile).
        func enc(_ v: Double) -> Double { pow(min(max(v * energy, 0.0), 1.0), 1.0 / 2.2) }
        return Color(red: enc(rgb.r), green: enc(rgb.g), blue: enc(rgb.b))
    }
}

// The immersive visual now opens as a FLOATING, resizable window (FloatingVisualWindow,
// toggled from the header monitor), not a fullscreen cover — so the earlier
// `ExpandedMonitor` enum + `ExpandedMonitorView` (a second, now-unreachable MetalBioView
// path) were removed (founder pivot 2026-07-02: one visual path, fewer surfaces).

// MARK: - EchoelLux monitor (header)

/// Compact header monitor of the LIGHT output (founder 2026-07-12, red sketch:
/// "oben neben dem EchoelBioSynth Monitor noch 2 Fenster … eins für EchoelLux").
/// HONEST: it shows the colour the fixtures are actually being sent — the same
/// `SpectralColor.color(forChord:)` × dimmer mapping the Art-Net/sACN senders
/// compute (MusicMediaMap.dmxChannels) — and goes idle-grey when no light route
/// is enabled. A LEAF: it reads the router + bus in its OWN body (freeze rule);
/// the route flags only change on user edits, the live colour renders inside a
/// 10 Hz TimelineView like the visual tile. Tap opens Routing (chrome door).
@MainActor
struct EchoelLuxMonitorMini: View {
    @Environment(SignalRouter.self) private var router
    @Environment(EngineBus.self) private var bus

    private var luxActive: Bool {
        #if canImport(Network)
        return router.graph.hasEnabledRoute(toSink: "artnet.out")
            || router.graph.hasEnabledRoute(toSink: "sacn.out")
        #else
        return false
        #endif
    }

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .echoelChromeDoor, object: "routing")
        } label: {
            Group {
                if luxActive {
                    TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { _ in
                        Self.lightColor(mf: bus.freshMusical(maxAge: 1.5))
                    }
                } else {
                    ZStack {
                        EchoelTheme.fill
                        Image(systemName: "lightbulb")
                            .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
                    }
                }
            }
            .frame(width: 38, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("EchoelLux light monitor")
        .accessibilityValue(luxActive ? "Sending to fixtures" : "No light route")
        .accessibilityHint("Opens routing")
    }

    /// The exact colour the DMX mapping sends: chord colour × the music dimmer
    /// (MusicMediaMap: 0.3 + 0.7 × level). Silence = the senders' resting dim —
    /// shown as a low warm glow, honest "fixtures idle, route armed".
    static func lightColor(mf: MusicalFrame?) -> Color {
        let chord: [(hz: Double, amplitude: Double)] =
            (mf?.notes ?? []).map { ($0.frequencyHz, $0.amplitude) }
        let rgb = SpectralColor.color(forChord: chord)
        let dim: Double = 0.3 + 0.7 * (mf?.masterLevel ?? 0)
        func enc(_ v: Double) -> Double { pow(min(max(v * dim, 0.0), 1.0), 1.0 / 2.2) }
        return Color(red: enc(rgb.r), green: enc(rgb.g), blue: enc(rgb.b))
    }
}

// MARK: - EchoelVideo monitor (header)

#if canImport(AVFoundation) && canImport(Metal)
/// Compact header monitor of the VIDEO pillar (founder 2026-07-12, red sketch:
/// "… und eins für EchoelVideo"). HONEST about what ships today: it mirrors the
/// visual recorder — a steady REC state while a clip is being captured (steady,
/// not blinking — flash law), idle film icon otherwise. Deliberately NOT a live
/// video thumbnail: that would need a second Metal/AV pipeline in the header
/// (one-GPU-canvas rule). Tap opens the Video panel (recorded clips library).
@MainActor
struct EchoelVideoMonitorMini: View {
    @Environment(VisualRecorder.self) private var recorder

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .echoelChromeDoor, object: "video")
        } label: {
            ZStack {
                EchoelTheme.fill
                HStack(spacing: 4) {
                    if recorder.isRecording {
                        Circle().fill(Color(red: 0.86, green: 0.22, blue: 0.20))
                            .frame(width: 7, height: 7)
                    }
                    Image(systemName: recorder.isRecording ? "record.circle" : "film")
                        .font(.system(size: 11))
                        .foregroundStyle(recorder.isRecording ? EchoelTheme.text : EchoelTheme.dim)
                }
            }
            .frame(width: 38, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(recorder.isRecording
                    ? Color(red: 0.86, green: 0.22, blue: 0.20).opacity(0.7)
                    : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("EchoelVideo monitor")
        .accessibilityValue(recorder.isRecording ? "Recording" : "Idle")
        .accessibilityHint("Opens the recorded clips library")
    }
}
#endif
#endif
