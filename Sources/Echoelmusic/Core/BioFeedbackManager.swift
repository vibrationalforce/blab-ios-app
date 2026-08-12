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
//    • Producer (app): call `publish(_:)` OFF the audio thread (≤10 Hz on the
//      main actor — the shared poll tick) to write the latest vitals into the
//      App Group store.
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
    /// Normalized HRV [0…1]. `0` means **not measured** — same convention as
    /// `BioSampleFrame.hrvNormalized`, which this mirrors across processes.
    public var hrvNormalized: Float
    public var breathPhase: Float
    /// Coherence [0…1]. `0` means **not measured** (too few beats to run the
    /// spectral estimate), not "maximally incoherent".
    public var coherence: Float
    /// `timeIntervalSinceReferenceDate` (== CFAbsoluteTimeGetCurrent) of the
    /// source frame — the SAME wall clock in every process, so the AUv3
    /// extension can compare it against its own `Date()` for freshness.
    public var timestamp: TimeInterval
    /// Breathing rate in breaths/min (`0` = not available). Added 2026-07-17;
    /// absent in v1 payloads (see `init(from:)`).
    public var breathRate: Float
    /// Whether this snapshot may surface OUTSIDE first-party Echoel processes —
    /// concretely: the AUv3 pushes vitals into HOST-VISIBLE AUParameters, which
    /// a third-party host (GarageBand/Logic/AUM) can read and record. App Store
    /// 5.1.3: HealthKit-store data must never take that path, so the app marks
    /// frames with `BioEgressPolicy.allowsEgress(source)` — the same rule OSC
    /// applies. First-party readers (Widget, Watch) ignore this flag.
    /// Absent in v1 payloads ⇒ decodes FALSE (privacy-safe: an old app version
    /// may have written HealthKit-sourced vitals unmarked).
    public var egressAllowed: Bool

    /// Defaults describe an UNMEASURED body, not an average one: `hrvNormalized`
    /// and `coherence` default to 0 ("not measured") rather than the old 0.5, which
    /// was a fabricated mid-scale reading that the Widget and the Watch printed as
    /// "50%". `heartRateBPM` keeps a positive placeholder because 0 BPM is not a
    /// readable state for the surfaces that divide by it; those surfaces gate on
    /// their own has-data flag before showing any number at all.
    public init(
        heartRateBPM: Float = 60,
        hrvNormalized: Float = 0,
        breathPhase: Float = 0,
        coherence: Float = 0,
        timestamp: TimeInterval = 0,
        breathRate: Float = 0,
        egressAllowed: Bool = false
    ) {
        self.heartRateBPM = heartRateBPM
        self.hrvNormalized = hrvNormalized
        self.breathPhase = breathPhase
        self.coherence = coherence
        self.timestamp = timestamp
        self.breathRate = breathRate
        self.egressAllowed = egressAllowed
    }

    private enum CodingKeys: String, CodingKey {
        case heartRateBPM, hrvNormalized, breathPhase, coherence, timestamp
        case breathRate, egressAllowed
    }

    /// Backward-compatible decode: v1 payloads (shipped builds before
    /// 2026-07-17) lack `breathRate`/`egressAllowed`. Missing breathRate ⇒ 0
    /// ("not available"); missing egressAllowed ⇒ false (never host-visible).
    /// Encoding stays synthesized (always writes both fields).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heartRateBPM = try c.decode(Float.self, forKey: .heartRateBPM)
        hrvNormalized = try c.decode(Float.self, forKey: .hrvNormalized)
        breathPhase = try c.decode(Float.self, forKey: .breathPhase)
        coherence = try c.decode(Float.self, forKey: .coherence)
        timestamp = try c.decode(TimeInterval.self, forKey: .timestamp)
        breathRate = try c.decodeIfPresent(Float.self, forKey: .breathRate) ?? 0
        egressAllowed = try c.decodeIfPresent(Bool.self, forKey: .egressAllowed) ?? false
    }

    /// All numeric fields are finite. A corrupted cross-process payload must
    /// never reach synth parameters — a NaN there is a permanently stuck /
    /// silent oscillator (same failure class BioReactiveSynthVoice guards).
    public var payloadIsFinite: Bool {
        heartRateBPM.isFinite && hrvNormalized.isFinite && breathPhase.isFinite
            && coherence.isFinite && breathRate.isFinite && timestamp.isFinite
    }

    /// Whether this snapshot is recent enough to treat as LIVE. Age is measured
    /// on the shared `timeIntervalSinceReferenceDate` clock; a small negative
    /// age is tolerated for cross-process clock jitter, anything more
    /// "from the future" is rejected — mirrors `EngineBus.freshBio`.
    ///
    /// ⛔ "mirrors" was the whole problem until #545: the sentence pointed at
    /// `EngineBus.freshBio` while the code below restated its `-1` as a literal, so the
    /// two could drift apart and the doc would still read correctly. It now ASKS
    /// `BioSource.futureSkewTolerance`, which is what "mirrors" was always claiming.
    /// The parenthetical "(≥ −1 s)" is gone with it — a doc that spells the number is a
    /// seventh copy of the decision, the same way `ColabPayload`'s was.
    public func isFresh(
        within maxAge: TimeInterval = 2,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> Bool {
        let age = now - timestamp
        return age <= maxAge && age >= -BioSource.futureSkewTolerance
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
              let vitals = try? JSONDecoder().decode(BioVitals.self, from: data),
              vitals.payloadIsFinite else { return nil }
        heartRate = vitals.heartRateBPM
        hrv = vitals.hrvNormalized
        breathPhase = vitals.breathPhase
        coherence = vitals.coherence
        return vitals
    }
}
