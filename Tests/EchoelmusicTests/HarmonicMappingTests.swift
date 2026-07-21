#if canImport(Accelerate)
// HarmonicMappingTests.swift
// Echoelmusic — the opt-in `.harmonicSeries` bio→sound mapping profile (Triage §1.2).
//
// Guards the two invariants that make the feature safe:
//   1. `.natural` (the default) is byte-identical to the established mapping —
//      harmonicity follows COHERENCE, unaffected by HRV. Zero-risk to the
//      already-tuned sound.
//   2. `.harmonicSeries` makes the BODY drive the overtone richness —
//      harmonicity follows HRV, not coherence. Same inputs → a different, richer
//      timbre than `.natural`.

import XCTest
@testable import Echoelmusic

final class HarmonicMappingTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    // MARK: - Default profile is `.natural` (no behaviour change)

    func testDefaultProfile_matchesExplicitNatural_harmonicity() {
        // No `profile:` argument → must equal an explicit `.natural`.
        ddsp.applyBioReactive(coherence: 0.2, hrvVariability: 0.9)
        let implicit = ddsp.harmonicity

        let other = EchoelDDSP()
        other.applyBioReactive(coherence: 0.2, hrvVariability: 0.9, profile: .natural)
        XCTAssertEqual(implicit, other.harmonicity, accuracy: 1e-5,
                       "The default profile must be `.natural` (identical harmonicity)")
    }

    // MARK: - `.natural` — harmonicity follows COHERENCE, not HRV

    func testNaturalProfile_harmonicityFollowsCoherence() {
        ddsp.applyBioReactive(coherence: 0.0, hrvVariability: 0.5, profile: .natural)
        let low = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 1.0, hrvVariability: 0.5, profile: .natural)
        let high = ddsp.harmonicity
        XCTAssertGreaterThan(high, low, "`.natural`: higher coherence = purer (higher harmonicity)")
    }

    func testNaturalProfile_hrvDoesNotDriveHarmonicity() {
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 0.0, profile: .natural)
        let lowHRV = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 1.0, profile: .natural)
        let highHRV = ddsp.harmonicity
        XCTAssertEqual(lowHRV, highHRV, accuracy: 1e-5,
                       "`.natural`: HRV must NOT move harmonicity (coherence does)")
    }

    // MARK: - `.harmonicSeries` — harmonicity follows HRV

    func testHarmonicSeries_hrvDrivesHarmonicity() {
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 0.0, profile: .harmonicSeries)
        let lowHRV = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 1.0, profile: .harmonicSeries)
        let highHRV = ddsp.harmonicity
        XCTAssertGreaterThan(highHRV, lowHRV,
                             "`.harmonicSeries`: higher HRV = richer overtones (higher harmonicity)")
    }

    func testHarmonicSeries_differsFromNatural_sameInputs() {
        // Low coherence + high HRV is exactly where the two profiles disagree:
        // natural → patch-relative base (0.88 + (coh−0.5)·0.12 → ~0.82 at coh 0);
        // harmonicSeries → HRV-driven overtone spread (0.40 + hrv·0.50 → ~0.90).
        // A8 narrowed the natural range, so the gap is ~0.08 — assert a realistic
        // margin that still proves the two profiles are audibly distinct.
        ddsp.applyBioReactive(coherence: 0.0, hrvVariability: 1.0, profile: .natural)
        let natural = ddsp.harmonicity

        let other = EchoelDDSP()
        other.applyBioReactive(coherence: 0.0, hrvVariability: 1.0, profile: .harmonicSeries)
        let harmonic = other.harmonicity

        XCTAssertGreaterThan(harmonic, natural + 0.03,
                             "For the same body state the two profiles must produce audibly different timbre")
    }

    // MARK: - Range safety (both profiles stay in-range, no NaN)

    func testHarmonicSeries_harmonicityStaysInRange() {
        for coh in stride(from: Float(0), through: 1, by: 0.25) {
            for hrv in stride(from: Float(0), through: 1, by: 0.25) {
                ddsp.applyBioReactive(coherence: coh, hrvVariability: hrv,
                                      breathPhase: 0.3, profile: .harmonicSeries)
                XCTAssertTrue(ddsp.harmonicity.isFinite, "harmonicity must be finite")
                XCTAssertGreaterThanOrEqual(ddsp.harmonicity, 0.05)
                XCTAssertLessThanOrEqual(ddsp.harmonicity, 0.98)
                XCTAssertTrue(ddsp.amplitude.isFinite, "amplitude must be finite")
                XCTAssertGreaterThanOrEqual(ddsp.amplitude, 0.0)
                XCTAssertLessThanOrEqual(ddsp.amplitude, 1.0)
            }
        }
    }
}

#endif
