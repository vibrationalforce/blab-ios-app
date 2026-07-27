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
    /// Header composition strip / transport tempo → studio (bottom-bar dissolve
    /// step 2b, 2026-07-17): a musical setting was edited BY THE USER in the
    /// chrome. `object` = the field ("genre" · "key" · "scale" · "tuning" ·
    /// "a4" · "tempoLock"); the studio applies the audible side effects
    /// (retune · recompose) — same decoupling as the doors, the chrome never
    /// reaches into studio state. Posted ONLY from user interaction (Picker
    /// binding set / field commit), never from programmatic writes, so a
    /// project open can update the shared keys without triggering strip
    /// side effects that would clobber the loaded patch.
    static let echoelCompositionEdited = Notification.Name("echoel.compositionEdited")
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
//    (BioStripView, PulseMonitorMiniLive, SessionNamePreviewLeaf).
//  • The surface selection is @AppStorage (changes on user tap only).
//  • CompositionHeaderStrip (steps 2b/2c of the bottom-bar dissolve) is its own
//    leaf: it reads only shared @AppStorage keys + session.a4Hz (user-edit
//    frequency) — never a bio/playhead value — and talks to the studio only
//    via the .echoelCompositionEdited notification. The body-following BPM in
//    its session-name preview is confined to SessionNamePreviewLeaf's own body.

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
    /// flash-safe + reduce-motion-aware and one tap to hide.
    ///
    /// INSTRUMENT-HOME (founder 2026-07-22 vision Step 1, flag `instrumentHome`
    /// DEFAULT-ON): while the flag is on, the visual is not a rider — it is the app
    /// HOME, so each COLD LAUNCH re-shows it FULLSCREEN (see the `.onAppear` seed on
    /// the body). This deliberately supersedes the old "remember a user who hides it"
    /// contract: home is the instrument, the DAW is the secondary behind the visual's
    /// contract button. Turn the flag OFF (`FeatureFlags.set(.instrumentHome, false)`)
    /// and the persisted visible/size prefs are honored untouched again (old home).
    @AppStorage("visual.floating.visible") private var floatingVisualVisible = true

    #if canImport(MetalKit) && canImport(UIKit)
    /// The floating visual's snap size (SHARED key + default with FloatingVisualWindow;
    /// @AppStorage defaults are per-declaration, so the named `.small` constant keeps
    /// this coupled to the enum instead of a bare literal that would drift on reorder).
    /// Written ONLY by the instrument-home seed to open the visual fullscreen at launch;
    /// a low-frequency (user-set) value, safe in this body per the freeze rule.
    @AppStorage("visual.floating.size") private var floatingSizeRaw = FloatingVisualWindow.WindowSize.small.rawValue
    /// One-shot guard so the instrument-home seed runs ONCE per launch. Persists for
    /// the WorkspaceView instance lifetime (survives background/foreground), so a user
    /// who contracts to the DAW mid-session is not re-fullscreened until the next cold
    /// launch (founder vision Step 1).
    @State private var didSeedInstrumentHome = false
    #endif

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
                // The brand header, transport, and musical-identity strip form ONE calm
                // chrome block on a shared background — no internal hairlines (three stacked
                // full-width rules read as "banding"/venetian blinds, not front-tier). A
                // SINGLE rule below separates the whole chrome from the timeline content.
                //
                // Dynamic Type (a11y): the chrome bars are FIXED-height (topBar 50 /
                // TransportBar 44 / CompositionHeaderStrip 40 pt), so at Accessibility
                // sizes their text overruns/clips. Clamp JUST this chrome Group to
                // xxLarge (the largest non-accessibility size) — the instrument below
                // (SurfaceHost) is deliberately NOT clamped and keeps FULL Dynamic Type
                // for its EchoelValueField controls. Same fit-vs-unbounded tradeoff
                // ArrangeTimelineView already accepted. Group is layout-transparent in a
                // VStack (no spacing/structure change), adds no sheet, reads nothing.
                Group {
                    topBar
                    TransportBar()
                    // Step 2b of the bottom-bar dissolve (founder 2026-07-14: "Unten die
                    // Leiste sollte längst aufgelöst sein und sich an anderer Stelle
                    // wieder finden"): the musical identity — Genre · Key · Scale ·
                    // Tone system · Concert pitch A4 — lives HERE in the chrome, always
                    // visible, one thin row. A LEAF (low-frequency reads only).
                    CompositionHeaderStrip()
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                Divider().overlay(EchoelTheme.border)
                // (The standalone Tempo row is gone — the tempo control moved UP into
                //  the transport bar next to Play, founder 2026-07-15 "Das soll da oben
                //  hin". Its vertical band is reclaimed for the timeline.)
                // THE one main view: since the pure-instrument verdict (#121,
                // founder 2026-07-24 "keine Timeline etc nur das alte Interface
                // mit create from within") SurfaceHost mounts only EchoelStudioView
                // ("create from within") — no timeline, no surface chips.
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
        // INSTRUMENT-HOME seed (founder 2026-07-22 vision Step 1: "app open → it
        // lives", no menu/setup). When the flag is on, open directly into the living
        // instrument — the existing FloatingVisualWindow FULLSCREEN (the single Metal
        // path + the playable TouchInstrumentView). The DAW chrome (the VStack above)
        // stays MOUNTED beneath this overlay — never torn down — so EchoelStudioView's
        // onDisappear/stopEverything never fires and the live session (bio + transport)
        // survives; it is one tap (the visual's contract button) away. Runs ONCE per
        // launch (didSeedInstrumentHome), so contracting to the DAW mid-session sticks
        // until the next cold launch. Reversible: FeatureFlags.set(.instrumentHome,
        // false) → the persisted "remember last floating size" home returns untouched.
        // No bio/playhead value is read here (freeze rule); this adds no sheet to
        // EchoelStudioView's chain (the fullscreen visual is this overlay, not a modal).
        .onAppear {
            #if canImport(MetalKit) && canImport(UIKit)
            guard !didSeedInstrumentHome else { return }
            didSeedInstrumentHome = true
            if FeatureFlags.instrumentHome {
                floatingVisualVisible = true
                floatingSizeRaw = FloatingVisualWindow.WindowSize.fullscreen.rawValue
            }
            #endif
        }
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
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(Self.versionString)
                        .font(EchoelTheme.font(9))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1).minimumScaleFactor(0.7)
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
                // RIGHT: the output monitors — recorded Clips · Lux · BioSynth visual.
                // (The former video-lane monitor tile was retired with the DAW video
                // editing — pure-instrument cut; the tile now surfaces the recorded
                // performance clips + REC state.) Each is a LEAF that reads its own
                // live state (freeze rule); taps go through the chrome-door
                // notification, never into studio state directly.
                #if canImport(AVFoundation) && canImport(Metal)
                EchoelClipsMonitorMini()
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
    // ▶ is the INSTRUMENT's button and reads NOTHING from the timeline document
    // (founder 2026-07-27). The `TimelineStore` / `ClipStore` / `TimelineRegionPlayer`
    // reads that used to live here are gone — see toggle().
    // Read ONLY inside toggle()'s action, never in body, so the transport bar
    // subscribes to nothing (freeze rule).
    @Environment(PianoRollModel.self) private var pianoRoll
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
            // Lock/unlock/edit posts "tempoLock" so the studio recomposes to the new
            // musical tempo (step 2b: this hook lived on the Composition panel's full
            // BodyTempoField, which is gone — THE tempo control is this one).
            BodyTempoField(onLockChanged: {
                NotificationCenter.default.post(name: .echoelCompositionEdited,
                                                object: "tempoLock")
            }, compact: true)

            // Global doors, grouped into ONE overflow menu (founder 2026-07-12 placed
            // Master · Export · Live · Learn "oben in die Leiste"; collapsing them to a
            // single "•••" frees the width for the tempo WITHOUT touching the brand
            // header — fully reversible). Each entry still posts its chrome-door
            // notification; the studio opens its dropdown/sheet.
            Menu {
                doorMenuButton("Master — loudness, output", icon: "slider.vertical.3", door: "master")
                doorMenuButton("Export — WAV loop", icon: "square.and.arrow.up", door: "export")
                // Step 2b: the Comp chip fell; its tempo TOOLS (tap · metronome ·
                // haptic beat) + the variation maze stay reachable through this
                // door — same pattern as Master/Export (chrome-door-only panel).
                doorMenuButton("Tempo and variations — tap, metronome, ideas",
                               icon: "metronome", door: "tempo")
                // Step 2c: the Session chip fell; the live name preview moved into
                // the header CompositionHeaderStrip, and the place/weather toggles
                // that FEED the name stay reachable through this door — same
                // chrome-door-only pattern as Master/Export/Tempo. A Menu entry,
                // not a modal (the studio's presentation chain is untouched).
                doorMenuButton("Session — place and weather in the name",
                               icon: "mappin.and.ellipse", door: "session")
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
                        .strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
            }
            // 44 pt HIG tap target (#113): the visible chip stays 30×32; the transport
            // bar's 12 pt spacing lets the hit area grow symmetrically (−6 → 42×44)
            // without overlapping the tempo field, matching the Play button's idiom.
            .contentShape(Rectangle().inset(by: -6))
            .accessibilityLabel("More — Master, Export, Tempo, Session, Live, Learn")

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
            // T1 breadcrumb: name the finger BEFORE the stop cascades — the 2361 log's
            // source-less "transport-stopped" burned a triage cycle proving it was a tap.
            // The old two-branch stop (timeline-follow vs pattern) is gone with the
            // arrangement branch below: nothing can put `TimelineRegionPlayer` into
            // `isPlaying` any more, so a branch on it would have been dead code that
            // still reads like a live choice.
            EchoelCrashLog.breadcrumb("stop source: transport-bar ■")
            player.pattern.stop()
        } else {
            // ▶ PLAYS THE INSTRUMENT. It no longer consults the timeline document at all
            // (founder 2026-07-27: "Der ganze DAW Quatsch der nicht funktioniert hat soll
            // erstmal raus aus dem TestFlight").
            //
            // What it did, and why that had to go: the first branch here read the PERSISTED
            // arrangement and, if it held any real region, played THAT instead of the
            // instrument. On build 2469 that is exactly what happened — ▶ produced a
            // breakbeat imported into the session weeks earlier. Slice 4 (#130) removed the
            // arrangement UI, so since then the document has been invisible AND undeletable
            // while still owning the one transport button: a control that answers to data
            // the user can neither see nor reach. Removing the surface without removing its
            // authority is what made it a trap rather than a leftover.
            //
            // The drum-grid condition went with it. `pattern.steps` can still come back
            // non-empty from a pre-#166 project via `open(_:)`, and since the founder
            // removed the drums it CANNOT make a sound — so it suppressed the universal
            // Start below and delivered silence. A condition whose only remaining effect is
            // to withhold sound is not a guard.
            //
            // The model (`TimelineStore`, `ClipStore`, `TimelineRegionPlayer`) is untouched:
            // `TimelineRegionPlayer` still fans transport steps out to the secondary lane
            // voices, which is live. Only its ARRANGEMENT-PLAYBACK entry point is now
            // unreachable. Retiring the model itself is #132 Slice 5.
            if pianoRoll.notes.isEmpty, !bus.instrumentRunning {
                // UX-2 (first-run silence): nothing is composed and nothing is running, so
                // `pattern.play()` would just walk the playhead over silence and a new user
                // concludes the app is broken. The one obvious ▶ must SOUND: start the
                // bio-generative instrument through the exact notification the header pulse
                // pill posts (the studio owns start/stop; chrome stays decoupled).
                // generate() starts the transport itself, so ▶ flips to ■ honestly.
                // Guarded on instrumentRunning so a tap in the brief start window (before
                // the first roll notes land) can't toggle the session OFF.
                EchoelCrashLog.breadcrumb("play: nothing composed → universal Start (toggleBio)")
                NotificationCenter.default.post(name: .echoelToggleBio, object: nil)
            } else {
                player.pattern.play(cause: .transportButton)
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

// MARK: - Composition header strip (bottom-bar dissolve, steps 2b/2c)

/// The musical identity in the chrome: Genre · Key · Scale · Tone system · Concert
/// pitch A4 — plus, since step 2c, the live session-name preview (the stamped
/// identity those settings produce) — one thin always-visible row
/// (PLAN_DISSOLVE_BOTTOM_BAR_2026-07-14 steps 2b/2c — these rows lived in the
/// bottom menu bar's Composition/Session dropdowns; founder 2026-07-14: "Unten die
/// Leiste sollte längst aufgelöst sein und sich an anderer Stelle wieder finden").
/// THE tempo control is NOT duplicated here — it already lives in the TransportBar
/// (BodyTempoField, "einer reicht").
///
/// RENDER SAFETY (skill: swiftui-render-safety):
///  • A LEAF view reading ONLY low-frequency state — the shared @AppStorage keys
///    (EchoelStudioView stays the semantic owner; same keys + defaults) and
///    `session.a4Hz` (changes on user edit / project open only). No bio, playhead
///    or any ~10 Hz value is read in THIS body, so the Menu Pickers it hosts are
///    never torn down by churn (freeze rule 10.76.50). The one churny value in
///    the row — the live session-name preview, whose BPM runs along with the
///    body while the tempo is unlocked — is confined to `SessionNamePreviewLeaf`'s
///    OWN body (step 2c): only that label rebuilds, never this Picker host.
///  • No presentation modifier is added to any root: the only sheet is INSIDE
///    EchoelValueField's own leaf (the shared number pad), exactly like the
///    transport bar's BodyTempoField.
///
/// DECOUPLING (chrome ↔ studio law): the chrome never reaches into studio state.
/// Every USER edit posts `.echoelCompositionEdited` with the field name; the studio
/// listens (menu-bar onReceive, like `.echoelChromeDoor`) and applies the audible
/// side effects (retune · recompose). Posts happen in the Picker BINDING's set —
/// i.e. only when the user picks — so a programmatic write of the same shared key
/// (e.g. project open) updates the shown value WITHOUT triggering side effects
/// that would clobber the loaded patch.
@MainActor
struct CompositionHeaderStrip: View {
    @Environment(SessionContext.self) private var session

    // Shared with EchoelStudioView — same keys + defaults (@AppStorage defaults are
    // PER-DECLARATION: a diverging copy here would lie until the key is written).
    @AppStorage(StudioDefaultKeys.genre.key) private var style: MusicStyle = StudioDefaultKeys.genre.value
    @AppStorage(StudioDefaultKeys.rootIndex.key) private var rootIndex = StudioDefaultKeys.rootIndex.value
    @AppStorage(StudioDefaultKeys.scale.key) private var scale: Scale = StudioDefaultKeys.scale.value
    @AppStorage("toneSystemID") private var tuningID = "edo12"
    // M1 Flow/Loop: the mode IS the tempo lock (same shared keys as the transport-bar
    // BodyTempoField lock button, so the two controls never disagree).
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage(StudioDefaultKeys.lockedBPM.key) private var lockedBPM: Double = StudioDefaultKeys.lockedBPM.value
    // Read ONLY in the mode binding's set closure (to seed the locked tempo) — never
    // in `body`, so the ~10 Hz `transport.tempo` churn never subscribes this Picker host.
    @Environment(Transport.self) private var transport

    private static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    var body: some View {
        @Bindable var session = session
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                labeled("Genre") {
                    Picker("Genre", selection: edited($style, posts: "genre")) {
                        // Curated palette (founder 2026-07-24 "Genre is better you
                        // decide and curate something that really fits the brand …
                        // Die 6 ruhigen Genres"): the picker offers only
                        // `MusicStyle.offered`, still grouped by sound-world. The full
                        // taxonomy stays intact (`cat.genres`) — only what's OFFERED is
                        // curated. Categories with no offered genre are skipped so no
                        // empty section header shows.
                        ForEach(MusicStyle.Category.allCases) { cat in
                            if !cat.offeredGenres.isEmpty {
                                Section(cat.title) {
                                    ForEach(cat.offeredGenres) { s in Text(s.displayName).tag(s) }
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Genre")
                }
                labeled("Key") {
                    Picker("Key", selection: edited($rootIndex, posts: "key")) {
                        ForEach(0..<12, id: \.self) { i in Text(Self.noteNames[i]).tag(i) }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Key root")
                }
                labeled("Scale") {
                    Picker("Scale", selection: edited($scale, posts: "scale")) {
                        ForEach(Scale.allCases, id: \.self) { sc in Text(sc.displayName).tag(sc) }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Scale")
                }
                labeled("Tone system") {
                    Picker("Tone system", selection: edited($tuningID, posts: "tuning")) {
                        ForEach(TuningSystem.library) { t in Text(t.name).tag(t.id) }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Tone system")
                }
                labeled("A4") {
                    // Concert pitch — number-pad entry, exact to 0.01 Hz (380–500),
                    // standard 440.00. Commit posts "a4"; the studio pushes the new
                    // tuning to every voice + the roll and recomposes (the exact
                    // side effects the Composition panel's kammertonRow ran).
                    EchoelValueField(label: "", value: $session.a4Hz, range: 380...500,
                                     unit: "Hz",
                                     onCommit: {
                                         NotificationCenter.default.post(
                                             name: .echoelCompositionEdited, object: "a4")
                                     },
                                     boxWidth: 104, boxHeight: 30)
                        .accessibilityLabel("Concert pitch A4")
                }
                labeled("Mode") {
                    // M1 Flow/Loop (founder: "flow mode for just meditation. But also
                    // loop mode with proper timing for production"). The two modes are
                    // ONE truth — the tempo lock — surfaced as a named choice.
                    Picker("Mode", selection: modeBinding) {
                        Text("Flow").tag(false)   // tempo follows the body — meditation
                        Text("Loop").tag(true)    // fixed BPM — production / DAW handoff
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Composition mode: Flow follows your body, Loop locks a fixed tempo")
                }
                // Step 2c (bottom-bar dissolve): the live stamped session name —
                // the head of the old Session card — rides at the end of the
                // strip, always visible in the chrome. ITS OWN leaf (it reads
                // `transport.tempo`, which runs along with the body while the
                // tempo is unlocked) so only its labels churn — see RENDER
                // SAFETY above. The place/weather toggles that FEED the name
                // open via the transport "•••" door ("session").
                Divider().frame(height: 24).overlay(EchoelTheme.border)
                SessionNamePreviewLeaf()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(height: 40)
        .background(EchoelTheme.bg)
    }

    /// Caption + control, inline (chrome row — the panel's label-above form layout
    /// would double the strip's height).
    private func labeled<Content: View>(_ caption: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(caption)
                .font(EchoelTheme.font(11, .medium))
                .foregroundStyle(EchoelTheme.dim)
            content()
        }
    }

    /// Wraps a shared-storage binding so a USER edit posts its field name (the
    /// studio hears it and applies retune/recompose). Programmatic writes elsewhere
    /// set the storage directly and never come through here — they post nothing.
    /// Equality-guarded (ui-state review MEDIUM): a `.menu` Picker fires `set`
    /// even when the user re-picks the CURRENT value — the old `.onChange(of:)`
    /// semantics only fired on a real change, so a no-op tap must neither write
    /// nor post (else re-picking the current genre reset presetIndex/currentPatch
    /// and audibly recomposed the running take).
    private func edited<T: Equatable>(_ base: Binding<T>, posts field: String) -> Binding<T> {
        Binding(get: { base.wrappedValue },
                set: { newValue in
                    guard newValue != base.wrappedValue else { return }
                    base.wrappedValue = newValue
                    NotificationCenter.default.post(name: .echoelCompositionEdited,
                                                    object: field)
                })
    }

    /// The Flow | Loop mode = ONE truth, the tempo lock (M1). Flow = tempo follows
    /// the body (meditation); Loop = a fixed BPM for production. Bound to the SAME
    /// `studio.lockBPM` as the transport-bar lock button, so the two never disagree.
    /// Switching to Loop seeds `lockedBPM` from the current transport tempo (exactly
    /// like the lock button) so production starts at a sensible fixed BPM; it then
    /// posts the shared `"tempoLock"` hook, so the studio recomposes and `generate()`
    /// applies the tempo (glideTempo; the click follows the clock) and the derived
    /// `ComposerMode` (S1).
    /// `transport.tempo` is read HERE, in the set closure — never in `body` — so the
    /// ~10 Hz tempo churn never tears down this Picker host (freeze rule).
    private var modeBinding: Binding<Bool> {
        Binding(get: { lockBPM },
                set: { newLocked in
                    guard newLocked != lockBPM else { return }
                    if newLocked {
                        let v = min(max(transport.tempo, Transport.minTempo), Transport.maxTempo)
                        lockedBPM = (v * 10_000).rounded() / 10_000
                    }
                    lockBPM = newLocked
                    NotificationCenter.default.post(name: .echoelCompositionEdited, object: "tempoLock")
                })
    }
}

/// R1: the live stamped session name (artist · date · [place] · key · BPM ·
/// Kammerton) — its OWN leaf because the tempo runs along with the body
/// (freeze rule: only this label churns, never the strip's Picker host).
/// Moved verbatim from EchoelStudioView's Session card (bottom-bar dissolve
/// step 2c) — it now rides at the end of the CompositionHeaderStrip.
@MainActor
private struct SessionNamePreviewLeaf: View {
    @Environment(SessionContext.self) private var session
    @Environment(Transport.self) private var transport

    /// The name as READABLE fields in the founder's order (E · date · place ·
    /// key · BPM · Kammerton) instead of the raw underscore filename. Place is
    /// shown only once it resolves, so the line never carries an empty slot.
    private var readableFields: [String] {
        var f: [String] = []
        let artist = session.artistName.trimmingCharacters(in: .whitespaces)
        f.append(artist.isEmpty ? "E~" : artist)                           // E~ (brand mark)
        f.append(Date().formatted(date: .abbreviated, time: .omitted))     // date
        if !session.placeToken.isEmpty { f.append(session.placeToken) }    // place
        f.append(session.key.name)                                         // Tonart, spelled out
        f.append("\(Int(transport.tempo.rounded())) BPM")                  // tempo
        f.append("\(Int(session.a4Hz.rounded())) Hz")                      // Kammerton
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Human-readable identity — the value of the whole card, made legible.
            // monospacedDigit (ui-state review LOW): while the tempo is unlocked
            // the body-following BPM ticks — proportional digits made the row
            // width jitter next to the strip's Pickers (layout wobble, not a
            // freeze — but visible). Fixed-width digits keep the row still.
            Text(readableFields.joined(separator: "  ·  "))
                .font(EchoelTheme.font(13, .medium).monospacedDigit())
                .foregroundStyle(EchoelTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            // The exact export/save filename, kept for reference but de-emphasised.
            Text("Datei: \(session.sessionName(bpm: transport.tempo.rounded()))")
                .font(EchoelTheme.font(10).monospacedDigit())
                .foregroundStyle(EchoelTheme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session: \(readableFields.joined(separator: ", "))")
    }
}
#endif
