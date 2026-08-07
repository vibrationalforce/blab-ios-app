// OneDefinitionOfCodeNotProseTests.swift
// Echoel — #453. The guard over ELEVEN copies of one decision, and over the one that replaces them.
//
// WHAT WAS WRONG. A large share of this bundle asserts on SOURCE TEXT, so every such guard first
// has to strip comments — this repo writes ⛔/⭐ blocks that quote the exact tokens the guards
// forbid (#404 solved the same problem on the source side). That stripping was written ELEVEN
// times, in FIVE materially different shapes. `SourceText.swift` carries the count and the shapes;
// this file is the half that notices when they drift.
//
// ⭐ THE ONE PART THAT IS NOT PROPHYLACTIC, and the reason the shared scanner is ORDERED rather
// than merely thorough: two of the eleven strip `/* … */` BEFORE line comments. A `/*` that is not
// a block opener at all — inside a `///` line, inside a string — therefore opens a phantom block
// and swallows every line down to the next `*/`. `Sources/` already holds 8 such `/*` across 6
// files, one of them in `BreathPattern.swift`, which `ThePacedRateMustBeReadableTests` scans.
// `testADocCommentSlashStarDoesNotEatTheNextLine` is that case, and it is RED on shape 5.
//
// ⛔ THE FIRST VERSION SHIPPED THREE OF THE ELEVEN AND PUT THE OTHER EIGHT ON A PERMISSION LIST,
// on the measured claim that "no scanned line holds a `//` inside a string literal". That claim is
// FALSE, and the counter-example is scanned by this bundle every run: `EchoelStudioView.swift`
// holds the WeatherKit attribution URL in `URL(string: "https://developer.apple.com/…")`. It was
// the ONE line on which the truncating shapes and the ordered scanner disagreed. The eight are
// migrated here, so the permission list is gone rather than corrected — a licence granted on a
// premise that did not hold is not worth keeping in either direction.
//
// ⚠️ WHAT THIS CANNOT SHOW: that any of the eight was wrong TODAY. Measured before migrating,
// every one is verdict-neutral. The grid guard is the sharpest case, because it is the one whose
// needle also appears in prose: `decimals:` sits in trailing comments 9× in EchoelValueField.swift,
// 8× in EchoelStudioView.swift, 2× in EchoelFXView.swift and 1× each in BodyTempoField.swift and
// WorkspaceView.swift — under a shape that keeps trailing comments, any of those inside a call
// site's line span would have satisfied the guard as PROSE. Measured both ways, the site counts
// (1/1, 4/4, 46/46, 1/1 for `EchoelValueField(`; 44/44 for `field(`) and the missing-`decimals:`
// sets ([131] on BodyTempoField, empty elsewhere) are IDENTICAL. This slice removes a mechanism,
// not a defect.
//
// ⚠️ AND THE LIST BELOW IS A FLOOR, NOT A CENSUS. It names the eleven known scanning guards and
// checks that each still delegates. It deliberately does NOT demand that every future delegating
// guard be listed: a new guard reaching for the shared scanner is the behaviour this slice wants,
// and a rule that turns it red would be obeying its own letter against its purpose (#364). What
// catches drift in the other direction is `testNoUnlistedFileDeclaresItsOwnStripper`, which is
// about a TWELFTH private copy and needs no list at all.

import Foundation
import XCTest

final class OneDefinitionOfCodeNotProseTests: XCTestCase {

    /// The eleven guards that assert on source text and therefore have to strip comments first.
    /// Each must route that stripping through `SourceText` — some through a one-line private
    /// wrapper kept so no call site changed, one (`ARejectedCrossing…`) directly at its call sites.
    private let scanningGuards: [String] = [
        "ARejectedCrossingIsNotFreshnessTests.swift",
        "BioSmoothingSharesOnePoleTests.swift",
        "ControllerEventDrainIsPushedTests.swift",
        "DisabledReverbIsNotClaimedLiveTests.swift",
        "EveryReachableRowStatesItsGridTests.swift",
        "ResonanceBreathingNeedsMoreThanOneWindowTests.swift",
        "TheBandEdgeIsMeasurableTests.swift",
        "TheDynamicsAreThePersonsTests.swift",
        "TheManifestArgumentOrderIsTheCompilersTests.swift",
        "ThePacedRateMustBeReadableTests.swift",
        "TheShownNumberIsTheKeptNumberTests.swift",
    ]

    // MARK: - The scanner itself

