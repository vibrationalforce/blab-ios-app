// TheTempoFieldCannotEatTheScreenTests.swift
// Echoel — #455. In LOOP mode the compact tempo box stood roughly a third of the screen tall,
// with the lock button and the pulse pill beside it at their normal 32 pt. Founder screenshot,
// v10.79.371 (2488), the box scribbled out.
//
// ⭐ THE MECHANISM WAS ALREADY WRITTEN DOWN — TWICE — BEFORE IT HAPPENED, and that is the
// interesting part of this slice.
//   · `EchoelValueField`: its scrub layer is a bare `Rectangle()`, which accepts ANY proposed
//     height, so the whole field is vertically GREEDY. Its own comment ends with "Do not remove
//     that without removing this greediness at the source."
//   · `WorkspaceView`: a `VStack` ranks children by flexibility, so a row hosting such a field
//     reports ∞ and starts SPLITTING free space with the instrument below it.
//
// ⛔ SO NOBODY IGNORED A COMMENT. The protection was a property of the BAR — `.fixedSize` +
// `.frame(minHeight: 44)` on `WorkspaceView`'s three chrome bars — and NOT of the control. #411
// moved `BodyTempoField` out of the transport bar into `EchoelStudioView.startControlRow` on a
// founder ask, and every word of that move's freeze-safety argument was correct. The LAYOUT half
// simply had no reason to travel with it. That is the #416 shape at its quietest: one decision,
// two owners, nothing that notices when they come apart.
//
// The fix therefore lives on the CONTROL, so the next bar it lands in inherits it, and this file
// pins that placement rather than the symptom.
//
// ⚠️ ONLY THE LOCKED BRANCH WAS EVER GREEDY — the following branches pin their own frames
// (compact `76×32`, wide: padded `Text`s). A Flow-mode screenshot would have shown nothing.
//
// ⚠️ WHAT THIS FILE CANNOT DO, said first. Every assertion is a SOURCE SCAN. SwiftUI layout is
// not reachable from a unit test here, so "the box is 35 pt and not 217" is a device look. What
// is proven is that the modifier is on the control, that the two premises the fix rests on are
// still true, and that the bars' own protection was not swept away as newly redundant.

import Foundation
import XCTest
@testable import Echoelmusic

/// Thrown when a scan anchor is gone. An uncaught error in a `throws` test method FAILS,
/// which is the point — `XCTSkip` would have been green (the #454 lesson).
private struct AnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

final class TheTempoFieldCannotEatTheScreenTests: XCTestCase {

    // MARK: - 1. the control carries its own non-greediness

