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
// already contains the fix and one member was skipped: the "•••" was outset by #113 and
// the playback ⏸ grown to 44×48 by #307's Nachlese, while the tempo LOCK between them
// stayed a bare 30×32 for months. A per-file review never catches that, because each file
// looks locally reasonable. A list does.
//
// ⛔ "the transport bar's '•••'" and "between them" WERE TRUE UNTIL #456. The bar dissolved;
// the "•••" now sits on line 2 of `EchoelStudioView.startControlRow` and the lock on line 1,
// so they are no longer one row and no longer flank anything. The assertions below are
// unaffected — they scan for the outset repo-file-wide, not for an adjacency — but a reader
// who trusts this paragraph would go looking for a row that does not exist. The LESSON is
// what survives: a list of controls beats a per-file review.
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

    // MARK: - The two preset overflow menus (#358)

    /// The Mood and Sound preset bars each end in an `ellipsis.circle` Menu drawn at 34×34 —
    /// 60 % of the HIG 44×44 floor by area — and each is the ONLY door to save / favorite /
    /// delete / submit for its library. They get the transport bar's outset, not a bigger
    /// frame: `contentShape` changes no layout, so the chip still reads as a peer of the
    /// 34-high preset menu beside it in the same row.
    ///
    /// ⛔ POSITION, NOT PRESENCE — AND THE FIRST DRAFT CHECKED PRESENCE, WHICH IS EXACTLY THE
    /// DEFECT IT THEN FAILED TO CATCH. It scanned a five-line window above the
    /// `accessibilityLabel`, so it was equally green with the modifier INSIDE the `Menu`'s
    /// `label:` closure — where it is almost certainly a no-op, because a `Menu` installs its
    /// press interaction over its OWN bounds and `contentShape` cannot change those from a
    /// descendant. The commit that added these two shipped the wrong level and asserted the
    /// effect as fact; a reviewer found it, this guard could not. So it now pins the exact two
    /// lines: the outset must be the first CODE line above the `accessibilityLabel`, and a
    /// closing brace immediately above that.
    ///
    /// The five-line window is gone with it: a window is the right shape for "is it still
    /// spelled", the wrong shape for "is it in the right place".
    ///
    /// ⛔ THE PRECEDENT IS ONE, NOT TWO — the #358 commit message and an earlier version of this
    /// note both cited `WorkspaceView`'s "•••" (#113) AND `BodyTempoField`'s lock as corroboration.
    /// `BodyTempoField`'s lock is a **`Button`**, and for a `Button` the label's content shape IS
    /// the tap area, so inside-vs-outside is a materially different question there and it says
    /// nothing about a `Menu`. One precedent, and #113 carries no recorded device verification
    /// either — which is why the placement fix says "device-verify" rather than "proven".
    ///
    /// ⚠️ WHAT THIS STILL CANNOT SEE: nothing ties the closing brace below to the `Menu`'s
    /// `label:` closure specifically. A refactor that put the outset and the label on an
    /// enclosing `HStack` AFTER the Menu closed would pass both assertions while outsetting the
    /// whole row. Named rather than papered over — closing it needs a brace-matching parser,
    /// which is more machinery than this bundle should carry.
    func testBothPresetOverflowMenusCarryTheHitAreaOutset() throws {
        let studio = try codeLines(Self.studio)

        /// The nearest non-blank line at or above `i`. `codeLines` drops whole-line comments but
        /// NOT blank lines, so a naive `idx - 1` reddens the only blocking gate for a stray empty
        /// line between the brace and the modifier — a whitespace-only edit failing a placement
        /// test is exactly how a guard gets switched off. Same class as the comment trap that
        /// `ScrubNotifiesOnlyOnRealChangeTests` documents; this one was found by review, not by CI.
        func codeIndex(above i: Int) -> Int? {
            var j = i - 1
            while j >= 0, studio[j].trimmingCharacters(in: .whitespaces).isEmpty { j -= 1 }
            return j >= 0 ? j : nil
        }

        for label in ["Mood actions", "Sound actions"] {
            let anchor = "accessibilityLabel(\"\(label)\")"
            let hits = studio.indices.filter { studio[$0].contains(anchor) }
            XCTAssertEqual(hits.count, 1, """
                `\(anchor)` is not unique in EchoelStudioView, so the lines below cannot be \
                trusted to describe the control this test names. Re-anchor before reading the \
                assertions that follow as a pass or a fail.
                """)
            guard let idx = hits.first,
                  let outsetIdx = codeIndex(above: idx),
                  let braceIdx = codeIndex(above: outsetIdx)
            else { continue }
            XCTAssertTrue(studio[outsetIdx].contains(Self.outset6), """
                The "\(label)" overflow menu lost its `\(Self.outset6)`, or it moved away from \
                the line directly above the accessibility label. Its visible chip is 34×34, \
                which is 60 % of the HIG 44×44 floor by area, and it is the only door to save / \
                favorite / delete / submit in that library — a missed tap there lands on the \
                preset menu next to it and CHANGES the preset instead.
                """)
            XCTAssertTrue(studio[braceIdx].trimmingCharacters(in: .whitespaces) == "}", """
                The "\(label)" outset is no longer the first modifier after the Menu's `label:` \
                closure. If it slid back INSIDE that closure it is a no-op: `contentShape` on a \
                descendant does not widen what the Menu presents from, which is why #113 closes \
                the label before outsetting.
                """)
        }
    }

    /// The outset is a claim about a GAP, and both gaps live in other lines. This pins them.
    ///
    /// ⛔ THE TWO ROWS ARE NOT THE SAME MEASUREMENT, and conflating them would have produced a
    /// real overlap. The Mood row puts a `Spacer` between the preset menu and the overflow, so
    /// `HStack(spacing: 8)` applies on BOTH sides of it — ≥16 pt of clearance. The Sound row has
    /// the two chips adjacent (the preset menu carries `maxWidth: .infinity`), so the gap is
    /// exactly 8 pt and −6 leaves 2. That is why only the ellipsis is outset in the Sound row:
    /// giving the preset menu the same modifier would overlap the two hit areas by 4 pt, and
    /// the overlapping half contains Delete.
    ///
    /// Vertically both rows sit in `EchoelPanel`'s content stack, whose 14 pt row spacing is the
    /// clearance below. That is why this test reads a second file.
    ///
    /// ⛔ EVERY LITERAL BELOW IS WINDOWED, AND THE FIRST DRAFT OF TWO OF THEM WAS NOT.
    /// `labeledRow("Character")` occurs TWICE in this file and `Spacer(minLength: 0)` FIVE
    /// times; a `firstIndex`/file-wide `contains` on either would have passed while the row
    /// this test names had lost the very thing being asserted — the same "assertion that
    /// cannot fail for its own name" trap #376 paid for. Each anchor here is a declaration
    /// that occurs once, and each literal is looked for between that declaration and the
    /// control it belongs to.
    func testThePresetRowGapsStillClearTheOutset() throws {
        let studio = try codeLines(Self.studio)

        /// Index range from a unique row declaration to that row's overflow-menu label.
        func rowRange(_ declaration: String, _ endAnchor: String) -> Range<Int>? {
            guard let start = studio.firstIndex(where: { $0.contains(declaration) }),
                  let end = studio[start...].firstIndex(where: { $0.contains(endAnchor) })
            else { return nil }
            return start..<end
        }

        let rows = [("private var moodPresetBar: some View {", "Mood actions", "Mood"),
                    ("private var presetRow: some View {", "Sound actions", "Sound")]
        for (declaration, endAnchor, row) in rows {
            guard let range = rowRange(declaration, endAnchor) else {
                XCTFail("""
                    the \(row) preset bar no longer spans `\(declaration)` → `\(endAnchor)`. If \
                    the row was renamed, re-anchor this test in the same commit; if it was \
                    removed, remove its outset assertion above with it rather than leaving it \
                    to pass vacuously.
                    """)
                continue
            }
            XCTAssertTrue(studio[range].contains { $0.contains("HStack(spacing: 8)") }, """
                The \(row) preset row's stack spacing changed. Both overflow menus' −6 outsets \
                were sized against an 8 pt gap. In the Sound row that gap is the whole clearance \
                (the two chips are adjacent), so narrowing it makes the overflow's hit area \
                overlap the preset menu — taps meant for Delete would open the preset list, and \
                taps meant for the preset list would land on a destructive menu. Re-measure the \
                outset in the same commit, or leave the spacing alone.
                """)

            if row == "Mood" {
                XCTAssertTrue(studio[range].contains { $0.contains("Spacer(minLength: 0)") }, """
                    The Mood preset row's `Spacer(minLength: 0)` is gone. It is what makes that \
                    row's clearance ≥16 pt rather than the Sound row's 8 — `HStack` spacing \
                    applies on both sides of a Spacer. Without it the two rows have the same \
                    tight gap, which is still safe for a −6 outset but no longer for anything \
                    larger.
                    """)
            }
        }

        // ⛔ THE VERTICAL HALF OF THIS MEASUREMENT IS PINNED ELSEWHERE, ON PURPOSE. `EchoelPanel`'s
        // two content stacks (force-open branch + DisclosureGroup branch) and their 14 pt row
        // spacing are what makes −6 safe vertically (−6 into 14 leaves 8). An assertion for that
        // stood HERE for one commit, and it was a duplicate: `SoundPanelReflowsTests` already
        // pins the same fact with a stricter needle, for its own unrelated reason (panel rhythm).
        // Removed rather than kept in sync, because the sibling guard this file's own batch edited
        // says it in one line — "a fact pinned twice in one bundle is a fact that gets
        // half-updated once" — and I had just written the second pin.
        //
        // If that spacing ever changes, `SoundPanelReflowsTests` goes red and BOTH outsets need
        // re-measuring; this comment is the pointer from here to there.
    }

    // MARK: - The Master panel's loudness Reset (#394)

    /// ⛔ THE SMALLEST TARGET IN A REACHABLE PANEL, AND IT FAILED BOTH FLOORS. Until #394 this
    /// was `Button("Reset") { audioEngine.resetMastering() }` with `.font(EchoelTheme.font(12))`
    /// and no frame at all — a hit area the size of the word, roughly 35 × 15 pt. That is under
    /// the HIG 44×44 AND under WCAG 2.5.8 (AA)'s 24×24, which the two preset menus above (34×34,
    /// outset) never were. It sits hard against the panel's right edge behind a `Spacer`, so a
    /// thumb that lands ten points low hits nothing at all.
    ///
    /// ⭐ WHY A FRAME AND NOT THE OUTSET IDIOM the rest of this file uses. `contentShape` alone
    /// would give ~47 × 27 pt — over WCAG, still well under HIG — because the deficit here is
    /// height, not a missing few points. And the row has the room: the sentence beside it wraps
    /// and is already taller than 44 in most widths, so `minHeight` costs no layout on a phone
    /// and only asserts the floor in the wide/short-text case where the row would otherwise
    /// collapse to the label's own height.
    ///
    /// ⚠️ THE FRAME IS ON THE LABEL, AND THE ASSERTION SAYS SO. For a title `Button` the label's
    /// bounds are what gets hit-tested, so an outer `.frame` grows the picture and not the
    /// target — the same inside-vs-outside distinction the preset-menu test above had to learn
    /// the hard way, mirrored. This windows from the action to its `accessibilityHint` so a
    /// `minHeight: 44` on some other control cannot satisfy it.
    ///
    /// ⚠️ `minHeight`, never `height`: a fixed one clips the label at large Dynamic Type sizes
    /// (the #353 class). Both halves are asserted, because fixing one and losing the other is
    /// how this control ends up back where it started with a different defect.
    func testTheLoudnessResetClearsTheTapTargetFloor() throws {
        let studio = try codeLines(Self.studio)
        let anchor = "audioEngine.resetMastering()"
        let hits = studio.indices.filter { studio[$0].contains(anchor) }
        XCTAssertEqual(hits.count, 1, """
            `\(anchor)` is no longer unique in EchoelStudioView, so the window below may be \
            describing a different control than the one this test names. Re-anchor before \
            reading the assertions that follow as a pass or a fail.
            """)
        guard let start = hits.first else { return }
        guard let end = studio[start...].firstIndex(where: {
            $0.contains("Clear the integrated loudness and peak hold")
        }) else {
            return XCTFail("""
                the loudness Reset lost its accessibility hint, so this test cannot say where \
                the control ends. Re-point the window at whatever closes it — do not widen it \
                to the file, which is how a guard starts passing on a neighbour's modifiers.
                """)
        }
        let control = studio[start...end]
        XCTAssertTrue(control.contains(where: { $0.contains("frame(minHeight: 44)") }), """
            the Master panel's loudness Reset lost its `frame(minHeight: 44)` (#394).

            Without it the control is a bare title button: ~35 × 15 pt, under the HIG 44×44 \
            floor and under WCAG 2.5.8's 24×24. It is the only way to clear the integrated \
            loudness and the peak hold, and it sits at the panel's right edge behind a Spacer.
            control: \(Array(control).map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        XCTAssertTrue(control.contains(where: { $0.contains("contentShape(Rectangle())") }), """
            the loudness Reset's `contentShape(Rectangle())` is gone. The frame above then \
            grows the LAYOUT without growing what is hit-tested — the label's glyph run stays \
            the target and the fix becomes decoration, which is exactly the inside-vs-outside \
            mistake the preset-menu guard in this file documents.
            """)
        XCTAssertFalse(control.contains(where: { $0.contains("frame(height: 44)") }), """
            the loudness Reset's frame is FIXED again. A fixed height clips the label once the \
            player raises the text size (the #353 class); the floor has to be a minimum.
            """)
    }
}