    /// The finding, stated as a test: a `/*` inside a doc comment is not a block opener.
    /// RED on the two shapes that strip blocks first — they return everything up to the next
    /// `*/`, i.e. the whole rest of the file, so the `let` below vanishes and a positive scan
    /// for it fails while a negative scan for anything passes on nothing.
    func testADocCommentSlashStarDoesNotEatTheNextLine() {
        let source = """
        /// Sends to `/echoelmusic/bio/breath/*` on every onset.
        let breathAddress = "onset"
        """
        let code = SourceText.codeOnly(source)
        XCTAssertTrue(code.contains("let breathAddress"), """
            A `/*` inside a doc comment opened a block and swallowed the code line after it. \
            Strip line comments BEFORE blocks; Sources/ holds 8 such non-opening `/*` today.
            """)
        XCTAssertFalse(code.contains("echoelmusic"), "The doc line itself must not survive.")
    }

    /// A URL in a string literal is code, not a comment. Four of the eleven shapes truncate at
    /// the first `//` unconditionally and would delete the rest of this line.
    func testASlashSlashInsideAStringIsNotAComment() {
        let code = SourceText.codeOnly(#"let site = "https://echoel.app" // the marketing page"#)
        XCTAssertTrue(code.contains("https://echoel.app"), """
            The `//` inside the string literal was treated as a comment, so the line lost its \
            value. A scan asserting on that URL would fail on correct code.
            """)
        XCTAssertFalse(code.contains("marketing"), "The real trailing comment must still go.")
    }

    /// Several guards assert on the ORDER of two matches, so a stripper must not delete lines.
    func testLineCountIsPreserved() {
        let source = """
        let a = 1
        // a whole-line comment
        let b = 2
        """
        XCTAssertEqual(SourceText.codeOnly(source).split(separator: "\n",
                                                         omittingEmptySubsequences: false).count,
                       3, "Comment lines must be blanked, never dropped.")
    }

    /// A genuine multi-line block must still be removed across lines — otherwise the shared
    /// scanner would be strictly weaker than the two shapes it replaces.
    func testARealBlockCommentIsRemovedAcrossLines() {
        let source = """
        let before = 1
        /* forbiddenToken
           still forbiddenToken */
        let after = 2
        """
        let code = SourceText.codeOnly(source)
        XCTAssertFalse(code.contains("forbiddenToken"), "A real block comment must not survive.")
        XCTAssertTrue(code.contains("let before"), "Code before the block must survive.")
        XCTAssertTrue(code.contains("let after"), "Code after the block must survive.")
    }

    /// An escaped quote must not leave string state inverted — if it did, the `//` after it
    /// would be kept as code and every later line of the file would be mis-stripped.
    func testAnEscapedQuoteDoesNotInvertStringState() {
        let code = SourceText.codeOnly(#"let q = "a \" b" // trailing"#)
        XCTAssertFalse(code.contains("trailing"), """
            The escaped quote left the scanner inside a string literal, so the trailing comment \
            survived as code.
            """)
    }

    // MARK: - The wiring

    /// The forward direction: every known scanning guard still routes its stripping through the
    /// one definition. `read` fails loudly for a name that is gone, so a deleted guard cannot
    /// leave a silently-passing entry behind.
    func testEveryScanningGuardDelegates() throws {
        for name in scanningGuards {
            let code = try read(name)
            XCTAssertTrue(code.contains("SourceText.codeOnly"), """
                \(name) strips comments before asserting on source text, but no longer routes \
                that through SourceText. A second shape over the same sources is the #416 defect \
                this slice removed — and the shapes are NOT interchangeable: they disagree on the \
                WeatherKit attribution URL in EchoelStudioView.swift.
                """)
        }
    }

    /// A twelfth private copy must not be able to appear unnoticed.
    func testNoUnlistedFileDeclaresItsOwnStripper() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertGreaterThan(files.count, 100, """
            Only \(files.count) files found in Tests/CISmoke — the scan is looking at the wrong \
            directory, so a green result below proves nothing.
            """)

        // The definition itself, and this guard — both quote `func codeOnly` in prose and would
        // otherwise report themselves. Named explicitly rather than relying on the fact that
        // both happen to mention `SourceText.codeOnly`: an accidental exemption is not one.
        let selfExempt = ["SourceText.swift", "OneDefinitionOfCodeNotProseTests.swift"]
        var offenders: [String] = []
        for name in files where !selfExempt.contains(name) {
            let code = try read(name)
            guard code.contains("func codeOnly") else { continue }
            if code.contains("SourceText.codeOnly") { continue }
            offenders.append(name)
        }
        XCTAssertEqual(offenders, [], """
            \(offenders.joined(separator: ", ")) declare their own comment stripper without \
            delegating to SourceText. That is a TWELFTH copy of a decision this bundle already \
            made eleven times, and the eleven were not interchangeable (#453).
            """)
    }

    // MARK: - Helper

    private func read(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("\(name) is not in Tests/CISmoke — this guard names a file that is gone.")
            throw XCTSkip("\(name) missing")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
