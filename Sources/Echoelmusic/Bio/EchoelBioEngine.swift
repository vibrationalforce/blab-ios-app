#if canImport(HealthKit)
//
//  EchoelBioEngine.swift
//  Echoelmusic — Real Biofeedback Engine
//
//  HealthKit integration for real physiological data:
//  - Heart Rate (HR) from Apple Watch / chest strap
//  - Heart Rate Variability (HRV) — HealthKit's own SDNN. Apple exposes averaged HR
//    + SDNN, NOT beat-to-beat RR, so NO time-domain RMSSD is derived here (real RR
//    HRV comes from the BLE strap via PolarH10BioPublisher).
//  - Breathing Rate (iOS 17+)
//
//  Replaces the mic-audio-level proxy in EchoelCreativeWorkspace.
//
//  IMPORTANT: Not a medical device. Data for self-observation only.
//

import Foundation
import HealthKit
#if canImport(Observation)
import Observation
#endif
#if canImport(Combine)
import Combine
#endif

// MARK: - Bio Data Snapshot

/// Current physiological state — updated from HealthKit or fallback
public struct BioSnapshot: Sendable {
    /// Heart rate in BPM [40-200]
    public var heartRate: Double = 72.0

    /// HRV normalized to [0-1] — from HealthKit's SDNN (the BLE strap path provides
    /// true beat-to-beat RMSSD; HealthKit does not, so no RMSSD is derived here).
    ///
    /// DEFAULT 0 = "no HRV has been measured yet", the same convention
    /// `HRVNormalization.normalize` already uses for unusable input and that the strip
    /// renders as "—". It used to default to 0.5, and that was not a harmless
    /// placeholder: `publishIfFresh` fires as soon as a HEART-RATE sample arrives (the
    /// snapshot's timestamp is only written on that path), so a Watch with no SDNN
    /// sample yet published an invented "medium HRV" as a real reading — driving
    /// brightness, humanisation and the displayed figure off a number nobody measured.
    public var hrvNormalized: Double = 0

    /// Raw RMSSD in milliseconds (BLE-strap path only; NOT written on the HealthKit
    /// path, which has no beat-to-beat RR — HealthKit HRV flows via `hrvNormalized`).
    /// 0 = not measured, as everywhere else.
    public var hrvRMSSD: Double = 0

    /// Raw SDNN in milliseconds. HealthKit IS a native SDNN source (it exposes SDNN
    /// directly), so this carries the real ms value out to `/echoelmusic/bio/heart/sdnn`
    /// — the normalized [0,1] field clamps at the 100 ms ceiling and cannot recover it.
    /// 0 = not provided by the source.
    public var hrvSDNNms: Double = 0

    /// Breathing rate in breaths/min [4-30]. 0 = not measured — HealthKit only has a
    /// respiratory rate when the user tracks sleep, so the old 12.0 default published a
    /// textbook average as an observation for most people. `PolarH10BioPublisher` already
    /// sends 0 for the same "this source has no breath" case.
    public var breathRate: Double = 0

    /// Breath phase [0-1] (0=exhale start, 0.5=inhale start, 1=exhale start).
    ///
    /// ⚠ Stays 0.5, and that IS still a placeholder: HealthKit measures no phase at all,
    /// and unlike the fields above `breathPhase` has no "unknown" sentinel — 0 is a
    /// meaningful value (exhale start), so an honest default cannot be expressed in this
    /// type. It only feeds slow visual position (donut sway, `BioVisualParams`), never a
    /// number shown as a measurement. Giving `BioSampleFrame.breathPhase` a real optional
    /// is a cross-cutting change and belongs in its own slice.
    public var breathPhase: Double = 0.5

    /// Coherence score [0-1]. 0 = not measured. `HealthKitBioPublisher` already
    /// hard-codes 0 on the wire (HealthKit has no beat-to-beat RR, so no real spectral
    /// coherence exists there); this makes the in-engine default agree with it.
    public var coherence: Double = 0

    /// LF/HF ratio of HRV spectrum
    public var lfHfRatio: Double = 1.0

