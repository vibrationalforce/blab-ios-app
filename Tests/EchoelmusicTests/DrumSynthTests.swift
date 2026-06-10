// DrumSynthTests.swift
// Echoel — hybrid drum model: pad mode + synth params persistence.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class DrumSynthTests: XCTestCase {

    func testPadModeCodableRoundTrip() throws {
        let modes: [BeatPlayer.PadMode] = [.sample, .synth, .blend(0.35)]
        for mode in modes {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(BeatPlayer.PadMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testDrumSynthParamsCodableRoundTrip() throws {
        var params = DrumSynthParams()
        params.material = "Bell"
        params.frequency = 180
        params.damping = 0.6
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(DrumSynthParams.self, from: data)
        XCTAssertEqual(decoded, params)
    }

    func testDefaultModeIsSample() {
        let player = BeatPlayer()
        XCTAssertEqual(player.modes.count, BeatPlayer.trackNames.count)
        XCTAssertTrue(player.modes.allSatisfy { $0 == .sample },
                      "pads default to sample mode so existing behavior is unchanged")
    }

    func testSetModeAndSynthParams() {
        let player = BeatPlayer()
        player.setMode(track: 0, .blend(0.5))
        XCTAssertEqual(player.modes[0], .blend(0.5))

        var params = DrumSynthParams()
        params.frequency = 220
        player.setSynthParams(track: 1, params)
        XCTAssertEqual(player.synthParams[1].frequency, 220)
    }
}
#endif
