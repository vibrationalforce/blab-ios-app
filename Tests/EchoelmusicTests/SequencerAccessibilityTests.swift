// SequencerAccessibilityTests.swift
// Echoel — the VoiceOver text a blind musician hears on the Clips + Arrange
// surfaces. Pure strings, hand-computed expectations.

import XCTest
@testable import Echoelmusic

final class SequencerAccessibilityTests: XCTestCase {

    func testBarsPluralize() {
        XCTAssertEqual(SequencerA11y.bars(1), "1 bar")
        XCTAssertEqual(SequencerA11y.bars(4), "4 bars")
        XCTAssertEqual(SequencerA11y.bars(0), "1 bar", "clamps to a valid minimum")
    }

    func testNotesPluralize() {
        XCTAssertEqual(SequencerA11y.notes(0), "no notes")
        XCTAssertEqual(SequencerA11y.notes(1), "1 note")
        XCTAssertEqual(SequencerA11y.notes(8), "8 notes")
        XCTAssertEqual(SequencerA11y.notes(-5), "no notes", "clamps negatives")
    }

    func testContentSummary() {
        XCTAssertEqual(SequencerA11y.content(hasDrums: true, noteCount: 8), "beat and 8 notes")
        XCTAssertEqual(SequencerA11y.content(hasDrums: true, noteCount: 0), "beat")
        XCTAssertEqual(SequencerA11y.content(hasDrums: false, noteCount: 3), "3 notes")
        XCTAssertEqual(SequencerA11y.content(hasDrums: false, noteCount: 0), "empty")
    }

    func testClipLabel() {
        XCTAssertEqual(
            SequencerA11y.clipLabel(name: "Verse", hasDrums: true, noteCount: 8, isQueued: false),
            "Clip Verse, beat and 8 notes"
        )
        XCTAssertEqual(
            SequencerA11y.clipLabel(name: "Drop", hasDrums: true, noteCount: 0, isQueued: true),
            "Clip Drop, beat, queued to launch on the next bar"
        )
    }

    func testClipHintReflectsQuantizeState() {
        XCTAssertEqual(SequencerA11y.clipHint(isPlaying: true, quantizeEnabled: true),
                       "Double tap to launch at the next bar")
        XCTAssertEqual(SequencerA11y.clipHint(isPlaying: true, quantizeEnabled: false),
                       "Double tap to launch")
        XCTAssertEqual(SequencerA11y.clipHint(isPlaying: false, quantizeEnabled: true),
                       "Double tap to launch")
    }

    func testQuantizeValue() {
        XCTAssertEqual(SequencerA11y.quantizeValue(true), "on")
        XCTAssertEqual(SequencerA11y.quantizeValue(false), "off")
    }

    func testSectionLabel() {
        XCTAssertEqual(
            SequencerA11y.sectionLabel(name: "Verse", clipName: "Drums", lengthBars: 4,
                                       position: 2, total: 5, isPlaying: false),
            "Section 2 of 5, Verse, clip Drums, 4 bars"
        )
        XCTAssertEqual(
            SequencerA11y.sectionLabel(name: "Break", clipName: nil, lengthBars: 1,
                                       position: 3, total: 3, isPlaying: true),
            "Section 3 of 3, Break, silent gap, 1 bar, now playing"
        )
    }

    func testArrangementTransportLabel() {
        XCTAssertEqual(SequencerA11y.arrangementTransportLabel(isPlaying: false, isEmpty: true),
                       "Play song, no sections yet")
        XCTAssertEqual(SequencerA11y.arrangementTransportLabel(isPlaying: false, isEmpty: false),
                       "Play song")
        XCTAssertEqual(SequencerA11y.arrangementTransportLabel(isPlaying: true, isEmpty: false),
                       "Stop song")
    }

    func testLoopLabel() {
        XCTAssertEqual(SequencerA11y.loopLabel(true), "Loop song, on")
        XCTAssertEqual(SequencerA11y.loopLabel(false), "Loop song, off")
    }

    func testSectionHintPresent() {
        XCTAssertFalse(SequencerA11y.sectionHint.isEmpty)
    }
}
