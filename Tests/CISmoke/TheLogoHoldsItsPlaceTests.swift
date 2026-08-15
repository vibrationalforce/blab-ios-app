// TheLogoHoldsItsPlaceTests.swift
// Echoel — #602. Founder clip 2026-08-15: "Das E soll an der selben Stelle und gleichgroß
// sein, wenn man hinundher wechselt vom Visual window zur Studio View."
//
// WHAT THIS GUARDS. The brand mark (`EchoelLogoMark`) is drawn twice: in
// `WorkspaceView.topBar` (studio chrome) and in `FloatingVisualWindow.handleBar` (the
// visual window's drag handle). Before #602 the fullscreen visual drew it 20 pt at centre
// (30, 22) while the studio drew it 26 pt at centre (25, 25) — measured off the founder's
// own clip frames before coding, and the source-derived numbers matched the pixels at
// ±1 pt. Toggling fullscreen ⇄ studio made the E jump and shrink. #602 makes the
// fullscreen mark land on the studio mark exactly: same 26 pt glyph, same (25, 25) centre.
//
// THE GUARD'S SHAPE, and why it is a RELATION and not pinned values (#364): a designer may
// move or resize the studio mark — that is ordinary design work and must not go red. What
// must go red is the two marks DIVERGING, because parity is the founder's explicit ask.
// Claim 1 DERIVES both centres from the two source files' literals and compares the
// derivations. ⚠️ Claim 2 additionally pins the CURRENT fullscreen literals (26/2/3) as
// existence needles, so a coordinated redesign DOES touch this file — it re-reddens claim 2
// with messages that say exactly that (#602b review: the first header claimed "stays green
// without being touched", which was true of claim 1 alone and false of the file).
// ⚠️ NOT OBSERVED (named limit, #602b): child ORDER in topBar. A new child inserted
// BEFORE the mark shifts the real centre while every literal here is unchanged — partial
// cover is `TheHeaderShowsTheLoopTests.testTheMarkLeadsTheHeaderAndIsNotAControl` (mark
// before readout before brand), which does not forbid a new leading child. That residue
// is the device probe's half.
//
// ⚠️ LIMIT — SOURCE-TEXT SCAN with arithmetic on extracted literals. It proves the
// LITERALS compose to equal centres under the documented layout model (HStack padding +
// leading-aligned frame + offset vs. padding + centred frame in a minHeight bar). It
// cannot prove SwiftUI lays either bar out as modelled, that safe areas match (topBar
// respects the top safe area; the fullscreen card bleeds bottom/horizontal only — read
// from `fullscreenBleedEdges`), or that the result LOOKS right — that stays a device
// probe, the same clip re-shot on the new build. The model was validated once against
// the founder's clip (studio ≈(24.8, 25), visual ≈(29, 22) pre-fix — both within 1 pt of
// the derivation), which is what makes arithmetic on literals worth anything here.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (30564bd) and this tree
// (#433/#464). 13 named assertions in 4 tests, hand-counted: claims 1 (5, incl. the
// #602b square-box check) + 2 (4) + 3 (2) + 4 (2); plus 2 `XCTAssertFalse(bar.isEmpty)`
// anchor sentinels inside the extraction helpers = 15 XCTAssert sites total (#602b
// review counted the sites; the first header said 12 and meant only the named claims).
// On THIS tree all pass (derivation: studio (25,25)/26 == fullscreen (25,25)/26). Against the PARENT: ONE finding (#486), reported across three tests —
// the fullscreen branch does not exist there, so `fullscreenGeometry()` THROWS at its
// first extraction (claim 1 errors with no verdicts on its four assertions — including
// its studio-side internal-consistency check, which would be green but is unreached),
// and claim 2's four needles plus claim 3's two are absent. All of these are FORWARD,
// born with this commit — the parent's mark frame is the comma-less
// `.frame(width: 40, height: handleHeight)`, so even claim 3's hit-frame needle is new
// text, not a surviving premise. The true both-trees COUNTERWEIGHTS are claim 4's two
// (drag gesture + mark presence) and the studio extraction (pad 12 / size 26 /
// minHeight 50 extract identically on both trees). ZERO regressions claimed, because
// zero exist.
// `SourceText.codeOnly` is PROPHYLAKTISCH here, MEASURED (#453): 0 of the extraction
// patterns flip raw-vs-stripped on this tree — the #602 prose block does name 26/2/3
// ("12 + 26/2 = 25"), but no extraction REGEX matches that prose form. The stripper
// stays because the guard's needles must not silently start matching a future comment
// that quotes them more literally (#491's living-law direction).

import Foundation
import XCTest

final class TheLogoHoldsItsPlaceTests: XCTestCase {

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let visual = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

    // MARK: - claim 1 — the two centres are EQUAL by derivation

