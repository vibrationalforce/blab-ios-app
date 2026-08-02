#if canImport(SwiftUI)
import SwiftUI

/// Chrome → instrument channels. Decoupled — the chrome never reaches into the studio view.
///
/// ⛔ `echoelToggleBio` USED TO LIVE HERE and is deleted with #234 (founder 2026-07-29:
/// "Ich hab jetzt hier 3 Knöpfe zum Start … könnte man das zu einem zusammenfassen?").
/// It was the wire by which two pieces of CHROME — the transport ▶ and the header pulse
/// pill — started the session that the front plate's "Create from Within" also starts.
/// Consolidating to one start button left it with zero posters, and a notification nobody
/// sends, plus a live `.onReceive` for it, is a wire that reads as an available hook while
/// being unreachable. If a future chrome control needs to start the session, re-add it
/// together with that control, never ahead of it.
extension Notification.Name {
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
    ///
    /// ⚠️ ONE POSTER IS NOT IN THE CHROME, and this doc is widened rather than
    /// quietly broken (#356): `EchoelStudioView.tapTempoRow` posts "tempoLock"
    /// too. Tap tempo is a user edit of a musical setting like any other, and it
    /// writes the same shared `lockBPM`/`lockedBPM` keys — so it owes the same
    /// side effects. It happens to live in the studio, which makes its post a
    /// round trip to its own `.onReceive`. The alternative was calling
    /// `recomposeIfRunning()` directly; that was rejected because the "tempoLock"
    /// case is then free to grow a second effect (re-arming the click, say) and
    /// the three doors would silently diverge. The invariant that matters is
    /// USER EDIT → this hook, not WHICH VIEW posts it; the "chrome never reaches
    /// into studio state" sentence above is about the DIRECTION of the coupling
    /// and still holds.
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
                // Dynamic Type (a11y). The three chrome bars used to be FIXED-height
                // (topBar 50 / TransportBar 44 / CompositionHeaderStrip 40 pt) and were
                // therefore clamped to `.xxLarge` so their text could not overrun the box
                // it sits in. That clamp is the single largest accessibility defect in the
                // app: it covers Play/Stop, tempo, Genre, Key, Scale, Tone system and A4 —
                // the always-visible controls.
                //
                // ⛔ AN EARLIER VERSION OF THIS COMMENT ALSO BLAMED THE CLAMP FOR CAPPING
                // THE APP'S OWN PINCH ZOOM. That was FALSE and worth correcting rather than
                // deleting: `StudioZoom` is applied INSIDE `EchoelStudioView`
                // (`EchoelStudioView.swift`), which mounts under `SurfaceHost` — a SIBLING
                // of this Group, not a descendant. `.dynamicTypeSize` only writes downward,
                // so the two never met. The pinch zoom has never reached the chrome and
                // still does not; this change did not alter that either way.
                //
                // The heights below are now MINIMUMS, not fixed sizes, so the bars grow
                // with the text instead of overflowing — which removes the reason the clamp
                // existed. `EchoelValueField.boxHeight` became a minimum in the same commit,
                // and its compact `boxWidth` became Dynamic-Type-scaled in the follow-up:
                // without the WIDTH half, raising the ceiling made the A4 field truncate at
                // AX1 (the unit label does not shrink, the number does, and it hits its 0.5
                // floor) — a new defect introduced by the fix, not an old one left alone.
                //
                // ⚠️ THE CEILING IS RAISED, NOT REMOVED, AND THE REASON IS HONEST: the
                // chrome is 134 pt today (50 + 44 + 40). At `.accessibility5` a naive 3.12×
                // gives 418 pt and a bottom-up estimate lands nearer 270 pt, because much of
                // each bar is fixed-size children that never scale — three defensible
                // numbers, which means the only honest statement is "somewhere between
                // roughly 270 and 420 pt, unmeasured". This environment has no simulator.
                // `.accessibility1` (~1.65× vs the old ~1.24×) is the largest step
                // verifiable by reasoning alone. Raising it further is a founder device
                // look, and it needs the fixed heights INSIDE the bars converted first
                // (`BodyTempoField` 76×32; ⛔ `HeaderMonitors.PulseMonitorMini` stood here too
                // and has not been chrome since #289 moved it into the instrument's
                // `startControlRow` — it is no longer part of this ceiling's arithmetic) — those
                // hold at AX1 and overflow from AX2 up, so "the layout is ready" is true
                // only for the step actually taken. Do NOT read this as "accessibility is
                // done": a user on AX4/AX5 still gets AX1 in the chrome.
                //
                // The instrument below (SurfaceHost) is deliberately NOT clamped at all.
                // Group is layout-transparent in a VStack (no spacing/structure change),
                // adds no sheet, reads nothing.
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
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
            //
            // ⭐ #311 — THE WINDOW IS NEVER UNMOUNTED, AND THAT IS A CORRECTNESS RULE, NOT A
            // LAYOUT PREFERENCE. Founder 2026-07-31: *"die arps soll immer hörbar sein und
            // nicht nur, wenn das Visual Fenster auf ist."* The Field's self-play generator
            // (the arp) is driven by a `CADisplayLink` that lives inside
            // `TouchInstrumentUIView`, and that view is an OVERLAY on this window's picture
            // card. `startAutoPlay` requires `window != nil` and `didMoveToWindow` stops the
            // link when the view leaves the hierarchy — so an `if floatingVisualVisible { … }`
            // here took the AUDIO with the PICTURE. A view was driving the instrument.
            //
            // The same trap was already reasoned about once, for the external-screen case
            // (#206, `FloatingVisualWindow.visualLayer`'s own doc): *"hiding the window takes
            // the phone's PLAY SURFACE with it"*. The fix there was swap-the-layer,
            // keep-the-window; this is the same fix for the other trigger, so the two now
            // agree instead of contradicting each other.
            //
            // Hidden means INERT, not merely transparent: no hit target (`allowsHitTesting`),
            // no VoiceOver element (`accessibilityHidden`), and — the expensive half — no
            // renderer, because `visualLayer` drops `MetalBioView` entirely while
            // `isPresented` is false. Keeping a 60 fps Metal layer alive behind an
            // `.opacity(0)` would trade the founder's bug for a battery one.
            #if canImport(MetalKit) && canImport(UIKit)
            FloatingVisualWindow(isPresented: $floatingVisualVisible)
                .opacity(floatingVisualVisible ? 1 : 0)
                .allowsHitTesting(floatingVisualVisible)
                .accessibilityHidden(!floatingVisualVisible)
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

