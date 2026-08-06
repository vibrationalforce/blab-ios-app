//
//  ModulationMatrix.swift
//  Echoelmusic — Core control-plane modulation routing
//
//  A freely-routable mapping layer: any biofeedback source can drive any
//  destination parameter. Each route is either
//
//    • LIVE   — the source modulates the destination continuously, or
//    • HOLD   — a value was captured and now stays on the destination,
//               either rigidly (drift = 0) or lightly modulated around
//               the captured value by the (still-moving) source.
//
//  This is the generalization the owner specified (2026-05-31):
//  "frei wählbar, welche Parameter von den Biofeedbackdaten moduliert
//   werden. Echtzeit gekoppelt, oder ein gefangener Wert bleibt starr
//   oder leicht moduliert auf dem Parameter."
//
//  v0 scope: pure, Codable value types + a deterministic evaluation
//  function. No audio/UI wiring yet — this is the tested skeleton other
//  cycles route into (synth params, sequencer, OSC out). All outputs are
//  normalized [0..1]; consumers scale to their own parameter range.
//
//  Pure value types only — safe to evaluate anywhere, including off the
//  audio thread by a control-plane subscriber.
//

import Foundation

// MARK: - Source

/// A biofeedback channel that can modulate a parameter. Each case maps to
/// one field of `BioSampleFrame` and carries the natural range used to
/// normalize that field into [0..1].
public enum ModSource: String, Codable, Sendable, CaseIterable {
    case heartRate
    case hrv
    case breathRate
    case breathPhase
    case coherence
    case motion
    // Additive facial-EXPRESSION sources (2026-07-18). Movement/expression used
    // as a CONTROL signal, NEVER an inferred emotion (see FaceExpressionMapping).
    // Appended at the END so existing rawValue/CaseIterable ordering and any
    // persisted routes decode unchanged.
    case faceSmile
    case faceBrow
    case faceJaw

    /// Human label for the "bind this parameter to the body" UI (the one shared
    /// source vocabulary — see BoundParameter / the modulation matrix).
    public var displayName: String {
        switch self {
        case .heartRate:   return "Heartbeat"
        case .hrv:         return "HRV"
        case .breathRate:  return "Breath rate"
        case .breathPhase: return "Breath"
        case .coherence:   return "Coherence"
        case .motion:      return "Motion"
        case .faceSmile:   return "Smile"
        case .faceBrow:    return "Brow"
        case .faceJaw:     return "Jaw"
        }
    }

