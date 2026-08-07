//
//  HealthKitWriter.swift
//  Echoelmusic — Bio
//
//  Opt-in "Works with Apple Health" WRITE path: when the user turns it on,
//  Echoel saves the heart rate + respiratory rate IT measures (camera rPPG / BLE
//  strap) into Apple Health, so those readings live alongside the rest of the
//  user's health data. Off by default; decisions live in HealthWritePolicy
//  (pure, unit-tested). Never writes HRV, and never echoes HealthKit/Watch data
//  back (non-circular — see HealthWritePolicy).
//
//  ⛔ "(we don't have real SDNN ms)" STOOD HERE AS THE REASON FOR THE HRV HALF
//  AND WAS FALSE (#463): three producers write real SDNN in ms into
//  `BioSampleFrame.hrvSDNNms`. The DECISION stands; its reason lives in
//  `HealthWritePolicy` rule 2 and is not restated here, because one decision
//  with two written reasons is how this one drifted in the first place (#416).
//  If you came here to add `heartRateVariabilitySDNN` to `toShare:` or a sample
//  to `write(_:)`, read that rule first — `HRVIsNotWrittenToHealthTests` will
//  go red, on purpose.
//

#if canImport(HealthKit)
import Foundation
import HealthKit
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class HealthKitWriter {

    /// User opt-in. Persisted; turning it on requests write authorization.
    public var enabled: Bool {
        didSet {
            guard oldValue != enabled else { return }
            UserDefaults.standard.set(enabled, forKey: Self.flagKey)
            if enabled { Task { await requestAuthorization() } }
        }
    }

    public private(set) var isAuthorized = false

    @ObservationIgnored private static let flagKey = "health.write.enabled"
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastWriteAt: TimeInterval = 0

    public init() {
        self.enabled = UserDefaults.standard.bool(forKey: Self.flagKey)
    }

    /// Begin a slow poll of the live bio snapshot; writes only when enabled +
    /// authorized + the policy allows (no-op and near-zero cost when off).
    public func start(reading bus: EngineBus) {
        guard task == nil else { return }
        if enabled { Task { await requestAuthorization() } }
        task = Task { @MainActor [weak self, weak bus] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let bus else { break }
                guard self.enabled else { continue }
                self.writeIfAllowed(bus.freshBio())
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }

    /// Ask the user to allow writing HR + respiratory rate. Read auth is handled
    /// separately by EchoelBioEngine; sharing uses the same healthkit entitlement.
    public func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let hr = HKObjectType.quantityType(forIdentifier: .heartRate),
              let resp = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else { return }
        do {
            try await store.requestAuthorization(toShare: [hr, resp], read: [])
            isAuthorized = true
        } catch {
            isAuthorized = false
            log.log(.warning, category: .audio, "HealthKitWriter: authorization failed")
        }
    }

    private func writeIfAllowed(_ frame: BioSampleFrame?) {
        let now = Date().timeIntervalSinceReferenceDate
        guard HealthWritePolicy.shouldWrite(frame: frame, enabled: enabled,
                                            authorized: isAuthorized,
                                            lastWriteAt: lastWriteAt, now: now),
              let frame else { return }
        lastWriteAt = now
        write(frame)
    }

    private func write(_ frame: BioSampleFrame) {
        let date = Date()
        let (hr, resp) = HealthWritePolicy.values(for: frame)
        var samples: [HKQuantitySample] = []
        let meta: [String: Any] = [HKMetadataKeyWasUserEntered: false]

        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            samples.append(HKQuantitySample(type: hrType,
                                            quantity: HKQuantity(unit: bpm, doubleValue: hr),
                                            start: date, end: date, metadata: meta))
        }
        if let resp, let respType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            let perMin = HKUnit.count().unitDivided(by: .minute())
            samples.append(HKQuantitySample(type: respType,
                                            quantity: HKQuantity(unit: perMin, doubleValue: resp),
                                            start: date, end: date, metadata: meta))
        }
        guard !samples.isEmpty else { return }
        // Best-effort, fire-and-forget (a failed write must never disrupt the app).
        store.save(samples) { _, _ in }
    }
}
#endif
