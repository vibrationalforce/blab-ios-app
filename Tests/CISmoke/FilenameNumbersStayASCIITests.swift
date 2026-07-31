// FilenameNumbersStayASCIITests.swift
// Echoel — the OTHER half of #232 G, and the one with no visible symptom until it bites.
//
// #267 routed every user-visible readout through `EchoelDecimalText`, so a German player
// reads "0,50". A filename must go the OPPOSITE way and stay ASCII forever. `SessionNaming`
// stamps tempo and concert pitch into export filenames ("E~Studio_2026-07-31_70_442.42"),
// and a comma there is not a nicer number — it is a filename that sorts differently, that
// some hosts and cloud syncs mangle, and that reads as corrupt next to yesterday's exports.
//
// THE CONCRETE RISK THIS GUARDS: the follow-up sweep to #267 walked a list of
// `String(format: "%.Nf")` sites and had to decide, per site, "display or filename?".
// `SessionNaming.trimmed` looks EXACTLY like a display formatter — same call, same two
// decimals, no unit — and a later pass with less context will convert it. Nothing else
// would notice: no compile error, no crash, correct-looking output on an English simulator,
// and the damage only appears on a German device, in a filename the user already saved.
//
// ⚠️ What this asserts is a property of the CALL SITE, not of `printf`. `String(format:)` is
// nil-locale by definition, so today's implementation cannot produce a comma no matter what
// `Locale.current` is. That is exactly why the assertion is written against the app's own
// function rather than against `printf`: it fails the moment someone swaps the call, which
// is the only way this can break.

import Foundation
import XCTest
@testable import Echoelmusic

final class FilenameNumbersStayASCIITests: XCTestCase {

    /// The numbers that actually reach a filename: tempo (integral and fractional) and
    /// concert pitch. `trimmed` is the one formatter on that path.
    func testFilenameNumbersUseAnASCIIPointInEveryLocale() {
        // A separator this app would render as "," / "٫" for a READOUT.
        let commaLocales = ["de_DE", "fr_FR", "pt_BR", "ru_RU", "tr_TR", "sv_SE", "ar_EG"]
        for id in commaLocales {
            let sep = EchoelDecimalText.separator(Locale(identifier: id))
            guard sep != "." else { continue }   // vacuous for a point locale, never false

            for value in [70.0, 123.5, 442.42, 432.0, 60.25] {
                let stamped = SessionNaming.trimmed(value)
                XCTAssertFalse(stamped.contains(sep),
                               "\(id): \"\(stamped)\" carries \(sep) — a filename number must "
                               + "stay ASCII. If this failed because someone routed "
                               + "`SessionNaming.trimmed` through `EchoelDecimalText`, that is "
                               + "the bug: readouts localize, filenames do not.")
                XCTAssertFalse(stamped.contains(","),
                               "\(id): \"\(stamped)\" carries a comma")
            }
        }
    }

    /// The trimming contract itself, pinned alongside — because the fix for a failure above
    /// would be to hand-write a formatter here, and the easiest way to get that wrong is to
    /// drop the trailing-zero trim that keeps "124" from becoming "124.00" in every filename.
    func testTrimmedKeepsItsShape() {
        XCTAssertEqual(SessionNaming.trimmed(124.0), "124")
        XCTAssertEqual(SessionNaming.trimmed(123.50), "123.5")
        XCTAssertEqual(SessionNaming.trimmed(442.42), "442.42")
        XCTAssertEqual(SessionNaming.trimmed(0), "0")
    }

    /// And the whole filename, end to end — because `trimmed` being right does not prove the
    /// assembled name is, and the name is what lands in the user's Files app.
    func testTheAssembledFileNameCarriesNoLocaleSeparator() {
        let name = SessionNaming.fileName(artist: "E~", date: Date(timeIntervalSince1970: 1_800_000_000),
                                          key: "Am", bpm: 123.5, a4Hz: 442.42,
                                          part: "Loop", ext: "wav", place: "Hamburg")
        XCTAssertTrue(name.hasSuffix(".wav"), name)
        XCTAssertTrue(name.contains("123.5bpm"), "tempo lost its ASCII point: \(name)")
        XCTAssertTrue(name.contains("A442.42"), "concert pitch lost its ASCII point: \(name)")
        XCTAssertFalse(name.contains(","), name)

        // ⚠️ NOT an ASCII assertion, deliberately. `sanitize` keeps `CharacterSet
        // .alphanumerics`, which is Unicode-wide, so a Japanese or Arabic PLACE name
        // survives into the filename by design (founder 2026-07-14: manual place entry).
        // This pins the punctuation set only — the part that carries the numbers.
        let punctuation = name.unicodeScalars.filter { !CharacterSet.alphanumerics.contains($0) }
        XCTAssertTrue(punctuation.allSatisfy { "~_-.".unicodeScalars.contains($0) },
                      "\(name) carries punctuation outside the filename-safe set")
    }
}
