// AFlatKeyIsSpelledWithFlatsTests.swift
// Echoel — #1060. Blocking bundle. Mostly REAL behaviour: claims 1–4 call the shipped code
// and compare strings, so they say what a player would read. Claim 5 is a source-text scan
// (`Tests/CISmoke/CLAUDE.md` §1) and exists only because a defaulted argument is invisible
// otherwise.
//
// ⭐ WHY THIS FILE EXISTS. `NoteNaming` had exactly one column per system and every one of
// them spelled the altered degrees with ♯. In F major the seventh degree is B♭, so the play
// grid printed "A♯": the right PITCH under the wrong NAME, on the surface where the column IS
// the note. Every flat key had it — E♭, B♭, A♭, D♭ major, and D, G, C, F minor — and so did
// the key picker's own readable label ("A♯ Minor" for what a musician calls B♭ minor).
//
// ⛔ THE RULE IS DERIVED, NOT A TASTE LIST (claim 1, and it is the half most likely to be
// "simplified" later). A minor tonality borrows its RELATIVE MAJOR's signature, a minor third
// up — so D minor is flat because F major is, not because D is anything. Dropping that step
// gives a rule that is right for majors and wrong for exactly the minor keys a bio-generative
// instrument spends most of its time in (`MusicalKey`'s own default scale is `.minor`).
//
// ⛔ SARGAM MUST NOT MOVE (claim 3, the counterweight that matters most). Its table already
// contains ♭, and it is tempting to read that as "already the flat column". It is not: `Re♭`
// there is komal Re, a DEGREE of the rāga, not an enharmonic choice about how to spell a
// pitch class. Giving sargam a second column would apply Western grammar to a system that
// does not have the question — the exact thing `NoteNaming`'s own sargam comment forbids.
//
// ⚠️ PITCH CLASS 6 IS A TIE AND STAYS SHARP. F♯ major (six sharps) and G♭ major (six flats)
// are both correct; there is no signature answer, only a convention. Claim 1 pins the choice
// so it stays a decision rather than becoming an accident.
//
// ⚠️ HONEST GRADING, and the two useful numbers are different ones. FOURTEEN assertion
// statements across five claims (2 · 7 · 1 · 1 · 3), several of them loops, so the statements
// cover EIGHTY-FIVE concrete cases (15 keys · 7 spellings · 12 sargam pitch classes · 48
// spoken names · 3 call sites). Driven: 85/85 pass on today's tables and rule. On the
// pre-slice tree only claim 5 can be graded at all — the rest would not COMPILE, because
// neither `prefersFlatSpelling` nor the `preferFlats:` parameter exists yet — and all three of
// its assertions are RED there. Counted from the driven run, not from this file's outline
// (#1054). What this file does NOT claim: that every scale in `Scale` has a notated signature. Outside major and
// minor the rule still produces a consistent spelling, but that is a fallback, not a claim
// about how a rāga or a maqām is written — `prefersFlatSpelling`'s own doc says so.

import Foundation
import XCTest
@testable import Echoelmusic

final class AFlatKeyIsSpelledWithFlatsTests: XCTestCase {

    /// claim 1 — the signature rule, including the relative-major step and the enharmonic tie.
    func testTheFlatKeysAreTheFlatKeys() {
        let flat: [(Int, Scale, String)] = [
            (5, .major, "F major"), (10, .major, "B♭ major"), (3, .major, "E♭ major"),
            (8, .major, "A♭ major"), (1, .major, "D♭ major"),
            (2, .minor, "D minor"), (7, .minor, "G minor"), (0, .minor, "C minor"),
            (5, .minor, "F minor"),
        ]
        for (root, scale, label) in flat {
            XCTAssertTrue(MusicalKey(root: root, scale: scale).prefersFlatSpelling, """
                \(label) is not being spelled with flats. For a MINOR key the signature comes \
                from the relative major a minor third UP — drop that step and every minor \
                key answers wrongly, which is most of what this instrument plays.
                """)
        }
        let sharp: [(Int, Scale, String)] = [
            (0, .major, "C major"), (7, .major, "G major"), (11, .major, "B major"),
            (9, .minor, "A minor"), (4, .minor, "E minor"),
            (6, .major, "F♯ major — the enharmonic tie"),
        ]
        for (root, scale, label) in sharp {
            XCTAssertFalse(MusicalKey(root: root, scale: scale).prefersFlatSpelling, """
                \(label) is being spelled with flats. Pitch class 6 in particular is a TIE \
                (F♯ major and G♭ major are equally correct) and was decided for sharps on \
                convention; if that is being changed, change it deliberately and say so here.
                """)
        }
    }

