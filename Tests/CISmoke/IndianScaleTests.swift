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
// (#208), so it cannot redden a merge. `Tests/CISmoke` is the only bundle that blocks. The
// overlap with `testAllScalesNonEmptyAndInRange` is deliberate duplication of the checks
// this slice depends on, not an oversight.

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
    }

    /// Raw values are PERSISTED in every saved project and session. Renaming a case silently
    /// resets a user's key to the default the next time they open their own work.
    func testTheAddedRawValuesArePersistedAndStable() {
        XCTAssertEqual(Scale.marwa.rawValue, "marwa")
        XCTAssertEqual(Scale.purvi.rawValue, "purvi")
        XCTAssertEqual(Scale.todi.rawValue, "todi")
        XCTAssertEqual(Scale.malkauns.rawValue, "malkauns")
        XCTAssertEqual(Scale.charukeshi.rawValue, "charukeshi")
        XCTAssertEqual(Scale.hamsadhwani.rawValue, "hamsadhwani")
        XCTAssertEqual(Scale.shanmukhapriya.rawValue, "shanmukhapriya")
    }

    /// Pentatonic entries are the ones a degree-walking composer can trip over: `malkauns`
    /// and `hamsadhwani` have five degrees where most neighbours have seven, and the arp /
    /// chord builders index by degree. The generic guards live in the non-blocking suite;
    /// this is the narrow one for the shapes this slice introduced.
    func testTheAddedScalesAreWellFormedForDegreeWalking() {
        for (scale, _, _) in Self.expected {
            let iv = scale.intervals
            XCTAssertEqual(iv.first, 0, "\(scale) must start on Sa")
            XCTAssertEqual(iv, iv.sorted(), "\(scale) must ascend")
            XCTAssertEqual(Set(iv).count, iv.count, "\(scale) repeats a degree")
            XCTAssertTrue(iv.allSatisfy { (0...11).contains($0) },
                          "\(scale) leaves the octave: \(iv)")
            XCTAssertGreaterThanOrEqual(iv.count, 5, "\(scale) is too sparse to walk")
        }
    }
}
