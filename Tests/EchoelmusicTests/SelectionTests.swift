// SelectionTests.swift
// Echoelmusic — app-wide single source of truth for selection (cohesion layer).

import XCTest
@testable import Echoelmusic

@MainActor
final class SelectionTests: XCTestCase {

    func testDefault_isEmpty() {
        let s = Selection()
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.current)
    }

    func testSelect_setsCurrent() {
        let s = Selection()
        s.select(.step(track: 2, step: 5))
        XCTAssertEqual(s.current, .step(track: 2, step: 5))
        XCTAssertFalse(s.isEmpty)
    }

    func testSelect_replacesPrevious() {
        let s = Selection()
        s.select(.pad(3))
        s.select(.clip(slot: 1))
        XCTAssertEqual(s.current, .clip(slot: 1))
    }

    func testClear_emptiesSelection() {
        let s = Selection()
        s.select(.pad(0))
        s.clear()
        XCTAssertTrue(s.isEmpty)
    }

    func testToggle_selectsThenClearsSameTarget() {
        let s = Selection()
        let id = UUID()
        s.toggle(.note(id: id))
        XCTAssertEqual(s.current, .note(id: id))
        s.toggle(.note(id: id))     // same target → clears
        XCTAssertTrue(s.isEmpty)
    }

    func testToggle_switchesBetweenDifferentTargets() {
        let s = Selection()
        s.toggle(.route(id: UUID()))
        let patchID = UUID()
        s.toggle(.patch(id: patchID)) // different → switches, not clears
        XCTAssertEqual(s.current, .patch(id: patchID))
    }

    func testIsSelected_matchesOnlyCurrent() {
        let s = Selection()
        s.select(.step(track: 0, step: 0))
        XCTAssertTrue(s.isSelected(.step(track: 0, step: 0)))
        XCTAssertFalse(s.isSelected(.step(track: 0, step: 1)))
        XCTAssertFalse(s.isSelected(.pad(0)))
    }

    func testTargets_distinctCasesAreNotEqual() {
        XCTAssertNotEqual(SelectionTarget.pad(0), .step(track: 0, step: 0))
        XCTAssertNotEqual(SelectionTarget.clip(slot: 0), .pad(0))
    }
}