    /// Natural input range of the raw field, used for [0..1] normalization.
    ///
    /// ⭐ THIS IS A SCALING RANGE, NOT A VALIDITY TEST. `isMeasured` decides whether a
    /// channel carries a reading; this decides how much of a route's depth a given
    /// reading spends. A value outside it is not rejected — it SATURATES, which is a
    /// different failure and a quieter one.
    ///
    /// ⭐ BREATH'S LOW BOUND IS THE GATE'S LOW BOUND, DELIBERATELY (#429). It was `4`,
    /// copied from `RespirationEstimator.minRate` — and that file and the `isMeasured`
    /// doc below both named it as the last live instance of that copy. The set of values
    /// that can EVER reach `normalizedValue` on a GATED route is exactly
    /// `BioSampleFrame.plausibleBreathRate` (`3...40`), because `isMeasured` drops everything
    /// else. (Three of the six consumers gate — the FX, FX-bio and visual paths. `output(for:
    /// frame:)` below and `BoundParameter.resolved` do NOT; see the KNOWN, DEFERRED note at
    /// `output`. It changes nothing here: outside `3...40` both the old and the new scale go
    /// negative or past 1 and `clamp01` flattens them identically, so an ungated consumer sees
    /// bit-identical values. Post-#429 it gets strictly better — a 3.5/min breather and the
    /// `breathRate: 0` "no respiration" sentinel used to be the same number.)
    /// So a scale starting at 4 left `[3, 4)` admitted-and-dead: a slow breather the
    /// gate called a measurement spent exactly zero depth, indistinguishable from a body
    /// that is not breathing. Chaining to the GATE closes that and mints no new constant;
    /// chaining to `reportableRange` (3.7736…) would have minted a fifth respiration number
    /// and still left `[3, 3.7736)` dead — HealthKit forwards whatever the watch reports,
    /// it is not bounded by our camera estimator.
    ///
    /// ⚠️ THE TOP IS NOT WIDENED TO MATCH, AND THAT ASYMMETRY IS THE DECISION, NOT AN
    /// OVERSIGHT. The gate admits to 40; above 30 this scale saturates at 1.0 and stays
    /// there. Widening to `3...40` costs **27% of travel at every rate** (10/37, a constant
    /// ratio) — in absolute terms 0.090 at 12/min, 0.170 at 20/min, and a maximum of 0.270
    /// at 30/min. It squeezes every rate a seated performer actually breathes at, to give
    /// resolution to panting. Saturating above 30 at full depth is a bounded answer.
    /// If you widen the top, delete this paragraph in the same commit or it becomes a lie.
    /// (⛔ This said "0.27 of travel at 20/min" for one commit. 0.27 is the RELATIVE loss,
    /// which is the same at every rate, and the ABSOLUTE loss at 30/min; at 20/min it is
    /// 0.170. One number wearing two units, pinned to the wrong rate, in four places.)
    ///
    /// ⚠️ IT MOVES SHIPPED ARITHMETIC, AND HERE IS THE SIZE OF IT: `(v−3)/27` against
    /// `(v−4)/26`. The shift is +0.037037 at 4/min and falls monotonically to EXACTLY zero
    /// at 30 (and above — both scales clamp). 6/min 0.0769 → 0.1111, 12/min 0.3077 → 0.3333,
    /// 20/min 0.6154 → 0.6296. It moves in the direction the product wants: the HRV-resonance
    /// band (~4.5–6/min, what `BreathPacer` paces and `BioScienceInfo` cites) sat in the
    /// bottom 8% of every breath route and gains +44% of travel at 6/min, +189% at 4.5 —
    /// one number would understate it at one end and overstate it at the other.
    ///
    /// ⛔ AND HERE IS WHO HEARS IT, because the first version of this paragraph said "no
    /// SHIPPED route binds `.breathRate` — the enum case appears only in this file's own
    /// switches — so nothing a user hears today changes", and BOTH halves were false. The
    /// chain: `hasProducer` returns `true` for `.breathRate` → `FXModCarrier.allChoices`
    /// (`FXModulation.swift`) is `ModSource.allCases.filter(\.hasProducer)` → the live
    /// carrier `Picker` in `EchoelFXView` offers **"Breath rate"** → `FXModulation
    /// .contributions` calls `normalizedValue` on it. There is a `switch` on `ModSource`
    /// in `FXModulation.swift` too. What IS true, and it is weaker: `FXBioModulator.routes`
    /// is in-memory only — no preset, store or default carries an `[FXModRoute]` — so no
    /// PERSISTED route is silently re-mapped and nothing is bound out of the box. A route
    /// the user builds in-session does change. **An audibility claim is the one a future
    /// session trusts when deciding whether a range change is safe; do not write one from
    /// a grep of this file alone.**
    ///
    /// ⚠️ WHAT THIS DOES NOT FIX, so the next session does not read it as fixed: the scale
    /// is LINEAR over a 10× span, and rate is perceived roughly logarithmically, so the
    /// resonance band still occupies a small slice of it. That is deliberately NOT solved
    /// by bending this range, because a per-route stage for exactly this already exists —
    /// `ModRoute.curve` runs AFTER normalization and `ResponseCurve.logarithmic` (√x)
    /// expands the bottom. Baking a curve into the range would apply it to every route
    /// whether or not that route wants it, and would double up on the routes that do. (It
    /// is user-facing on the bio-mod routes today; `ModRoute`'s own UI is #136.)
    public var range: ClosedRange<Float> {
        switch self {
        case .heartRate:   return 40...200
        case .breathRate:  return 3...30
        case .hrv, .breathPhase, .coherence, .motion,
             .faceSmile, .faceBrow, .faceJaw: return 0...1
        }
    }

    /// The raw field value for this source from a bio frame.
    public func rawValue(from frame: BioSampleFrame) -> Float {
        switch self {
        case .heartRate:   return frame.heartRateBPM
        case .hrv:         return frame.hrvNormalized
        case .breathRate:  return frame.breathRate
        case .breathPhase: return frame.breathPhase
        case .coherence:   return frame.coherence
        case .motion:      return frame.motionEnergy
        case .faceSmile:   return frame.faceSmile
        case .faceBrow:    return frame.faceBrowRaise
        case .faceJaw:     return frame.faceJawOpen
        }
    }

