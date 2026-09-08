//
//  ExternalDisplayScene.swift
//  Echoelmusic — Studio
//
//  THE STAGE OUTPUT (#206, founder 2026-07-28): "das Bild für die visuals für einen
//  anderen Bildschirm, Beamer etc nutzen … es soll trotzdem vom iPhone aus spielbar sein".
//
//  Not mirroring and not Picture-in-Picture — a SECOND SCENE. Mirroring (AirPlay or an
//  HDMI cable) works today with no code at all, but it puts the whole instrument UI on the
//  projector. PiP was ruled out on the merits, not on effort: it floats video over other
//  apps on the SAME device and never reaches an external screen. A scene with the role
//  `UIWindowSceneSessionRoleExternalDisplayNonInteractive` is the one mechanism that shows
//  DIFFERENT content on the second screen, over both cable and AirPlay, while the phone
//  keeps the instrument and stays playable.
//
//  ✅ SLICE 1'S QUESTION IS ANSWERED — device log v10.79.356 (build 2473): `init a`–`f`,
//  `startup 1/4`–`4/4`, `LaunchGuard: confirming healthy (studio)`, `inactive → active`,
//  with nothing attached. The scene manifest did not harm the launch path, so slice 2
//  (the actual visual, below) was allowed to proceed. That gate was real, not ceremony.
//
//  WHY THE APPLICATION ROLE IS DECLARED TOO (Info.plist): once `UISceneConfigurations`
//  exists, an app that names ONLY the external role logs "Info.plist contained no UIScene
//  configuration dictionary" and relies on a fallback. The application-role entry carries
//  NO `UISceneDelegateClassName` on purpose: naming a class there is what WOULD displace
//  SwiftUI's own scene handling, so omitting it is the conservative option. That SwiftUI
//  then keeps its own delegate is REASONED, not verified — it is precisely what the device
//  run of this slice has to establish, and nothing here should be read as proof of it.
//
//  WHY NOT `UIScreen.didConnectNotification`: it needs no Info.plist change at all, so it
//  would genuinely have been the cheaper slice. It is rejected because it is DEPRECATED
//  since iOS 16 and the scene role is the supported mechanism — not for a build reason.
//  ⛔ An earlier version of this comment claimed it "would be a red build" because
//  `Package.swift` uses `-warnings-as-errors`. That was FALSE and it mattered, because it
//  was the stated justification for touching the launch path: any `UIScreen` code sits
//  inside `#if canImport(UIKit)`, both SwiftPM jobs build for hosts WITHOUT UIKit, and the
//  Xcode lanes set no `SWIFT_TREAT_WARNINGS_AS_ERRORS` at all. The deprecation would have
//  reddened nothing. The real reason is the API, not the gate.
//
//  ⚠️ SIDE EFFECT, stated because it was NOT asked for. There is no "external-display only"
//  variant of the switch: `UIApplicationSupportsMultipleScenes` is app-wide, so wherever the
//  OS offers a second app window (Split View / Stage Manager) this permits one.
//
//  ⛔ THIS USED TO ASSERT THAT `project.yml` SHIPS BOTH THE PHONE AND THE TABLET FAMILY, and it
//  drew the iPad half of the side effect above from that — falsified by #292 and left standing
//  until #551. Phone-only ships today, so the iPad half is not reachable; and this scene mounts
//  `ExternalStageView` through its own `UIHostingController` (see below), never `WorkspaceView`,
//  so the extra scene it DOES create cannot re-run the startup task either. The value belongs to
//  `project.yml` alone — pinned by `DeviceFamilyIsPhoneOnlyTests` — and restating it here was the
//  second copy that went stale (#416). Described rather than quoted, because the guard that keeps
//  this corrected is a negative scan of `Sources/` prose and a verbatim quote would red it on the
//  very commit that repairs it; the longer version of that reasoning is in `EchoelmusicApp`.
//
//  ⭐ The reasoning below is UNCHANGED and still correct; only its trigger moved from "today
//  on iPad" to "the day a second window is possible again". I first wrote that this
//  was "survivable" because both windows share ONE engine — that was WRONG and it is why
//  `EchoelmusicApp` now carries a `startupDone` latch: sharing the engine is exactly the
//  problem, because the second window's `.task` would run the WHOLE startup again against
//  an already-running engine, and `AudioEngine.attachSourceNode` has no already-attached
//  guard. That is the hot-attach-to-a-running-engine shape blamed for the build-1363
//  launch crash. The latch — not a refusal of extra scenes — is the fix, because it costs
//  the launch path one boolean instead of an app-delegate hook.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// Owns the window on an attached external screen. Referenced from Info.plist by name
/// (`$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate`) — renaming this type without
/// updating that string silently disables the feature. It fails QUIETLY by design: a
/// missing or misnamed class means no external window, never a failed launch.
@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // BREADCRUMB, not os_log: `echoel_diag.log` is the founder's only ground truth,
        // and without this line "nothing appears on the beamer" is undiagnosable — there
        // is no way to tell "the manifest was ignored and this delegate never ran" from
        // "the delegate ran and the window is wrong". Nothing here executes unless a
        // screen actually connects, so it costs the launch path nothing.
        guard let windowScene = scene as? UIWindowScene else {
            EchoelCrashLog.breadcrumb("extdisplay: connected but NOT a UIWindowScene — no output")
            return
        }
        let size = windowScene.screen.bounds.size
        EchoelCrashLog.breadcrumb(String(format: "extdisplay: connect %.0fx%.0f", size.width, size.height))
        ExternalStageBridge.shared.setConnected(true)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalStageView())
        // A projector is not a phone: nothing here is touchable, and the OS already
        // marks this role non-interactive. Making it explicit keeps a stray gesture
        // recogniser from ever stealing a touch that belongs to the instrument.
        window.isUserInteractionEnabled = false
        window.isHidden = false
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Unplugging mid-performance is a STAGE SCENARIO, not an edge case. Dropping the
        // window here is what lets the phone carry on untouched; holding a reference to a
        // disconnected scene's window is how the next reconnect gets a dead surface.
        EchoelCrashLog.breadcrumb("extdisplay: disconnect")
        // ORDER MATTERS: drop the window FIRST, release the claim second. The reverse
        // (which this file briefly had) hands the phone permission to mount its renderer
        // while this one is still alive — two live `MetalBioView`s, the exact state the
        // GPU law forbids. This order can only ever leave a gap, never an overlap, and a
        // gap is a black beamer for one layout pass instead of a starved GPU.
        window = nil
        ExternalStageBridge.shared.setConnected(false)
    }
}

