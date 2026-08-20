//
//  FXModulation.swift
//  Echoelmusic — bio-reactive FX modulation core.
//
//  The Echoel thesis applied to effects: the body (and free LFOs) continuously
//  sculpt the EchoelFX chain — coherence opening a reverb, the breath sweeping a
//  filter, the heartbeat driving a tremolo. This is the PURE, deterministic core
//  (routes + the value mapping); the control-rate `FXBioModulator` reads the bio
//  snapshot at ~30 Hz and writes the results to the live chain, and the FX view
//  edits the routes. No audio-thread work here — value types only, Linux-testable.
//
//  Reuses `ModSource` (Core/ModulationMatrix) for the body→[0..1] normalisation so
//  there is ONE definition of "what coherence/breath/HR mean" across the app.
//

import Foundation

/// A modulatable EchoelFX parameter. Each carries the natural range used to scale a
/// normalized [0..1] modulation signal into a real parameter offset, plus a label.
public enum FXModTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case filterCutoff
    case filterResonance
    case saturationDrive
    case chorusMix
    case flangerMix
    case phaserMix
    case tremoloDepth
    case delayMix
    case delayFeedback
    case reverbMix
    case reverbSize
    case bitcrushMix
    case stereoWidth

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .filterCutoff:    return "Filter Cutoff"
        case .filterResonance: return "Filter Resonance"
        case .saturationDrive: return "Saturation Drive"
        case .chorusMix:       return "Chorus Mix"
        case .flangerMix:      return "Flanger Mix"
        case .phaserMix:       return "Phaser Mix"
        case .tremoloDepth:    return "Tremolo Depth"
        case .delayMix:        return "Delay Mix"
        case .delayFeedback:   return "Delay Feedback"
        case .reverbMix:       return "Reverb Mix"
        case .reverbSize:      return "Reverb Size"
        case .bitcrushMix:     return "Bitcrush Mix"
        case .stereoWidth:     return "Stereo Width"
        }
    }

    /// The parameter's natural range — the modulation offset is scaled by its span
    /// and the result is clamped here so the audio thread never sees an illegal value.
    public var range: ClosedRange<Float> {
        switch self {
        case .filterCutoff:    return 80...18000
        case .delayFeedback:   return 0...0.95
        case .stereoWidth:     return 0...2
        default:               return 0...1     // mixes/depths/drive/resonance/size
        }
    }
}

/// The signal driving a route: a body channel (reused `ModSource`) or a free LFO.
public enum FXModCarrier: Codable, Sendable, Equatable, Hashable {
    case bio(ModSource)
    case lfo