    /// The source value normalized into [0..1] using `range`.
    public func normalizedValue(from frame: BioSampleFrame) -> Float {
        ModulationMatrix.normalize(rawValue(from: frame), in: range)
    }

    /// Whether this channel was actually MEASURED in `frame`.
    ///
    /// `normalizedValue` cannot express this — it returns a clamped [0..1] number in
    /// which 0 means both "the bottom of the scale" and "nobody read this". A frame
    /// can be present, fresh and perfectly usable and still carry nothing on a given
    /// channel. The live case is `coherence`, which every source without beat-to-beat RR
    /// publishes as 0 — `HealthKitBioPublisher` does so explicitly — and `hrvNormalized`,
    /// 0 until a source produces real HRV. `FaceExpressionBioPublisher` is the mirror
    /// image (a `.faceCam` frame carries no pulse at all), but it is not yet reachable:
    /// the class compiles and nothing starts it, so that half is a guard for when it is
    /// wired, not a defect anyone has heard.
    ///
    /// It matters most for BIPOLAR routes, which map signal 0 to a FULL NEGATIVE
    /// excursion (`(0·2−1)·depth·span·0.5`): without this gate, a bipolar route on a
    /// channel the body never reported applies a permanent maximal offset — a
    /// coherence→cutoff route on HealthKit muffles the instrument for the whole
    /// session, off nothing.
    ///
    /// UNIPOLAR routes are unaffected on every channel whose sentinel normalizes to 0
    /// (heart rate, HRV, coherence, motion, face) — there `signal·depth·span` is already
    /// 0, so skipping is identical. BREATH is the exception, because its gate reads a
    /// different field than its value: HealthKit with no respiration publishes
    /// `breathRate: 0` but `breathPhase: 0.5` (the engine placeholder), so a unipolar
    /// breath-phase route WAS contributing half-depth off a placeholder and now
    /// contributes nothing. That is a real behaviour change, and the intended one.
    ///
    /// Agrees with `BioModulationMap.isMeasured` (the display-side gate) on the four
    /// channels they share — heart rate, HRV, coherence, breath. It is a SECOND,
    /// independent switch, not a shared implementation, and nothing tests that the two
    /// stay aligned: if you change either, change both. The HOIST this note asked for is
    /// done for the two channels that have one — `hasMeasuredHeartRate` and
    /// `hasMeasuredBreath` on `BioSampleFrame` — and deliberately NOT for `hrv`/`coherence`:
    /// their gate is a bare sentinel on the field itself, and a named property would only
    /// restate the field name. Motion and the three face channels exist only here.
    ///
    /// Breath is the channel whose gate reads a DIFFERENT field than its value:
    /// `breathPhase` has no unknown sentinel (0 is a real position, exhale start), so
    /// both breath sources ride `BioSampleFrame.hasMeasuredBreath`, which gates on
    /// `breathRate`. That band (`3...40`) and `ModSource.breathRate.range` (`3...30`) now
    /// share a LOW bound, which is the point of #429: a 3.5/min resonance breather used to
    /// pass this gate and still normalize to exactly 0 — the same full excursion, surviving
    /// INSIDE the gate. They still differ at the TOP (40 vs 30) and that half is deliberate;
    /// the reason is written at `range`. Saturating above 30 is a bounded answer, spending
    /// zero depth below 4 was not.
    ///
    /// The face channels gate on PROVENANCE rather than a sentinel, because a tracked,
    /// genuinely neutral face reads 0 and must stay a reading — widen this if a future
    /// publisher ever carries pulse and expression in one frame (coexistence is
    /// deferred today).
    public func isMeasured(in frame: BioSampleFrame) -> Bool {
        switch self {
        case .heartRate:   return frame.hasMeasuredHeartRate
        case .hrv:         return frame.hrvNormalized > 0
        case .coherence:   return frame.coherence > 0
        case .breathRate, .breathPhase: return frame.hasMeasuredBreath
        case .faceSmile, .faceBrow, .faceJaw: return frame.source == .faceCam
        // Motion has NO producer: all six `BioSampleFrame` construction sites in
        // `Sources/` hardcode `motionEnergy: 0`, and the last CoreMotion provider was
        // removed in the 2026-06-19 cleanup. So nothing measures it, and `false` is the
        // literal truth rather than a policy.
        //
        // When a CoreMotion source returns, gate this on THAT source's provenance (as
        // the face channels do) — do NOT write `motionEnergy > 0`. Unlike HRV and
        // coherence, motion has no documented sentinel: 0 is a real reading ("perfectly
        // still"). A value gate would drop a motionless performer's routes and make a
        // bipolar route discontinuous at the origin — 1e-7 gives −½·depth·span while
        // 0.0 gives nothing, a full-depth jump between adjacent samples.
        case .motion:      return false
        }
    }

