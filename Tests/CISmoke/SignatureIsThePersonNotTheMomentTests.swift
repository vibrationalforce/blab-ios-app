// SignatureIsThePersonNotTheMomentTests.swift
// Echoel — #403 Slice 1. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. The founder's ask is that two people who pick the same preset,
// change nothing and hit render do not get the same-feeling song. `PerformerSignature` is the
// half that makes the difference belong to a PERSON rather than to a dice roll: a slowly
// learned fingerprint that folds into the composer's STRUCTURE seed.
//
// Two properties carry the whole idea, and they pull in opposite directions:
//   · DIFFERENT bodies must land on different skeletons (or the ask is unmet), and
//   · the SAME body must keep its skeleton across sessions (or it is a dice roll wearing a
//     fingerprint's name — the failure mode the plan's Vision-Keeper seat named explicitly).
// The second is why the quantisation here is COARSE while `EchoelStudioView.bioSeed` is fine:
// the moment wants a new number whenever the body moves, the person wants the same one.
//
// ⚠️ HOW FAR THE CLAIM GOES. Nothing here says the result SOUNDS individual. It says which
// seed a body opens on. On `.selfObservation` — the genre a fresh install opens with, three
// chords and four sustained tones — a different skeleton has very little room to be audible;
// that is why the plan re-weighted Slice 2 (character offsets) as the slice that reaches the
// contemplative middle. Reading this file as "the individuality is shipped" would be exactly
// the overstatement `ContentPipeline/CLAIMS.md` exists to prevent.
//
// WHY THREE SOURCE SCANS AT THE END: the fold and the learning both live inside a private
// method of a @MainActor SwiftUI view, so neither is drivable from here. A pure core with no
// caller is the same defect with more steps, so the CALLS are pinned by source text.

import Foundation
import XCTest
@testable import Echoelmusic

final class SignatureIsThePersonNotTheMomentTests: XCTestCase {

    private func body(at t: TimeInterval,
                      hr: Float = 0,
                      hrv: Float = 0,
                      coh: Float = 0,
                      breath: Float = 0,
                      source: BioSource = .cameraPPG) -> BioSampleFrame {
        BioSampleFrame(timestamp: t,
                       heartRateBPM: hr,
                       hrvNormalized: hrv,
                       breathRate: breath,
                       breathPhase: 0.25,
                       coherence: coh,
                       motionEnergy: 0,
                       source: source)
    }

    // MARK: - The empty case is the safety story

    func testAFreshInstallContributesNothing() {
        let fresh = PerformerSignature.unknown
        XCTAssertFalse(fresh.hasBody, "A signature nobody taught cannot claim to know a body.")
        let message = "An unmeasured performer must contribute salt 0, because the composer "
            + "folds the salt with XOR and only 0 is a no-op. Anything else here means a user "
            + "who never showed the app a pulse silently gets a different composition than "
            + "before #403 — a behaviour change nobody asked for and nobody can explain."
        XCTAssertEqual(fresh.seedSalt, 0, message)
    }

    func testOneMeasuredBodyMakesASignature() {
        let sig = PerformerSignature.unknown.observing(body(at: 1000, hr: 61, hrv: 0.42))
        XCTAssertTrue(sig.hasBody, "A frame with a real heart rate is a measured body.")
        let message = "A taught signature produced salt 0, which the composer reads as "
            + "\"no signature\". A real fingerprint must never be indistinguishable from an "
            + "absent one."
        XCTAssertNotEqual(sig.seedSalt, 0, message)
    }

    // MARK: - Person, not moment

