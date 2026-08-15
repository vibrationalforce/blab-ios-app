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
// ⚠️ LIMIT — SOURCE-TEXT SCAN (§1). Nothing here scrolls a view; whether the fade reads
// as "more to the right" and never occludes a resting chip is a DEVICE probe (named in
// the release notes). VoiceOver is unaffected either way: chips are buttons, swipe
// navigation reaches them regardless of visual clipping.
//
// ⚠️ HONEST GRADING (#433/#464) — transcribed in Python against the parent (e9a83a7) and
// this tree. 7 assertions in 3 tests, hand-counted: claims 1 (3) + 2 (2) + 3 (2).
// Against the PARENT: FIVE are red as ONE finding (#486) — the geometry transform, the
// state declaration, the overlay gate, the fade's hit-test empty and its width all name
// lines born with this commit, FORWARD. Claim 3's two are COUNTERWEIGHTS, green on both
// trees (`showsIndicators: false` and the #291 scroll-into-view are the premises that
// make the hint necessary and sufficient). ZERO regressions claimed, because zero exist.
// `SourceText.codeOnly` is PROPHYLAKTISCH here, MEASURED (#453): 0 of 7 verdicts flip
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
        XCTAssertTrue(code.contains("ScrollView(.horizontal, showsIndicators: false)"), """
            The strip's hidden-indicator scroll is gone. If indicators came back, the \
            fade is a second overflow affordance and the two should be re-judged \
            together rather than shipped stacked.
            """)
        XCTAssertTrue(code.contains("proxy.scrollTo(menu.id, anchor: .center)"), """
            The #291 scroll-into-view is gone. The fade says "more exists"; the scrollTo \
            is what guarantees the SELECTED chip is never the hidden one. Losing it \
            re-opens the pulse-pill bug (#291 rationale 1) that predates this slice.
            """)
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
