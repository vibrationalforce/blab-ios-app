//
//  EngineBus.swift
//  Echoelmusic
//
//  Central typed pub/sub for biofeedback samples, controller events
//  (MPE + air CCs), and discrete bio events. Hybrid isolation model:
//
//    Control plane (latest snapshots for SwiftUI observation):
//        @MainActor @Observable, single-source-of-truth for views.
//
//    Data plane (audio-thread consumers, ≤120 Hz bio producers):
//        Lock-free SPSCQueue per topic, allocation-free at the
//        consumer side.
//
//  Publishers run at sub-kHz rates (Oura ≤4 Hz, HealthKit ≤1 Hz,
//  CoreMIDI ≤sub-kHz) and may dual-update both planes safely.
//  Audio-thread *consumers* only read from the queues — they never
//  publish through this surface.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

// MARK: - Continuous biosignal frame

/// One snapshot of a bio source's normalized, low-rate channels.
/// All values are normalized per master prompt §2 except where noted.
public struct BioSampleFrame: Sendable, Equatable {

    /// `CFAbsoluteTime` (seconds since the 2001 reference date, i.e.
    /// `CFAbsoluteTimeGetCurrent()` / `Date.timeIntervalSinceReferenceDate`) at
    /// which this frame was RECEIVED by its publisher — NOT mach_absolute_time, and
    /// NOT the underlying measurement time. Every publisher stamps this same clock at
    /// receipt (see the freshness contract at `freshBio`/`usableBio` below) so the
    /// age comparison is valid across BLE / rPPG / HealthKit / Demo sources.
    public let timestamp: TimeInterval

    /// Heart rate in BPM. Range [40..200], unclamped here.
    public let heartRateBPM: Float

    /// HRV (rMSSD) normalized to [0..1]. `0` means **not measured**, not "minimum
    /// variability" — a Watch before its first SDNN sample, a camera before it locks.
    /// Anything that DISPLAYS this must render 0 as "—" (see `BioStripView`); anything
    /// that MODULATES with it should read `hrvForSound` instead.
    public let hrvNormalized: Float

