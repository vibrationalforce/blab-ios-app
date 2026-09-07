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

        /// The full-intensity brightness offset for `ToneTrim` — see `toneTrim(for:intensity:)`.
        /// Carried on the contribution so a caller that stored one does not also have to keep
        /// the snapshot alive; defaulted so existing constructions (and their tests) still
        /// compile with the same meaning as before, namely no tone effect.
        public var toneBrightnessShift: Float

        /// This sky's tone offset at the given `Param.warmth` mixer intensity.
        public func toneTrim(intensity: Float) -> ToneTrim {
            WeatherMood.toneTrim(fullBrightnessShift: toneBrightnessShift, intensity: intensity)
        }

        public init(structureSalt: UInt64, darknessTarget: Float, livelinessTarget: Float,
                    tensionTarget: Float, hue: Float, saturation: Float,
                    glowTarget: Float, motionTarget: Float, descriptor: String,
                    toneBrightnessShift: Float = 0) {
            self.structureSalt = structureSalt
            self.darknessTarget = darknessTarget
            self.livelinessTarget = livelinessTarget
            self.tensionTarget = tensionTarget
            self.hue = hue
            self.saturation = saturation
            self.glowTarget = glowTarget
            self.motionTarget = motionTarget
            self.descriptor = descriptor
            self.toneBrightnessShift = toneBrightnessShift
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

    /// A bounded, RELATIVE timbre offset — the half of "Warmth" you can actually hear.
    ///
    /// ⛔ WHY THIS EXISTS, and it is a defect report about the version above it. `Param.warmth`
    /// promises "Warm weather brightens the TONE, cold darkens it". It was wired only to
    /// `MoodProfile.darkness`, and `darkness` is not a gradient anywhere in the engine — its
    /// only two readers are `mood.darkness > 0.6 ? -1 : 0` (`BioComposer`, twice: the ambient
    /// octave and the pad voicing). `MoodPreset.swift` already records this in its own comment
    /// ("Two moods can therefore differ by 0.43 of darkness and produce the SAME notes" —
    /// quoted exactly; an earlier draft tidied the sentence inside its quotation marks). So a weather
    /// nudge of a few hundredths did LITERALLY NOTHING unless it happened to cross 0.6, and
    /// then it moved a whole octave. Founder, 2026-08-01: "Wetter ist nicht bemerkbar bis
    /// jetzt oder?" — correct, and this is why.
    ///
    /// Also note what the label says: TONE, not register. The engine implemented register. This
    /// is the parameter the text was always describing.
    ///
    /// RELATIVE AND BOUNDED, for the reason `RoleRhythm.TimbreTrim` states at length: #81/#125
    /// were "every genre converges on one sound", and an absolute target per condition would
    /// rebuild that with eight targets. A brightness OFFSET and a cutoff FACTOR applied to
    /// whatever patch arrives leave every genre exactly as far apart as it was.
    public struct ToneTrim: Sendable, Equatable {
        /// Added to the patch's `brightness` (0…1) by the caller, then clamped there.
        public var brightness: Float
        /// Multiplies the patch's `filterCutoff`, then clamped there.
        public var cutoffFactor: Float

        /// The identity — what intensity 0 must return, so weather-off is bit-identical.
        public static let neutral = ToneTrim(brightness: 0, cutoffFactor: 1)

        public init(brightness: Float, cutoffFactor: Float) {
            self.brightness = brightness
            self.cutoffFactor = cutoffFactor
        }
    }

    /// The widest this trim may move at FULL intensity. Deliberately larger than
    /// `RoleRhythm.TimbreTrim`'s ±0.05 / ±12 %, and the difference is principled rather than
    /// a preference: that trim pulls every genre toward one of six per-character targets (a
    /// convergence risk, hence tiny), while this one applies the SAME relative offset to
    /// whatever is playing — genre distances are preserved by construction. It is also opt-in,
    /// per-session, and has its own fader. At the default intensity of 0.5 the reachable
    /// extremes are half of these.
    public static let maxToneBrightnessShift: Float = 0.20
    public static let maxToneCutoffDeviation: Float = 0.36

    /// Warm/clear sky → brighter and more open; cold/fog/rain → darker and softer.
    /// `intensity` is `Param.warmth`'s mixer; 0 returns `.neutral` exactly.
    ///
    /// CONTINUOUS BY CONSTRUCTION — there is no threshold anywhere in here, which is the whole
    /// point of the slice. Every 1 °C of temperature and every step of the mixer moves the
    /// sound a little, so the fader behaves like a fader.
    public static func toneTrim(for w: WeatherSnapshot, intensity: Float) -> ToneTrim {
        toneTrim(fullBrightnessShift: toneBrightnessShift(for: w), intensity: intensity)
    }

    /// The same trim from an already-computed full-intensity shift — what
    /// `Contribution.toneTrim(intensity:)` uses, so a stored contribution needs no snapshot
    /// kept alongside it. One shape function, two entry points; a second copy of the maths is
    /// how the two would drift.
    public static func toneTrim(fullBrightnessShift shift: Float, intensity: Float) -> ToneTrim {
        let i = Swift.min(Swift.max(intensity, 0), 1)
        guard i > 0, shift.isFinite else { return .neutral }
        let brightness = clampRange(shift, -maxToneBrightnessShift, maxToneBrightnessShift) * i
        // Cutoff follows brightness rather than carrying its own table: they are two views of
        // the same "how open is this" and letting them disagree is how a sound ends up bright
        // and muffled at once. 1.8 is chosen so the ±0.20 brightness bound lands ON the ±0.36
        // cutoff bound — which means this second clamp is UNREACHABLE today, by construction
        // rather than by accident. It stays because the two bounds are independent constants
        // that a later tune can move apart, and a clamp that only starts working then is
        // cheaper than a defect that only appears then. (Not "exactly": in Float,
        // `0.2 * 1.8 == 0.35999998`, a hair inside the bound. Nothing depends on the equality,
        // but the earlier wording claimed a precision this arithmetic does not have.)
        let cutoff = clampRange(1 + brightness * 1.8,
                                1 - maxToneCutoffDeviation, 1 + maxToneCutoffDeviation)
        return ToneTrim(brightness: brightness, cutoffFactor: cutoff)
    }

    /// The unscaled brightness offset for one sky, before any mixer.
    static func toneBrightnessShift(for w: WeatherSnapshot) -> Float {
        // ⛔ SANITISE THE TEMPERATURE FIRST, and the reason is that the clamp below CANNOT do
        // it. `clampRange` is `min(max(v, lo), hi)`, and Swift's `max(x, y)` is `y >= x ? y : x`
        // — so `max(+inf, 0)` returns `+inf` and `min(+inf, 1)` then returns `1`. An INFINITE
        // temperature is therefore saturated into a perfectly finite `t`, and the
        // `shift.isFinite` guard in `toneTrim(fullBrightnessShift:intensity:)` never fires: the
        // sky arrives with the MAXIMUM trim (±0.20 brightness, ×1.36 / ×0.82 cutoff) instead of
        // neutral. NaN is the only non-finite the clamp passes through, so the first version of
        // this file was NaN-safe and infinity-wrong — and its test asserted all three, which is
        // how it was caught. Note `RoleRhythm.clampRange` has the OPPOSITE argument order and
        // therefore the opposite behaviour (`+inf → upper`); the two must not be reasoned about
        // interchangeably. A non-finite reading means "no usable temperature", and the honest
        // answer to that is no tone at all — not the strongest one this table can produce.
        guard w.temperatureC.isFinite else { return 0 }

        // Temperature is the PRIMARY term because the label names it first. Linear in °C
        // between −5 and 32 rather than reusing `temperatureBand` — the bands are five steps,
        // and a five-step staircase is the same "nothing happens, then a jump" defect one size
        // smaller. `temperatureBand` stays where it is: the structure SALT wants a stable
        // bucket (same sky = same skeleton), a tone wants a slope. Two questions, two shapes.
        let t = Swift.min(Swift.max((w.temperatureC + 5) / 37, 0), 1)   // 0 at −5 °C, 1 at 32 °C
        let tempShift = Float(t - 0.5) * 0.30                           // ±0.15

        let condShift: Float
        switch w.condition {
        case .clear:        condShift = 0.05
        case .partlyCloudy: condShift = 0.0
        case .overcast:     condShift = -0.05
        case .fog:          condShift = -0.08
        case .drizzle:      condShift = -0.04
        case .rain:         condShift = -0.06
        // A storm is dark but not DULL — it has edge. Less closed than plain rain on purpose.
        case .storm:        condShift = -0.02
        case .snow:         condShift = -0.03
        }
        let night: Float = w.isDaylight ? 0 : -0.03

        return clampRange(tempShift + condShift + night,
                          -maxToneBrightnessShift, maxToneBrightnessShift)
    }

    /// The four live visual controls, in the ranges the renderer expects — the INPUT and the
    /// OUTPUT of `visualValues(base:mixers:contribution:)`. `Double` because that is what the
    /// `@AppStorage` keys hold; the mix itself narrows to `Float` inside `blend`.
    public struct VisualValues: Sendable, Equatable {
        public var hue: Double
        public var saturation: Double
        public var intensity: Double
        public var motion: Double
        public init(hue: Double, saturation: Double, intensity: Double, motion: Double) {
            self.hue = hue
            self.saturation = saturation
            self.intensity = intensity
            self.motion = motion
        }
    }

    /// Per-parameter mix strengths, 0…1. Each one is a user control
    /// (`WeatherMood.Param.<x>.mixKey`); all zero is neutral — see the note on
    /// `visualValues` for why "neutral" and "bit-identical" are not the same word here.
    public struct VisualMixers: Sendable, Equatable {
        public var hue: Double
        public var saturation: Double
        public var glow: Double
        public var movement: Double
        public init(hue: Double, saturation: Double, glow: Double, movement: Double) {
            self.hue = hue
            self.saturation = saturation
            self.glow = glow
            self.movement = movement
        }
    }

    /// The four VISUAL values with the sky mixed in — the ONE definition of that mix (#1072).
    ///
    /// ⛔ WHY THIS EXISTS: there were TWO surfaces rendering the visual and only one of them
    /// mixed. `FloatingVisualWindow.weatheredVisuals()` blended hue · saturation · intensity ·
    /// motion; `ExternalStageScene` read the same four `@AppStorage` keys and handed them to
    /// `MetalBioView` RAW, so attaching a projector silently dropped the weather tint mid-show
    /// (measured, #1071). Two spellings of one decision is the #416 defect, and this is what it
    /// looks like after a year: not a disagreement anyone can see, but a picture that changes
    /// when a cable goes in.
    ///
    /// PURE, and deliberately so. It takes the contribution rather than a provider, so it can be
    /// driven end-to-end in the blocking bundle (§1's strong kind) and so neither caller needs
    /// the other's environment. `nil` means "weather is off, or no snapshot yet" and returns
    /// `base` EXACTLY — it short-circuits before any arithmetic.
    ///
    /// ⚠️ ALL MIXERS AT 0 IS NEUTRAL BUT NOT BIT-IDENTICAL, and the difference is worth one
    /// line because a test asserted the wrong one first. That path still runs the crossfade,
    /// and `blend` works in `Float`, so a `Double` base comes back narrowed
    /// (0.20 → 0.20000000298…). Invisible in a picture, real to `XCTAssertEqual`. Not
    /// "fixed" with an all-zero short-circuit: that would change shipped behaviour to make a
    /// test prettier.
    ///
    /// ⚠️ THE MIXERS ARE PER-PARAMETER AND NOT INTERCHANGEABLE. `glow` drives INTENSITY and
    /// `movement` drives MOTION; their key names (`WeatherMood.Param.glow` / `.movement`) do not
    /// match the visual parameter names, and that mismatch is exactly the kind a second
    /// hand-written copy gets subtly wrong. Pinned per pair by
    /// `TheWeatherVisualMixHasOneDefinitionTests`.
    public static func visualValues(base: VisualValues,
                                    mixers: VisualMixers,
                                    contribution: Contribution?) -> VisualValues {
        guard let wx = contribution else { return base }
        func mix(_ b: Double, _ target: Float, _ intensity: Double) -> Double {
            Double(blend(base: Float(b), target: target, intensity: Float(intensity)))
        }
        return VisualValues(hue: mix(base.hue, wx.hue, mixers.hue),
                            saturation: mix(base.saturation, wx.saturation, mixers.saturation),
                            intensity: mix(base.intensity, wx.glowTarget, mixers.glow),
                            motion: mix(base.motion, wx.motionTarget, mixers.movement))
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
                            descriptor: descriptor,
                            toneBrightnessShift: toneBrightnessShift(for: w))
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
