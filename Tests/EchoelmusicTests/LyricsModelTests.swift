// LyricsModelTests.swift
// W1 — the pure lyric foundation: deterministic singing syllabification
// (open-syllable preference, de/en cluster rules), word-boundary flags +
// hyphen display, melisma-aware syllable→note binding, Codable round-trip.

import XCTest
import Foundation
@testable import Echoelmusic

final class LyricsModelTests: XCTestCase {

    // MARK: - Syllabifier, German

    func testGerman_openSyllablesAndClusters() {
        XCTAssertEqual(Syllabifier.syllables(of: "Liebe", language: .german), ["Lie", "be"])
        XCTAssertEqual(Syllabifier.syllables(of: "Atem", language: .german), ["A", "tem"])
        XCTAssertEqual(Syllabifier.syllables(of: "Herzen", language: .german), ["Her", "zen"])
        XCTAssertEqual(Syllabifier.syllables(of: "Morgen", language: .german), ["Mor", "gen"])
        XCTAssertEqual(Syllabifier.syllables(of: "singen", language: .german), ["sin", "gen"])
        XCTAssertEqual(Syllabifier.syllables(of: "Wasser", language: .german), ["Was", "ser"])
        XCTAssertEqual(Syllabifier.syllables(of: "Schatten", language: .german), ["Schat", "ten"])
    }

    func testGerman_inseparableClusters_moveWholeToNextSyllable() {
        // ck never splits (Zu-cker), st stays a sung onset (Fen-ster).
        XCTAssertEqual(Syllabifier.syllables(of: "Zucker", language: .german), ["Zu", "cker"])
        XCTAssertEqual(Syllabifier.syllables(of: "Fenster", language: .german), ["Fen", "ster"])
    }

    func testGerman_diphthongsStayOneNucleus() {
        XCTAssertEqual(Syllabifier.syllables(of: "Melodie", language: .german), ["Me", "lo", "die"])
    }

    func testGerman_diphthongPairs_neverSplitInside() {
        // Cover the diphthong table beyond "ie": au / eu each stay one nucleus.
        XCTAssertEqual(Syllabifier.syllables(of: "Auge", language: .german), ["Au", "ge"])
        XCTAssertEqual(Syllabifier.syllables(of: "heute", language: .german), ["heu", "te"])
    }

    func testGerman_adjacentVowelHiatus_splitsBetweenNuclei() {
        // Two vowels that are NOT a diphthong ("ea") form separate nuclei and
        // split (the runLength<=0 branch the source documents as "Bea-te").
        XCTAssertEqual(Syllabifier.syllables(of: "Beate", language: .german), ["Be", "a", "te"])
    }

    func testGerman_midWordThreeConsonantCluster_keepsSchTogether() {
        // The width-3 onset-cluster match: "sch" mid-word starts the next syllable.
        XCTAssertEqual(Syllabifier.syllables(of: "rauschen", language: .german), ["rau", "schen"])
    }

    func testGerman_singleSyllableAndNoVowels_stayWhole() {
        XCTAssertEqual(Syllabifier.syllables(of: "Herbst", language: .german), ["Herbst"])
        XCTAssertEqual(Syllabifier.syllables(of: "hmm", language: .german), ["hmm"])
        XCTAssertEqual(Syllabifier.syllables(of: "", language: .german), [])
    }

    // MARK: - Syllabifier, English

    func testEnglish_openSyllablePreference() {
        // Sung distribution favours open syllables (vocal-writing convention).
        XCTAssertEqual(Syllabifier.syllables(of: "river", language: .english), ["ri", "ver"])
        XCTAssertEqual(Syllabifier.syllables(of: "water", language: .english), ["wa", "ter"])
        XCTAssertEqual(Syllabifier.syllables(of: "shadow", language: .english), ["sha", "dow"])
    }

    func testEnglish_silentFinalE_isNotASyllable() {
        XCTAssertEqual(Syllabifier.syllables(of: "time", language: .english), ["time"])
    }

    func testEnglish_consonantLE_isASungNucleus() {
        XCTAssertEqual(Syllabifier.syllables(of: "table", language: .english), ["ta", "ble"])
        XCTAssertEqual(Syllabifier.syllables(of: "little", language: .english), ["lit", "tle"])
        XCTAssertEqual(Syllabifier.syllables(of: "apple", language: .english), ["ap", "ple"])
    }

    func testEnglish_vowelRunsAreOneNucleus() {
        XCTAssertEqual(Syllabifier.syllables(of: "beautiful", language: .english),
                       ["beau", "ti", "ful"])
    }

    func testSyllabifier_isDeterministic() {
        let a = Syllabifier.syllables(of: "Melodie", language: .german)
        for _ in 0..<10 {
            XCTAssertEqual(Syllabifier.syllables(of: "Melodie", language: .german), a)
        }
    }

    // MARK: - Line splitting + display

