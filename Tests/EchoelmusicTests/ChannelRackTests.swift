// ChannelRackTests.swift
// Echoelmusic — the Channel-Rack mixer gate (mute / solo) on BeatPlayer.
//
// ⚠ THE FEATURE IS GONE (#167, 2026-07-27). `ChannelRackView` is deleted, and so are
// the `mutes`/`solos` arrays and the `trigger` gate that called this rule. This file
// is now the only place in the repo the name "ChannelRack" survives, so read it as a
// test for a pure function, not for a shipping surface: `BeatPlayer.shouldSound` is a
// `nonisolated static` rule that takes both arrays as arguments and has no production
// caller. It is kept on purpose — the rule is correct and cheap to hold — and it goes
// when the drum voices it used to gate go.

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
