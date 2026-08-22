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
// so they are no longer one row and no longer flank anything. ⛔ AND THE SENTENCE THAT
// FOLLOWED — "the assertions below are unaffected, they scan for the outset repo-file-wide" —
// stopped being true one commit later: #482 re-pointed the first assertion at a TYPE NAME in
// `WorkspaceView`, because the "•••" reaches 44 through `EchoelIconTile`'s frame now and has
// no outset to scan for. A reader who trusts either paragraph goes looking for a row that
// does not exist, or for a repo-wide scan that is now file-and-symbol specific. The LESSON is
// what survives both: a list of controls beats a per-file review.
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
    /// #644 moved the narration disclosure out of `EchoelStudioView` into its own leaf, so its
    /// heading could name the driver the paragraph beneath it already names. The geometry moved
    /// with it, byte for byte — this scan follows it (§4).
    private static let narration = "Sources/Echoelmusic/Studio/LiveNarrationDisclosure.swift"

    /// The outset idiom, spelled exactly as both transport-bar controls spell it.
    private static let outset6 = "contentShape(Rectangle().inset(by: -6))"

    // MARK: - The transport bar

    /// The tempo lock and the two global-door tiles reach the 44 pt floor by two DIFFERENT
    /// means since #482. Checking them together is still the point: the original defect was
    /// one of them lacking a floor while looking identical to the other.
    ///
    /// ⛔ THE PAIR'S SECOND HALF USED TO BE THE "•••" OVERFLOW, ONE CONTROL IN
    /// `WorkspaceView`. #492 dissolved that menu on a founder ask; its two entries are
    /// separate tiles in `EchoelStudioView.quickDoorRow` now, so the half is two needles in a
    /// different file. Same property, same reason, more call sites to lose it from.
    ///
    /// This asserts the enlargement is spelled in each file. It cannot assert the resulting
    /// rectangle — see the header — so read a failure as "someone removed the floor", which
    /// is the only way this regresses textually.
    ///
    /// ⛔ RENAMED FROM `testBothTransportBarChipsCarryTheHitAreaOutset` (#482) — there is only
    /// ONE outset in this pair now, and a name promising "both" would send its reader looking
    /// for a modifier that was deliberately removed. `TransportOverflowMenu`'s "•••" reaches
    /// the 44 pt floor through `EchoelIconTile`'s layout frame instead.
    ///
    /// ⛔ AND THE REASON GIVEN FOR THAT SWAP WAS WRONG, IN THE DIRECTION THAT COSTS MOST. It
    /// read: "this file's own header records that a `contentShape` inside a `Menu`'s `label:`
    /// closure is almost certainly a no-op". Two errors. (a) The no-op claim lives in
    /// `testBothPresetOverflowMenusCarryTheHitAreaOutset`'s doc below, not in the header.
    /// (b) The removed modifier was NOT inside the label closure — `git show 39f112b` puts it
    /// after the closing brace, on the `Menu` itself, which is precisely the placement that
    /// same test certifies as CORRECT for the two preset overflows. It worked; the chip was
    /// 42 × 44. Left standing, the sentence was a ready-made argument for deleting those two
    /// pinned outsets. The HONEST reason for the frame: it is bigger (42 → 44 wide) and it
    /// survives repetition — six −6 outsets at 8 pt spacing overlap by 4 pt, which is exactly
    /// the geometry `quickActionRow` now has.
    ///
    /// The tempo lock keeps the outset, and its arithmetic is unchanged: 32 + 6 + 6 = 44,
    /// pinned from the other side by `OneChromeControlHeightTests`.
    func testTheTempoLockKeepsTheOutsetAndTheDoorsGotAFrame() throws {
        // ⛔ THIS READ `Self.workspace` FOR ONE `EchoelIconTile(systemImage: "ellipsis"` UNTIL
        // #492, AND THAT NEEDLE IS GONE WITH ITS CONTROL, not weakened. The founder asked for
        // the "•••" entries as individual buttons; the menu is deleted and its two doors are
        // tiles in `EchoelStudioView.quickDoorRow`. The PROPERTY being defended is unchanged
        // and is now checked where it lives: the only doors to Live Colabo and Learn must be
        // built from the shared tile, which is what holds them to the 44 pt floor (#113).
        // Retargeting rather than deleting is the #456 rule — a commit that removes a surface
        // moves the guards over that surface in the same breath.
        let studio = try codeLines(Self.studio)
        // Anchored on the glyph argument only, NOT the full call: the call sites also pass
        // `expands: true` so every tile in the row is one width, and a whole-call needle would
        // go red on an unrelated width change.
        for door in ["dot.radiowaves.left.and.right", "book"] {
            XCTAssertTrue(studio.contains { $0.contains("EchoelIconTile(systemImage: \"\(door)\"") }, """
                The `\(door)` door tile no longer builds `EchoelIconTile`. That type's layout \
                frame is the ONLY thing holding these two controls to the 44 pt floor — the \
                `contentShape(Rectangle().inset(by: -6))` the old "•••" carried went with #482 \
                and was never re-added. A bare `Image` under `.buttonStyle(.plain)` hit-tests \
                its glyph run (~15–17 pt), which is under WCAG 2.5.8's 24 pt, let alone HIG's \
                44. Restore the tile, or add an outset in the same commit; do not leave neither.
                """)
        }

        let lock = try codeLines(Self.tempoField)
        XCTAssertTrue(lock.contains { $0.contains(Self.outset6) }, """
            BodyTempoField's lock button lost its `\(Self.outset6)`. The visible chip is \
            30×32 (compact), which is 47% of the HIG 44×44 floor by area — without the \
            outset the control that decides whether the tempo follows the body is the \
            smallest target in the always-visible chrome, and a missed tap lands on the \
            tempo value's scrub gesture instead. ⛔ The neighbour this message used to cite \
            as precedent — the "•••", "carrying the identical modifier since #113" — no \
            longer does: #482 gave it `EchoelIconTile`'s 44 pt frame instead. ⛔ And the \
            sentence that followed THAT, "the lock is now the ONLY outset in the chrome", was \
            false in the same breath: `git grep "inset(by: -6)" -- Sources` on code lines \
            finds FOUR — this lock, `BioStripView`, and the two preset overflows pinned by \
            `testBothPresetOverflowMenusCarryTheHitAreaOutset` in this same file. The idiom is \
            alive and corroborated; keep this assertion because the lock is the smallest \
            always-visible target, not because it stands alone.
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
    /// `.fullScreenCover(isPresented: $showVisual)` overlay. ⚠️ That overlay was unreachable
    /// when this note was written, and #747 doored it — so "its size is nobody's problem" is no
    /// longer true, and its tap targets are a real open question (recorded in
    /// `VisualFineTuneReflowsTests`' device-verify note, not re-asserted here). The needle
    /// lesson is untouched by that. `firstIndex` found THAT one,
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

    // MARK: - the video-library row trio (#617, audit case A11y#3)

    /// GRADING (#433): all three sub-checks are FORWARD guards — #617 creates the fixes they
    /// pin, so none could have been red before it. On the parent tree each is red for its
    /// named reason (the fix is absent at an anchor that exists there); the counterweights
    /// (spacing 10, the play chip's 32×32, the card padding) are green on both trees.
    /// Stripper: MEASURED PROPHYLAKTISCH (0 verdicts flip raw vs stripped on either tree).
    /// One needle COUNT differs since #617b — the source comment above Share/Delete quotes
    /// `contentShape(Rectangle())` verbatim (raw 3 vs stripped 2 in that file) — but the
    /// quoting comment sits ABOVE the Share anchor, outside every window this case scans,
    /// so no verdict depends on the stripping. Measured, not assumed (the §2 discipline).
    ///
    /// Two DIFFERENT fixes in one row, on purpose, and the reasons are the row's geometry:
    /// the play button keeps its bordered 32-chip look and gets the outset (its neighbours
    /// are the card's own padding and non-interactive text), while Share and Delete are
    /// ADJACENT at 10 pt — two −6 outsets across that gap overlap by 2 pt with Delete in
    /// the overlapping strip (the Sound-row lesson above), so they get 44 pt frames instead:
    /// bare glyphs, the frame grows only whitespace.
    func testTheVideoLibraryRowButtonsClearTheFloor() throws {
        let path = "Sources/Echoelmusic/Studio/VideoLibraryPanel.swift"
        let lines = try codeLines(path)

        /// Window from a unique action anchor to that control's accessibility label.
        func window(_ anchor: String, _ end: String) throws -> ArraySlice<String> {
            let hits = lines.indices.filter { lines[$0].contains(anchor) }
            XCTAssertEqual(hits.count, 1, """
                `\(anchor)` is no longer unique in VideoLibraryPanel, so the window below \
                may describe a different control. Re-anchor before trusting what follows.
                """)
            guard let start = hits.first,
                  let stop = lines[start...].firstIndex(where: { $0.contains(end) })
            else { throw XCTSkip("the \(anchor) control is gone — remove this case with it") }
            return lines[start...stop]
        }

        let play = try window("togglePlay(clip)", "accessibilityLabel(playingURL")
        XCTAssertTrue(play.contains { $0.contains(Self.outset6) }, """
            the video-library play/stop button lost its `\(Self.outset6)` (#617). Its \
            bordered chip is 32×32 — 53 % of the HIG 44×44 floor by area — and without \
            the outset a missed tap on "Stop" lands on nothing while a take is sounding.
            """)
        XCTAssertTrue(play.contains { $0.contains("frame(width: 32, height: 32)") }, """
            the play button's 32×32 chip frame changed. The −6 outset was sized as \
            32 + 6 + 6 = 44 — re-measure the outset in the same commit, or restore the chip.
            """)

        for (anchor, end, name) in
            [("Button { onShare(clip.url) } label: {", "accessibilityLabel(\"Share", "Share"),
             ("Button(role: .destructive) { delete(clip) } label: {", "accessibilityLabel(\"Delete", "Delete")] {
            let control = try window(anchor, end)
            XCTAssertTrue(control.contains { $0.contains("frame(width: 44, height: 44)") }, """
                the video-library \(name) button lost its 44×44 frame (#617) — a bare \
                13 pt glyph again, roughly an eighth of the HIG floor by area, in a list \
                where \(name == "Delete" ? "it destroys a recording" : "it is the only export door").
                """)
            // ⛔ #617b — THE FIRST VERSION OF THIS CASE DID NOT ASK FOR THIS LINE, and the
            // fix it certified was decoration: under `.buttonStyle(.plain)` the hit test
            // follows the label's glyph run (#485, measured on device), so the 44-frame
            // alone grew layout and not the target. The review caught it; the exact
            // omission #486 documents re-committing one commit after #485 fixed it.
            XCTAssertTrue(control.contains { $0.contains("contentShape(Rectangle())") }, """
                the \(name) button's `contentShape(Rectangle())` is gone (#617b). Without \
                it the 44×44 frame grows layout while the hit target stays the ~13 pt \
                glyph run — the loudness-Reset lesson in this file, third occurrence.
                """)
            XCTAssertFalse(control.contains { $0.contains("inset(by:") }, """
                the \(name) button acquired an outset. Share and Delete are adjacent at \
                the row's 10 pt spacing: two −6 outsets overlap by 2 pt and the strip \
                contains Delete — that is the exact defect the Sound-row case in this \
                file documents. Grow the frame (with `contentShape(Rectangle())`), never \
                outset this pair.
                """)
        }

        // The geometry both fixes were measured against — WINDOWED into `clipRow` (#617b:
        // the first version scanned file-wide, which stays green if the row's spacing
        // changes while another spacing-10 stack appears elsewhere in the file).
        let row = try window("private func clipRow(", "accessibilityLabel(playingURL")
        XCTAssertTrue(row.contains { $0.contains("HStack(spacing: 10)") }, """
            the video-library row's `HStack(spacing: 10)` is gone from `clipRow`. The play \
            outset and the 44-frame adjacency argument were both sized against a 10 pt \
            gap — re-measure both in the same commit.
            """)
    }

    // MARK: - the live-narration disclosure (#617, audit case A11y#6)

    /// FORWARD guard (#433, same as the trio above): #617 creates what it pins.
    ///
    /// The disclosure row is a `.plain` Button whose label was ~16 pt of intrinsic text
    /// height — under WCAG 2.5.8's 24. The fix is the pair: `minHeight: 34` (never a
    /// fixed height — the #353 clipping class) plus a −5 outset into the card's own
    /// 12 pt padding, ≥44 pt effective.
    ///
    /// ⚠️ HONEST LIMIT (#617b, review): `liveNarrationBanner` is currently UNMOUNTED —
    /// its only occurrence in `Sources/` is its declaration, pinned as a known orphan by
    /// `NoDoorlessStudioViewsTests` and task #326. This case fixes the surface's geometry
    /// so the doored version inherits it; it does NOT claim a user can reach it today,
    /// and the audit case A11y#6 is closed only in that inherited sense.
    ///
    /// ⛔ RE-ANCHORED IN #644, and the old form would have gone RED ON CORRECT CODE rather than
    /// skipping: the disclosure moved into `LiveNarrationDisclosure.swift` (its heading had to
    /// name the driver its paragraph names, and doing that in `EchoelStudioView` would have put
    /// an `@Observable` read in a Picker-hosting body). `hits.count` in the studio file drops to
    /// zero, which trips the uniqueness assertion BEFORE the `XCTSkip` escape below can run.
    /// Same window, same two needles, one file further out.
    func testTheNarrationDisclosureClearsTheFloor() throws {
        let narration = try codeLines(Self.narration)
        let anchor = "isOpen.toggle()"
        let hits = narration.indices.filter { narration[$0].contains(anchor) }
        XCTAssertEqual(hits.count, 1, """
            `\(anchor)` is no longer unique in LiveNarrationDisclosure — re-anchor this window \
            before trusting the assertions below.
            """)
        guard let start = hits.first,
              let stop = narration[start...].firstIndex(where: {
                  $0.contains("accessibilityLabel(caption.driver.voiceOverLabel)")
              })
        else { throw XCTSkip("the narration disclosure is gone — remove this case with it") }
        let control = narration[start...stop]
        XCTAssertTrue(control.contains { $0.contains("frame(minHeight: 34)") }, """
            the narration disclosure lost its `frame(minHeight: 34)` (#617) — back to a \
            ~16 pt tap strip. `minHeight`, never `height`: the label wraps at large \
            Dynamic Type (the #353 class).
            """)
        XCTAssertTrue(control.contains { $0.contains("contentShape(Rectangle().inset(by: -5))") }, """
            the narration disclosure's −5 outset is gone (#617). 34 + 5 + 5 = 44 — the \
            bleed lands in the card's own 12 pt padding above and the 10 pt gap to the \
            NON-interactive caption below, which is why −5 is safe here and not between \
            the selectable chips this same commit left outset-free.
            """)
    }

    // MARK: - the three 30 pt studio chips became minimums (#617, audit case A11y#7)

    /// FORWARD guard (#433). Three pill buttons carried `.frame(height: 30)` — under every
    /// floor AND fixed, so the pill could not grow with its text (the #353 class, the same
    /// defect `menuChip` documents at length). They are now `minHeight: 34` — the house
    /// in-panel floor (#610b), NOT HIG's 44, stated as the honest limit: these chips sit in
    /// 8 pt rows of selectable peers, where an outset to 44 would overlap the neighbour.
    ///
    /// ⚠️ Deliberately NOT a file-wide ban on `frame(height: 30)` (#364): a future
    /// decorative 30 pt element is legitimate. The needles pin exactly the three chip
    /// spellings this slice changed, padding included, so only a revert can trip them.
    func testTheStudioChipsAreMinimumsNotFixedHeights() throws {
        let studio = try codeLines(Self.studio)
        let grown = studio.filter { $0.contains(".padding(.horizontal, 11).frame(minHeight: 34)") }
        XCTAssertEqual(grown.count, 2, """
            expected exactly the two 11-padded chip pills (`touchPatchChip` + the look \
            chips) at `minHeight: 34` — found \(grown.count). If a chip was redesigned, \
            re-anchor this count in the same commit; if one reverted to a fixed 30, that \
            is the regression this case exists for.
            """)
        // ⛔ THE FIRST DRAFT COUNTED `.padding(.horizontal, 12).frame(minHeight: 34)` == 1
        // FILE-WIDE AND WAS RED ON ITS OWN TREE — the #408 the transcription run caught
        // before CI could: the shape TextField (#262) has carried that exact spelling
        // since long before this slice. A count is only an anchor when the token occurs
        // ONLY at the intended site; this one never did, so the Explore pill is windowed
        // from its unique Button line instead.
        // ⛔ #617b RE-ANCHORED AND TIGHTENED THIS: the first fix styled the pill OUTSIDE
        // the Button's label (`Button("Explore") { … }.padding…`), so under `.plain` the
        // hit test stayed the title's glyph run and the grown pill was decoration — the
        // review's second CRITICAL. The control is now label-closure-built like its two
        // sibling chips, and the window requires the `contentShape` that makes the pill
        // the target.
        let exploreAnchor = "Button { exploreVariations() } label: {"
        let exploreHits = studio.indices.filter { studio[$0].contains(exploreAnchor) }
        XCTAssertEqual(exploreHits.count, 1, """
            the variations Explore/New button line is no longer unique in EchoelStudioView — \
            re-anchor this window before trusting the assertion below.
            """)
        if let start = exploreHits.first {
            let windowEnd = min(start + 10, studio.count)
            let window = studio[start..<windowEnd]
            XCTAssertTrue(window.contains { $0.contains(".padding(.horizontal, 12).frame(minHeight: 34)") }, """
                the variations Explore/New pill is no longer the 12-padded `minHeight: 34` \
                chip (#617). It sits above tappable variation rows, which is why it has no \
                outset and the minimum IS the whole fix.
                """)
            XCTAssertTrue(window.contains { $0.contains("contentShape(Rectangle())") }, """
                the Explore/New pill lost its `contentShape(Rectangle())` (#617b) — or the \
                pill styling moved back OUTSIDE the label closure, where the hit test \
                reverts to the title's ~15 pt glyph run (#485's measured law) and the pill \
                is decoration again.
                """)
        }
        for stale in [".padding(.horizontal, 11).frame(height: 30)",
                      ".padding(.horizontal, 12).frame(height: 30)"] {
            XCTAssertFalse(studio.contains { $0.contains(stale) }, """
                a studio chip reverted to `\(stale)` — fixed below every tap floor and \
                clipping at AX sizes (the #353 class). #617 grew these to `minHeight: 34`.
                """)
        }
    }

    // MARK: - the two mic-Settings doors (#610b — the audit case this file's header asks for)

    /// The #610 "Allow microphone" chips shipped as byte-for-byte copies of BioStrip's
    /// camera door — visible chip ~18 pt, under WCAG 2.5.8's 24 — in the same card whose
    /// "Choose input…" door already carries the 34-pt fix for exactly this defect. The
    /// review found it; per this file's own discipline the finding becomes a case. Both
    /// doors grow the HIT area only (`minHeight`, never `height` — the #353 clipping class)
    /// and need `contentShape(Rectangle())`, or the frame grows layout without growing what
    /// is hit-tested (the loudness-Reset lesson above).
    func testTheMicSettingsDoorsClearTheFloor() throws {
        let sites = [(Self.studio, "mix-board strip"),
                     ("Sources/Echoelmusic/Studio/AudioInputPickerView.swift", "input sheet")]
        for (path, name) in sites {
            let lines = try codeLines(path)
            let anchor = "Button { openAppSettings() } label: {"
            let hits = lines.indices.filter { lines[$0].contains(anchor) }
            XCTAssertEqual(hits.count, 1, """
                `\(anchor)` is no longer unique in \(name)'s file, so the window below may \
                describe a different control. Re-anchor before reading what follows.
                """)
            guard let start = hits.first else { continue }
            guard let end = lines[start...].firstIndex(where: {
                $0.contains("hear yourself live")
            }) else {
                XCTFail("""
                    the \(name) mic-Settings door lost its accessibility hint, so this test \
                    cannot say where the control ends. Re-point the window at whatever closes \
                    it — do not widen it to the file.
                    """)
                continue
            }
            let control = lines[start...end]
            XCTAssertTrue(control.contains(where: { $0.contains("frame(minHeight: 34)") }), """
                the \(name) "Allow microphone" door lost its `frame(minHeight: 34)` (#610b). \
                The bare chip is ~18 pt tall — under WCAG 2.5.8's 24 — and it is the only \
                on-screen path to the fix for a denied microphone.
                """)
            XCTAssertTrue(control.contains(where: { $0.contains("contentShape(Rectangle())") }), """
                the \(name) "Allow microphone" door's `contentShape(Rectangle())` is gone — \
                the frame then grows layout without growing the hit target (the loudness-\
                Reset lesson in this file).
                """)
            XCTAssertFalse(control.contains(where: { $0.contains("frame(height: 34)") }), """
                the \(name) door's frame is FIXED. A fixed height clips the label at large \
                Dynamic Type (the #353 class); the floor has to be a minimum.
                """)
        }
    }
}