    func testTheFullscreenMarkLandsOnTheStudioMark() throws {
        let studio = try studioGeometry()
        let vis = try fullscreenGeometry()
        XCTAssertEqual(studio.size, vis.size, """
            The studio mark is \(studio.size) pt and the fullscreen visual mark is \
            \(vis.size) pt. The founder's ask (#602) is that the E is GLEICHGROSS across \
            the toggle — change either size only together with the other, in the same \
            commit (the visual side is the `windowSize.isFullscreen ? N : 20` literal in \
            `handleBar`).
            """)
        XCTAssertEqual(studio.centerX, vis.centerX, """
            Derived horizontal centres diverge: studio pad \(studio.pad) + \(studio.size)/2 \
            = \(studio.centerX) vs fullscreen pad \(vis.pad) + \(vis.size)/2 + x-offset \
            \(vis.offsetX) = \(vis.centerX). The E must sit AN DER SELBEN STELLE across \
            the toggle (#602) — after moving the studio mark, recompute the visual's \
            `.offset(x:)` in `handleBar` in the same commit.
            """)
        XCTAssertEqual(studio.centerY, vis.centerY, """
            Derived vertical centres diverge: studio bar minHeight \(studio.barHeight)/2 = \
            \(studio.centerY) vs fullscreen bar \(vis.barHeight)/2 + offset \(vis.offsetY) \
            = \(vis.centerY). Recompute the fullscreen `.offset(y:)` in `handleBar` when \
            either bar's design height changes.
            """)
        XCTAssertEqual(studio.size, 2 * (studio.centerX - studio.pad), """
            The derivation's Int arithmetic broke: the studio mark size is ODD, so \
            `size/2` truncates and every centre above is off by half a point. Use an \
            even design size or switch this file's arithmetic to Double.
            """)
        // ⚠️ #602b: this assertion is ARITHMETIC-ONLY (an odd-size tripwire). Its first
        // version claimed to detect "the mark is no longer the first child" — nothing in
        // this file observes child order; see the header's NOT-OBSERVED note.
        XCTAssertEqual(try fullscreenHeight(), vis.size, """
            The fullscreen mark's HEIGHT branch diverged from its width — the frame is \
            no longer square, so the drawn glyph is distorted relative to the studio's \
            \(studio.size)×\(studio.size) box. Keep the two `windowSize.isFullscreen ? N \
            : 20` literals identical.
            """)
    }

    // MARK: - claim 2 — the fullscreen branch exists (the #602 mechanism)

