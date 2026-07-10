// WaveformReducerTests.swift — locks the Stage-2 waveform reduction (pure, Linux CI).

import XCTest
@testable import Echoelmusic

final class WaveformReducerTests: XCTestCase {

    func testReduce_knownSignal_minMaxRms() {
        // Two buckets of 4: [-1,1,0,0] and [0.5,-0.5,0.5,-0.5].
        let s: [Float] = [-1, 1, 0, 0, 0.5, -0.5, 0.5, -0.5]
        let b = WaveformReducer.reduce(s, bucketSize: 4)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0].min, -1); XCTAssertEqual(b[0].max, 1)
        XCTAssertEqual(b[0].rms, (0.5 as Float).squareRoot(), accuracy: 1e-6)
        XCTAssertEqual(b[1].min, -0.5); XCTAssertEqual(b[1].max, 0.5)
        XCTAssertEqual(b[1].rms, 0.5, accuracy: 1e-6)
    }

    func testReduce_partialLastBucket_andEmpty_andClamp() {
        let b = WaveformReducer.reduce([0.2, -0.4, 0.6], bucketSize: 2)
        XCTAssertEqual(b.count, 2)                       // 2 + 1 partial
        XCTAssertEqual(b[1].min, 0.6); XCTAssertEqual(b[1].max, 0.6)
        XCTAssertTrue(WaveformReducer.reduce([], bucketSize: 256).isEmpty)
        XCTAssertEqual(WaveformReducer.reduce([1, -1], bucketSize: 0).count, 2) // size clamps to 1
    }

    func testFoldStereo_keepsLargerMagnitudeSigned() {
        let out = WaveformReducer.foldStereo(left: [0.9, -0.1, -0.7],
                                             right: [-0.2, 0.8, 0.7])
        XCTAssertEqual(out, [0.9, 0.8, -0.7])            // sign preserved, extremes win
    }

    func testDownsample_preservesExtremes() {
        let fine = WaveformReducer.reduce([-1, 0, 0, 0, 0, 0, 0, 1], bucketSize: 2) // 4 buckets
        let coarse = WaveformReducer.downsample(fine, factor: 4)
        XCTAssertEqual(coarse.count, 1)
        XCTAssertEqual(coarse[0].min, -1)                 // extremes never vanish
        XCTAssertEqual(coarse[0].max, 1)
    }
}
