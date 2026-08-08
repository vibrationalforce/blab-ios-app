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

    /// The fifteen guards that assert on source text and therefore have to strip comments first.
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
        // ⛔ THE TWELFTH, AND IT WAS ALREADY HERE WHEN THIS LIST WAS WRITTEN. #453 surveyed
        // eleven strippers and folded eleven in; `TimingVerdictReachesTheScreenTests` (#408)
        // predates #453 and carried a private `func codeOnly` that did NOT delegate. The guard
        // below selects it deterministically — replicating its logic against the tree returns
        // exactly that one file — so the survey missed what the guard could not.
        // ⚠️ Said precisely: it WOULD have failed on any run that reached it, and whether any
        // run reached it is unknowable. It appears in no flushed CI log, and under #445 that
        // absence proves nothing: #396 kills one simulator clone mid-suite and the survivor
        // flushes a non-deterministic subset. A verdict nobody can observe is the shape this
        // bundle exists to avoid, and it stood from #453 until #477.
        "TimingVerdictReachesTheScreenTests.swift",
        // ⭐ THE THIRTEENTH, FOURTEENTH AND FIFTEENTH (#460). All three declared
        // `stripComments` — a name this file's other guard cannot see — and all three used the
        // NAIVE truncate at the first `//`, which also cuts a `//` inside a string literal.
        // Measured before folding them in: verdict-neutral on every literal each file holds
        // (0 flips), but two sources they scan carry such a line — `EchoelStudioView.swift`
        // (WeatherKit attribution) and `WorkspaceView.swift` (the website URL) — so a future
        // needle there would have gone red on CORRECT code. `stripComments` now has ZERO
        // non-delegating declarers; `stripComment`, `sourceLines` and `codeLines` still do,
        // which is the rest of #460 and is measured in the doc comment below.
        "PoincareViewDoorTests.swift",
        "ScopeTriggerStandsStillTests.swift",
        "WeatherToneIsAudibleTests.swift",
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

    /// A further private copy must not be able to appear unnoticed.
    ///
    /// ⚠️ IT DETECTS BY NAME, AND THAT IS A MEASURED BLIND SPOT, NOT A THEORETICAL ONE. The
    /// anchor is `func codeOnly`, so a copy under any other name is invisible to it. Re-counted
    /// across `Tests/CISmoke` on 2026-08-08, AFTER #460 folded the three `stripComments` files
    /// in — `git grep` the five names and cross them with `SourceText.codeOnly`:
    /// **8** files declare `stripComment` and none delegate, **2** declare `sourceLines` and
    /// none delegate, **63** declare `codeLines` of which **58** do not — **61 files in total**
    /// still hold a private stripper. `stripComments` is now at **zero**. So the true copy count
    /// is far above fifteen; this guard covers the `codeOnly` family only.
    ///
    /// ⚠️ AND #460 MEASURED WHAT THAT COSTS TODAY, so the deferral below is a number and not a
    /// hope. The 61 differ from `SourceText.codeOnly` in exactly two ways: 47 of them drop whole
    /// `//` lines and therefore RETAIN trailing comments (they keep text the scanner cuts, in
    /// 185 of 349 sources); the rest truncate and can eat a `//` inside a string literal. Their
    /// non-empty LINE ARRAYS agree with the scanner in count on every source they scan (110
    /// pairs), so index arithmetic, `firstIndex` and ordering claims are untouched. Verdict
    /// flips today: **zero**, over 650 literal-needle pairs and 3374 literal×source triples.
    /// Latent, therefore — and one keystroke from live, because a negative scan whose needle
    /// lands in one of this repo's ⛔ retraction comments goes red on CORRECT code.
    ///
    /// Widening the anchor is #460 and is deliberately NOT done here: it would turn ~70 files
    /// red in one commit, and each needs its own read (some `codeLines` also filter blanks or
    /// keep line numbers, so they are not drop-in replaceable). A guard that reds on correct
    /// work until someone does a week of migration gets deleted, which is the #364 trap. What
    /// this file can honestly claim is stated in its own name.
    ///
    /// ⚠️ AND THE EXEMPTION IS RAW-TEXT, so it can be satisfied by PROSE: a file that keeps its
    /// private copy and merely writes `SourceText.codeOnly` in a comment passes. `read` returns
    /// raw text on purpose — this file and `SourceText.swift` both quote `func codeOnly` in
    /// prose and would otherwise report themselves — so the looseness is the price of the
    /// self-exemption, not an oversight. Stated rather than tightened: the tight version needs
    /// to tell a call site from a mention, which is the "code, not prose" problem this whole
    /// file exists to solve, applied to itself.
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
            delegating to SourceText. That is one more copy of a decision this bundle already \
            made twelve times, and the twelve were not interchangeable (#453). Call \
            SourceText.codeOnly, or — if the new shape genuinely differs — say so at the \
            declaration and add the file to `scanningGuards` above so the difference is a \
            stated choice rather than a drift.

            ⛔ Do NOT satisfy this by renaming the helper. The anchor is the string \
            `func codeOnly`; `stripComment`, `codeLines` and friends are already invisible to \
            it, which is #460 and is measured in this test's doc comment. Renaming to hide \
            from a guard is worse than the copy it hides.
            """)
    }

    /// COUNTERWEIGHT (#343/#460): the reason the shapes are not interchangeable must keep
    /// existing, or every claim above quietly becomes vacuous.
    ///
    /// `testEveryScanningGuardDelegates` says the shapes "disagree on the WeatherKit
    /// attribution URL in EchoelStudioView.swift". That sentence is only true while such a
    /// line exists. Measured 2026-08-08, the two sources the fifteen guards scan that carry a
    /// `//` INSIDE a string literal are `EchoelStudioView.swift` (the WeatherKit attribution)
    /// and `WorkspaceView.swift` (the website URL) — exactly one line each. Delete or reword
    /// them and the disagreement is gone; the private shapes would then be genuinely equivalent
    /// on today's tree, and the next session would read the sentence above as still-binding
    /// evidence for a difference nobody can reproduce.
    ///
    /// So this pins the WITNESS, not the URL: the scanner must keep the whole literal, and a
    /// naive truncate at the first `//` must NOT. Both halves are computed here rather than
    /// asserted, so the day the witness goes the test says which half broke.
    func testTheWitnessForTheDisagreementStillExists() throws {
        let sources = [
            "Sources/Echoelmusic/Studio/EchoelStudioView.swift",
            "Sources/Echoelmusic/Studio/WorkspaceView.swift",
        ]
        var witnesses: [String] = []
        for path in sources {
            let text = try readSource(path)
            // `codeOnly` preserves the line count, so the two arrays line up index for index.
            let raw = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let kept = SourceText.codeOnly(text)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            XCTAssertEqual(raw.count, kept.count, """
                SourceText.codeOnly no longer preserves the line count on \(path). Several \
                guards in this bundle assert on the ORDER of two matches; a scanner that drops \
                lines breaks them silently.
                """)
            guard raw.count == kept.count else { return }
            for i in 0..<raw.count {
                // A line the scanner left untouched, that nevertheless holds a `//`, is one
                // where the `//` sits inside a string literal. A naive truncate cuts it there.
                guard raw[i].range(of: "//") != nil else { continue }
                guard kept[i] == raw[i] else { continue }
                witnesses.append("\(path):\(i + 1)")
            }
        }
        XCTAssertFalse(witnesses.isEmpty, """
            No line under the scanned sources holds a `//` inside a string literal any more. \
            That is not a failure of the scanner — it means the EVIDENCE for "the shapes are \
            not interchangeable" is gone, and the failure message in \
            testEveryScanningGuardDelegates cites something that no longer exists. Either name \
            the new witness there, or say plainly that on today's tree the shapes agree and the \
            migration was prophylactic (#460 measured zero verdict flips either way — the point \
            is that the SENTENCE must not outlive its example).
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

    /// Reads a repo-relative source file.
    ///
    /// ⚠️ The skip gates on the DIRECTORY, never on the individual file (#475). A `fileExists`
    /// bracket around each read would turn the very catastrophe this guard stands against —
    /// a source that vanished — into a green skip. If `Sources/Echoelmusic` is reachable, a
    /// named file that is missing is a hard failure.
    private func readSource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("Source tree not reachable from the test bundle.")
        }
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("\(path) is gone — this guard names a source file that no longer exists.")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
