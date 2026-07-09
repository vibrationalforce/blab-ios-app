//
//  AdaptiveQuality.swift
//  Echoelmusic — battery / CPU / GPU resource-conservation core.
//
//  Pure, deterministic mapping from device pressure signals (thermal state, Low
//  Power Mode, battery level/charging, and the measured render FPS) to a concrete
//  set of quality knobs the rest of the app honours: the visual frame rate and
//  detail, whether the (expensive) spectral donuts render, and the bio/OSC poll
//  rates. No UIKit, no Foundation device APIs — so it unit-tests on Linux. The
//  runtime `ResourceGovernor` reads the OS signals and feeds them through here.
//
//  Design intent (founder, 2026-06-23): "Baue das System für Akku, CPU, GPU für
//  Ressourcenschonungen ein. Adaptive Qualität und Formate." Visuals get the most
//  headroom so everything stays ruckelfrei: when the device heats up or the battery
//  runs low we step the GPU load down *before* the OS throttles us, and step back
//  up only when it's safe (charging + cool).
//

import Foundation

/// Device thermal pressure, abstracted from `ProcessInfo.ThermalState` so the
/// mapping is testable without Foundation's device APIs.
public enum ThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3
    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The four operating tiers, coldest/most-capable last. `Comparable` so callers can
/// clamp with `min`/`max`.
public enum QualityTier: Int, Codable, Sendable, Comparable, CaseIterable {
    /// Survival mode — thermal critical or near-empty battery on the move.
    case minimal = 0
    /// Conserving — Low Power Mode, warm device, or low battery.
    case low = 1
    /// The default everyday tier.
    case balanced = 2
    /// Full fidelity — charging and cool.
    case high = 3

    public static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short human label for the UI / VoiceOver.
    public var label: String {
        switch self {
        case .minimal:  return "Power Saver"
        case .low:      return "Efficient"
        case .balanced: return "Balanced"
        case .high:     return "High Fidelity"
        }
    }
}

/// Concrete, app-wide quality knobs for one tier. Every subsystem reads from here
/// rather than inventing its own thresholds.
public struct QualitySettings: Sendable, Equatable {
    public var tier: QualityTier
    /// Preferred render frame rate for the Metal visual (MTKView.preferredFramesPerSecond).
    public var targetFPS: Int
    /// Multiplier on visual detail (ring density / particle counts). 0.5…1.0.
    public var visualDetailScale: Float
    /// Whether the expensive spectral-donut overlay may render.
    public var allowSpectralDonuts: Bool
    /// Bio snapshot poll rate (Hz) for UI/visual consumers.
    public var bioHz: Double
    /// OSC / network emit rate (Hz).
    public var oscHz: Double
    /// Force a still visual (no animation) — true only at the minimal tier.
    public var reduceMotion: Bool

    public init(tier: QualityTier, targetFPS: Int, visualDetailScale: Float,
                allowSpectralDonuts: Bool, bioHz: Double, oscHz: Double,
                reduceMotion: Bool) {
        self.tier = tier
        self.targetFPS = targetFPS
        self.visualDetailScale = visualDetailScale
        self.allowSpectralDonuts = allowSpectralDonuts
        self.bioHz = bioHz
        self.oscHz = oscHz
        self.reduceMotion = reduceMotion
    }
}

/// The pure resource-conservation policy. All decisions live here so they can be
/// reasoned about and unit-tested in isolation.
public enum AdaptiveQuality {

    /// Fixed knob set for a tier. Visuals scale hardest; bio/OSC degrade gently so
    /// the instrument stays responsive even in Power Saver.
    public static func settings(for tier: QualityTier) -> QualitySettings {
        switch tier {
        case .minimal:
            return QualitySettings(tier: .minimal, targetFPS: 24, visualDetailScale: 0.5,
                                   allowSpectralDonuts: false, bioHz: 5, oscHz: 10,
                                   reduceMotion: true)
        case .low:
            return QualitySettings(tier: .low, targetFPS: 30, visualDetailScale: 0.7,
                                   allowSpectralDonuts: false, bioHz: 10, oscHz: 15,
                                   reduceMotion: false)
        case .balanced:
            return QualitySettings(tier: .balanced, targetFPS: 60, visualDetailScale: 1.0,
                                   allowSpectralDonuts: true, bioHz: 10, oscHz: 30,
                                   reduceMotion: false)
        case .high:
            // targetFPS is 60, not 120: the visual display frame rate is pinned at 60
            // in MetalBioView (a stable CADisplayLink = no cadence flicker), and 60 fps
            // is the temperature-friendly ceiling. The `high` tier still earns its keep
            // via full detail + the faster bio/OSC poll rates. (A 120-target here would
            // also make the pinned-60 display read as "missing target" and spuriously
            // demote via the measured-FPS feedback.)
            return QualitySettings(tier: .high, targetFPS: 60, visualDetailScale: 1.0,
                                   allowSpectralDonuts: true, bioHz: 15, oscHz: 60,
                                   reduceMotion: false)
        }
    }

    /// Choose a tier from the device signals alone (before any FPS feedback).
    ///
    /// - Parameters:
    ///   - thermal: current thermal pressure.
    ///   - lowPower: iOS Low Power Mode enabled.
    ///   - batteryLevel: 0…1, or a negative value if unknown (e.g. plugged Mac/sim).
    ///   - charging: whether the device is charging / on external power.
    public static func tier(thermal: ThermalLevel, lowPower: Bool,
                            batteryLevel: Float, charging: Bool) -> QualityTier {
        // 1) Hard ceiling imposed by the worst active constraint.
        var ceiling: QualityTier = .high
        switch thermal {
        case .nominal:  break
        case .fair:     ceiling = Swift.min(ceiling, .balanced)
        case .serious:  ceiling = Swift.min(ceiling, .low)
        case .critical: ceiling = Swift.min(ceiling, .minimal)
        }
        if lowPower { ceiling = Swift.min(ceiling, .low) }
        if batteryLevel >= 0 && !charging {
            if batteryLevel < 0.10 { ceiling = Swift.min(ceiling, .minimal) }
            else if batteryLevel < 0.20 { ceiling = Swift.min(ceiling, .low) }
        }

        // 2) Aim for balanced by default; only reach for high when it's clearly safe
        //    (charging AND cool AND not on a critically low battery reading).
        var chosen: QualityTier = .balanced
        let batteryOK = batteryLevel < 0 || batteryLevel >= 0.30
        if charging && thermal == .nominal && batteryOK {
            chosen = .high
        }

        // 3) Never exceed the ceiling.
        return Swift.min(chosen, ceiling)
    }

    /// Full decision including measured-FPS feedback: if the renderer is missing its
    /// target by a wide margin we demote one extra tier (the GPU is the bottleneck,
    /// not the policy). `measuredFPS <= 0` means "no reading yet" and is ignored.
    public static func settings(thermal: ThermalLevel, lowPower: Bool,
                                batteryLevel: Float, charging: Bool,
                                measuredFPS: Double) -> QualitySettings {
        var t = tier(thermal: thermal, lowPower: lowPower,
                     batteryLevel: batteryLevel, charging: charging)
        if measuredFPS > 0 {
            let target = Double(settings(for: t).targetFPS)
            // Sustained < 75% of target → the device can't keep up; back off once.
            if measuredFPS < target * 0.75, t > .minimal,
               let lower = QualityTier(rawValue: t.rawValue - 1) {
                t = lower
            }
        }
        return settings(for: t)
    }
}
