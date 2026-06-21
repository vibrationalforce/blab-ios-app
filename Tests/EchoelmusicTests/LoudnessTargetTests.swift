import XCTest
@testable import Echoelmusic

final class LoudnessTargetTests: XCTestCase {

    private let floor: Float = -120

    func testOff_isAlwaysUnknown() {
        XCTAssertEqual(LoudnessTarget.off.compliance(integratedLUFS: -14, floor: floor), .unknown)
    }

    func testSilence_isUnknown() {
        // At the floor → nothing playing → unknown, not "too quiet".
        XCTAssertEqual(LoudnessTarget.streaming.compliance(integratedLUFS: floor, floor: floor), .unknown)
    }

    func testOnTarget_withinTolerance() {
        XCTAssertEqual(LoudnessTarget.streaming.compliance(integratedLUFS: -14.0, floor: floor), .onTarget)
        XCTAssertEqual(LoudnessTarget.streaming.compliance(integratedLUFS: -13.2, floor: floor), .onTarget)
        XCTAssertEqual(LoudnessTarget.streaming.compliance(integratedLUFS: -14.8, floor: floor), .onTarget)
    }

    func testTooLoud_aboveTargetPlusTolerance() {
        XCTAssertEqual(LoudnessTarget.streaming.compliance(integratedLUFS: -11.0, floor: floor), .tooLoud)
    }

    func testTooQuiet_belowTargetMinusTolerance() {
        XCTAssertEqual(LoudnessTarget.streaming.compliance(integratedLUFS: -20.0, floor: floor), .tooQuiet)
    }

    func testTruePeak_exceedsCeiling() {
        XCTAssertTrue(LoudnessTarget.streaming.truePeakExceeds(-0.5, floor: floor))  // > -1 dBTP
        XCTAssertFalse(LoudnessTarget.streaming.truePeakExceeds(-1.5, floor: floor)) // under ceiling
    }

    func testTruePeak_ignoredWhenOffOrSilent() {
        XCTAssertFalse(LoudnessTarget.off.truePeakExceeds(0.0, floor: floor))
        XCTAssertFalse(LoudnessTarget.streaming.truePeakExceeds(floor, floor: floor))
    }
}