    /// Data source description
    public var source: BioDataSource = .fallback

    /// Timestamp
    public var timestamp: Date = Date()
}

/// Where bio data is coming from
public enum BioDataSource: String, Sendable {
    case healthKit = "HealthKit"
    case appleWatch = "Apple Watch"
    case chestStrap = "Chest Strap"
    case camera = "Camera rPPG"
    case ouraRing = "Oura Ring"
    case arkit = "ARKit Face"
    case microphone = "Microphone"
    case fallback = "Simulated"
}

// MARK: - EchoelBioEngine

/// Real biofeedback engine with HealthKit integration
@preconcurrency @MainActor
@Observable
public final class EchoelBioEngine {

    // MARK: - Singleton

    @MainActor public static let shared = EchoelBioEngine()

    // MARK: - Published State

    public var snapshot: BioSnapshot = BioSnapshot()
    public var isAuthorized: Bool = false
    public var isStreaming: Bool = false
    public var dataSource: BioDataSource = .fallback

    /// Smoothed values for audio thread (EMA with ~100ms window)
    public var smoothHeartRate: Double = 72.0
    public var smoothHRV: Double = 0.5
    public var smoothCoherence: Double = 0.5
    public var smoothBreathPhase: Double = 0.5
    public var smoothBreathDepth: Double = 0.5

    // MARK: - HealthKit

    private var healthStore: HKHealthStore?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var hrvQuery: HKAnchoredObjectQuery?
    private var breathRateQuery: HKAnchoredObjectQuery?
    private var cancellables = Set<AnyCancellable>()
    private var breathTimerCancellable: AnyCancellable?

    // MARK: - HRV Calculation

    /// Smoothing factor (higher = smoother, more latency)
    private let smoothingAlpha: Double = 0.15

    /// Has a REAL sample of each kind arrived yet? The smoothers start at nominal
    /// placeholders, so the first genuine reading must replace the seed rather than be
    /// averaged with it — otherwise ~85 % of an invented value survives into what the
    /// user is told is a measurement.
    private var hasHRSample = false
    private var hasHRVSample = false

    // MARK: - Constants

    /// Apple Watch HR latency is ~4-5 seconds — don't use for beat-sync
    private let appleWatchHRLatency: TimeInterval = 4.5

    // HRV normalization now lives in ONE shared source of truth (HRVNormalization) so the
    // camera, BLE strap, and HealthKit all map onto the same [0,1] ceiling — the old
    // per-source divisors (and this constant's RMSSD-vs-SDNN naming mix-up) are gone.

    // MARK: - Init

