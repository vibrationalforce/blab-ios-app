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

    // MARK: - The bus-publish gate must be the SAME bar as the display

    /// The defect this pins, straight out of device log 2469 (build 10.79.352): the shown
    /// number was gated on `pulseTrustworthy` while the BUS — synth, visual, OSC, ADM-OSC,
    /// Art-Net — was gated on confidence alone. Two readings in that log sit exactly in the
    /// gap, so the readout correctly held ~48 bpm while the instrument played 75–80.
    func testPublishGate_rejectsTheReadingsTheDisplayAlreadyRejected() {
        XCTAssertFalse(P.shouldPublish(bpm: 75, confidence: 0.62, autoStrength: 0.30),
                       "device log 2469: over the old confidence-only threshold, under the "
                       + "display's — this is the reading the sound followed and the screen did not")
        XCTAssertFalse(P.shouldPublish(bpm: 80, confidence: 0.62, autoStrength: 0.32))
    }

    /// HONEST LABEL: a CHANGE DETECTOR, not a behaviour test. `shouldPublish` is defined as
    /// `bpm > 0 && pulseTrustworthy(...)`, so "published ⟹ the display would show it" is
    /// true by construction and this sweep cannot fail unless someone edits the
    /// implementation — which is exactly what it is here to catch. It is NOT evidence that
    /// the invariant holds at runtime; that would need the publish loop itself.
    func testPublishGate_neverAdmitsWhatTheDisplayWouldRefuse_byConstruction() {
        for conf in stride(from: 0.0, through: 1.0, by: 0.05) {
            for acf in stride(from: 0.0, through: 1.0, by: 0.05) {
                if P.shouldPublish(bpm: 60, confidence: conf, autoStrength: acf) {
                    XCTAssertTrue(P.pulseTrustworthy(confidence: conf, autoStrength: acf),
                                  "published at conf \(conf) / acf \(acf) but the display "
                                  + "would not show it")
                }
            }
        }
    }

    /// The half of the fix that is easy to get wrong. ANDing the new gate with
    /// `lockThreshold` would look safer and would silently drop the documented
    /// strong-periodicity / low-confidence case (acf 0.59–0.72 at conf 0.01, a stable real
    /// 56 bpm) out of the SOUND while the display still shows it — the same asymmetry,
    /// inverted. If this test ever fails, someone added that AND back.
    func testPublishGate_stillCarriesAGenuinePulseWhoseConfidenceLags() {
        XCTAssertTrue(P.shouldPublish(bpm: 56, confidence: 0.01, autoStrength: 0.65))
        XCTAssertLessThan(0.01, P.lockThreshold,
                          "the point of this case is that it sits BELOW the old publish "
                          + "threshold — if lockThreshold ever drops under 0.01 it stops testing anything")
    }

    func testPublishGate_rejectsZeroBPMEvenWhenTheEvidenceLooksStrong() {
        XCTAssertFalse(P.shouldPublish(bpm: 0, confidence: 0.95, autoStrength: 0.90))
    }

    // MARK: - The published VALUE, not just the bar (#185)

    /// The remainder the gate fix explicitly left open, and named in its own doc comment:
    /// unifying `shouldPublish` made the screen and the bus clear ONE BAR, but the screen
    /// showed `displayBPM` (octave-folded) while the bus carried the raw
    /// `analyzer.estimatedBPM`. rPPG peak-counting reports 2× (or ½) the true pulse often
    /// enough that the display has folded since 2026-07-02 ("springt ständig auf 196 bpm").
    /// So a trustworthy 196 against an established 98 was SHOWN as 98 and PLAYED as 196 —
    /// the same see/hear split, one layer down.
    func testFold_halvesADoubledEstimateTowardTheEstablishedRate() {
        XCTAssertEqual(P.octaveFolded(196, toward: 98), 98, accuracy: 1e-9)
        XCTAssertEqual(P.octaveFolded(133, toward: 70), 66.5, accuracy: 1e-9)
    }

    func testFold_doublesAHalvedEstimate() {
        XCTAssertEqual(P.octaveFolded(35, toward: 72), 70, accuracy: 1e-9)
    }

    /// The band that must pass through untouched is wide on purpose — a genuine heart rate
    /// moves, and folding a real change would be worse than the octave error it prevents.
    func testFold_leavesAGenuineChangeAlone() {
        for raw in stride(from: 43.0, through: 110.0, by: 0.5) {   // 0.6× … 1.6× of 70
            XCTAssertEqual(P.octaveFolded(raw, toward: 70), raw, accuracy: 1e-9,
                           "\(raw) sits inside the pass band and must not be folded")
        }
    }

    /// No reference yet (first reading, or the display never locked) ⇒ identity. This is
    /// what keeps the change inert on the very first publish: `displayBPM` adopts the first
    /// trustworthy reading as-is, so reference == raw and the fold is a no-op there too.
    func testFold_withoutAReference_isIdentity() {
        XCTAssertEqual(P.octaveFolded(196, toward: 0), 196, accuracy: 1e-9)
        XCTAssertEqual(P.octaveFolded(196, toward: -1), 196, accuracy: 1e-9)
        XCTAssertEqual(P.octaveFolded(0, toward: 70), 0, accuracy: 1e-9)
    }

    /// ONE step, deliberately — the same rule the display has run on for weeks. A 4×
    /// estimate folds to 2×, not to 1×, and the next tick folds again. Pinning this stops
    /// a future "improvement" turning it into a `while` loop that could collapse a real
    /// tachycardia onto a resting rate.
    func testFold_takesASingleOctaveStepNotALoop() {
        XCTAssertEqual(P.octaveFolded(280, toward: 70), 140, accuracy: 1e-9)
        XCTAssertEqual(P.octaveFolded(18, toward: 72), 36, accuracy: 1e-9)
    }

    /// The property the fix exists for, swept rather than sampled: after folding, the
    /// published value is always within the display's own pass band of what is shown —
    /// i.e. never an octave apart from the number on screen.
    func testFold_publishedValueIsNeverAnOctaveFromTheShownOne() {
        let reference = 70.0
        for raw in stride(from: 30.0, through: 200.0, by: 0.5) {
            let published = P.octaveFolded(raw, toward: reference)
            // Bounds INCLUSIVE: the fold's own comparisons are strict (`>`/`<`), so a raw
            // landing exactly on 1.6×/0.6× passes through unfolded and legitimately sits
            // on the rail. Asserting strictly here would fail on that boundary value, which
            // `stride(by: 0.5)` does hit exactly (112.0).
            XCTAssertLessThanOrEqual(published, reference * 1.6,
                                     "raw \(raw) still published an octave above the shown \(reference)")
            XCTAssertGreaterThanOrEqual(published, reference * 0.6,
                                        "raw \(raw) still published an octave below the shown \(reference)")
        }
    }
}
#endif