    /// `hrvNormalized` for MODULATION targets: unmeasured (0) becomes a neutral 0.5.
    ///
    /// Why this exists as one property instead of a ternary at each call site: 0 is not
    /// a neutral value in any of the HRV mappings, it is an EXTREME. Feeding a literal 0
    /// asserts "minimum variability" — it darkens timbre, and in `BioComposer` it reads
    /// as maximum sympathetic load and composes a busier, more agitated take precisely
    /// when the app knows nothing about the body. That is a worse fabrication than the
    /// placeholder this convention replaced. The rule was first written inline at two
    /// synth voices and drifted immediately — a review sweep found it missing at every
    /// other value-mapping consumer. Keeping it in one place is what stops that again.
    ///
    /// **Applies to VALUE mappings only.** Where 0 already means "no contribution",
    /// the raw value is the CORRECT one and substituting 0.5 would invent a permanent
    /// half-depth offset out of nothing. Two such places:
    /// - `BioComposer.hrvHumanize` — guards `span > 0`, so no HRV means it touches
    ///   nothing. Verified: it is a discrete op the user invokes by name, and a
    ///   neutral 0.5 there would present seeded jitter AS their variability.
    /// - `FXModulation.offset` / `VisualModulation`, but **only on the unipolar
    ///   branch** (`signal·depth·span`), which is also why `contributions` feeds
    ///   signal 0 for a missing frame.
    ///
    /// The bipolar branch is `(signal·2−1)·depth·span·0.5`, where signal 0 is the FULL
    /// NEGATIVE excursion — so a bipolar route on a channel the body never reported used
    /// to apply a permanent maximal offset. Both halves of that are now CLOSED, and
    /// neither was fixed here, deliberately:
    ///
    /// - A missing frame never reached the audio: `FXBioModulator` treated a bio route
    ///   with no frame as contributing nothing, so the base value stood. It DID reach
    ///   the ~10 Hz `contributions` readout, which showed that excursion for a route
    ///   contributing nothing; fixed by forcing the offset to 0.
    /// - A frame present but carrying a STRUCTURAL zero DID reach the audio, because
    ///   `ModSource.rawValue` reads the RAW fields and `FXModRoute` defaults to
    ///   `bipolar: true`. It was not a corner case: the FX view's "add route" button
    ///   always creates a `.bio(.coherence)` route, and `coherence` is 0 on every source
    ///   without beat-to-beat RR — so every bio route reachable from the UI hit this on
    ///   HealthKit. Fixed by `ModSource.isMeasured(in:)`, which the FX driver and the FX
    ///   readout gate on. (`VisualModulation` gates on it too, but that core has no
    ///   caller yet — it is a guard for when the visual path is wired, not a fix anyone
    ///   has seen.)
    ///
    /// Neither fix routes `ModSource.rawValue` through this property, and that is the
    /// point: a neutral 0.5 substitution would invent a permanent half-depth offset for
    /// every UNIPOLAR route to fix one polarity. Skipping is the honest form — it is
    /// exactly "no contribution", and on every channel whose sentinel normalizes to 0 it
    /// already equals the unipolar result.
    ///
    /// The gate's own boundary is FADED, not stepped: `FXRouteFade` holds a route's last
    /// real offset and eases it out over ~0.25 s when its channel stops being measured
    /// (the camera's ~4 s dropout grace is the live case — it republishes
    /// `breathRate: 0` while still holding a continuous `breathPhase`). What remains is
    /// NOT this gate's doing and is not closed: no `EchoelFXChain` stage smooths its own
    /// parameters, so every control-rate write is a staircase — a 10 Hz bio carrier
    /// steps cutoff 10× a second regardless of any boundary. That needs chain-side
    /// parameter smoothing, the way `EchoelDelay` already smooths its read tap.
    ///
    /// This is deliberately NOT the fully honest form. The honest form is "do not apply
    /// the HRV mapping at all when there is no HRV" — depth to zero rather than value to
    /// the middle — which needs an optional or a `hasHRV` flag threaded through every
    /// mapping. Until then: the DISPLAY must never state an unmeasured value, and the
    /// instrument must still play.
    public var hrvForSound: Float { hrvNormalized > 0 ? Swift.min(hrvNormalized, 1) : 0.5 }

    /// Raw HRV as RMSSD in **milliseconds** — the un-normalized, instrument-grade
    /// value for display, logging, and OSC. `0` means the source does not provide
    /// a real RMSSD (e.g. HealthKit, which exposes SDNN only); UI should then fall
    /// back to `hrvNormalized`. Never synthesize an inaccurate ms from the
    /// normalized value for a real sensor.
    public let hrvRMSSDms: Float

    /// SDNN in **milliseconds** — standard deviation of NN intervals (overall
    /// variability). `0` = not available from this source.
    public let hrvSDNNms: Float

    /// pNN50 as a **percentage** [0…100] — successive |RR differences| > 50 ms.
    /// `0` may mean "not available" or a genuine 0 %; pair with `hrvRMSSDms > 0`
    /// to know a real sensor is present.
    public let hrvPNN50: Float

    /// Breathing rate in breaths/min. `0` = the source derives no respiration.
    public let breathRate: Float

    /// Physiologically plausible respiration window (breaths/min). You cannot breathe
    /// zero times a minute, so a value outside this band is an absence, not a reading.
    public static let plausibleBreathRate: ClosedRange<Float> = 3...40

    /// Whether this frame carries a REAL respiration measurement.
    ///
    /// The gate is `breathRate`, deliberately, even for consumers that read `breathPhase`:
    /// `breathPhase` has NO unknown sentinel — 0 is a meaningful position (exhale start)
    /// — so it cannot answer this question about itself. Publishers encode "no breath" by
    /// leaving `breathRate` at 0 (`PolarH10BioPublisher`, `FaceExpressionBioPublisher`,
    /// and `CameraRPPGBioPublisher` below its confidence threshold), and the HealthKit
    /// path leaves `breathPhase` at the engine's 0.5 placeholder. Anything DISPLAYING a
    /// breath value must gate on this; a 0.50 rendered next to honest "—" neighbours
    /// reads as the most confident number on the panel.
    public var hasMeasuredBreath: Bool { Self.plausibleBreathRate.contains(breathRate) }

