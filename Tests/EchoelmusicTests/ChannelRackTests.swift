// ChannelRackTests.swift
// Echoelmusic — the Channel-Rack mixer gate (mute / solo) on BeatPlayer.

import XCTest
@testable import Echoelmusic

final class ChannelRackTests: XCTestCase {

    private let n = 8
    private func allFalse() -> [Bool] { [Bool](repeating: false, count: 8) }

    func testNoMuteNoSolo_allSound() {
        let m = allFalse(), s = allFalse()
        for t in 0..<n {
            XCTAssertTrue(BeatPlayer.shouldSound(track: t, mutes: m, solos: s))
        }
    }

    func testMutedTrack_silent() {
        var m = allFalse(); m[2] = true
        XCTAssertFalse(BeatPlayer.shouldSound(track: 2, mutes: m, solos: allFalse()))
        XCTAssertTrue(BeatPlayer.shouldSound(track: 3, mutes: m, solos: allFalse()))
    }

    func testSolo_onlySoloedSound() {
        var s = allFalse(); s[1] = true
        XCTAssertTrue(BeatPlayer.shouldSound(track: 1, mutes: allFalse(), solos: s))
        XCTAssertFalse(BeatPlayer.shouldSound(track: 0, mutes: allFalse(), solos: s),
                       "non-soloed channels go silent when any solo is active")
    }

    func testMuteWinsOverSolo() {
        var m = allFalse(); m[1] = true
        var s = allFalse(); s[1] = true
        XCTAssertFalse(BeatPlayer.shouldSound(track: 1, mutes: m, solos: s),
                       "a muted channel stays silent even if soloed")
    }

    func testMultipleSolos() {
        var s = allFalse(); s[0] = true; s[3] = true
        XCTAssertTrue(BeatPlayer.shouldSound(track: 0, mutes: allFalse(), solos: s))
        XCTAssertTrue(BeatPlayer.shouldSound(track: 3, mutes: allFalse(), solos: s))
        XCTAssertFalse(BeatPlayer.shouldSound(track: 5, mutes: allFalse(), solos: s))
    }

    func testOutOfRange_defaultsToAudible() {
        XCTAssertTrue(BeatPlayer.shouldSound(track: 99, mutes: allFalse(), solos: allFalse()))
    }
}
