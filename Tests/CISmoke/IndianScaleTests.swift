// IndianScaleTests.swift
// Echoel — the scale list had six Japanese pentatonics, the Maqām family and a Balinese
// approximation, and not one named Indian entry (#232 J). This pins the seven that closed
// that hole, plus the two structural properties the closure ARGUES FROM.
//
// The argument was: seven of the ten Hindustani thāts are already reachable under Western
// names (Bilāval = major, Kāfī = dorian, Bhairav = doubleHarmonic …), so adding aliases
// would put duplicate pitch sets in one picker; only the genuinely absent sets were added.
// `testNoTwoScalesShareAPitchSet` is that argument as an assertion. Without it the claim
// is a comment, and the next person adding "Bilaval" for discoverability gets a picker
// with two rows that sound identical and no test to stop them.
//
// ⚠️ WHY HERE AND NOT IN `Tests/EchoelmusicTests/MusicalKeyTests`. That suite already has
// range/uniqueness checks and is the natural home — but it runs `continue-on-error: true`
// (#208), so it cannot redden a merge. `Tests/CISmoke` is the only bundle that blocks.
//
// PRECISELY WHAT IS DUPLICATED, because the first version of this note waved at
// `testAllScalesNonEmptyAndInRange` as if the whole thing were copied: that test sweeps
// `Scale.allCases` for non-empty · in-range · ascending · first == 0 · no repeated degree ·
// non-empty name · non-empty tag. Reproduced here over `allCases`, in the blocking bundle:
// the well-formedness sweep, the tag/name UNIQUENESS pair, and the ASCII rule (which has
// no equivalent anywhere). Everything else here is new.

import Foundation
import XCTest
@testable import Echoelmusic

final class IndianScaleTests: XCTestCase {

    /// Swaras in the comment on each row so the set is checkable against a rāga reference
    /// without translating twice. Sa is the root throughout.
    private static let expected: [(Scale, [Int], String)] = [
        (.marwa,           [0, 1, 4, 6, 7, 9, 11],  "S r G M♯ P D N"),
        (.purvi,           [0, 1, 4, 6, 7, 8, 11],  "S r G M♯ P d N"),
        (.todi,            [0, 1, 3, 6, 7, 8, 11],  "S r g M♯ P d N"),
        (.malkauns,        [0, 3, 5, 8, 10],        "S g m d n"),
        (.charukeshi,      [0, 2, 4, 5, 7, 8, 10],  "S R G m P d n"),
        (.hamsadhwani,     [0, 2, 4, 7, 11],        "S R G P N"),
        (.shanmukhapriya,  [0, 2, 3, 6, 7, 8, 10],  "S R g M♯ P d n"),
    ]

    func testTheSevenAddedScalesHaveTheirDocumentedPitchSets() {
        for (scale, intervals, swaras) in Self.expected {
            XCTAssertEqual(scale.intervals, intervals,
                           "\(scale) must be \(swaras) — a scale whose pitches drift is a "
                           + "different scale wearing the same name")
        }
    }

    /// The structural claim behind the whole slice. Two rows in the key picker that produce
    /// the same notes are a lie about how much the instrument can do.
    ///
    /// ⚠️ THIS IS A POLICY, NOT A LAW — and it is a blocking gate, so say so out loud. It
    /// forbids ever shipping "Bhairav" beside `doubleHarmonic` or "Kāfī" beside `dorian`,
    /// which is the most obvious next step of this same epic (see the trade-off note in
    /// `MusicalKey.swift`: an Indian reader currently sees three of ten thāts named). If
    /// the founder decides those aliases should exist, the right shape is ONE case with a
    /// per-tradition display name — and this test gets rewritten, not deleted quietly.
    func testNoTwoScalesShareAPitchSet() {
        var byPitchSet: [[Int]: [Scale]] = [:]
        for scale in Scale.allCases {
            byPitchSet[scale.intervals, default: []].append(scale)
        }
        let collisions = byPitchSet.filter { $0.value.count > 1 }
        XCTAssertTrue(collisions.isEmpty,
                      "these scales are the same notes under different names, so the picker "
                      + "offers a choice that changes nothing: "
                      + collisions.map { "\($0.value.map(\.displayName)) = \($0.key)" }
                                  .sorted().joined(separator: "; "))
    }