    /// Breath phase, [0..1]. 0 = exhale start, 0.5 = inhale start.
    public let breathPhase: Float

    /// Coherence score, [0..1]. Real frequency-domain HRV coherence
    /// (`HRVCoherence`, Lomb–Scargle / Welch over the RR series) on sources that
    /// deliver beat-to-beat RR — BLE/Polar (`.ble`) and camera (`.cameraPPG`).
    /// `0` where the source has no real RR (HealthKit gives averaged HR + SDNN
    /// only). The demo/`.fallback` source carries a simulated value. Treat `0`
    /// as "not available", not as "incoherent".
    public let coherence: Float

    /// `coherence` for MODULATION targets: unmeasured (0) becomes a neutral 0.5.
    ///
    /// The twin of `hrvForSound`, and it exists for the same reason: this rule had
    /// been written inline three times over — a private helper in one synth voice, a
    /// bare ternary in the other, a held-body variant in the studio view — and was
    /// missing at the sound and visual consumers. That is the exact drift `hrvForSound`
    /// was created to stop, left half-finished. (The sweep is NOT complete: the light
    /// and space egress — `ArtNetSender`'s dimmer, `ADMOSCSender`'s distance — still
    /// read raw. Those are output renders for a console the operator also drives, so
    /// they need a deliberate EchoelLux/spatial decision, not this mechanical swap.)
    /// Coherence bites harder than HRV because more mappings
    /// read it as "calmness": a literal 0 muffles the filter to 200 Hz, picks the
    /// least-consonant chord voicing, and pins the composer to a sparse frozen take.
    /// The first two copies are now deleted; the studio one deliberately stays (it can
    /// fall back to a held body's real coherence, which is better than this 0.5).
    ///
    /// The VALUE-mappings-only caveat on `hrvForSound` applies here unchanged.
    public var coherenceForSound: Float { coherence > 0 ? Swift.min(coherence, 1) : 0.5 }

    /// Motion energy, [0..1]. Aggregate from CoreMotion.
    public let motionEnergy: Float

    /// Facial-EXPRESSION control channels, all [0..1], all default `0` when the
    /// source does not track the face (every current publisher writes `0`, like
    /// `motionEnergy`). These are movement/expression used as a CONTROL signal —
    /// NEVER an inferred emotion (EU AI Act framing; see `FaceExpressionMapping`).

    /// Smile expression as a control value, [0..1]. `0` = not tracked / neutral.
    public let faceSmile: Float

    /// Brow-raise expression as a control value, [0..1]. `0` = not tracked / neutral.
    public let faceBrowRaise: Float

    /// Jaw-open expression as a control value, [0..1]. `0` = not tracked / neutral.
    public let faceJawOpen: Float

    /// Where the frame originated.
    public let source: BioSource

    public init(
        timestamp: TimeInterval,
        heartRateBPM: Float,
        hrvNormalized: Float,
        breathRate: Float,
        breathPhase: Float,
        coherence: Float,
        motionEnergy: Float,
        source: BioSource,
        hrvRMSSDms: Float = 0,
        hrvSDNNms: Float = 0,
        hrvPNN50: Float = 0,
        faceSmile: Float = 0,
        faceBrowRaise: Float = 0,
        faceJawOpen: Float = 0
    ) {
        self.timestamp = timestamp
        self.heartRateBPM = heartRateBPM
        self.hrvNormalized = hrvNormalized
        self.breathRate = breathRate
        self.breathPhase = breathPhase
        self.coherence = coherence
        self.motionEnergy = motionEnergy
        self.source = source
        self.hrvRMSSDms = hrvRMSSDms
        self.hrvSDNNms = hrvSDNNms
        self.hrvPNN50 = hrvPNN50
        self.faceSmile = faceSmile
        self.faceBrowRaise = faceBrowRaise
        self.faceJawOpen = faceJawOpen
    }
}

