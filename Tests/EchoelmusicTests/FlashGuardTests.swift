// FlashGuardTests.swift
// Echoelmusic — WCAG 2.3.1 visual-safety primitive (pure).

import XCTest
@testable import Echoelmusic

final class FlashGuardTests: XCTestCase {

    func testMaxFlashHz_isThreePerWCAG() {
        XCTAssertEqual(FlashGuard.maxFlashHz, 3.0, accuracy: 1e-9)
    }

    func testSafeFrequency_clampsToMax() {
        XCTAssertEqual(FlashGuard.safeFrequency(5.0), 3.0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.safeFrequency(2.0), 2.0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.safeFrequency(-1.0), 0.0, accuracy: 1e-9)
    }

    func testSafeFrequency_reduceMotionStopsOscillation() {
        XCTAssertEqual(FlashGuard.safeFrequency(2.0, reduceMotion: true), 0.0, accuracy: 1e-9)
    }

    func testSafeFrequency_nonFiniteIsZero() {
        XCTAssertEqual(FlashGuard.safeFrequency(.nan), 0.0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.safeFrequency(.infinity), 0.0, accuracy: 1e-9)
    }

    func testIsFlash_darkToBright_isFlash() {
        XCTAssertTrue(FlashGuard.isFlash(from: 0.0, to: 0.5))   // big swing from dark
    }

    func testIsFlash_smallDelta_isNotFlash() {
        XCTAssertFalse(FlashGuard.isFlash(from: 0.5, to: 0.55)) // 0.05 < 0.10
    }

    func testIsFlash_bothBright_isNotFlash() {
        XCTAssertFalse(FlashGuard.isFlash(from: 0.85, to: 0.98)) // darker state ≥ 0.80
    }

    func testLimitedLuminance_capsStep() {
        XCTAssertEqual(FlashGuard.limitedLuminance(from: 0.0, to: 1.0), 0.10, accuracy: 1e-9)  // up-capped
        XCTAssertEqual(FlashGuard.limitedLuminance(from: 1.0, to: 0.0), 0.90, accuracy: 1e-9)  // down-capped
        XCTAssertEqual(FlashGuard.limitedLuminance(from: 0.50, to: 0.55), 0.55, accuracy: 1e-9) // within cap
    }

    // MARK: - Squared-field rate (the trap that let a shipping look reach 5 Hz)

