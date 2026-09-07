//
//  ExternalStageBridge.swift
//  Echoelmusic — Studio
//
//  THE ONE HAND-OFF between the App's `@State` engine objects and a scene that UIKit
//  creates (#206 slice 2).
//
//  WHY IT HAS TO EXIST. `MetalBioView` reads three `@Environment` objects — `EngineBus`,
//  `ResourceGovernor`, `VisualRecorder`. Those live as `@State` on the `App` struct and
//  reach the phone's views through `.environment(...)` on the `WindowGroup`'s content.
//  The external window is built by `ExternalDisplaySceneDelegate` with its own
//  `UIHostingController`, which is NOT inside that hierarchy and inherits nothing — a
//  `MetalBioView` mounted there would trap on the first missing environment value. There
//  is no iOS API for a SwiftUI-declared external-display scene, so the delegate is not a
//  choice, and neither is this bridge.
//
//  ⚠️ THIS IS A SINGLETON, WHICH THIS CODEBASE OTHERWISE AVOIDS. It is deliberately the
//  NARROWEST possible one, and the test for "narrow" is NOT the member count — it is
//  whether a member is something the external scene genuinely cannot reach any other way.
//  Every phone-side view keeps using `@Environment`: no phone-side view reads
//  `bus`/`governor`/`recorder`, the phone reads ONLY `isConnected` — `FloatingVisualWindow`
//  to yield the GPU, and since #1044 `EchoelStudioView` to hold the screen awake while the
//  beamer has the picture. An earlier version of this line claimed "nothing on the phone
//  path reads this type at all" — false, and it was the dangerous kind of false: it is the
//  sentence a future session would read as permission to change `isConnected` freely.
//
//  ⛔ AND THE COUNT IN THAT SENTENCE WENT STALE TWICE, WHICH IS WHY IT IS GONE. It said
//  "three optional references … do not add a fourth thing here because it is convenient"
//  while FOUR already existed: `synth` arrived with #594 slice 2 for exactly the class of
//  problem the warning was meant to prevent ("beamer tint parity"), and #1073 makes it
//  five for the same reason. A rule stated as a NUMBER expires the first time someone
//  obeys its purpose; the rule is the QUESTION instead, and it has a real answer here.
//  Ask it every time:
//
//    Can the scene get this any other way? — No. UIKit builds this hierarchy; it inherits
//    no `@Environment`, and `WeatherSnapshot` is never persisted, so there is nothing to
//    read back. (`WeatherProvider` itself is NOT carried, deliberately: it lives inside
//    `#if canImport(WeatherKit) && canImport(CoreLocation)`, so a member of that type
//    would give `wire(...)` two platform-dependent signatures. A pure VALUE crosses for
//    free.)
//    Is it a VALUE or an ENGINE OBJECT? — `sky` is a value: `Sendable`, `Equatable`,
//    Foundation-only, no behaviour. That is the cheap kind; a fifth engine object would
//    not have passed.
//
//  If a future member cannot answer both, it does not belong here. That is the doctrine
//  the number was standing in for.
//
//  THE GPU LAW IT ALSO CARRIES. decisions.csv 2026-07-03: "Visual black-screen (two live
//  MetalBioViews) fixed by mutual exclusion — GPU rule = ONE MetalBioView app-wide". A
//  second renderer on the external screen would re-create exactly that, so `isConnected`
//  exists for the phone side to yield its floating window while the beamer has the
//  picture. That is not a compromise, it IS the founder's ask: "das Bild für die visuals
//  für einen anderen Bildschirm … es soll trotzdem vom iPhone aus spielbar sein" — the
//  phone keeps the instrument, the beamer takes the image.
//
//  FREEZE LAW: `isConnected` flips on a cable/AirPlay connect, i.e. seconds apart at
//  worst, never at frame or bio rate. Reading it in an ancestor body is safe in a way a
//  10 Hz bio read never is. Nothing else here is observable.
//

import Foundation
import Observation

#if canImport(UIKit)

/// Publishes the shared engine objects to the external-display scene, and the fact that
/// such a scene exists back to the phone UI.
///
/// INTERNAL, not `public` — and that is a compile requirement, not taste: `VisualRecorder`
/// is internal, so a `public` property or method carrying it is the hard error CLAUDE.md's
/// table already names ("`public let foo: InternalType` — match access levels"). All four
/// reference sites are in-module.
@MainActor
@Observable
final class ExternalStageBridge {