/// Origin of a bio frame.
public enum BioSource: UInt8, Sendable, Equatable {
    case fallback = 0
    case healthKit = 1
    case oura = 2
    case ble = 3
    case watch = 4
    case cameraPPG = 5
    /// Front-camera facial-EXPRESSION tracking (ARKit blendShapes → smile/brow/jaw
    /// control channels). Appended at the END so persisted raw values stay stable.
    /// It carries NO pulse — expression/movement used as a control signal, never an
    /// inferred emotion or a heart measurement.
    case faceCam = 6

    /// Whether this source delivers beat-to-beat RR intervals accurate enough
    /// for time-domain HRV (RMSSD). Only a BLE Heart-Rate-Service chest strap
    /// (0x180D, e.g. Polar H10) qualifies: wrist/camera PPG smooths or gaps the
    /// RR series and Apple Watch carries ~4–5 s latency, so their "HRV" is an
    /// estimate, not a measurement (research §A1). Consumers gate HRV-driven
    /// modulation on this so a strap-only route stays silent on weak sources.
    public var providesTrustedHRV: Bool { self == .ble }

    /// How long a reading from this source stays musically usable. Live optical/
    /// electrical sources (BLE strap, camera rPPG) expire fast — a lifted finger or
    /// a dropped strap must NOT keep driving sound off a frozen value. But Apple
    /// Watch / HealthKit HR is latent AND sporadic (Apple writes resting HR only
    /// every few minutes); a reading from a minute ago is still your current heart
    /// rate, so a 5 s gate discards it and the wrist never "feels" connected. Give
    /// each source a window matched to how it actually arrives. Staleness is still
    /// enforced — a truly stalled Watch eventually expires.
    public var freshnessWindow: TimeInterval {
        switch self {
        case .ble, .cameraPPG: return 6      // live, near beat-to-beat
        case .faceCam: return 6              // live front-camera expression, same cadence
        case .watch, .healthKit: return 90   // latent + sporadic, valid at rest
        case .oura: return 600               // periodic readiness/HRV
        case .fallback: return 5
        }
    }
}

// MARK: - External controller event (MPE + air dimensions)

/// One event from MIDI/MPE/Network-MIDI external controllers.
public struct ControllerEvent: Sendable, Equatable {

    public enum Kind: UInt8, Sendable, Equatable {
        case noteOn
        case noteOff
        case pitchBend
        case channelPressure
        case slide          // CC74 (MPE timbre)
        case airCC          // CC 21..31 (master prompt §3 air dimensions)
    }

    public let timestamp: TimeInterval

    public let kind: Kind

    /// MPE member channel 2..15, or 1 for master/global.
    public let channel: UInt8

    /// MIDI note 0..127 (0 for non-note events).
    public let note: UInt8

    /// Normalized value. Range depends on kind: pitch bend in [-1..1],
    /// pressure / slide / airCC in [0..1].
    public let value: Float

    /// For `.airCC`: source CC number (21..31). 0 otherwise.
    public let auxCC: UInt8

    public init(
        timestamp: TimeInterval,
        kind: Kind,
        channel: UInt8,
        note: UInt8,
        value: Float,
        auxCC: UInt8
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.channel = channel
        self.note = note
        self.value = value
        self.auxCC = auxCC
    }
}

// MARK: - Discrete bio event (from BioEventGraph, see SKILL.md)

/// One discrete event emitted by `BioEventGraph`.
public struct BioEvent: Sendable, Equatable {

    public enum Kind: UInt8, Sendable, Equatable {
        case heartbeat
        case breathInhaleOnset
        case breathExhaleOnset
        case motionPeak
        case coherenceShift
        case eegBurst
    }

    public let timestamp: TimeInterval

    public let kind: Kind

    /// Detector confidence, [0..1].
    public let confidence: Float

    /// Kind-specific scalar (e.g., inter-beat interval ms for `.heartbeat`,
    /// band power for `.eegBurst`).
    public let aux: Float

