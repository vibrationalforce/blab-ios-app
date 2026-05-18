//
//  HealthKitBioPublisher.swift
//  Echoelmusic
//
//  Bridges EchoelBioEngine (HealthKit pipeline) onto EngineBus.
//  Polls the engine's snapshot at 500 ms and publishes a fresh
//  BioSampleFrame whenever the snapshot's timestamp advances AND
//  the engine's data source is .healthKit (real data flowing).
//
//  Fallback-mode frames from EchoelBioEngine are NOT republished —
//  the BioSimulator (DEBUG) or the "No source" empty state owns
//  that display until a real publisher arrives.
//

#if canImport(HealthKit)
import Foundation
import HealthKit
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class HealthKitBioPublisher {

    public private(set) var isAuthorized = false

    public private(set) var isPublishing = false

    @ObservationIgnored
    private let engine: EchoelBioEngine

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var lastTimestamp: Date?

    public init(engine: EchoelBioEngine = .shared) {
        self.engine = engine
    }

    /// Request HealthKit permission and begin polling the engine snapshot
    /// for fresh frames to publish onto the bus. Idempotent.
    public func start(publishing to bus: EngineBus) async {
        guard !isPublishing else { return }
        isAuthorized = await engine.requestAuthorization()
        guard isAuthorized else {
            log.log(.warning, category: .audio, "HealthKitBioPublisher: not authorized")
            return
        }
        engine.startStreaming()
        isPublishing = true
        task = Task { @MainActor [weak self, weak bus] in
            while !Task.isCancelled {
                guard let self, let bus else { break }
                self.publishIfFresh(to: bus)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        engine.stopStreaming()
        isPublishing = false
    }

    // MARK: - Private

    private func publishIfFresh(to bus: EngineBus) {
        guard engine.dataSource == .healthKit else { return }
        let snap = engine.snapshot
        guard snap.timestamp != lastTimestamp else { return }
        lastTimestamp = snap.timestamp

        bus.publish(bio: BioSampleFrame(
            timestamp: snap.timestamp.timeIntervalSinceReferenceDate,
            heartRateBPM: Float(snap.heartRate),
            hrvNormalized: Float(snap.hrvNormalized),
            breathRate: Float(snap.breathRate),
            breathPhase: Float(snap.breathPhase),
            coherence: Float(snap.coherence),
            motionEnergy: 0,
            source: .healthKit
        ))
    }
}
#endif