/// What the projector shows: the live visual, edge to edge, with no controls.
///
/// It reads the SAME `@AppStorage` look keys the floating window uses, so the beamer and
/// the phone are one instrument with one set of settings rather than two that drift. The
/// engine objects come from `ExternalStageBridge` — this hierarchy is created by UIKit
/// and inherits no `@Environment`, which is the whole reason that type exists.
///
/// ⚠️ ONE MetalBioView APP-WIDE (decisions.csv 2026-07-03: two live renderers = GPU
/// starvation = the documented black immersive). The phone's floating window yields
/// while this one is up; see `WorkspaceView`. Do not mount a second renderer here.
private struct ExternalStageView: View {

    // The SAME design keys the floating window reads, so a tweak in the Visual panel
    // shows on the beamer too. NOTE the deliberate name mismatch: the key is
    // `visualDetail`, the `MetalBioView` parameter is `ringDensity:` — there is no
    // `visualRingDensity` key, and only the call site records that.
    //
    // ⭐ AND SINCE #1073 IT IS TRUE OF THE PICTURE TOO — the sentence above finally means
    // what it says. It did not for a long time, and the history is kept because the SHAPE of
    // the bug is the useful part: the phone mixed the live weather into four of these values
    // (hue · saturation · intensity · motion, each behind its own user mixer) while this scene
    // rendered the same four keys RAW, so plugging in a projector silently dropped the tint
    // mid-show. Nobody could see it without a projector, and the prose here read as if the two
    // matched. Measured and pinned in #1071, given ONE shared definition in #1072
    // (`WeatherMood.visualValues`), and wired here in #1073.
    //
    // ⚠️ THE RULE THIS FILE ALREADY STATED, one paragraph down, is what made it a gap and not
    // a taste question: #609 wired `autoMode` because "without this reader, plugging in a
    // projector would silently strip the Auto mode's visual half mid-show and the swap would
    // read as a broken look." Weather was the same class of half. **Apply that rule to every
    // new key added below** — a design key the phone TRANSFORMS before rendering must arrive
    // here transformed, or the swap changes the look. That is the durable lesson; the weather
    // instance of it is now closed.

