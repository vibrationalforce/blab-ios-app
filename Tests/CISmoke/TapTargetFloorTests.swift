// TapTargetFloorTests.swift
// Echoel — icon-only controls must be hittable, not merely visible.
//
// WHAT THIS GUARDS. Apple's HIG floor is a 44×44 pt tap target; WCAG 2.5.8 (AA) asks for
// 24×24. Echoel's chrome and panels are dense with icon-only buttons whose VISIBLE chip is
// deliberately smaller than either number — a 30×32 lock, a 14 pt glyph — and the house
// answer is to grow the HIT AREA without growing the picture, either by outsetting the
// content shape into a measured gap (`contentShape(Rectangle().inset(by: -6))`) or by
// giving the control a frame that matches its row.
//
// The defect this file exists for is not "a control is small". It is that the SAME row
// already contains the fix and one member was skipped: the transport bar's "•••" was
// outset by #113 and the playback ⏸ grown to 44×48 by #307's Nachlese, while the tempo
// LOCK between them stayed a bare 30×32 for months. A per-file review never catches that,
// because each file looks locally reasonable. A list does.
//
// ⚠️ WHY A SOURCE SCAN AND NOT A LAYOUT TEST — the same honest limit `ChromeDynamicTypeTests`
// states, repeated rather than cross-referenced because a reader arriving here must not have
// to trust another file's caveat. There is no simulator in this environment and the blocking
// bundle is `Tests/CISmoke`, so no SwiftUI hit-test can run. What CAN regress textually is
// someone deleting an outset while "tidying" modifiers, and that is exactly what this checks.
// A green here means the enlargement is still SPELLED, never that a finger lands on it.
//
// ⚠️ SECOND LIMIT: it scans SOURCE TEXT. If the checkout is not at the path this file was
// compiled from it SKIPS rather than passes — a silent pass on an unscanned tree is the
// `continue-on-error` lie the `doctor` skill exists to catch.
//
// ⛔ THIS FILE IS DELIBERATELY NOT A SWEEP. It does not try to find every `.frame(width:` under
// 44 pt in `Sources/` and fail on it. Such a check would fire on decorative glyphs, on labels
// inside a larger button, and on the many controls whose parent supplies the target — noise
// that gets a gate switched off, which is the failure mode this bundle cannot afford. It pins
// the specific controls a real audit found and a human judged. Add a case when an audit finds
// one; do not generalise it into a linter.

import Foundation
import XCTest

final class TapTargetFloorTests: XCTestCase {

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Comments are dropped because the
    /// fixes below QUOTE the sizes they replaced in their own prose, so a naive match would
    /// find the old spelling in the very block that explains the new one.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let tempoField = "Sources/Echoelmusic/Studio/BodyTempoField.swift"
    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The outset idiom, spelled exactly as both transport-bar controls spell it.
    private static let outset6 = "contentShape(Rectangle().inset(by: -6))"

    // MARK: - The transport bar

    /// The tempo lock and the "•••" overflow sit in one row, 12 pt apart, and must BOTH carry
    /// the outset. Checking them together is the point: the defect was one of them having it.
    ///
    /// This asserts the enlargement is spelled in each file. It cannot assert the resulting
    /// rectangle — see the header — so read a failure as "someone removed the outset", which
    /// is the only way this regresses textually.
    func testBothTransportBarChipsCarryTheHitAreaOutset() throws {
        let lock = try codeLines(Self.tempoField)
        XCTAssertTrue(lock.contains { $0.contains(Self.outset6) }, """
            BodyTempoField's lock button lost its `\(Self.outset6)`. The visible chip is \
            30×32 (compact), which is 47% of the HIG 44×44 floor by area — without the \
            outset the control that decides whether the tempo follows the body is the \
            smallest target in the always-visible chrome, and a missed tap lands on the \
            tempo value's scrub gesture instead. Its neighbour two controls over has \
            carried the identical modifier since #113.
            """)

        let bar = try codeLines(Self.workspace)
        XCTAssertTrue(bar.contains { $0.contains(Self.outset6) }, """
            The transport bar's "•••" overflow lost its `\(Self.outset6)` (#113). It is the \
            only door to Live Colabo and Learn, and it is a 30×32 chip.
            """)
    }