    /// Whether ANY publisher in this build can ever put a value on this channel.
    ///
    /// This is a STRUCTURAL question and `isMeasured` is a per-frame one. `isMeasured`
    /// answers "is this reading real right now" — it needs a frame and it flips as the
    /// body comes and goes. `hasProducer` answers "could this channel ever be anything
    /// but zero", and it is a fact about the codebase, not about the moment. A picker
    /// must filter on THIS one: offering a channel whose answer is permanently no is a
    /// control that lies, and the user has no way to tell it apart from a body that has
    /// not settled yet.
    ///
    /// Keep it in step with the two producers:
    /// - `.motion` — every `BioSampleFrame` construction site in `Sources/` hardcodes
    ///   `motionEnergy: 0`; the last CoreMotion provider went in the 2026-06-19 cleanup.
    /// - the three face channels — `FaceExpressionBioPublisher` exists and is complete,
    ///   but has ZERO instantiations in `Sources/` (it is behind `FeatureFlags
    ///   .cameraExpression`, and its front-camera permission string is founder-gated,
    ///   #67/#68). The day it is constructed, flip these to `true` in the same commit.
    public var hasProducer: Bool {
        switch self {
        case .heartRate, .hrv, .coherence, .breathRate, .breathPhase: return true
        case .motion, .faceSmile, .faceBrow, .faceJaw: return false
        }
    }
}

// MARK: - Destination

/// An opaque, normalized destination parameter key, resolved by whatever
/// consumer owns the parameter (e.g. "synth.cutoff", "tempo", "voice.brightness",
/// "seq.track.0.gate"). Keeping it a string keeps the matrix decoupled from
/// any concrete parameter enum.
public struct ModDestination: Codable, Sendable, Hashable {
    public let key: String
    public init(_ key: String) { self.key = key }
}

// MARK: - Mode

/// How a route maps its source onto its destination.
public enum ModMode: Codable, Sendable, Equatable {
    /// Continuous real-time coupling: destination tracks the source.
    case live
    /// Latched: hold `value` ([0..1]). `drift` ([0..1]) is the amount of
    /// light bipolar modulation applied around the held value by the
    /// (still-moving) source — `drift == 0` is fully rigid.
    case hold(value: Float, drift: Float)
}

// MARK: - Route

