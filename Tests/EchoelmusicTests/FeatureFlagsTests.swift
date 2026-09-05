// FeatureFlagsTests.swift
// Echoel — S0 of the spatial expansion: the flag switchboard must be OFF by default for
// every flag NOTHING registers (Release bit-identical), overridable per injected store,
// and its keys stable + distinct (they are the staged-rollout contract).
//
// ⛔ THE HEADER SAID "OFF BY DEFAULT" FLAT, AND SO DID THE TEST BELOW, WHILE THREE FLAGS
// ARE REGISTERED ON (#1011). The same over-claim was already caught one level up: the
// blocking guard `EveryFlagSaysWhatItGatesTests.testTheSummaryNoLongerClaimsEveryFlagIsOff`
// forbids `FeatureFlags`' own summary from saying it. Nothing forbade the TEST from saying
// it in executable form, so it said it — and went red where nobody was reading.

import XCTest
@testable import Echoelmusic

final class FeatureFlagsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FeatureFlagsTests-\(UUID().uuidString)")!
    }

    /// ⛔ #1011 — THIS ASSERTED "EVERY FLAG IS OFF" AND THREE OF THEM ARE DELIBERATELY ON.
    /// `EchoelmusicApp.init()` calls `UserDefaults.standard.register(defaults:)` for
    /// `multiRoll`, `voiceKindRouting` and `instrumentHome` — the three that decide what the
    /// app IS (per-lane voices, heterogeneous rack voices, and the front door it opens into).
    /// `FeatureFlags`' own header says so in a ⛔ block. This test said the opposite.
    ///
    /// ⭐ WHY A FRESH SUITE DID NOT SAVE IT, which is the part worth carrying away: the
    /// registration domain is PROCESS-VOLATILE and PROCESS-WIDE. `UserDefaults(suiteName:)`
    /// gives a private persistent domain, not a private search list — `NSRegistrationDomain`
    /// is still consulted last, so anything the host app registered at launch is visible to
    /// every defaults object in the process. A fixture that looks hermetic is not hermetic
    /// against `register(defaults:)`, and that is exactly why the flags were registered in
    /// `init()` in the first place (#580).
    ///
    /// ⚠️ THE THREE NAMES ARE TYPED OUT HERE AND THAT IS SAFE, unlike #1009's stale literal:
    /// `Tests/CISmoke/EveryFlagSaysWhatItGatesTests.testExactlyThreeFlagsAreRegisteredDefaultOn`
    /// scans the source for the registrations and is in the BLOCKING bundle, so a fourth
    /// registration goes red there first, with this file named. The count assertion below is
    /// the local half of that pairing.
    func testEveryUnregisteredFlagDefaultsOff() {
        // The flags `EchoelmusicApp.init()` registers ON. Their read is a founder decision,
        // not a default — see the ⛔ block in `FeatureFlags`.
        let registeredOn: Set<FeatureFlags.Key> = [.multiRoll, .voiceKindRouting, .instrumentHome]
        XCTAssertEqual(registeredOn.count, 3, """
        the set of default-ON flags changed. Update the blocking guard \
        `EveryFlagSaysWhatItGatesTests.testExactlyThreeFlagsAreRegisteredDefaultOn` and this \
        list in the SAME commit — a flag that turns the app on by default must never be able \
        to arrive quietly.
        """)

        let d = freshDefaults()
        for key in FeatureFlags.Key.allCases where !registeredOn.contains(key) {
            XCTAssertFalse(FeatureFlags.isOn(key, defaults: d),
                           "\(key.rawValue) must be OFF when absent (Release default)")
        }
    }

    /// The mirror of the case above: OFF is the behaviour of an UNREGISTERED key, so prove it
    /// on a key nothing registers rather than on "every" key. `set(_:false:)` writes an
    /// explicit false into the suite's own domain, which beats the registration domain — so
    /// this also shows the registered three can still be turned off per store.
    func testARegisteredFlagCanStillBeTurnedOffPerStore() {
        let d = freshDefaults()
        FeatureFlags.set(.instrumentHome, false, defaults: d)
        XCTAssertFalse(FeatureFlags.isOn(.instrumentHome, defaults: d), """
        an explicit false no longer beats the process-wide registration domain. The documented \
        one-line rollback `FeatureFlags.set(.instrumentHome, false)` depends on exactly this.
        """)
    }

    func testSetAndReadRoundTrip() {
        let d = freshDefaults()
        FeatureFlags.set(.spatialEngine, true, defaults: d)
        XCTAssertTrue(FeatureFlags.isOn(.spatialEngine, defaults: d))
        // Only the touched flag flips — neighbours stay OFF.
        XCTAssertFalse(FeatureFlags.isOn(.bioSpace, defaults: d))
        FeatureFlags.set(.spatialEngine, false, defaults: d)
        XCTAssertFalse(FeatureFlags.isOn(.spatialEngine, defaults: d))
    }

    func testKeysAreDistinctAndNamespaced() {
        let raws = FeatureFlags.Key.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "flag keys must be unique")
        for r in raws {
            XCTAssertTrue(r.hasPrefix("feature."), "\(r) must live in the feature.* namespace")
        }
    }
}
