#if canImport(SwiftUI)
import SwiftUI

/// Chrome → instrument channel: the TransportBar's pulse button posts this; the
/// studio (which owns the start/stop logic + camera/evolve lifecycle) listens and
/// toggles. Decoupled — the chrome never reaches into the studio view.
extension Notification.Name {
    static let echoelToggleBio = Notification.Name("echoel.toggleBio")
    /// Chrome → studio global doors (founder 2026-07-12 shell v3: "Master,
    /// Export, Live und Learn kommt oben in die Leiste neben das Schloss").
    /// `object` = the door name ("master" · "export" · "live" · "learn"); the
    /// studio listens and opens its dropdown/sheet — same decoupling as the
    /// pulse button, the chrome never reaches into studio state.
    static let echoelChromeDoor = Notification.Name("echoel.chromeDoor")
}

// WorkspaceView.swift
// Echoel — the app HOME: the bio-generative instrument. Founder re-focus
// 2026-07-06B ("die Leute brauchen gar keine Atemübung. Es geht um Performance
// und Entspannungssteigerung dadurch, dass sich die Musik mit dem Biofeedback
// generativ verändert"): the product IS the organic, professional generative
// music + visual driven by the live body — so the instrument is front and
// center again. The breathing-session experiment (SessionView/SessionEngine,
// the brief 2026-07-06A shell flip) is REMOVED from navigation — the code
// stays in the tree, compiling and reversible, but nothing presents it.
//
// Shell = brand header (topBar) + persistent TransportBar + SurfaceHost — which
// IS the one main view (founder 2026-07-10: the Ableton-arrangement layout,
// timeline over instrument zone; the 4-chip surface switcher is unmounted) +
// the floating immersive visual.
//
// Render safety (skill: swiftui-render-safety):
//  • No modal is owned here (the brief Pro-unlock sheet was removed with the
//    2026-07-10 free-instrument decision) — EchoelStudioView's ~18-modal chain
//    is untouched. ONE lightweight shell sheet would be safe if v1.1 Live
//    needs it; never more without consolidating first.
//  • No high-frequency @Observable is read in this body; the header monitor
//    reads only the LOW-frequency isRunning flag. Live bio lives in leaves
//    (BioStripView, PulseMonitorMiniLive).
//  • The surface selection is @AppStorage (changes on user tap only).

@MainActor
struct WorkspaceView: View {

    /// LOW-frequency flag only (isRunning = start/stop) — never a ~10 Hz value
    /// in this body (freeze rule 10.76.50).
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    /// The immersive visual rides along as a FLOATING, resizable, show/hide window —
    /// toggled from the header monitor, persisted across launches. Default TRUE so
    /// the living visual greets the user immediately ("wow von Sekunde 1"); it's
    /// flash-safe + reduce-motion-aware and one tap to hide, and @AppStorage
    /// remembers a user who hides it (only fresh installs auto-show).
    @AppStorage("visual.floating.visible") private var floatingVisualVisible = true

    /// Tapping the brand (mark + name) opens the website in the system default
    /// browser (founder 2026-07-07) — where the current version + TestFlight
    /// signup live.
    @Environment(\.openURL) private var openURL
    private static let websiteURL = URL(string: "https://echoelmusic.com")

