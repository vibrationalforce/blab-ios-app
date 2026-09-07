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
//  NARROWEST possible one: three optional references, written exactly once from the
//  startup task, and read only by the external scene. It is NOT a general service
//  locator — do not add a fourth thing here because it is convenient. Every phone-side
//  view keeps using `@Environment`: no phone-side view reads `bus`/`governor`/`recorder`,
//  the phone reads ONLY `isConnected` — `FloatingVisualWindow` to yield the GPU, and since
//  #1044 `EchoelStudioView` to hold the screen awake while the beamer has the picture. An
//  earlier version of this line claimed "nothing on the phone path reads this type at
//  all" — false, and it was the dangerous kind of false: it is the sentence a future
//  session would read as permission to change `isConnected` freely.
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
}

#endif