/// One source → destination mapping with shaping.
public struct ModRoute: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var source: ModSource
    public var destination: ModDestination
    public var mode: ModMode
    /// Output amount, [0..1]. Scales the final normalized value.
    public var depth: Float
    /// Invert the response (1 - value) before the curve and depth are applied.
    public var invert: Bool
    /// Whether this route currently contributes output.
    public var enabled: Bool
    /// Response shaping applied to the [0..1] value (after invert, before
    /// depth) — pick `.logarithmic` for pitch-like targets, `.exponential`
    /// for loudness-like ones (research §A2). Defaults to `.linear` (identity)
    /// so existing routes and persisted data behave exactly as before.
    public var curve: ResponseCurve
    /// When true, this route only contributes when the bio frame's source is
    /// trustworthy for HRV (a BLE chest strap — `BioSource.providesTrustedHRV`).
    /// Set it on HRV-driven routes so they go silent on wrist/camera/Watch
    /// sources instead of modulating off an unreliable estimate (research §A1).
    /// Defaults to `false`: existing routes never gate.
    public var requiresTrustedSource: Bool
    /// One-pole smoothing time constant in seconds, applied by the stateful
    /// `ModulationEngine` to this route's output (NOT by the pure matrix). 0 =
    /// no smoothing (instant). Use ~0.1–0.3 s for fast targets (filter/bright),
    /// ~0.5–2 s for slow ones (coherence/HRV) to avoid zipper/jumps (research
    /// §A2). Defaults to `0`: existing routes are unsmoothed exactly as before.
    public var smoothingTau: Float

    /// Input SENSITIVITY window (AU2 — "Bio fühlt sich zu neutral an"): bio
    /// operating ranges are narrow (coherence typically lives in ~[0.3,0.6]), so
    /// a full-range destination driven by the raw value only moves a fraction and
    /// feels flat. The source's normalized value is remapped
    /// `[inputLow…inputHigh] → [0…1]` BEFORE invert/curve/depth, so a route can
    /// span its destination from the body's ACTUAL operating range. Defaults
    /// `inputLow=0, inputHigh=1` = identity (existing routes + persisted data
    /// behave EXACTLY as before). A non-positive width falls back to identity
    /// (never divides by zero). Both clamped into [0,1].
    /// NOTE (.hold mode): the window is applied to the FINAL base — including a
    /// latched/held value — so a value captured at e.g. 0.45 under a [0.3,0.6]
    /// window emits 0.5 (the destination always sees windowed output). This is
    /// intentional (the meter/param is consistent with `.live`); it means a held
    /// value is scaled, not reproduced literally.
    public var inputLow: Float
    public var inputHigh: Float

    public init(
        id: UUID = UUID(),
        source: ModSource,
        destination: ModDestination,
        mode: ModMode = .live,
        depth: Float = 1.0,
        invert: Bool = false,
        enabled: Bool = true,
        curve: ResponseCurve = .linear,
        requiresTrustedSource: Bool = false,
        smoothingTau: Float = 0,
        inputLow: Float = 0,
        inputHigh: Float = 1
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.mode = mode
        self.depth = depth
        self.invert = invert
        self.enabled = enabled
        self.curve = curve
        self.requiresTrustedSource = requiresTrustedSource
        self.smoothingTau = Swift.max(0, smoothingTau)
        self.inputLow = ModulationMatrix.clamp01(inputLow)
        self.inputHigh = ModulationMatrix.clamp01(inputHigh)
    }

    /// Remap `v` through the sensitivity window `[inputLow, inputHigh] → [0,1]`.
    /// A non-positive width is identity (guards divide-by-zero); result clamped.
    /// With the identity window (0…1) this returns `clamp01(v)` unchanged — the
    /// golden-gate for every pre-AU2 route.
    func windowed(_ v: Float) -> Float {
        guard inputHigh > inputLow else { return ModulationMatrix.clamp01(v) }
        return ModulationMatrix.clamp01((v - inputLow) / (inputHigh - inputLow))
    }

    // Custom Codable so older persisted routes (missing newer keys) still
    // decode with safe defaults. encode(to:) stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case id, source, destination, mode, depth, invert, enabled, curve, requiresTrustedSource, smoothingTau, inputLow, inputHigh
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` and the behaviour/shaping fields have NEUTRAL defaults, so a renamed
        // or removed key degrades that ONE field (never throws the route away). But
        // `source`/`destination` are the route's IDENTITY with no neutral default —
        // a route with no source, or one whose ModSource/ModDestination case was
        // retired, is meaningless. They stay REQUIRED so an undecodable one throws
        // and `ModulationMatrix`'s lossy array drops JUST that route (keeping every
        // other route) instead of fabricating a ghost route onto a default source.
        // (Previously the first 7 fields were all naked `try decode` — a rename of
        // any one silently vaporized the user's whole modulation matrix.)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try c.decode(ModSource.self, forKey: .source)
        destination = try c.decode(ModDestination.self, forKey: .destination)
        mode = try c.decodeIfPresent(ModMode.self, forKey: .mode) ?? .live
        depth = try c.decodeIfPresent(Float.self, forKey: .depth) ?? 1.0
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        curve = try c.decodeIfPresent(ResponseCurve.self, forKey: .curve) ?? .linear
        requiresTrustedSource = try c.decodeIfPresent(Bool.self, forKey: .requiresTrustedSource) ?? false
        smoothingTau = try c.decodeIfPresent(Float.self, forKey: .smoothingTau) ?? 0
        inputLow = ModulationMatrix.clamp01(try c.decodeIfPresent(Float.self, forKey: .inputLow) ?? 0)
        inputHigh = ModulationMatrix.clamp01(try c.decodeIfPresent(Float.self, forKey: .inputHigh) ?? 1)
    }

    /// Returns a copy of this route latched to the source's current value
    /// from `frame`, with the given `drift` (0 = rigid). Implements the
    /// owner's "capture a value, then hold it" action.
    public func captured(from frame: BioSampleFrame, drift: Float = 0) -> ModRoute {
        var copy = self
        copy.mode = .hold(
            value: source.normalizedValue(from: frame),
            drift: ModulationMatrix.clamp01(drift)
        )
        return copy
    }
}

// MARK: - Matrix

/// An ordered collection of routes plus the pure evaluation logic.
public struct ModulationMatrix: Codable, Sendable, Equatable {

    public var routes: [ModRoute]

    public init(routes: [ModRoute] = []) {
        self.routes = routes
    }

    // Custom decode so a SINGLE corrupt route — a retired ModSource/ModDestination
    // enum case, on-disk corruption, or a source/destination key rename — drops
    // only THAT route instead of throwing, which would make `ModulationEngine.load`
    // (a guarded `try?`) discard the user's ENTIRE bio→parameter routing table.
    // `encode(to:)` stays synthesized; the single key matches the property name so
    // existing persisted matrices round-trip byte-for-byte.
    private enum CodingKeys: String, CodingKey { case routes }
    private struct LossyRoute: Decodable {
        let route: ModRoute?
        init(from decoder: Decoder) throws { route = try? ModRoute(from: decoder) }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let wrapped = try? c.decodeIfPresent([LossyRoute].self, forKey: .routes)
        routes = (wrapped ?? []).compactMap { $0.route }
    }

    // MARK: Evaluation (pure)

    /// Normalized [0..1] output for one route given a bio frame.
    /// Disabled routes return 0. Deterministic and side-effect free.
    ///
    /// KNOWN, DEFERRED: this evaluator is NOT gated on `ModSource.isMeasured` the way the
    /// FX and visual paths are, and two of its branches carry the same defect. With an
    /// unmeasured channel (`live == 0`), `invert: true` yields `depth` — the destination
    /// pinned at MAXIMUM, permanently, the mirror of the bipolar slam. `.hold` computes
    /// `held + drift·(live−0.5)·2`, i.e. `held − drift`, which is the bipolar form
    /// outright. Left alone on purpose: `ModRoute` has no construction site in `Sources/`
    /// and nothing in the UI sets `invert`, so both are reachable only from persisted
    /// data, and gating here would change the semantics of the general matrix for every
    /// consumer at once. Gate it in the same slice that gives `ModRoute` a real UI.
    public static func output(for route: ModRoute, frame: BioSampleFrame) -> Float {
        guard route.enabled else { return 0 }
        // HRV-trust gate: a strap-only route stays silent on weak sources.
        if route.requiresTrustedSource && !frame.source.providesTrustedHRV { return 0 }

        let live = route.source.normalizedValue(from: frame)
        let base: Float
        switch route.mode {
        case .live:
            base = live
        case .hold(let held, let drift):
            // Bipolar light modulation around the held value:
            // (live - 0.5) maps [0..1] → [-0.5..0.5]; ×2 → [-1..1]; ×drift scales.
            base = clamp01(held + drift * (live - 0.5) * 2)
        }

        // AU2 sensitivity: expand the body's actual operating range to full
        // scale BEFORE invert/curve/depth (identity for pre-AU2 routes).
        let windowed = route.windowed(base)
        let inverted = route.invert ? (1 - windowed) : windowed
        let shaped = route.curve.apply(inverted)
        return clamp01(shaped * clamp01(route.depth))
    }

    /// Evaluates every route against `frame`, returning the summed,
    /// clamped [0..1] output per destination. Multiple routes onto the
    /// same destination are additive (then clamped).
    public func evaluate(_ frame: BioSampleFrame) -> [ModDestination: Float] {
        var result: [ModDestination: Float] = [:]
        for route in routes {
            let out = Self.output(for: route, frame: frame)
            guard out > 0 else { continue }
            result[route.destination, default: 0] = Self.clamp01((result[route.destination] ?? 0) + out)
        }
        return result
    }

    // MARK: Helpers

    /// Linear normalize `v` from `range` into [0..1]. Degenerate ranges → 0.
    public static func normalize(_ v: Float, in range: ClosedRange<Float>) -> Float {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return clamp01((v - range.lowerBound) / span)
    }

    public static func clamp01(_ v: Float) -> Float {
        if v.isNaN { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }
}
