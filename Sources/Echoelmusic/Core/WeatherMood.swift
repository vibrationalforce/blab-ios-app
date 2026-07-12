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

public extension WeatherSnapshot.Condition {
    /// Maps WeatherKit's `WeatherCondition.rawValue` strings onto our coarse
    /// 8-case palette. PURE (string in, case out) so Linux CI tests it without
    /// WeatherKit. Unknown raw values → nil; the provider then falls back to
    /// `.partlyCloudy` (the least-opinionated flavour) rather than guessing.
    init?(weatherKitRaw raw: String) {
        switch raw {
        case "clear", "mostlyClear", "hot":
            self = .clear
        case "partlyCloudy", "breezy", "windy":
            self = .partlyCloudy
        case "mostlyCloudy", "cloudy":
            self = .overcast
        case "foggy", "haze", "smoky":
            self = .fog
        case "drizzle", "freezingDrizzle", "sunShowers":
            self = .drizzle
        case "rain", "heavyRain", "freezingRain":
            self = .rain
        case "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms",
             "thunderstorms", "hurricane", "tropicalStorm", "hail":
            self = .storm
        case "snow", "heavySnow", "flurries", "sunFlurries", "sleet",
             "wintryMix", "blizzard", "blowingSnow", "frigid":
            self = .snow
        default:
            return nil
        }
    }
}

/// Deterministic weather → music/visual mapping. Same snapshot in, same
/// values out — reproducible like everything else in the composer.
public enum WeatherMood {

    /// What one weather situation contributes. The founder asked for the sky to
    /// touch SOUND *and* IMAGE through SEVERAL parameters, each mixable in/out on
    /// its own ("Klang und Bild aber getrennte und mehrere Parameter" +
    /// "Intensitäts-Slider damit man das Wetter rein und rausmischen kann").
    /// So this carries an ABSOLUTE target per parameter (in that parameter's own
    /// natural range); the wiring crossfades the user's base toward the target by
    /// the per-parameter intensity mixer (`blend`) — intensity 0 = no change.
    public struct Contribution: Sendable, Equatable {
        /// XOR-salt for `BioComposer.Input.structureSeed`. Stable across a
        /// weather situation (condition + daylight + temperature band), so
        /// consecutive takes under the same sky share a skeleton.
        public var structureSalt: UInt64

        // SOUND targets — in `MoodProfile` 0…1 space (the composer already
        // blends `mood` with the live body; weather blends one more step toward
        // these before that). Neutral is the user's own mood value.
        /// 0 bright/high register … 1 dark/low. Warm sky → brighter, cold → darker.
        public var darknessTarget: Float
        /// 0 sparse/still … 1 busy/active. Wind & storms → busier, calm → stiller.
        public var livelinessTarget: Float
        /// 0 friendly/consonant … 1 tense/dissonant. Storm → tense, clear → calm.
        public var tensionTarget: Float

        // VISUAL targets — in the live visual controls' ranges.
        /// Hue rotation 0…1 (wraps).
        public var hue: Float
        /// Saturation 0…2 (1 = neutral). Trübes Wetter entsättigt, klares sättigt.
        public var saturation: Float
        /// Visual intensity/glow 0…1.5 (1 = neutral). Sonne/Sturm heller, Nebel dämpft.
        public var glowTarget: Float
        /// Visual motion 0…1.5 (1 = neutral). Wind bringt Bewegung ins Bild.
        public var motionTarget: Float

        /// Short token for logs/UI, e.g. "rain-day-cold". Never marketing copy.
        public var descriptor: String

        public init(structureSalt: UInt64, darknessTarget: Float, livelinessTarget: Float,
                    tensionTarget: Float, hue: Float, saturation: Float,
                    glowTarget: Float, motionTarget: Float, descriptor: String) {
            self.structureSalt = structureSalt
            self.darknessTarget = darknessTarget
            self.livelinessTarget = livelinessTarget
            self.tensionTarget = tensionTarget
            self.hue = hue
            self.saturation = saturation
            self.glowTarget = glowTarget
            self.motionTarget = motionTarget
            self.descriptor = descriptor
        }