    private init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        }
    }

    // MARK: - Authorization

    /// Request HealthKit permissions
    public func requestAuthorization() async -> Bool {
        guard let healthStore = healthStore else {
            log.log(.warning, category: .audio, "HealthKit not available on this device")
            return false
        }

        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let brType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else {
            log.log(.warning, category: .audio, "HealthKit quantity types unavailable")
            isAuthorized = false
            return false
        }
        let readTypes: Set<HKObjectType> = [hrType, hrvType, brType]

        do {
            try await healthStore.requestAuthorization(toShare: Set(), read: readTypes)
            // requestAuthorization does NOT throw when user denies — check actual status
            let hrStatus = healthStore.authorizationStatus(for: hrType)
            let authorized = hrStatus == .sharingAuthorized || hrStatus == .notDetermined
            // Note: .notDetermined means user hasn't been asked yet for this specific type,
            // but after requestAuthorization it means sharing wasn't requested (read-only).
            // For read types, Apple hides denial — we detect via query returning no data.
            // Best-effort: check if at least heart rate is readable.
            isAuthorized = authorized
            if authorized {
                log.log(.info, category: .audio, "HealthKit authorization granted")
            } else {
                log.log(.warning, category: .audio, "HealthKit authorization denied by user")
            }
            return authorized
        } catch {
            log.log(.error, category: .audio, "HealthKit authorization failed: \(error.localizedDescription)")
            isAuthorized = false
            return false
        }
    }

    /// Whether calling `requestAuthorization()` would present the system Health
    /// permission sheet right now (UX-3: launch must NEVER prompt — only a real,
    /// user-initiated bio moment may). Best-effort: unknown/error counts as
    /// "would prompt" so the caller defers instead of surprising the user.
    public func authorizationRequestNeeded() async -> Bool {
        guard let healthStore = healthStore else { return false }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let brType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else {
            return false
        }
        let readTypes: Set<HKObjectType> = [hrType, hrvType, brType]
        do {
            let status = try await healthStore.statusForAuthorizationRequest(toShare: [], read: readTypes)
            return status != .unnecessary
        } catch {
            log.log(.warning, category: .audio,
                    "HealthKit authorization status check failed: \(error.localizedDescription)")
            return true
        }
    }

    // MARK: - Streaming

    /// Start real-time bio data streaming
    public func startStreaming() {
        guard !isStreaming else { return }

        if let healthStore = healthStore, isAuthorized {
            startHeartRateQuery(healthStore: healthStore)
            startHRVQuery(healthStore: healthStore)
            startBreathRateQuery(healthStore: healthStore)
            dataSource = .healthKit
        } else {
            dataSource = .fallback
            startFallbackMode()
        }

        isStreaming = true
        log.log(.info, category: .audio, "Bio streaming started — source: \(dataSource.rawValue)")
    }

    /// Stop streaming
    public func stopStreaming() {
        guard isStreaming else { return }

        if let healthStore = healthStore {
            if let query = heartRateQuery { healthStore.stop(query) }
            if let query = hrvQuery { healthStore.stop(query) }
            if let query = breathRateQuery { healthStore.stop(query) }
        }
        heartRateQuery = nil
        hrvQuery = nil
        breathRateQuery = nil
        cancellables.removeAll()
        breathTimerCancellable?.cancel()
        breathTimerCancellable = nil

        isStreaming = false
        log.log(.info, category: .audio, "Bio streaming stopped")
    }

    // MARK: - HealthKit Queries

    private func startHeartRateQuery(healthStore: HKHealthStore) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        // Look back an hour, not 60 s: the Apple Watch writes resting HR to HealthKit
        // only sporadically (minutes apart), so a 60 s window usually returns NOTHING
        // on start and the wrist appears dead. The anchored query takes the most
        // recent sample (processHeartRateSamples uses .last) and then live-updates as
        // new samples sync — so the latest known HR surfaces immediately.
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-3600),
            end: nil,
            options: .strictStartDate
        )

        heartRateQuery = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        heartRateQuery?.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        if let query = heartRateQuery {
            healthStore.execute(query)
        }
    }

    private func startHRVQuery(healthStore: HKHealthStore) {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-300),
            end: nil,
            options: .strictStartDate
        )

        hrvQuery = HKAnchoredObjectQuery(
            type: hrvType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHRVSamples(samples)
        }

        hrvQuery?.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHRVSamples(samples)
        }

        if let query = hrvQuery {
            healthStore.execute(query)
        }
    }

    private func startBreathRateQuery(healthStore: HKHealthStore) {
        guard let breathType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else { return }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-300),
            end: nil,
            options: .strictStartDate
        )

        breathRateQuery = HKAnchoredObjectQuery(
            type: breathType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processBreathRateSamples(samples)
        }

        breathRateQuery?.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processBreathRateSamples(samples)
        }

        if let query = breathRateQuery {
            healthStore.execute(query)
        }
    }

    // MARK: - Sample Processing

    private nonisolated func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }

        // Newest by date — anchored-query results aren't guaranteed date-sorted, and
        // the widened (1 h) window can return several samples, so .last could be stale.
        guard let latestSample = quantitySamples.max(by: { $0.endDate < $1.endDate }) else { return }
        let bpm = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        // Guard against invalid HR values
        guard bpm >= 30 && bpm <= 220 else { return }

        // NOTE: HealthKit heart-rate samples are AVERAGED BPM, not beat-to-beat RR
        // intervals — so we do NOT derive RR = 60000/HR and run RMSSD over it. That is
        // physiologically meaningless: a steady resting HR yields ~0 "RMSSD" = a false
        // "dead HRV". Real time-domain HRV (RMSSD) comes from the BLE strap
        // (PolarH10BioPublisher). This path tracks HR only; the honest HealthKit HRV
        // signal is its own SDNN (see processHRVSamples).
        let sampleDate = latestSample.startDate

        // HealthKit callbacks fire on background thread — hop to MainActor safely
        DispatchQueue.main.async {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.snapshot.heartRate = bpm
                self.snapshot.timestamp = sampleDate
                // Same seed-don't-blend rule as HRV below: `smoothHeartRate` starts at
                // a nominal 72, and blending from it would report a first reading that
                // is mostly that nominal value.
                if !self.hasHRSample {
                    self.smoothHeartRate = bpm
                    self.hasHRSample = true
                }
                self.smoothHeartRate = self.smoothHeartRate * (1.0 - self.smoothingAlpha) + bpm * self.smoothingAlpha
            }
        }
    }

    private nonisolated func processHRVSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }

        guard let latestSample = quantitySamples.last else { return }
        let sdnn = latestSample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))

        // Guard against invalid HRV values
        guard sdnn >= 0 && sdnn <= 500 else { return }

        DispatchQueue.main.async {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                // HealthKit's real HRV is SDNN (it does not expose beat-to-beat RR),
                // so SDNN drives the normalized HRV directly. (This used to be gated
                // behind "not enough RR intervals" and then overridden by a fabricated
                // RMSSD computed from averaged HR — that fabrication has been removed.)
                let normalized = HRVNormalization.normalize(sdnn)
                self.snapshot.hrvNormalized = normalized
                // Carry the real SDNN ms too — HealthKit is a native SDNN source, so the
                // raw value is available for ON-DEVICE display / self-observation (the
                // normalized [0,1] field clamps at the 100 ms ceiling and loses it).
                // NOTE: HealthKit-sourced frames are network-egress-blocked upstream by
                // BioEgressPolicy (App Store 5.1.3), so this value stays on-device.
                self.snapshot.hrvSDNNms = sdnn
                // SEED, don't blend, on the first real sample. `smoothHRV` starts at a
                // placeholder, and an EMA from a placeholder means the first genuine
                // reading is reported as mostly-placeholder (α = 0.15, so ~85 % of the
                // invented value survives the first sample and it takes ~15 samples to
                // wash out). Jumping to the first measurement makes the smoother a
                // smoother of REAL data instead of a slow leak of a made-up one.
                self.smoothHRV = self.hasHRVSample
                    ? self.smoothHRV * (1.0 - self.smoothingAlpha) + normalized * self.smoothingAlpha
                    : normalized
                self.hasHRVSample = true
            }
        }
    }

    private nonisolated func processBreathRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }

        guard let latestSample = quantitySamples.last else { return }
        let rate = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        // Guard against invalid breath rate
        guard rate >= 2 && rate <= 60 else { return }

        DispatchQueue.main.async {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.snapshot.breathRate = rate
            }
        }
    }

    // NOTE: The former `calculateRMSSD()` / `calculateCoherence()` pair was removed
    // (#98c1). Both ran over RR intervals fabricated from HealthKit's AVERAGED HR
    // (RR = 60000/HR), which is not beat-to-beat data — so the resulting RMSSD and
    // coherence were physiologically meaningless and, worse, overrode the real SDNN.
    // HealthKit HRV now flows honestly as SDNN (processHRVSamples); real RMSSD/coherence
    // come from the BLE strap path (PolarH10BioPublisher), consistent with
    // `BioSource.providesTrustedHRV == false` for HealthKit. (The RMSSD/coherence math
    // itself remains covered by the algorithm tests in BioEngineTests, fed real RR.)

    // MARK: - Fallback Mode (Mic Level Proxy)

    /// When HealthKit unavailable, use microphone RMS as coherence proxy
    private func startFallbackMode() {
        // Cancel any existing breath timer to prevent accumulation
        breathTimerCancellable?.cancel()
        // Simulate slow bio oscillation for demo/preview purposes
        let breathTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()
        breathTimerCancellable = breathTimer.sink { [weak self] _ in
            guard let self = self else { return }
            let t = Date().timeIntervalSinceReferenceDate

            // Breath: sinusoidal at ~12 breaths/min
            let breathPhase = (12.0 / 60.0) * 2.0 * Double.pi
            self.snapshot.breathPhase = (sin(t * breathPhase) + 1.0) / 2.0
            self.smoothBreathPhase = self.snapshot.breathPhase

            // Heart rate: gentle drift around 68 BPM (slow sine, ~0.05 Hz)
            self.snapshot.heartRate = 68.0 + sin(t * 0.05 * 2.0 * Double.pi) * 4.0
            self.smoothHeartRate = self.snapshot.heartRate

            // Coherence: slow drift around 0.55 (very slow, ~0.02 Hz)
            self.snapshot.coherence = 0.55 + sin(t * 0.02 * 2.0 * Double.pi) * 0.15
            self.smoothCoherence = self.snapshot.coherence

            // HRV: slow drift around 0.5
            self.snapshot.hrvNormalized = 0.5 + sin(t * 0.03 * 2.0 * Double.pi) * 0.1
            self.smoothHRV = self.snapshot.hrvNormalized
        }
    }

    // MARK: - Bio → Audio Parameter Bridge

    /// Get current bio parameters for audio engine consumption
    public func audioParameters() -> (coherence: Float, hrv: Float, heartRate: Float, breathPhase: Float, breathDepth: Float) {
        return (
            coherence: Float(smoothCoherence),
            hrv: Float(smoothHRV),
            heartRate: Float(smoothHeartRate),
            breathPhase: Float(smoothBreathPhase),
            breathDepth: Float(smoothBreathDepth)
        )
    }
}

