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
    public func start(publishing bus: EngineBus) async {
        guard !isPublishing else { return }
        isAuthorized = await engine.requestAuthorization()
        guard isAuthorized else {
            log.log(.warning, category: .audio, "HealthKitBioPublisher: not authorized")
            return
        }
        engine.startStreaming()
        isPublishing = true
        // Two callers can pass the guard above concurrently (isPublishing flips
        // only after the requestAuthorization await — e.g. the launch
        // startIfAlreadyAuthorized racing the first-bio-use start). Cancel any
        // earlier poll loop before replacing it so it can't leak uncancelled.
        task?.cancel()
        task = Task { @MainActor [weak self, weak bus] in
            while !Task.isCancelled {
                guard let self, let bus else { break }
                self.publishIfFresh(to: bus)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Launch-safe start: begins publishing ONLY when the Health permission sheet
    /// would NOT appear (already answered on an earlier run). On a fresh install
    /// this is a silent no-op — the ASK moves to the first real bio use (UX-3:
    /// the context-free sheet used to interrupt the very first studio render).
    /// Previously-granted users (Watch) keep their launch behavior unchanged.
    public func startIfAlreadyAuthorized(publishing bus: EngineBus) async {
        guard !isPublishing else { return }
        if await engine.authorizationRequestNeeded() {
            log.log(.info, category: .audio,
                    "HealthKitBioPublisher: authorization ask deferred to first bio use")
            return
        }
        await start(publishing: bus)
    }

    public func stop() {
        task?.cancel()
        task = nil
        engine.stopStreaming()
        isPublishing = false
    }

    // MARK: - Private

    /// Internal (not `private`) so `@testable` can drive it directly with an
    /// injected snapshot — the polling `start(publishing:)` path is timer-driven
    /// and not deterministically testable.
    func publishIfFresh(to bus: EngineBus) {
        guard engine.dataSource == .healthKit else { return }
        let snap = engine.snapshot
        guard snap.timestamp != lastTimestamp else { return }
        lastTimestamp = snap.timestamp

        // Stamp RECEIPT time, not the measurement time. EngineBus's freshness
        // windows (freshBio/usableBio) ask "how long ago did THIS app observe a
        // live reading?" — the contract at EngineBus.swift:266 says every publisher
        // (BLE, rPPG, Demo) stamps the CFAbsoluteTimeGetCurrent clock at receipt.
        // HealthKit publishes measurement-time snapshots that are already 4–5 s old
        // (Watch latency) and often minutes stale at rest; stamping THAT aged the
        // frame past even the 90 s wrist window, so the Watch was silently dropped
        // as a bio source. The :95 dedup stays on snap.timestamp (measurement time)
        // so we still publish once per NEW reading — only the freshness clock moves.
        bus.publish(bio: BioSampleFrame(
            timestamp: CFAbsoluteTimeGetCurrent(),
            heartRateBPM: Float(snap.heartRate),
            hrvNormalized: Float(snap.hrvNormalized),
            breathRate: Float(snap.breathRate),
            breathPhase: Float(snap.breathPhase),
            // HealthKit exposes averaged HR + SDNN, NOT beat-to-beat RR intervals,
            // so there is no trustworthy frequency-domain coherence to publish here
            // (the engine's legacy inverse-variance estimate is not a real spectral
            // coherence). Honest 0 = "not available from this source"; consistent
            // with BioSource.providesTrustedHRV == false for .healthKit. Real
            // coherence comes from the BLE/Polar and camera RR paths (HRVCoherence).
            coherence: 0,
            motionEnergy: 0,
            source: .healthKit,
            // HealthKit is a native SDNN source — carry the real ms so it is available
            // for on-device display / self-observation (previously left at 0). It does
            // NOT leave the device: BioEgressPolicy blocks HealthKit-sourced frames from
            // every network sender (OSC/ADM/Art-Net/sACN) per App Store 5.1.3. Declared
            // AFTER source: to match the BioSampleFrame init's parameter order (Xcode is
            // strict about this even though SwiftPM's checker accepted it out of order).
            hrvSDNNms: Float(snap.hrvSDNNms)
        ))
    }
}
#endif
