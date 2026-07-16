#if canImport(SwiftUI)
import SwiftUI

/// Chrome → instrument channel: the TransportBar's pulse button posts this; the
/// studio (which owns the start/stop logic + camera/evolve lifecycle) listens and
/// toggles. Decoupled — the chrome never reaches into the studio view.
extension Notification.Name {
    static let echoelToggleBio = Notification.Name("echoel.toggleBio")
    /// Header pill → studio: pick the BIO input source (founder 2026-07-15 video:
    /// "Lange drücken = drop down: camera light · Search for Bluetooth Device ·
    /// Simulation"). `object` = the source id ("camera" · "ble" · "sim"); the studio
    /// owns all three publishers and switches the active one — same decoupling as the
    /// toggle (the chrome never reaches into studio state).
    static let echoelSelectBioSource = Notification.Name("echoel.selectBioSource")
    /// Studio → app layer: a user-initiated take's bio source finished starting
    /// (posted AFTER `startBioSource()` returns, so any camera permission dialog
    /// has already been answered — no stacked system sheets). The app uses it to
    /// run the HealthKit ask at a REAL bio-use moment instead of context-free at
    /// launch (UX-3). Same chrome/app decoupling as the toggle above.
    static let echoelBioSourceStarted = Notification.Name("echoel.bioSourceStarted")
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

    /// The VIDEO MONITOR floats the same way (founder 2026-07-15: the header film
    /// tile opens it, "Verschiedene größen einstellbar wie visualiser"). Default
    /// hidden — it earns its screen space once video clips exist on the timeline;
    /// @AppStorage remembers a user who keeps it open.
    @AppStorage("video.monitor.visible") private var videoMonitorVisible = false

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
                // (The standalone Tempo row is gone — the tempo control moved UP into
                //  the transport bar next to Play, founder 2026-07-15 "Das soll da oben
                //  hin". Its vertical band is reclaimed for the timeline.)
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
            // The floating VIDEO MONITOR — the timeline's video lanes rendered at the
            // playhead (stills + video), toggled from the header film tile. Docks
            // bottom-leading so it coexists with the visual window. Its ~10 Hz
            // transport follow is confined to its own content leaf (freeze rule).
            #if canImport(AVFoundation)
            if videoMonitorVisible {
                FloatingVideoMonitor(isPresented: $videoMonitorVisible)
            }
            #endif
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
            .accessibilityHint("Opens echoelmusic.com — release notes and support")
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
                EchoelVideoMonitorMini(monitorVisible: videoMonitorVisible) {
                    withAnimation(.easeInOut(duration: 0.15)) { videoMonitorVisible.toggle() }
                }
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
    // The ONE transport plays the ARRANGEMENT when the timeline has regions (founder
    // 2026-07-15 video: "zu viele Play Knöpfe, einer reicht" — the separate "Play
    // timeline" button is gone). These are read ONLY inside toggle()'s action, never in
    // body, so the transport bar subscribes to none of them (freeze rule).
    @Environment(TimelineStore.self) private var timeline
    @Environment(ClipStore.self) private var clips
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(TimelineRegionPlayer.self) private var timelinePlayer
    /// Read ONLY inside toggle() (a tap handler, not body) for the UX-2 empty-project
    /// branch — `instrumentRunning` is the Start/Stop-frequency chrome mirror, and a
    /// closure read registers no body observation anyway (freeze rule intact).
    @Environment(EngineBus.self) private var bus

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

            // (The transport pulse button is GONE — founder 2026-07-15 video: "zu viele
            //  Play Knöpfe, einer reicht." Bio activation moved to the pulse pill next to
            //  the E-logo in the brand header: TAP = start/stop, long-press = pick source.
            //  The pill posts the exact same `.echoelToggleBio` the button used to.)

            // THE tempo control, up in the transport chrome next to Play (founder
            // 2026-07-15 "Das soll da oben hin", "beide behalten" — the pulse monitor
            // stays in the brand header above; the wasteful full-width Tempo row is
            // gone). Compact 4-decimal field + its lock. A self-contained LEAF that
            // reads the ~10 Hz pulse in its OWN body, so the transport bar / root never
            // subscribe to the churn (freeze rule, same as PulseMonitorMiniLive).
            BodyTempoField(compact: true)