    func testTheFullscreenBranchCarriesTheParity() throws {
        let code = try source(Self.visual)
        XCTAssertTrue(code.contains("windowSize.isFullscreen ? 26 : 20"), """
            The fullscreen mark-size branch is gone from `handleBar`. Without it the \
            visual window regresses to the 20 pt handle in fullscreen and the E shrinks \
            on every toggle (#602). If the sizes were legitimately redesigned, this \
            needle and the derivation assertions above must move together.
            """)
        XCTAssertTrue(code.contains("alignment: windowSize.isFullscreen ? .leading : .center"), """
            The fullscreen leading alignment is gone. Centred in its 40 pt hit frame the \
            mark sits at x=30, not the studio's 25 — the horizontal half of the jump the \
            founder filmed.
            """)
        XCTAssertTrue(code.contains(".offset(x: windowSize.isFullscreen ? 2 : 0,"), """
            The 2 pt fullscreen x-offset is gone — leading-aligned without it the mark \
            centres at 23, not 25; it closes the pad difference (studio 12 vs bar 10). \
            It is an OFFSET and not a leading padding ON PURPOSE: an offset consumes no \
            layout width, so `ChromeCost.logo = 40` and its re-derived twin in \
            `ChromeBudgetFitsTests` stay exactly true.
            """)
        XCTAssertTrue(code.contains("y: windowSize.isFullscreen ? 3 : 0)"), """
            The 3 pt fullscreen y-offset is gone — it closes the bar-height difference \
            (studio 50 vs handle bar 44) so the glyph centres align at 25 pt from each \
            bar's top.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the floating sizes kept their compact handle

    /// #343: the ask is about the FULLSCREEN toggle. In the floating card sizes the studio
    /// bar with its own mark is on screen at the same time; a second 26 pt mark in a small
    /// card bar would crowd it. Both branches falling back to `20` / `.center` / `0` is
    /// the deliberate other half of the design.
    func testTheFloatingSizesKeepTheCompactHandle() throws {
        let code = try source(Self.visual)
        XCTAssertTrue(code.contains("? 26 : 20"), """
            The floating fallback size is no longer 20 — if the floating handle was \
            legitimately redesigned, rewrite this file's claim-3 rationale too; if not, \
            the small card bars just inherited a 26 pt mark they were never sized for.
            """)
        XCTAssertTrue(code.contains(".frame(width: 40, height: handleHeight,"), """
            The 40 pt hit frame around the mark is gone. It is the drag handle's tap \
            target (the old ≡'s size) — shrinking it to the glyph breaks move-by-handle \
            on the floating cards.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the mark is still the drag handle

    func testTheMarkStillDrags() throws {
        let code = try source(Self.visual)
        let bar = slice(code, from: "private func handleBar", to: "\n    private func")
        XCTAssertTrue(bar.contains("DragGesture(coordinateSpace: .global)"), """
            The logo's drag gesture left `handleBar` (or lost its `.global` space — the \
            `.local` version feeds back on itself and the window trembles, founder \
            "zittert"). #602 re-shaped the logo's frames; the gesture must survive that \
            chain.
            """)
        XCTAssertTrue(bar.contains("EchoelLogoMark()"), """
            `handleBar` no longer draws the brand mark at all — the founder's 2026-07-07 \
            ask put the logo here as the drag handle ("im Visual Fenster soll man das \
            Logo sehen, oben links"), and #602 built its parity on top. Whatever replaced \
            it must re-answer both asks.
            """)
    }

    // MARK: - geometry extraction

    private struct StudioGeometry {
        let pad: Int; let size: Int; let barHeight: Int
        var centerX: Int { pad + size / 2 }
        var centerY: Int { barHeight / 2 }
    }

    private struct FullscreenGeometry {
        let pad: Int; let offsetX: Int; let size: Int; let barHeight: Int; let offsetY: Int
        var centerX: Int { pad + size / 2 + offsetX }
        var centerY: Int { barHeight / 2 + offsetY }
    }

    /// `topBar`'s mark: first child of the bar's HStack. Slice runs to the bar's closing
    /// `.background`, so the one `.padding(.horizontal, N)` inside is the bar's own.
    private func studioGeometry() throws -> StudioGeometry {
        let code = try source(Self.workspace)
        let bar = slice(code, from: "private var topBar: some View", to: ".background(EchoelTheme.bg)")
        XCTAssertFalse(bar.isEmpty, "topBar (or its .background terminator) is gone from WorkspaceView — re-anchor this scan")
        let mark = slice(bar, from: "EchoelLogoMark()", to: ".accessibilityHidden")
        let size = try number(#"\.frame\(width: (\d+), height: \d+\)"#, in: mark, context: "studio mark size")
        let pad = try number(#"\.padding\(\.horizontal, (\d+)\)"#, in: bar, context: "topBar horizontal padding")
        let barHeight = try number(#"minHeight: (\d+)"#, in: bar, context: "topBar minHeight")
        return StudioGeometry(pad: pad, size: size, barHeight: barHeight)
    }

    /// The fullscreen mark's HEIGHT literal — asserted equal to the width so the box
    /// stays square (#602b review: the width needle alone let a height-only edit pass).
    private func fullscreenHeight() throws -> Int {
        let bar = slice(try source(Self.visual), from: "private func handleBar", to: "\n    private func")
        return try number(#"height: windowSize\.isFullscreen \? (\d+) : 20"#, in: bar,
                          context: "fullscreen mark height")
    }

    /// `handleBar`'s mark in the fullscreen branch. The bar's own padding is the one
    /// directly above `.frame(height: handleHeight)` — the Studio chip inside the bar
    /// carries another `.padding(.horizontal, 10)`, which is why the anchored pair form
    /// is required (#408).
    private func fullscreenGeometry() throws -> FullscreenGeometry {
        let code = try source(Self.visual)
        let bar = slice(code, from: "private func handleBar", to: "\n    private func")
        XCTAssertFalse(bar.isEmpty, "handleBar is gone from FloatingVisualWindow — re-anchor this scan")
        let size = try number(#"width: windowSize\.isFullscreen \? (\d+) : 20"#, in: bar, context: "fullscreen mark size")
        let offsetX = try number(#"\.offset\(x: windowSize\.isFullscreen \? (\d+) : 0,"#, in: bar, context: "fullscreen x offset")
        let offsetY = try number(#"y: windowSize\.isFullscreen \? (\d+) : 0\)"#, in: bar, context: "fullscreen y offset")
        let pad = try number(#"\.padding\(\.horizontal, (\d+)\)\s*\n\s*\.frame\(height: handleHeight\)"#, in: bar, context: "handleBar horizontal padding")
        let barHeight = try number(#"private let handleHeight: CGFloat = (\d+)"#, in: code, context: "handleHeight")
        return FullscreenGeometry(pad: pad, offsetX: offsetX, size: size, barHeight: barHeight, offsetY: offsetY)
    }

    private func number(_ pattern: String, in text: String, context: String) throws -> Int {
        let re = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text), let value = Int(text[r]) else {
            throw AnchorMissing(reason: """
                Could not extract \(context) (pattern \(pattern)) — the layout literal moved \
                or was renamed. Re-anchor this extraction rather than letting the derivation \
                silently compare nothing.
                """)
        }
        return value
    }

    // MARK: - source access

    private struct AnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func slice(_ code: String, from: String, to: String) -> String {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            return ""
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }
}
