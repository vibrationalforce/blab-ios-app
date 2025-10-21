import XCTest
@testable import Blab

/// Tests for FaceToAudioMapper
final class FaceToAudioMapperTests: XCTestCase {

    var sut: FaceToAudioMapper!

    override func setUp() {
        super.setUp()
        sut = FaceToAudioMapper()
        sut.smoothingFactor = 0  // Disable smoothing for predictable tests
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Jaw Open → Filter Cutoff Tests

    func testJawClosedMapsToLowFrequency() {
        let expression = FaceExpression(jawOpen: 0.0)
        let params = sut.mapToAudio(faceExpression: expression)

        // Jaw closed should map to minimum frequency (200 Hz)
        XCTAssertEqual(params.filterCutoff, 200, accuracy: 10,
                       "Closed jaw should map to 200 Hz")
    }

    func testJawOpenMapsToHighFrequency() {
        let expression = FaceExpression(jawOpen: 1.0)
        let params = sut.mapToAudio(faceExpression: expression)

        // Jaw fully open should map to maximum frequency (8000 Hz)
        XCTAssertEqual(params.filterCutoff, 8000, accuracy: 100,
                       "Fully open jaw should map to 8000 Hz")
    }

    func testJawHalfOpenMapsTomidFrequency() {
        let expression = FaceExpression(jawOpen: 0.5)
        let params = sut.mapToAudio(faceExpression: expression)

        // Jaw half open should map to mid-range frequency
        // Exponential curve, so not exactly 4100 Hz (linear midpoint)
        // Should be somewhere between 1000-3000 Hz
        XCTAssertGreaterThan(params.filterCutoff, 1000)
        XCTAssertLessThan(params.filterCutoff, 3000)
    }

    func testJawOpenThreshold() {
        // Very small jaw open (below threshold) should still map to minimum
        let expression = FaceExpression(jawOpen: 0.03)  // Below default 0.05 threshold
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.filterCutoff, 200, accuracy: 10,
                       "Jaw open below threshold should map to minimum frequency")
    }

    // MARK: - Smile → Stereo Width Tests

