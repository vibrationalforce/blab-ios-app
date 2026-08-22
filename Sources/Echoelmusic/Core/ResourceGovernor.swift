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
//      they are the reason this is NOT a drive-by. ⛔ THE OLD REASON GIVEN HERE IS
//      OUT OF DATE and is corrected rather than deleted, because it argued the wrong
//      way round: it said both slew per TICK, so capping their 30 Hz to 10 Hz would
//      stretch a fade threefold. Since #372 the step is derived from
//      `FlashGuard.senderTickMilliseconds`, so lowering the rate THROUGH that constant
//      keeps the fade DURATION and simply sends fewer, larger steps. The real cost of
//      throttling them is therefore fade SMOOTHNESS (visible banding on a slow fade),
//      not fade length — still show-visible, still the founder's call, but a different
//      trade-off than the one written here for a month.
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

    /// Whether automatic governing is on.
    ///
    /// ⛔ THIS LINE SAID a performer "can pin a tier (e.g. force High for a show)" AND NO
    /// PERFORMER CAN (#727). Measured in `Sources/`, comments stripped (`git grep` it):
    /// `isAutomatic` occurs THREE times — this declaration, its own `didSet`, and the `guard`
    /// in `recompute()`. No writer, no binding, no control in any shipped code path.
    ///
    /// ⚠️ AND THE CONSEQUENCE IS ONE STEP FURTHER THAN A MISSING SWITCH: because no shipped
    /// path sets the flag `false`, the `guard isAutomatic else { apply(…manualTier) }` branch
    /// in `recompute()` never runs there, so `manualTier` — whose only read lives inside it —
    /// cannot affect the app. Two `public var`s that read as the manual-override half of this
    /// class, and that half is unreachable from the product.
    ///
    /// ⛔ THE FIRST VERSION OF THIS BLOCK SAID "no writer", "permanently `true`" and "can
    /// never affect anything either" — UNSCOPED CONCLUSIONS drawn from a correctly scoped
    /// measurement (#728). There IS one writer:
    /// `Tests/EchoelmusicTests/PollingLoopTests.testResourceGovernor_publishesTheCeilingForAPinnedTier`
    /// pins `isAutomatic = false` and steps `manualTier` precisely so its `bioHz` assertion is
    /// device-independent. So the branch is not dead code — it is the only way to drive this
    /// class deterministically, and it is exercised. ⚠️ That suite is compiled by NO gate
    /// (#208), which is why nothing here turns red when it breaks — a reason to state the
    /// writer, not to ignore it.
    ///
    /// ⭐ THE AUTOMATIC HALF IS LIVE AND UNAFFECTED. `EchoelmusicApp` constructs the governor,
    /// `MetalBioView` reads it via `@Environment`, `ExternalStageBridge` wires it, and its
    /// `bioHz` output drives `OSCSender`'s egress ceiling. Nothing here is dead code in the
    /// sense of "delete it" — what is absent is the DOOR, and the sentence that promised one.
    ///
    /// ⚠️ WHETHER A PERFORMER SHOULD BE ABLE TO PIN A TIER IS A FOUNDER QUESTION, not a
    /// cleanup. Pinning High for a show is a real live-performance need, and the machinery is
    /// two lines from working; this note exists so that question gets asked from facts rather
    /// than from a doc comment that already claims the answer. Guard:
    /// `Tests/CISmoke/TheQualityPinHasNoDoorTests.swift` — it forbids building one (#364).
    public var isAutomatic: Bool = true {
        didSet { recompute() }
    }

    /// The tier used when `isAutomatic == false` — i.e. never, until that flag gets a writer.
    /// See the ⛔ block above; this property's only read is inside the unreachable branch.
    public var manualTier: QualityTier = .balanced {
        didSet { if !isAutomatic { recompute() } }
    }

    // Live device readings (mirrored so recompute is cheap & testable).
    @ObservationIgnored private var thermal: ThermalLevel = .nominal
    @ObservationIgnored private var lowPower: Bool = false
    @ObservationIgnored private var batteryLevel: Float = -1
    @ObservationIgnored private var charging: Bool = false

    @ObservationIgnored private var lastFrameTime: CFTimeInterval = 0

    /// #271 — THE ONLY FPS READING A TIER DECISION EVER SEES. Stays exactly `0` until the
    /// warm-up below has completed, which is the value `AdaptiveQuality.settings(…
    /// measuredFPS:)` already documents as "no reading yet, ignore me". Every path into
    /// `recompute()` — the thermal and battery notifications included, which never touch
    /// `recordFrame` — therefore reads a number that is either trustworthy or absent.
    ///
    /// Why it exists (founder device log 2478, v10.79.361): the estimate used to be SEEDED
    /// FROM A SINGLE FRAME (`smoothedFPS == 0 ? instantaneous : …`), so the very first
    /// measured interval of the app's life WAS the whole estimate. A demotion then applies
    /// IMMEDIATELY (asymmetric hysteresis, by design), while recovery needs a wider band
    /// plus a 4 s dwell. In the founder's log: `redMot=1 detail=0.50` at 27 s and 32 s,
    /// back to `redMot=0 detail=0.70` at 37 s — the immersive visual sat frozen, which is
    /// the report "motion is tied to whether the visual window is open; it should run when
    /// you turn it on".
    ///
    /// ⛔ FOUR THINGS THE FIRST VERSION OF THIS COMMENT CLAIMED THAT ARE FALSE (count the
    /// bullets, not the last numeral — this file's own house rule) — kept with
    /// their refutation, because a wrong reason is worse than none (a later session cannot
    /// disprove it):
    /// · "every time it was switched on". The governor is ONE app-lifetime instance
    ///   (`EchoelmusicApp.swift:177`, a single `@State`), so the cold seed could only ever
    ///   happen ONCE PER LAUNCH. A remount fed the surviving EMA at 5 % weight, so ONE slow
    ///   frame moved a 60 fps estimate to 57.2 — nowhere near the 45 fps demotion floor.
    ///   That matters: it is why a stall must NOT reset the warm-up (see `recordFrame`).
    /// · "MetalBioView compiles its shader at runtime [during that frame]". True as a
    ///   standalone fact, irrelevant here — `configure(device:)` runs from `makeUIView`,
    ///   synchronously, before the delegate ever draws. What IS inside the measured
    ///   interval is the forced first drawable allocation and the synchronous present.
    /// · "the slowest frame the renderer will ever produce". Never measured — an assertion
    ///   dressed as a fact. What is provable is only that ONE interval decided a tier.
    /// · "about ten seconds". The diag line is 5 s periodic, so the log brackets the freeze
    ///   between 5 and 15 s and cannot pin it closer.
    ///
    /// Readable (not writable) outside the type on purpose: on CI hardware a tier change is
    /// UNOBSERVABLE — `init` leaves `settings` at `.balanced` while the pressure tier is
    /// `.high` (the promotion dwell returns before `apply`), so a one-tier demotion lands
    /// back on `.balanced` and `apply`'s `next != settings` guard swallows it. Tests that
    /// assert on `settings.tier` therefore pass with or without this mechanism; they assert
    /// on this value instead.
    @ObservationIgnored private(set) var trustedFPS: Double = 0
    /// Measured intervals seen since launch, capped at the warm-up length.
    @ObservationIgnored private var warmupFramesSeen = 0
    /// Sum of the warm-up window's instantaneous rates — averaged, never EMA-seeded, so no
    /// single interval can carry more than 1/30 of the first decision.
    @ObservationIgnored private var warmupFPSSum: Double = 0
    /// How many measured intervals a renderer must deliver before its FPS may move a tier.
    ///
    /// ⛔ The first version said "short enough that a genuinely overloaded GPU is still
    /// caught within a second" — inverted. 30 frames is one second only AT 30 fps; the
    /// slower the renderer, the LONGER the gate takes (3 s at 10 fps, 7.5 s at 4 fps). The
    /// honest statement is the other one: it costs a struggling device a few seconds of
    /// full detail once per launch, and buys that no single interval can demote it.
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
        guard lastFrameTime > 0 else { lastFrameTime = timestamp; return }
        let dt = timestamp - lastFrameTime
        lastFrameTime = timestamp
        // A gap this long is not a slow frame, it is an UNMEASURABLE one: the window was
        // hidden, the app was backgrounded, the scene changed. Drop the sample and keep
        // everything else.
        //
        // ⛔ THE FIRST #271 FIX RESTARTED THE WARM-UP HERE, AND THAT WAS A REGRESSION —
        // found in review, before the founder ever saw it. Any renderer that stalls MORE
        // OFTEN THAN ONCE PER 30 MEASURED FRAMES then never completes the gate, `trustedFPS`
        // stays 0 forever, and the FPS feedback is silenced permanently — on exactly the
        // struggling device it exists for (4 fps with a 1.2 s hitch every 20 frames: the
        // pre-#271 code demoted, the "fixed" code never would). It was also fixing a problem
        // that does not exist: a remount is not a cold start, because the governor is one
        // app-lifetime instance whose EMA survives and only moves 5 % per frame.
        guard dt > 0, dt < 1 else { return }
        let instantaneous = 1.0 / dt
        if warmupFramesSeen < Self.fpsWarmupFrames {
            // #271 — WARM-UP. The old code made the FIRST measured interval the entire
            // estimate; here the first 30 are averaged, so the cold one weighs 1/30 and
            // `trustedFPS` stays 0 (which `AdaptiveQuality` already documents as "no
            // reading yet") until there is something to trust.
            warmupFPSSum += instantaneous
            warmupFramesSeen += 1
            guard warmupFramesSeen >= Self.fpsWarmupFrames else { return }
            trustedFPS = warmupFPSSum / Double(Self.fpsWarmupFrames)
        } else {
            // Exponential smoothing (~1 s time constant at 60 fps).
            trustedFPS = trustedFPS * 0.95 + instantaneous * 0.05
        }
        // Only recompute if the smoothed FPS would change the demotion decision.
        let target = Double(settings.targetFPS)
        let nearFloor = trustedFPS < target * 0.75
        // Wider recovery band (0.95, was 0.90) + a per-tier DWELL so the FPS feedback
        // can't oscillate the tier on a device hovering near a boundary — that flapping
        // visibly jumps detail + frame rate mid-session ("Visuals nicht stabil"). Thermal/
        // battery changes still apply immediately via refresh()/recompute() (not gated).
        let recovered = trustedFPS > target * 0.95
        guard nearFloor || (recovered && settings.tier < pressureTier) else { return }
        guard timestamp - lastFpsTierChangeAt >= Self.tierDwellSeconds else { return }
        let before = settings.tier
        recompute()
        if settings.tier != before { lastFpsTierChangeAt = timestamp }
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
        // `trustedFPS` is 0 until the renderer has proven a rate over a warm-up window
        // (#271) — and `AdaptiveQuality` reads 0 as "no measurement", so this path is
        // pressure-only until then. That is what keeps the thermal/battery notifications,
        // which never pass through `recordFrame`, from deciding on a cold reading.
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