    /// The outset is only safe because the gaps it grows into are known. `BodyTempoField`'s own
    /// `HStack` spacing is the tighter of the two (6 pt in compact mode), so a −6 outset reaches
    /// exactly the value box's edge and no further. If someone tightens that spacing, the lock's
    /// hit area starts eating the value field's scrub area — silently, because both still work,
    /// just not where the user aims.
    ///
    /// ⛔ THIS IS THE ASSERTION I ALMOST WROTE AS `>= 6`, WHICH WOULD HAVE BEEN BACKWARDS.
    /// A LARGER spacing is harmless (more clearance); a SMALLER one is the overlap. The
    /// literal is pinned because the outset constant is pinned — they are one decision, and
    /// a test that allowed the gap to shrink would allow exactly the bug.
    func testTheCompactSpacingStillClearsTheOutset() throws {
        let lock = try codeLines(Self.tempoField)
        XCTAssertTrue(lock.contains { $0.contains("HStack(spacing: compact ? 6 : 10)") }, """
            BodyTempoField's row spacing changed. The lock's −6 outset was sized against a \
            6 pt compact gap: it reaches the value box's edge and stops. Narrow that gap and \
            the outset overlaps a control that is itself hit-testable when the tempo is \
            locked — taps meant for the lock would scrub the number instead. Re-measure the \
            outset in the same commit, or leave the spacing alone.
            """)
    }

    // MARK: - Panels

    /// The "clear manual place" ✕ was a bare 14 pt glyph with no frame at all — the smallest
    /// target the 2026-08-01 accessibility audit found, ~14×14 pt. It is fixed by GROWING the
    /// control to its row's height rather than by outsetting, because it abuts a `TextField`
    /// with no gap on its leading side and an outset would have stolen that field's taps.
    ///
    /// ⛔ THE ANCHOR IS THE ACTION, NOT THE GLYPH, and the first draft got that wrong in a way
    /// that would have passed while testing the wrong control. `xmark.circle.fill` appears
    /// TWICE in this file; the other is a "Close visual" button inside the
    /// `.fullScreenCover(isPresented: $showVisual)` overlay — which `showVisual` has no setter
    /// for, so it is unreachable and its size is nobody's problem. `firstIndex` found THAT one,
    /// six hundred lines earlier, and the assertion failed against a control this slice never
    /// touched. `locationNamer.manualPlace = ""` is unique and names the button by what it
    /// does, which is the property a glyph name does not have.
    func testTheClearPlaceButtonHasAFrameAndNotJustAGlyph() throws {
        let studio = try codeLines(Self.studio)
        let anchor = #"locationNamer.manualPlace = """#
        let hits = studio.indices.filter { studio[$0].contains(anchor) }
        guard let clear = hits.first else {
            throw XCTSkip("""
                the clear-place ✕ is gone from EchoelStudioView — if the manual-place field \
                was removed this test should be removed with it, not left to pass vacuously
                """)
        }
        XCTAssertEqual(hits.count, 1, """
            `\(anchor)` is no longer unique in EchoelStudioView, so the window below may be \
            scanning a different control than the one this test names. Re-anchor before \
            trusting the assertion that follows.
            """)
        // The frame follows the Image within a few lines; scan a small window rather than the
        // whole file so an unrelated 36×36 elsewhere cannot satisfy this.
        let windowEnd = min(clear + 6, studio.count)
        let window = studio[clear..<windowEnd]
        XCTAssertTrue(window.contains { $0.contains("frame(width: 36, height: 36)") }, """
            The clear-place ✕ lost its 36×36 frame and is a bare 14 pt glyph again — roughly \
            14×14 pt of target, about a fifteenth of the HIG 44×44 area. 36 is this row's own \
            height (`.frame(height: 36)` on the enclosing HStack), which is why it is 36 and \
            not 44: a taller control would outgrow the row that contains it.
            """)
    }
}
