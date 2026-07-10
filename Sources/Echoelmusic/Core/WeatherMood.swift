// WeatherMood.swift
// Echoel — ecosystem plan E3a: the PURE mapping from coarse weather to
// composition/visual parameters ("Umwelt als zweite physikalische Realität",
// Masterplan §1). No WeatherKit import — E3b adapts a WeatherKit fetch into a
// `WeatherSnapshot` once the capability is enabled in the developer portal.
//
// What weather is allowed to touch (and what not):
//  • Composition: a deterministic SALT for `BioComposer.Input.structureSeed` —
//    the same weather situation keeps the same structural skeleton, so a rainy
//    afternoon session feels like ONE piece, not per-fetch jitter. The body
//    (bio) stays the primary driver; weather only flavours the skeleton.
//  • Visual: an OPT-IN palette (hue rotation + saturation) in VisualPreset's
//    existing ranges. The science-first physical-colour default is preserved —
//    wiring must never apply this without the user choosing it.
//
// Pure value logic, fully unit-tested on every platform.

import Foundation

/// Coarse, privacy-friendly weather at session start. Only what the mapping
/// needs — no location, no timestamps, nothing stored.
public struct WeatherSnapshot: Sendable, Equatable, Codable {

    public enum Condition: String, CaseIterable, Sendable, Codable {
        case clear
        case partlyCloudy
        case overcast
        case fog
        case drizzle
        case rain
        case storm
        case snow
    }

    public var temperatureC: Double
    public var condition: Condition
    public var isDaylight: Bool
    /// Wind in km/h; only coarse bands are used.
    public var windKph: Double

    public init(temperatureC: Double, condition: Condition, isDaylight: Bool, windKph: Double = 0) {
        self.temperatureC = temperatureC
        self.condition = condition
        self.isDaylight = isDaylight
        self.windKph = windKph
    }
}

/// Deterministic weather → music/visual mapping. Same snapshot in, same
/// values out — reproducible like everything else in the composer.
public enum WeatherMood {

    /// What one weather situation contributes.
    public struct Contribution: Sendable, Equatable {
        /// XOR-salt for `BioComposer.Input.structureSeed`. Stable across a
        /// weather situation (condition + daylight + temperature band), so
        /// consecutive takes under the same sky share a skeleton.
        public var structureSalt: UInt64
        /// Optional visual palette in `VisualPreset` ranges: hue rotation 0…1.
        public var hue: Float
        /// Saturation 0…2 (1 = neutral).
        public var saturation: Float
        /// Short token for logs/UI, e.g. "rain-day-cold". Never marketing copy.
        public var descriptor: String
    }

    /// Temperature band edges in °C: freezing <0, cold <10, mild <20,
    /// warm <30, hot ≥30.
    static func temperatureBand(_ c: Double) -> String {
        switch c {
        case ..<0: return "freezing"
        case ..<10: return "cold"
        case ..<20: return "mild"
        case ..<30: return "warm"
        default: return "hot"
        }
    }

    public static func contribution(for w: WeatherSnapshot) -> Contribution {
        let band = temperatureBand(w.temperatureC)
        let daypart = w.isDaylight ? "day" : "night"
        let descriptor = "\(w.condition.rawValue)-\(daypart)-\(band)"

        // FNV-1a over the descriptor — the same stable-hash approach as the
        // waveform disk-cache key (never Hasher: that is seeded per-process).
        var salt: UInt64 = 0xcbf29ce484222325
        for byte in descriptor.utf8 {
            salt ^= UInt64(byte)
            salt = salt &* 0x100000001b3
        }

        let (hue, saturation) = palette(for: w.condition, isDaylight: w.isDaylight)
        return Contribution(structureSalt: salt, hue: hue, saturation: saturation,
                            descriptor: descriptor)
    }

    /// Palette per condition — graded, never neon (UI rules). Values live in
    /// VisualPreset's ranges (hue 0…1, saturation 0…2).
    static func palette(for condition: WeatherSnapshot.Condition,
                        isDaylight: Bool) -> (hue: Float, saturation: Float) {
        switch condition {
        case .clear:
            return isDaylight ? (0.12, 1.10) : (0.62, 1.00)   // warm gold / deep night blue
        case .partlyCloudy:
            return isDaylight ? (0.10, 1.00) : (0.60, 0.95)
        case .overcast:
            return (0.08, 0.80)                                // muted, low-chroma
        case .fog:
            return (0.00, 0.60)                                // near-monochrome
        case .drizzle:
            return (0.55, 0.85)
        case .rain:
            return (0.55, 0.95)                                // blue-grey
        case .storm:
            return (0.72, 1.10)                                // violet slate
        case .snow:
            return (0.50, 0.85)                                // icy cyan, soft
        }
    }
}