    /// Clamping the PHASE rate is not enough: a style whose visible field is the
    /// SQUARED amplitude (energy ∝ amplitude², the physically correct quantity for
    /// interference) flashes at TWICE its phase rate, because
    /// sin²(x) = ½(1 − cos 2x). `MetalBioView`'s Rings look fed the full 2.5 Hz
    /// capped phase into a squared field and therefore reached 5 Hz — over the WCAG
    /// limit — while every guard in the codebase read "2.5 ≤ 3, safe".
    func testEffectiveFieldHz_foldingDoublesTheRate() {
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: 2.5, phaseMultiplier: 1.0,
                                                   folds: false), 2.5, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: 2.5, phaseMultiplier: 1.0,
                                                   folds: true), 5.0, accuracy: 1e-9)
    }

    /// Fails CLOSED, unlike `safeFrequency`: this result is a value to CHECK, so
    /// garbage in must not silently satisfy `<= maxFlashHz`.
    func testEffectiveFieldHz_nonFiniteFailsClosed() {
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: .nan, phaseMultiplier: 1.0,
                                                   folds: true), .infinity)
        XCTAssertFalse(FlashGuard.effectiveFieldHz(phaseRateHz: .nan, phaseMultiplier: 1.0,
                                                   folds: true) <= FlashGuard.maxFlashHz)
    }

    func testEffectiveFieldHz_signIsIrrelevant() {
        // A negative multiplier is a phase inversion, not a slower oscillation.
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: 2.5, phaseMultiplier: -1.0,
                                                   folds: true), 5.0, accuracy: 1e-9)
    }

    /// The literal interpolated into the Metal source MUST equal the Double the law is
    /// reasoned about. A mismatch would be a runtime SHADER COMPILE failure on device
    /// (black visual) or, worse, a silently wrong damping — neither is caught by the
    /// build, because the shader is compiled from a string at launch.
    func testRingsDampingLiteralMatchesTheConstant() {
        XCTAssertEqual(Double(FlashGuard.ringsPhaseDampingLiteral),
                       FlashGuard.ringsPhaseDamping)
        // Must parse as a plain Metal float literal — no locale comma, no exponent.
        XCTAssertFalse(FlashGuard.ringsPhaseDampingLiteral.contains(","))
        XCTAssertTrue(FlashGuard.ringsPhaseDampingLiteral.allSatisfy {
            $0.isNumber || $0 == "." || $0 == "-"
        })
    }

    /// The Rings damping is SHARED with the shader (interpolated into the Metal
    /// source), so this asserts the real constant, not a copy of it.
    func testRingsDampingKeepsTheSquaredFieldOnTheCap() {
        let hz = FlashGuard.effectiveFieldHz(phaseRateHz: 2.5,
                                             phaseMultiplier: FlashGuard.ringsPhaseDamping,
                                             folds: true)
        XCTAssertEqual(hz, 2.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(hz, FlashGuard.maxFlashHz)
    }

    /// The heartbeat bloom is an ADDITIVE second oscillator at the FULL phase rate, so
    /// `effectiveFieldHz` cannot bound it (its model is one oscillator). Instead its own
    /// luminance swing is held under the WCAG general-flash threshold, which makes its
    /// transitions not qualify as flashes. This asserts that product from the shader's
    /// documented constants — and it is the guard that catches the mistake actually made
    /// while implementing it: 0.50 looked fine until the filmic curve's 1.06 contrast
    /// lift was counted, which pushed it back over the gate.
    ///
    /// ⛔ THE FOURTH FACTOR USED TO BE A HAND-TYPED `1.06` HERE, and #1059 replaced the
    /// curve it described. The number is unchanged — the new luminance S-curve peaks at
    /// exactly the old uniform gain — but a literal that happens to still be right is not
    /// the same as one that CANNOT be wrong. It now reads `FlashGuard.filmicMaxSlope`,
    /// which is derived as `1 + filmicStrength/2` from the value the shader actually
    /// interpolates, so changing the curve moves this product instead of silently leaving
    /// a stale bound behind. That silent-stale case is the whole reason this test exists.
    func testBloomBeatSwingStaysUnderTheGeneralFlashThreshold() {
        let restGlowMax = 0.21          // MetalBioView: 0.07 + 0.14 · breath, breath ≤ 1
        let oneMinusAmbient = 0.94      // outCol = col · (0.06 + 0.94 · energy)
        let sCurveGain = FlashGuard.filmicMaxSlope   // steepest point of the closing curve
        let delta = FlashGuard.bloomBeatGainSwing * restGlowMax * oneMinusAmbient * sCurveGain
        XCTAssertLessThan(delta, FlashGuard.luminanceDeltaThreshold,
                          "bloom swings \(delta) relative luminance per beat — at or over "
                          + "the WCAG general-flash gate, so it becomes a second "
                          + "qualifying flash on top of the field")
        // Guard the guard: the previously-attempted 0.50 must still be shown as failing,
        // so nobody "restores" it thinking the threshold has room.
        XCTAssertGreaterThan(0.50 * restGlowMax * oneMinusAmbient * sCurveGain,
                             FlashGuard.luminanceDeltaThreshold)
    }

    func testBloomSwingLiteralMatchesTheConstant() {
        XCTAssertEqual(Double(FlashGuard.bloomBeatGainSwingLiteral),
                       FlashGuard.bloomBeatGainSwing)
        XCTAssertTrue(FlashGuard.bloomBeatGainSwingLiteral.allSatisfy {
            $0.isNumber || $0 == "." || $0 == "-"
        })
    }

    /// THE LAW, as a table: every user-selectable look must stay at or under 3 Hz at
    /// the maximum phase rate the renderer can integrate (2.5 Hz).
    ///
    /// ⚠ HONEST LIMITS OF THIS TEST — read before trusting it:
    /// 1. Only the Rings row is tied to the shader (via `ringsPhaseDamping`). The
    ///    other three multipliers are READ BY HAND from `MetalBioView.swift` and can
    ///    drift if someone edits the Metal source without updating them. A first
    ///    version of this table had three of four rows wrong, so treat the numbers
    ///    as documentation that must be re-derived, not as a proof.
    /// 2. The multipliers are the FASTEST term in each function, which for Water and
    ///    Depth is a PRODUCT of two phase-bearing factors (sum sideband f₁+f₂), and
    ///    for Aurora is an `abs()` FOLD of a phase-bearing wave — not a plain
    ///    "the style's own multiplier".
    /// 3. It does NOT cover additive superposition (the heartbeat bloom on top of the
    ///    field) or the A↔B blend union. Those need per-pixel photometry.
    func testEveryReachableLookObeysTheThreeHzLaw() {
        // READ the ceiling, never re-type it: this line used to be `let maxPhaseRate = 2.5`
        // with a comment pointing at MetalBioView, so raising the renderer's cap left the
        // whole proof below green while Aurora (0 margin, see below) went to 3.6 Hz.
        let maxPhaseRate = FlashGuard.maxPulseRateHz
        // (multiplier, folds) of the FASTEST temporal term in each shader function.
        let looks: [(name: String, phaseMultiplier: Double, folds: Bool)] = [
            // fieldRings: p = 0.5·phase, then interference INTENSITY (bipolar square).
            ("Rings",  FlashGuard.ringsPhaseDamping, true),                 // → 2.50 Hz
            // fieldWater: sin(x·s + t)·cos(y·(s−1) − 0.7t), t = 0.4·phase.
            // PRODUCT of two phase-bearing factors ⇒ sum sideband 0.4 + 0.28 = 0.68.
            ("Water",  0.68, false),                                        // → 1.70 Hz
            // fieldAurora: abs(p.y − wave) FOLDS a wave whose fastest term is
            // 1.0·t = 0.35·phase ⇒ 0.70. The curtain is then MULTIPLIED by
            // `breathe` (0.5·phase), adding a 0.70 + 0.50 = 1.20 sideband ⇒ 3.00 Hz.
            // Aurora therefore sits exactly ON the limit with ZERO margin — the
            // worst-case row in the app. Do not add any further phase term to it.
            ("Aurora", 1.20, false),                                        // → 3.00 Hz
            // fieldDepthCaustics: sin(x·s + t)·cos(y·s − 0.8t), t = 0.4·phase
            // ⇒ product sideband 0.4 + 0.32 = 0.72.
            ("Depth",  0.72, false)                                         // → 1.80 Hz
        ]
        for look in looks {
            let hz = FlashGuard.effectiveFieldHz(phaseRateHz: maxPhaseRate,
                                                 phaseMultiplier: look.phaseMultiplier,
                                                 folds: look.folds)
            XCTAssertLessThanOrEqual(hz, FlashGuard.maxFlashHz,
                                     "\(look.name) flashes at \(hz) Hz — over the WCAG 3 Hz law")
        }
    }

    /// The app ceiling is what makes the table above pass, so pin the RELATIONSHIP rather
    /// than trusting a future tuning pass to re-derive four look budgets by hand.
    ///
    /// Aurora is the binding constraint: 1.20 × the phase rate, no fold. At 2.5 Hz that is
    /// exactly 3.00 Hz — dead on `maxFlashHz` with zero margin. So the app ceiling is not a
    /// free parameter: any increase is an immediate WCAG 2.3.1 violation on a look that is
    /// reachable today, and this test is what says so instead of a comment nobody reads.
    func testAppPulseCeiling_isWhatKeepsTheWorstLookLegal() {
        XCTAssertLessThanOrEqual(FlashGuard.maxPulseRateHz, FlashGuard.maxFlashHz,
                                 "the app ceiling can never exceed the WCAG law it serves")
        let auroraMultiplier = 1.20   // fieldAurora: 0.70 curtain + 0.50 breathe sideband
        let aurora = FlashGuard.effectiveFieldHz(phaseRateHz: FlashGuard.maxPulseRateHz,
                                                 phaseMultiplier: auroraMultiplier,
                                                 folds: false)
        XCTAssertLessThanOrEqual(aurora, FlashGuard.maxFlashHz,
                                 "Aurora at the app ceiling flashes at \(aurora) Hz")
        // NO equality assertion on the zero margin. The first version had one, to make
        // raising the ceiling "fail loudly here" — but the `<=` above already does exactly
        // that (at a 3.0 ceiling Aurora is 3.6 and goes red with its own message), so the
        // equality added no coverage while failing on changes that make the app SAFER:
        // tightening the ceiling to 2.0, or calming Aurora's shader, both leave `<=` green
        // and break equality. A safety guard that goes red when the margin GROWS teaches
        // people to edit the guard. The zero-margin fact lives in `maxPulseRateHz`'s doc
        // block, which is where someone changing the ceiling will actually read it.
    }

    /// Retired-but-compiled styles are NOT in `LookBlendMap.library`, and one of them
    /// (Scope) computes to ~3.0 Hz — re-adding a row without re-deriving its budget
    /// would ship a violation. This pins the reachable set so that adding a look
    /// forces someone to touch the table above.
    func testReachableLookSetIsExactlyTheBudgetedOne() {
        XCTAssertEqual(Set(LookBlendMap.library.map(\.name)),
                       ["Rings", "Water", "Aurora", "Depth"],
                       "A look was added or removed — re-derive its flash budget in "
                       + "testEveryReachableLookObeysTheThreeHzLaw before changing this.")
    }
}
