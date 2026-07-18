// ArrangementTests.swift
// Echoel — the song timeline: Codable round-trip, the pure bar-advance cursor
// (section chaining, looping, finishing, mid-play deletion), and the store's
// structural edits. The cursor is the heart of arrangement playback, so it gets
// tick-by-tick coverage with hand-computed expectations.

import XCTest
@testable import Echoelmusic

final class ArrangementTests: XCTestCase {

    // MARK: - Model

    func testSectionClampsLengthToAtLeastOneBar() {
        let s = ArrangementSection(name: "A", lengthBars: 0)
        XCTAssertEqual(s.lengthBars, 1)
        let n = ArrangementSection(name: "B", lengthBars: -5)
        XCTAssertEqual(n.lengthBars, 1)
    }

    func testTotalBarsSumsSections() {
        let song = Arrangement(sections: [
            ArrangementSection(name: "Intro", lengthBars: 2),
            ArrangementSection(name: "Verse", lengthBars: 4),
            ArrangementSection(name: "Drop", lengthBars: 8)
        ])
        XCTAssertEqual(song.totalBars, 14)
        XCTAssertEqual(song.sectionLengths, [2, 4, 8])
    }

    func testArrangementCodableRoundTrip() throws {
        let song = Arrangement(sections: [
            ArrangementSection(clipID: UUID(), name: "Intro", colorIndex: 1, lengthBars: 2),
            ArrangementSection(clipID: nil, name: "Gap", colorIndex: 0, lengthBars: 1)
        ])
        let data = try JSONEncoder().encode(song)
        let decoded = try JSONDecoder().decode(Arrangement.self, from: data)
        XCTAssertEqual(decoded, song)
    }

    // MARK: - Cursor: chaining

    func testCursorStaysInMultiBarSectionUntilItEnds() {
        var cursor = ArrangementCursor()
        let lengths = [3, 1]
        // Bar 1 of a 3-bar section: still inside.
        var a = cursor.completeBar(sectionLengths: lengths, loop: false)
        XCTAssertFalse(a.enteredNewSection)
        XCTAssertEqual(cursor.index, 0)
        XCTAssertEqual(cursor.barsIntoSection, 1)
        // Bar 2: still inside.
        a = cursor.completeBar(sectionLengths: lengths, loop: false)
        XCTAssertFalse(a.enteredNewSection)
        XCTAssertEqual(cursor.barsIntoSection, 2)
        // Bar 3 completes the section → advance to section 1.
        a = cursor.completeBar(sectionLengths: lengths, loop: false)
        XCTAssertTrue(a.enteredNewSection)
        XCTAssertFalse(a.finished)
        XCTAssertEqual(cursor.index, 1)
        XCTAssertEqual(cursor.barsIntoSection, 0)
    }

    func testCursorAdvancesEverySingleBarSection() {
        var cursor = ArrangementCursor()
        let lengths = [1, 1, 1]
        let a1 = cursor.completeBar(sectionLengths: lengths, loop: false)
        XCTAssertTrue(a1.enteredNewSection); XCTAssertEqual(cursor.index, 1)
        let a2 = cursor.completeBar(sectionLengths: lengths, loop: false)
        XCTAssertTrue(a2.enteredNewSection); XCTAssertEqual(cursor.index, 2)
    }

    // MARK: - Cursor: loop vs finish

    func testCursorLoopsBackToStart() {
        var cursor = ArrangementCursor(index: 1, barsIntoSection: 0)
        let lengths = [1, 1]
        // Completing the last (index 1) section with loop → back to section 0.
        let a = cursor.completeBar(sectionLengths: lengths, loop: true)
        XCTAssertTrue(a.enteredNewSection)
        XCTAssertFalse(a.finished)
        XCTAssertEqual(cursor.index, 0)
        XCTAssertEqual(cursor.barsIntoSection, 0)
    }

    func testCursorFinishesWhenNotLooping() {
        var cursor = ArrangementCursor(index: 1, barsIntoSection: 0)
        let lengths = [1, 1]
        let a = cursor.completeBar(sectionLengths: lengths, loop: false)
        XCTAssertFalse(a.enteredNewSection)
        XCTAssertTrue(a.finished)
    }

    func testEmptyArrangementFinishesImmediately() {
        var cursor = ArrangementCursor()
        let a = cursor.completeBar(sectionLengths: [], loop: true)
        XCTAssertTrue(a.finished)
    }

    func testStaleIndexRecoversToStart() {
        var cursor = ArrangementCursor(index: 5, barsIntoSection: 0)
        let a = cursor.completeBar(sectionLengths: [1, 1], loop: false)
        XCTAssertTrue(a.enteredNewSection)
        XCTAssertEqual(cursor.index, 0)
    }

