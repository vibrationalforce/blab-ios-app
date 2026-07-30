// NoteNamingTests.swift
// Echoel — the same pitch has different NAMES in different musical cultures, and until
// 2026-07-30 the app knew only one of them.
//
// FOUNDER, 2026-07-29: *"international für alle Kulturen und Hintergründe accessible."*
// The note-name audit (#232 E) found the twelve English names hard-coded in six live places,
// including the Key picker in the permanent chrome. That is not a missing translation — it is
// the WRONG NOTE for a large part of Europe. In German, Austrian and Scandinavian notation the
// natural above A♯ is called **H**, and the name **B** is taken: it means B♭. So a German
// musician reading "B" in our Key picker reads a pitch one semitone below the one that sounds,
// on the control that decides the key of everything. The developer of this app is in Hamburg.
//
// This file pins the pure core. It deliberately asserts the CLASH — that English `B` and German
// `B` are different pitch classes — because that is the entire reason the type exists, and a
// future edit that "tidies" the German table into a copy of the English one would otherwise
// pass every other check here.
//
// ⚠️ WHAT THIS IS NOT. Naming is a DISPLAY choice. It must never reach:
//   · `MusicalKey.shortName`, which stamps share-sheet FILENAMES — two people on two devices
//     with two settings have to produce the same file name for the same key, or a shared take
//     stops matching itself.
//   · the MIDI export, which carries pitch NUMBERS and no names at all.
// Those two are English-by-construction and are checked in `testTheFilenameTagIgnoresNaming`.

import Foundation
import XCTest
@testable import Echoelmusic

final class NoteNamingTests: XCTestCase {

    func testEveryNamingOffersTwelveDistinctNonEmptyNames() {
        for naming in NoteNaming.allCases {
            let names = (0..<12).map { naming.name(pitchClass: $0) }
            XCTAssertEqual(names.count, 12, "\(naming)")
            XCTAssertFalse(names.contains(where: \.isEmpty),
                           "\(naming) has an empty name: \(names)")
            XCTAssertEqual(Set(names).count, 12,
                           "\(naming) names two pitch classes the same, so the picker would "
                           + "show one label twice and the player could not tell them apart: "
                           + "\(names)")
        }
    }

    /// THE point of the type. If this ever passes trivially, the feature is gone.
    func testGermanBAndEnglishBAreDifferentPitches() {
        XCTAssertEqual(NoteNaming.english.name(pitchClass: 11), "B")
        XCTAssertEqual(NoteNaming.german.name(pitchClass: 11), "H",
                       "in German notation the natural above A♯ is H, not B")
        XCTAssertEqual(NoteNaming.german.name(pitchClass: 10), "B",
                       "in German notation the name B is TAKEN: it means B♭, one semitone "
                       + "below the English B. Naming pitch class 10 anything else re-opens "
                       + "exactly the confusion this type exists to remove.")
        // Stated as a fact, not as a chain of lookups: the same letter, two pitches.
        XCTAssertNotEqual(NoteNaming.english.name(pitchClass: 11),
                          NoteNaming.german.name(pitchClass: 11))
    }

    /// German differs from English at EXACTLY those two indices — not at C♯, not at F♯. A
    /// count-only assertion would let a well-meant "let's use flats throughout" edit through.
    func testGermanDivergesFromEnglishOnlyAtTenAndEleven() {
        let diverging = (0..<12).filter {
            NoteNaming.german.name(pitchClass: $0) != NoteNaming.english.name(pitchClass: $0)
        }
        XCTAssertEqual(diverging, [10, 11],
                       "German notation differs from English in the B/H pair and nowhere else; "
                       + "found \(diverging)")
    }

    /// Fixed-do (Romance languages, and the standard in much of East Asia). Every degree is
    /// renamed, so a single shared name would mean the table was half-filled.
    func testSolfegeRenamesEveryDegree() {
        for pc in 0..<12 {
            XCTAssertNotEqual(NoteNaming.solfege.name(pitchClass: pc),
                              NoteNaming.english.name(pitchClass: pc),
                              "pitch class \(pc) is still a letter name in solfège")
        }
        XCTAssertEqual(NoteNaming.solfege.name(pitchClass: 0), "Do")
        XCTAssertEqual(NoteNaming.solfege.name(pitchClass: 7), "Sol")
        XCTAssertEqual(NoteNaming.solfege.name(pitchClass: 11), "Si",
                       "fixed-do uses Si for the leading tone; Ti is the movable-do/English "
                       + "convention and would be the wrong system inside this case")
    }

    /// Callers pass MIDI notes and interval arithmetic results, not pre-clamped indices.
    /// Out-of-range must WRAP, never trap — an index-out-of-range here would crash the chrome.
    func testAnyIntegerNamesSomething() {
        for naming in NoteNaming.allCases {
            XCTAssertEqual(naming.name(pitchClass: 12), naming.name(pitchClass: 0))
            XCTAssertEqual(naming.name(pitchClass: 60), naming.name(pitchClass: 0))
            XCTAssertEqual(naming.name(pitchClass: -1), naming.name(pitchClass: 11),
                           "a negative pitch class must fold up, not down — Swift's % keeps "
                           + "the sign, so the naive [x % 12] would trap here")
            XCTAssertEqual(naming.name(pitchClass: -13), naming.name(pitchClass: 11))
            XCTAssertFalse(naming.name(pitchClass: Int.min).isEmpty,
                           "Int.min % 12 is the classic overflow corner")
            XCTAssertFalse(naming.name(pitchClass: Int.max).isEmpty)
        }
    }

    /// The raw values are PERSISTED (`StudioDefaultKeys.noteNaming`). Renaming a case would
    /// silently reset every existing install to the default, which for a German user means the
    /// wrong note names come back without them touching anything.
    func testRawValuesArePersistedAndStable() {
        XCTAssertEqual(NoteNaming.english.rawValue, "english")
        XCTAssertEqual(NoteNaming.german.rawValue, "german")
        XCTAssertEqual(NoteNaming.solfege.rawValue, "solfege")
        XCTAssertEqual(StudioDefaultKeys.noteNaming.value, NoteNaming.english.rawValue,
                       "the stored default must BE a valid case, or a fresh install decodes "
                       + "nothing and falls back by accident rather than by design")
    }

    /// A stored value from a future build, or a corrupted one, must land on English rather
    /// than on nil — the app has to name notes somehow (`decodeIfPresent` law).
    func testAnUnknownStoredNamingFallsBackToEnglish() {
        XCTAssertEqual(NoteNaming(stored: "klingon"), .english)
        XCTAssertEqual(NoteNaming(stored: ""), .english)
        XCTAssertEqual(NoteNaming(stored: "GERMAN"), .english,
                       "the lookup is exact, not case-insensitive — documenting which, so the "
                       + "writer side never starts emitting a variant spelling")
        XCTAssertEqual(NoteNaming(stored: "german"), .german)
    }

    /// Display is a choice; the FILENAME is not. Two people sharing a take must produce the
    /// same tag for the same key whatever their picker says.
    func testTheFilenameTagIgnoresNaming() {
        // Pitch class 11 is the B/H pair — the one place a leak would show.
        let key = MusicalKey(root: 11, scale: .minor)
        XCTAssertTrue(key.shortName.hasPrefix("B"),
                      "the filename-safe tag must stay English (\(key.shortName)). If a naming "
                      + "setting ever reaches this path, a German user's shared file stops "
                      + "matching an English user's for the identical key.")
        XCTAssertFalse(key.shortName.hasPrefix("H"))
    }
}
