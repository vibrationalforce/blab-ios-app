// TheChipStripAdmitsItOverflowsTests.swift
// Echoel — #607 (GUI-Board Scheibe 4, from the #603 UX audit's finding #5).
//
// WHAT THIS GUARDS. The chip strip — the app's primary navigation — overflows a portrait
// phone (~540 pt of chips on 393 pt, measured in `menuBar`'s own #291 doc) and scrolls
// with `showsIndicators: false`. Nothing on screen said "there is more": the trailing
// chips (Field · Save & Export) were simply invisible, which is #272's buried-"•••"
// complaint reborn one layer over. The fix: an `onScrollGeometryChange` (iOS 18 floor)
// reduces the scroll geometry to ONE Bool — "content continues past the trailing edge" —
// and a 24 pt fade to the strip's own background renders only while that is true. At the
// fully-scrolled-right position the Bool is false and the last chip is shown UNfaded:
// the hint never lies about an edge the user has already reached.
//
// ⚠️ UNCODIXFY: the fade is a FUNCTIONAL affordance (signals clipped content — the
// "serve a control function" clause), not a decorative gradient. It is non-interactive
// (`allowsHitTesting(false)`) so the chip beneath stays tappable through it.
//
// ⚠️ FREEZE LAW, stated because a scroll callback smells like a clock: the transform
// closure runs during scrolls, but `action:` fires only when the REDUCED value changes —
// a Bool that flips at the overflow boundary, i.e. edge-triggered state writes at
// interaction rate, not a per-frame publisher. No `@Observable` is read.
//
// ⚠️ LIMIT — SOURCE-TEXT SCAN (§1). Nothing here scrolls a view. TWO device questions,
// named separately because only one of them can defeat the slice: (1) the SEEDING
// question — does `onScrollGeometryChange`'s `action:` fire once at appearance, so an
// overflowing strip shows the fade BEFORE the first scroll? Two independent API
// mechanisms say yes (the documented initial invocation of the on*GeometryChange family,
// and the initial-layout geometry change itself flipping false→true), but neither is
// provable without a device — if it does NOT fire, the hint is invisible to exactly the
// user it targets. (2) the READING question — does the fade read as "more to the right"
// rather than occluding a resting chip. VoiceOver is unaffected either way: chips are
// buttons, swipe navigation reaches them regardless of visual clipping.
//
// ⚠️ HONEST GRADING (#433/#464) — transcribed in Python against the parent (e9a83a7) and
// this tree. 8 assertions in 3 tests, hand-counted: claims 1 (3) + 2 (2) + 3 (1 slice
// non-empty + 2 scoped needles = 3; the slice-scoping and its non-empty check are #607b,
// after the review found the indicator needle five-fold file-wide).
// Against the PARENT: FIVE are red as ONE finding (#486) — the geometry transform, the
// state declaration, the action WRITE (`chipStripHasMoreTrailing = hasMore`), the
// overlay gate and the fade's hit-test empty all name lines born with this commit,
// FORWARD. ⛔ The first version of this sentence listed "and its width" — there is no
// width assertion in this file — and omitted the action write: the #475 class (right
// number, wrong object), caught by the #607 review in the very header whose job is the
// count. Claim 3's three are COUNTERWEIGHTS, green on both trees (`menuBar` exists,
// and its `showsIndicators: false` + #291 scroll-into-view are the premises that make
// the hint necessary and sufficient). ZERO regressions claimed, because zero exist.
// `SourceText.codeOnly` is PROPHYLAKTISCH here, MEASURED (#453): 0 of 8 verdicts flip
// raw-vs-stripped on either tree — no needle below is quoted whole in a comment.

import Foundation
import XCTest

final class TheChipStripAdmitsItOverflowsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - claim 1 — the strip measures its own overflow, edge-triggered

    func testTheStripMeasuresItsOwnOverflow() throws {
        let code = try source(Self.studio)
        XCTAssertTrue(code.contains("geo.contentOffset.x + geo.containerSize.width < geo.contentSize.width - 1"), """
            The overflow reduction is gone or changed. This exact inequality is the whole \
            measurement: "the content continues past the trailing edge" (1 pt tolerance so \
            a rounding rest at the end position cannot flicker the fade). If it moved to a \
            helper, move this needle with it in the same commit.
            """)
        XCTAssertTrue(code.contains("@State private var chipStripHasMoreTrailing = false"), """
            The overflow flag is gone (or its default changed). `false` at rest matters: \
            before the first geometry callback the strip shows NO fade — a wrong `true` \
            default would fade the last chip on strips that never overflow (iPad-class \
            widths, few chips).
            """)
        XCTAssertTrue(code.contains("chipStripHasMoreTrailing = hasMore"), """
            The action no longer writes the flag. Without the write the fade is frozen at \
            its default forever and the whole slice is a no-op wearing the shape of a fix \
            — the silent-no-op failure mode `menuBar`'s own #291 retrospective names.
            """)
    }

    // MARK: - claim 2 — the fade renders only while true, and never steals a tap

    func testTheFadeIsConditionalAndNonInteractive() throws {
        let code = try source(Self.studio)
        XCTAssertTrue(code.contains("if chipStripHasMoreTrailing {"), """
            The fade lost its gate. Unconditional, it dims the LAST chip precisely at the \
            fully-scrolled position — telling the user "there is more" at the one moment \
            there is not, and permanently on strips that never overflow.
            """)
        XCTAssertTrue(code.contains(".allowsHitTesting(false)"), """
            The fade became interactive. It overlays the trailing ~24 pt of the strip, \
            which is exactly where the last chip's tap target sits — without \
            `allowsHitTesting(false)` the hint would swallow the tap on the very chip it \
            exists to make findable. (First occurrence of this modifier in this file — \
            if a second appears, re-anchor this needle to the fade's overlay.)
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHTS, #343) — the premises that make the hint right

    func testTheStripsScrollPremisesSurvive() throws {
        let code = try source(Self.studio)
        // ⛔ #607b: this needle occurs FIVE times file-wide (measured — the #607 review
        // caught the first version asserting it file-wide while the log called every
        // needle unique). Scoped to `menuBar`'s own body, the #408 way: the slice runs
        // from the declaration to the first indent-4 closing brace, which is the
        // member's own end (every line inside the body sits at indent ≥ 8).
        let bar = slice(code, from: "private var menuBar: some View {", to: "\n    }")
        XCTAssertFalse(bar.isEmpty, """
            `menuBar` is gone or renamed — the chip strip this whole guard is about. \
            Re-anchor the slice; do not let the two scoped needles below go green on \
            an empty string.
            """)
        XCTAssertTrue(bar.contains("ScrollView(.horizontal, showsIndicators: false)"), """
            The CHIP STRIP's hidden-indicator scroll is gone (four other ScrollViews in \
            this file legitimately share the pattern — this assertion is scoped to \
            `menuBar`). If indicators came back HERE, the fade is a second overflow \
            affordance and the two should be re-judged together rather than shipped \
            stacked.
            """)
        XCTAssertTrue(bar.contains("proxy.scrollTo(menu.id, anchor: .center)"), """
            The #291 scroll-into-view is gone from `menuBar`. The fade says "more \
            exists"; the scrollTo is what guarantees the SELECTED chip is never the \
            hidden one. Losing it re-opens the pulse-pill bug (#291 rationale 1) that \
            predates this slice.
            """)
    }

    private func slice(_ code: String, from: String, to: String) -> String {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            return ""
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct AnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
