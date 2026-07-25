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
    func testEffectiveFieldHz_squaringDoublesTheRate() {
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: 2.5, phaseMultiplier: 1.0,
                                                   squared: false), 2.5, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: 2.5, phaseMultiplier: 1.0,
                                                   squared: true), 5.0, accuracy: 1e-9)
    }

    func testEffectiveFieldHz_nonFiniteAndNegativeAreTreatedAsStill() {
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: .nan, phaseMultiplier: 1.0,
                                                   squared: true), 0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.effectiveFieldHz(phaseRateHz: 2.5, phaseMultiplier: -1.0,
                                                   squared: true), 5.0, accuracy: 1e-9)
    }

    /// THE LAW, as a table. Every user-selectable look in `LookBlendMap.library`
    /// must stay at or under 3 Hz at the maximum phase rate the renderer can
    /// integrate (2.5 Hz). Values mirror the shader in `MetalBioView.swift` —
    /// when you add or retune a style, update this row and keep it passing.
    /// Rings is listed at 0.5 because it squares: 0.5 × 2 = 1.0 → 2.5 Hz.
    func testEveryReachableLookObeysTheThreeHzLaw() {
        let maxPhaseRate = 2.5   // MetalBioView: min(pulseHz × motion, 2.5)
        let looks: [(name: String, phaseMultiplier: Double, squared: Bool)] = [
            ("Rings",  0.5,  true),    // fieldRings — interference INTENSITY (squared)
            ("Water",  0.6,  false),   // fieldWater — shimmer term is the fastest
            ("Aurora", 0.5,  false),   // fieldAurora — `breathe` term
            ("Depth",  0.4,  false)    // fieldDepthCaustics
        ]
        for look in looks {
            let hz = FlashGuard.effectiveFieldHz(phaseRateHz: maxPhaseRate,
                                                 phaseMultiplier: look.phaseMultiplier,
                                                 squared: look.squared)
            XCTAssertLessThanOrEqual(hz, FlashGuard.maxFlashHz,
                                     "\(look.name) flashes at \(hz) Hz — over the WCAG 3 Hz law")
        }
    }
}
