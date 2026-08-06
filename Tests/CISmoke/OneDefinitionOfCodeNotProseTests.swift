// OneDefinitionOfCodeNotProseTests.swift
// Echoel — #453. The guard over ELEVEN copies of one decision, and over the one that replaces them.
//
// WHAT WAS WRONG. A large share of this bundle asserts on SOURCE TEXT, so every such guard first
// has to strip comments — this repo writes ⛔/⭐ blocks that quote the exact tokens the guards
// forbid (#404 solved the same problem on the source side). That stripping was written ELEVEN
// times, in FIVE materially different shapes. `SourceText.swift` carries the count and the shapes;
// this file is the half that notices when they drift.
//
// ⚠️ THE HONEST SCOPE, because a guard that oversells itself is the defect it is guarding against:
// on today's tree the eleven AGREE for every `contains`-style assertion, so THREE were migrated —
// exactly the ones that scan `RespirationEstimator.swift` and `BreathPattern.swift`, i.e. the
// demonstrated same-target divergence. The other EIGHT are on an explicit permission list below,
// and that list is checked in BOTH directions: an entry whose file no longer holds a private copy
// is a stale licence and goes red, so migrating one forces this list to shrink in the same commit
// (#440's form).
//
// ⭐ THE ONE PART THAT IS NOT PROPHYLACTIC, and the reason the shared scanner is ORDERED rather
// than merely thorough: two of the eleven strip `/* … */` BEFORE line comments. A `/*` that is not
// a block opener at all — inside a `///` line, inside a string — therefore opens a phantom block
// and swallows every line down to the next `*/`. `Sources/` already holds 8 such `/*` across 6
// files, one of them in `BreathPattern.swift`, which `ThePacedRateMustBeReadableTests` scans.
// `testADocCommentSlashStarDoesNotEatTheNextLine` is that case, and it is RED on shape 5.
//
// ⚠️ WHAT THIS CANNOT SHOW: that any of the eight remaining copies is wrong today. It is not — it
// is measured equivalent. What it shows is that there is now one place to fix, and a list that
// cannot rot quietly.

import Foundation
import XCTest

final class OneDefinitionOfCodeNotProseTests: XCTestCase {

    /// Files that still carry their own private stripper. Shrink this list when you migrate one —
    /// the test below goes red if an entry is stale, so it cannot silently outlive its reason.
    private let notYetMigrated: [String] = [
        "BioSmoothingSharesOnePoleTests.swift",
        "ControllerEventDrainIsPushedTests.swift",
        "DisabledReverbIsNotClaimedLiveTests.swift",
        "EveryReachableRowStatesItsGridTests.swift",
        "ResonanceBreathingNeedsMoreThanOneWindowTests.swift",
        "TheDynamicsAreThePersonsTests.swift",
        "TheManifestArgumentOrderIsTheCompilersTests.swift",
        "TheShownNumberIsTheKeptNumberTests.swift",
    ]

    /// The three that scan the same sources and therefore had to agree first.
    private let migrated: [String] = [
        "ARejectedCrossingIsNotFreshnessTests.swift",
        "TheBandEdgeIsMeasurableTests.swift",
        "ThePacedRateMustBeReadableTests.swift",
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

    // MARK: - The wiring, and the permission list

    func testTheThreeSameTargetGuardsDelegate() throws {
        for name in migrated {
            let code = try read(name)
            XCTAssertTrue(code.contains("SourceText.codeOnly"), """
                \(name) scans a source file that another guard in this bundle also scans, but it \
                no longer routes its stripping through SourceText. Two shapes over one file is \
                the #416 defect this slice removed.
                """)
        }
    }

    /// Both directions. A stale licence — a file that migrated, or one that no longer exists —
    /// is exactly how a permission list turns into a lie (#440).
    func testThePermissionListIsNotStale() throws {
        for name in notYetMigrated {
            let code = try read(name)
            XCTAssertTrue(code.contains("func codeOnly"), """
                \(name) is listed as still carrying its own stripper, but declares none. Remove \
                the entry — a permission list that outlives its reason reads as coverage.
                """)
            XCTAssertFalse(code.contains("SourceText.codeOnly"), """
                \(name) already delegates to SourceText but is still on the not-yet-migrated \
                list. Take it off in the same commit that migrated it.
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
            if notYetMigrated.contains(name) { continue }
            offenders.append(name)
        }
        XCTAssertEqual(offenders, [], """
            \(offenders.joined(separator: ", ")) declare their own comment stripper without \
            delegating to SourceText and without being on the permission list. That is a new \
            copy of a decision this bundle already made eleven times (#453).
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