        /// The absolute target for one mixable parameter (nil for `.structure`,
        /// which is a discrete skeleton salt, not a crossfaded value).
        public func target(for param: Param) -> Float? {
            switch param {
            case .structure:  return nil
            case .warmth:     return darknessTarget
            case .energy:     return livelinessTarget
            case .drama:      return tensionTarget
            case .hue:        return hue
            case .saturation: return saturation
            case .glow:       return glowTarget
            case .movement:   return motionTarget
            }
        }
    }

    /// Which side of the instrument a weather parameter touches.
    public enum Domain: String, Sendable, Codable, CaseIterable {
        case sound   // "Klang"
        case visual  // "Bild"
    }

    /// One independently-mixable weather influence. Each has UI copy that says
    /// exactly what it changes (the founder's "Wetter soll kurz erklärt werden")
    /// and a persisted intensity mixer [0…1] (0 = off = bit-identical default).
    public enum Param: String, CaseIterable, Sendable, Codable, Identifiable {
        // SOUND
        case structure   // harmonic skeleton salt
        case warmth      // → darkness
        case energy      // → liveliness
        case drama       // → tension
        // VISUAL
        case hue
        case saturation
        case glow        // → visual intensity
        case movement    // → visual motion

        public var id: String { rawValue }

        public var domain: Domain {
            switch self {
            case .structure, .warmth, .energy, .drama: return .sound
            case .hue, .saturation, .glow, .movement:  return .visual
            }
        }

        /// Short human label for the mixer row.
        public var label: String {
            switch self {
            case .structure:  return "Structure"
            case .warmth:     return "Warmth"
            case .energy:     return "Energy"
            case .drama:      return "Drama"
            case .hue:        return "Hue"
            case .saturation: return "Saturation"
            case .glow:       return "Glow"
            case .movement:   return "Movement"
            }
        }

        /// One clear line: what turning this up actually does.
        public var explanation: String {
            switch self {
            case .structure:  return "Same sky keeps the same harmonic skeleton across takes."
            case .warmth:     return "Warm weather brightens the tone, cold darkens it."
            case .energy:     return "Wind and storms make the music busier, calm keeps it still."
            case .drama:      return "Storms add tension; a clear sky stays consonant."
            case .hue:        return "Shifts the colour toward the sky (rain → blue, sun → gold)."
            case .saturation: return "Dull weather drains colour; clear skies deepen it."
            case .glow:       return "Sun and storms make the image glow; fog dims it."
            case .movement:   return "Wind sets the image in motion."
            }
        }

        /// `@AppStorage` key for the persisted per-parameter intensity mixer.
        public var mixKey: String { "weather.mix.\(rawValue)" }

        /// Default mixer intensity. Weather itself is opt-in (default OFF), so the
        /// app-wide default is already bit-identical; once the founder enables
        /// weather these give it a gentle, real, mixable effect out of the box.
        /// `structure` defaults to full for back-compat (the salt always applied
        /// when weather was on before this multi-param split).
        public var defaultIntensity: Double { self == .structure ? 1.0 : 0.5 }

        /// The persisted intensity for this parameter, falling back to
        /// `defaultIntensity` when the key was never written. ONE reader shared by
        /// the mixer UI (`@AppStorage`) and the sound/visual wiring, so both agree
        /// that "unset = default" (never the raw UserDefaults 0.0, which would read
        /// as "off"). `@AppStorage` only writes once the user moves the fader, so an
        /// untouched key stays absent here.
        public func currentIntensity(_ defaults: UserDefaults = .standard) -> Float {
            guard defaults.object(forKey: mixKey) != nil else { return Float(defaultIntensity) }
            return Float(defaults.double(forKey: mixKey))
        }
    }