    /// Short label for the UI / VoiceOver.
    public var displayName: String {
        switch self {
        case .lfo: return "LFO"
        case .bio(let s):
            switch s {
            case .heartRate:   return "Heart rate"
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
    }

    /// Carrier choices offered in the picker: every body channel that HAS a producer,
    /// plus the LFO.
    ///
    /// It used to be `ModSource.allCases` unfiltered, which offered four channels
    /// nothing in this build can write — motion and the three face channels (#135).
    /// Picking one produced a route that renders "—" forever, and a user cannot
    /// distinguish that from a body that has not settled yet. A control that cannot
    /// do anything is worse than an absent one.
    ///
    /// ⚠ A SwiftUI `Picker` renders BLANK when its selection is not among its tags, so
    /// a route persisted on a since-dropped channel would show an empty menu with no
    /// way back. Call sites must union the route's own carrier in — see
    /// `choices(including:)`, which is what the UI should use.
    public static var allChoices: [FXModCarrier] {
        ModSource.allCases.filter(\.hasProducer).map { .bio($0) } + [.lfo]
    }

    /// `allChoices` plus `current`, so a persisted route on a channel that is no longer
    /// offered still renders its own name instead of an empty menu.
    public static func choices(including current: FXModCarrier) -> [FXModCarrier] {
        let base = allChoices
        return base.contains(current) ? base : [current] + base
    }
}

/// One carrier → FX-target modulation, with depth and polarity. Codable so a whole
/// modulation scene saves with an FX preset later.
public struct FXModRoute: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var carrier: FXModCarrier
    public var target: FXModTarget
    /// Output amount [0..1] — the fraction of the target's range the modulation can
    /// move it by (bipolar: ±depth·span/2 around base; unipolar: 0…+depth·span).
    public var depth: Float
    /// Bipolar swings both sides of the user's base value; unipolar only adds.
    public var bipolar: Bool
    /// LFO rate in Hz (used when `carrier == .lfo`).
    public var lfoRateHz: Float
    /// Response shaping applied to the [0..1] carrier signal before depth/polarity —
    /// `.exponential` for a slow start then a fast top, `.logarithmic` for the
    /// reverse, `.sCurve` for soft ends. Default `.linear` (identity).
    public var curve: ResponseCurve
    public var enabled: Bool

    public init(id: UUID = UUID(), carrier: FXModCarrier, target: FXModTarget,
                depth: Float = 0.5, bipolar: Bool = true, lfoRateHz: Float = 0.5,
                curve: ResponseCurve = .linear, enabled: Bool = true) {
        self.id = id
        self.carrier = carrier
        self.target = target
        self.depth = FXModulation.clamp01(depth)
        self.bipolar = bipolar
        self.lfoRateHz = Swift.max(0.01, lfoRateHz)
        self.curve = curve
        self.enabled = enabled
    }
}

/// What the "Live" section's HEADING may honestly claim about who is driving it.
///
/// ⭐ WHY AN ENUM IN A PURE FILE RATHER THAN A TERNARY IN THE VIEW. #641 put the answer in
/// `EchoelFXView` and it took two follow-ups to get right, because each state was decided in a
/// different place: the demo half in the view, then on the modulator, while the LFO half was
/// never decided at all. Here the four states and their four strings sit in ONE `switch` that a
/// test bundle can drive — and `TheFXHeadersSayWhoseBodyTests` turns three source-text scans
/// into END-TO-END assertions as a direct result (§1: that is the strong kind).
///
/// ⛔ THE STATE THIS TYPE EXISTS FOR IS `lfoOnly`, AND IT WAS A LIVE OVER-CLAIM. An LFO carrier
/// is a real oscillator, deliberately never marked synthetic (`BioModContribution.synthetic`).
/// So a section holding ONLY LFO routes fell through every demo test and rendered
/// "Live — body → sound" over rows in which no body is involved at all — the product's core
/// claim, printed over an oscillator. #641's own review registered it and did not fix it; this
/// is that fix.
///
/// ⚠️ `noRoutes` KEEPS THE PLAIN HEADING ON PURPOSE. With nothing enabled the section renders
/// its empty-state text ("No routes yet, so no effect parameter is moving. Add one above."), so
/// the heading is the section's NAME and claims nothing about a current reading. Printing
/// "LFO → sound" there would invent an oscillator that does not exist — the over-correction this
/// family has had to retract twice already.
public enum LiveModOrigin: String, Sendable, Equatable, CaseIterable {
    /// No enabled route at all — the heading is a section name, not a claim.
    case noRoutes
    /// Enabled routes exist and none of them has a bio carrier.
    case lfoOnly
    /// At least one enabled bio route, fed by a real measured source.
    case body
    /// At least one enabled bio route, fed by the demo generator.
    case simulatedDemo

    /// The rendered heading. One `switch`, so the four states cannot drift into five spellings.
    public var heading: String {
        switch self {
        case .noRoutes, .body: return "Live — body → sound"
        case .lfoOnly:         return "Live — LFO → sound"
        case .simulatedDemo:   return "Live — simulated demo → sound"
        }
    }
}

extension FXModulation {

