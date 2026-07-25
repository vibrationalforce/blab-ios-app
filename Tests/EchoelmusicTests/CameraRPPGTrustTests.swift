//
//  CameraRPPGTrustTests.swift
//  Echoelmusic — rPPG "earn trust" gate.
//
//  Tests the pure `CameraRPPGBioPublisher.pulseTrustworthy(confidence:autoStrength:)` gate.
//  A reading may move the shown pulse / latch the tempo when it is EITHER confident AND
//  corroborated by real periodicity (autocorrelation), OR carries strong periodicity on its
//  own — so a poorly-placed finger, where the peak-counter self-agrees on a noisy signal, can
//  no longer show or seed a fantasy number (device log 2026-07-04: acf 0.14 / conf 0.90
//  "settled" at a wrong 79 bpm; true pulse ~54), while a genuinely periodic pulse whose
//  confidence metric lags (device log 1783420026: acf 0.6–0.72 / conf 0.01, stable 56 bpm) is
//  shown promptly instead of stuck on "acquiring".
//

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class CameraRPPGTrustTests: XCTestCase {

    typealias P = CameraRPPGBioPublisher

    func testRealLock_confidentAndCorroborated_isTrusted() {
        // This device's real locks: strong acf (0.57–0.84) with confidence.
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.90, autoStrength: 0.80))
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.72, autoStrength: 0.65)) // the true late lock (bpm 54–55)
    }

    func testBadReading_confidentButNoPeriodicity_isRejected() {
        // The exact device-log failure: high confidence from peak-count self-agreement, but
        // the autocorrelation found almost nothing → must NOT be trusted (would have shown 79).
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.90, autoStrength: 0.14))
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.86, autoStrength: 0.16))
    }

    func testStrongPeriodicityAlone_isTrusted_evenWithLowConfidence() {
        // Device log 1783420026: acf climbed to 0.59–0.72 with a rock-stable 56 bpm
        // for ~10 s while conf sat at 0.01 — a genuine, strongly periodic pulse the
        // display used to refuse because it also demanded confidence. Strong
        // periodicity is the STRONGER evidence and must stand on its own.
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.01, autoStrength: 0.65))
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.50, autoStrength: 0.90))
    }

    func testMidPeriodicityWithLowConfidence_stillRejected() {
        // The OR path only opens for STRONG periodicity (>= strongAutoFloor 0.6).
        // A middling acf without confidence is still not enough → holds "acquiring".
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.30, autoStrength: 0.50))
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.30, autoStrength: P.strongAutoFloor - 0.01))
    }

    func testBoundaries() {
        // Path A — confident AND corroborated: conf >= displayThreshold (0.6),
        // acf >= trustAutoFloor (0.4).
        XCTAssertTrue(P.pulseTrustworthy(confidence: P.displayThreshold, autoStrength: P.trustAutoFloor))
        XCTAssertFalse(P.pulseTrustworthy(confidence: P.displayThreshold, autoStrength: 0.39))
        // Path B — strong periodicity alone: acf >= strongAutoFloor (0.6) trusts
        // regardless of confidence; one tick below with weak confidence does not.
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.10, autoStrength: P.strongAutoFloor))
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.10, autoStrength: P.strongAutoFloor - 0.01))
        // strongAutoFloor sits safely above the junk ceiling (~0.29).
        XCTAssertGreaterThan(P.strongAutoFloor, 0.4)
    }

    // MARK: - Dropout hold vs. consumer freshness (the regression this pins)

    /// During a brief dropout the publisher re-emits the last good frame carrying its
    /// ORIGINAL timestamp (re-stamping it would make a held frame indistinguishable
    /// from a live one and defeat every `freshBio`/`usableBio` gate). That only holds
    /// the picture steady while the hold is SHORTER than the consumer's freshness
    /// window — otherwise the frame expires mid-grace and the consumer snaps to its
    /// idle defaults, which is the bio↔idle flicker the hold was written to remove.
    /// `SpectralDonutView` shipped with `freshBio(maxAge: 2)` against a 4 s hold and
    /// did exactly that; it now calls `usableBio()`, i.e. this window.
    @MainActor
    func testDropoutHoldFitsInsideTheCameraFreshnessWindow() {
        let holdSeconds = Double(P.bioHoldTicks) / 10.0     // the publish loop ticks at 10 Hz
        XCTAssertLessThan(holdSeconds, BioSource.cameraPPG.freshnessWindow,
                          "the hold outlives the frame it re-emits — consumers will fall "
                          + "to idle mid-grace")
    }
}
#endif