    func testTwoDifferentBodiesDoNotShareASkeleton() {
        let a = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 52, hrv: 0.68, coh: 0.71, breath: 5.5))
        let b = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 84, hrv: 0.21, coh: 0.30, breath: 15.0))
        let message = "Two clearly different bodies folded to the SAME salt. That is the "
            + "founder's complaint in its purest form: same preset, different person, same "
            + "song."
        XCTAssertNotEqual(a.seedSalt, b.seedSalt, message)
    }

    func testTheSameFingerprintAlwaysFoldsTheSameWay() {
        let a = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 61, hrv: 0.42, coh: 0.55, breath: 11))
        let b = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 61, hrv: 0.42, coh: 0.55, breath: 11))
        XCTAssertEqual(a.seedSalt, b.seedSalt,
                       "The salt is a pure function of the fingerprint and must be stable.")
    }

    func testASmallDriftKeepsTheSameSkeleton() {
        // THE PROPERTY THAT SEPARATES A PERSON FROM A MOMENT. Nobody's resting heart rate is
        // the same number twice; if a third of a beat per minute re-rolled the skeleton, the
        // "signature" would just be a slower dice.
        let monday = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 60.0, hrv: 0.400, coh: 0.500, breath: 12.0))
        let friday = PerformerSignature.unknown
            .observing(body(at: 9000, hr: 60.3, hrv: 0.404, coh: 0.510, breath: 12.1))
        let message = "The same person, measured on two days with ordinary drift, landed on "
            + "two different skeletons. The quantisation in `seedSalt` is what prevents this "
            + "— if it was made finer, this is the test that says so."
        XCTAssertEqual(monday.seedSalt, friday.seedSalt, message)
    }

    func testAChannelNobodyMeasuredIsNotTheSameAsAChannelThatReadsLow() {
        // A source that derives no respiration must not be confused with a very slow
        // breather. Both would carry breathRate ~0 if unmeasured channels were averaged in.
        let noBreathSource = PerformerSignature.unknown.observing(body(at: 1000, hr: 61))
        let slowBreather = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 61, breath: 4))
        let message = "A performer whose source reports no respiration folded to the same "
            + "salt as one measured at 4 breaths/min. Which channels a body actually reports "
            + "is part of who is playing."
        XCTAssertNotEqual(noBreathSource.seedSalt, slowBreather.seedSalt, message)
    }

    // MARK: - What must never be learned

    func testASimulatedBodyTeachesNothing() {
        // `.fallback` is `BioSimulator`, and it emits perfectly plausible numbers. A
        // handwriting learned from those would be a synthetic person presented as the user —
        // the "randomness is not a body" failure the plan names outright. Not hypothetical:
        // the founder's own 2026-08-05 session ran with `bio simulation starting`.
        let sig = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 61, hrv: 0.42, coh: 0.55,
                            breath: 11, source: .fallback))
        let message = "The simulator taught the performer fingerprint. Every demo session "
            + "would then write over who the user is, and the app would claim a personal "
            + "signature it derived from its own test tone."
        XCTAssertEqual(sig, .unknown, message)
    }

    func testARealSourceStillTeachesAfterASimulatedOne() {
        // The mirror image: refusing the simulator must not consume the window either, or a
        // demo-then-play session would silently skip the first real measurement.
        let simulated = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 61, source: .fallback))
        let real = simulated.observing(body(at: 1001, hr: 61, source: .ble))
        XCTAssertEqual(real.heartRateCount, 1,
                       "A refused simulated frame must leave the window untouched.")
    }

    func testAnUnmeasuredChannelIsNotAveragedIn() {
        // Zero means NOT MEASURED on the bus (see `BioSampleFrame.hrvNormalized`), and it is
        // an EXTREME rather than a neutral value — averaging it in would drag the fingerprint
        // toward a body nobody has.
        let sig = PerformerSignature.unknown.observing(body(at: 1000, hr: 61))
        XCTAssertEqual(sig.heartRateCount, 1, "The one measured channel must be learned.")
        let message = "An unmeasured channel raised its count. Its running mean is now an "
            + "average over readings that were never taken, and every later real reading is "
            + "diluted by them."
        XCTAssertEqual(sig.hrvCount, 0, message)
        XCTAssertEqual(sig.coherenceCount, 0, message)
        XCTAssertEqual(sig.breathCount, 0, message)
    }

    func testABusySessionCannotTeachTwiceInThirtySeconds() {
        // Every control tap recomposes. Without the window, ten minutes of tweaking would
        // count as dozens of independent pieces of evidence about the person — one session
        // would own a fingerprint that is supposed to describe them across sessions.
        let first = PerformerSignature.unknown.observing(body(at: 1000, hr: 60))
        let again = first.observing(body(at: 1005, hr: 90))
        let message = "A second take five seconds later moved the fingerprint. The rate "
            + "limit in `observing` is gone or the window is being consumed by frames it "
            + "should have ignored."
        XCTAssertEqual(again, first, message)
    }

    func testThirtySecondsLaterItLearnsAgain() {
        let first = PerformerSignature.unknown.observing(body(at: 1000, hr: 60))
        let later = first.observing(body(at: 1040, hr: 90))
        XCTAssertEqual(later.heartRateCount, 2,
                       "Past the window a real take must teach, or nothing is ever learned.")
        XCTAssertGreaterThan(later.heartRateBPM, first.heartRateBPM,
                             "A faster body must move the running mean upward.")
    }

    func testAFrameThatMeasuresNothingDoesNotConsumeTheWindow() {
        // The trap this closes: a source emitting empty frames would keep re-stamping
        // `lastObservation`, so the REAL body would be permanently inside the rate limit and
        // the fingerprint would never learn anything at all.
        let taught = PerformerSignature.unknown.observing(body(at: 1000, hr: 60))
        let empty = taught.observing(body(at: 1040))
        XCTAssertEqual(empty, taught, "An empty frame teaches nothing, so it changes nothing.")
        let real = empty.observing(body(at: 1041, hr: 62))
        let message = "The empty frame moved the window forward, so the real body one second "
            + "later was refused. An unmeasurable source would silently freeze learning."
        XCTAssertEqual(real.heartRateCount, 2, message)
    }

    func testNonFiniteReadingsNeitherTrapNorCount() {
        // rPPG and BLE both emit NaN on a dropped lock, and `UInt64(Float.nan)` is a crash,
        // not a bad value. The bucket maths sits directly on these numbers.
        let sig = PerformerSignature.unknown
            .observing(body(at: 1000, hr: .nan, hrv: .infinity, coh: -1, breath: 12))
        XCTAssertEqual(sig.heartRateCount, 0, "NaN is not a heart rate.")
        XCTAssertEqual(sig.hrvCount, 0, "Infinity is not a variability reading.")
        XCTAssertEqual(sig.coherenceCount, 0, "A negative coherence is not a measurement.")
        XCTAssertEqual(sig.breathCount, 1, "The one real channel must still be learned.")
        XCTAssertNotEqual(sig.seedSalt, 0, "And the salt must still be computable.")
    }

    func testAnImpossibleReadingIsClampedNotTrusted() {
        let sig = PerformerSignature.unknown.observing(body(at: 1000, hr: 5000))
        let message = "A 5000 BPM reading was stored verbatim. Nothing downstream traps on "
            + "it today, but the fingerprint would then be permanently owned by one broken "
            + "frame — the saturating mean can only pull it back 1/64th at a time."
        XCTAssertEqual(sig.heartRateBPM, 300, accuracy: 0.001, message)
    }

    func testOneUnusualAfternoonCannotRedrawTheHandwriting() {
        var sig = PerformerSignature.unknown
        var t: TimeInterval = 1000
        for _ in 0..<200 {
            sig = sig.observing(body(at: t, hr: 60))
            t += 30
        }
        let settled = sig.heartRateBPM
        let afterASprint = sig.observing(body(at: t, hr: 120)).heartRateBPM
        let message = "A single extreme session moved the learned resting rate by more than "
            + "one BPM. Past `saturation` the weight must be 1/64, so 60 BPM of difference "
            + "may move the mean by at most ~0.94."
        XCTAssertLessThan(afterASprint - settled, 1.0, message)
        XCTAssertGreaterThan(afterASprint, settled,
                             "…but it must still move: a frozen fingerprint stops being one.")
    }

    func testAClockThatWentBackwardsStillTeaches() {
        // A restored backup or a manual date change can put `frame.timestamp` behind the
        // stored stamp. Refusing everything until real time catches up would freeze the
        // fingerprint for as long as the jump was.
        let taught = PerformerSignature.unknown.observing(body(at: 9_000_000, hr: 60))
        let afterJump = taught.observing(body(at: 1000, hr: 62))
        let message = "A backwards clock must read as elapsed, never as a window that "
            + "cannot end."
        XCTAssertEqual(afterJump.heartRateCount, 2, message)
    }

    // MARK: - Persistence (on-device only)

    func testTheFingerprintSurvivesARoundTrip() throws {
        var sig = PerformerSignature.unknown
        sig = sig.observing(body(at: 1000, hr: 61, hrv: 0.42, coh: 0.55, breath: 11))
        sig = sig.observing(body(at: 1100, hr: 63, hrv: 0.44, coh: 0.57, breath: 12))
        let data = try JSONEncoder().encode(sig)
        let back = try JSONDecoder().decode(PerformerSignature.self, from: data)
        let message = "A fingerprint that cannot round-trip is re-learned from scratch on "
            + "every launch, which is exactly the moment-not-person bug."
        XCTAssertEqual(back, sig, message)
        XCTAssertEqual(back.seedSalt, sig.seedSalt, "…and it must fold identically.")
    }

    func testAPartialPayloadDegradesInsteadOfThrowing() throws {
        // The `decodeIfPresent` law (#163/#189). A signature is derived data that can always
        // be re-learned, so a payload written by an older or newer shape must cost at most
        // the fields it is missing.
        let partial = Data("{\"heartRateBPM\":61,\"heartRateCount\":3}".utf8)
        let decoded = try JSONDecoder().decode(PerformerSignature.self, from: partial)
        XCTAssertEqual(decoded.heartRateCount, 3, "What was present must survive.")
        XCTAssertEqual(decoded.breathCount, 0, "What was absent degrades to unmeasured.")
        XCTAssertTrue(decoded.hasBody, "A partial fingerprint is still a fingerprint.")
    }

    func testAnEmptyStoreReadsAsUnknown() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "PerformerSignatureTests.empty"))
        suite.removeObject(forKey: PerformerSignature.storageKey)
        XCTAssertEqual(PerformerSignature.load(from: suite), .unknown,
                       "No stored fingerprint must read as no fingerprint, not as a crash.")
    }

    func testAStoredFingerprintComesBack() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "PerformerSignatureTests.roundTrip"))
        suite.removeObject(forKey: PerformerSignature.storageKey)
        let sig = PerformerSignature.unknown.observing(body(at: 1000, hr: 61, hrv: 0.42))
        sig.save(to: suite)
        XCTAssertEqual(PerformerSignature.load(from: suite), sig,
                       "The fingerprint must survive the launch it is supposed to outlive.")
        suite.removeObject(forKey: PerformerSignature.storageKey)
    }

    func testCorruptStoredBytesReadAsUnknownRatherThanCrash() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "PerformerSignatureTests.corrupt"))
        suite.set(Data([0x00, 0x01, 0x02]), forKey: PerformerSignature.storageKey)
        let message = "Unreadable bytes must degrade to no fingerprint — losing a nuance is "
            + "acceptable, refusing to launch is not."
        XCTAssertEqual(PerformerSignature.load(from: suite), .unknown, message)
        suite.removeObject(forKey: PerformerSignature.storageKey)
    }

    // MARK: - Provenance, and the way out

    func testARestrictedSourceLeavesAStickyMark() {
        // `observing` blends every source into the same four means, so after the blend the
        // `BioSource` is gone and `BioEgressPolicy.allowsEgress` — which takes exactly that —
        // can no longer be asked. One bit, recorded at learn time, keeps the answer available
        // for the two places already planned (Slice 3's UI, and a peer share).
        let ownMeasurement = PerformerSignature.unknown
            .observing(body(at: 1000, hr: 61, source: .cameraPPG))
        XCTAssertFalse(ownMeasurement.taughtByRestrictedSource,
                       "rPPG is measured by this app and may egress; it marks nothing.")

        let fromHealthStore = ownMeasurement.observing(body(at: 1040, hr: 62, source: .healthKit))
        XCTAssertTrue(fromHealthStore.taughtByRestrictedSource,
                      "A HealthKit reading contributed to the mean; the mark must be set.")

        let laterOwn = fromHealthStore.observing(body(at: 1080, hr: 63, source: .ble))
        let message = "The mark cleared once a non-restricted source taught again. It must be "
            + "STICKY: the mean the restricted reading moved does not un-mix, so the answer "
            + "\"has a Health-store value influenced this?\" stays yes forever."
        XCTAssertTrue(laterOwn.taughtByRestrictedSource, message)
    }

    func testAPayloadFromBeforeTheMarkIsTreatedAsRestricted() throws {
        // Conservative on unknown provenance, but only where there IS provenance to be unsure
        // about — an empty payload has taught nothing and must stay indistinguishable from
        // `.unknown`.
        let taught = Data("{\"heartRateBPM\":61,\"heartRateCount\":3}".utf8)
        let old = try JSONDecoder().decode(PerformerSignature.self, from: taught)
        let message = "An older payload carries no provenance bit and there is no way left to "
            + "recover it, so the honest default is the restricted one. Defaulting to false "
            + "would declare unknown provenance to be safe provenance."
        XCTAssertTrue(old.taughtByRestrictedSource, message)

        let empty = try JSONDecoder().decode(PerformerSignature.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .unknown,
                       "A payload that taught nothing has nothing to be unsure about.")
    }

    func testTheFingerprintHasAWayOut() {
        // ⭐ THE OFF-SWITCH. A persisted, invisible, health-derived value that changes every
        // take must be clearable without deleting the app — `SoundReset`'s whole thesis, and
        // this file's value is the one that would otherwise have no remedy at all.
        let cleared = SoundReset.keys.contains(PerformerSignature.storageKey)
        let message = "`SoundReset` no longer clears the performer fingerprint. Its only "
            + "remedy is then delete-and-reinstall, which also destroys every patch, take and "
            + "project — the amputation `SoundReset.swift` exists to replace."
        XCTAssertTrue(cleared, message)
    }

    func testTheResetIsProvenAgainstAScratchStore() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "PerformerSignatureTests.reset"))
        let sig = PerformerSignature.unknown.observing(body(at: 1000, hr: 61, hrv: 0.42))
        sig.save(to: suite)
        XCTAssertTrue(PerformerSignature.load(from: suite).hasBody, "precondition")
        SoundReset.clear(in: suite)
        XCTAssertEqual(PerformerSignature.load(from: suite), .unknown,
                       "After a sound reset the stored fingerprint must be gone, not stale.")
        suite.removeObject(forKey: PerformerSignature.storageKey)
    }

    // MARK: - The wiring (source text — see the header for why)

    func testTheSkeletonSeedActuallyCarriesTheSignature() throws {
        let source = try Self.studioSource()
        let message = "The composer no longer folds the performer salt into its structure "
            + "seed. Everything above this line then tests a fingerprint that reaches no "
            + "music at all, which is the same defect as not having built it."
        XCTAssertTrue(source.contains("structureSeed ^= salt"), message)
    }

    func testARealTakeActuallyTeachesTheSignature() throws {
        let source = try Self.studioSource()
        let message = "Nothing calls `observing` any more, so the fingerprint can never "
            + "learn. It would stay `.unknown` forever, fold to salt 0, and every user would "
            + "be back to the pre-#403 behaviour with a persistence layer for company."
        XCTAssertTrue(source.contains("performerSignature.observing(f)"), message)
    }

    func testTheFingerprintIsReadBackAtLaunch() throws {
        let source = try Self.studioSource()
        let message = "The studio no longer loads the stored fingerprint, so it is re-learned "
            + "from scratch on every launch — the person becomes the session again, which is "
            + "precisely what this slice exists to stop."
        XCTAssertTrue(source.contains("PerformerSignature.load(from: .standard)"), message)
    }

    func testTheLiveCopyIsClearedTooNotJustTheStoredOne() throws {
        // ⚠️ THE HALF-FIX THIS REPO HAS NOW PAID FOR THREE TIMES (`SessionContext`, `MixerStore`,
        // and this). `performerSignature` is `@State`, read once at view construction, so
        // clearing the KEY leaves the in-memory copy salting every take until the next launch —
        // a factory reset that visibly does nothing, which is the reinstall experience coming
        // back through the button built to end it.
        let source = try Self.studioSource()
        let message = "`resetSoundToDefaults` no longer assigns `.unknown` to the live "
            + "fingerprint. The stored key goes, the in-memory one keeps colouring every take "
            + "until relaunch, and the reset reads as broken."
        XCTAssertTrue(source.contains("performerSignature = .unknown"), message)
    }

    func testTheLaunchLineReportsPresenceAndNeverValues() throws {
        // The pairing with `SoundReset` is enforced by
        // `ResetSoundClearsWhatTheLaunchLineReportsTests`; what THIS pins is the shape of what
        // gets reported. `echoel_diag.log` is a file the founder pastes into a chat, so a
        // learned resting heart rate printed there is a health value leaving the device by the
        // most ordinary route there is — and it would turn a musical handwriting into a
        // readout ABOUT a person, which this feature is forbidden from becoming.
        let source = try Self.studioSource()
        let present = "let signatureText = performerSignature.hasBody ? \"learned\" : \"none\""
        let message = "The launch breadcrumb no longer reports the fingerprint as a plain "
            + "presence flag. If it now prints the learned values instead, health numbers are "
            + "going into the diagnostics file users share."
        XCTAssertTrue(source.contains(present), message)
    }

    /// The one place that resolves the source path, so a directory move breaks three tests
    /// with one honest error instead of three misleading ones.
    private static func studioSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
