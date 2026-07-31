//
//  ResourceGovernor.swift
//  Echoelmusic — the runtime that feeds live device pressure into AdaptiveQuality.
//
//  Reads the OS signals the pure `AdaptiveQuality` policy needs — thermal state,
//  Low Power Mode, battery level/charging — plus a smoothed measured render FPS from
//  the visual, and republishes a single `QualitySettings` the whole app observes.
//  Resource conservation is decided in ONE place.
//
//  WHO ACTUALLY HONOURS WHICH KNOB (kept honest deliberately — the old header
//  listed four consumers, three of which did not exist):
//    · `visualDetailScale` + `reduceMotion` → MetalBioView.draw(in:).
//    · `bioHz` → `OSCSender`'s bio-egress loop, via `PollingRateCeiling`. The other
//      four 10 Hz control-plane loops are NOT opted in yet, each for a stated reason:
//      `ModulationEngine` hardcodes `tickSeconds = 0.1` as the dt of its own
//      smoothing filter, so slowing its loop without also measuring dt would silently
//      double every route's time constant; `BioReactiveSynthVoice` and
//      `PolySynthVoice` feed the synth and are held until the v10.79.354 limiter is
//      device-auditioned; `SessionEngine` is dormant (nothing presents SessionView).
//    · `targetFPS` → NOBODY, on purpose: reassigning MTKView.preferredFramesPerSecond
//      reconfigures the CADisplayLink, a visible cadence hitch (see MetalBioView).
//      It survives only as the reference the FPS-feedback demotion compares against.
//    · `oscHz` → nobody yet, and mind the naming trap: the ONE governed egress loop
//      is `OSCSender`'s, and it is governed by `bioHz`, because what it emits is a
//      bio poll. The genuine unconsumed candidate for `oscHz` is `ADMOSCSender`'s
//      20 Hz object-out, which the minimal tier's 10 Hz would actually halve.
//      Art-Net/sACN are the other two rate-capping candidates (not OSC at all), and
//      they are the reason this is NOT a drive-by: both slew per TICK
//      (`FlashGuard.slewedDimmer`, maxDelta per call), so capping their 30 Hz to
//      10 Hz stretches a lighting fade threefold — show-visible, founder's call.
//    · `allowSpectralDonuts` → nobody; `SpectralDonutView` has no reachable door.
//
//  @MainActor @Observable: it is pure control-plane state read by SwiftUI. It never
//  touches the audio thread. Updates are event-driven (thermal/power notifications)
//  plus a low rate FPS feed-in with hysteresis, so it costs almost nothing.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
public final class ResourceGovernor {

    /// The current app-wide quality knobs. Observe this.
    public private(set) var settings: QualitySettings =
        AdaptiveQuality.settings(for: .balanced)

    /// Whether automatic governing is on. When off, `settings` is held at
    /// `manualTier` so a performer can pin a tier (e.g. force High for a show).
    public var isAutomatic: Bool = true {
        didSet { recompute() }
    }

    /// The tier used when `isAutomatic == false`.
    public var manualTier: QualityTier = .balanced {
        didSet { if !isAutomatic { recompute() } }
    }

    // Live device readings (mirrored so recompute is cheap & testable).
    @ObservationIgnored private var thermal: ThermalLevel = .nominal
    @ObservationIgnored private var lowPower: Bool = false
    @ObservationIgnored private var batteryLevel: Float = -1
    @ObservationIgnored private var charging: Bool = false

    // Smoothed FPS feedback from the renderer.
    @ObservationIgnored private var smoothedFPS: Double = 0
    @ObservationIgnored private var lastFrameTime: CFTimeInterval = 0

    /// #271 — THE FPS READING A TIER DECISION IS ALLOWED TO SEE. Separate from the raw
    /// EMA on purpose: `0` means "no trustworthy reading yet", which is exactly the value
    /// `AdaptiveQuality.settings(…measuredFPS:)` already documents as "ignore me".
    ///
    /// Why it exists (founder device log 2478, v10.79.361): the raw EMA is SEEDED FROM A
    /// SINGLE FRAME (`smoothedFPS == 0 ? instantaneous : …`). The first frame after a mount
    /// is the slowest one the renderer will ever produce — `MetalBioView` compiles its
    /// shader at runtime and waits on the first drawable — so that one frame became the
    /// whole estimate. A demotion then applies IMMEDIATELY (asymmetric hysteresis, by
    /// design), while recovery needs a wider band plus a 4 s dwell. Net effect on the
    /// founder's device: `redMot=1 detail=0.50` at 27 s and 32 s, back to `redMot=0
    /// detail=0.70` at 37 s — the immersive visual sat FROZEN for about ten seconds every
    /// time it was switched on, which is precisely the report "motion is tied to whether
    /// the visual window is open; it should run when you turn it on".
    @ObservationIgnored private var trustedFPS: Double = 0
    /// Valid frames counted since the last cold start or stall.
    @ObservationIgnored private var framesSinceDiscontinuity = 0
    /// How many consecutive good frames a renderer must deliver before its FPS may move a
    /// tier. 30 frames is half a second at the pinned 60 fps — long enough that a
    /// shader-compile stall or a first-drawable wait cannot decide anything, short enough
    /// that a genuinely overloaded GPU is still caught within a second.
    private static let fpsWarmupFrames = 30