    /// Which bio source this event was DERIVED FROM — the provenance the network
    /// egress gate needs (#186, App Store 5.1.3).
    ///
    /// `nil` means UNSTAMPED, and the gate treats that as "do not send". Fail-closed is
    /// the only safe default here: a permissive one would let a future producer leak by
    /// forgetting a line, which is exactly how the gap this fixes came to exist.
    ///
    /// It is optional-with-a-default rather than required for a hard reason:
    /// `BioEventGraph` constructs four of the five `BioEvent`s in this repo and is a
    /// PROTECTED Rausch component (READ-ONLY without founder approval). A required
    /// parameter would force edits inside it. So the graph keeps producing unstamped
    /// events — it does not know the provenance anyway, it only sees channel values —
    /// and whoever DOES know stamps them at the publish boundary via `stamped(source:)`.
    public let source: BioSource?

    public init(
        timestamp: TimeInterval,
        kind: Kind,
        confidence: Float,
        aux: Float,
        source: BioSource? = nil
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.confidence = confidence
        self.aux = aux
        self.source = source
    }

    /// This event with its provenance recorded. Non-mutating so the protected graph's
    /// output can be stamped by its caller without the graph knowing about sources.
    public func stamped(source: BioSource) -> BioEvent {
        BioEvent(timestamp: timestamp, kind: kind, confidence: confidence,
                 aux: aux, source: source)
    }
}

// MARK: - EngineBus

/// Single source of truth for bio, controller, and event signal routing
/// between modules. See master prompt §1 — modules consume/produce here,
/// never directly couple to each other.
@MainActor
@Observable
public final class EngineBus {

    // MARK: - Latest snapshots (control plane, @MainActor)

    public private(set) var latestBio: BioSampleFrame?

    /// The freshest bio frame, but only if it arrived within `maxAge` seconds of
    /// now — else `nil`. `BioSampleFrame.timestamp` is on the
    /// `timeIntervalSinceReferenceDate` clock (CFAbsoluteTimeGetCurrent), shared by
    /// every publisher (BLE, rPPG, HealthKit, Demo), so the comparison is valid
    /// across sources. This is the single guard that stops a frozen reading — a
    /// dropped BLE strap, a lifted finger, a stalled Watch — from being treated as a
    /// live body signal (music kept playing on a dead HR, the strip stayed green).
    /// Default 5 s tolerates HealthKit's ~4–5 s Watch latency; pass a tighter window
    /// (e.g. 3 s) for low-latency BLE/rPPG UI.
    public func freshBio(maxAge: TimeInterval = 5) -> BioSampleFrame? {
        guard let f = latestBio,
              CFAbsoluteTimeGetCurrent() - f.timestamp <= maxAge,
              CFAbsoluteTimeGetCurrent() - f.timestamp >= -1 else { return nil }
        return f
    }

    /// The freshest frame still within ITS OWN source's usefulness window — the
    /// "is there a usable body signal right now?" question the composer asks. A
    /// camera/BLE reading expires in 6 s (live), a Watch/HealthKit reading stays
    /// usable for 90 s (latent + sporadic, but valid at rest), so wrist HR actually
    /// drives the music instead of being discarded the instant it's a few seconds
    /// old. Still guards against a frozen/stalled source (each window is finite).
    public func usableBio() -> BioSampleFrame? {
        guard let f = latestBio else { return nil }
        let age = CFAbsoluteTimeGetCurrent() - f.timestamp
        guard age <= f.source.freshnessWindow, age >= -1 else { return nil }
        return f
    }

    public private(set) var latestControllerEvent: ControllerEvent?

    public private(set) var latestBioEvent: BioEvent?

    /// LOW-frequency run state of the bio-generative instrument (Start/Stop, set by
    /// the studio's start/stop paths). Lets the chrome (TransportBar's pulse button)
    /// mirror the instrument state without coupling to the studio view — modules
    /// couple only via the bus. `private(set)` + mutator so no future module can
    /// turn it into a high-frequency churn source — it must stay Start/Stop-only
    /// (any body may read it under the freeze rule ONLY because of that).
    public private(set) var instrumentRunning = false

