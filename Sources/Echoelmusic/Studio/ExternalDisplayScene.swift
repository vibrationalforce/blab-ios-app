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
//  ⚠️ SLICE 1 DELIBERATELY RENDERS ALMOST NOTHING. The visual itself lands in slice 2.
//  This slice exists to answer ONE question on a real device: does the app still launch
//  cleanly with NO external screen attached? Adding a scene manifest flips
//  `UIApplicationSupportsMultipleScenes` and introduces a scene delegate — it touches the
//  launch path, and this app has a black-screen history (10.76.34, SIGSEGV before first
//  render). Verifying that first, alone, is the whole point. Do not add the Metal view
//  here until the launch has been confirmed on hardware.
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
//  ⚠️ SIDE EFFECT ON iPad, stated because it was NOT asked for. There is no
//  "external-display only" variant of the switch: `UIApplicationSupportsMultipleScenes`
//  is app-wide, and `project.yml` ships `TARGETED_DEVICE_FAMILY: "1,2"`. On iPad this now
//  also permits a SECOND app window (Split View / Stage Manager). I first wrote that this
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
        window = nil
    }
}

/// What the projector shows. Slice 1: the room stays dark and the instrument is named.
/// Slice 2 replaces this body with the live visual.
private struct ExternalStageView: View {
    var body: some View {
        ZStack {
            // Solid fill, not a gradient — a projector in a dark room exaggerates banding,
            // and this is also the surface a live visual will later draw over.
            EchoelTheme.bg.ignoresSafeArea()
            Text("ECHOEL")
                .font(EchoelTheme.font(28, .semibold))
                .foregroundStyle(EchoelTheme.dim)
                .accessibilityHidden(true)
        }
    }
}
#endif