    /// Which of the four the "Live" section is in, from the routes and the SOURCE.
    ///
    /// ⚠️ `enabled` IS FILTERED, and that is a defect this function fixes rather than a detail.
    /// The first version of the demo test asked `routes.contains { … .bio … }` over ALL routes,
    /// so a route the player had switched OFF still put "simulated demo" over a section it
    /// could not touch. `contributions(routes:frame:now:)` — the thing that actually builds the
    /// rows — filters on `enabled` in its first line; the heading has to use the same set or it
    /// describes a different section than the one below it (#416).
    ///
    /// ⚠️ THE SOURCE FLAG IS AN ARGUMENT, not read here, so this stays a pure function of its
    /// inputs and the caller keeps the decision about WHICH gate it comes through. That matters:
    /// the caller deliberately passes the RAW frame's source, because the always-on heading three
    /// rows further down reads raw too, and deriving the two through different freshness gates is
    /// exactly how #641 made them contradict each other.
    public static func liveOrigin(routes: [FXModRoute], sourceIsSynthetic: Bool) -> LiveModOrigin {
        let live = routes.filter { $0.enabled }
        guard !live.isEmpty else { return .noRoutes }
        let anyBio = live.contains { route in
            if case .bio = route.carrier { return true }
            return false
        }
        guard anyBio else { return .lfoOnly }
        return sourceIsSynthetic ? .simulatedDemo : .body
    }
}

/// One enabled route's LIVE effect, for the "which parameters is the body moving"
/// display (Item 2). Pure value type — built deterministically from the routes +
/// the current bio frame, so the leaf view reads a low-rate snapshot instead of
/// the 30 Hz driver (menu-freeze law). `signal01` is the RAW normalized carrier
/// value (pre-curve — the honest "your coherence is at 0.6"); `offset` is the
/// signed amount this route pushes the target by, in the target's own units.
public struct BioModContribution: Sendable, Equatable, Identifiable {
    public var id: UUID            // the route's id (stable across snapshots)
    public var carrierName: String
    public var targetName: String
    public var signal01: Float
    public var offset: Float
    /// Whether the body actually REPORTED this carrier for this snapshot. `false` when
    /// there is no frame at all, or a frame that carries nothing on this channel
    /// (`ModSource.isMeasured`). The row must then render "—", never the "0.00" that
    /// `signal01`/`offset` hold — the same law `BioStripView` applies to the bio strip,
    /// because a confident zero reads as "your body is at the bottom of the scale"
    /// rather than "nobody measured this". Always `true` for an LFO carrier, which
    /// needs no body.
    public var measured: Bool
    /// Whether the reading behind this row came from the DEMO source rather than a body.
    /// `measured` and `synthetic` answer different questions and both are needed: a demo
    /// frame reports every channel, so it is `measured: true` and would otherwise draw a
    /// confident number and a full-strength bar that nothing on screen distinguishes from
    /// a real pulse. This is the same law the bio strip, the header pill, the always-on
    /// channel rows, the Live-Colabo rows, the widget and the watch already carry.
    ///
    /// ⚠️ TRUE ONLY FOR A CONTRIBUTING BIO CARRIER, and both exclusions are deliberate:
    /// an **LFO** carrier is a real oscillator and is not made simulated by the bio source
    /// running in demo — marking it would be a fresh false claim of exactly the kind this
    /// field exists to remove; an **unmeasured** row already renders "—" and says "not
    /// measured", so it claims nothing that needs qualifying. `TheFXRoutesSayWhoseBodyTests`
    /// carries both as counterweights.
    public var synthetic: Bool

    /// ⚠️ `synthetic` has NO DEFAULT, deliberately (#431/#440/#443): a defaulted argument
    /// that no call site writes never appears in a diff, so the one construction site would
    /// keep compiling while silently claiming every demo route is a real body. There is
    /// exactly one construction site in `Sources/` and `Tests/` (`FXModulation.contributions`),
    /// so the cost of no default is one edit. (`measured` predates this rule and keeps its
    /// default; changing that is a separate slice, not a drive-by.)
    public init(id: UUID, carrierName: String, targetName: String,
                signal01: Float, offset: Float, measured: Bool = true,
                synthetic: Bool) {
        self.id = id
        self.carrierName = carrierName
        self.targetName = targetName
        self.signal01 = signal01
        self.offset = offset
        self.measured = measured
        self.synthetic = synthetic
    }
}

/// Pure mapping helpers — the deterministic heart of the feature.
public enum FXModulation {

