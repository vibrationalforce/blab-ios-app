//
//  ResourceGovernor.swift
//  Echoelmusic — the runtime that feeds live device pressure into AdaptiveQuality.
//
//  Reads the OS signals the pure `AdaptiveQuality` policy needs — thermal state,
//  Low Power Mode, battery level/charging — plus a smoothed measured render FPS from
//  the visual, and republishes a single `QualitySettings` the whole app observes.
//  Subsystems (MetalBioView frame rate / detail, spectral donuts, bio & OSC poll
//  rates) read `.settings` so resource conservation is decided in ONE place.
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

    public init() {
        readDeviceState()
        observeNotifications()
        recompute()
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
        guard dt > 0, dt < 1 else { return }   // ignore stalls / first frame
        let instantaneous = 1.0 / dt
        // Exponential smoothing (~1 s time constant at 60 fps).
        smoothedFPS = smoothedFPS == 0 ? instantaneous
                                       : smoothedFPS * 0.95 + instantaneous * 0.05
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
        let next: QualitySettings
        if isAutomatic {
            next = AdaptiveQuality.settings(thermal: thermal, lowPower: lowPower,
                                            batteryLevel: batteryLevel, charging: charging,
                                            measuredFPS: smoothedFPS)
        } else {
            next = AdaptiveQuality.settings(for: manualTier)
        }
        if next != settings {
            settings = next
            log.log(.info, category: .system,
                    "ResourceGovernor → \(next.tier.label) (fps target \(next.targetFPS), detail \(next.visualDetailScale))")
        }
    }
}