    public init() {
        readDeviceState()
        observeNotifications()
        recompute()
        // `recompute()` can return WITHOUT calling `apply` (the promotion-dwell path:
        // a charging, cool device wants `.high` immediately but must prove it for
        // 6 s). Publish the ceiling that is actually in force either way, so the
        // holder is never left at its uncapped launch default by that path.
        PollingRateCeiling.setBioHz(settings.bioHz)
    }

    // MARK: - Device state

    private func readDeviceState() {
        // Thermal + Low Power Mode are Apple-only (swift-corelibs-foundation on Linux
        // has neither); on other platforms we stay nominal / on-power.
        #if canImport(Darwin)
        let info = ProcessInfo.processInfo
        lowPower = info.isLowPowerModeEnabled
        thermal = Self.map(info.thermalState)
        #else
        lowPower = false
        thermal = .nominal
        #endif
        #if canImport(UIKit) && os(iOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        batteryLevel = device.batteryLevel          // -1 when unknown
        switch device.batteryState {
        case .charging, .full: charging = true
        default:               charging = false
        }
        #else
        batteryLevel = -1
        charging = true   // desktop/sim/Linux: treat as on external power
        #endif
    }

    #if canImport(Darwin)
    private static func map(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal:  return .nominal
        case .fair:     return .fair
        case .serious:  return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }
    #endif

    private func observeNotifications() {
        let nc = NotificationCenter.default
        #if canImport(Darwin)
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        #endif
        #if canImport(UIKit) && os(iOS)
        nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        #endif
    }

    /// Re-read the device and recompute (called on every relevant notification).
    public func refresh() {
        readDeviceState()
        recompute()
    }

    // MARK: - FPS feedback

    /// Feed one frame's timestamp from the visual's draw loop. Maintains a smoothed
    /// FPS estimate; a sustained drop demotes a tier on the next recompute. Cheap:
    /// only recomputes settings when the smoothed value crosses a threshold.
    public func recordFrame(timestamp: CFTimeInterval) {
        guard lastFrameTime > 0 else { beginWarmup(at: timestamp); return }
        let dt = timestamp - lastFrameTime
        lastFrameTime = timestamp
        // A stall is a DISCONTINUITY, not a slow frame: the window was hidden, the app was
        // backgrounded, the scene changed. Restart the warm-up rather than resuming an
        // estimate that describes a renderer which no longer exists. (Before #271 this
        // branch only skipped the sample, so the frames right after a remount — the slow
        // ones — went straight into a decision.)
        guard dt > 0, dt < 1 else { beginWarmup(at: timestamp); return }
        let instantaneous = 1.0 / dt
        // Exponential smoothing (~1 s time constant at 60 fps).
        smoothedFPS = smoothedFPS == 0 ? instantaneous
                                       : smoothedFPS * 0.95 + instantaneous * 0.05
        framesSinceDiscontinuity += 1
        // #271 — WARM-UP GATE. Until the renderer has delivered enough consecutive frames,
        // its FPS is not evidence of anything and `trustedFPS` stays 0, which
        // `AdaptiveQuality` already treats as "no reading yet". Without this, the single
        // slowest frame of the whole session (the first one after a mount) WAS the estimate.
        guard framesSinceDiscontinuity >= Self.fpsWarmupFrames else { return }
        trustedFPS = smoothedFPS
        // Only recompute if the smoothed FPS would change the demotion decision.
        let target = Double(settings.targetFPS)
        let nearFloor = smoothedFPS < target * 0.75
        // Wider recovery band (0.95, was 0.90) + a per-tier DWELL so the FPS feedback
        // can't oscillate the tier on a device hovering near a boundary — that flapping
        // visibly jumps detail + frame rate mid-session ("Visuals nicht stabil"). Thermal/
        // battery changes still apply immediately via refresh()/recompute() (not gated).
        let recovered = smoothedFPS > target * 0.95
        guard nearFloor || (recovered && settings.tier < pressureTier) else { return }
        guard timestamp - lastFpsTierChangeAt >= Self.tierDwellSeconds else { return }
        let before = settings.tier
        recompute()
        if settings.tier != before { lastFpsTierChangeAt = timestamp }
    }

