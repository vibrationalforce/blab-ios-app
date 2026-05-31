//
//  BioFeedbackManager.swift
//  Echoelmusic — Core
//
//  Cross-process bridge for live vitals between the main app (producer) and
//  the AUv3 extension (consumer, separate process), over the shared App Group
//  container.
//
//  ── AUDIO-THREAD SAFETY (the whole point of this design) ──────────────────
//  `UserDefaults` access is ObjC messaging + file I/O + locking, which is
//  FORBIDDEN on the audio render thread (CLAUDE.md). So:
//    • Producer (app): call `publish(_:)` OFF the audio thread (e.g. ~1 Hz on
//      the main actor) to write the latest vitals into the App Group store.
//    • Consumer (AUv3): call `refreshFromSharedStore()` OFF the audio thread
//      (e.g. on the extension's UI/timer tick). It decodes the latest vitals
//      into lock-free, atomic-width `Float` fields.
//    • Render block: read ONLY the atomic fields (`heartRate`, `hrv`,
//      `breathPhase`, `coherence`) — never touch UserDefaults there. This
//      mirrors the BioReactiveSynthVoice param-sharing pattern already in use.
//
//  App Group: `group.com.echoelmusic` — matches both .entitlements files and
//  the identity on record (decisions.csv 2026-05-22). If the group ever moves
//  to `group.com.echoelmusic.app`, register it in App Store Connect and update
//  both entitlements FIRST, then change `appGroupIdentifier` here.
//

import Foundation

/// One snapshot of the vitals shared across processes.
public struct BioVitals: Codable, Sendable, Equatable {
    public var heartRateBPM: Float
    public var hrvNormalized: Float
    public var breathPhase: Float
    public var coherence: Float
    public var timestamp: TimeInterval

    public init(
        heartRateBPM: Float = 60,
        hrvNormalized: Float = 0.5,
        breathPhase: Float = 0,
        coherence: Float = 0.5,
        timestamp: TimeInterval = 0
    ) {
        self.heartRateBPM = heartRateBPM
        self.hrvNormalized = hrvNormalized
        self.breathPhase = breathPhase
        self.coherence = coherence
        self.timestamp = timestamp
    }
}

public final class BioFeedbackManager: @unchecked Sendable {

    /// Canonical App Group (see file header before changing).
    public static let appGroupIdentifier = "group.com.echoelmusic"
    private static let storageKey = "bioVitals.v1"

    private let defaults: UserDefaults?

    // MARK: - Atomic-width snapshot for the render thread
    // Float reads/writes are atomic-width on Apple platforms; the render block
    // reads these directly without locks (same contract as EchoelDDSP params).

    nonisolated(unsafe) public private(set) var heartRate: Float = 60
    nonisolated(unsafe) public private(set) var hrv: Float = 0.5
    nonisolated(unsafe) public private(set) var breathPhase: Float = 0
    nonisolated(unsafe) public private(set) var coherence: Float = 0.5

    /// `defaults` is nil if the App Group is not provisioned for this build
    /// (e.g. running without the entitlement) — all calls then no-op safely.
    public init(appGroup: String = BioFeedbackManager.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroup)
    }

    public var isAvailable: Bool { defaults != nil }

    // MARK: - Producer (app side) — call OFF the audio thread

    public func publish(_ vitals: BioVitals) {
        guard let defaults, let data = try? JSONEncoder().encode(vitals) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Consumer (extension side) — call OFF the audio thread

    /// Reads the latest shared vitals and folds them into the atomic fields the
    /// render thread reads. Returns the decoded vitals (nil if none/unavailable).
    @discardableResult
    public func refreshFromSharedStore() -> BioVitals? {
        guard let defaults,
              let data = defaults.data(forKey: Self.storageKey),
              let vitals = try? JSONDecoder().decode(BioVitals.self, from: data) else { return nil }
        heartRate = vitals.heartRateBPM
        hrv = vitals.hrvNormalized
        breathPhase = vitals.breathPhase
        coherence = vitals.coherence
        return vitals
    }
}

#if canImport(Observation)
import Observation

/// App-side producer: polls EngineBus's latest bio frame OFF the audio thread
/// (~1 Hz on the main actor) and publishes it to the App Group so the AUv3
/// extension can read it. Mirrors the OSCSender subscriber pattern.
@MainActor
@Observable
public final class BioFeedbackPublisher {

    @ObservationIgnored public let manager: BioFeedbackManager
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private let loop = PollingLoop()

    public init(manager: BioFeedbackManager = BioFeedbackManager()) {
        self.manager = manager
    }

    public func start(publishingFrom bus: EngineBus) {
        self.bus = bus
        loop.start(interval: .seconds(1)) { [weak self] in
            guard let self, let frame = self.bus?.latestBio else { return }
            self.manager.publish(BioVitals(
                heartRateBPM: frame.heartRateBPM,
                hrvNormalized: frame.hrvNormalized,
                breathPhase: frame.breathPhase,
                coherence: frame.coherence,
                timestamp: frame.timestamp
            ))
        }
    }

    public func stop() { loop.stop() }
}
#endif
