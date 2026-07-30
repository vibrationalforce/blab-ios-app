// NoteNamingTests.swift
// Echoel — the same pitch has different NAMES in different musical cultures, and until
// 2026-07-30 the app knew only one of them.
//
// FOUNDER, 2026-07-29: *"international für alle Kulturen und Hintergründe accessible."*
// The note-name audit (#232 E) found the twelve English names hard-coded in six places. Three
// of those six are LIVE — the Key picker in the permanent chrome, the play surface's cell
// labels, and `MusicalKey` (display + filenames). The other three are not, and the first
// version of this header called all six "live", which is the kind of inflation that makes the
// next reader distrust the rest: `TuningDetector.keyName` and `TuningReference.noteName` have
// zero production callers (tests only), and `PianoRollModel.name(forPitch:)` is reachable only
// from `PianoRollView`, which nothing instantiates. That is not a missing translation — it is
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
            // No `names.count == 12` assertion: it is a `(0..<12).map`, so it could not be
            // anything else. The two below are the ones that can actually fail.
            let names = (0..<12).map { naming.name(pitchClass: $0) }
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
        XCTAssertEqual(NoteNaming.sargam.rawValue, "sargam")
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
    ///
    /// ⚠️ IT SETS THE SETTING FIRST, and the first version did not — which made it a test that
    /// could not fail. With the stored default at `.english`, asserting "shortName starts with
    /// B" passes whether or not `shortName` consults `NoteNaming`, so it guarded nothing while
    /// the file header claimed it did. The German setting has to be ACTIVE for the assertion
    /// to mean "this path ignores the setting".
    func testTheFilenameTagIgnoresNaming() {
        let key = StudioDefaultKeys.noteNaming.key
        let previous = UserDefaults.standard.string(forKey: key)
        addTeardownBlock {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(NoteNaming.german.rawValue, forKey: key)

        // Pitch class 11 is the B/H pair — the one place a leak would show.
        let musicalKey = MusicalKey(root: 11, scale: .minor)
        XCTAssertTrue(musicalKey.shortName.hasPrefix("B"),
                      "the filename-safe tag must stay English (\(musicalKey.shortName)) even "
                      + "with German selected. If a naming setting reaches this path, a German "
                      + "user's shared file stops matching an English user's for the same key.")
        XCTAssertFalse(musicalKey.shortName.hasPrefix("H"))

        // `MusicalKey.name` is the DISPLAY twin and must move — pinning both here keeps the
        // split visible in one place. The parameterless `name` stays English by definition.
        XCTAssertEqual(musicalKey.name(naming: .german), "H Minor")
        XCTAssertEqual(musicalKey.name, "B Minor",
                       "the parameterless `name` is the interop spelling and must not follow "
                       + "the setting — a display caller passes a naming explicitly")
    }

    /// A blind user and a sighted user must be in the same system. Before this existed the
    /// play surface spoke its own hard-coded English root ten lines from the labels it
    /// contradicted — the worst possible place for it, given the ask was accessibility.
    func testTheSpokenNameMatchesTheSeenName() {
        for naming in NoteNaming.allCases {
            for pc in 0..<12 {
                let seen = naming.name(pitchClass: pc)
                let spoken = naming.spokenName(pitchClass: pc)
                XCTAssertFalse(spoken.contains("♯"),
                               "VoiceOver cannot pronounce ♯ — \(naming) pitch \(pc) says "
                               + "\(spoken)")
                XCTAssertFalse(spoken.contains("♭"),
                               "VoiceOver cannot pronounce ♭ — \(naming) pitch \(pc) says "
                               + "\(spoken)")

                // The two assertions above name the two marks that exist TODAY, and that is
                // exactly their weakness: a future column spelling "Ma'" (the printed tīvra
                // convention), "B♮" or "E𝄫" passes both and reaches a screen reader as a
                // symbol it announces as its Unicode name or not at all. This one is the
                // general form — plain ASCII letters and spaces, nothing else — so any NEW
                // mark fails on the day it is added rather than on a device months later.
                // `spokenName`'s doc comment claims this guard exists; this is the line
                // that makes the claim true.
                let speakable = Set("abcdefghijklmnopqrstuvwxyz"
                                    + "ABCDEFGHIJKLMNOPQRSTUVWXYZ ")
                XCTAssertTrue(spoken.allSatisfy(speakable.contains),
                              "\(naming) pitch \(pc) speaks \"\(spoken)\", which carries a "
                              + "character that is neither an ASCII letter nor a space — "
                              + "expand it in `spokenName` the way ♯ and ♭ are expanded")

                let expanded = seen
                    .replacingOccurrences(of: "♯", with: " sharp")
                    .replacingOccurrences(of: "♭", with: " flat")
                XCTAssertEqual(spoken, expanded,
                               "the spoken form must be the SEEN form with its accidentals "
                               + "expanded, not a second table that can drift from it")
            }
        }
        XCTAssertEqual(NoteNaming.german.spokenName(pitchClass: 11), "H")
        XCTAssertEqual(NoteNaming.english.spokenName(pitchClass: 1), "C sharp")
        // The arm that did not exist before sargam. Without it a blind Indian player hears
        // "Re" for both Re♭ and Re — one name, two pitches, on the key control.
        XCTAssertEqual(NoteNaming.sargam.spokenName(pitchClass: 1), "Re flat")
        XCTAssertEqual(NoteNaming.sargam.spokenName(pitchClass: 6), "Ma sharp")
    }

    /// Sargam (#232 F, Indian third). The app grew seven Indian scales in #232 J and then
    /// spelled their notes "D♯"; this is the alphabet those scales are read in.
    func testSargamNamesTheSevenDegreesAndMarksTheAlteredOnes() {
        let sargam = NoteNaming.sargam
        // The seven śuddha degrees, in order, on the pitch classes of a major scale.
        XCTAssertEqual([0, 2, 4, 5, 7, 9, 11].map { sargam.name(pitchClass: $0) },
                       ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"])

        // Sa and Pa are the fixed drone degrees and have no altered form in either the
        // Hindustani or the Carnatic system. A table that produced "Sa♯" would mean the
        // column had been filled mechanically from a Western one.
        XCTAssertEqual(sargam.name(pitchClass: 0), "Sa")
        XCTAssertEqual(sargam.name(pitchClass: 7), "Pa")

        // Komal marked with ♭, tīvra Ma with ♯ — a DEPARTURE from the printed convention,
        // which distinguishes them by case ("re" vs "Re", "Ma'"). Pinned here because the
        // departure is the point: a case-only difference is invisible in a menu row and
        // identical to a screen reader, which would defeat the setting's whole purpose.
        // If someone "corrects" this to lowercase, this test is what stops it.
        XCTAssertEqual(sargam.name(pitchClass: 1), "Re♭")
        XCTAssertEqual(sargam.name(pitchClass: 6), "Ma♯")
        XCTAssertEqual(sargam.name(pitchClass: 10), "Ni♭")
        // No `XCTAssertNotEqual(name(1), name(2))` here: the two equalities directly above
        // already pin "Re♭" and "Re", so it could never fail on its own. An assertion that
        // cannot fail independently reads as extra coverage and is none (#140's lesson).
    }

    /// The one thing that links `NoteNaming` to the sentence a blind player HEARS.
    ///
    /// `WorkspaceView`'s note-name Picker carries an `.accessibilityHint` that ENUMERATES
    /// the options, because a menu Picker speaks only its current value until it is opened.
    /// That string is hand-written prose with no compiler link to this enum — add a case
    /// and it silently undercounts, on the single control this epic exists to make
    /// accessible. This test cannot read the string, so it does the next best thing: it
    /// fails the moment the count changes, and says where to go.
    func testAddingANamingSystemAlsoMeansEditingTheSpokenHint() {
        XCTAssertEqual(NoteNaming.allCases.count, 4,
                       "NoteNaming grew or shrank. Update the `.accessibilityHint` on the "
                       + "\"Note names\" Picker in WorkspaceView so a VoiceOver user is told "
                       + "about the same options a sighted user can see, then update this "
                       + "number.")
    }
}