    /// Start/Stop-frequency ONLY — never call this per-frame/per-tick.
    public func setInstrumentRunning(_ running: Bool) {
        instrumentRunning = running
    }

    // MARK: - Latest MUSICAL snapshot (DMMW: media subscribe to musical parameters)

    public private(set) var latestMusical: MusicalFrame?

    /// The freshest musical frame within `maxAge` seconds — the music-side mirror of
    /// `freshBio`, so renderers (visual/light/spatial) only react to LIVE musical
    /// state and never to a frozen frame after playback stops. Same shared clock.
    public func freshMusical(maxAge: TimeInterval = 2) -> MusicalFrame? {
        guard let f = latestMusical,
              CFAbsoluteTimeGetCurrent() - f.timestamp <= maxAge,
              CFAbsoluteTimeGetCurrent() - f.timestamp >= -1 else { return nil }
        return f
    }

    // MARK: - Lock-free queues (data plane, audio-thread consumers)

    @ObservationIgnored
    nonisolated(unsafe) public let bioFrames: SPSCQueue<BioSampleFrame>

    @ObservationIgnored
    nonisolated(unsafe) public let controllerEvents: SPSCQueue<ControllerEvent>

    @ObservationIgnored
    nonisolated(unsafe) public let bioEvents: SPSCQueue<BioEvent>

    // MARK: - Init

    public init(
        bioCapacity: Int = 32,
        controllerCapacity: Int = 128,
        bioEventCapacity: Int = 64
    ) {
        self.bioFrames = SPSCQueue(capacity: bioCapacity)
        self.controllerEvents = SPSCQueue(capacity: controllerCapacity)
        self.bioEvents = SPSCQueue(capacity: bioEventCapacity)
    }

    // MARK: - Publishers (callable from any thread except audio render)

    /// Publish a bio frame. Enqueues to the lock-free queue (audio-side
    /// consumers see it immediately) and updates the @MainActor latest
    /// snapshot for SwiftUI observation.
    nonisolated public func publish(bio frame: BioSampleFrame) {
        bioFrames.enqueue(frame)
        Task { @MainActor [weak self] in
            self?.latestBio = frame
        }
    }

    /// Publish a controller event.
    nonisolated public func publish(controller event: ControllerEvent) {
        controllerEvents.enqueue(event)
        Task { @MainActor [weak self] in
            self?.latestControllerEvent = event
        }
    }

    /// Publish a discrete bio event.
    ///
    /// SPSC CONTRACT (audited 2026-07-24). `bioEvents` is a single-producer /
    /// single-consumer lock-free queue. This method is `nonisolated` for call-site
    /// convenience, but the enqueue is race-free ONLY because every current caller
    /// publishes from `@MainActor` — `BioEventPublisher.tick` runs on its @MainActor
    /// poll, and `PolarH10BioPublisher.didUpdateValueFor` (a nonisolated BLE callback)
    /// hops to `Task { @MainActor }` before publishing — so all enqueues serialize on
    /// the main thread, and the SOLE consumer (`OSCSender.drainAndSendEvents`) also
    /// drains on @MainActor. A NEW caller MUST publish bio events from @MainActor too;
    /// enqueuing from a second thread would corrupt the lock-free head/tail. (The
    /// "two-producer SPSC race" audit flag was a FALSE POSITIVE: both producers are
    /// already @MainActor-serialized by construction — do not add a lock here.)
    nonisolated public func publish(bioEvent event: BioEvent) {
        bioEvents.enqueue(event)
        Task { @MainActor [weak self] in
            self?.latestBioEvent = event
        }
    }

    /// Publish the current musical state. Slow control-plane (UI-rate), so it only
    /// updates the @MainActor snapshot — no lock-free queue needed (renderers read it
    /// via `freshMusical`). Mirrors `publish(bio:)`.
    nonisolated public func publish(musical frame: MusicalFrame) {
        Task { @MainActor [weak self] in
            self?.latestMusical = frame
        }
    }
}
