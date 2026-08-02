// ChipLabelGrowsWithTheTextTests.swift
// Echoel — the app's primary navigation must grow with the text, not overflow it. #353b.
//
// WHAT THIS GUARDS. `menuChip` drew its label inside `.frame(height: 26)`. The label uses
// `EchoelTheme.font(12, .semibold)`, which is `.custom(…, relativeTo: .body)` — it scales
// with Dynamic Type — and `EchoelStudioView` is the ONE surface deliberately left unclamped
// (`WorkspaceView` clamps only the chrome, to `.accessibility1`). `StudioZoom` OVERRIDES the
// effective size from its own `.large … .accessibility5` ladder rather than multiplying the
// system one, so the pinch gesture alone reaches the top rung for a user who never opened
// Larger Text.
//
// ⭐ THE CROSSOVER IS AX2, AND IT IS DERIVED RATHER THAN GUESSED — the first draft of this
// header pinned "AX3", the second replaced it with "around AX2, unmeasured", and a reviewer
// then MEASURED it, which is the version that belongs here: `AtkinsonHyperlegible-Bold.ttf`
// has unitsPerEm 1000, ascender 950, descender −290, lineGap 0, i.e. a 1.24 em line box. A
// 12 pt `relativeTo: .body` label draws 14.9 pt at Large, 24.5 pt at AX1 — still inside 26 —
// and 28.9 pt at AX2, which is where it starts overhanging. The device instruction below says
// AX3+ deliberately: comfortably past the crossover, so the check cannot come back ambiguous.
//
// A `.frame` does not clip. The `.background`/`.overlay` rounded rectangles below it size to
// the FRAME, so what actually happens is the text draws OUTSIDE its own pill — the identical
// mechanism `EchoelValueField.boxHeight` documents ("overflowed, not clipped").
//
// ⚠️ THE CHROME BARS IN `WorkspaceView` HAD THE SAME DEFECT BUT NEEDED A BIGGER FIX, and
// saying "same fix" (as the first draft did) would mislead whoever copies this. Theirs is a
// PAIR — `.fixedSize(horizontal: false, vertical: true)` + `.frame(minHeight:)` — and their
// own note says removing either half is a regression for EVERY user, because a vertically
// FLEXIBLE child stretches to the proposal and turns the minimum into an infinity. The chip's
// only child is a `Text`, which never expands to fill, so bare `minHeight` is complete here.
//
// ⭐ WHY THIS ROW WAS MISSED WHILE ITS TWO SIBLINGS WERE FIXED, which is the part worth
// remembering: an overflowing chip in a horizontal strip reads as "the font is a bit big",
// not as breakage. The chrome bars overflowed downward into the next bar and were obvious.
// A defect's VISIBILITY is not its severity — this one sits on the app's most-touched control.
//
// ⚠️ WHY NO `lineLimit` / `minimumScaleFactor` IS ASSERTED, and why one must not be added as a
// "completion" of this fix: shrinking text the user explicitly asked to be larger is the
// anti-fix. (The `minimumScaleFactor(0.6)` on the bio numbers is filed as the #353c half for
// exactly that reason.) The labels cannot wrap here anyway — an unconstrained width inside a
// horizontal `ScrollView` gives every chip its ideal width.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator: it proves the minimum is still SPELLED,
// never that a glyph lands inside its pill at AX5 (NEEDS-FOUNDER-VERIFY: set Larger Text to
// AX3+ and look at the chip strip). And it pins ONE row — it is not a sweep for every fixed
// `.frame(height:)` under `Sources/`. That sweep would fire on decorative glyphs and on rows
// whose parent supplies the height, which is how a gate gets switched off. The rest is filed
// as #353c, and each row there needs the same per-row judgement this one got.
//
// ⛔ THIS SENTENCE SAID "#353c lists the other 21 candidates" AND WAS WRONG TWICE OVER, in the
// exact way this repo keeps paying for. First: at the time it was written **#353c did not
// exist** — it was cited as a filed item in three source locations and a commit body while
// `grep -rn "353c"` returned only those citations. A rationale resting on a record that is not
// there is worse than none, because the next reader cannot refute it. It is filed now. Second:
// 21 was wrong under every reading — the audit's own list of 21 line numbers INCLUDES the chip
// this slice just fixed, so 20 remain from it, while the file today holds 22 non-comment
// `.frame(height:` sites. No number is quoted here any more; #353c carries the command that
// counts them, because that is the only form of this fact that stays true.
//
// ⛔ ONE TEST HERE GOES RED ON THE PRE-FIX SOURCE, NOT TWO, and saying so is the point.
// `testTheChipLabelUsesAMinimumHeight` fails both ways it can (no `minHeight`, a fixed
// `height` present) against `HEAD` before this slice — the intended red. The tap-frame test
// was already green and stays green: it is a CONSISTENCY PIN against a plausible future
// "tidy-up", never evidence that this slice fixed anything there. The sibling file
// `LockedTempoIsTheNumberYouSetTests` carries a note about claiming "red for the right
// reason" over a file when it was true of one assertion; this is that note paid forward.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class ChipLabelGrowsWithTheTextTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The chip label's own height constraint must be a floor, so the pill grows with the text.
    ///
    /// ⛔ THE WINDOW IS BOUNDED BY THE FUNCTION'S OWN LAST LINE, NOT BY A LINE COUNT. A count
    /// rots the moment someone adds a rationale block — and this slice added a large one to the
    /// very function being scanned. `codeLines` strips whole-line comments, so those do not
    /// shift the window; a future one that lands mid-expression would. Anchoring on the closing
    /// `accessibilityAddTraits` makes the window describe the control rather than a distance
    /// to it.
    ///
    /// (⛔ "twelve comment lines" stood here and was 30 by the time it shipped — the number was
    /// true of a draft and was not re-counted when a correction was inserted into the same
    /// block. A self-referential count describing its own commit is the easiest kind to leave
    /// stale, and the sentence does not need it: the argument is "a count rots", which the
    /// count itself then demonstrated.)
    func testTheChipLabelUsesAMinimumHeight() throws {
        let studio = try codeLines(Self.studio)
        let range = try chipRange(studio)

        XCTAssertTrue(studio[range].contains { $0.contains("frame(minHeight: 26)") }, """
            The menu chip's label no longer carries `.frame(minHeight: 26)`. That 26 is the \
            designed pill height (Uncodixfy) and it must be a FLOOR: the label is \
            `EchoelTheme.font(12, .semibold)`, i.e. `.custom(…, relativeTo: .body)`, and \
            `EchoelStudioView` is deliberately not Dynamic-Type-clamped and additionally \
            raised by `StudioZoom` up to `.accessibility5`. Pinned to 26 the text simply draws \
            outside its own pill at the upper rungs, because a `.frame` does not clip and the \
            background/overlay size to the frame rather than to the text. The crossover is AX2 \
            — Atkinson Hyperlegible Bold's 1.24 em line box puts a 12 pt body-relative label at \
            24.5 pt at AX1 and 28.9 pt at AX2 — and it is reachable by pinch alone, without \
            ever opening Larger Text. Same fix as `EchoelValueField`'s `boxHeight`; the chrome \
            bars in `WorkspaceView` took the same defect but needed `fixedSize` alongside, \
            which this control does not (see the header).
            """)

        let fixed = studio[range].filter { $0.contains("frame(height:") }
        XCTAssertTrue(fixed.isEmpty, """
            A fixed `.frame(height:)` is back inside `menuChip`: \
            \(fixed.map { $0.trimmingCharacters(in: .whitespaces) }). \
            Every height in this control is a minimum on purpose — the chip is the app's \
            primary navigation and the only surface with no Dynamic Type ceiling above it. \
            If a new child genuinely needs a fixed box, it needs its own reason written next \
            to it and this assertion narrowed to name the one it excuses.
            """)
    }

    /// The 44 pt tap frame must stay a MINIMUM too, or the fix above breaks it.
    ///
    /// ⛔ THE FIRST DRAFT OPENED "THIS IS NOT A DUPLICATE OF `TapTargetFloorTests`" AND SENT A
    /// FUTURE READER THERE FOR THE CHIP'S 44 pt FLOOR. That file never mentions this control:
    /// its cases are the transport-bar chips, the clear-place ✕ and the two preset overflow
    /// menus, and `grep -rln "chipTapTarget" Tests/` returns only THIS file. So the sentence
    /// invented a division of labour with a file that was not party to it — the same
    /// "rationale resting on a record that is not there" the header now carries a ⛔ about.
    ///
    /// What is true: this assertion is the ONLY guard on the chip's 44 pt anywhere, and it
    /// pins two independent things at once. (1) The FLOOR: 44×44 is the HIG minimum and this
    /// is the app's most-touched control. (2) The DIRECTION: `minHeight` lets the pill grow
    /// THROUGH the tap frame once the label is large, while a `height: 44` would clamp the
    /// wrapper and put the overflow straight back one level out — invisible to any hit-target
    /// check, which only ever asks whether the rectangle is big enough.
    func testTheTapFrameIsStillAFloorAndNotACeiling() throws {
        let studio = try codeLines(Self.studio)
        guard let idx = studio.firstIndex(where: {
            $0.contains("private func chipTapTarget<Content: View>")
        }) else {
            throw XCTSkip("""
                `chipTapTarget` is gone from EchoelStudioView — if the chip strip was \
                restructured this test should be rewritten with it, not left to pass vacuously
                """)
        }
        // ⛔ BOUNDED BY THE NEXT DECLARATION, NOT BY `idx + 6`. The count version had ZERO
        // margin: after comment-stripping it ended exactly one element before `menuChip`'s
        // own declaration, so deleting a single `///` line above `menuChip` would have made
        // the two windows touch. Harmless today — the decl line carries no frame — but it is
        // the same rotting-count shape the sibling assertion's ⛔ argues against, in the file
        // that argues it. `contentShape` is `chipTapTarget`'s last line either way.
        let end = studio[idx...].dropFirst().firstIndex { $0.contains("private func ") } ?? studio.count
        XCTAssertTrue(studio[idx..<end].contains { $0.contains("frame(minWidth: 44, minHeight: 44)") }, """
            `chipTapTarget` no longer spells `.frame(minWidth: 44, minHeight: 44)`. Both \
            numbers are the HIG 44×44 floor AND both are minimums for a second reason: the \
            pill inside grows with Dynamic Type, and a fixed 44 would clamp the wrapper so \
            the enlarged label overflows the tap frame instead of the pill. This is the only \
            place in the whole test bundle that pins either fact about this control — if the \
            floor itself is being changed, that is a founder-facing HIG decision and needs an \
            argument here, not a quiet edit.
            """)
    }

    // MARK: - Reading the source

    /// Index range spanning `menuChip`'s body, from its declaration to its last modifier.
    private func chipRange(_ studio: [String]) throws -> Range<Int> {
        let declaration = "private func menuChip(_ menu: StudioMenu)"
        let terminator = "accessibilityAddTraits(isActive"
        guard let start = studio.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `menuChip` is gone from EchoelStudioView — if the chip strip was restructured \
                this test should be rewritten with it, not left to pass vacuously
                """)
        }
        guard let end = studio[start...].firstIndex(where: { $0.contains(terminator) }) else {
            // ⛔ A THROWN FAILURE, NOT `XCTFail` + `XCTSkip`. The first draft did both, which
            // reports one test as failed AND skipped — an ambiguous result in the only bundle
            // that can redden a merge. A missing terminator is a real defect (the window would
            // otherwise run to the end of a 9000-line file and pass on some unrelated row), so
            // it must be a plain red with the reason attached.
            throw GuardFailure("""
                `menuChip` no longer ends at `\(terminator)`, so this test cannot tell which \
                lines belong to the chip. Re-anchor it in the same commit that moved the \
                modifier rather than letting the window run to the end of the file.
                """)
        }
        return start..<end
    }

    /// A red with an explanation, for the cases where skipping would hide a real regression.
    private struct GuardFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Lines of `path` that are not whole-line comments. Dropped because the fix QUOTES the
    /// spelling it replaced (`.frame(height:`) in its own rationale block, inside the very
    /// window this test scans — a naive match would find the old form in the prose explaining
    /// the new one and fail forever.
    ///
    /// ⚠️ WHOLE-LINE ONLY, and that leaves one shape open that the window note above does not
    /// cover. A TRAILING comment survives: `.padding(.horizontal, 10)  // was .frame(height: 26)`
    /// reads as code, so `fixed.isEmpty` would fail permanently with a message accusing a
    /// comment of being a control. The window note warns about a mid-expression comment moving
    /// the BOUNDS; this is a different hazard on the same mechanism — it poisons the CONTENT.
    /// Every comment inside `menuChip` is whole-line today, which is why this is a warning and
    /// not a fix: a real comment-stripper is more machinery than one assertion is worth, and
    /// `TapTargetFloorTests` accepts the same limit for the same reason.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent(Self.studio)
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