    /// Crossfade a base value toward `target` by `intensity` [0…1]. Intensity 0
    /// returns `base` unchanged (bit-identical); 1 returns `target`. Pure.
    public static func blend(base: Float, target: Float, intensity: Float) -> Float {
        let i = Swift.min(Swift.max(intensity, 0), 1)
        let out = base + (target - base) * i
        return out.isFinite ? out : base
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
        return Contribution(structureSalt: salt,
                            darknessTarget: darknessTarget(for: w),
                            livelinessTarget: livelinessTarget(for: w),
                            tensionTarget: tensionTarget(for: w.condition),
                            hue: hue, saturation: saturation,
                            glowTarget: glowTarget(for: w),
                            motionTarget: motionTarget(forWindKph: w.windKph),
                            descriptor: descriptor)
    }

    // MARK: Sound targets (MoodProfile 0…1 space)

    /// Warm sky → brighter (low darkness); cold → darker. Night adds a touch of
    /// darkness. Rain/overcast/fog/storm sit darker than clear skies.
    static func darknessTarget(for w: WeatherSnapshot) -> Float {
        let tempDark: Float
        switch temperatureBand(w.temperatureC) {
        case "freezing": tempDark = 0.72
        case "cold":     tempDark = 0.60
        case "mild":     tempDark = 0.48
        case "warm":     tempDark = 0.36
        default:         tempDark = 0.28   // hot
        }
        let condDark: Float
        switch w.condition {
        case .clear:        condDark = -0.06
        case .partlyCloudy: condDark = 0.0
        case .overcast:     condDark = 0.10
        case .fog:          condDark = 0.14
        case .drizzle:      condDark = 0.10
        case .rain:         condDark = 0.16
        case .storm:        condDark = 0.20
        case .snow:         condDark = 0.06
        }
        let night: Float = w.isDaylight ? 0 : 0.10
        return clamp01(tempDark + condDark + night)
    }

    /// Wind & storms → busier; calm & fog → stiller.
    static func livelinessTarget(for w: WeatherSnapshot) -> Float {
        let windLively: Float
        switch w.windKph {
        case ..<8:   windLively = 0.30
        case ..<20:  windLively = 0.45
        case ..<40:  windLively = 0.62
        default:     windLively = 0.80
        }
        let condLively: Float
        switch w.condition {
        case .storm:        condLively = 0.18
        case .rain:         condLively = 0.08
        case .drizzle:      condLively = 0.02
        case .clear:        condLively = 0.05
        case .partlyCloudy: condLively = 0.0
        case .overcast:     condLively = -0.05
        case .fog:          condLively = -0.12
        case .snow:         condLively = -0.06
        }
        return clamp01(windLively + condLively)
    }

    /// Storms are tense, clear skies calm.
    static func tensionTarget(for condition: WeatherSnapshot.Condition) -> Float {
        switch condition {
        case .clear:        return 0.22
        case .partlyCloudy: return 0.26
        case .overcast:     return 0.38
        case .fog:          return 0.32
        case .drizzle:      return 0.42
        case .rain:         return 0.50
        case .storm:        return 0.70
        case .snow:         return 0.30
        }
    }

    // MARK: Visual targets (live-control ranges)

    /// Visual intensity/glow 0…1.5 (1 = neutral). Sun/storm glow, fog/overcast dim.
    static func glowTarget(for w: WeatherSnapshot) -> Float {
        let base: Float
        switch w.condition {
        case .clear:        base = 1.28
        case .partlyCloudy: base = 1.12
        case .overcast:     base = 0.88
        case .fog:          base = 0.72
        case .drizzle:      base = 0.92
        case .rain:         base = 0.90
        case .storm:        base = 1.30
        case .snow:         base = 1.10
        }
        // Night dims everything a little (storms keep their flash).
        let night: Float = w.isDaylight ? 0 : (w.condition == .storm ? -0.05 : -0.18)
        return clampRange(base + night, 0, 1.5)
    }

    /// Visual motion 0…1.5 (1 = neutral). Driven by wind.
    static func motionTarget(forWindKph windKph: Double) -> Float {
        switch windKph {
        case ..<8:   return 0.80
        case ..<20:  return 1.05
        case ..<40:  return 1.28
        default:     return 1.45
        }
    }

    static func clamp01(_ v: Float) -> Float { clampRange(v, 0, 1) }
    static func clampRange(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        Swift.min(Swift.max(v, lo), hi)
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