    func testLine_wordBoundariesAndHyphens() {
        let syls = Syllabifier.syllables(ofLine: "Liebe singen", language: .german)
        XCTAssertEqual(syls.map(\.text), ["Lie", "be", "sin", "gen"])
        XCTAssertEqual(syls.map(\.isWordStart), [true, false, true, false])
        XCTAssertEqual(syls.map(\.isWordEnd), [false, true, false, true])
        // Vocal-score convention: hyphen while the word continues.
        XCTAssertEqual(syls.map(\.displayText), ["Lie-", "be", "sin-", "gen"])
    }

    func testDocument_allSyllables_singingOrderAcrossLines() {
        let doc = LyricsDocument(language: .german, lines: [
            LyricLine(syllables: Syllabifier.syllables(ofLine: "Liebe", language: .german)),
            LyricLine(syllables: Syllabifier.syllables(ofLine: "Atem", language: .german)),
        ])
        XCTAssertEqual(doc.allSyllables.map(\.text), ["Lie", "be", "A", "tem"])
    }

    // MARK: - Mapper (syllables → notes, melisma)

    private func makeNotes(_ startTicks: [Int]) -> [Note] {
        startTicks.map { Note(pitch: 60, startTick: $0, lengthTicks: 480) }
    }

    func testBind_oneSyllablePerNote_inTickOrder() {
        let notes = makeNotes([960, 0, 480])   // deliberately unsorted
        let syls = Syllabifier.syllables(ofLine: "Liebe singen", language: .german)
        let bound = LyricsMapper.bind(syllables: syls, to: notes)
        XCTAssertEqual(bound.count, 3)
        // Binding order follows startTick, not array order.
        XCTAssertEqual(bound.map(\.noteID), [notes[1].id, notes[2].id, notes[0].id])
        XCTAssertEqual(bound.map(\.syllableIndex), [0, 1, 2])
        XCTAssertFalse(bound.contains { $0.isMelismaExtension })
    }

    func testBind_melismaNoteHoldsPreviousSyllable() {
        let notes = makeNotes([0, 480, 960])
        let syls = Syllabifier.syllables(ofLine: "Liebe", language: .german)   // 2 syllables
        let bound = LyricsMapper.bind(syllables: syls, to: notes,
                                      melisma: [notes[1].id])
        XCTAssertEqual(bound.map(\.syllableIndex), [0, 0, 1])
        XCTAssertEqual(bound.map(\.isMelismaExtension), [false, true, false])
    }

    func testBind_moreNotesThanSyllables_trailingNotesAreVocalise() {
        let notes = makeNotes([0, 480, 960])
        let syls = [LyricSyllable(text: "La")]
        let bound = LyricsMapper.bind(syllables: syls, to: notes)
        XCTAssertEqual(bound.map(\.syllableIndex), [0, nil, nil])
    }

    func testBind_melismaOnFirstNoteWithNothingHeld_consumesNormally() {
        // A melisma mark with no previous syllable cannot hold anything —
        // the note consumes the first syllable instead of crashing/skipping.
        let notes = makeNotes([0])
        let syls = [LyricSyllable(text: "La")]
        let bound = LyricsMapper.bind(syllables: syls, to: notes,
                                      melisma: [notes[0].id])
        XCTAssertEqual(bound.map(\.syllableIndex), [0])
        XCTAssertEqual(bound.map(\.isMelismaExtension), [false])
    }

    func testBind_chordNotesOrderByPitch_stable() {
        // Same startTick → pitch breaks the tie, so binding is deterministic.
        let low = Note(pitch: 48, startTick: 0, lengthTicks: 480)
        let high = Note(pitch: 72, startTick: 0, lengthTicks: 480)
        let bound = LyricsMapper.bind(
            syllables: [LyricSyllable(text: "A"), LyricSyllable(text: "B")],
            to: [high, low]
        )
        XCTAssertEqual(bound.map(\.noteID), [low.id, high.id])
    }

    // MARK: - Persistence

    func testDocument_codableRoundTrip() throws {
        let doc = LyricsDocument(language: .english, lines: [
            LyricLine(syllables: Syllabifier.syllables(ofLine: "beautiful river", language: .english)),
        ])
        let back = try JSONDecoder().decode(LyricsDocument.self,
                                            from: JSONEncoder().encode(doc))
        XCTAssertEqual(back, doc)
    }

    func testBinding_codableRoundTrip() throws {
        let binding = LyricNoteBinding(noteID: UUID(), syllableIndex: 3,
                                       isMelismaExtension: true)
        let back = try JSONDecoder().decode(LyricNoteBinding.self,
                                            from: JSONEncoder().encode(binding))
        XCTAssertEqual(back, binding)
    }

    func testLanguage_rawValues_stableForPersistence() {
        XCTAssertEqual(LyricLanguage.german.rawValue, "german")
        XCTAssertEqual(LyricLanguage.english.rawValue, "english")
    }
}