    // Monetization (founder 2026-07-10, second decision of the day — supersedes
    // the same-day one-time-Pro): the INSTRUMENT is fully free; revenue comes in
    // v1.1 as the "Echoel Live" YEARLY subscription (worldwide SharePlay
    // sessions, ~29,99 €/y) + a per-event host fee (consumable IAP) in v1.2.
    // Therefore v1.0 shows NO purchase UI — the Pro chip + sheet that briefly
    // lived here are removed from presentation. ProUnlockView/EchoelStore/
    // ProGate stay in code, compiling, to be REPURPOSED for the Live sub —
    // do not delete, do not re-present before v1.1.

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(EchoelTheme.border)
                TransportBar()
                Divider().overlay(EchoelTheme.border)
                // THE one main view (founder 2026-07-10): Arrange timeline over
                // the instrument zone — no surface chips, no view-switching.
                SurfaceHost()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The immersive visual floats ABOVE the whole screen so its FULLSCREEN size can
            // cover the chrome too (true Vollbild). In the floating sizes it docks
            // bottom-trailing; its transparent area never blocks the header/transport (an
            // empty GeometryReader installs no hit target). One Metal path app-wide (GPU rule).
            #if canImport(MetalKit) && canImport(UIKit)
            if floatingVisualVisible {
                FloatingVisualWindow(isPresented: $floatingVisualVisible)
            }
            #endif
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
        // Bottom-edge protection (founder 2026-07-12: "das Fenster von
        // Echoelmusic will sich schließen, wenn man am unteren Bildschirmrand
        // ist"): the iOS home-indicator swipe and our bottom controls (bio
        // strip, track chips) fight for the same edge. Deferring the system
        // gesture makes the FIRST swipe reach the app; leaving the app takes a
        // deliberate second swipe (standard for games/DAWs). We do NOT hide
        // the indicator (persistentSystemOverlays) — the way home must stay
        // visible, it just must not fire mid-performance.
        #if os(iOS)
        .defersSystemGestures(on: .bottom)
        #endif
    }

    /// Persistent brand header — always on screen. Centre: "Echoelmusic" + the running
    /// version/build. Left: app mark (the live pulse number lives once in the bio strip,
    /// not here). Right: the immersive-visual monitor, which shows/hides the floating
    /// visual. Uncodixfy-compliant.
    private var topBar: some View {
        ZStack {
            Button { openWebsite() } label: {
                VStack(spacing: 1) {
                    Text("Echoelmusic")
                        .font(EchoelTheme.font(14, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text(Self.versionString)
                        .font(EchoelTheme.font(9))
                        .foregroundStyle(EchoelTheme.dim)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Echoelmusic \(Self.versionString)")
            .accessibilityHint("Opens echoelmusic.com — release notes and TestFlight signup")
            HStack(spacing: 8) {
                Button { openWebsite() } label: {
                    EchoelLogoMark().frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                // The centred title button already announces + opens the website —
                // two adjacent VoiceOver stops for one action is noise (AX audit).
                .accessibilityHidden(true)
                // The live pulse monitor (trace + BPM), between logo and title
                // (founder 2026-07-12: "Der Pulsmonitor kommt nach oben zwischen
                // Logo und Echoelmusic"). A LEAF that reads the ~10 Hz publisher in
                // its OWN body (freeze rule 10.76.50) — WorkspaceView stays still.
                #if canImport(AVFoundation)
                PulseMonitorMiniLive()
                #endif
                Spacer(minLength: 0)
                // RIGHT: the three output monitors — Video · Lux · BioSynth visual
                // (founder 2026-07-12, red sketch: "oben neben dem EchoelBioSynth
                // Monitor noch 2 Fenster … eins für EchoelVideo und eins für
                // EchoelLux"). Klang · Bild · Licht in one header row. Each is a
                // LEAF that reads its own live state (freeze rule); taps go through
                // the chrome-door notification, never into studio state directly.
                #if canImport(AVFoundation) && canImport(Metal)
                EchoelVideoMonitorMini()
                #endif
                EchoelLuxMonitorMini()
                // The immersive-visual monitor. (No purchase chip in v1.0 —
                // everything is free; "Echoel Live" arrives as the v1.1 subscription.)
                // `isRunning` is a LOW-frequency read (start/stop), safe in this body; the
                // live waveform stays in its own leaf.
                #if canImport(AVFoundation)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { floatingVisualVisible.toggle() }
                } label: {
                    ImmersiveMonitorMini(active: cameraRPPG.isRunning)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(floatingVisualVisible ? "Hide floating visual" : "Show floating visual")
                #endif
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(EchoelTheme.bg)
    }

    /// Open the website in the system default browser (no-op if the URL fails to
    /// parse, which it can't for the constant above — defensive).
    private func openWebsite() {
        guard let url = Self.websiteURL else { return }
        openURL(url)
    }

    /// Short version + build, e.g. "v10.35.2 (1550)" — from the bundle, so it always
    /// reflects the actual installed build.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }
}

// MARK: - Persistent transport bar (DAW chrome)

/// Always-on transport across the instrument: Play/Stop on the left, the Tempo field, and
/// a bars.beats.sixteenths position readout on the right. A LEAF view so its reads never
/// rebuild the instrument tree. It reads only the LOW-frequency Transport state (isPlaying,
/// tempo); the ~10 Hz position lives in its own `TransportPositionView` leaf so the
/// buttons/field don't churn (freeze rule). Play/Stop drives PatternEngine — the clock that
/// RELAYS into Transport — so the position/tempo shown stay authoritative.
@MainActor
private struct TransportBar: View {
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player
    @Environment(MetronomeVoice.self) private var metronome
    /// LOW-frequency instrument run state (set on Start/Stop only) — mirrors the
    /// studio so the pulse button shows the right state. Never a ~10 Hz read.
    @Environment(EngineBus.self) private var bus
    // Shared with the Compose panel (same @AppStorage keys + defaults). Read here so a
    // transport-bar tempo edit while LOCKED also persists the locked value — otherwise the
    // next generate() would snap the clock back to the stale lockedBPM.
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    var body: some View {
        HStack(spacing: 12) {
            Button { toggle() } label: {
                Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.text)
                    .frame(width: 38, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // 44 pt touch target (HIG) — the visible chip stays 38×32, the hit
            // area fills the bar height (performance control, AX audit 2026-07-09).
            .contentShape(Rectangle().inset(by: -6))
            .accessibilityLabel(transport.isPlaying ? "Stop" : "Play")

            // THE pulse button — Start/Stop of the bio-generative instrument, in the
            // chrome next to Play (founder 2026-07-12: the big "Create from Within"
            // CTA is gone; "der Button mit dem Pulszeichen kommt neben das Play
            // oben"). Green ring = the body is live (green is reserved for live bio).
            pulseButton

            // NO tempo number here anymore (founder 2026-07-04: "zwei Anzeigen irritieren
            // immernoch") — the chrome's one live number is the PULSE in the bio strip. The
            // musical tempo lives in the Composition panel's BodyTempoField (runs along with
            // the biofeedback rate, 4 decimals, lockable). The lock stays here for one-tap
            // freezing from anywhere; its state mirrors the panel (same @AppStorage).

            lockButton

            // Global doors in the chrome, next to the lock (founder 2026-07-12,
            // shell v3): Master · Export · Live · Learn. Icon chips posting the
            // door notification — the studio opens its dropdown/sheet.
            doorButton("slider.vertical.3", door: "master",
                       a11y: "Master — loudness, output")
            doorButton("square.and.arrow.up", door: "export",
                       a11y: "Export — WAV loop")
            #if canImport(MultipeerConnectivity)
            doorButton("dot.radiowaves.left.and.right", door: "live",
                       a11y: "Live Colabo — play together nearby")
            #endif
            doorButton("book", door: "learn",
                       a11y: "Learn and news")

            Spacer(minLength: 0)

            TransportPositionView()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(EchoelTheme.bg)
    }

    /// Start/Stop the bio-generative instrument from the chrome. Posts the toggle
    /// notification; the studio (owner of camera/evolve/voices lifecycle) handles it —
    /// the exact same path as the old "Create from Within" button and the Siri intents.
    private var pulseButton: some View {
        Button {
            NotificationCenter.default.post(name: .echoelToggleBio, object: nil)
        } label: {
            Image(systemName: bus.instrumentRunning ? "stop.circle.fill" : "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(bus.instrumentRunning ? EchoelTheme.accent : EchoelTheme.text)
                .frame(width: 38, height: 32)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(bus.instrumentRunning ? EchoelTheme.accent : EchoelTheme.border,
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -6))   // 44 pt-class target (HIG)
        .accessibilityLabel(bus.instrumentRunning ? "Stop the body instrument"
                                                  : "Create from within — start biofeedback")
        .accessibilityHint("Your body composes and plays the music. Tap again to stop.")
    }

    /// FIX the tempo, one tap, always reachable (founder: "Tempo fixen muss aber auch immer
    /// gehen"). Locking freezes the tempo you're hearing right now and stops the body's gentle
    /// tempo-follow — from then on biofeedback only shapes the SOUND (filter/timbre), never the
    /// beat. Same `studio.lockBPM`/`lockedBPM` state as the Composition panel's toggle, so both
    /// stay in sync; freezing here captures the live tempo directly (robust even when that panel
    /// is collapsed and its onChange isn't mounted).
    private var lockButton: some View {
        Button {
            lockBPM.toggle()
            if lockBPM {
                lockedBPM = transport.tempo.rounded()
                player.pattern.setTempo(lockedBPM)   // freeze exactly what's playing (no jump)
                metronome.bpm = transport.tempo
            }
        } label: {
            Image(systemName: lockBPM ? "lock.fill" : "lock.open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(lockBPM ? EchoelTheme.accent : EchoelTheme.dim)
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(lockBPM ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -6))   // 44 pt-class target (HIG)
        .accessibilityLabel(lockBPM ? "Tempo locked — tap to let it follow the body" : "Lock tempo")
        .accessibilityHint("When locked, the beat holds and biofeedback only shapes the sound")
    }

    /// One compact chrome door: posts the studio's door notification.
    private func doorButton(_ icon: String, door: String, a11y: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .echoelChromeDoor, object: door)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EchoelTheme.text)
                .frame(width: 30, height: 32)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -5))
        .accessibilityLabel(a11y)
    }

    private func toggle() {
        if transport.isPlaying { player.pattern.stop() }
        else { player.pattern.play() }
    }
}

/// The moving playhead — bars.beats.sixteenths (1-based, DAW convention). Isolated in
/// its OWN leaf because `transport.position` updates on every step (~10 Hz at 120 BPM);
/// keeping the read here means only this tiny label rebuilds, never the transport bar's
/// buttons/field or (crucially) the instrument below. Monospaced so width is steady.
@MainActor
private struct TransportPositionView: View {
    @Environment(Transport.self) private var transport
    /// The loop size (shared @AppStorage with the Compose panel). Read here so the chrome
    /// always SHOWS how big the loop is + where we are inside it (founder: "optische Anzeige,
    /// je nachdem wie groß der Loop umgestellt ist"). Low-frequency — safe in this leaf.
    @AppStorage("studio.loopBars") private var loopBars: LoopBarLength = .four

    var body: some View {
        let pos = transport.position
        let bars = max(1, loopBars.rawValue)
        let barInLoop = pos.bar % bars                 // 0-based bar within the current loop
        let sixteenth = pos.step % Transport.stepsPerBeat
        // Fraction through the whole loop (bars × 16 steps) — drives the slim progress bar.
        let loopFraction = Double(barInLoop * Transport.stepsPerBar + pos.step)
            / Double(bars * Transport.stepsPerBar)
        return HStack(spacing: 8) {
            // Slim loop-progress bar: fills once per loop so the loop length is legible at a
            // glance (opacity/fill only — no glow, per the UI rules).
            ZStack(alignment: .leading) {
                Capsule().fill(EchoelTheme.text.opacity(0.12)).frame(width: 44, height: 4)
                Capsule().fill(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: 44 * max(0.02, loopFraction), height: 4)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%d.%d.%d", barInLoop + 1, pos.beat + 1, sixteenth + 1))
                    .font(EchoelTheme.font(14, .medium).monospacedDigit())
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
                Text("loop \(barInLoop + 1)/\(bars)")
                    .font(EchoelTheme.font(10).monospacedDigit())
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue("Bar \(barInLoop + 1) of \(bars), beat \(pos.beat + 1)")
    }
}
#endif