    @inline(__always) public static func clamp01(_ x: Float) -> Float {
        Swift.min(Swift.max(x.isFinite ? x : 0, 0), 1)
    }

    /// Whether the ~30 Hz driver should refresh the observable `liveContributions`
    /// snapshot on this tick — `everyN = 3` gives ~10 Hz out of 30, keeping the UI
    /// observation load low. Guards `everyN <= 0` (never divide/modulo by zero).
    public static func shouldPublish(tick: Int, everyN: Int) -> Bool {
        everyN > 0 && tick % everyN == 0
    }

    /// Build the per-route live contributions for the ENABLED routes. A bio carrier the
    /// body is not currently reporting still appears — the row stays visible so the user
    /// can see the route exists — but is marked `measured: false` with signal 0 and
    /// offset 0, and `BioModContributionRow` renders that as "—", not a number. LFO
    /// carriers use `now` (seconds) for their phase and ignore the frame; they are always
    /// measured. Order preserved. Deterministic → Linux-testable.
    ///
    /// This reports AVAILABILITY, not the driver's fade: `FXBioModulator` eases a route
    /// in and out over ~0.25 s (`presence`), so for that quarter second the row can read
    /// "—" while a tail is still audible, or show a full offset while the route is still
    /// easing in. Deliberate — the row's job is "is your body driving this", which is a
    /// yes/no about the sensor, and threading the envelope in would make the readout
    /// stateful and no longer a pure function of the routes and the frame.
    ///
    /// "Not reporting" is two cases, and both must be caught: no frame at all, and a
    /// frame that carries nothing ON THIS CHANNEL (`ModSource.isMeasured` — a `.faceCam`
    /// frame has no pulse, a source without beat-to-beat RR has no coherence). The offset
    /// is forced to 0 in both rather than computed from signal 0, and that is not
    /// cosmetic: this readout exists to answer "what is my body moving right now", so it
    /// must agree with where the driver ENDS UP — and `FXBioModulator` disengages exactly
    /// these routes, settling on the base value (via `FXRouteFade`, over ~0.25 s, which
    /// is the transient the paragraph above owns). Running signal 0 through the BIPOLAR
    /// formula instead gives `(0·2−1)·depth·span·0.5`, a FULL NEGATIVE excursion, so a route
    /// displayed a large negative contribution it was not making.
    public static func contributions(routes: [FXModRoute], frame: BioSampleFrame?,
                                     now: Float) -> [BioModContribution] {
        routes.filter { $0.enabled }.map { route in
            let signal: Float
            var contributing = true
            switch route.carrier {
            case .bio(let source):
                if let frame, source.isMeasured(in: frame) {
                    signal = source.normalizedValue(from: frame)
                } else {
                    signal = 0
                    contributing = false
                }
            case .lfo:
                let phase = (now * route.lfoRateHz).truncatingRemainder(dividingBy: 1)
                signal = lfoUnipolar(phase: phase)
            }
            let off = contributing
                ? offset(target: route.target, signal: route.curve.apply(signal),
                         depth: route.depth, bipolar: route.bipolar)
                : 0
            // Demo-ness is a property of the BODY, so only a contributing `.bio` carrier
            // can carry it: an LFO keeps running on its own clock and is never simulated,
            // and an unmeasured row already renders "—" rather than a claim. `frame` is the
            // only provenance this pure function has — deliberately, since reaching for a
            // camera/publisher state here would make it stateful and no longer Linux-testable.
            var isDemo = false
            if case .bio = route.carrier, contributing, frame?.source == .fallback {
                isDemo = true
            }
            return BioModContribution(id: route.id,
                                      carrierName: route.carrier.displayName,
                                      targetName: route.target.displayName,
                                      signal01: clamp01(signal), offset: off,
                                      measured: contributing,
                                      synthetic: isDemo)
        }
    }

