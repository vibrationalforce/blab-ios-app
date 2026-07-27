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

    // MARK: - Export target resolution (the "No target" lie)

    func testExportTarget_offMeansDoNotNormalise() {
        // The whole point of the fix. Until now the export resolved "No target" to
        // −14 LUFS, so choosing it did exactly what choosing "Streaming (−14)" did:
        // a control that reads "off" and is not off.
        XCTAssertNil(LoudnessTarget.exportTargetLUFS(rawValue: LoudnessTarget.off.rawValue),
                     "\"No target\" must disable normalisation, not silently mean −14")
    }

    func testExportTarget_eachTargetResolvesToItsOwnLoudness() {
        XCTAssertEqual(LoudnessTarget.exportTargetLUFS(rawValue: "streaming"), -14)
        XCTAssertEqual(LoudnessTarget.exportTargetLUFS(rawValue: "podcast"), -16)
        XCTAssertEqual(LoudnessTarget.exportTargetLUFS(rawValue: "broadcastEBU"), -23)
        XCTAssertEqual(LoudnessTarget.exportTargetLUFS(rawValue: "cinema"), -24)
    }

    func testExportTarget_unreadableSettingFallsBackToTheDefaultNotToOff() {
        // HONEST LABEL: this asserts UNCHANGED behaviour, not the fix — the old
        // expression also produced −14 for an unparseable raw. It is a regression pin
        // (it would catch a future `?? .off`), not evidence that the two nils are now
        // separated; `testExportTarget_offMeansDoNotNormalise` is the only test that
        // distinguishes new code from old.
        //
        // Derived from `StudioDefaultKeys`, not hardcoded to −14: the resolver's
        // `?? .streaming` duplicates the registered default with no compile-time link,
        // so changing the default tomorrow must fail here rather than silently leave
        // the resolver behind while the doc comment becomes a lie.
        let registeredDefault = LoudnessTarget(rawValue: StudioDefaultKeys.loudnessTarget.value)?.integratedLUFS
        XCTAssertEqual(LoudnessTarget.exportTargetLUFS(rawValue: "not-a-target"), registeredDefault)
        XCTAssertEqual(LoudnessTarget.exportTargetLUFS(rawValue: ""), registeredDefault)
        XCTAssertNotNil(registeredDefault, "the registered default must be a real target, never \"off\"")
    }
}