    func testNoSmileMapsToNarrowStereo() {
        let expression = FaceExpression(
            mouthSmileLeft: 0.0,
            mouthSmileRight: 0.0
        )
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.stereoWidth, 0.5, accuracy: 0.1,
                       "No smile should map to narrow stereo (0.5)")
    }

    func testFullSmileMapsToWideStereo() {
        let expression = FaceExpression(
            mouthSmileLeft: 1.0,
            mouthSmileRight: 1.0
        )
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.stereoWidth, 2.0, accuracy: 0.1,
                       "Full smile should map to wide stereo (2.0)")
    }

    // MARK: - Eyebrow Raise → Reverb Size Tests

    func testNeutralBrowMapsToSmallReverb() {
        let expression = FaceExpression(
            browInnerUp: 0.0,
            browOuterUpLeft: 0.0,
            browOuterUpRight: 0.0
        )
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.reverbSize, 0.5, accuracy: 0.1,
                       "Neutral brow should map to small reverb (0.5)")
    }

    func testRaisedBrowMapsToLargeReverb() {
        let expression = FaceExpression(
            browInnerUp: 1.0,
            browOuterUpLeft: 1.0,
            browOuterUpRight: 1.0
        )
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.reverbSize, 5.0, accuracy: 0.1,
                       "Raised brows should map to large reverb (5.0)")
    }

    // MARK: - Mouth Funnel → Resonance Tests

    func testNoFunnelMapsToLowResonance() {
        let expression = FaceExpression(mouthFunnel: 0.0)
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.filterResonance, 0.707, accuracy: 0.1,
                       "No funnel should map to Butterworth Q (0.707)")
    }

    func testFullFunnelMapsToHighResonance() {
        let expression = FaceExpression(mouthFunnel: 1.0)
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.filterResonance, 5.0, accuracy: 0.1,
                       "Full funnel should map to high resonance (5.0)")
    }

    // MARK: - Mouth Pucker → Modulation Depth Tests

    func testPuckerMapsToModulationDepth() {
        let expression = FaceExpression(mouthPucker: 0.7)
        let params = sut.mapToAudio(faceExpression: expression)

        XCTAssertEqual(params.modulationDepth, 0.7, accuracy: 0.01,
                       "Pucker should directly map to modulation depth")
    }

    // MARK: - Smoothing Tests

    func testSmoothingReducesAbruptChanges() {
        sut.smoothingFactor = 0.9  // High smoothing

        // First update: jaw closed
        let expression1 = FaceExpression(jawOpen: 0.0)
        let params1 = sut.mapToAudio(faceExpression: expression1)
        XCTAssertEqual(params1.filterCutoff, 200, accuracy: 20)

        // Second update: jaw fully open (should be smoothed, not instant)
        let expression2 = FaceExpression(jawOpen: 1.0)
        let params2 = sut.mapToAudio(faceExpression: expression2)

        // With high smoothing, should NOT jump directly to 8000 Hz
        XCTAssertLessThan(params2.filterCutoff, 8000)
        XCTAssertGreaterThan(params2.filterCutoff, 200)
    }

    func testNoSmoothingAllowsInstantChanges() {
        sut.smoothingFactor = 0.0  // No smoothing

        let expression1 = FaceExpression(jawOpen: 0.0)
        _ = sut.mapToAudio(faceExpression: expression1)

        let expression2 = FaceExpression(jawOpen: 1.0)
        let params2 = sut.mapToAudio(faceExpression: expression2)

        // With no smoothing, should jump directly to 8000 Hz
        XCTAssertEqual(params2.filterCutoff, 8000, accuracy: 100)
    }

    // MARK: - FaceExpression Computed Properties Tests

    func testFaceExpressionSmileComputed() {
        let expression = FaceExpression(
            mouthSmileLeft: 0.6,
            mouthSmileRight: 0.8
        )

        XCTAssertEqual(expression.smile, 0.7, accuracy: 0.01,
                       "Smile should be average of left and right")
    }

    func testFaceExpressionBrowRaiseComputed() {
        let expression = FaceExpression(
            browInnerUp: 0.3,
            browOuterUpLeft: 0.6,
            browOuterUpRight: 0.9
        )

        XCTAssertEqual(expression.browRaise, 0.6, accuracy: 0.01,
                       "Brow raise should be average of three brow values")
    }

    func testFaceExpressionEyeBlinkComputed() {
        let expression = FaceExpression(
            eyeBlinkLeft: 0.4,
            eyeBlinkRight: 0.6
        )

        XCTAssertEqual(expression.eyeBlink, 0.5, accuracy: 0.01,
                       "Eye blink should be average of left and right")
    }

    // MARK: - Edge Cases

    func testAllParametersWithNeutralFace() {
        let neutralExpression = FaceExpression()  // All zeros
        let params = sut.mapToAudio(faceExpression: neutralExpression)

        // Verify all parameters have sensible neutral values
        XCTAssertEqual(params.filterCutoff, 200, accuracy: 20)
        XCTAssertEqual(params.filterResonance, 0.707, accuracy: 0.1)
        XCTAssertEqual(params.stereoWidth, 0.5, accuracy: 0.1)
        XCTAssertEqual(params.reverbSize, 0.5, accuracy: 0.1)
        XCTAssertEqual(params.modulationDepth, 0.0, accuracy: 0.01)
    }

    func testAllParametersWithExtremeFace() {
        let extremeExpression = FaceExpression(
            jawOpen: 1.0,
            mouthSmileLeft: 1.0,
            mouthSmileRight: 1.0,
            browInnerUp: 1.0,
            browOuterUpLeft: 1.0,
            browOuterUpRight: 1.0,
            mouthFunnel: 1.0,
            mouthPucker: 1.0
        )
        let params = sut.mapToAudio(faceExpression: extremeExpression)

        // Verify all parameters hit their maximum values
        XCTAssertEqual(params.filterCutoff, 8000, accuracy: 100)
        XCTAssertEqual(params.filterResonance, 5.0, accuracy: 0.1)
        XCTAssertEqual(params.stereoWidth, 2.0, accuracy: 0.1)
        XCTAssertEqual(params.reverbSize, 5.0, accuracy: 0.1)
        XCTAssertEqual(params.modulationDepth, 1.0, accuracy: 0.01)
    }
}
