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

    /// Whether these numbers came from the DEMO generator rather than a body.
    /// `nil` means the writer did not say — the same three-state encoding
    /// `ColabPayload.BioPeek.synthetic` uses for a peer (#629), and for the same
    /// reason: a glanceable surface must be able to distinguish "measured" from
    /// "unknown" instead of folding both into `false`. `true` ⇒ the reader marks it.
    ///
    /// ⭐ WHY `Bool?` HERE WHEN `egressAllowed` NEXT DOOR IS A PLAIN `Bool`: that one
    /// fails CLOSED — an absent value must mean "refuse egress", so `false` is the
    /// safe reading of silence. This one has no safe `false`: reading silence as
    /// "measured" prints a demo pulse as the user's, and reading it as "demo" brands
    /// a real reading fake. Neither direction is safe, so silence stays silence.
    ///
    /// ⛔ IT CANNOT BE A `BioSource`. This file is compiled STANDALONE into
    /// `EchoelmusicWidgets` and `EchoelmusicWatch` (see the `isFresh` note below);
    /// `BioSource` does not exist in either target. The app-side mapping in
    /// `BioFeedbackPublisher.vitals(from:)` is where the source is read.
    public var synthetic: Bool?

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
        egressAllowed: Bool = false,
        synthetic: Bool? = nil
    ) {
        self.heartRateBPM = heartRateBPM
        self.hrvNormalized = hrvNormalized
        self.breathPhase = breathPhase
        self.coherence = coherence
        self.timestamp = timestamp
        self.breathRate = breathRate
        self.egressAllowed = egressAllowed
        self.synthetic = synthetic
    }

    private enum CodingKeys: String, CodingKey {
        case heartRateBPM, hrvNormalized, breathPhase, coherence, timestamp
        case breathRate, egressAllowed, synthetic
    }

    /// Backward-compatible decode: v1 payloads (shipped builds before
    /// 2026-07-17) lack `breathRate`/`egressAllowed`. Missing breathRate ⇒ 0
    /// ("not available"); missing egressAllowed ⇒ false (never host-visible);
    /// missing `synthetic` ⇒ **nil**, which is "unknown", not "measured".
    /// Encoding stays synthesized (a nil `synthetic` is simply omitted).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heartRateBPM = try c.decode(Float.self, forKey: .heartRateBPM)
        hrvNormalized = try c.decode(Float.self, forKey: .hrvNormalized)
        breathPhase = try c.decode(Float.self, forKey: .breathPhase)
        coherence = try c.decode(Float.self, forKey: .coherence)
        timestamp = try c.decode(TimeInterval.self, forKey: .timestamp)
        breathRate = try c.decodeIfPresent(Float.self, forKey: .breathRate) ?? 0
        egressAllowed = try c.decodeIfPresent(Bool.self, forKey: .egressAllowed) ?? false
        synthetic = try c.decodeIfPresent(Bool.self, forKey: .synthetic)   // absent ⇒ nil, NOT false
    }

    /// All numeric fields are finite. A corrupted cross-process payload must
    /// never reach synth parameters — a NaN there is a permanently stuck /
    /// silent oscillator (same failure class BioReactiveSynthVoice guards).
    public var payloadIsFinite: Bool {
        heartRateBPM.isFinite && hrvNormalized.isFinite && breathPhase.isFinite
            && coherence.isFinite && breathRate.isFinite && timestamp.isFinite
    }

    /// The window a GLANCE must use — an UPPER BOUND, derived rather than chosen.
    ///
    /// `isFresh`'s 2 s default below is a wire window: right for a live in-app read, useless on
    /// a Home-Screen widget or a watch face, which render whenever the system decides. Those
    /// surfaces need ONE window covering every source, because this payload carries no
    /// `BioSource` — see the ⛔ note on `isFresh` for why the TYPE cannot travel into those
    /// targets. So the value is the largest window the engine itself still believes:
    /// `BioSource.freshnessWindow` is 6 s for camera/BLE/face and **90 s for
    /// `.watch`/`.healthKit`**, of which `.healthKit` is the one with a producer
    /// (`Bio/HealthKitBioPublisher`); `.watch` shares the number. `.oura`'s 600 s is excluded
    /// because it has no producer at all — `Sequencer/BreathHold.swift` records the same
    /// exclusion for the same reason.
    ///
    /// ⛔ IT IS A BOUND, NOT AN AGREEMENT, and the first draft of this comment claimed the
    /// stronger thing — "at 90 s the glance agrees with `EngineBus.usableBio` exactly". It does
    /// not: `usableBio` is PER-SOURCE, so a camera-rPPG payload — the app's own headline live
    /// pipeline — is dropped by the engine at 6 s and still reads current here for another 84.
    /// What 90 guarantees is the safe direction only: **it can never mark a live reading
    /// stale.** The over-claim is exactly the kind this comment then warned against two
    /// sentences later ("a hand-picked margin would open a band nobody could explain"), while
    /// opening a 6→90 s band on the default source.
    ///
    /// ⭐ THE BETTER FIX IS A SLICE, NOT A NUMBER, and it is not blocked by anything: the
    /// TYPE cannot cross into the extension targets, but the WINDOW is a `TimeInterval` and
    /// can. `BioVitals` already gained `synthetic: Bool?` this way (#632, `decodeIfPresent`,
    /// backward-compatible), so a `sourceFreshnessWindow: TimeInterval?` written by
    /// `BioFeedbackPublisher.vitals(from:)` as `frame.source.freshnessWindow` would make the
    /// glance agree with the engine for real. The first draft called that impossible; it is
    /// merely unbuilt, and saying "impossible" would have taken the decision away from whoever
    /// reads this next.
    ///
    /// ⚠️ THE NUMBER IS A LITERAL HERE for the same structural reason `isFresh`'s `-1` is
    /// (#545): `Core/EngineBus.swift`, where `freshnessWindow` lives, is in neither extension
    /// target. `TheGlanceSaysWhetherItIsCurrentTests` pins this to 90 AND pins the case in
    /// `EngineBus` it is copied from, so the day that source window moves this goes red
    /// instead of quietly meaning something else.
    public static let glanceFreshnessWindow: TimeInterval = 90

    /// Whether this snapshot is recent enough to treat as LIVE. Age is measured
    /// on the shared `timeIntervalSinceReferenceDate` clock; a small negative
    /// age is tolerated for cross-process clock jitter, anything more
    /// "from the future" is rejected — mirrors `EngineBus.freshBio`.
    ///
    /// ⛔ THIS FILE IS THE ONE SITE THAT CANNOT ASK `BioSource.futureSkewTolerance`, and the
    /// reason is structural rather than stylistic (#545, learned from a red compile, not from
    /// a rule): this file is compiled STANDALONE into two other targets —
    /// `project.yml` lists `Sources/Echoelmusic/Core/BioFeedbackManager.swift` under
    /// `EchoelmusicWidgets` and under `EchoelmusicWatch`, both of which pull in this ONE file
    /// and none of `Core/EngineBus.swift`. `BioSource` does not exist there. Converting this
    /// line produced exactly that: `error: cannot find 'BioSource' in scope`, twice.
    ///
    /// ⭐ SO THE LITERAL STAYS, and #545's own argument against a second copy is what makes
    /// this an exception rather than a hole. That argument was: "keep a second literal because
    /// two phones are not clock-synchronised" is a rationale that SOUNDS right and is false, so
    /// it must not be installed. This one is testable — the compiler settles it — and the guard
    /// `OneOwnerForTheClockSkewTests` exempts this file only WHILE the premise holds: it asserts
    /// `project.yml` still lists this path standalone under a non-app target. The day this file
    /// joins the app module, the exemption expires by itself and the guard names this line.
    ///
    /// The doc's old "(≥ −1 s)" parenthetical is still gone: that one really was a spare copy,
    /// and it cost nothing to remove because prose has no target membership.
    public func isFresh(
        within maxAge: TimeInterval = 2,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> Bool {
        let age = now - timestamp
        return age <= maxAge && age >= -1   // see the ⛔ note: no `BioSource` in the appex/watch
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

    // MARK: - Erase (privacy) — call OFF the audio thread

    /// Forget the last shared reading. `publish` writes a decoded body measurement into a
    /// `UserDefaults` suite, and a suite lives in `Library/Preferences`, which encrypted
    /// backups and iCloud include — so without this there is NO way for a person to make the
    /// app forget a vital sign short of deleting the app. This repo already reasoned through
    /// exactly that channel for the DERIVED performer fingerprint and applied the remedy only
    /// there; the raw reading it is derived from stayed.
    ///
    /// It matters for more people than "HealthKit users": the key holds the last reading from
    /// ANY source, and camera rPPG is the default — so it is everyone who has ever pressed
    /// play, plus anyone who handed the phone to a second performer.
    ///
    /// ⚠️ IT DOES NOT STOP A LIVE SESSION FROM RE-WRITING, and that is correct rather than a
    /// hole: `BioFeedbackPublisher.publishTick()` writes on its own cadence while a source is
    /// running, so a reading taken AFTER the erase is current data, not a leftover. What this
    /// removes is the stale payload that outlives the session, the app launch and the owner.
    ///
    /// `static` so a caller can erase without owning an instance — the app side constructs its
    /// manager inside `BioFeedbackPublisher`, and a factory reset must not have to reach
    /// through it. Opening the suite is the whole cost.
    public static func clearSharedVitals(appGroup: String = BioFeedbackManager.appGroupIdentifier) {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: storageKey)
    }

    /// Instance form, for a holder that already has the suite open.
    public func clearSharedVitals() {
        defaults?.removeObject(forKey: Self.storageKey)
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
