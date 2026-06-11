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

    /// Mach absolute time when this frame was produced.
    public let timestamp: TimeInterval

    /// Heart rate in BPM. Range [40..200], unclamped here.
    public let heartRateBPM: Float

    /// HRV (rMSSD) normalized to [0..1].
    public let hrvNormalized: Float

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

    /// Breathing rate in breaths/min. Range [4..30].
    public let breathRate: Float

    /// Breath phase, [0..1]. 0 = exhale start, 0.5 = inhale start.
    public let breathPhase: Float

    /// Coherence score, [0..1]. Derived from HRV spectrum.
    public let coherence: Float

    /// Motion energy, [0..1]. Aggregate from CoreMotion.
    public let motionEnergy: Float

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
        hrvPNN50: Float = 0
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

    public init(
        timestamp: TimeInterval,
        kind: Kind,
        confidence: Float,
        aux: Float
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.confidence = confidence
        self.aux = aux
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

    public private(set) var latestControllerEvent: ControllerEvent?

    public private(set) var latestBioEvent: BioEvent?

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
    nonisolated public func publish(bioEvent event: BioEvent) {
        bioEvents.enqueue(event)
        Task { @MainActor [weak self] in
            self?.latestBioEvent = event
        }
    }
}
