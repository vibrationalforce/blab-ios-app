import XCTest
@testable import Echoelmusic

final class TapTempoTests: XCTestCase {

    func testFirstTap_returnsNil() {
        var t = TapTempo()
        XCTAssertNil(t.tap(at: 0))
    }

    func testTwoTaps_halfSecondApart_is120BPM() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        XCTAssertEqual(t.tap(at: 0.5) ?? 0, 120, accuracy: 0.5)
    }

    func testSteadyTaps_oneSecondApart_is60BPM() {
        var t = TapTempo()
        var bpm: Double = 0
        for i in 0...4 { if let b = t.tap(at: Double(i)) { bpm = b } }
        XCTAssertEqual(bpm, 60, accuracy: 0.5)
    }

    func testLongGap_resetsMeasurement() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        _ = t.tap(at: 0.5)          // establishes 120
        // A 5 s gap is well beyond resetGap → the next tap starts fresh (nil).
        XCTAssertNil(t.tap(at: 5.5))
    }

    func testEstimate_isClampedToRange() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        // 10 ms apart → 6000 BPM raw → clamps to maxBPM (240).
        XCTAssertEqual(t.tap(at: 0.01) ?? 0, 240, accuracy: 0.001)
    }
}