    /// Drop every FPS reading and start counting again. Called for a cold start AND for a
    /// stall, because both mean the same thing: whatever comes next is a renderer warming
    /// up, and the numbers it produces while doing so describe the warm-up, not the device.
    ///
    /// `trustedFPS` is cleared too — otherwise a thermal or battery notification arriving
    /// mid-warm-up would call `recompute()` and demote on a reading this method just
    /// declared untrustworthy. That path does not go through `recordFrame` at all, which is
    /// why gating only the call site would not have been enough.
    private func beginWarmup(at timestamp: CFTimeInterval) {
        lastFrameTime = timestamp
        framesSinceDiscontinuity = 0
        smoothedFPS = 0
        trustedFPS = 0
    }

    /// Minimum seconds between FPS-feedback-driven tier changes — stops boundary flapping.
    private static let tierDwellSeconds: CFTimeInterval = 4
    @ObservationIgnored private var lastFpsTierChangeAt: CFTimeInterval = 0

    /// The tier the device pressure alone would pick (ignores FPS) — used to know if
    /// the renderer has headroom to recover after an FPS-driven demotion.
    private var pressureTier: QualityTier {
        AdaptiveQuality.tier(thermal: thermal, lowPower: lowPower,
                             batteryLevel: batteryLevel, charging: charging)
    }

    // MARK: - Recompute

    private func recompute() {
        guard isAutomatic else {
            apply(AdaptiveQuality.settings(for: manualTier))   // pinned: immediate, no dwell
            return
        }
        // `trustedFPS`, not the raw EMA (#271): 0 until the renderer has proven a rate.
        let raw = AdaptiveQuality.settings(thermal: thermal, lowPower: lowPower,
                                           batteryLevel: batteryLevel, charging: charging,
                                           measuredFPS: trustedFPS)
        // ASYMMETRIC HYSTERESIS (founder "Visuals Zucken noch"). A DEMOTION (more
        // conservative) applies immediately — if the device is stressed, back off now.
        // A PROMOTION (more expensive: higher targetFPS/detail) must PERSIST for
        // promoteDwellSeconds before we adopt it. Without this, a charging device warming
        // and cooling across the nominal↔fair thermal boundary flapped the tier, which
        // rewrote MTKView.preferredFramesPerSecond (120↔60) and reconfigured the
        // CADisplayLink — a visible frame-pacing hitch. The renderer's easing is already
        // frame-rate-independent, so holding a stable FPS costs nothing visually.
        if raw.tier > settings.tier {
            let now = CFAbsoluteTimeGetCurrent()
            if pendingPromoteTier != raw.tier {
                pendingPromoteTier = raw.tier
                pendingPromoteSince = now
            }
            guard now - pendingPromoteSince >= Self.promoteDwellSeconds else {
                return   // hold the current tier until the better condition proves stable
            }
            pendingPromoteTier = nil
        } else {
            pendingPromoteTier = nil   // demotion / no change → clear any pending promotion
        }
        apply(raw)
    }

    /// Minimum seconds a better (more expensive) tier must persist before it's adopted.
    private static let promoteDwellSeconds: CFTimeInterval = 6
    @ObservationIgnored private var pendingPromoteTier: QualityTier?
    @ObservationIgnored private var pendingPromoteSince: CFTimeInterval = 0

    private func apply(_ next: QualitySettings) {
        // Belt-and-braces with the unconditional publish at the end of `init()`: since
        // `settings` is written ONLY here, the ceiling cannot go stale even behind the
        // guard. Placed before it anyway so the invariant survives `apply` ever gaining
        // a second caller — the class of drift this whole slice exists to end.
        PollingRateCeiling.setBioHz(next.bioHz)
        guard next != settings else { return }
        settings = next
        // `fps ref`, not `fps target`: nothing reassigns MTKView.preferredFramesPerSecond
        // (see the knob table above). Logged because it is the value the FPS-feedback
        // demotion measures against — reading it as an applied setting is the trap.
        log.log(.info, category: .system,
                "ResourceGovernor → \(next.tier.label) (fps ref \(next.targetFPS), detail \(next.visualDetailScale))")
    }
}