            // Global doors, grouped into ONE overflow menu (founder 2026-07-12 placed
            // Master · Export · Live · Learn "oben in die Leiste"; collapsing them to a
            // single "•••" frees the width for the tempo WITHOUT touching the brand
            // header — fully reversible). Each entry still posts its chrome-door
            // notification; the studio opens its dropdown/sheet.
            Menu {
                doorMenuButton("Master — loudness, output", icon: "slider.vertical.3", door: "master")
                doorMenuButton("Export — WAV loop", icon: "square.and.arrow.up", door: "export")
                #if canImport(MultipeerConnectivity)
                doorMenuButton("Live Colabo — play together nearby",
                               icon: "dot.radiowaves.left.and.right", door: "live")
                #endif
                doorMenuButton("Learn and news", icon: "book", door: "learn")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 30, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("More — Master, Export, Live, Learn")

            Spacer(minLength: 0)

            TransportPositionView()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(EchoelTheme.bg)
    }

    /// One chrome-door entry inside the transport bar's "•••" overflow menu: posts
    /// the studio's door notification (same decoupling as before — the chrome never
    /// reaches into studio state).
    private func doorMenuButton(_ title: String, icon: String, door: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .echoelChromeDoor, object: door)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func toggle() {
        if transport.isPlaying {
            // Stop whichever engine is running: timeline-follow releases its region clips
            // + secondary-lane voices; a plain pattern loop just stops.
            // T1 breadcrumb: name the finger BEFORE the stop cascades — the 2361 log's
            // source-less "transport-stopped" burned a triage cycle proving it was a tap.
            EchoelCrashLog.breadcrumb("stop source: transport-bar ■ (\(timelinePlayer.isPlaying ? "timeline" : "pattern"))")
            if timelinePlayer.isPlaying { timelinePlayer.stop() }
            else { player.pattern.stop() }
        } else {
            // Play the SONG if anything is arranged on the timeline, else the live loop.
            // timelinePlayer.play starts the shared pattern itself and chains the region
            // clips via the always-on onTick relay (PianoRollView) — so this ONE button
            // covers both the loop and the arrangement.
            let doc = timeline.document
            // Playable = a MIDI (roll) lane OR an audio lane exists (A1: a pure-audio
            // arrangement must sound too — the old rollLaneID-only check silenced it).
            if doc.rollLaneID != nil || !doc.audioLaneIDs.isEmpty, !doc.regions.isEmpty {
                // CLIP-5: start at the PARKED playhead's bar (drag-then-play), not
                // always bar 1. Read the position BEFORE play — pattern.play() →
                // transport.play() zeroes it.
                let parkedTick = transport.position.absoluteStep * TimelineTime.ticksPerTransportStep
                timelinePlayer.play(document: doc, clips: clips,
                                    pattern: player.pattern, pianoRoll: pianoRoll,
                                    fromTick: parkedTick)
                // Show the REAL start bar (the player folded/clamped the tick).
                if timelinePlayer.isPlaying, timelinePlayer.currentTick > 0 {
                    transport.seek(toBar: timelinePlayer.currentTick / TimelineTime.ticksPerBar)
                }
            } else if doc.regions.isEmpty,
                      !player.pattern.steps.contains(where: { $0.contains(true) }),
                      pianoRoll.notes.isEmpty, !bus.instrumentRunning {
                // UX-2 (first-run silence): NOTHING is composed anywhere — no timeline
                // region of ANY kind (explicit: a video-only arrangement must fall to
                // pattern.play() below, not get generative music it never asked for),
                // no drum step, no roll note. pattern.play()
                // would move the playhead over pure silence and a new user concludes
                // the app is broken. The one obvious ▶ must SOUND: start the
                // bio-generative instrument through the exact notification the header
                // pulse pill posts (the studio owns start/stop; chrome stays decoupled).
                // generate() starts the transport itself, so ▶ flips to ■ honestly.
                // Guarded on instrumentRunning so a tap in the brief start window
                // (before the first roll notes land) can't toggle the session OFF.
                EchoelCrashLog.breadcrumb("play: empty project → universal Start (toggleBio)")
                NotificationCenter.default.post(name: .echoelToggleBio, object: nil)
            } else {
                player.pattern.play()
            }
        }
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
    // Default MUST match the semantic owner EchoelStudioView.loopBars (= .eight,
    // founder: 8-bar produce-able phrase). @AppStorage defaults are PER-DECLARATION:
    // on a fresh install (key unwritten) a diverging copy here showed "loop N/4"
    // while the instrument composed 8 bars (H15-LOOPBARS).
    @AppStorage("studio.loopBars") private var loopBars: LoopBarLength = .eight

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