    /// RED before #455: the modifier existed only on the three `WorkspaceView` bars, and the one
    /// live mount of this control is in neither of them.
    func testTheTempoFieldPinsItsOwnHeight() throws {
        let source = try source("Sources/Echoelmusic/Studio/BodyTempoField.swift")
        XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"), """
            `BodyTempoField` no longer pins its own height.

            Its locked branch is an `EchoelValueField`, whose scrub layer is a bare `Rectangle()` \
            and therefore accepts any proposed height. Without this modifier the row hosting it \
            reports infinite vertical flexibility and its parent `VStack` hands it a share of the \
            free space — the founder saw the tempo box roughly a third of the screen tall.

            If this was removed because the HOST bar carries the modifier again, put it back \
            anyway: that arrangement is exactly what broke when #411 moved the control between \
            bars.
            """)
    }

    // MARK: - 2. the two premises the fix rests on

    /// If the locked branch stops being an `EchoelValueField`, the greediness argument no longer
    /// applies to this control and the paragraph above needs re-deriving rather than trusting.
    func testTheLockedBranchIsStillTheGreedyControl() throws {
        let source = try source("Sources/Echoelmusic/Studio/BodyTempoField.swift")
        XCTAssertTrue(source.contains("EchoelValueField("), """
            `BodyTempoField` no longer constructs an `EchoelValueField`.

            That construction IS the greedy path — the reason the modifier in claim 1 exists. \
            A different control here means the whole rationale has to be re-derived.
            """)
    }

    /// The source of the greediness. Should the scrub layer ever stop accepting any proposed
    /// height, the modifier in claim 1 becomes decoration and this file should say so instead of
    /// quietly guarding nothing.
    func testTheScrubLayerIsStillTheBareGreedyRectangle() throws {
        let source = try source("Sources/Echoelmusic/Studio/EchoelValueField.swift")
        XCTAssertTrue(source.contains("Rectangle().fill(Color.clear).contentShape(Rectangle())"), """
            `EchoelValueField`'s bare scrub `Rectangle()` is gone or reshaped.

            Good news if it now has a bounded height — but then the `.fixedSize` in \
            `BodyTempoField` and the three in `WorkspaceView` are no longer load-bearing, and \
            four comments in this repo describing them as load-bearing have gone stale. Update \
            them in the same commit.
            """)
    }

    // MARK: - 3. the counterweight: the bars keep their own protection

    /// ⭐ THE ASSERTION THAT EARNS ITS PLACE GOING FORWARD.
    ///
    /// The obvious tidy-up after #455 is "the control protects itself now, so the bars need not".
    /// That would be wrong, and silently: `CompositionHeaderStrip` hosts the **A4 concert-pitch**
    /// `EchoelValueField` — a DIFFERENT greedy control, which `BodyTempoField` knows nothing
    /// about. Removing that bar's modifier re-opens the same split one strip higher, on the
    /// control whose accidental edits already cost this repo #391, #392 and #440.
    func testTheHeaderStripStillPinsItsOwnHeight() throws {
        let body = try structBody(named: "CompositionHeaderStrip",
                                  in: "Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(body.contains(".fixedSize(horizontal: false, vertical: true)"), """
            `CompositionHeaderStrip` lost its own height pin.

            It hosts the A4 concert-pitch `EchoelValueField`, which is greedy for the same reason \
            the tempo field was. #455 put the modifier on `BodyTempoField`; that helps this strip \
            not at all.

            Body scanned (comments blanked by SourceText.codeOnly):
            \(body)
            """)
    }

    // MARK: - 4. why the fix belongs on the control and not on the row

    /// The mount is OUTSIDE the protected bars — that is the whole reason claim 1 is placed where
    /// it is. Comments are blanked first, so the two prose mentions of `BodyTempoField(` (one in
    /// `WorkspaceView`'s account of #411, one in `EchoelStudioView`'s) cannot satisfy this.
    func testTheOnlyMountIsOutsideTheProtectedBars() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("BodyTempoField("), """
            `EchoelStudioView` no longer mounts `BodyTempoField`.

            If the control moved back into a `WorkspaceView` bar, claim 1 is no longer the ONLY \
            thing standing between Loop mode and a stretched row — but leave it there anyway and \
            rewrite this test, rather than deleting a modifier that costs nothing.
            """)
    }

    // MARK: - source access

    /// Comment-stripped source, or a skip when the tree is not present.
    ///
    /// `SourceText.codeOnly` (#453) is kept as a PROPHYLACTIC here, and the honest measurement
    /// says so.
    ///
    /// ⛔ THIS PARAGRAPH CLAIMED "three of the five assertions here would pass on the
    /// explanation instead of the code" — an unmeasured "load-bearing" claim, which is the same
    /// defect this file family has retracted numbers for three times. Measured at `d8bf125`,
    /// every needle of both this file's five claims and the #456 guard's, raw text vs stripped:
    /// **one of ten outcomes differs**, and it is a false RED it prevents, not a false green —
    /// `EchoelStudioView` quotes `transport.position` in a doc comment, so #456's claim 4b
    /// ("the studio must NOT read it") would fail on prose without stripping. None of this
    /// file's own five change either way.
    ///
    /// The helper stays: this repo writes comments that quote the code they explain, so the
    /// next needle may well need it. But "prophylactic" is what it is today.
    ///
    /// ⛔ AND A LINE-NUMBER PAIR STOOD HERE ("line 754 vs 759", called "one line above"): five
    /// lines apart, not one — and #456, the very next commit, moved both. CLAUDE.md strikes
    /// this pattern by name: a quoted phrase survives an insertion, a line number does not.
    /// The real one now lives in the note above `topBar`'s frame in `WorkspaceView`.
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        // ⛔ THE SKIP IS SCOPED TO THE TREE, NOT THE FILE. The first version skipped whenever
        // the FILE was missing, so renaming or moving any scanned file turned every claim in
        // this file green at once — the #454 lesson (a skip PASSES CI) one level out.
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body of a `struct <name>: View {` declaration.
    ///
    /// Brace-matched rather than "from the declaration to the next `struct`": `WorkspaceView.swift`
    /// holds five occurrences of the modifier across four types, so a scan that only found the
    /// declaration and searched forward would happily read a NEIGHBOUR's pin as this one's.
    private func structBody(named name: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let key = "struct \(name): View {"
        // ⛔ THIS THREW `XCTSkip` ON ARRIVAL, and `ControlBoundaryIsInteractiveTests` already
        // spelled out why that is wrong: "A source-text guard may skip when the TREE is absent;
        // it must never skip because the THING IT GUARDS moved." Renaming the type would have
        // turned the counterweight — the claim this file calls the one that earns its place
        // going forward — silently green forever. `TheTransportBarIsDissolvedTests`, written an
        // hour later, got this right; this one did not, in the same session.
        guard let start = text.range(of: key) else {
            throw AnchorMissing(reason: """
                `\(key)` not found in \(relativePath) — renamed, reflowed or removed. \
                Re-anchor this scan; do not leave it silent.
                """)
        }
        // `start.upperBound` sits just past the opening brace, so the depth starts at 1.
        var depth = 1
        var body = ""
        var i = start.upperBound
        while i < text.endIndex, depth > 0 {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            body.append(c)
            i = text.index(after: i)
        }
        XCTAssertEqual(depth, 0, "unbalanced braces while extracting `\(name)` — scan is unsound")
        return body
    }
}
