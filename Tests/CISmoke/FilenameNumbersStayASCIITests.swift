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

    /// The two formatters pinned AGAINST each other, on one explicit comma locale.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST COULD NOT FAIL FOR THE BUG IT WAS WRITTEN TO CATCH,
    /// and it looked like it could, which is worse than not existing. It looped over seven
    /// locale identifiers and asserted against `SessionNaming.trimmed(_:)` — a function that
    /// TAKES NO LOCALE. So if someone did the exact thing the header warns about and rewrote
    /// `trimmed` to call `EchoelDecimalText.string(…)`, that call would use `locale:
    /// .current`; no workflow in `.github/` sets `LANG`/`LC_ALL`, a macOS runner is en_US,
    /// the output stays "442.42", and every assertion passes while the bug ships. The seven
    /// identifiers manufactured an appearance of locale coverage that did not exist.
    ///
    /// This version pins the CONTRACT instead: the same number, through the two formatters,
    /// must come out DIFFERENT — and the readout side names its locale explicitly, so it
    /// cannot be neutralized by the runner's default. Merging the two implementations in
    /// either direction now fails here.
    func testTheTwoFormattersArePinnedToGoOppositeWays() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(EchoelDecimalText.separator(german), ",",
                       "precondition: de_DE must read a comma, or the pin below proves nothing")

        for value in [70.0, 123.5, 442.42, 60.25] {
            let readout = EchoelDecimalText.string(value, decimals: 2, locale: german)
            let filename = SessionNaming.trimmed(value)

            XCTAssertTrue(readout.contains(","),
                          "a German READOUT of \(value) must carry a comma, got \"\(readout)\"")
            XCTAssertFalse(filename.contains(","),
                           "\"\(filename)\" carries a comma. A filename number must stay ASCII: "
                           + "it sorts differently, hosts and cloud syncs mangle it, and it "
                           + "reads as corrupt beside yesterday's exports. If this failed "
                           + "because `SessionNaming.trimmed` was routed through "
                           + "`EchoelDecimalText`, THAT is the bug — readouts localize, "
                           + "filenames do not.")
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