    static let shared = ExternalStageBridge()

    /// True while an external screen has a live window. Drives the phone's floating
    /// visual out of the way so only ONE `MetalBioView` renders at a time.
    private(set) var isConnected = false

    /// The engine objects the external `MetalBioView` needs.
    ///
    /// These are deliberately OBSERVED, not `@ObservationIgnored`. A projector plugged
    /// in BEFORE the app is launched is the normal stage order, and in that order the
    /// scene connects while the startup task is still running — so the external view
    /// evaluates its body with all of them still nil. If they were ignored, that view
    /// would sit on the ECHOEL wordmark for the whole show with no way back. Observed,
    /// `wire(...)` re-renders it into the live visual. Nothing on the PHONE path reads
    /// these, so the observation costs no rebuild anywhere else, and they are written
    /// exactly once per launch — this is not a churn source.
    private(set) var bus: EngineBus?
    private(set) var governor: ResourceGovernor?
    private(set) var recorder: VisualRecorder?
    /// #594 slice 2 (beamer tint parity): the voice the phone tints its palette
    /// from. Same observed-not-ignored rationale as its three siblings; unlike
    /// them it is handed to the scene OUTSIDE the `if let` render gate (via the
    /// optional `.environment` overload) — a missing synth dims the tint, it must
    /// never black out the stage.
    private(set) var synth: PolySynthVoice?

    /// #1073 — THE SKY, so the beamer can draw the phone's picture instead of a raw one.
    ///
    /// ⛔ WHY THIS EXISTS AS A VALUE AND NOT AS THE PROVIDER. `#1071` measured the gap: the
    /// phone mixes the weather into hue · saturation · intensity · motion, the external scene
    /// rendered the same four `@AppStorage` keys RAW, so plugging in a projector silently
    /// dropped the tint mid-show. `#1072` gave the mix ONE definition
    /// (`WeatherMood.visualValues`); this is the last thing the scene was missing in order to
    /// call it. Carrying `WeatherProvider` instead would drag `#if canImport(WeatherKit)` into
    /// this file and split `wire(...)` in two — see the doctrine note at the top.
    ///
    /// ⚠️ LIFETIME IS THE POINT, and it is why the writer is `FloatingVisualWindow` and not
    /// the one line in `EchoelStudioView` where a contribution already happens to sit. That
    /// one is written only when a session STARTS with a location fix; the window computes the
    /// sky live from the 30-minute cache, which is what the phone's own tint follows. A beamer
    /// tinted for a different hour than the phone is the same defect as one that does not tint
    /// at all — and it would be visible only with a projector attached, i.e. never in CI.
    ///
    /// Observed like its siblings (a projector plugged in before launch is the normal stage
    /// order). It changes about twice an hour, so the 10.76.41/50 freeze law is untouched:
    /// this is nowhere near a bio- or frame-rate source.
    private(set) var sky: WeatherMood.Contribution?

    private init() {}

    /// Called once from the app's startup task, before any screen can connect.
    /// Idempotent — a second call (a second scene re-running startup would be a bug the
    /// `startupDone` latch already prevents) simply rewrites the same references.
    func wire(bus: EngineBus, governor: ResourceGovernor, recorder: VisualRecorder, synth: PolySynthVoice) {
        self.bus = bus
        self.governor = governor
        self.recorder = recorder
        self.synth = synth
    }

    // NO `canRenderVisual` convenience here, deliberately. It existed, had zero callers,
    // and its doc claimed the scene delegate consulted it — which it never did. The real
    // guard is the `if let` in `ExternalStageView.body`, and that one is strictly better
    // because it BINDS the values it checks: a separate boolean invites a future session
    // to trust the flag and drop the binding, which is exactly how a trapped
    // `@Environment` lookup would reach a stage.

    /// Scene lifecycle, called only by `ExternalDisplaySceneDelegate`.
    func setConnected(_ connected: Bool) { isConnected = connected }

    /// The current sky, pushed by `FloatingVisualWindow` whenever its own tint would change
    /// (#1073). Separate from `wire(...)` on purpose: that one runs once per launch, this one
    /// tracks a value that moves — folding them together would make the once-per-launch
    /// contract of `wire` untrue.
    func setSky(_ contribution: WeatherMood.Contribution?) { sky = contribution }
}

#endif
