import XCTest
@testable import Echoelmusic

/// Tests for the pure `FaceExpressionMapping` one-pole smoother plus the additive
/// BioSampleFrame face fields and ModSource face cases.
///
/// Framing: these coefficients are EXPRESSION/MOVEMENT used as a CONTROL signal,
/// never an inferred emotion — the tests assert only signal behaviour.
final class FaceExpressionMappingTests: XCTestCase {

    // MARK: - EMA convergence

    func testUpdate_convergesMonotonicallyTowardTarget() {
        var m = FaceExpressionMapping(timeConstant: 0.15)
        var previous = m.smile
        for _ in 0..<40 {
            m = m.updated(rawSmile: 1, rawBrowRaise: 1, rawJawOpen: 1, dt: 0.05)
            // Strictly increasing toward the target, never overshooting.
            XCTAssertGreaterThan(m.smile, previous)
            XCTAssertLessThanOrEqual(m.smile, 1)
            previous = m.smile
        }
        // After many steps it is very close to the target.
        XCTAssertEqual(m.smile, 1, accuracy: 1e-3)
        XCTAssertEqual(m.browRaise, 1, accuracy: 1e-3)
        XCTAssertEqual(m.jawOpen, 1, accuracy: 1e-3)
    }

    func testUpdate_convergesDownwardMonotonically() {
        var m = FaceExpressionMapping(smile: 1, browRaise: 1, jawOpen: 1, timeConstant: 0.15)
        var previous = m.smile
        for _ in 0..<40 {
            m = m.updated(rawSmile: 0, rawBrowRaise: 0, rawJawOpen: 0, dt: 0.05)
            XCTAssertLessThan(m.smile, previous)
            XCTAssertGreaterThanOrEqual(m.smile, 0)
            previous = m.smile
        }
        XCTAssertEqual(m.smile, 0, accuracy: 1e-3)
    }

    // MARK: - Neutral stays neutral

    func testNeutralFaceStaysZero() {
        var m = FaceExpressionMapping()
        for _ in 0..<50 {
            m = m.updated(rawSmile: 0, rawBrowRaise: 0, rawJawOpen: 0, dt: 0.033)
            XCTAssertEqual(m.smile, 0)
            XCTAssertEqual(m.browRaise, 0)
            XCTAssertEqual(m.jawOpen, 0)
        }
    }

    // MARK: - Clamping

    func testUpdate_clampsAboveOne() {
        var m = FaceExpressionMapping(timeConstant: 0.05)
        for _ in 0..<60 {
            m = m.updated(rawSmile: 2.5, rawBrowRaise: 9, rawJawOpen: 100, dt: 0.05)
            XCTAssertLessThanOrEqual(m.smile, 1)
            XCTAssertLessThanOrEqual(m.browRaise, 1)
            XCTAssertLessThanOrEqual(m.jawOpen, 1)
        }
        XCTAssertEqual(m.smile, 1, accuracy: 1e-3)
    }

    func testUpdate_clampsBelowZero() {
        var m = FaceExpressionMapping(smile: 0.5, browRaise: 0.5, jawOpen: 0.5, timeConstant: 0.05)
        for _ in 0..<60 {
            m = m.updated(rawSmile: -3, rawBrowRaise: -0.2, rawJawOpen: -100, dt: 0.05)
            XCTAssertGreaterThanOrEqual(m.smile, 0)
            XCTAssertGreaterThanOrEqual(m.browRaise, 0)
            XCTAssertGreaterThanOrEqual(m.jawOpen, 0)
        }
        XCTAssertEqual(m.smile, 0, accuracy: 1e-3)
    }

    func testInitClampsInputs() {
        let hi = FaceExpressionMapping(smile: 5, browRaise: 2, jawOpen: 1.5)
        XCTAssertEqual(hi.smile, 1)
        XCTAssertEqual(hi.browRaise, 1)
        XCTAssertEqual(hi.jawOpen, 1)
        let lo = FaceExpressionMapping(smile: -5, browRaise: -0.1, jawOpen: -9)
        XCTAssertEqual(lo.smile, 0)
        XCTAssertEqual(lo.browRaise, 0)
        XCTAssertEqual(lo.jawOpen, 0)
    }

    // MARK: - dt = 0 holds

    func testDeltaTimeZeroDoesNotChange() {
        let start = FaceExpressionMapping(smile: 0.3, browRaise: 0.6, jawOpen: 0.9)
        let same = start.updated(rawSmile: 1, rawBrowRaise: 1, rawJawOpen: 1, dt: 0)
        XCTAssertEqual(same, start)
        // Negative dt also holds.
        let same2 = start.updated(rawSmile: 1, rawBrowRaise: 1, rawJawOpen: 1, dt: -0.5)
        XCTAssertEqual(same2, start)
    }

