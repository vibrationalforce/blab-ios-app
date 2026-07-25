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
    /// Live acquisition coaching (device log 2026-07-14: the pulse washed out to
    /// saturation silently while playing). When it is ACTIONABLE and not locked, the
    /// trace goes amber and the BPM slot shows the short cue so the drop is visible +
    /// self-correctable — the founder's "tap for more info" detail still carries the
    /// full guidance. nil / not-actionable / locked ⇒ the plain monitor.
    var cue: PulseCue? = nil
    /// BLE strap status (BLE-1, device log 2361: the founder's first strap scans
    /// looked dead and were aborted <5 s). `short` fills the BPM slot while no
    /// pulse flows; `full` carries the VoiceOver/coaching text. nil ⇒ plain monitor.
    var status: (short: String, full: String)? = nil

    /// Show the amber coaching cue: a correctable placement issue while not locked.
    private var showCue: Bool { !locked && (cue?.isActionable ?? false) }

    /// Show the strap status text: no lock, no camera cue competing for the slot.
    private var showStatus: Bool { !locked && !showCue && status != nil }

    var body: some View {
        HStack(spacing: 6) {
            PulseTrace(samples: waveform,
                       color: locked ? EchoelTheme.accent : (showCue ? EchoelTheme.warning : EchoelTheme.dim))
                .frame(width: 50, height: 24)
            Group {
                if locked && bpm > 0 {
                    Text("\(Int(bpm))")
                        .font(EchoelTheme.font(11, .semibold)).monospacedDigit()
                        .foregroundStyle(EchoelTheme.text)
                } else if showCue, let cue {
                    Text(cue.shortLabel)
                        .font(EchoelTheme.font(9, .semibold))
                        .foregroundStyle(EchoelTheme.warning)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else if showStatus, let status {
                    Text(status.short)
                        .font(EchoelTheme.font(9, .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("—")
                        .font(EchoelTheme.font(11, .semibold)).monospacedDigit()
                        .foregroundStyle(EchoelTheme.dim)
                }
            }
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
        if showCue, let cue { return cue.fullHint }
        if showStatus, let status { return status.full }
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
    #if canImport(CoreBluetooth)
    @Environment(PolarH10BioPublisher.self) private var polarH10
    #endif

    /// BLE strap status for the pill (BLE-1): only while the strap publisher is
    /// the active source (publishing, camera off). `state` changes at scan/connect
    /// lifecycle only — a low-frequency read, freeze-rule safe in this leaf.
    private func strapStatus(cameraLive: Bool, hasLiveFrames: Bool) -> (short: String, full: String)? {
        #if canImport(CoreBluetooth)
        guard polarH10.isPublishing, !cameraLive else { return nil }
        return PolarH10BioPublisher.statusLabel(for: polarH10.state,
                                                deviceName: polarH10.connectedDeviceName,
                                                hasLiveFrames: hasLiveFrames)
        #else
        return nil
        #endif
    }

    var body: some View {
        // The pill reflects whichever source is live (founder 2026-07-15 source picker):
        //   • Camera — a real PPG waveform + the CALM `displayBPM` (holds the last
        //     confident reading through noise) + lock.
        //   • A BLE strap or the Simulation demo — the BPM comes from the bus snapshot
        //     (no per-sample waveform exists off-camera → the trace stays honestly flat,
        //     no fabricated line). A fresh bus frame counts as "locked" so the number and
        //     accent show. Reading cameraRPPG + bus.freshBio() HERE keeps the 10 Hz churn
        //     in this leaf (freeze rule); WorkspaceView never subscribes.
        let fresh = bus.freshBio()
        let cameraLive = cameraRPPG.isRunning
        PulseMonitorMini(waveform: cameraRPPG.waveform,
                         bpm: cameraLive ? cameraRPPG.displayBPM : Double(fresh?.heartRateBPM ?? 0),
                         locked: cameraLive ? cameraRPPG.isLocked : (fresh != nil),
                         coherence: fresh.map { Double($0.coherence) },
                         // Only the camera has an acquisition cue ("cover the lens"); a
                         // strap/sim monitor stays plain. Denied access must surface even
                         // though the camera is NOT running (it can never run — UX-1) —
                         // but not while ANOTHER source delivers a live body (fresh frames).
                         // `permissionDenied` is a low-frequency start-attempt flag and this
                         // pill is already the 10 Hz leaf, so the freeze rule holds.
                         cue: (cameraRPPG.permissionDenied && fresh == nil) ? .cameraDenied
                             : (cameraLive ? cameraRPPG.acquisitionCue : nil),
                         // BLE-1: while the strap is the source, the scan/connect
                         // lifecycle is VISIBLE here instead of a dead flat trace.
                         status: strapStatus(cameraLive: cameraLive,
                                             hasLiveFrames: fresh != nil))
            // E-Bio-Header — bio's HOME is this header pill (founder 2026-07-14 +
            // 2026-07-15 video: "Wenn Biofeedback aktiviert werden soll drückt man
            // einfach oben rechts neben dem Echoel Icon drauf. Lange drücken = drop
            // down: camera light · Search for Bluetooth Device · Simulation").
            //   • TAP starts/stops the bio-generative instrument (the exact
            //     `.echoelToggleBio` the removed transport pulse button used to post —
            //     "einer reicht", the duplicate button is gone).
            //   • LONG-PRESS opens the SOURCE dropdown: pick Camera light / a Bluetooth
            //     strap / the Simulation demo; the studio owns all three publishers and
            //     switches the live one (decoupled via .echoelSelectBioSource). A "Bio
            //     details…" entry still reaches the full HR/HRV/routing panel (chrome
            //     door "bio") so nothing is stranded.
            // `.contextMenu` builds its content only when opened (not at body time), so
            // this adds NO 10 Hz read to the pill's body — freeze rule intact.
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .echoelToggleBio, object: nil)
            }
            .contextMenu {
                Button {
                    NotificationCenter.default.post(name: .echoelSelectBioSource, object: "camera")
                } label: { Label("Camera light", systemImage: "camera.fill") }
                Button {
                    NotificationCenter.default.post(name: .echoelSelectBioSource, object: "ble")
                } label: { Label("Search for Bluetooth device", systemImage: "dot.radiowaves.left.and.right") }
                Button {
                    NotificationCenter.default.post(name: .echoelSelectBioSource, object: "sim")
                } label: { Label("Simulation", systemImage: "waveform.path") }
                Divider()
                Button {
                    NotificationCenter.default.post(name: .echoelChromeDoor, object: "bio")
                } label: { Label("Bio details…", systemImage: "info.circle") }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(cameraRPPG.isRunning
                ? "Tap to stop your pulse reading. Touch and hold to choose a bio source or open details."
                : "Tap to start reading your pulse. Touch and hold to choose a bio source or open details.")
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
    /// Flash-safety + accessibility: freeze the per-beat brightness pulse when the
    /// system Reduce Motion setting is on (the pulse rate is separately capped ≤2.5 Hz
    /// for everyone in `tileColor`).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    // Colour work lives in the pure helper below — inlining the
                    // Double/Float mix here sent the type-checker into "unable to
                    // type-check in reasonable time" (Xcode gate, d41c13d).
                    RadialGradient(colors: [Self.tileColor(bio: bus.freshBio(),
                                                           mf: bus.freshMusical(maxAge: 1.0),
                                                           date: tl.date,
                                                           reduceMotion: reduceMotion),
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
        // 44 pt HIG tap height (#113): the visible chip stays 32, the hit area grows
        // vertically only — the header row is 8 pt-spaced, so NO horizontal expansion
        // (that would overlap the neighbour tiles). Chip stays centred = no visible change.
        .frame(height: 44)
        .contentShape(Rectangle())
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
    /// Flash-safety (WCAG epilepsy ≤3 Hz + the app's own ceiling): the tile's brightness-
    /// pulse rate in Hz, CAPPED at 2.5 Hz so even a very fast heart rate can never drive
    /// the tile past the epilepsy-safe flash rate. Matches MetalBioView's 2.5 Hz ceiling.
    /// Pure + testable — the law lives in one place, not inlined in the render.
    static func flashSafePulseRate(heartRateBPM: Double) -> Double {
        min(max(40.0, heartRateBPM) / 60.0, 2.5)
    }

    static func tileColor(bio: BioSampleFrame?, mf: MusicalFrame?, date: Date,
                          reduceMotion: Bool) -> Color {
        let rate: Double = flashSafePulseRate(heartRateBPM: Double(bio?.heartRateBPM ?? 60))
        let phase: Double = (date.timeIntervalSinceReferenceDate * rate)
            .truncatingRemainder(dividingBy: 1.0)
        // Reduce Motion → hold a steady mid-brightness instead of the per-beat pulse.
        let pulse: Double = reduceMotion ? 0.5 : (0.5 - 0.5 * cos(phase * 2.0 * .pi))  // 0…1 per beat
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
    /// Flash-safety + accessibility (WCAG epilepsy ≤3 Hz): freeze the music-driven
    /// hue animation when the system Reduce Motion setting is on. Mirrors the sibling
    /// `ImmersiveMonitorMini` (#112) — the always-on chrome must obey the same law.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    if reduceMotion {
                        // Reduce Motion → drop the animation timer entirely; the colour
                        // then changes only when a new musical frame is published (via the
                        // observed `latestMusical`), never on a synthetic clock.
                        Self.lightColor(mf: bus.freshMusical(maxAge: 1.5))
                    } else {
                        // Reduce the synthetic redraw timer from 10 Hz to 2.5 Hz (the app's
                        // MetalBioView/ImmersiveMonitorMini ceiling) + honour Reduce Motion
                        // above — bringing this tile to the SAME flash policy as its sibling
                        // (#112). HONEST CAVEAT: like the sibling, the music-driven hue is a
                        // content signal (chord × dimmer), not a synthetic oscillator — the
                        // observed `latestMusical` read still re-renders at the musical-frame
                        // rate, so this timer bounds the synthetic redraws, not a hard ≤3 Hz
                        // content-flash cap. A true content slew (applied to BOTH tiles) is a
                        // separate follow-up; this slice reaches sibling parity.
                        TimelineView(.animation(minimumInterval: 1.0 / 2.5)) { _ in
                            Self.lightColor(mf: bus.freshMusical(maxAge: 1.5))
                        }
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
            // 44 pt HIG tap height (#113): vertical-only (8 pt header spacing forbids
            // horizontal growth); the 38×32 chip stays centred, no visible change.
            .frame(height: 44)
            .contentShape(Rectangle())
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
/// "… und eins für EchoelVideo"). TAP shows/hides the floating VIDEO MONITOR —
/// the resizable window rendering the timeline's video lanes at the playhead
/// (founder 2026-07-15, red circle on this tile: "Dort soll der Video Monitor zum
/// anklicken. Verschiedene größen einstellbar wie visualiser"). LONG-PRESS keeps
/// the recorded-clips library reachable (the tile's former tap action — nothing
/// is stranded). While the visual recorder captures a clip it shows a steady REC
/// state (steady, not blinking — flash law). Deliberately NOT a live thumbnail:
/// that would be a second video pipeline in the header; the floating monitor IS
/// the one live picture.
@MainActor
struct EchoelVideoMonitorMini: View {
    @Environment(VisualRecorder.self) private var recorder
    /// True while the floating video monitor is shown — the tile tints so the
    /// toggle state is visible (same idea as the visual monitor's active state).
    let monitorVisible: Bool
    /// Show/hide the floating video monitor (owned by WorkspaceView).
    let onToggleMonitor: () -> Void

    var body: some View {
        Button {
            onToggleMonitor()
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
                        .foregroundStyle(recorder.isRecording || monitorVisible
                                         ? EchoelTheme.text : EchoelTheme.dim)
                }
            }
            .frame(width: 38, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(recorder.isRecording
                    ? Color(red: 0.86, green: 0.22, blue: 0.20).opacity(0.7)
                    : (monitorVisible ? EchoelTheme.accent.opacity(0.6) : EchoelTheme.border),
                    lineWidth: 1))
            // 44 pt HIG tap height (#113): vertical-only (8 pt header spacing forbids
            // horizontal growth); the 38×32 chip stays centred, no visible change.
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Built only when opened — no extra body-time reads (freeze rule intact).
        .contextMenu {
            Button {
                NotificationCenter.default.post(name: .echoelChromeDoor, object: "video")
            } label: { Label("Clips library…", systemImage: "folder") }
        }
        .accessibilityLabel("Video monitor")
        .accessibilityValue(recorder.isRecording ? "Recording"
                            : monitorVisible ? "Monitor shown" : "Monitor hidden")
        .accessibilityHint("Shows or hides the floating video monitor. Touch and hold for the clips library.")
    }
}
#endif
#endif