    /// #609 — the beamer draws the SAME auto-attuned picture the phone would (H15):
    /// without this reader, plugging in a projector would silently strip the Auto
    /// mode's visual half mid-show and the swap would read as a broken look.
    @AppStorage(StudioDefaultKeys.autoMode.key) private var autoMode = StudioDefaultKeys.autoMode.value
    @AppStorage(StudioDefaultKeys.visualStyle.key) private var style = StudioDefaultKeys.visualStyle.value
    @AppStorage(StudioDefaultKeys.visualStyleB.key) private var styleB = StudioDefaultKeys.visualStyleB.value
    @AppStorage(StudioDefaultKeys.visualBlend.key) private var blend = StudioDefaultKeys.visualBlend.value
    @AppStorage(StudioDefaultKeys.visualIntensity.key) private var intensity = StudioDefaultKeys.visualIntensity.value
    @AppStorage(StudioDefaultKeys.visualDetail.key) private var detail = StudioDefaultKeys.visualDetail.value
    @AppStorage(StudioDefaultKeys.visualMotion.key) private var motion = StudioDefaultKeys.visualMotion.value
    @AppStorage(StudioDefaultKeys.visualSpread.key) private var spread = StudioDefaultKeys.visualSpread.value
    @AppStorage(StudioDefaultKeys.visualHue.key) private var hue = StudioDefaultKeys.visualHue.value
    @AppStorage(StudioDefaultKeys.visualSaturation.key) private var saturation = StudioDefaultKeys.visualSaturation.value
    @AppStorage(StudioDefaultKeys.visualTexture.key) private var texture = StudioDefaultKeys.visualTexture.value
    @AppStorage(StudioDefaultKeys.visualGlitter.key) private var glitter = StudioDefaultKeys.visualGlitter.value
    @AppStorage(StudioDefaultKeys.visualStructure.key) private var structure = StudioDefaultKeys.visualStructure.value

    // MARK: - Accessibility (#1118)

    /// The OS "Reduce Motion" setting, as SwiftUI sees it here.
    ///
    /// ⛔ THE BEAMER IGNORED THIS SETTING ENTIRELY UNTIL #1118, AND IT IS THE BIGGEST
    /// SURFACE THE APP DRIVES. `FloatingVisualWindow` has read it since it was written and
    /// passes it to `MetalBioView`; this scene never mentioned the word. So a person who
    /// turns Reduce Motion on got a still picture on a 6-inch phone and a full-motion one on
    /// a projector filling the room — the wrong way round, and the site says plainly that the
    /// visual honours the setting (`architecture.html`, `faq.html`). Nothing here was a
    /// deliberate exception; the argument in `MetalBioView` about "the ONE mount that omits
    /// it" is about `playGridKey`, a different parameter, and was mistaken for cover.
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion

    /// The same setting read straight from UIKit, OR-ed with the environment value below.
    ///
    /// ⚠️ WHY BOTH, and it is not belt-and-braces for its own sake. This hierarchy is built
    /// by UIKit on a second `UIWindow` (see `weathered`'s note), and this file's own comment
    /// warns that it "inherits no `@Environment`". That warning is about the `.environment(…)`
    /// injections the phone's hierarchy makes — accessibility values DO arrive from the
    /// host's trait collection — but the distinction is subtle enough that betting an
    /// accessibility guarantee on it is the wrong bet. The static read is authoritative the
    /// moment the scene is built; the environment value is the one that updates live if the
    /// user flips the switch mid-show. OR is the safe direction: either source saying
    /// "reduce" reduces.
    /// (No `#if canImport(UIKit)` here: this whole file already sits inside one, and a
    /// nested guard would read as if UIKit were optional at this point. It is not.)
    private var reduceMotion: Bool {
        envReduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    // #1073 — the weather half, so the beamer draws the phone's picture and not a raw one.
    // ⚠️ EVERY DEFAULT HERE IS THE SAME EXPRESSION `FloatingVisualWindow` uses, not a copy of
    // its VALUE. Writing `0.5` would have re-created the divergence this slice repairs, one
    // level down: the two surfaces would agree until someone changed `defaultIntensity`.
    @AppStorage(StudioDefaultKeys.weatherEnabled.key) private var weatherEnabled = StudioDefaultKeys.weatherEnabled.value
    @AppStorage(WeatherMood.Param.hue.mixKey)        private var wxMixHue = WeatherMood.Param.hue.defaultIntensity
    @AppStorage(WeatherMood.Param.saturation.mixKey) private var wxMixSat = WeatherMood.Param.saturation.defaultIntensity
    @AppStorage(WeatherMood.Param.glow.mixKey)       private var wxMixGlow = WeatherMood.Param.glow.defaultIntensity
    @AppStorage(WeatherMood.Param.movement.mixKey)   private var wxMixMove = WeatherMood.Param.movement.defaultIntensity

    /// The four visual values with the sky mixed in — THE SAME function the phone calls
    /// (#1072/#1073). Not a second implementation, on purpose: two spellings of one decision
    /// is what produced #1071 in the first place, and a copy here would look right for a year.
    ///
    /// `sky` comes over `ExternalStageBridge` because this hierarchy is built by UIKit and
    /// inherits no `@Environment`; `weatherEnabled` and the four mixers are `@AppStorage`, so
    /// they cross by themselves. Weather off, or no sky published yet → the user's own values,
    /// which is exactly what this scene rendered before.
    private func weathered(sky: WeatherMood.Contribution?)
        -> WeatherMood.VisualValues {
        WeatherMood.visualValues(
            base: WeatherMood.VisualValues(hue: hue, saturation: saturation,
                                           intensity: intensity, motion: motion),
            mixers: WeatherMood.VisualMixers(hue: wxMixHue, saturation: wxMixSat,
                                             glow: wxMixGlow, movement: wxMixMove),
            contribution: weatherEnabled ? sky : nil)
    }

    var body: some View {
        // Read `.shared` INLINE, not via a stored `private let`. Observation registers on
        // the property getter either way, so this is not about correctness — it matches
        // how every other view in this repo reaches a shared object, and it avoids a
        // stored-property default whose isolation rules are subtler than they look.
        let bridge = ExternalStageBridge.shared
        return ZStack {
            // Solid fill, not a gradient — a projector in a dark room exaggerates banding,
            // and it is the backdrop the visual draws over.
            EchoelTheme.bg.ignoresSafeArea()
            // The `if let` IS the guard — it binds what it checks. There is deliberately
            // no separate "is it wired?" boolean to drift out of sync with it.
            if let bus = bridge.bus, let governor = bridge.governor, let recorder = bridge.recorder {
                // #1073: the weather-mixed values, from the one shared definition.
                let wx = weathered(sky: bridge.sky)
                // `capturesVideo: false` — deliberately, and the cost is GUARDED, not just
                // noted: while the beamer has the picture the phone's capturing instance
                // has yielded, so `FloatingVisualWindow` DISABLES its video-record button
                // rather than let a red REC pill count up over an empty file. Handing
                // capture over here is not a one-liner — `AVAssetWriter` takes its
                // dimensions from the first frame, so a projector plugged in mid-recording
                // would push landscape frames into a portrait file. Own slice.
                // #1118 — `reduceMotion` sits SECOND because `MetalBioView` declares it
                // second and Swift's memberwise init follows declaration order (the same law
                // that struct's own "DECLARED LAST ON PURPOSE" note is about). The projector
                // now obeys the accessibility setting the phone has always obeyed;
                // `MetalBioView` turns it into a STILL frame (pulseHz 0), which on a stage is
                // a real consequence and the correct one — the person who set the switch is
                // the person driving the show. NEEDS-FOUNDER-VERIFY: if a performance must
                // keep moving with the switch on, that is a per-surface OVERRIDE to design,
                // not a reason to go back to ignoring the setting.
                MetalBioView(capturesVideo: false,
                             reduceMotion: reduceMotion,
                             autoAttuned: autoMode,
                             intensity: Float(wx.intensity),
                             ringDensity: Float(detail),
                             motion: Float(wx.motion),
                             spread: Float(spread),
                             hueShift: Float(wx.hue),
                             saturation: Float(wx.saturation),
                             textureAmount: Float(texture),
                             glitterAmount: Float(glitter),
                             structureAmount: Float(structure),
                             style: style, styleB: styleB, blend: Float(blend))
                    .environment(bus)
                    .environment(governor)
                    .environment(recorder)
                    // #594 slice 2: OPTIONAL on purpose, outside the if-let gate —
                    // the optional .environment overload hands a pre-wire nil
                    // through, and MetalBioView's optional read renders untinted
                    // rather than trapping. The tint follows once wire() has run.
                    .environment(bridge.synth)
                    .ignoresSafeArea()
            } else {
                // Not wired yet (a screen attached before the startup task finished, or a
                // future refactor that forgets `wire`). A backdrop that says ECHOEL is a
                // usable stage; a trapped `@Environment` lookup takes the whole app down
                // in front of an audience. Fail to the wordmark, on purpose.
                Text("ECHOEL")
                    .font(EchoelTheme.font(28, .semibold))
                    .foregroundStyle(EchoelTheme.dim)
                    .accessibilityHidden(true)
            }
        }
    }
}
#endif