    /// How fast a route engages and disengages when its carrier starts or stops being
    /// measured, as a one-pole time constant in seconds. ~0.08 s reaches 95 % in about
    /// a quarter second: fast enough that the body still feels connected to the sound,
    /// slow enough that a sensor dropout is a fade rather than a click.
    public static let presenceTau: Float = 0.08

    /// Rate-based [0..1] engagement for ONE route, stepped by `dt` seconds toward 1
    /// while its carrier is measured and toward 0 while it is not.
    ///
    /// This is deliberately an envelope on the route's PRESENCE, not a smoother on its
    /// offset. Smoothing the offset would also blunt every intentional fast move — a
    /// 5 Hz LFO on tremolo, a sharp breath transient — to fix a boundary those moves
    /// have nothing to do with. Multiplying a held offset by this envelope leaves the
    /// modulation itself as sharp as the user asked for, and only fades the route in
    /// and out at the edges of the body's actual availability.
    ///
    /// Rate-based per the project law: `1 − e^(−dt/τ)` depends on elapsed time, so the
    /// fade takes the same wall-clock time whether the driver ticks at 30 Hz or faster.
    /// A non-advancing or non-finite clock snaps to the target rather than freezing the
    /// envelope mid-fade or poisoning it with NaN.
    public static func presence(current: Float, measured: Bool,
                                dt: Float, tauSeconds: Float = presenceTau) -> Float {
        let target: Float = measured ? 1 : 0
        let c = current.isFinite ? clamp01(current) : target
        // A zero/invalid time CONSTANT means "instant" — snap is the right reading.
        guard tauSeconds.isFinite, tauSeconds > 0 else { return target }
        // A zero/negative/invalid time STEP means no time passed — hold, do not snap.
        // These two cases pull opposite ways, which is why they are separate guards:
        // folding them together made a stalled clock produce a complete transition.
        guard dt.isFinite, dt > 0 else { return c }
        let alpha = clamp01(1 - expf(-dt / tauSeconds))
        let next = c + (target - c) * alpha
        return clamp01(next.isFinite ? next : target)
    }

    /// Below this a route counts as fully disengaged, and its fade SNAPS to zero.
    /// A one-pole only reaches zero by denormal underflow (~8 s here), and a route
    /// lingering at an inaudible amount is not free — it keeps its FX stage enabled, so
    /// a reverb tank goes on running eight comb filters at a mix nobody can hear.
    public static let presenceEpsilon: Float = 0.0005

    /// The longest gap treated as real elapsed time when advancing a fade.
    ///
    /// Without a ceiling the envelope defeats itself: `alpha` saturates fast, so a
    /// 200 ms main-actor stall (this app documents plenty) collapses a route by 92 % in
    /// one tick, and a return from background — where the whole 30 Hz loop was suspended
    /// — snaps it outright. That is the full-magnitude step the fade exists to remove,
    /// re-entering through the clock. Clamping means a hitch resumes the fade at its
    /// normal rate instead: the fade takes longer in wall-clock time, which is a
    /// graceful degradation rather than a click. 0.05 s is ~1.5 nominal ticks, so
    /// ordinary jitter stays exactly rate-independent.
    public static let maxFadeStepSeconds: Float = 0.05

    /// A free LFO's unipolar [0..1] value at a phase in turns (1.0 = one cycle).
    public static func lfoUnipolar(phase: Float) -> Float {
        0.5 + 0.5 * sinf(2 * .pi * phase)
    }

    /// The signed offset a single route contributes to `target` for a normalized
    /// carrier `signal` in [0..1]. Lets the driver SUM several routes on one target
    /// before clamping once (so two body channels can sculpt the same parameter).
    ///
    /// - bipolar:  (signal·2−1)·depth·span/2  → swings either side of base
    /// - unipolar: signal·depth·span          → adds upward from base
    public static func offset(target: FXModTarget, signal: Float,
                              depth: Float, bipolar: Bool) -> Float {
        let span = target.range.upperBound - target.range.lowerBound
        let s = clamp01(signal)
        let d = clamp01(depth)
        let o: Float = bipolar ? (s * 2 - 1) * d * span * 0.5 : s * d * span
        return o.isFinite ? o : 0
    }

