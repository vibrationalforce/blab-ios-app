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
    /// `object` = the door name. (⛔ This listed "master" · "export" · "live" ·
    /// "learn" — the four the "•••" overflow posted, and NONE of them is a case
    /// any more: the first two became chips with #290, the last two became tiles
    /// with #492. The live names are "video" · "routing" · "bio", all posted from
    /// `HeaderMonitors`. An example list of dead strings is worse than none — it
    /// invites a new poster for a case that no longer exists.) The studio listens
    /// and opens its dropdown/sheet — same decoupling as the pulse button, the
    /// chrome never reaches into studio state.
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
// Shell = brand header (topBar) + CompositionHeaderStrip + SurfaceHost — which
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
                // (topBar 50 / TransportBar 44 / CompositionHeaderStrip 40 pt — the middle
                // one is dissolved since #456) and were
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
                // chrome is 94 pt today (50 + 44).
                //
                // ⛔ THIS NUMBER HAS NOW GONE STALE TWICE, THE SECOND TIME AT MY OWN HAND,
                // ONE CYCLE AFTER I QUOTED THE FIRST ONE AS A LESSON. It read "134 pt
                // (50 + 44 + 40)" until #456 dissolved the transport bar — and the commit
                // that removed the 44 edited the sentence four lines above this one without
                // touching it. It then read "90 pt (50 + 40)" until #502 slice 1, which gave
                // `CompositionHeaderStrip`'s children the 44 pt tap floor and therefore made
                // the bar render 44 — priced in that slice's own `labeled` doc as "+4 pt",
                // and left uncorrected HERE, in the same file, by the same commit. The 40
                // survives one line above `labeled` as a COLLAPSE floor and is no longer the
                // binding constraint, so quoting it as the bar's height is exactly the drift
                // the ⛔ below describes. **A band height belongs to the band, not to the
                // `minHeight` literal that used to set it** — read the tallest child. Every
                // number that used to hang off the 134 (a naive `.accessibility5` 3.12×
                // "418 pt", a bottom-up "nearer 270 pt") is therefore WITHDRAWN rather than
                // rescaled: they were an estimate of a three-bar chrome, and re-deriving
                // them for two bars is arithmetic I have not done. What survives unchanged
                // is the SHAPE of the argument — much of each bar is fixed-size children
                // that never scale, so top-down and bottom-up disagree, and this
                // environment has no simulator to settle it. `.accessibility1` (~1.65× vs
                // the old ~1.24×) remains the largest step verifiable by reasoning alone.
                // Raising it further is a founder device look, and it needs the fixed
                // heights INSIDE the bars converted first
                // (⛔ `BodyTempoField` 76×32 was named here and LEFT with #411 — like
                // `HeaderMonitors.PulseMonitorMini` before it (#289) and the "•••" overflow
                // after it (#456), it now lives in the instrument's `startControlRow`, so
                // none of the three is part of this ceiling's arithmetic any more. What is
                // still fixed-size in the chrome: `EchoelValueField`'s A4 box in
                // `CompositionHeaderStrip`, and nothing else. THREE named examples have now
                // migrated out of this list without the list noticing — the third one
                // migrated in the very commit that had to correct the count from TWO, which
                // is the argument for re-measuring rather than re-quoting it) — that box
                // holds at AX1 and overflows from AX2 up, so "the layout is ready" is true
                // only for the step actually taken. Do NOT read this as "accessibility is
                // done": a user on AX4/AX5 still gets AX1 in the chrome.
                //
                // The instrument below (SurfaceHost) is deliberately NOT clamped at all.
                // Group is layout-transparent in a VStack (no spacing/structure change),
                // adds no sheet, reads nothing.
                Group {
                    topBar
                    // (TransportBar stood here and is DISSOLVED — #456. Its two remaining
                    // children, the "•••" overflow and the position/loop readout, moved into
                    // `EchoelStudioView.startControlRow` on the founder's 2026-08-07 screenshot
                    // arrows. The chrome is two bars now, not three; see the note where the
                    // struct used to be for why they landed on a SECOND line rather than one.)
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
            // ⭐ #1025 — THE CONTROL COLUMN HAS A READABLE CEILING, AND IT IS ONE OF TWO
            // SITES (the other is `EchoelSheetPanelModifier`, which covers every sheet).
            // Founder clip, build 448/2567: *"Die adaptive View muss her. Es muss vermieden
            // werden, dass wir plötzlich verzerrte und zu große Fenster haben."* Rotating the
            // phone hands this VStack ~852 pt; nothing below is designed for it, so rows stop
            // wrapping and paragraphs run off the edge — the frames the clip shows.
            //
            // TWO `frame`s ON PURPOSE, and the order is the whole trick: the inner one caps
            // the content, the outer one re-claims the full width so the capped column is
            // CENTRED instead of hugging the leading edge. One `frame` alone gives a
            // left-aligned column with all the empty space on the right.
            //
            // ⚠️ IT BINDS ON NO iPHONE IN PORTRAIT (440 pt widest today vs a 560 pt ceiling),
            // so on the founder's device this changes exactly nothing. That is intended: it
            // is a guard against canvases the layout was never drawn for, not a redesign of
            // the one it was.
            //
            // ⚠️ INSIDE THE `ZStack`, NOT AROUND IT. `FloatingVisualWindow` is the sibling
            // below and must keep the FULL screen — "true Vollbild" is a rule stated a few
            // lines down, and capping the ZStack would shrink the one surface whose entire
            // point is to cover everything. Pinned by the guard's counterweight.
            .frame(maxWidth: EchoelTheme.readableContentWidth)
            .frame(maxWidth: .infinity)
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
            // renderer, because `visualLayer` drops `MetalBioView` while `isPresented` is
            // false. Keeping a 60 fps Metal layer alive behind an `.opacity(0)` would trade
            // the founder's bug for a battery one.
            //
            // ⚠️ EXACTLY ONE STATE BREAKS THAT, AND IT IS WRITTEN HERE BECAUSE THIS IS THE
            // MOUNT SITE — the first place a session reads when it asks what a hidden window
            // costs. While a video take is RUNNING and no external stage is connected, the
            // hidden window KEEPS its renderer (#319): `MetalBioView`'s draw loop is
            // `VisualRecorder`'s only frame source, so dropping it made the take silently
            // record nothing (`AVAssetWriter` is built from the FIRST frame; none arrived,
            // `stop()` returned nil, the REC badge counted wall-clock seconds it never
            // wrote). The condition lives in `FloatingVisualWindow`'s
            // `mustKeepRenderingForRecording`; this sentence exists so the paragraph above
            // cannot be read as "a hidden window can never be rendering" — it can, and it is
            // deliberate. Do not "restore" the unconditional claim here or the drop there.
            #if canImport(MetalKit) && canImport(UIKit)
            FloatingVisualWindow(isPresented: $floatingVisualVisible)
                .opacity(floatingVisualVisible ? 1 : 0)
                .allowsHitTesting(floatingVisualVisible)
                .accessibilityHidden(!floatingVisualVisible)
            #endif
            // #603 B1 — the founder's on/off guide, as the ZStack's TOP layer (above the
            // fullscreen visual, so the tour's first card — "the app opens as a picture" —
            // is readable on the very screen it describes). Costs ZERO presentation
            // modifiers (the whole point; the chain below is at its pinned 14). The view
            // reads one low-frequency `@AppStorage` bool in ITS OWN body — constructing
            // it here registers nothing (freeze rule 10.76.50). Toggle: Save & Export
            // panel; content: `LearnLibrary.guideEntries`, the guard-pinned one source.
            GuideOverlay()
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
            // ⭐ #580 — THE FRONT DOOR NAMES ITSELF IN THE LOG. This branch decided which
            // app a user opens, and until now a pasted device log could not tell which side
            // it took: the flag read false for three weeks (registered after the first view
            // appeared — see `EchoelmusicApp.init()`), and NOTHING said so. The same lesson
            // as #579 one layer up: a state that steers the whole session must be printable,
            // or the next founder log answers a question nobody can ask.
            //
            // Cheap and safe: fires exactly once per launch behind `didSeedInstrumentHome`,
            // reads only a flag and two `@AppStorage` values — no bio, no playhead, so the
            // freeze rule is untouched (the comment above already says so for the seed).
            if FeatureFlags.instrumentHome {
                floatingVisualVisible = true
                floatingSizeRaw = FloatingVisualWindow.WindowSize.fullscreen.rawValue
                EchoelCrashLog.breadcrumb("front door: instrument (fullscreen visual, chrome mounted beneath)")
            } else {
                EchoelCrashLog.breadcrumb(
                    "front door: chrome first (instrumentHome OFF — an explicit dev override, "
                    + "since its default registers in init())")
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

    /// Persistent brand header — always on screen. LEADING: the mark (decorative). SECOND: the
    /// loop length + playhead. MIDDLE: the wordmark + running version/build, the ONE control.
    /// TRAILING: the output monitors. Uncodixfy-compliant.
    ///
    /// ⭐ FOUNDER, 2026-08-12, screenshot of v10.79.384 (2501) (#528): a circle drawn tightly
    /// around the `E` TILE with the wordmark visibly outside it, and a red arc with a SINGLE
    /// arrowhead sweeping left onto the loop bar at the far edge. One arrowhead is MIGRATE
    /// (#411), so the circled thing moves to where the arrow lands — and the circled thing is the
    /// MARK, not the block. Row is now **mark · position · wordmark · monitors**. The reading
    /// that moves the whole block is the one to resist: it reproduces #501 exactly and undoes
    /// *"wieder in die Mitte"* (#516, four days old, said twice in one sentence). Splitting is
    /// what leaves both asks true. The full argument, the accessibility cost and the width
    /// arithmetic are on the children themselves rather than repeated here.
    ///
    /// ⭐ FOUNDER, 2026-08-08 (second ask of the same day), screenshot of v10.79.379 (2496): a
    /// circle round the brand block at the leading edge, a circle round the `1.1.1 / loop 1/8`
    /// readout, and an arc with an arrowhead at EACH end between them — *"Den Schriftzug
    /// Echoelmusic wieder in die Mitte und dementsprechend mit der Takt Anzeige tauschen."* Two
    /// arrowheads is this founder's SWAP grammar (one arrowhead = migrate, #411/#490/#501), and
    /// the sentence says the same thing twice, so there is no ambiguity to resolve: the two
    /// children exchange places. Row was then **position · brand · monitors** (⛔ this sentence
    /// read "is now" until #528 split the block; a "now" in a historical record goes stale the
    /// next time the founder draws an arrow, and this header has had five).
    ///
    /// ⛔ THIS IS THE SECOND REVERSAL OF THE SAME ORDERING IN TWO DAYS and both are recorded
    /// rather than smoothed over: #490 (2026-08-07) put the brand TRAILING, #501 (2026-08-08,
    /// earlier) put it LEADING, this puts it in the MIDDLE — which is where #384 had it on
    /// 2026-08-02, before the colour bars were removed from underneath it. The founder is free to
    /// converge by trying; what a session must not do is read one of these notes as the settled
    /// design. **The invariant across all FIVE is the LAW, not the layout:** one greedy flank, no
    /// `Spacer`, no `ZStack`, and the readout stays a leaf. (⛔ "all four" until #528 added a
    /// fifth — #384 middle, #490 trailing, #501 leading, #516 middle, #528 block split. An
    /// ordinal in a running tally is a number and ages exactly like one.)
    ///
    /// ⚠️ AND THE PRICE #501 PAID OFF IS BORROWED AGAIN, said plainly because #501 made a point of
    /// paying it: #490's note priced the brand at the trailing edge as *"a website link — not a
    /// 44 pt control — sits in the thumb corner"*, and #501 repaid that by giving the corner back
    /// to the monitor tiles. This slice does NOT undo that — the tiles are still trailing-most, so
    /// the thumb corner is still a 44 pt control (#113). What moves is only the pair to their
    /// left. That is the whole reason this is a two-child swap and not another full reorder.
    ///
    /// ⭐ FOUNDER, 2026-08-07, screenshot of v10.79.374 (2491) with a scribble over the colour
    /// bars, a circle around the mark and a long arrow down to the position readout: *"E Logo
    /// wieder nach rechts, die bunten Balken weg stattdessen die Anzeige für die Loop Länge und
    /// der Balken."* All three clauses are ONE change and the arrow is what disambiguates it —
    /// the readout does not get copied here, it MOVES here (a second copy would be #416).
    ///
    /// ⛔ IT SUPERSEDES #384, WHICH IS FIVE DAYS OLD, and the previous reasoning is kept below
    /// rather than deleted because it was not wrong. On 2026-08-02 the founder asked for the
    /// Field panel's colour bars up here and for the wordmark back in the middle; the argument
    /// recorded then was that a live spectrum is a MEASUREMENT rather than a decorative tile,
    /// which is the one class of content the science-first rule asks for by name. That argument
    /// still holds — and it holds even better for what replaced it. The loop readout is also a
    /// measurement, it is the ONE fact a performer needs at a glance while both hands are busy,
    /// and unlike the spectrum it exists nowhere else on screen. **The spectrum was a SECOND
    /// copy**: `AnalysisSpectrumView` in the Field panel is the same ring, the same bands and
    /// the same frequency→visible-light colours, at a size where the number beside it is
    /// readable. So this removes a duplicate, not a capability — which is the fact that made
    /// deleting `HeaderSpectrumStrip.swift` outright the honest move rather than unmounting it
    /// and leaving a doorless leaf behind.
    ///
    /// ⚠️ THE BRAND IS CENTRED IN THE SLACK, NOT IN THE BAR — and the difference is measurable, so
    /// it is stated rather than implied by the word "Mitte". The centring machinery #384 used was
    /// TWO greedy flanks splitting the leftover width evenly, which does put a child in the
    /// geometric middle; it is still banned (the "one greedy flank" law below — named rather than
    /// pointed at, because a positional reference in this file has never survived an insertion),
    /// so the greedy modifier simply MOVED from the readout onto the brand. One flank
    /// centres the brand between its two
    /// neighbours, and those neighbours are not the same width: the offset from true centre is
    /// exactly half their difference. The tile cluster is 54 + 38 + 38 + 2×8 = **146** by
    /// construction; the readout is a 44 pt capsule plus ~46 pt of digits ≈ **98**. So the
    /// wordmark sits about **24 pt LEFT** of the bar's true middle — the FORM of that number is
    /// exact, its size inherits the readout estimate, and neither is a measurement of a rendered
    /// layout. At ~24 pt (roughly two characters) that is the cheapest honest reading of "in die
    /// Mitte" available under the law below; true centring costs a second flank.
    ///
    /// ⚠️ THE GREEDY MODIFIER SITS OUTSIDE THE `Button`, AND THAT IS LOAD-BEARING. Under
    /// `.buttonStyle(.plain)` the hit test follows the label's own content, not an enclosing
    /// frame — the measured fact behind #482 and #485, where five `.plain` buttons fell back to
    /// ~38×32 until `.contentShape(Rectangle())` was added on purpose. Here that works FOR us:
    /// the brand keeps exactly the tap area it had, and the slack it now spans stays dead. **Do
    /// not "fix" this by adding `.contentShape`** — it would turn the middle third of the header
    /// into a link that opens a website, which is the opposite of a 44 pt control in a place a
    /// thumb rests.
    ///
    /// ⚠️ UNDER COMPRESSION THE WORDMARK NOW YIELDS FIRST, where the readout used to. The greedy
    /// child is the flexible one, so on the narrowest shipped phone (360 pt, iPhone 12/13 mini,
    /// both on iOS 18) the brand absorbs the shortfall and `minimumScaleFactor(0.7)` takes it.
    /// That is the better direction and is why the swap is safe as well as asked-for: the readout
    /// is a MEASUREMENT whose digits must stay legible, the wordmark is a link that already ships
    /// a scale floor for exactly this. Two things from the old machinery MUST survive, and both
    /// are pinned:
    ///   · **NO `ZStack`.** It gives its layers no collision avoidance, so a title on its own
    ///     layer grows straight THROUGH the mark and the tiles as Dynamic Type raises it, with
    ///     `minimumScaleFactor(0.7)` only bounding how far. The chrome is capped at
    ///     `.accessibility1` (#262), not `.xxLarge`, so that overlap is reachable. In an
    ///     `HStack` the slack yields first and nothing can overlap at any size.
    ///   · **NO `Spacer`.** The one greedy flank already owns the leftover width; a `Spacer`
    ///     would compete with it for the same slack and move the layout by an amount that
    ///     depends on how much slack there happens to be. Place with the flank's alignment.
    ///
    /// ⚠️ THE READOUT IS A LEAF AND MUST STAY ONE — and this placement is the highest-stakes
    /// instance of that law in the app, exactly as the spectrum's was. `TransportPositionView`
    /// reads `transport.position`, ~10 Hz at 120 BPM, in ITS OWN body. CONSTRUCTING it here
    /// registers nothing. Inlining its two labels — the tempting "simplification" for a
    /// two-label view — would put a 10 Hz read in the ROOT chrome, an ancestor of every surface,
    /// and every rebuild tears down any open `.menu` Picker in the instrument below: the
    /// 10.76.50 freeze, which took four attempts to find because three audits scoped to
    /// `EchoelStudioView` while the read was one level up. `AnyView` is not an observation
    /// boundary; only a separate `View` struct is.
    ///
    /// ⭐ ONE THING GOT BETTER BY ACCIDENT AND IS WORTH NAMING, because the note on
    /// `TransportPositionView` recorded it as an unmeasured cost when it went the other way:
    /// down in `EchoelStudioView` the readout was UNCLAMPED (the chrome's `.accessibility1` cap
    /// is on this Group, and `SurfaceHost` is its sibling) and inside `StudioZoom`'s pinch
    /// scope. Back up here it is clamped again, next to a hard `44×4` capsule it has to live
    /// with. That is the outcome that note wanted; it is still a device look, not a proof.
    private var topBar: some View {
        HStack(spacing: 8) {
            // LEADING: the mark alone — the founder's 2026-08-12 arrow (#528).
            //
            // ⭐ THE ASK, screenshot of v10.79.384 (2501): a circle drawn tightly around the `E`
            // TILE — the wordmark "Echoelmusic" is visibly OUTSIDE it — and a red arc with a
            // SINGLE arrowhead sweeping left onto the loop bar at the far edge. One arrowhead is
            // this founder's MIGRATE grammar (#411); two would have been a swap (#516). So the
            // circled thing moves to where the arrow lands, and the circled thing is the mark.
            //
            // ⛔ THE TEMPTING READING IS "MOVE THE BRAND BLOCK", AND IT CONTRADICTS HIS OWN LAST
            // SENTENCE. Moving mark AND wordmark to the leading edge reproduces the #501 layout
            // exactly — undoing *"Den Schriftzug Echoelmusic wieder in die Mitte"* (#516), which
            // is four days old and was stated twice in one sentence. He has circled the brand
            // WITH the wordmark before (#501) and did not this time. Splitting is the reading
            // that leaves both asks true: the mark takes the leading edge, the wordmark keeps
            // the middle. Nothing here is inferred from taste — it is the smaller circle.
            //
            // ⚠️ IT IS DECORATIVE NOW, AND THAT IS A NAMED COST, not an oversight. Inside the
            // `Button`'s label the mark was part of one control and one VoiceOver stop; standing
            // alone it would be a SECOND stop announcing "Echoelmusic" beside a button announcing
            // "Echoelmusic <version>" (`EchoelLogoMark` carries its own `.accessibilityLabel`, so
            // it is an element on its own — being a `Canvas` does not exempt it). Hence
            // `.accessibilityHidden(true)`, the same workaround the pre-#384 split mark used and
            // the reason `ChromeDynamicTypeTests` banned that modifier; that ban is now an
            // exactly-one allowance, updated in this commit rather than deleted (#456).
            // What is LOST: tapping the logo no longer opens the website. The door is unchanged
            // and two children away on the wordmark — one action, one announcement, one control.
            // Making it a second `Button` instead would restore the tap and buy back both
            // problems, plus a 22×22 hit target under the 44 pt floor (#113).
            //
            // ⚠️ THE WIDTH BUDGET, and it is arithmetic rather than hope. #528 made it net zero:
            // the bar gained a 22 pt child and a fourth top-level gap (+30) while the brand block
            // lost the same mark and its inner 8 pt gap (−30). The 26 below spends **+4 pt** of
            // that, and it comes out of the ONE greedy flank, which is the brand block. On the
            // narrowest shipped phone (360 pt, iPhone 12/13 mini — both on iOS 18) the brand's
            // share goes ~76 → ~72 pt against a mixed-case "Echoelmusic" of ~85 pt at 14 pt, so
            // `minimumScaleFactor(0.7)` absorbs it at ~0.85 and never reaches its floor. The
            // readout is the inflexible child and does not move. Constants, not a rendered layout.
            //
            // ⭐ 22 → 26 IS THE FOUNDER'S 2026-08-12 ASK (*"E links oben könnte gefühlt größer
            // aber schau selbst"*), and it is deliberately NOT a proportion fix — measured, the
            // proportion was already right: the website nav sets the mark to 28 px in a 64 px bar
            // (43.8 %), this bar is ~50 pt and 22 pt is 44 %. What differed was the LETTERFORM
            // (SF Pro vs Atkinson — corrected in `EchoelLogoMark` in the same commit). 26 pt is
            // 52 % of this bar, i.e. deliberately more prominent than the site's ratio rather
            // than equal to it, because he asked for more presence and this bar is denser than a
            // 1120 pt nav. The number itself is NOT pinned by a guard: a design size that a test
            // freezes is a test that reddens ordinary design work (#364).
            //
            // ⚠️ NO TAP-TARGET FLOOR APPLIES and that is why growing it is cheap: the mark is
            // decorative and `.accessibilityHidden(true)` (see above) — it is not a control, so
            // #113's 44 pt does not bind. It also stays well under the tile cluster's 44 pt tap
            // height, so the bar's own height is unchanged.
            EchoelLogoMark()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            // SECOND: the loop length + the playhead inside it — the founder's "die Anzeige für
            // die Loop Länge und der Balken" (#490), which lived in the MIDDLE until the #516
            // swap moved it to the leading edge and #528 put the mark to its left. It is still
            // the only copy: `EchoelStudioView` gave up its third line for it, so there is one
            // readout at one address (#416).
            //
            // ⚠️ NO `#if canImport(AVFoundation)` HERE and none is needed — this leaf reads
            // `Transport` and `@AppStorage` only. (The colour-bar strip it originally replaced
            // carried a note about NOT guarding it, because its `#else` branch would have been a
            // `Spacer` fighting a flank for the same slack. That hazard is unchanged and is why
            // the `Spacer` ban in the property's doc is pinned rather than remembered.)
            //
            // ⚠️ IT NO LONGER CARRIES THE GREEDY FLANK — the modifier moved onto the brand block
            // below, so this child now takes its natural width. The COUNT is unchanged (still
            // exactly one, pinned in `TheHeaderShowsTheLoopTests`); only the owner moved. The
            // consequence worth knowing before "tidying" this back: as the inflexible child, the
            // readout keeps its digits at full size when the bar runs out of room, and the
            // wordmark absorbs the shortfall through its own `minimumScaleFactor(0.7)`. A
            // measurement should not be the thing that shrinks.
            TransportPositionView()
            // MIDDLE: the wordmark + version, centred in the slack between the readout and the
            // monitor tiles. ⛔ THIS SAID "the brand block — mark then wordmark, in the website's
            // lockup order (`docs/index.html` `.nav-logo`: `display: flex`, the 28 px mark, a
            // gap, then the name)" until #528 sent the mark to the leading edge on the founder's
            // arrow. The lockup no longer matches the website's, deliberately and by ask — do not
            // "restore" it from this note or from `docs/index.html`.
            //
            // ⭐ THE ASK, founder 2026-08-08 (second of the day), screenshot of v10.79.379 (2496):
            // the brand circled at the leading edge, the `1.1.1 / loop 1/8` readout circled, and
            // an arc between them with an arrowhead at EACH end — *"Den Schriftzug Echoelmusic
            // wieder in die Mitte und dementsprechend mit der Takt Anzeige tauschen."* Two
            // arrowheads is the SWAP grammar (one arrowhead has meant migrate since #411), and
            // the sentence states it twice ("in die Mitte" + "tauschen"), so nothing here is
            // inferred: these two children exchange places, everything else stands.
            //
            // ⛔ THIS IS THE THIRD PLACEMENT OF THE BRAND IN TWO DAYS — trailing (#490), leading
            // (#501), middle (now, which is where #384 had it on 2026-08-02). All three are
            // recorded rather than overwritten, because the tempting shortcut for a future
            // session is to treat whichever note it finds as the settled design and "restore" it.
            // None of them is. What IS invariant across all three is the law in the property's
            // doc: one greedy flank, no `Spacer`, no `ZStack`, readout stays a leaf.
            //
            // ⚠️ #501's REPAYMENT SURVIVES AND IS NOT RE-BORROWED. #490 priced the brand at the
            // trailing edge as *"a website link — not a 44 pt control — sits in the thumb
            // corner"*; #501 paid that back by giving the corner to the monitor tiles. This slice
            // touches only the pair to their LEFT, so the tiles are still trailing-most and the
            // thumb corner is still a 44 pt control (#113). That is exactly why the founder's
            // two-child swap is implemented as a two-child swap and not as another full reorder.
            //
            // ⚠️ WHAT IS **NOT** COPIED FROM THE WEBSITE, measured rather than waved away: the
            // site sets the wordmark `text-transform: uppercase; letter-spacing: 3px`. At the
            // shipped 14 pt that turns "Echoelmusic" (~85 pt wide) into "ECHOELMUSIC" (~112 pt
            // without tracking, ~145 pt with 3 pt of it). The bar's budget on the narrowest
            // shipped phone (360 pt, iPhone 12/13 mini — both on iOS 18) is 360 − 24 padding
            // = 336, of which the tile cluster takes 54 + 38 + 38 + 2×8 = 146 and the two
            // top-level gaps take 16, leaving 174 pt for brand AND readout together. The
            // readout is a 44 pt capsule plus ~46 pt of digits ≈ 98. So the brand has ~76 pt,
            // and even the mixed-case wordmark only fits by way of `minimumScaleFactor(0.7)`.
            // Uppercase + tracking is a legibility LOSS at this width, not a gain. Arithmetic
            // over constants, not a measurement of a rendered layout — the device look is the
            // founder's call.
            Button { openWebsite() } label: {
                // ⛔ THE `HStack(spacing: 8)` THAT WRAPPED THIS HELD THE MARK AND IS GONE (#528).
                // It had exactly one job — the gap between mark and wordmark — and the mark left
                // for the leading edge, so a container around a single child would have been
                // structure kept to satisfy a test. `ChromeDynamicTypeTests` counted three
                // `HStack(spacing: 8)` in this bar and now counts two, updated in the same commit.
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
            .buttonStyle(.plain)
            // ONE element, one announcement, one action — still true after #528, by a different
            // mechanism. ⛔ THIS SAID "putting the mark INSIDE its label is what removes the
            // second VoiceOver stop"; the mark is no longer inside it. What keeps the count at
            // one is now the `.accessibilityHidden(true)` on the leading mark — the same
            // workaround the pre-#384 split used, restored because the split is back by ask.
            // Deliberately no `.accessibilityElement(children: .ignore)` here: on a Button that
            // is at best redundant and at worst rebuilds the element without its activation.
            .accessibilityLabel("Echoelmusic \(Self.versionString)")
            .accessibilityHint("Opens echoelmusic.com — release notes and support")
            // THE ONE GREEDY FLANK, and it is now the brand's. The count is unchanged and pinned
            // in `TheHeaderShowsTheLoopTests`; only the owner moved (readout → brand), which is
            // what makes "Mitte" happen at all: the flexible child absorbs the leftover width and
            // `.center` puts its content in the middle of what it absorbed.
            //
            // ⚠️ IT SITS OUTSIDE THE `Button`, AND THAT IS LOAD-BEARING. Under
            // `.buttonStyle(.plain)` the hit test follows the label's own content, not an
            // enclosing frame — measured in #482/#485, where five `.plain` buttons fell back to
            // ~38×32 until `.contentShape(Rectangle())` was added deliberately. Here that works
            // FOR us: the brand keeps exactly the tap area it had and the slack it spans stays
            // dead. **Do not "fix" this with `.contentShape`** — it would turn the middle of the
            // header into a link that opens a website, under a thumb that is reaching for the
            // tiles.
            .frame(maxWidth: .infinity, alignment: .center)
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
            // picker) — only its address changed. ⛔ THIS SENTENCE ENDED ON "the space it left
            // was circled again on 2026-08-02 and now holds the output spectrum" — written by
            // #384 and left standing by #490, which DELETED that spectrum. The space holds the
            // loop readout, which since the 2026-08-08 swap is the LEADING child rather than the
            // middle one — so this note no longer sits next to what it describes, and says so
            // instead of pointing "above". Same class as everything else in this file: a note
            // whose subject was moved or removed by a later slice reads as if it never happened.
            //
            // TRAILING: the output monitors — recorded Clips · Lux · BioSynth visual.
            // (The former video-lane monitor tile was retired with the DAW video
            // editing — pure-instrument cut; the tile now surfaces the recorded
            // performance clips + REC state.) Each is a LEAF that reads its own
            // live state (freeze rule); taps go through the chrome-door
            // notification, never into studio state directly.
            //
            // ⚠️ GROUPED IN ITS OWN `HStack`, and that is not cosmetic: it makes the three tiles
            // ONE child of the bar, so the bar's `spacing: 8` puts a single gap between them and
            // the brand block to their left. Applied per tile, a width modifier would give each
            // one its own share of the leftover width and spread them across the bar. ⛔ THE
            // `.frame(maxWidth: .infinity, alignment: .trailing)` THAT SAT HERE IS GONE and MUST
            // STAY GONE. Its REASON has now been re-stated three times under three different
            // layouts, and that is exactly why it is kept as a ⛔ rather than trimmed: under #490
            // a second flank would have pulled the brand off the TRAILING edge; under #501 off
            // the LEADING one; today it would split the slack the brand centres in, so the
            // wordmark would drift with whatever width is left over instead of sitting in the
            // middle. Three layouts, three failure descriptions, one rule. One greedy flank —
            // and since 2026-08-08 it belongs to the BRAND, not the readout. Still no `Spacer`
            // (see the property's doc).
            HStack(spacing: 8) {
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
            // ⬆ THE MONITOR CLUSTER STAYS TRAILING-MOST — it was NOT part of the 2026-08-08 swap
            // and that is deliberate, not an omission: the founder's arc had an arrowhead at each
            // end and both ends were the brand and the readout. The tiles held the thumb corner
            // from #501 onward and keep it, so the 44 pt tap floor (#113) stays where a thumb
            // reaches. Reordering them "for symmetry" with the pair to their left would silently
            // re-borrow the cost #490 wrote down and #501 repaid.
        }
        .padding(.horizontal, 12)
        // ⚠️ `fixedSize` + `minHeight` ARE A PAIR, and `fixedSize` comes FIRST. This is the
        // canonical statement of the rule for every chrome bar in this file; it used to live
        // on `TransportBar`'s frame and moved here when #456 dissolved that bar, because
        // another frame points at it by name ("read that note first"). ⛔ THAT COUNT WAS
        // WRITTEN AS "two other frames" IN THE MOVE ITSELF: it was two while `TransportBar`
        // existed, and moving the note onto `topBar` turned one of the two citers INTO the
        // host. `CompositionHeaderStrip`'s frame is the one that remains.
        //
        // `.frame(height: h)` reports `h` whatever the child does. `.frame(minHeight: h)`
        // forwards the incoming proposal downward and reports `max(child, h)` — so it only
        // preserves the old geometry if the subtree is vertically INFLEXIBLE. A chrome subtree
        // is not automatically that: `EchoelValueField`'s scrub layer is a bare `Rectangle()`,
        // which accepts any proposed height (see the note at that Rectangle). A bar hosting one
        // therefore starts reporting ∞ — and its sibling `SurfaceHost` is `maxHeight: .infinity`
        // too, so a VStack ranking both as infinitely flexible SPLITS the free space between
        // them. That is exactly what the founder photographed in v10.79.371 once #411 moved the
        // tempo field out from under a bar that carried this pair (#455): the control itself now
        // carries `fixedSize`, so it is safe in any bar — but a bar that hosts ANY future greedy
        // child still needs this pair of its own.
        //
        // `.fixedSize(horizontal: false, vertical: true)` proposes nil downward, so a greedy
        // child falls back to its ideal and the bar takes its true content height; the
        // `minHeight` then floors it at the design size. Flexibility is back to zero, which is
        // what a fixed height gave us — this time without capping the text. Removing either half
        // re-opens the split. (⛔ This paragraph ended on "44 pt is also the HIG tap-target
        // floor" — true of the DELETED bar's design height, meaningless above the 50 below.
        // A note that moves keeps its rule and drops its host's numbers. Every chrome design
        // height in this file is at or above the 44 pt floor, which is the general form.)
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
/// #289 — the playback ■/▶, EXTRACTED from the then-existing `TransportBar` so it can sit in the studio's
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
        // REQUESTED, and the only producer of that request was the `PianoRollView` struct,
        // whose door was removed on 2026-07-26 (and the struct itself deleted by #475, so do
        // not go looking for it). So this ■ ended the whole session — a second full Stop
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
                    //
                    // ⛔ 44×48 UNTIL #481, AND THE COMMENT ABOVE WAS ALREADY FALSE WHEN IT WAS
                    // WRITTEN. It justified 48 with "Ableton's transport strip is UNIFORM-height
                    // — ours was 56 / 32 / 48 centred" — and then picked a FOURTH number, so the
                    // row read 56 / 44×48 / 32 / 48 / 32. The observation was right and the fix
                    // did not follow from it. The founder said the same thing again on
                    // 2026-08-07 with the row circled, and named the reference this time: the
                    // header tiles. `EchoelTheme.controlHeight` is that size, and it is now the
                    // one definition (#416) rather than a fifth literal.
                    //
                    // Reason (2) of the old comment survives intact and is why the tap frame
                    // below exists: this clears the HIG floor on its OWN geometry, so the hit
                    // area is never faked by outsetting into a neighbour's gap.
                    .frame(width: 44, height: EchoelTheme.controlHeight)
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
                        // neighbourhood was invented: at the time the "•••" lived in
                        // `TransportBar`, two rows and a divider above the studio, and the note at
                        // the top of that struct said so in as many words. I derived adjacency from
                        // FILE ORDER — the
                        // exact mistake CLAUDE.md had just been amended about, in the same
                        // session, over a grid attributed to the wrong panel for the same reason.
                        // It also called this "the lowest-contrast control in the app", which was
                        // a ~46-way tie: `border` is ONE opacity. What was true, and is the whole
                        // argument, is that it was the LARGEST control still at 1.16:1.
                        .strokeBorder(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.borderStrong, lineWidth: 1))
                    // AFTER background+overlay, the header-tile spelling: the picture stays
                    // `controlHeight`, only the hit area grows (#113/#481). Before them it
                    // would paint the chip 44 tall instead.
                    .frame(height: EchoelTheme.controlTapHeight)
            }
            .buttonStyle(.plain)
            // ⛔ The outset is GONE (`inset(by: -6)`), and deliberately, not by oversight: it
            // existed only to lift a 38×32 chip to the 44 pt HIG floor by borrowing 6 pt from
            // each side — which meant this button's hit area reached into the gaps beside its
            // neighbours. The floor is met by the control itself: 44 pt wide by its own frame,
            // 44 pt tall by the `controlTapHeight` frame INSIDE the label above — which is
            // where it has to be, because a `Button`'s tap area is its LABEL's content shape.
            // (⛔ The sentence here said "the chip is 44×48 now" until #481 shrank the picture
            // to the header tiles' 32; the floor argument is unchanged, its source moved.)
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

// ⛔ `TransportBar` IS DISSOLVED (#456, founder 2026-08-07, screenshot of v10.79.371 with
// the "•••" and the `1.1.1 / loop 1/32` readout each circled and an arrow drawn INTO the
// transport row below them). It was the last chrome bar, and since #411 took the tempo
// field out it held exactly two children — this menu and `TransportPositionView`. The menu
// lives in `EchoelStudioView.quickActionRow`; the readout went there too and came BACK to
// `WorkspaceView.topBar` with #490 (⛔ this clause said "Both now live in
// `EchoelStudioView.startControlRow`" and was half false the moment #490 landed — the same
// commit that lectured about re-pointing `ChromeDynamicTypeTests` in the same breath missed
// the pointer in the file it was editing). The struct is deleted rather than left as an
// empty container, so there is no bar to "put something back into".
//
// ⭐ WHY TWO LINES AND NOT ONE, which is what the arrows most literally ask for. The note
// that stood on this struct measured it and said no, and that measurement still holds:
// folding all four of the row's children plus these two onto one line leaves the analysis
// pill — which the founder asked to make BIGGER on 2026-07-31 (#305/#307) — with roughly a
// third of its width on a 393 pt phone once the pause button appears. Two founder asks pull
// against each other. `startControlRow`'s own doc had already written down the answer for
// exactly that case: *"the cheapest answer is to move `TransportPositionView` and the '•••'
// overflow OUT of the chrome bar as well and give this row a second line — NOT to send the
// tempo back up."* #456 is that sentence carried out. Line 1 is bit-for-bit unchanged, so
// nothing can be squeezed, and the arithmetic goes the right way: this bar was ≥44 pt of
// chrome and the new second line is ~32 pt inside the instrument, so the playable area
// GAINS height rather than losing it.
//
// ⚠️ THE `fixedSize` + `minHeight` NOTE THAT LIVED ON THIS STRUCT'S FRAME MOVED to `topBar`'s
// frame. It is a rule about every chrome bar rather than about this one — deleting the bar
// would have deleted the canonical statement of a law that still governs live frames. (⛔ Both
// this sentence and the note itself said "two other frames" on arrival. Two was right while
// this struct existed; hosting the note on `topBar` converted one citer into the host, so the
// answer is ONE: `CompositionHeaderStrip`. A count taken before a move does not survive it.)
//
// ⛔ `toggle()` WENT FROM HERE EARLIER, not merely unused: it moved with the ■ into
// `PlaybackToggleButton` (#289). A private method with no caller compiles silently in Swift
// — no warning, no gate — so leaving it would have been a second, divergent copy of the
// playback-stop path waiting for someone to "restore" a button onto it. The four
// `@Environment` values it needed went with it for the same reason.

// ⛔ `TransportOverflowMenu` WAS DELETED HERE (#492, founder 2026-08-07, third of four asks on
// the v10.79.374 screenshot: *"Das mit den drei Punkten als einzelnde Buttons anzeigen."*). It
// was the "•••" chip that held the last two global doors; both are individual `EchoelIconTile`
// buttons in `EchoelStudioView.quickDoorRow` now, and they set `showLiveColabo` / `showLearn`
// directly instead of posting `.echoelChromeDoor` to the view they already live in.
//
// TWO THINGS THIS TYPE CARRIED THAT MUST NOT GO WITH IT, moved to `quickDoorRow`'s doc rather
// than left here where nothing renders them (#456: a deletion that strands its own reasoning
// reads as "the rule was withdrawn"):
//   · WHY Live Colabo and Learn were never chips (#290) — they are the only global doors that
//     are NOT panels, they present full sheets, and a chip that opens a modal is a lying tab.
//   · THE 44 pt FLOOR (#113) — this chip reached it through `EchoelIconTile`'s layout frame,
//     not through the `contentShape(...inset(by: -6))` outset it carried until #482. The two
//     preset overflows still use that outset at the correct level (on the `Menu`, outside the
//     `label:` closure) and `TapTargetFloorTests` pins both; nothing here is an argument
//     against them.
//
// `doorMenuButton` went with it — its only caller. A private helper with no caller compiles
// silently in Swift, which is the same trap the `toggle()` note above records.

/// The moving playhead — bars.beats.sixteenths (1-based, DAW convention). Isolated in
/// its OWN leaf because `transport.position` updates on every step (~10 Hz at 120 BPM);
/// keeping the read here means only this tiny label rebuilds, never its siblings or
/// (crucially) the instrument below. Monospaced so width is steady.
///
/// ⚠️ THE LEAF IS LOAD-BEARING IN THE HARDEST PLACE THERE IS. Its home since #490 is
/// `WorkspaceView.topBar` — the ROOT chrome, an ancestor of every surface in the app.
/// (⛔ This paragraph used to add "and that is why it stopped being `private` (#456) and stays
/// that way", and by #490 that reason DISPROVES itself: it lost `private` because #456 moved the
/// mount into `EchoelStudioView.swift`, and a `topBar` home is precisely the condition under which
/// `private` — which on a top-level type means `fileprivate` — compiles again. Nothing outside
/// this file constructs it. The access level is vestigial and harmless; it is not a law, and
/// leaving a justification whose premise negates it is the #167 mistake.)
/// Mounting a leaf there registers NOTHING;
/// only its own body reads `transport.position`, so the ~10 Hz churn stays here. Inlining these
/// two labels into the header instead is the 10.76.50 freeze exactly: the root body would rebuild
/// ten times a second and tear down any open `.menu` Picker in the instrument below. That took
/// four attempts to find, because three audits scoped to `EchoelStudioView` while the read was one
/// level up. Do not inline them.
///
/// ⭐ IT WENT DOWN INTO THE INSTRUMENT AND CAME BACK, AND THE ROUND TRIP FIXED A COST. The
/// retracted note here recorded that `EchoelStudioView` left it UNCLAMPED — the chrome Group in
/// `body` carries `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` and `SurfaceHost` is its
/// SIBLING, not a descendant — and inside `StudioZoom`'s pinch scope. Its labels are
/// `EchoelTheme.font(14)`/`(10)`, which resolve `relativeTo: .body` and therefore DO scale, while
/// the loop capsule beside them is a hard `44×4`; text that grows next to a bar that does not is
/// the shape that overflows at AX4/AX5. Back in the header it is clamped again. That is the
/// outcome the old note wanted — and it is still an unmeasured device look, not a proof.
/// (The "•••" overflow made the same trip down with no effect and then ceased to exist with
/// #492 — its glyph was `.system(size: 13)`, which does not respond to Dynamic Type at all
/// inside `EchoelIconTile`. The two door tiles that replaced it inherit exactly that property,
/// so the asymmetry described above is still ONE-sided: this readout's labels scale, the tiles
/// beside it do not.)
@MainActor
struct TransportPositionView: View {
    @Environment(Transport.self) private var transport
    /// The loop size (shared @AppStorage with the Compose panel). Read here so the chrome
    /// always SHOWS how big the loop is + where we are inside it (founder: "optische Anzeige,
    /// je nachdem wie groß der Loop umgestellt ist"). Low-frequency — safe in this leaf.
    // ⭐ READS `StudioDefaultKeys` SINCE #502 — it used to spell out `"studio.loopBars"` and
    // `.eight` by hand, under a comment saying "Default MUST match the semantic owner
    // EchoelStudioView.loopBars". That instruction was correct and unenforceable: `@AppStorage`
    // defaults are PER DECLARATION, so on a fresh install (key unwritten) a diverging copy here
    // showed "loop N/4" while the instrument composed 8 bars — H15-LOOPBARS, which SHIPPED.
    // `EchoelStudioView` has read the named constant all along; this was the last hand-written
    // copy of a decision that already had one home (#416). Now the two cannot drift, because
    // there is only one place to change.
    @AppStorage(StudioDefaultKeys.loopBars.key)
    private var loopBars: LoopBarLength = StudioDefaultKeys.loopBars.value

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
            // ⚠️ BOTH LABELS SHRINK RATHER THAN WRAP, and that is not cosmetic tidying — it is
            // what the thing this replaced did for free. `HeaderSpectrumStrip` carried only a
            // height and its Canvas opened with `guard size.width >= 36`: under-width it drew
            // nothing and cost no layout. This view has a hard `44×4` capsule beside it, and
            // `topBar` is `.fixedSize(horizontal: false, vertical: true)` over a `minHeight`, so a
            // WRAP here does not truncate — it GROWS the chrome, on the one bar whose whole job is
            // to stay a fixed slab above the instrument. The brand block two children over already
            // carries exactly this pair for exactly this reason; the asymmetry was the defect.
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%d.%d.%d", barInLoop + 1, pos.beat + 1, sixteenth + 1))
                    .font(EchoelTheme.font(14).monospacedDigit())
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // ⭐ THIS LABEL IS LOAD-BEARING FOR A SECOND THING SINCE #502, and nothing
                // said so until then. It is the ONLY place `loopBars` reaches the screen as a
                // number: the Record tile used to say "Record 8 bars → send" and became
                // icon-only with #482, whose own comment then claimed "the bar count is gone
                // from the screen entirely" — false, because #490 had already put it here.
                // So this is not just "where are we in the loop", it is also "how long is the
                // loop I am about to record". Deleting or conditioning it takes BOTH.
                // `TheBarCountHasACarrierTests` pins it together with the Record tile's
                // spoken label, so the pair cannot drift apart unnoticed.
                Text("loop \(barInLoop + 1)/\(bars)")
                    .font(EchoelTheme.font(10).monospacedDigit())
                    .foregroundStyle(EchoelTheme.dim)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
/// THE tempo control is NOT duplicated here — it lives in
/// `EchoelStudioView.startControlRow` since #411 (BodyTempoField, "einer reicht").
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
            // 8, not 12 (#502 slice 1). Every control now carries its own border, so the gap
            // no longer has to do the separating — and 8 is what the chrome rows one band
            // down already space at (`quickActionRow`, `quickDoorRow`). Five gaps × 4 pt back
            // is the only width this slice GIVES; the chip padding takes more (see `labeled`).
            HStack(spacing: 8) {
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
                labeled("A4", chromed: false) {
                    // Concert pitch — number-pad entry, exact to 0.01 Hz (380–500),
                    // standard 440.00. Commit posts "a4"; the studio pushes the new
                    // tuning to every voice + the roll and recomposes (the exact
                    // side effects the Composition panel's kammertonRow ran).
                    // ⛔ `horizontalScrub: false` IS LOAD-BEARING (#391). This field is the ONLY
                    // `EchoelValueField` inside this `ScrollView(.horizontal)`, and with the
                    // sideways axis live the gesture that scrolls the strip also raised the
                    // global tuning reference: the founder's 2026-08-02 recording shows A4
                    // walking 440 → 483.4352 → 500.0000 Hz (the range ceiling) with the keypad
                    // never opening. `onCommit` below then retunes every voice and recomposes
                    // the running take, and `session.a4Hz` is persisted — so an accidental
                    // scroll detuned the instrument and kept it detuned across relaunches.
                    // If another value field is ever added to this strip, it needs this too.
                    // ⛔ `decimals: 2` IS THE COMMENT ABOVE, MADE TRUE (#440). This row ran on
                    // `EchoelValueField`'s default 4 while the "exact to 0.01 Hz" promise at
                    // the head of this block stood over it — and `decimals` is the SNAP GRID,
                    // not a readout preference (#430), so the row actually offered 0.0001 Hz.
                    // The founder's own 2026-08-02 recording, quoted above, shows the result:
                    // `483.4352` and `500.0000` on screen. Four digits made an accidental
                    // scroll look like a deliberate setting.
                    // ⛔ This sentence said "the line six above it" and the distance was 29
                    // lines — and the same wrong "six" had already been copied into the guard
                    // and into CLAUDE.md twice before anyone re-derived it. A count of lines
                    // between two points in a file is the most fragile kind of fact this repo
                    // writes down: the very commit that states it moves the lines. Name the
                    // block, not the offset.
                    // ⛔ AND CLAUDE.md's #427 ENTRY IS WRONG ABOUT THIS ROW. It lists A4 and
                    // the locked tempo as the two that "both say 'editable to 0.0001' in their
                    // own comment". Only `BodyTempoField` says that; this one says 0.01 and
                    // always did. That entry is corrected in the same commit.
                    // ⚠️ It costs an existing user something, and the cost is measured. Worst
                    // case is half a grid step, 0.005 Hz, which at 440 Hz is 0.0197 cents —
                    // about 250× below the ~5-cent just-noticeable difference for pitch, so it
                    // is inaudible; but it IS a write, and the value is persisted.
                    // ⛔ The first draft pinned 0.0197 to a WORKED EXAMPLE — "a stored 442.3456
                    // snaps to 442.35 … that is 0.0197 cents". That snap is 0.0044 Hz at
                    // 442.3456 Hz, which is 0.0172 cents. The number was right and the sentence
                    // attached it to the wrong event; an example is not a bound, and the bound
                    // is what the claim needs.
                    // ⭐ `boxHeight` READS THE TOKEN since #502 slice 1 (was a literal 30).
                    // `EchoelValueField` already paints `radius` corners, `fill` behind and
                    // `borderStrong` around — it was always in the one format, it was just
                    // 2 pt shorter than the format says. That 2 pt is why this row is the
                    // ONLY `chromed: false` call site: adding the chip here would draw a
                    // second border around a box that has one.
                    EchoelValueField(label: "", value: $session.a4Hz, range: 380...500,
                                     unit: "Hz", decimals: 2,
                                     onCommit: {
                                         NotificationCenter.default.post(
                                             name: .echoelCompositionEdited, object: "a4")
                                     },
                                     boxWidth: 104, boxHeight: EchoelTheme.controlHeight,
                                     horizontalScrub: false)
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
            // ⛔ `.padding(.vertical, 4)` WAS HERE AND IS DELETED (#502 slice 1), not lost.
            // Every child now carries `.frame(minHeight: EchoelTheme.controlTapHeight)`
            // around a `controlHeight` chip, so each one already brings 6 pt of transparent
            // margin above and below its own paint. Keeping the padding would have stacked
            // that on top and made the band 52 pt — a compaction slice that grew the bar by
            // 12. Restoring it is how this slice's +4 becomes +12.
        }
        // Same `fixedSize` + `minHeight` pair as `topBar` — read that note first.
        //
        // This one sits on a HORIZONTAL ScrollView, and the correction to my first comment
        // here is worth keeping: a ScrollView's cross axis does NOT clamp to some intrinsic
        // size, it takes the CONTENT's size under the proposal it passes through. So with a
        // vertically greedy content (the A4 `EchoelValueField`) the ScrollView is greedy too
        // and the strip would have grown to FILL, not "grown rather than cropped". The
        // `fixedSize` is what actually bounds it; the ScrollView semantics were never the
        // thing keeping this honest.
        //
        // ⚠️ THE 40 STOPPED BEING THE BINDING CONSTRAINT IN #502 SLICE 1 and is kept anyway.
        // Its children are now 44 pt tall (`labeled`'s tap floor), so the bar renders 44 and
        // this line only guarantees it cannot COLLAPSE below 40 if every control were ever
        // removed. `ChromeDynamicTypeTests` pins this exact spelling — the number is not
        // raised to 44 because that would claim the floor moved when what moved is the
        // content, and a floor that equals the content is a fixed height wearing a minimum's
        // name (the defect #262 closed).
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 40)
        .background(EchoelTheme.bg)
    }

    /// Caption + control, inline (chrome row — the panel's label-above form layout
    /// would double the strip's height).
    ///
    /// ⭐ THIS IS WHERE THE ONE CONTROL FORMAT LIVES FOR THIS BAR (#502 slice 1).
    ///
    /// Founder, 2026-08-08, second red outline on v10.79.377 (2494): *"Den anderen rot
    /// umrandeten Bereich noch einmal auf Usability und kompactheit im einheitlichen Design
    /// intelligent anordnen und aufräumen."* Measured before anything changed, this strip was
    /// the ONE surface inside that outline with no fill, no border, no radius and no tap
    /// floor — every other control in the band (the `EchoelIconTile` rows, the chip strip, the
    /// transport controls, and the A4 field three lines up in this very strip) had read
    /// `EchoelTheme.controlHeight` / `controlTapHeight` / `radius` / `borderStrong` since
    /// #481/#483. This bar was built 2026-07-14 and simply did not take part.
    ///
    /// The treatment sits HERE and not at the six call sites on purpose: a format spelled once
    /// per control is how the transport row ended up with three heights (#416/#481). A control
    /// added later inherits it by construction; one that hand-rolls its own border is what
    /// `TheHeaderStripWearsTheOneFormatTests` goes red on.
    ///
    /// ⚠️ `chromed: false` HAS EXACTLY ONE CALLER AND MUST KEEP HAVING ONE. `EchoelValueField`
    /// already paints the identical box (same `radius`, same `fill`, same `borderStrong` —
    /// read its `valueBox`), so the A4 row would get a second border drawn around its first.
    /// It is not an opt-out from the format; it is the row that already had it.
    ///
    /// ⚠️ THE TAP FLOOR IS DELIBERATELY OUTSIDE THAT CONDITION. A4 is a control too, and its
    /// 32 pt box is as far under the 44 pt HIG floor (#113) as the pickers were. Folding it
    /// into the `chromed` branch would look tidier and would silently exempt the one row in
    /// this bar that a mis-tap actually costs something on (it retunes every voice and is
    /// persisted — see the `horizontalScrub: false` block above).
    ///
    /// ⚠️ NO `.contentShape` HERE, AND THAT IS MEASURED RATHER THAN FORGOTTEN.
    /// `EchoelIconTile` needs one because a `.plain` `Button`'s hit area is its label's
    /// CONTENT shape, so a transparent frame around it is not tappable. Every control this
    /// helper wraps is a `Picker(.menu)` or an `EchoelValueField`; a Menu's bounds ARE its
    /// label's LAYOUT size, which the frame below sets. `EchoelIconTile`'s own note says the
    /// modifier is "genuinely redundant for the `Menu`". Adding one anyway would be a
    /// modifier nobody could later prove was load-bearing.
    ///
    /// ⚠️ HEIGHT COST, stated because compactness was half the ask: the tallest child goes
    /// from ~22 pt to 44, and the strip's own `.padding(.vertical, 4)` is dropped in the same
    /// slice because the 44 pt frame already leaves 6 pt of margin around the 32 pt chip. Net
    /// band height 40 → 44, i.e. **+4 pt**, which is what `PLAN_TIDY_THE_INSTRUMENT_BAND`
    /// priced. `minHeight: 40` stays on the bar as a FLOOR (it is no longer the binding
    /// constraint) — `ChromeDynamicTypeTests` pins that spelling and it is still true.
    ///
    /// ⚠️ WIDTH COST, the honest other half: 12 pt of horizontal padding on each of six chips
    /// is +144 pt, against −20 pt from the row gap dropping 12 → 8. Net ≈ +124 pt of scroll in
    /// a bar that already scrolls horizontally, so nothing clips — it is further to scroll,
    /// not less to see. 12 is not a free choice either: it is what `EchoelValueField` pads,
    /// and the A4 box sits in this same row.
    ///
    /// ⚠️ AND `minHeight`, NEVER `height` — `EchoelTheme`'s own doc draws that line: these
    /// controls carry TEXT, and a hard height re-opens the accessibility-size overflow #262
    /// closed. The chip grows with the type; only its floor is the token.
    private func labeled<Content: View>(_ caption: String,
                                        chromed: Bool = true,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(caption)
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
            content()
                .padding(.horizontal, chromed ? 12 : 0)
                .padding(.vertical, chromed ? 3 : 0)
                .frame(minHeight: chromed ? EchoelTheme.controlHeight : nil)
                .background {
                    if chromed {
                        RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(EchoelTheme.fill)
                    }
                }
                .overlay {
                    if chromed {
                        RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.borderStrong, lineWidth: 1)
                    }
                }
                // AFTER the paint, the order `EchoelIconTile` and the header tiles both use.
                // Before it, the rounded rect would be PAINTED 44 tall — the picture grows and
                // the hit area does not, which is the opposite of the #113 idiom.
                .frame(minHeight: EchoelTheme.controlTapHeight)
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
            // ⛔ #380: THIS PREVIEW ROUNDED AND THE FILE DID NOT. Every path that actually
            // writes a name passes the unrounded tempo (`EchoelStudioView`'s save, the WAV,
            // MIDI and project exports, and `FloatingVisualWindow`'s share), and
            // `SessionNaming.trimmed` prints up to two decimals. So the label said
            // `…_71bpm_A440` while the file landed as `…_71.23bpm_A440`. Before #380 the
            // mismatch was transient — the next re-seed rounded the clock and the two agreed
            // again; #380 made it permanent for every locked fractional take, which is what
            // turned a cosmetic drift into a label that is simply wrong. A preview whose whole
            // job is "this is the exact filename" may not be the one place that rounds.
            // ⚠️ `readableFields` above KEEPS its `Int(...rounded())` and must — its own doc
            // says "READABLE is the operative word: this is a preview, not the stamped name",
            // and it rounds the concert pitch the same way. Do not sweep the two together.
            Text("File: \(session.sessionName(bpm: transport.tempo))")
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