    /// claim 2 — the spelling actually reaches the string a player reads.
    func testTheAlteredDegreesRespell() {
        XCTAssertEqual(NoteNaming.english.name(pitchClass: 10, preferFlats: true), "B♭")
        XCTAssertEqual(NoteNaming.english.name(pitchClass: 10, preferFlats: false), "A♯")
        XCTAssertEqual(NoteNaming.solfege.name(pitchClass: 3, preferFlats: true), "Mi♭")
        XCTAssertEqual(NoteNaming.solfege.name(pitchClass: 3, preferFlats: false), "Re♯")
        // German's 10 is the one that was ALREADY flat-correct — "B" in German IS B♭ — so it
        // must read the same on both sides. A flat column built mechanically from the English
        // one would have produced "B♭" here and broken the B/H pair this repo fixed once.
        XCTAssertEqual(NoteNaming.german.name(pitchClass: 10, preferFlats: true), "B")
        XCTAssertEqual(NoteNaming.german.name(pitchClass: 11, preferFlats: true), "H")
        // The key's own readable label follows its signature without the caller asking.
        XCTAssertTrue(MusicalKey(root: 10, scale: .minor).name(naming: .english).hasPrefix("B♭"), """
            The key picker's readable label still spells its own root on the sharp side. \
            `MusicalKey.name(naming:)` holds the key — there is no caller to blame and no \
            reason for it to disagree with the grid two controls away.
            """)
    }

    /// claim 3 — the counterweight (#367). Sargam has ONE column and must keep it.
    func testSargamIsUntouchedByTheSpellingSide() {
        for pitchClass in 0..<12 {
            XCTAssertEqual(NoteNaming.sargam.name(pitchClass: pitchClass, preferFlats: true),
                           NoteNaming.sargam.name(pitchClass: pitchClass, preferFlats: false), """
                Sargam changed spelling at pitch class \(pitchClass). Its ♭ marks are komal \
                DEGREES of the rāga, not an enharmonic side — a second sargam column would be \
                Western grammar applied to a system that does not ask the question.
                """)
        }
    }

    /// claim 4 — VoiceOver still gets plain speech from the new column. `spokenName` expands
    /// ♯ and ♭; a mark it does not know would reach a screen reader as nothing useful, and
    /// that failure is silent for everyone who can see the label.
    func testTheFlatNamesSpeakAsPlainAscii() {
        for naming in NoteNaming.allCases {
            for pitchClass in 0..<12 {
                let spoken = naming.spokenName(pitchClass: pitchClass, preferFlats: true)
                let ok = spoken.allSatisfy { $0.isASCII && ($0.isLetter || $0 == " " || $0 == "'") }
                XCTAssertTrue(ok, """
                    \(naming) speaks pitch class \(pitchClass) as "\(spoken)", which is not \
                    plain letters. `spokenName` only expands ♯ and ♭ — a new accidental in a \
                    table needs an arm there in the SAME commit, or VoiceOver reads the mark \
                    as nothing and a blind player hears two different pitches identically.
                    """)
            }
        }
    }

    /// claim 5 — the defaulted argument is actually written where a key exists (#431). This
    /// is the one text scan: a default that no caller passes is invisible in every diff, and
    /// the whole fix is exactly those three call sites.
    func testTheKeyAwareCallSitesPassTheSpelling() throws {
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
        let touch = code("Sources/Echoelmusic/Studio/TouchInstrumentView.swift")
        XCTAssertEqual(touch.components(separatedBy: "preferFlats: spellFlat").count - 1, 2, """
            The play grid's two label paths no longer both pass the key's spelling. There are \
            two on purpose — the fitting pre-pass and the rendered label — and if they \
            disagree the grid measures one string and draws another, which is #1058's defect \
            wearing a different hat.
            """)
        XCTAssertTrue(touch.contains("preferFlats: key.prefersFlatSpelling"), """
            The SPOKEN root no longer follows the key's spelling. VoiceOver would then say \
            "A sharp" over cells labelled B♭ — the sighted/blind split this naming work \
            exists to close.
            """)
        XCTAssertTrue(code("Sources/Echoelmusic/Sequencer/MusicalKey.swift")
                        .contains("preferFlats: prefersFlatSpelling"), """
            `MusicalKey.name(naming:)` stopped consulting its own signature. It holds the key; \
            nothing else can decide this for it.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Tonart auf F-Dur oder g-Moll stellen, Ton-Gitter einblenden. Die Zelle,
// die vorher „A♯" hieß, muss jetzt „B♭" heißen (auf Deutsch schlicht „B"), und die Kopfzeile des
// Tonart-Wählers muss dasselbe sagen. Gegenprobe A-Moll oder G-Dur: dort müssen die Kreuze
// bleiben.