    /// Persistent brand header — always on screen. LEFT: the brand block (mark + wordmark +
    /// running version/build) as ONE control. RIGHT: the output monitors. Uncodixfy-compliant.
    ///
    /// ⭐ WHY THE TITLE IS NO LONGER CENTRED — founder, 2026-08-01, with the empty space left of
    /// the title circled in red: *"Was kann hier jetzt noch hin?"* The honest answer is
    /// **nothing**, and that is a decision, not a shrug: the UI rules ban decorative tiles and
    /// "control-room cosplay", every status a performer needs already has a home (transport and
    /// tempo in `TransportBar`, key/scale/tone system/A4 in `CompositionHeaderStrip`, the three
    /// output monitors on the right), and the live pulse pill was deliberately moved OUT of this
    /// bar four days earlier on the founder's own ask (#289). Inventing a fourth chrome tile to
    /// fill a gap would undo that reasoning to solve an aesthetic problem.
    ///
    /// The gap is a LAYOUT defect, so the layout is what changed: the wordmark moves left into
    /// the space instead of a new element moving in beside it. The mark and the title were two
    /// separate buttons for the same action, on two different layers of a `ZStack` — which also
    /// made the second one `accessibilityHidden` to stop VoiceOver announcing the same door
    /// twice. One leading button is simply what that was always describing.
    ///
    /// ⚠️ AND IT FIXES A REAL DYNAMIC-TYPE DEFECT, not only the look. A `ZStack` gives its
    /// layers NO collision avoidance: the centred title sat on its own layer above the row that
    /// holds the mark and the monitors, so as the text grew it grew straight THROUGH them.
    /// `minimumScaleFactor(0.7)` only bounds how far. In an `HStack` the `Spacer` is what yields,
    /// so the title and the tiles can no longer overlap at any text size — which matters because
    /// the chrome is capped at `.accessibility1`, not at `.xxLarge`, since #262.
    private var topBar: some View {
        HStack(spacing: 8) {
            Button { openWebsite() } label: {
                HStack(spacing: 8) {
                    EchoelLogoMark().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
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
            }
            .buttonStyle(.plain)
            // ONE element, one announcement, one action. A `Button` is already a single
            // accessibility element, so putting the mark INSIDE its label is what removes the
            // second VoiceOver stop — the old `.accessibilityHidden(true)` on the separate mark
            // button was buying the same thing by hand. Deliberately no
            // `.accessibilityElement(children: .ignore)` here: on a Button that is at best
            // redundant and at worst rebuilds the element without its activation.
            .accessibilityLabel("Echoelmusic \(Self.versionString)")
            .accessibilityHint("Opens echoelmusic.com — release notes and support")
            // ⬆ THE LIVE PULSE MONITOR MOVED OUT (#289, founder 2026-07-31, red circle
            // around this pill and the transport ■: "könnte ja alles in dem Create From
            // within Button drin sein … Führe intelligent zusammen"). It now sits
            // immediately left of "Create from Within" in `EchoelStudioView`, so the
            // feedback appears ON the control that produces it instead of at the other
            // end of the window.
            //
            // ⛔ This supersedes the founder's 2026-07-12 placement ("Der Pulsmonitor
            // kommt nach oben zwischen Logo und Echoelmusic"), whose note in
            // `HeaderMonitors` says not to unmount it again without a fresh founder ask.
            // This IS that ask, from the same person, with a drawing. The pill itself is
            // unchanged — same leaf, same tap (Bio panel), same long-press (source
            // picker) — only its address changed. The space it left is the one the founder
            // circled on 2026-08-01; see this property's own doc for why it is closed by
            // moving the wordmark rather than by filling it.
            Spacer(minLength: 8)
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
        .padding(.horizontal, 12)
        // `fixedSize` BEFORE `minHeight`, and the order is load-bearing — see the shared
        // note above `TransportBar`'s frame for why the pair is not optional.
        .fixedSize(horizontal: false, vertical: true)
        // minHeight, not height: the bar keeps its 50 pt design size at every normal text
        // size and GROWS instead of overflowing at accessibility sizes (see the Dynamic
        // Type note on the chrome Group in `body`).
        .frame(minHeight: 50)
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
/// #289 — the playback ■/▶, EXTRACTED from `TransportBar` so it can sit in the studio's
/// one control block beside "Create from Within" (founder 2026-07-31: the pulse pill and
/// this button "könnte ja alles in dem Create From within Button drin sein … Führe
/// intelligent zusammen").
///
/// ⭐ A LEAF, and that is the whole reason it is a separate `struct` rather than a few lines
/// inlined into `EchoelStudioView.startControlRow`. It reads `bus.instrumentRunning` and
/// `transport.isPlaying` in its OWN body. Inlined, those two reads would sit in
/// `EchoelStudioView.body` — the body that hosts every `.menu` Picker in the instrument —
/// and the freeze law (10.76.41/50) is about exactly that. Both are low-frequency today
/// (they flip on start and on stop), so inlining would probably not freeze anything; "probably
/// not" is not the standard this file is held to, and `Transport` also owns the ~10 Hz
/// `position`, which is one careless `transport.position` away from being read here.
///
/// Behaviour is UNCHANGED from the transport bar — same gate, same pause intent, same
/// breadcrumb. This is a relocation, not a redesign; the rationale below is #179's and is
/// carried across whole because it is the reason this button is not merged INTO the hero
/// button's tap target.
@MainActor
struct PlaybackToggleButton: View {
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player
    /// Read ONLY inside `toggle()` — a tap handler, never `body` — so this leaf subscribes
    /// to nothing extra. It carries the PAUSE INTENT: `PianoRollModel` owns the one-shot
    /// flag the studio's transport observer consumes.
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(EngineBus.self) private var bus

    var body: some View {
        // ⛔ THE MUSIC TRANSPORT, AND ONLY WHILE A SESSION RUNS (founder 2026-07-29,
        // screenshot: "Ich hab jetzt hier 3 Knöpfe zum Start … könnte man das zu einem
        // zusammenfassen?"). Three controls began the same session: this ▶, the header
        // pulse pill, and the full-width "Create from Within". The last one — labelled,
        // unmissable, named after what the instrument does — is now the only way to START.
        //
        // Why this button SURVIVES instead of being folded into that one: it does a job the
        // hero button cannot. "Stop" ends the whole session, and the camera pulse then needs
        // ~20 s to re-acquire a lock. A performer who wants silence between two sections must
        // be able to drop the music WITHOUT dropping the body — that is this ■, and it only
        // makes sense while there is a session to drop out of. Hidden the rest of the time,
        // so at the "how do I start?" moment exactly one button on screen starts anything.
        //
        // ⛔ THAT WAS NOT TRUE WHEN IT WAS FIRST WRITTEN, and the founder's own device log
        // proved it within the hour (2475, second session):
        //
        //     828.182  stop source: transport-bar ■
        //     828.196  stopEverything(transport-stopped): transport + all voices released
        //
        // `TransportTransition.decide` returns `.endSession` unless a playback-only stop was
        // REQUESTED, and the only producer of that request was `PianoRollView`, whose door was
        // removed on 2026-07-26. So this ■ ended the whole session — a second full Stop
        // wearing a different glyph, i.e. exactly the duplicate the slice claimed to have
        // removed. The rationale above is now honoured instead of repaired away: `toggle()`
        // raises the pause intent, so the sentence describes what the button does. This is
        // #179 decided as RESCUE rather than RETIRE — every piece (the flag, the pure
        // decision, `pausePlaybackKeepingSession`, `resumeAfterPause`) was already built and
        // tested and only lacked a caller.
        //
        // `instrumentRunning` is the start/stop chrome mirror — it changes twice per session,
        // not per frame, so reading it here is freeze-safe. (Reading `pianoRoll.notes` instead
        // would have been the exact 10 Hz read the freeze law forbids — the roll changes on
        // every generate.)
        //
        // ⛔ THE GLYPH WAS `stop.fill` UNTIL #305, AND IT LIED — in the one row where lying
        // is most expensive. Founder 2026-07-31, red circle around that row: *"Einfaches
        // start stop Recording Taster und etwas größere Anzeige für Analyse ist besser."*
        // That is the FOURTH complaint about this cluster (2026-07-15 "zu viele Play Knöpfe",
        // 2026-07-29 "3 Knöpfe zum Start", 2026-07-31 "Führe intelligent zusammen"), and the
        // screenshot shows why it kept coming back: `startControlRow` presented a wide button
        // reading "Stop" and, 8 pt to its right, a second ■. Two identical claims, two
        // different effects — one ends the session (camera included, ~20 s to re-lock), the
        // other only pauses the music. Nothing on screen distinguished them.
        //
        // `pause.fill` is the whole fix and it is not cosmetic: the paragraph above justifies
        // this button's existence entirely on "drop the music WITHOUT dropping the body", and
        // `toggle()` below does exactly that (`requestPlaybackOnlyStop()`). The glyph now
        // states the behaviour the code already had. Exactly ONE control in that row means
        // stop, and it is the labelled one. `OneStartControlTests` pins both halves.
        if bus.instrumentRunning {
            Button { toggle() } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.text)
                    // 44×48, was 38×32 until #307's Nachlese. TWO reasons, and the second is
                    // the one that matters. (1) The commit that built this row called it an
                    // "Ableton transport", and Ableton's transport strip is UNIFORM-height —
                    // ours was 56 / 32 / 48 centred, so this chip floated 12 pt inside the row
                    // on both edges and read as a stray control rather than part of the block.
                    // A reviewer called the claim out and was right. (2) 44×48 clears the HIG
                    // touch floor on its OWN geometry, so the hit area no longer has to be
                    // faked by outsetting the shape into the 8 pt gaps between neighbours.
                    .frame(width: 44, height: 48)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        // #367: idle used `border`, the DECORATIVE token whose own doc says
                        // "Do not use it on anything tappable" (1.16:1). This button renders in
                        // `EchoelStudioView.startControlRow` — see the #289 note further down
                        // THIS file — so its actual on-screen neighbours are `startButton` and
                        // `PulseMonitorMiniLive`, and both were already on `borderStrong`. One
                        // row, three controls, the biggest of them outlined like a divider.
                        //
                        // ⛔ THE FIRST VERSION OF THIS COMMENT CALLED THE "•••" ITS "30x32
                        // NEIGHBOUR … 140 lines down". The 140 lines are right and the
                        // neighbourhood is invented: the "•••" lives in `TransportBar`, two rows
                        // and a divider above the studio, and the note at the top of that struct
                        // says so in as many words. I derived adjacency from FILE ORDER — the
                        // exact mistake CLAUDE.md had just been amended about, in the same
                        // session, over a grid attributed to the wrong panel for the same reason.
                        // It also called this "the lowest-contrast control in the app", which was
                        // a ~46-way tie: `border` is ONE opacity. What was true, and is the whole
                        // argument, is that it was the LARGEST control still at 1.16:1.
                        .strokeBorder(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // ⛔ The outset is GONE (`inset(by: -6)`), and deliberately, not by oversight: it
            // existed only to lift a 38×32 chip to the 44 pt HIG floor by borrowing 6 pt from
            // each side — which meant this button's hit area reached into the gaps beside its
            // neighbours. The chip is 44×48 now, so the floor is met by the control itself.
            // A plain `contentShape` keeps the whole frame hit-testable (the background fill
            // already covers it; this makes it explicit rather than implied).
            .contentShape(Rectangle())
            // `Text` on both ternary branches, as a forward guard — NOT a bug fix. Be
            // precise, because the sibling comment in `OnboardingView` was written as if it
            // were one: the non-generic `LocalizedStringKey` overload is preferred over the
            // generic `StringProtocol` one, so two bare literals almost certainly localised
            // already. Neither string is a catalog key today either, so nothing a user sees
            // changes. What `Text` buys is that the question stops depending on overload
            // ranking — worth one word on the only description a VoiceOver user gets of a
            // control whose whole point is that it does NOT end the session.
            // "Pause", not "Stop" — the same #305 correction as the glyph. A VoiceOver user
            // got the WORSE version of this confusion: two controls both announced as "Stop",
            // with no picture to tell them apart and no way to discover that one of them keeps
            // the pulse lock. The hint carried the real difference all along; now the label
            // does too, so the distinction survives being read out one control at a time.
            .accessibilityLabel(transport.isPlaying ? Text("Pause the music") : Text("Play the music"))
            .accessibilityHint(Text("Leaves the session and your pulse reading running."))
        }
    }

    private func toggle() {
        if transport.isPlaying {
            // T1 breadcrumb: name the finger BEFORE the stop cascades — the 2361 log's
            // source-less "transport-stopped" burned a triage cycle proving it was a tap.
            // PAUSE, not end-of-session. The flag is a one-shot consumed by the studio's
            // transport observer in the SAME turn as the `isPlaying` flip below, and every
            // other stop path clears it defensively (`stopEverything`), so it cannot latch
            // and downgrade a later real Stop — the #161 trap. Raising it BEFORE
            // `pattern.stop()` is required, not stylistic: the observer reads it as a
            // consequence of that call.
            //
            // It also cannot be raised while no take is live, which is the other half of that
            // trap: this button does not exist unless `bus.instrumentRunning` is true.
            //
            // ⛔ The breadcrumb still says "transport-bar ■" although the button now lives in
            // the studio's control row (#289). Kept VERBATIM on purpose: it is the string the
            // founder's device logs are read against, and renaming it would silently break
            // every existing triage note that greps for it. The location changed; the identity
            // of the finger did not.
            EchoelCrashLog.breadcrumb("stop source: transport-bar ■ (playback only)")
            pianoRoll.requestPlaybackOnlyStop()
            player.pattern.stop()
        } else {
            // ▶ PLAYS THE INSTRUMENT. It does not consult the timeline document at all
            // (founder 2026-07-27: "Der ganze DAW Quatsch der nicht funktioniert hat soll
            // erstmal raus aus dem TestFlight"). The arrangement branch, the drum-grid
            // condition and the UX-2 first-run branch that used to stand here are gone with
            // #130/#166/#234 respectively; `TimelineRegionPlayer` is permanently inert
            // (`transportStep` opens with `guard isPlaying`, and `play(document:)` — its only
            // writer — has no production caller). #132 Slice 5 retires the model.
            player.pattern.play(cause: .transportButton)
        }
    }
}

@MainActor
private struct TransportBar: View {
    var body: some View {
        HStack(spacing: 12) {
            // ⬆ THE PLAYBACK ■/▶ MOVED OUT (#289, founder 2026-07-31: the pulse pill and
            // this button "könnte ja alles in dem Create From within Button drin sein …
            // Führe intelligent zusammen"). It now sits in `EchoelStudioView`'s one control
            // row, beside "Create from Within", as `PlaybackToggleButton` — the leaf defined
            // above this struct, which carries its full #179 rationale. Nothing about WHAT it
            // does changed; it stopped being on the far side of the window from the control
            // it belongs to.

            // (The transport pulse button is GONE — founder 2026-07-15 video: "zu viele
            //  Play Knöpfe, einer reicht." Its job moved to the header pulse pill, and
            //  with #234 it moved on again: the pill is a MONITOR whose tap opens the Bio
            //  panel, and starting the session is the front plate's "Create from Within"
            //  alone. Same founder complaint, answered twice — the second time by removing
            //  the duplicate rather than relocating it.)

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
            // ⛔ FOUR OF THE SIX ENTRIES LEFT THIS MENU (#290, founder 2026-07-31, red circle
            // around the open overflow: "Lässt sich das alles intelligent unterbringen in der
            // Reihe mit den ganzen Funktionen?"). Master, Save/Export, Tempo and Weather &
            // place became CHIPS — they always were full `StudioMenu` cases with working
            // panels, merely filtered out of the strip, so moving them cost no new surface and
            // no new modal. Their `.echoelChromeDoor` cases in `EchoelStudioView` went with
            // them; a case whose only poster was deleted is dead code that reads like a hook.
            //
            // ⛔ WHY THESE TWO STAYED, because the honest answer is not "they did not fit":
            // Live Colabo and Learn are the only two that are NOT panels. They present full
            // sheets (`showLiveColabo`, `showLearn`). The chip strip's grammar is "this chip
            // selects what the plate shows" — a chip that opens a modal instead would be a
            // lying tab, and it would add two entries to the presentation chain the
            // black-screen law tells us not to grow. Two entries in an overflow is a small
            // price for a strip where every chip means the same thing.
            //
            // ⛔ AND THE "Weather & place" CHIP IS GONE AGAIN (#359, 2026-08-01) — the whole
            // `.session` case with it. This paragraph is left in the past tense rather than
            // rewritten, because it is an argument about what #290 did, and #290 really did
            // promote four entries. Where those four are TODAY: Master, Save/Export and Tempo
            // are still chips; the weather half of the fourth moved into Mood (sound
            // influences) and Field (image influences), and the place half into "Save &
            // Export", one line above the Save button whose file name it shapes.
            //
            // The #272 lesson is carried into the Save/Export CHIP label rather than lost: the
            // founder reported "Session speichern und Loops aufnehmen fehlt" about controls
            // that were behind an entry named only "Export". And the #202/#59 lesson — name
            // what weather DOES (it salts the harmonic skeleton and blends darkness/
            // liveliness/tension into the composer's mood) instead of calling it a naming
            // gimmick — now lives in `StudioMenu.mood.fullName`, which is the door that
            // actually holds those knobs. It was in `.session.fullName` until #359 step 3
            // deleted that case; this line was the only pointer to it in the repo, so it is
            // corrected rather than dropped.
            Menu {
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
            .accessibilityLabel("More — Live Colabo; Learn and news")

            Spacer(minLength: 0)

            TransportPositionView()
        }
        .padding(.horizontal, 12)
        // ⚠️ `fixedSize` + `minHeight` ARE A PAIR. `minHeight` alone would have been a
        // regression for EVERY user, not only accessibility users, and the mechanism is
        // worth stating once here for all three bars:
        //
        // `.frame(height: h)` reports `h` whatever the child does. `.frame(minHeight: h)`
        // forwards the incoming proposal downward and reports `max(child, h)` — so it only
        // preserves the old geometry if the subtree is vertically INFLEXIBLE. This subtree is
        // not: `EchoelValueField`'s scrub layer is a bare `Rectangle()`, which accepts any
        // proposed height (see the note at that Rectangle). In Loop mode the tempo control IS
        // an `EchoelValueField`, so this bar would have started reporting ∞ — and its sibling
        // `SurfaceHost` is `maxHeight: .infinity` too, so a VStack ranking both as infinitely
        // flexible SPLITS the free space between them. The transport bar would have taken
        // roughly half the screen at the DEFAULT text size.
        //
        // `.fixedSize(horizontal: false, vertical: true)` proposes nil downward, so the
        // Rectangle falls back to its ideal and the bar takes its true content height; the
        // `minHeight` then floors it at the design size. Flexibility is back to zero, which
        // is what the old fixed height gave us — this time without capping the text.
        // Removing either half re-opens the split. 44 pt is also the HIG tap-target floor.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
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

    // ⛔ `toggle()` IS GONE FROM HERE, not merely unused: it moved with the ■ into
    // `PlaybackToggleButton` (#289). A private method with no caller compiles silently in
    // Swift — no warning, no gate — so leaving it would have been a second, divergent copy
    // of the playback-stop path waiting for someone to "restore" a button onto it. The four
    // `@Environment` values it needed went with it for the same reason.
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
                    .font(EchoelTheme.font(14).monospacedDigit())
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

    /// How the Key picker spells its twelve names (#232 E). A LOW-frequency read (a user
    /// setting), safe in this Picker-hosting body under the freeze law.
    ///
    /// This replaced a hard-coded English array. It was not a translation gap: in German,
    /// Austrian and Scandinavian notation the natural above A♯ is **H**, and **B** means B♭ —
    /// so this picker was offering a German reader the wrong note, on the control that
    /// decides the key of everything the app generates.
    @AppStorage(StudioDefaultKeys.noteNaming.key) private var noteNamingRaw = StudioDefaultKeys.noteNaming.value
    private var noteNaming: NoteNaming { NoteNaming(stored: noteNamingRaw) }

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
                        ForEach(0..<12, id: \.self) { i in
                            Text(noteNaming.name(pitchClass: i)).tag(i)
                        }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Key root")
                }
                labeled("Scale") {
                    Picker("Scale", selection: edited($scale, posts: "scale")) {
                        // Grouped, mirroring the Genre picker two controls to the left —
                        // this row was the one place this strip was inconsistent with
                        // itself, and at 57 entries a flat list is a wall. The headers also
                        // do the #232 job the display names cannot: they name the tradition
                        // (maqām, thāt/rāga) WITHOUT putting a duplicate pitch set in the
                        // list. See `Scale.Family` for why the attributions are marked
                        // 12-TET and where the real microtonal tunings live.
                        //
                        // No `if !family.scales.isEmpty` guard, unlike the Genre picker:
                        // there every category can be emptied by curation, here every
                        // family is a hand-written non-empty literal and the blocking
                        // `ScaleFamilyTests` proves the partition is total. A guard would
                        // silently hide a scale instead of failing.
                        ForEach(Scale.Family.allCases) { family in
                            Section(family.title) {
                                ForEach(family.scales, id: \.self) { sc in
                                    Text(sc.displayName).tag(sc)
                                }
                            }
                        }
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
                // Directly after "Tone system" on purpose: that row picks WHICH pitches
                // exist, this one picks what they are CALLED. Together they are the whole
                // "what musical culture am I reading in" question, and a player who needs
                // one usually needs the other. A `Picker` and not an `EchoelValueField` —
                // the values have names, which is the stated exception to the one-control
                // law, not a violation of it.
                labeled("Note names") {
                    Picker("Note names", selection: $noteNamingRaw) {
                        ForEach(NoteNaming.allCases, id: \.rawValue) { n in
                            Text(n.displayName).tag(n.rawValue)
                        }
                    }
                    .pickerStyle(.menu).tint(EchoelTheme.text)
                    .accessibilityLabel("Note name system")
                    // The hint enumerates the options because a menu Picker speaks only the
                    // CURRENT value until it is opened. It listed three while four shipped
                    // for one commit — on the one control this whole epic exists to make
                    // accessible, which is the worst possible place to undercount. Adding a
                    // case to `NoteNaming` means editing this string too; there is no
                    // compiler link between them.
                    .accessibilityHint("Chooses how the twelve notes are spelled — "
                                       + "international A B C, German A H C, solfège Do Re Mi, "
                                       + "or Indian sargam Sa Re Ga")
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
        // Same `fixedSize` + `minHeight` pair as `TransportBar` — read that note first.
        //
        // This one sits on a HORIZONTAL ScrollView, and the correction to my first comment
        // here is worth keeping: a ScrollView's cross axis does NOT clamp to some intrinsic
        // size, it takes the CONTENT's size under the proposal it passes through. So with a
        // vertically greedy content (the A4 `EchoelValueField`) the ScrollView is greedy too
        // and the strip would have grown to FILL, not "grown rather than cropped". The
        // `fixedSize` is what actually bounds it; the ScrollView semantics were never the
        // thing keeping this honest.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 40)
        .background(EchoelTheme.bg)
    }

    /// Caption + control, inline (chrome row — the panel's label-above form layout
    /// would double the strip's height).
    private func labeled<Content: View>(_ caption: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(caption)
                .font(EchoelTheme.font(11))
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
    /// This leaf sits at the END of the same strip as the Key picker, so it has to spell the
    /// key the same way (#232 E) — otherwise the picker offers H and the line two controls to
    /// the right reads "B Minor". A user setting, so a low-frequency read.
    @AppStorage(StudioDefaultKeys.noteNaming.key) private var noteNamingRaw = StudioDefaultKeys.noteNaming.value

    /// The name as READABLE fields in the founder's order (E · date · place ·
    /// key · BPM · Kammerton) instead of the raw underscore filename. Place is
    /// shown only once it resolves, so the line never carries an empty slot.
    ///
    /// READABLE is the operative word: this is a preview, not the stamped name. The name that
    /// actually reaches a file goes through `key.shortName` in `SessionContext` and stays
    /// English on every device — see the note on `MusicalKey.name(naming:)`.
    private var readableFields: [String] {
        var f: [String] = []
        let artist = session.artistName.trimmingCharacters(in: .whitespaces)
        f.append(artist.isEmpty ? "E~" : artist)                           // E~ (brand mark)
        f.append(Date().formatted(date: .abbreviated, time: .omitted))     // date
        if !session.placeToken.isEmpty { f.append(session.placeToken) }    // place
        f.append(session.key.name(naming: NoteNaming(stored: noteNamingRaw)))  // Tonart, spelled out
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
                .font(EchoelTheme.font(13).monospacedDigit())
                .foregroundStyle(EchoelTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            // The exact export/save filename, kept for reference but de-emphasised.
            Text("File: \(session.sessionName(bpm: transport.tempo.rounded()))")
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