    func testSeekJumpsToSectionAndRestartsItsBars() {
        var cursor = ArrangementCursor(index: 0, barsIntoSection: 3)
        cursor.seek(to: 2, sectionCount: 4)
        XCTAssertEqual(cursor.index, 2)
        XCTAssertEqual(cursor.barsIntoSection, 0)   // restarts the section from bar 0
    }

    func testSeekOutOfRangeIsNoOp() {
        var cursor = ArrangementCursor(index: 1, barsIntoSection: 2)
        cursor.seek(to: 9, sectionCount: 3)         // past the end → ignored
        cursor.seek(to: -1, sectionCount: 3)        // negative → ignored
        XCTAssertEqual(cursor.index, 1)
        XCTAssertEqual(cursor.barsIntoSection, 2)
    }

    // MARK: - Store

    @MainActor
    func testStoreAddRemoveMove() {
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(name: "A", lengthBars: 2)
        store.addSection(name: "B", lengthBars: 1)
        store.addSection(name: "C", lengthBars: 4)
        XCTAssertEqual(store.sections.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(store.totalBars, 7)

        // Move C to the front.
        store.move(at: 2, by: -2)
        XCTAssertEqual(store.sections.map(\.name), ["C", "A", "B"])

        store.remove(at: 1) // remove A
        XCTAssertEqual(store.sections.map(\.name), ["C", "B"])
        store.clearAll()
    }

    @MainActor
    func testStoreSetLengthAndClip() {
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(name: "A", lengthBars: 1)
        guard let id = store.sections.first?.id else { return XCTFail("no section") }
        store.setLength(id: id, bars: 8)
        XCTAssertEqual(store.sections.first?.lengthBars, 8)
        let clipID = UUID()
        store.setClip(id: id, clipID: clipID, name: "Verse", colorIndex: 3)
        XCTAssertEqual(store.sections.first?.clipID, clipID)
        XCTAssertEqual(store.sections.first?.name, "Verse")
        XCTAssertEqual(store.sections.first?.colorIndex, 3)
        store.clearAll()
    }

    // MARK: - Additive Codable (law 9 — no silent whole-song loss on decode)

    /// Full round-trip stays exact (the custom decoder must not change encode).
    func testArrangement_roundTripsExactly() throws {
        let a = Arrangement(sections: [
            ArrangementSection(clipID: UUID(), name: "Intro", colorIndex: 2, lengthBars: 4),
            ArrangementSection(name: "Gap", lengthBars: 2),
        ])
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(Arrangement.self, from: data)
        XCTAssertEqual(a, back)
    }

    /// A section JSON missing later-added fields decodes to defaults, NOT a throw —
    /// the whole point: one absent field must not lose the song.
    func testArrangementSection_missingFieldsDecodeToDefaults() throws {
        // Only `id` + `name` present (as an early build might have saved).
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(ArrangementSection.self, from: json)
        XCTAssertEqual(s.name, "Old")
        XCTAssertNil(s.clipID)          // absent ⇒ silent gap
        XCTAssertEqual(s.colorIndex, 0) // absent ⇒ default
        XCTAssertEqual(s.lengthBars, 1) // absent ⇒ clamped default, never 0
    }

    /// A completely foreign / future-shaped section object still decodes (all
    /// defaults) rather than throwing and dropping the arrangement.
    func testArrangementSection_unknownShapeDoesNotThrow() throws {
        let json = #"{"future":123,"lengthBars":0}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(ArrangementSection.self, from: json)
        XCTAssertEqual(s.lengthBars, 1, "lengthBars 0 clamps to 1 even on decode")
        XCTAssertEqual(s.name, "Section")
    }

    /// An arrangement document missing `sections` loads as an empty song, not a throw.
    func testArrangement_missingSectionsDecodesEmpty() throws {
        let json = #"{}"#.data(using: .utf8)!
        let a = try JSONDecoder().decode(Arrangement.self, from: json)
        XCTAssertTrue(a.sections.isEmpty)
    }

    /// The nested case: a section inside the array carries only partial fields —
    /// the arrangement still loads with that section defaulted (no whole-song loss).
    func testArrangement_partialNestedSectionSurvives() throws {
        let json = #"{"sections":[{"name":"Verse"}]}"#.data(using: .utf8)!
        let a = try JSONDecoder().decode(Arrangement.self, from: json)
        XCTAssertEqual(a.sections.count, 1)
        XCTAssertEqual(a.sections.first?.name, "Verse")
        XCTAssertEqual(a.sections.first?.lengthBars, 1)
    }
}
