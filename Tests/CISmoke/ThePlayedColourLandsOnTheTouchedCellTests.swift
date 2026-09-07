// ThePlayedColourLandsOnTheTouchedCellTests.swift
// Echoel — #1061. Blocking bundle. Mostly REAL arithmetic: claims 1–3 invert the grid's own
// cell formula and compare coordinates, so they say where a colour actually blooms. Claim 4 is
// a source-text scan (`Tests/CISmoke/CLAUDE.md` §1), because a defaulted property that no
// mount passes is invisible in every diff (#431).
//
// ⭐ WHY THIS FILE EXISTS. The founder's ask for this whole mechanism (2026-07-08) was that a
// colour appears WHERE its tone sounds. It did not. `SpectralColor.notePosition` placed a note
// at its CHROMATIC fraction above C — and its own doc called that "the fretboard grid's column
// order", which is exactly what the grid is not: equal-width SCALE-DEGREE columns with the
// ROOT at the left. So touching a cell lit a cloud somewhere else in every key but C, and in
// the wrong column even in C for any non-chromatic scale (7 degrees spread over a width the
// chromatic fraction divides into 12).
//
// ⛔ THE ROW IS THE TRAP, and claim 2 exists only for it. A grid ROW is a BAND, not the note's
// octave NUMBER: a degree high in the scale crosses into the next octave number while staying
// in the same row. In A minor the sixth degree of the BOTTOM row is MIDI 65, whose octave
// number is 4 while its band is 3 — so deriving the row from `pitch / 12 - 1` (which is what
// the cell LABEL prints, three lines away in the same file) puts it one row too high, in the
// key the picker opens on. The shipped code inverts `key.degree(_:octave:)` instead.
//
// ⛔ AND THE OLD MAPPING MUST SURVIVE (claim 3, the counterweight). It is not a bug to delete:
// it is the source-agnostic PITCH-SPACE placement, which is the honest answer for a field with
// NO grid over it — the fullscreen cover and the external stage draw none — and for a note
// whose pitch class is not in the key at all. Two of the three mounts pass no key on purpose.
//
// ⚠️ WHAT THIS DOES NOT CLAIM: pixel-exactness in fullscreen. The grid draws inside `playRect`
// (bounds inset by the safe area) while the Metal field fills the whole bounds, so where those
// differ the cell and the cloud are off by that inset — a few per cent of the width, against a
// whole column before. One rect shared by both surfaces is the real repair and belongs to the
// fullscreen merge, not here.
//
// ⚠️ HONEST GRADING. FIFTEEN assertion statements across four claims (4 · 3 · 5 · 3), and the
// loops make them cover far more: claim 1 alone drives 1116 cells (12 roots · 4 scales · 3
// bands) against both coordinates. Driven today: everything passes. On the pre-slice tree only
// claim 4 can be graded — the rest would not COMPILE, since `TouchPitchMap.fieldPosition` does
// not exist yet — and all THREE of its assertions are RED there, which is the honest shape of
// this fix: the arithmetic is new, and the wiring is the part that could silently not happen.
// Counted from the driven run, not from this file's outline (#1054).

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePlayedColourLandsOnTheTouchedCellTests: XCTestCase {

    /// claim 1 — every cell of the grid maps to its own centre, for a spread of keys and
    /// scales. This is the whole fix stated as an identity: draw the cell, ask where its note
    /// lives, get the cell back.
    func testEveryCellMapsToItsOwnCentre() {
        let scales: [Scale] = [.major, .minor, .chromatic, .pentatonicMinor]
        let bands = TouchPitchMap.octaveBands
        var checked = 0
        for root in 0..<12 {
            for scale in scales {
                let key = MusicalKey(root: root, scale: scale)
                let n = key.degreesPerOctave
                for (row, band) in bands.enumerated() {
                    for column in 0..<n {
                        let pitch = key.degree(column, octave: band)
                        guard let place = TouchPitchMap.fieldPosition(forPitch: pitch, key: key) else {
                            XCTFail("""
                                No field position for the note in column \(column), row \(row) \
                                of \(key.name) — that cell is DRAWN, so a colour has somewhere \
                                to land and returning nil sends it back to pitch space.
                                """)
                            continue
                        }
                        let wantX = (Double(column) + 0.5) / Double(n) * 2.0 - 1.0
                        let wantY = (Double(row) + 0.5) / Double(bands.count) * 2.0 - 1.0
                        XCTAssertEqual(place.x, wantX, accuracy: 1e-12, """
                            \(key.name) column \(column) blooms at x=\(place.x), its cell is \
                            centred at \(wantX). Columns are equal-width scale degrees with \
                            the ROOT at the left — a chromatic fraction above C is a different \
                            axis and lands in a different column.
                            """)
                        XCTAssertEqual(place.y, wantY, accuracy: 1e-12, """
                            \(key.name) column \(column), row \(row) blooms at y=\(place.y), \
                            its cell is centred at \(wantY). The row is the BAND, not the \
                            note's octave NUMBER.
                            """)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 300, """
            Only \(checked) cells were exercised. The loop is meant to cover twelve roots \
            across four scales and three bands; a collapse to a handful means `Scale` renamed \
            a case and the array quietly shrank, which would leave this guard passing on a \
            fraction of the surface.
            """)
    }

    /// claim 2 — the row trap, named as its own case so a regression says WHICH mistake it is.
    func testAHighDegreeStaysInItsOwnRow() {
        let aMinor = MusicalKey(root: 9, scale: .minor)
        let bands = TouchPitchMap.octaveBands
        let pitch = aMinor.degree(5, octave: bands[0])       // bottom row, sixth degree
        XCTAssertEqual(pitch / 12 - 1, bands[0] + 1, """
            The premise of this test moved: the sixth degree of A minor's bottom row no longer \
            has an octave NUMBER one above its band, so it no longer demonstrates the trap. \
            Re-derive a note that does (any degree whose interval pushes past B) rather than \
            deleting the case — the trap itself has not gone anywhere.
            """)
        guard let place = TouchPitchMap.fieldPosition(forPitch: pitch, key: aMinor) else {
            return XCTFail("No field position for a note that IS on the grid.")
        }
        let bottomRowY = 0.5 / Double(bands.count) * 2.0 - 1.0
        XCTAssertEqual(place.y, bottomRowY, accuracy: 1e-12, """
            A note in the BOTTOM row blooms at y=\(place.y) instead of \(bottomRowY). Its \
            octave number is one higher than its band — deriving the row from `pitch / 12 - 1` \
            (what the cell label prints) puts it one row up. Invert `key.degree(_:octave:)`.
            """)
    }

    /// claim 3 — the counterweights (#367). Off-grid notes fall back, and the pitch-space
    /// mapping they fall back TO must still exist.
    func testOffGridNotesFallBackToPitchSpace() {
        let cMajor = MusicalKey(root: 0, scale: .major)
        XCTAssertNil(TouchPitchMap.fieldPosition(forPitch: 61, key: cMajor), """
            C♯ was given a cell in C major. It has none — the grid draws seven degree columns \
            and C♯ is in no column, so the honest answer is nil and the caller keeps the \
            pitch-space position. Inventing a nearest column would put a chromatic passing \
            note on top of a diatonic one.
            """)
        XCTAssertNil(TouchPitchMap.fieldPosition(forHz: 0, a4Hz: 440, key: cMajor))
        XCTAssertNil(TouchPitchMap.fieldPosition(forHz: 440, a4Hz: 440, key: nil), """
            A nil key produced a position. nil means "no play grid under this field", which is \
            the real state of the fullscreen cover and the external stage; answering with a \
            cell would place colours by a grid the viewer cannot see.
            """)
        // The fallback itself. Deleting it as "superseded" would leave the two grid-less
        // mounts and every off-key note with nowhere to go.
        let pitchSpace = SpectralColor.notePosition(forHz: 440)
        XCTAssertTrue(pitchSpace.x.isFinite && pitchSpace.y.isFinite, """
            `SpectralColor.notePosition` no longer returns a usable place. It is not obsolete: \
            it is what a field with no grid uses, and what an off-key note uses. #1061 removed \
            a false CLAIM from its doc, not the function.
            """)
        // A4 concert pitch actually matters — a re-tuned instrument must still land.
        let at440 = TouchPitchMap.fieldPosition(forHz: 440, a4Hz: 440, key: MusicalKey(root: 9, scale: .minor))
        let at432 = TouchPitchMap.fieldPosition(forHz: 432, a4Hz: 432, key: MusicalKey(root: 9, scale: .minor))
        XCTAssertEqual(at440?.x, at432?.x, """
            The same DEGREE lands in different columns at two concert pitches. `a4Hz` is \
            threaded so a re-tuned take still maps onto its own cells; ignoring it would send \
            every note a semitone sideways at 432 Hz.
            """)
    }

    /// claim 4 — the wiring, which no arithmetic can see. The property is defaulted, so the
    /// one mount that passes it is the entire fix (#431).
    func testTheWindowActuallyPassesItsKey() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func code(_ relative: String) -> String {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative),
                                         encoding: .utf8) else {
                XCTFail("ANCHOR MISSING: \(relative) — a missing anchor is a finding (#454).")
                return ""
            }
            return SourceText.codeOnly(text)
        }
        XCTAssertTrue(code("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
                        .contains("noteFieldKey: MusicalKey(root: rootIndex, scale: touchScale)"), """
            The floating window stopped handing its key to the field. It is the ONLY mount with \
            a `TouchInstrumentView` over it, so without this line the whole slice is inert and \
            every arithmetic claim above still passes — which is exactly why this text claim \
            exists. The key must be built from the same two values the overlay uses.
            """)
        let metal = code("Sources/Echoelmusic/Views/MetalBioView.swift")
        XCTAssertTrue(metal.contains("c.noteFieldKey = noteFieldKey"), """
            `updateUIView` no longer forwards the key to the renderer. The struct property \
            alone changes nothing; the draw loop reads the coordinator.
            """)
        XCTAssertTrue(metal.contains("TouchPitchMap.fieldPosition(forHz: cloudHzSlot[k]"), """
            The renderer went back to placing clouds by pitch space alone. That call is where \
            the grid-aware position is actually used; the `??` fallback beside it is what keeps \
            the grid-less mounts correct.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Schwebendes Fenster, Ton-Gitter einblenden, Tonart auf etwas anderes als
// C stellen (z. B. a-Moll oder F-Dur). Eine Zelle antippen: die Farbwolke muss GENAU unter dem
// Finger aufblühen, nicht in einer Nachbarspalte. Gegenprobe unterste Reihe, rechte Spalten —
// dort saß der Reihen-Fehler. Im Vollbild bleibt ein kleiner Versatz durch die Safe-Area.