    // MARK: - Determinism

    func testDeterministicForSameInputSequence() {
        func run() -> FaceExpressionMapping {
            var m = FaceExpressionMapping(timeConstant: 0.2)
            let targets: [(Float, Float, Float, Double)] = [
                (0.2, 0.1, 0.0, 0.03),
                (0.8, 0.4, 0.5, 0.05),
                (0.1, 0.9, 0.3, 0.02),
                (1.0, 0.0, 1.0, 0.04)
            ]
            for t in targets {
                m = m.updated(rawSmile: t.0, rawBrowRaise: t.1, rawJawOpen: t.2, dt: t.3)
            }
            return m
        }
        XCTAssertEqual(run(), run())
    }

    func testInstantTimeConstantSnapsToTarget() {
        let m = FaceExpressionMapping(timeConstant: 0)
            .updated(rawSmile: 0.7, rawBrowRaise: 0.2, rawJawOpen: 1.0, dt: 0.016)
        XCTAssertEqual(m.smile, 0.7, accuracy: 1e-6)
        XCTAssertEqual(m.browRaise, 0.2, accuracy: 1e-6)
        XCTAssertEqual(m.jawOpen, 1.0, accuracy: 1e-6)
    }

    // MARK: - GOLDEN: additive default-0 on BioSampleFrame

    /// BioSampleFrame is not Codable; the additive guarantee it CAN make is that a
    /// frame constructed WITHOUT the face fields carries `0` on all three (the
    /// memberwise default), i.e. every existing publisher is byte-identical.
    func testBioSampleFrameFaceFieldsDefaultToZero() {
        let frame = BioSampleFrame(
            timestamp: 0,
            heartRateBPM: 72,
            hrvNormalized: 0.5,
            breathRate: 12,
            breathPhase: 0.5,
            coherence: 0.5,
            motionEnergy: 0,
            source: .fallback
        )
        XCTAssertEqual(frame.faceSmile, 0)
        XCTAssertEqual(frame.faceBrowRaise, 0)
        XCTAssertEqual(frame.faceJawOpen, 0)
    }

    func testBioSampleFrameFaceFieldsRoundTripWhenProvided() {
        let frame = BioSampleFrame(
            timestamp: 0,
            heartRateBPM: 72,
            hrvNormalized: 0.5,
            breathRate: 12,
            breathPhase: 0.5,
            coherence: 0.5,
            motionEnergy: 0,
            source: .fallback,
            faceSmile: 0.42,
            faceBrowRaise: 0.7,
            faceJawOpen: 0.9
        )
        XCTAssertEqual(frame.faceSmile, 0.42, accuracy: 1e-6)
        XCTAssertEqual(frame.faceBrowRaise, 0.7, accuracy: 1e-6)
        XCTAssertEqual(frame.faceJawOpen, 0.9, accuracy: 1e-6)
    }

    // MARK: - ModSource face cases read the frame

    func testModSourceFaceCasesReadFrameFields() {
        let frame = BioSampleFrame(
            timestamp: 0,
            heartRateBPM: 72,
            hrvNormalized: 0.5,
            breathRate: 12,
            breathPhase: 0.5,
            coherence: 0.5,
            motionEnergy: 0,
            source: .fallback,
            faceSmile: 0.25,
            faceBrowRaise: 0.6,
            faceJawOpen: 0.8
        )
        XCTAssertEqual(ModSource.faceSmile.rawValue(from: frame), 0.25, accuracy: 1e-6)
        XCTAssertEqual(ModSource.faceBrow.rawValue(from: frame), 0.6, accuracy: 1e-6)
        XCTAssertEqual(ModSource.faceJaw.rawValue(from: frame), 0.8, accuracy: 1e-6)
        // 0..1 sources normalize to identity.
        XCTAssertEqual(ModSource.faceSmile.normalizedValue(from: frame), 0.25, accuracy: 1e-6)
        XCTAssertEqual(ModSource.faceSmile.range, 0...1)
    }

    /// New cases are appended (CaseIterable order preserved) so persisted rawValue
    /// routes decode unchanged.
    func testModSourceRawValuesStable() {
        XCTAssertEqual(ModSource.faceSmile.rawValue, "faceSmile")
        XCTAssertEqual(ModSource.faceBrow.rawValue, "faceBrow")
        XCTAssertEqual(ModSource.faceJaw.rawValue, "faceJaw")
        // The pre-existing cases keep their positions at the front.
        XCTAssertEqual(Array(ModSource.allCases.prefix(6)),
                       [.heartRate, .hrv, .breathRate, .breathPhase, .coherence, .motion])
    }
}