#else
// Non-HealthKit platforms (macOS, Linux)
import Foundation
#if canImport(Observation)
import Observation
#endif

// Keep these defaults in step with the HealthKit-platform `BioSnapshot` above —
// 0 means "not measured" for every field that has an unknown state.
public struct BioSnapshot: Sendable {
    public var heartRate: Double = 72.0
    public var hrvNormalized: Double = 0
    public var hrvRMSSD: Double = 0
    public var hrvSDNNms: Double = 0
    public var breathRate: Double = 0
    public var breathPhase: Double = 0.5   // no unknown sentinel exists — see above
    public var coherence: Double = 0
    public var lfHfRatio: Double = 1.0
    public var source: BioDataSource = .fallback
    public var timestamp: Date = Date()
}

public enum BioDataSource: String, Sendable {
    case healthKit = "HealthKit"
    case appleWatch = "Apple Watch"
    case chestStrap = "Chest Strap"
    case camera = "Camera rPPG"
    case ouraRing = "Oura Ring"
    case arkit = "ARKit Face"
    case microphone = "Microphone"
    case fallback = "Simulated"
}

@preconcurrency @MainActor
@Observable
public final class EchoelBioEngine {
    @MainActor public static let shared = EchoelBioEngine()
    public var snapshot: BioSnapshot = BioSnapshot()
    public var isAuthorized: Bool = false
    public var isStreaming: Bool = false
    public var dataSource: BioDataSource = .fallback
    public var smoothCoherence: Double = 0.5
    public var smoothHRV: Double = 0.5
    public var smoothHeartRate: Double = 72.0
    public var smoothBreathPhase: Double = 0.5
    public var smoothBreathDepth: Double = 0.5
    private init() {}

    public func requestAuthorization() async -> Bool { false }
    public func authorizationRequestNeeded() async -> Bool { false }
    public func startStreaming() { isStreaming = true }
    public func stopStreaming() { isStreaming = false }

    public func audioParameters() -> (coherence: Float, hrv: Float, heartRate: Float, breathPhase: Float, breathDepth: Float) {
        (Float(smoothCoherence), Float(smoothHRV), Float(smoothHeartRate), Float(smoothBreathPhase), Float(smoothBreathDepth))
    }
}
#endif
