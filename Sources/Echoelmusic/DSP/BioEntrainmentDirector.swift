import Foundation

/// Biofeedback-driven brainwave-entrainment DIRECTOR — the missing "brain" that turns
/// the body's slow autonomic trends into an entrainment target for BOTH audio (the
/// existing isochronic `EchoelEntrainment` on each DDSP voice) AND the visual (a
/// flash-safe luminance pulse). Pure value logic, fully unit-testable, no audio-thread
/// or platform dependency.
///
/// Science-first, on-brand (NOT wellness/esoteric):
///  - Bands are named + specified in Hz (Delta/Theta/Alpha/Beta/Gamma via `BrainwaveBand`).
///  - The band is selected on the validated arousal→calm axis of HRV **coherence**, so the
///    stimulus follows the body's measured state — this is the "biofeedback driven" part.
///  - Depth is deliberately SUBTLE and gated by signal quality: a noisy/absent pulse lock
///    can never drive a strong stimulus (honest — we only entrain on a real signal, and we
///    claim the *stimulus*, never a guaranteed neural effect).
///  - The visual pulse is HARD-capped at 3 Hz (W3C WCAG epilepsy ceiling); higher audio
///    bands drive a musically-related sub-harmonic on screen, never an unsafe flicker.
public struct BioEntrainmentTarget: Equatable, Sendable {
    /// Audio entrainment band (isochronic AM frequency = `band.centerFrequency`).
    public var band: BrainwaveBand
    /// Isochronic depth [0…maxDepth]; 0 = no stimulus.
    public var depth: Float
    /// Flash-SAFE visual pulse rate in Hz (always ≤ 3.0). Feed to the visual pulse.
    public var visualPulseHz: Double

    /// True when the stimulus is audible/visible.
    public var isActive: Bool { depth > 0.01 }

    public init(band: BrainwaveBand, depth: Float, visualPulseHz: Double) {
        self.band = band
        self.depth = depth
        self.visualPulseHz = visualPulseHz
    }

    public static let inactive = BioEntrainmentTarget(band: .alpha, depth: 0, visualPulseHz: 0)
}

public struct BioEntrainmentDirector: Sendable {

    /// Never modulate harder than this — a subtle stimulus, not an overwhelming pulse.
    public static let maxDepth: Float = 0.6
    /// W3C WCAG epilepsy ceiling for ANY visual flicker (Hz).
    ///
    /// ⚠️ THIRD COPY of one number. The canonical declaration is `FlashGuard.maxFlashHz`;
    /// `EntrainmentEngine.maxVisualFlashHz` is the second, and its header carries the full
    /// reasoning. Short version: `FlashGuard` is in `Studio/` and this file is in `DSP/`, which
    /// is kept Foundation-only by hygiene (`project.yml`), so this one CANNOT chain even if the
    /// other two did. `Tests/CISmoke/TheFlashCeilingIsOneNumberTests` asserts all three agree —
    /// relaxing this alone turns the blocking bundle red, which is the point.
    public static let maxVisualHz: Double = 3.0
    /// Below this pulse-lock quality we emit NO stimulus (don't entrain on a bad signal).
    public static let qualityFloor: Float = 0.35

    /// When set, the user has pinned a band (manual mode). `nil` = auto (bio-selected).
    public var manualBand: BrainwaveBand?

    public init(manualBand: BrainwaveBand? = nil) { self.manualBand = manualBand }

    /// Map the slow bio trends → an entrainment target.
    /// - Parameters:
    ///   - coherence: HRV coherence [0…1]; selects the band on the arousal→calm axis in auto mode.
    ///   - quality: pulse-lock confidence [0…1]; depth scales with it (no stimulus on a bad lock).
    public func target(coherence: Float, quality: Float) -> BioEntrainmentTarget {
        let q = min(max(quality, 0), 1)
        let c = min(max(coherence, 0), 1)
        guard q >= Self.qualityFloor else { return .inactive }

        let band = manualBand ?? Self.autoBand(coherence: c)
        // Subtle by design: scale with lock quality AND coherence (settle → deeper).
        let depth = Self.maxDepth * q * (0.5 + 0.5 * c)
        return BioEntrainmentTarget(band: band,
                                    depth: min(max(depth, 0), Self.maxDepth),
                                    visualPulseHz: Self.visualHz(for: band))
    }

    /// Coherence → band on the aroused→calm axis (coherence is a validated autonomic
    /// balance measure): low = aroused/active → Beta; mid = relaxed focus → Alpha; high
    /// sustained = deeply settled → Theta. (Delta/Gamma are reserved for manual mode —
    /// deep sleep and peak cognition aren't states we auto-nudge from a live session.)
    public static func autoBand(coherence c: Float) -> BrainwaveBand {
        if c < 0.30 { return .beta }
        if c < 0.65 { return .alpha }
        return .theta
    }

    /// Fold the band centre to a flash-safe (≤3 Hz) visual pulse by halving until safe,
    /// so the on-screen pulse is a musically-related sub-harmonic of the audio band and
    /// NEVER exceeds the epilepsy ceiling. Delta 2→2, Theta 6→3, Alpha 10→2.5,
    /// Beta 20→2.5, Gamma 40→2.5.
    public static func visualHz(for band: BrainwaveBand) -> Double {
        var f = Double(band.centerFrequency)
        guard f > 0 else { return 0 }
        while f > maxVisualHz { f /= 2 }
        return f
    }
}
