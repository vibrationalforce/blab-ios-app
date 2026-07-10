import Foundation

/// A capability the UI may ask permission for before presenting it.
///
/// Free vs. Pro split (founder decision 2026-07-10): the core instrument is
/// complete and free; Echoel Pro is a ONE-TIME unlock for extensions only.
public enum ProFeature: String, CaseIterable, Sendable {
    // MARK: Pro-gated extensions
    /// Video/audio export format presets (4K, aspect ratios) — Stage F.
    case exportFormatPresets
    /// AUv3 generator plugin inside host DAWs.
    case auv3Plugin
    /// Extended engine/FX preset packs beyond the built-in set.
    case extendedPresetPacks
    /// Video FX catalog.
    case videoFXCatalog

    // MARK: Never gated (core instrument)
    /// Bio measurement (HealthKit, BLE, rPPG) — never gated.
    case bioMeasurement
    /// Sound generation, composition, performance — never gated.
    case soundGeneration
    /// Safety features (flash limits, warnings, feedback guard) — never gated.
    case safety
    /// Accessibility (VoiceOver, contrast, alternatives) — never gated.
    case accessibility
}

/// Pure free/Pro policy — no StoreKit, fully testable on any platform.
///
/// The ONLY source of truth for what Echoel Pro unlocks. UI asks
/// `ProGate.isUnlocked(_:proPurchased:)`; the purchase state comes from
/// `EchoelStore.isProUnlocked` (StoreKit 2 entitlement).
public enum ProGate {

    /// The single non-consumable product. One purchase, forever.
    /// (Replaces the pre-2026-07-10 subscription IDs — Echoel is an
    /// instrument, not a subscription.)
    public static let productID = "com.echoelmusic.app.pro"

    /// Features unlocked by the one-time Echoel Pro purchase.
    public static let proFeatures: Set<ProFeature> = [
        .exportFormatPresets,
        .auv3Plugin,
        .extendedPresetPacks,
        .videoFXCatalog
    ]

    /// Core capabilities that are free forever, purchase or not.
    /// Bio, sound, safety and accessibility are NEVER gated.
    public static let alwaysFree: Set<ProFeature> = [
        .bioMeasurement,
        .soundGeneration,
        .safety,
        .accessibility
    ]

    /// Whether `feature` is usable given the current purchase state.
    public static func isUnlocked(_ feature: ProFeature, proPurchased: Bool) -> Bool {
        if alwaysFree.contains(feature) { return true }
        return proPurchased
    }
}