    /// `shortTag` is stamped into share-sheet FILENAMES. A diacritic there round-trips
    /// through a file system as composed or decomposed Unicode depending on the path, and
    /// two devices stop agreeing on the name of the same take — the same reason
    /// `MusicalKey.shortName` folds ♯ to "s". This is the guard on writing "Cārukeśī".
    func testEveryScaleTagStaysFilenameSafeASCII() {
        // Spelled out rather than via `CharacterSet.alphanumerics`, which ACCEPTS "ā" and
        // "ś" — it is the Unicode alphanumeric set, not the ASCII one, so using it here
        // would have passed exactly the spelling this test exists to reject.
        for scale in Scale.allCases {
            let tag = scale.shortTag
            XCTAssertFalse(tag.isEmpty, "\(scale) has no tag")
            XCTAssertTrue(tag.unicodeScalars.allSatisfy { $0.isASCII },
                          "\(scale) tag \"\(tag)\" is not ASCII, and it goes into a filename")
            XCTAssertTrue(tag.allSatisfy { $0.isLetter || $0.isNumber },
                          "\(scale) tag \"\(tag)\" has a separator or punctuation character")
        }

        // UNIQUENESS BELONGS HERE TOO, and the source comment in `MusicalKey.swift` used
        // to point at `MusicalKeyTests` for it — a suite that runs continue-on-error and
        // therefore guarantees nothing at a merge. The new tags are exactly the
        // collision-prone kind: "malk", "charu", "hamsa", "shanmu" are truncations. Two
        // keys sharing a tag means two different takes exporting under one filename.
        XCTAssertEqual(Set(Scale.allCases.map(\.shortTag)).count, Scale.allCases.count,
                       "two scales share a filename tag")
        XCTAssertEqual(Set(Scale.allCases.map(\.displayName)).count, Scale.allCases.count,
                       "two scales share a picker label, so one of them is unpickable")
    }

    /// Raw values are PERSISTED in every saved project and session (`SessionContext`,
    /// `Project`, `@AppStorage`), and every decode site falls back to `.minor` — silently.
    ///
    /// ⚠️ WHAT THIS ACTUALLY GUARDS, corrected: NOT "renaming a case". A rename makes
    /// `Scale.marwa` below a COMPILE error, so this test would never even run. It catches
    /// the change that still compiles — someone attaching an explicit raw value
    /// (`case marwa = "raga_marwa"`), after which every saved project silently reopens in
    /// C Minor instead of the key it was written in.
    func testTheAddedRawValuesArePersistedAndStable() {
        XCTAssertEqual(Scale.marwa.rawValue, "marwa")
        XCTAssertEqual(Scale.purvi.rawValue, "purvi")
        XCTAssertEqual(Scale.todi.rawValue, "todi")
        XCTAssertEqual(Scale.malkauns.rawValue, "malkauns")
        XCTAssertEqual(Scale.charukeshi.rawValue, "charukeshi")
        XCTAssertEqual(Scale.hamsadhwani.rawValue, "hamsadhwani")
        XCTAssertEqual(Scale.shanmukhapriya.rawValue, "shanmukhapriya")
    }

    /// Every scale must be walkable by degree — the arp and chord builders index into
    /// `intervals`, and `malkauns`/`hamsadhwani` have five degrees where most neighbours
    /// have seven.
    ///
    /// ⚠️ IT SWEEPS `Scale.allCases`, NOT `Self.expected`, and the first version did the
    /// latter — which made it a test that could not fail on its own. `Self.expected`'s
    /// literals are already asserted to equal `scale.intervals` two methods up, and those
    /// literals satisfy every property checked here by inspection, so the only world where
    /// this failed was one where the other test had already gone red. Over `allCases` it
    /// has its own failure mode AND brings the well-formedness sweep — which otherwise
    /// exists only in the non-blocking suite — into the bundle that can stop a merge.
    func testEveryScaleIsWellFormedForDegreeWalking() {
        for scale in Scale.allCases {
            let iv = scale.intervals
            XCTAssertEqual(iv.first, 0, "\(scale) must start on the root")
            XCTAssertEqual(iv, iv.sorted(), "\(scale) must ascend")
            XCTAssertEqual(Set(iv).count, iv.count, "\(scale) repeats a degree")
            XCTAssertTrue(iv.allSatisfy { (0...11).contains($0) },
                          "\(scale) leaves the octave: \(iv)")
            XCTAssertGreaterThanOrEqual(iv.count, 5, "\(scale) is too sparse to walk")
        }
    }
}
