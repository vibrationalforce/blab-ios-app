// LightFixtureGroupTests.swift
// Echoel — EchoelLux L2: a pure model composing ONE DMX universe from N fixtures,
// all scaled by a Grand Master and cut by Blackout (the L1 master law fanned out).
// No Network import (raw channel bytes only), deterministic, Codable-migratable.

import XCTest
import Foundation
@testable import Echoelmusic

final class LightFixtureGroupTests: XCTestCase {

    private func fixture(_ ch: Int, _ dim: Float, _ colour: [UInt8]) -> LightFixture {
        LightFixture(startChannel: ch, dimmerUnit: dim, colour: colour)
    }

    // MARK: - Compose

    func testCompose_placesEachFixtureAtItsStartChannel() {
        let group = LightFixtureGroup(fixtures: [
            fixture(1, 1, [10, 20, 30]),
            fixture(5, 1, [40, 50, 60]),
        ])
        XCTAssertEqual(group.composeUniverse(),
                       [255, 10, 20, 30, 255, 40, 50, 60],
                       "dimmer byte at the start channel, colour bytes right after")
    }

    func testCompose_grandMasterScalesEveryDimmer_colourUntouched() {
        let group = LightFixtureGroup(fixtures: [fixture(1, 1, [255, 0, 0])], grandMaster: 0.5)
        let buf = group.composeUniverse()
        XCTAssertEqual(Int(buf[0]), 127, "0.5 master → half dimmer")
        XCTAssertEqual(Array(buf[1...3]), [255, 0, 0], "colour is not scaled by the master")
    }

    func testCompose_blackoutZeroesAllDimmers_keepsColour() {
        // Non-overlapping fixtures at ch1 (1..4) and ch5 (5..8).
        let group = LightFixtureGroup(fixtures: [
            fixture(1, 1, [11, 22, 33]),
            fixture(5, 1, [44, 55, 66]),
        ], blackout: true)
        let buf = group.composeUniverse()
        XCTAssertEqual(Int(buf[0]), 0, "blackout cuts the first fixture's dimmer")
        XCTAssertEqual(Int(buf[4]), 0, "…and the second fixture's dimmer")
        XCTAssertEqual(Array(buf[1...3]), [11, 22, 33], "colour bytes survive a blackout")
        XCTAssertEqual(Array(buf[5...7]), [44, 55, 66])
    }

    func testCompose_emptyGroupIsSafeZeroBuffer() {
        XCTAssertEqual(LightFixtureGroup().composeUniverse(), [])
    }

    func testCompose_clampsToUniverseSize() {
        // A fixture straddling the 512 ceiling must not grow the buffer past 512.
        let group = LightFixtureGroup(fixtures: [fixture(511, 1, [1, 2, 3, 4])])
        let buf = group.composeUniverse()
        XCTAssertLessThanOrEqual(buf.count, LightFixtureGroup.universeSize)
        XCTAssertEqual(buf.count, 512)
        XCTAssertEqual(Int(buf[510]), 255, "dimmer lands at channel 511")
        XCTAssertEqual(Int(buf[511]), 1, "first colour byte lands at 512; the rest clamp away")
    }

    func testCompose_outOfRangeAndOverlappingChannelsClampNotCrash() {
        let group = LightFixtureGroup(fixtures: [
            fixture(0, 1, [9]),        // non-positive address → dropped
            fixture(-4, 1, [9]),       // negative → dropped
            fixture(9000, 1, [9]),     // beyond the universe → dropped
            fixture(1, 0.5, [7, 8]),   // valid
            fixture(2, 1, [1, 2]),     // overlaps fixture at 1 → later wins on shared channels
        ])
        let buf = group.composeUniverse()
        XCTAssertEqual(buf.count, 4, "only the in-range fixtures size the buffer (ch2 + 2 colour = 4)")
        XCTAssertEqual(Int(buf[0]), 127, "ch1 dimmer (0.5)")
        XCTAssertEqual(Int(buf[1]), 255, "ch2 dimmer overwrote ch1's first colour byte (overlap: later wins)")
    }

    func testCompose_isDeterministic() {
        let group = LightFixtureGroup(fixtures: [fixture(1, 0.7, [100, 150, 200])], grandMaster: 0.8)
        XCTAssertEqual(group.composeUniverse(), group.composeUniverse())
    }

    // MARK: - Clamps

    func testInit_clampsMasterAndDimmer() {
        XCTAssertEqual(LightFixtureGroup(grandMaster: 5).grandMaster, 1)
        XCTAssertEqual(LightFixtureGroup(grandMaster: -1).grandMaster, 0)
        XCTAssertEqual(LightFixtureGroup(grandMaster: .nan).grandMaster, 0)
        XCTAssertEqual(fixture(1, 9, []).dimmerUnit, 1)
        XCTAssertEqual(fixture(1, .nan, []).dimmerUnit, 0)
    }

    // MARK: - Codable

    func testGroup_codableRoundTrip() throws {
        let group = LightFixtureGroup(fixtures: [
            LightFixture(id: UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!,
                         startChannel: 3, dimmerUnit: 0.5, colour: [1, 2, 3]),
        ], grandMaster: 0.25, blackout: true)
        let back = try JSONDecoder().decode(LightFixtureGroup.self,
                                            from: JSONEncoder().encode(group))
        XCTAssertEqual(back, group)
    }

    func testLegacyJSON_missingKeysDecodeAsDefaults() throws {
        let group = try JSONDecoder().decode(LightFixtureGroup.self, from: Data("{}".utf8))
        XCTAssertEqual(group.fixtures, [])
        XCTAssertEqual(group.grandMaster, 1)
        XCTAssertFalse(group.blackout)

        let fx = try JSONDecoder().decode(LightFixture.self, from: Data(#"{"startChannel":3}"#.utf8))
        XCTAssertEqual(fx.startChannel, 3)
        XCTAssertEqual(fx.dimmerUnit, 1)
        XCTAssertEqual(fx.colour, [])
    }
}
