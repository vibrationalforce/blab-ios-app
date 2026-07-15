// MelodyBarEditTests.swift
// H11 — the bar-splice laws behind the clip-scoped MIDI editor: slicing a bar
// out for editing, splicing it back, and above all the MULTI-BAR-SAFETY law
// (notes outside the edited bar survive byte-identical — a multi-bar clip can
// never be silently flattened by the single-bar roll).

import XCTest
@testable import Echoelmusic

final class MelodyBarEditTests: XCTestCase {

    private let perBar = TimelineTime.ticksPerBar

    private func note(_ pitch: Int, tick: Int, len: Int = Note.ticksPerStep) -> Note {
        Note(pitch: pitch, startTick: tick, lengthTicks: len)
    }

    private func sortedByID(_ notes: [Note]) -> [Note] {
        notes.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - barCount

    func testBarCount_emptyIsOne_extentDrivesBars() {
        XCTAssertEqual(MelodyBarEdit.barCount(of: []), 1)
        XCTAssertEqual(MelodyBarEdit.barCount(of: [note(60, tick: 0)]), 1)
        XCTAssertEqual(MelodyBarEdit.barCount(of: [note(60, tick: perBar)]), 2,
                       "a note starting in bar 1 makes it a 2-bar melody")
        XCTAssertEqual(MelodyBarEdit.barCount(of: [note(60, tick: 0, len: perBar)]), 1,
                       "ending exactly ON the bar line stays a 1-bar melody")
        XCTAssertEqual(MelodyBarEdit.barCount(of: [note(60, tick: 0, len: perBar + 1)]), 2,
                       "one tick past the line spills into bar 2")
    }

    // MARK: - slice

    func testSlice_rebasesBarRelative_keepsSustainLength() {
        let long = note(48, tick: perBar + 240, len: perBar)   // bar 1, cross-bar sustain
        let all = [note(60, tick: 0), long, note(72, tick: 2 * perBar)]
        let bar1 = MelodyBarEdit.slice(bar: 1, of: all)
        XCTAssertEqual(bar1.count, 1)
        XCTAssertEqual(bar1.first?.startTick, 240, "rebased to bar-relative ticks")
        XCTAssertEqual(bar1.first?.lengthTicks, perBar, "cross-bar sustain keeps its length")
        XCTAssertEqual(bar1.first?.id, long.id, "identity survives the rebase")
        XCTAssertTrue(MelodyBarEdit.slice(bar: 5, of: all).isEmpty)
        XCTAssertTrue(MelodyBarEdit.slice(bar: -1, of: all).isEmpty)
    }

    func testSlice_barBoundaries_loInclusive_hiExclusive() {
        let onLine = note(60, tick: perBar)            // exactly ON bar 1's line
        let lastTick = note(62, tick: 2 * perBar - 1)  // last tick of bar 1
        let nextLine = note(64, tick: 2 * perBar)      // exactly ON bar 2's line
        let bar1 = MelodyBarEdit.slice(bar: 1, of: [onLine, lastTick, nextLine])
        XCTAssertEqual(bar1.map(\.pitch).sorted(), [60, 62],
                       "lo-inclusive, hi-exclusive — the bar-line note belongs to the bar it starts")
        XCTAssertEqual(bar1.first { $0.pitch == 60 }?.startTick, 0)
        XCTAssertEqual(bar1.first { $0.pitch == 62 }?.startTick, perBar - 1)
    }

    // MARK: - splice: the multi-bar-safety law

    func testSplice_otherBarsSurviveByteIdentical() {
        let bar0 = note(60, tick: 100)
        let bar2 = note(72, tick: 2 * perBar + 300, len: 555)
        let all = [bar0, note(64, tick: perBar), bar2]
        let edited = [note(50, tick: 0), note(52, tick: 480)]   // new bar-1 content
        let merged = MelodyBarEdit.splice(bar: 1, edited: edited, into: all)
        XCTAssertEqual(merged.count, 4)
        XCTAssertTrue(merged.contains(bar0), "bar-0 note byte-identical (same id, ticks, length)")
        XCTAssertTrue(merged.contains(bar2), "bar-2 note byte-identical — NO flattening")
        XCTAssertEqual(merged.filter { $0.startTick >= perBar && $0.startTick < 2 * perBar }
                             .map(\.pitch).sorted(), [50, 52],
                       "edited notes landed at the bar's offset")
    }

    func testSplice_roundtrip_isLossless() {
        // slice → splice unchanged = the same melody (identity-preserving).
        let all = [note(60, tick: 0), note(64, tick: perBar + 120, len: 2 * perBar),
                   note(72, tick: 3 * perBar)]
        let merged = MelodyBarEdit.splice(bar: 1,
                                          edited: MelodyBarEdit.slice(bar: 1, of: all),
                                          into: all)
        XCTAssertEqual(sortedByID(merged), sortedByID(all),
                       "no-op edit ⇒ identical notes (ids, ticks, lengths, velocities)")
    }

    func testSplice_emptyEdit_clearsOnlyThatBar() {
        let all = [note(60, tick: 0), note(64, tick: perBar), note(72, tick: 2 * perBar)]
        let merged = MelodyBarEdit.splice(bar: 1, edited: [], into: all)
        XCTAssertEqual(merged.map(\.pitch).sorted(), [60, 72],
                       "deleting every note in the editor empties exactly that bar")
    }

    func testSplice_intoEmptyClip_createsContentAtBar() {
        let merged = MelodyBarEdit.splice(bar: 2, edited: [note(60, tick: 480)], into: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.startTick, 2 * perBar + 480,
                       "drawing into an empty clip lands at the tapped bar")
    }

    func testSplice_defensive_outOfBarEditDropped_negativeBarNoop() {
        let all = [note(60, tick: 0)]
        let rogue = note(50, tick: perBar + 1)   // outside the single-bar editor window
        XCTAssertEqual(MelodyBarEdit.splice(bar: 0, edited: [rogue], into: all).count, 0,
                       "bar 0 replaced by nothing (rogue dropped), no bleed into bar 1")
        XCTAssertEqual(MelodyBarEdit.splice(bar: -1, edited: [rogue], into: all), all)
    }

    func testSplice_deterministicOrdering() {
        let merged = MelodyBarEdit.splice(bar: 0,
                                          edited: [note(72, tick: 0), note(60, tick: 0)],
                                          into: [note(64, tick: perBar)])
        XCTAssertEqual(merged.map(\.pitch), [60, 72, 64],
                       "(startTick, pitch) ordering — stable persistence")
    }

    // MARK: - ClipStore write-back door

    @MainActor
    func testUpdateMelody_byID_writesAndPersists_unknownIDFalse() {
        let store = ClipStore()
        var clip = Clip(name: "H11", kind: .midi)
        clip.melody = MelodyClip(notes: [note(60, tick: 0)])
        store.setClip(at: 0, clip)
        let newNotes = [note(50, tick: 0), note(52, tick: 480)]
        XCTAssertTrue(store.updateMelody(id: clip.id, notes: newNotes))
        XCTAssertEqual(store.clip(id: clip.id)?.melody?.notes, newNotes)
        XCTAssertFalse(store.updateMelody(id: UUID(), notes: []),
                       "unknown id writes nothing and says so")
        // Persistence law: a FRESH store (same App-Group file) sees the write.
        let reloaded = ClipStore()
        XCTAssertEqual(reloaded.clip(id: clip.id)?.melody?.notes, newNotes,
                       "updateMelody persists, not just mutates in memory")
    }

    @MainActor
    func testUpdateMelody_nonMIDIClip_isRefused() {
        let store = ClipStore()
        let audio = Clip(name: "A", kind: .audio, mediaRef: "x.wav")
        store.setClip(at: 1, audio)
        XCTAssertFalse(store.updateMelody(id: audio.id, notes: [note(60, tick: 0)]),
                       "melody is MIDI content only — the API self-defends")
        XCTAssertNil(store.clip(id: audio.id)?.melody)
    }
}
