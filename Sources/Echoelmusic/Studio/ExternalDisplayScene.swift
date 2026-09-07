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
    // ⛔ "THE SAME" IS TRUE OF THE KEYS AND NOT OF THE PICTURE (#1071, measured). The phone
    // does NOT render these values raw: `FloatingVisualWindow.weatheredVisuals()` blends FOUR
    // of them — hue, saturation, intensity, motion — through `WeatherMood.blend` against the
    // live sky, each with its own user mixer (`WeatherMood.Param.<x>.mixKey`). This scene
    // reads the raw keys and renders them. So plugging in a projector SILENTLY DROPS the
    // weather tint, and the sentence above reads as if the two matched.
    //
    // ⚠️ THIS FILE ALREADY DECIDED THE PRINCIPLE, one paragraph down, and then did not apply
    // it here. #609 wired `autoMode` for exactly this reason: "without this reader, plugging
    // in a projector would silently strip the Auto mode's visual half mid-show and the swap
    // would read as a broken look." Weather is the same class of half and was left out. That
    // makes this a KNOWN GAP against a stated rule, not a taste question — the founder's open
    // "Beamer wettergemischt oder roh?" was asked before anyone measured which one it does.
    //
    // ⛔ NOT FIXED IN THIS COMMIT, and the reason is honest rather than tidy: the blend needs
    // `weatherProvider.current`, which lives on the phone side and reaches this scene only
    // through `ExternalStageBridge` — new wiring in a file no gate here can run, on a path
    // that is visible only with a projector attached. The repair belongs in its own slice with
    // `weatheredVisuals()` lifted into ONE shared pure helper both sides call (#416), so the
    // two can never diverge again. Pinned meanwhile by
    // `Tests/CISmoke/TheBeamerDrawsTheSamePictureTests.swift`, which is written to go RED on
    // the day the gap is closed — it is a record of a divergence, not a defence of it.
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
                // `capturesVideo: false` — deliberately, and the cost is GUARDED, not just
                // noted: while the beamer has the picture the phone's capturing instance
                // has yielded, so `FloatingVisualWindow` DISABLES its video-record button
                // rather than let a red REC pill count up over an empty file. Handing
                // capture over here is not a one-liner — `AVAssetWriter` takes its
                // dimensions from the first frame, so a projector plugged in mid-recording
                // would push landscape frames into a portrait file. Own slice.
                MetalBioView(capturesVideo: false,
                             autoAttuned: autoMode,
                             intensity: Float(intensity),
                             ringDensity: Float(detail),
                             motion: Float(motion),
                             spread: Float(spread),
                             hueShift: Float(hue),
                             saturation: Float(saturation),
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
