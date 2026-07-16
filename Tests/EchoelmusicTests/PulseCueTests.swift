// PulseCueTests.swift
// Pure, Linux-CI coverage for the rPPG coaching classification: the full hint,
// the compact header label, and which cues are user-actionable (drive the amber).

import XCTest
@testable import Echoelmusic

final class PulseCueTests: XCTestCase {

    func testFullHint_matchesTheShippedWording() {
        // UX-1: denied camera access names the ONLY real fix (Settings), never
        // placement coaching — "Cover camera" can't help a permission dead end.
        XCTAssertEqual(PulseCue.cameraDenied.fullHint,
                       "Camera access is off — enable it in Settings to read your pulse")
        XCTAssertEqual(PulseCue.locked.fullHint, "Locked")
        XCTAssertEqual(PulseCue.coverLens.fullHint, "Cover the rear camera + flash")
        XCTAssertEqual(PulseCue.tooBright.fullHint, "Press a little lighter")
        XCTAssertEqual(PulseCue.holdStill.fullHint, "Hold still — keep your finger steady")
        XCTAssertEqual(PulseCue.pressGently.fullHint, "Press gently and hold still")
        XCTAssertEqual(PulseCue.finding.fullHint, "Hold still — finding your pulse…")
    }

    func testShortLabel_isCompactForTheHeader() {
        // Header room is tight — every short label must stay brief.
        for cue in [PulseCue.cameraDenied, .locked, .coverLens, .tooBright, .holdStill, .pressGently, .finding] {
            XCTAssertLessThanOrEqual(cue.shortLabel.count, 12, "\(cue) short label too long")
            XCTAssertFalse(cue.shortLabel.isEmpty)
        }
        XCTAssertEqual(PulseCue.tooBright.shortLabel, "Too bright")
    }

    func testIsActionable_onlyForCorrectablePlacementIssues() {
        // Amber only when the user can DO something now. Denied access IS
        // actionable — the user can flip the switch in Settings right now.
        XCTAssertTrue(PulseCue.cameraDenied.isActionable)
        XCTAssertTrue(PulseCue.coverLens.isActionable)
        XCTAssertTrue(PulseCue.tooBright.isActionable)
        XCTAssertTrue(PulseCue.holdStill.isActionable)
        XCTAssertTrue(PulseCue.pressGently.isActionable)
        // Not actionable: locked is fine, finding is normal warmup (just wait).
        XCTAssertFalse(PulseCue.locked.isActionable)
        XCTAssertFalse(PulseCue.finding.isActionable)
    }
}
