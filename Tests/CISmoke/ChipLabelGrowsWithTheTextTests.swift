// ChipLabelGrowsWithTheTextTests.swift
// Echoel — the app's primary navigation must grow with the text, not overflow it. #353b.
//
// WHAT THIS GUARDS. `menuChip` drew its label inside `.frame(height: 26)`. The label uses
// `EchoelTheme.font(12, .semibold)`, which is `.custom(…, relativeTo: .body)` — it scales
// with Dynamic Type — and `EchoelStudioView` is the ONE surface deliberately left unclamped
// (`WorkspaceView` clamps only the chrome, to `.accessibility1`). `StudioZoom` OVERRIDES the
// effective size from its own `.large … .accessibility5` ladder rather than multiplying the
// system one, so the pinch gesture alone reaches the top rung for a user who never opened
// Larger Text. Either way the glyphs end up taller than 26 pt well before the top.
//
// A `.frame` does not clip. The `.background`/`.overlay` rounded rectangles below it size to
// the FRAME, so what actually happens is the text draws OUTSIDE its own pill — the identical
// mechanism `EchoelValueField.boxHeight` documents ("overflowed, not clipped") and the same
// fix the three chrome bars in `WorkspaceView` took: the number becomes a MINIMUM.
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
// whose parent supplies the height, which is how a gate gets switched off. #353c lists the
// other 21 candidates; each needs the same per-row judgement this one got.
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
    /// rots the moment someone adds a rationale block — and this slice added twelve comment
    /// lines to the very function being scanned. `codeLines` strips whole-line comments, so
    /// those twelve do not shift the window; a future one that lands mid-expression would.
    /// Anchoring on the closing `accessibilityAddTraits` makes the window describe the control
    /// rather than a distance to it.
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
            background/overlay size to the frame rather than to the text. (No rung is named \
            here on purpose: the crossover depends on Atkinson Hyperlegible's line height and \
            this environment has no simulator to measure it. A back-of-envelope body-scale \
            calculation puts it around AX2 — near enough that pinning "AX3" would be a number \
            nobody checked.) Same fix as `EchoelValueField`'s `boxHeight` and the three chrome \
            bars in `WorkspaceView`.
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
    /// ⚠️ THIS IS NOT A DUPLICATE OF `TapTargetFloorTests`. That file guards the HIG floor —
    /// that the enlargement exists at all. This one guards the direction of the constraint:
    /// `minHeight: 44` lets the pill grow THROUGH the tap frame when the text is large, while
    /// a `height: 44` would clamp the frame and put the overflow straight back — the same
    /// defect one level out, and green in every hit-target check. The two facts are adjacent
    /// in the source and independent in what they protect.
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
        let end = min(idx + 6, studio.count)
        XCTAssertTrue(studio[idx..<end].contains { $0.contains("frame(minWidth: 44, minHeight: 44)") }, """
            `chipTapTarget` no longer spells `.frame(minWidth: 44, minHeight: 44)`. Both \
            numbers are the HIG 44×44 floor AND both are minimums for a second reason: the \
            pill inside grows with Dynamic Type, and a fixed 44 would clamp the wrapper so \
            the enlarged label overflows the tap frame instead of the pill. If the floor \
            itself moved, `TapTargetFloorTests` is the file that argues about the number; \
            this assertion is about `min`.
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
