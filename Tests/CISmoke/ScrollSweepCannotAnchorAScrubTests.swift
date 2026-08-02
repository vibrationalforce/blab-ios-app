// ScrollSweepCannotAnchorAScrubTests.swift
// Echoel — the other half of #391: a sideways sweep must not anchor a scrub. BLOCKING. #392.
//
// THE RESIDUAL #391 LEFT, IN ITS OWN WORDS. That fix zeroed the x contribution for a field that
// opts out of the sideways axis, and its doc said plainly what it did not do: "this zeroes the x
// contribution, it does not make the field ignore a dominantly-horizontal gesture. A sideways
// flick that carries vertical jitter can still nudge the number … the next step is an axis
// DOMINANCE test, not a bigger dead zone." This is that step.
//
// ⛔ WHY THE RESIDUAL IS NOT COSMETIC ON THIS ONE FIELD. A thumb sweeping the header chip strip
// wanders several points vertically. Over `fullRangePoints` on the A4 field's 380…500 Hz range
// that is still a handful of Hz per sweep — and A4 is the global tuning reference: `onCommit`
// posts "a4", which retunes every voice and recomposes the running take, and the value is
// persisted, so the drift accumulates across sweeps and survives relaunch. Small and permanent
// is worse here than large and obvious; 500,0000 Hz gets noticed, 443 Hz does not.
//
// ⭐ TWO MECHANISMS, AND THIS FILE EXISTS BECAUSE EITHER ONE ALONE IS INSUFFICIENT. The `dxStep`
// gate (#391, guarded by `ConcertPitchDoesNotRideTheScrollTests`) and the decline (#392, guarded
// here) protect the same value from the same gesture by different means. They are asserted
// together in `testBothMechanismsAreStillPresent` so that removing one cannot read as a
// simplification.
//
// ⚠️ WHY A SOURCE SCAN. The behaviour is a `DragGesture` arbitrating against a parent
// `ScrollView` on a `@MainActor` view; there is no local toolchain and no simulator. House
// pattern. It proves the decline is WRITTEN and where; it cannot sweep a finger.
//
// NEEDS-FOUNDER-VERIFY: sweep the header strip sideways with the finger crossing the A4 box —
// the number must not move at all, not even slightly. A deliberate UP/DOWN drag on the box must
// still adjust it, and a tap must still open the keypad.

import Foundation
import XCTest

final class ScrollSweepCannotAnchorAScrubTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/EchoelValueField.swift"

    /// ⭐ POSITIONAL, because position IS the invariant. "The gesture mentions `horizontalScrub`
    /// somewhere" is already true of #391 alone. The decline has to sit INSIDE the anchor branch
    /// and BEFORE `scrubbing = true` — after that line it would be decoration on a gesture that
    /// has already latched, taken its anchor and begun accruing a target.
    func testTheDeclineSitsBeforeTheAnchorLatches() throws {
        let body = try memberBody(startingWith: "private var scrubGesture: some Gesture",
                                  in: Self.field)
        guard let branch = body.firstIndex(where: { $0.contains("if !scrubbing {") }) else {
            return XCTFail("""
                the anchor branch is gone from `scrubGesture` — `if !scrubbing {` no longer \
                appears. Every latch this file and #375/#376/#377/#378 reason about is seeded \
                there, so move those guards with it rather than deleting this one.
                """)
        }
        guard let latch = body[(branch + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "scrubbing = true"
        }) else {
            return XCTFail("""
                the anchor branch no longer latches with a bare `scrubbing = true`, so this \
                guard cannot say where "before the latch" is. Re-point it at whatever took \
                that line's place — do not drop the positional check for a `contains`.
                """)
        }
        let beforeLatch = body[(branch + 1)..<latch]
        XCTAssertTrue(beforeLatch.contains(where: { $0.contains("if !horizontalScrub,") }), """
            the anchor branch no longer declines a dominantly-sideways gesture (#392).

            Without it a field that opted out of the x axis still reads the vertical jitter of \
            a scroll sweep. On the A4 field that is a few Hz of tuning drift per sweep, \
            committed, persisted and accumulating — the quiet half of the defect the founder \
            saw as 440 → 500 Hz.
            anchor branch: \(Array(beforeLatch).map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        XCTAssertTrue(beforeLatch.contains(where: {
            $0.contains("abs(g.translation.width) > abs(g.translation.height)")
        }), """
            the decline is no longer an axis-DOMINANCE test. #391's doc rejected the \
            alternative by name: a bigger dead zone taxes the deliberate drag too. If the \
            comparison genuinely had to change, say so where the doc makes the claim as well.
            """)
    }

    /// ⛔ THE DECLINE MUST TEAR UP THE CANCELLATION RECEIPT, and this is the assertion that would
    /// have caught a silent regression rather than a missing feature. `onEnded` DOES fire for a
    /// declined drag, and a decline leaves `gestureSeq` untouched — so a receipt left by the
    /// PREVIOUS gesture's cancellation still satisfies `r.seq == gestureSeq`, and `onEnded` would
    /// undo that revert and re-apply the value #378 took back. For an anchored drag the `&+= 1`
    /// is what makes a stale receipt unreadable; a decline has to say it outright.
    func testTheDeclineDropsTheCancellationReceipt() throws {
        let body = try memberBody(startingWith: "private var scrubGesture: some Gesture",
                                  in: Self.field)
        guard let decline = body.firstIndex(where: { $0.contains("if !horizontalScrub,") }) else {
            return XCTFail("the decline is gone — see the previous test, which says why.")
        }
        guard let ret = body[(decline + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "return"
        }) else {
            return XCTFail("""
                the decline no longer returns, so it is not a decline. Whatever it does now, \
                it runs on into the latch and the field anchors on a scroll sweep anyway.
                """)
        }
        XCTAssertTrue(body[(decline + 1)...ret].contains(where: {
            $0.trimmingCharacters(in: .whitespaces) == "revertedGesture = nil"
        }), """
            the decline no longer drops `revertedGesture` before returning (#392).

            That is not hygiene. `onEnded` fires for a declined drag and `gestureSeq` did not \
            move, so a receipt from a previous cancellation still matches and `onEnded` \
            RESTORES the value #378's revert removed — the #360 defect, re-entered from the \
            other side and only on the field that opted out of the sideways axis.
            decline: \(Array(body[decline...ret]).map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    /// ⛔ BOTH HALVES OR NEITHER. The `dxStep` gate and the decline defend the same value from
    /// the same gesture by different means, and the flag's doc now says so in capitals. Removing
    /// one would look like a simplification — this is the line that makes it look like a
    /// regression instead. (The `dxStep` half also has its own guard next door in
    /// `ConcertPitchDoesNotRideTheScrollTests`; the duplication is the point.)
    func testBothMechanismsAreStillPresent() throws {
        let code = try codeLines(Self.field)
        let gated = code.filter { $0.contains("let dxStep") }
        XCTAssertEqual(gated.count, 1, """
            expected exactly one `dxStep` binding, found \(gated.count):
            \(gated.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        XCTAssertTrue(gated[0].contains("horizontalScrub ?"), """
            the sideways delta is no longer gated on `horizontalScrub` (#391), so the decline \
            added by #392 is now the ONLY thing between the header scroll and the tuning \
            reference — and it deliberately does not cover a gesture that starts vertical and \
            travels sideways:
            \(gated[0].trimmingCharacters(in: .whitespaces))
            """)
        XCTAssertTrue(code.contains(where: { $0.contains("var horizontalScrub: Bool = true") }), """
            `EchoelValueField.horizontalScrub` is gone. Both mechanisms hang off it, and so \
            does the A4 call site in WorkspaceView — move all four in one commit or none.
            """)
    }

    // MARK: - Source helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here more than usual: the
    /// decline carries a long ⛔ block that quotes `revertedGesture`, `gestureSeq` and
    /// `horizontalScrub` verbatim while explaining them, and a scan that read prose would find
    /// every needle in the explanation of the code rather than in the code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
