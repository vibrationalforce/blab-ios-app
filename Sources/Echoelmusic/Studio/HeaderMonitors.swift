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
/// MOUNTED in `EchoelStudioView.startControlRow`, immediately left of "Create from Within"
/// (founder 2026-07-31, #289: red circle around this pill and the transport ■, "könnte ja
/// alles in dem Create From within Button drin sein … Führe intelligent zusammen").
///
/// ⛔ It sat in `WorkspaceView.topBar` between logo and title from 2026-07-12 (founder: "Der
/// Pulsmonitor kommt nach oben zwischen Logo und Echoelmusic"), and this doc used to end
/// "Do not remove it again without a fresh founder ask" — because a 2026-07-03 unmount had
/// already been reversed once. The 2026-07-31 instruction IS that fresh ask, from the same
/// person, with a drawing; it is a MOVE, not an unmount, and the sentence is kept here in
/// its new form so the third session to touch this does not have to reconstruct the history.
/// The view itself is untouched: same leaf, same tap (Bio panel), same long-press (source
/// picker).
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

    // #305 → #307 — "etwas größere Anzeige für Analyse ist besser", then "Create from within
    // can also weg, einfaches Menü mit Playbutton etc wie bei Ableton reicht" (founder
    // 2026-07-31, two consecutive messages about the same row).
    //
    // ⛔ THE WIDTH BUDGET THAT STOOD HERE IS GONE, AND SO IS THE THING IT WAS BUDGETING
    // AGAINST. #305 grew this tile from 90 to 108 pt by arithmetic, against the ~205–215 pt
    // sentence "Create from Within" sharing the row. Hours later that sentence was removed:
    // the primary control is a 64 pt ▶ now, so the constraint the whole calculation existed to
    // respect no longer exists. Rather than publish a third edition of a sum about a deleted
    // label, the tile simply TAKES the row — `maxWidth: .infinity`, which is both the honest
    // expression of "there is no competitor for this space" and the largest possible answer to
    // the founder's ask, without a single hard-coded width to go stale next time.
    //
    // What is still a real choice and not a consequence:
    //   · height 48 (30 before #305, 38 after) — the first size at which this clears the HIG
    //     44 pt target for its own tap (it opens the Bio panel), which it never did as a pill.
    //   · the TRACE keeps a `minWidth` and flexes above it. A Canvas accepts any proposal, so
    //     without a floor it would collapse to nothing the moment the numbers beside it grow
    //     at accessibility text sizes — the readout must lose the fight for space, not the
    //     waveform, because the waveform is what tells you the finger is placed right.
    //   · the numbers stay LEFT-anchored next to the trace rather than pushed to the far edge:
    //     a BPM 300 pt away from the pulse it belongs to is two readouts, not one.
    var body: some View {
        HStack(spacing: 6) {
            PulseTrace(samples: waveform,
                       color: locked ? EchoelTheme.accent : (showCue ? EchoelTheme.warning : EchoelTheme.dim),
                       lineWidth: 1.8)
                .frame(minWidth: 60, maxWidth: .infinity)
                .frame(height: 34)
            Group {
                if locked && bpm > 0 {
                    Text("\(Int(bpm))")
                        .font(EchoelTheme.font(17, .semibold)).monospacedDigit()
                        .foregroundStyle(EchoelTheme.text)
                } else if showCue, let cue {
                    Text(cue.shortLabel)
                        .font(EchoelTheme.font(11, .semibold))
                        .foregroundStyle(EchoelTheme.warning)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else if showStatus, let status {
                    Text(status.short)
                        .font(EchoelTheme.font(11, .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("—")
                        .font(EchoelTheme.font(17, .semibold)).monospacedDigit()
                        .foregroundStyle(EchoelTheme.dim)
                }
            }
            .frame(minWidth: 28, alignment: .leading)
            if let coh = coherence {
                Text(EchoelDecimalText.string(coh, decimals: 2))
                    .font(EchoelTheme.font(12)).monospacedDigit()
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 8).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
        // This leaf owns the pulse element (it reads the live BPM; WorkspaceView can't,
        // per the freeze rule).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        if showCue, let cue { return cue.fullHint }
        if showStatus, let status { return status.full }
        guard locked && bpm > 0 else { return "No pulse lock" }
        if let coh = coherence {
            return "\(Int(bpm)) beats per minute, coherence \(EchoelDecimalText.string(coh, decimals: 2))"
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
/// reads here keeps WorkspaceView still; only this 38 pt monitor refreshes. (30 pt until
/// #305 — the height is quoted because it is the whole cost of the churn, so it has to move
/// with the constant.)
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
                         // `flatMap`, not `map`: a fresh frame whose coherence was never
                         // measured (HealthKit never provides it; the camera not until
                         // enough beats accrue) maps to Optional(0.0), and the pill then
                         // prints "0.00" — which reads as "incoherent", not "not yet".
                         // nil drops the number and leaves the pulse, the same law
                         // `BioStripView.coherenceString` already follows one row away.
                         coherence: fresh.flatMap { $0.coherence > 0 ? Double($0.coherence) : nil },
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
            // 2026-07-15 video: "Lange drücken = drop down: camera light · Search for
            // Bluetooth Device · Simulation").
            //   • TAP opens the Bio panel — the live numbers, tap-to-learn, the camera
            //     source control and Routing.
            //   • LONG-PRESS opens the SOURCE dropdown — "Play with camera light / a
            //     Bluetooth strap / the simulation" (the labels say "Play with" because the
            //     entries START the music when idle; see the menu's own note). The studio
            //     owns all three publishers and switches the live one (decoupled via
            //     .echoelSelectBioSource).
            //
            // ⛔ TAP NO LONGER STARTS THE INSTRUMENT (founder 2026-07-29, screenshot:
            // "Ich hab jetzt hier 3 Knöpfe zum Start … könnte man das zu einem
            // zusammenfassen?"). It did from 2026-07-15 until now, and it was one of
            // three controls that all began the same session. The one that stays is the
            // full-width, labelled "Create from Within" on the front plate; this pill
            // goes back to being what it looks like — a MONITOR. Two reasons beyond the
            // count: (a) a tap target that shows CAMERA state (`cameraRPPG.isRunning`)
            // while starting the WHOLE session is a control whose picture and effect
            // disagree the moment a BLE strap is the source; (b) the bio panel behind it
            // was reachable only through a long-press submenu entry, which is the least
            // discoverable gesture we ship and is hard to perform with a motor
            // impairment. The tap now buys the thing the pill is about.
            //
            // Deliberately a chrome-door NOTIFICATION and not a `Menu` here: this leaf
            // reads the ~10 Hz publisher in its own body, and a menu popover hosted by a
            // body that rebuilds 10×/s is torn down as fast as it opens (the freeze law,
            // 10.76.41/50). `.contextMenu` is safe because it builds its content only
            // when opened, never at body time.
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .echoelChromeDoor, object: "bio")
            }
            // ⚠️ "Play with …", not the bare source names these carried until #234. Every one
            // of them routes to `selectBioSource`, which hot-swaps the source while a take is
            // live and STARTS A FULL GENERATIVE SESSION when idle. Under the plain labels
            // ("Camera light", "Simulation") that made this menu a hidden Start — the exact
            // thing the founder counted — and one that promised only a sensor choice. The
            // capability is deliberately kept (choosing how to begin is useful); what changed
            // is that the label now says the music begins. "Play with" is honest in BOTH
            // states: idle it starts, running it keeps playing on the new source.
            .contextMenu {
                Button {
                    NotificationCenter.default.post(name: .echoelSelectBioSource, object: "camera")
                } label: { Label("Play with camera light", systemImage: "camera.fill") }
                Button {
                    NotificationCenter.default.post(name: .echoelSelectBioSource, object: "ble")
                  // "scans for one" carries the half the old "Search for Bluetooth device"
                  // said and the bare rename dropped: the music starts from neutral defaults
                  // immediately, whether or not a strap is ever found. Both halves are true
                  // and the user needs both.
                } label: { Label("Play with a Bluetooth strap — scans for one",
                                 systemImage: "dot.radiowaves.left.and.right") }
                Button {
                    NotificationCenter.default.post(name: .echoelSelectBioSource, object: "sim")
                } label: { Label("Play with the simulation", systemImage: "waveform.path") }
                Divider()
                // The only entry here that does NOT start anything — and now a duplicate of
                // the pill's own tap. Kept deliberately: it is the one place a VoiceOver user
                // exploring this menu learns the panel exists, and the three above it are all
                // commitments to start playing.
                Button {
                    NotificationCenter.default.post(name: .echoelChromeDoor, object: "bio")
                } label: { Label("Bio details…", systemImage: "info.circle") }
            }
            .accessibilityAddTraits(.isButton)
            // One hint, not two: the tap now does the same thing whether or not a pulse
            // is live, so branching on `cameraRPPG.isRunning` would only have described
            // the CAMERA while the pill may be showing a strap. The old branch also
            // promised "Tap to start reading your pulse", which is no longer true.
            // `Text(...)`, not a `String + String`: a concatenation binds the generic
            // `StringProtocol` overload, which looks nothing up — the same trap the same
            // slice spent ten lines guarding against in `OnboardingView`, walked into one
            // file over. One literal, one localisable key.
            .accessibilityHint(Text("Opens the bio panel — pulse, breath and coherence. Touch and hold to choose a bio source."))
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

    /// True while a second screen actually has the picture — i.e. the external scene is
    /// connected AND wired, so it is rendering the visual rather than the ECHOEL wordmark
    /// it falls back to before `wire(...)` lands (`ExternalStageBridge`).
    ///
    /// WHY THIS LIVES HERE INSTEAD OF ITS OWN CHIP (#206 slice 3). It was a separate
    /// header tile for exactly one review round. `topBar` is a ZStack whose right-hand
    /// HStack draws OVER the centred wordmark, and a fourth 38 pt tile + spacing moved the
    /// cluster 46 pt left — 64 pt of overlap on a 375 pt iPhone, plus the pulse pill's
    /// coherence number truncating. It would have fired at the worst possible moment: a
    /// cable going in mid-show. This tile is already THE visual monitor and already the
    /// door to the floating window, so the state belongs on it and costs zero width.
    private var onExternalScreen: Bool {
        #if canImport(UIKit)
        let bridge = ExternalStageBridge.shared
        return bridge.isConnected && bridge.bus != nil
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if onExternalScreen {
                // The picture is on the beamer; this phone's renderer has yielded (GPU
                // law). Show WHERE it went — a performer whose projector is behind them
                // otherwise cannot tell a live external output from a dead visual. Static
                // and solid: no animation, because the point of yielding is to spend
                // nothing here.
                ZStack {
                    EchoelTheme.fill
                    Image(systemName: "tv").font(.system(size: 12)).foregroundStyle(EchoelTheme.text)
                }
            } else if active {
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
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
        // 44 pt HIG tap height (#113): the visible chip stays 32, the hit area grows
        // vertically only — the header row is 8 pt-spaced, so NO horizontal expansion
        // (that would overlap the neighbour tiles). Chip stays centred = no visible change.
        .frame(height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Immersive visual monitor")
        .accessibilityValue(onExternalScreen ? "On external screen" : (active ? "Live" : "Idle"))
        .accessibilityHint("Shows or hides the floating visual window")
        .accessibilityAddTraits(.isButton)
    }

    /// The tile's live colour — the sounding chord's physical tone colour
    /// (SpectralColor, the Swift twin of the shader's CIE fit), brightness
    /// breathing with the music level and pulsing at the heart rate. PURE with
    /// explicit Double types so the ViewBuilder above stays type-checker-cheap;
    /// silent input → SpectralColor's neutral grey (an honest "nothing sounds").
    /// Flash-safety (WCAG epilepsy ≤3 Hz + the app's own ceiling): the tile's brightness-
    /// pulse rate in Hz, capped at `FlashGuard.maxPulseRateHz` so even a very fast heart
    /// rate can never drive the tile past the epilepsy-safe flash rate. Reads the shared
    /// constant rather than repeating 2.5 — the claim "the law lives in one place" was not
    /// true while this function, MetalBioView and the test each carried their own copy.
    static func flashSafePulseRate(heartRateBPM: Double) -> Double {
        min(max(40.0, heartRateBPM) / 60.0, FlashGuard.maxPulseRateHz)
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
        let rgb = SpectralColor.physicalColor(forChord: chord)
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
/// `SpectralColor.physicalColor(forChord:)` × dimmer mapping the Art-Net/sACN senders
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
                        TimelineView(.animation(minimumInterval: 1.0 / FlashGuard.maxPulseRateHz)) { _ in
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
                .strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
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
        let rgb = SpectralColor.physicalColor(forChord: chord)
        let dim: Double = 0.3 + 0.7 * (mf?.masterLevel ?? 0)
        func enc(_ v: Double) -> Double { pow(min(max(v * dim, 0.0), 1.0), 1.0 / 2.2) }
        return Color(red: enc(rgb.r), green: enc(rgb.g), blue: enc(rgb.b))
    }
}

// MARK: - Recorded-clips monitor (header)

#if canImport(AVFoundation) && canImport(Metal)
/// Compact header tile for the recorded PERFORMANCE clips (visual + master mix).
/// The former video-lane monitor was retired with the DAW video editing
/// (pure-instrument cut); this tile keeps the two things that survive that cut —
/// TAP opens the recorded-clips library (the VisualRecorder output / EchoelPublish
/// surface), and while the visual recorder captures a clip it shows a steady REC
/// state (steady, not blinking — flash law). Deliberately NOT a live thumbnail:
/// the floating visual window is the one live picture.
@MainActor
struct EchoelClipsMonitorMini: View {
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
                    : EchoelTheme.border,
                    lineWidth: 1))
            // 44 pt HIG tap height (#113): vertical-only (8 pt header spacing forbids
            // horizontal growth); the 38×32 chip stays centred, no visible change.
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recorded clips")
        .accessibilityValue(recorder.isRecording ? "Recording" : "")
        .accessibilityHint("Opens the recorded clips library.")
    }
}
#endif
#endif