    /// Combine a base value with summed route offsets, clamped to the target range.
    public static func combine(base: Float, target: FXModTarget, offset: Float) -> Float {
        let r = target.range
        let v = base + offset
        return Swift.min(Swift.max(v.isFinite ? v : base, r.lowerBound), r.upperBound)
    }

    /// The value to WRITE to `target` given the user's `base`, a normalized carrier
    /// `signal` in [0..1], `depth` [0..1] and polarity. Clamped to the target range.
    public static func value(base: Float, target: FXModTarget,
                             signal: Float, depth: Float, bipolar: Bool) -> Float {
        combine(base: base, target: target,
                offset: offset(target: target, signal: signal, depth: depth, bipolar: bipolar))
    }
}

/// One route's fade state — the last offset it actually produced, and how engaged it
/// currently is. Pure and `Equatable`, so the whole engage/hold/disengage state machine
/// is testable without the 30 Hz driver, an audio chain or a device.
///
/// The design point: this envelopes the route's PRESENCE, never its offset. Smoothing
/// the offset would also blunt every intentional fast move — an 8 Hz LFO on tremolo, a
/// sharp breath transient — to fix a boundary those moves have nothing to do with.
public struct FXRouteFade: Sendable, Equatable {

    /// What a held offset MEANS. The offset is only refreshed on a measured tick, so
    /// without this a route sitting on an unmeasured carrier keeps a number in the units
    /// of whatever it used to point at — and the FX view's target picker repoints a route
    /// IN PLACE, keeping its id. A held `+4480` from Filter Cutoff applied to Reverb Mix
    /// (range 0…1) would clamp the reverb to fully wet. Depth, polarity and curve are in
    /// here for the milder version of the same thing: editing them while the carrier is
    /// unmeasured would otherwise do nothing until the body came back, so the control
    /// reads as dead.
    public struct Shape: Sendable, Equatable {
        public var target: FXModTarget
        public var depth: Float
        public var bipolar: Bool
        public var curve: ResponseCurve
        public init(_ r: FXModRoute) {
            target = r.target; depth = r.depth; bipolar = r.bipolar; curve = r.curve
        }
    }

    public private(set) var offset: Float = 0
    public private(set) var presence: Float = 0
    public private(set) var shape: Shape?

    public init() {}

    /// Advance one control tick. `signal` is the route's normalized [0..1] carrier value,
    /// or `nil` when the body is not reporting that channel at all (no frame, or a frame
    /// with nothing on this channel — see `ModSource.isMeasured`).
    public mutating func step(route: FXModRoute, signal: Float?, dt: Float,
                              tauSeconds: Float = FXModulation.presenceTau) {
        let current = Shape(route)
        if shape != current {
            shape = current
            offset = 0          // the held number no longer means anything
        }
        if let signal {
            offset = FXModulation.offset(target: route.target,
                                         signal: route.curve.apply(signal),
                                         depth: route.depth, bipolar: route.bipolar)
        }
        let stepSeconds = Swift.min(dt.isFinite ? Swift.max(dt, 0) : 0,
                                    FXModulation.maxFadeStepSeconds)
        presence = FXModulation.presence(current: presence, measured: signal != nil,
                                         dt: stepSeconds, tauSeconds: tauSeconds)
        if signal == nil, presence < FXModulation.presenceEpsilon {
            presence = 0
            offset = 0
        }
    }

    /// The signed amount this route contributes to its target right now.
    public var contribution: Float { offset * presence }

    /// Whether the route is still doing anything audible — including a tail that is
    /// fading out, so the driver keeps its FX stage enabled for the whole tail.
    public var isEngaged: Bool { presence > FXModulation.presenceEpsilon }
}
