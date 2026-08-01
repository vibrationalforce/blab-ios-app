// SoundPanelReflowsTests.swift
// Echoel — #292 Slice 2. The Sound panel is the live timbre editor (the one behind the Sound
// chip; the doorless near-duplicate `PatchEditorView` is deleted, #132 Slice 6) and the
// longest surface in the app.
// Until this slice it was one column at ANY width.
//
// ⭐ THE DEFECT, STATED PRECISELY, because #292's first attempt stated it wrong and the wrong
// version would have sent this pass looking for the wrong thing. It is NOT "a narrow column in
// empty space". `menuPanelHost` sets `maxWidth: .infinity`, and `EchoelValueField` is
// `HStack { label; Spacer(minLength: 8); valueBox }` — a row therefore FILLS the offered width,
// putting the label against the far left edge and its own value box against the far right. On a
// landscape phone that is hundreds of points of nothing between a name and its number. Two
// columns keep each row readable and spend the width on more parameters instead of more gap.
//
// ⚠️ WHAT THIS FILE ACTUALLY GUARDS — three things, and the third is the one that will break.
//   1. The grids exist in `soundPanel` at all.
//   2. `AdaptiveCardGrid`'s spacing still DEFAULTS to 10, so the card caller that predates
//      this slice — `mixerPanel` — is untouched by it. ⛔ The first version wrote
//      `sessionPanel` here and in three other places — wrong: `sessionPanel` merely RENDERED
//      `weatherRow` and contained no grid at all, so anyone acting on a failure message would
//      have grepped it and found nothing. A guard that names the wrong file is a guard that
//      sends its reader away from the code.
//      ⚠️ AND THE CORRECTED VERSION HAS SINCE GONE STALE TOO, which is the more useful lesson:
//      it said "the TWO card callers (`mixerPanel`, `weatherRow`)" and #359 step 2 removed
//      `weatherRow`'s grid when its second card moved to `visualPanel`. One bare caller now.
//      The ASSERTIONS below never named `weatherRow` — they count `init(spacing:)` and match
//      `= 10` — so nothing went red and the prose aged silently. A guard can be correct and
//      its explanation false at the same time; only the explanation is what the next reader
//      acts on.
//   3. THE COUPLING: `soundPanel` passes `spacing: 14` because 14 is `EchoelPanel`'s own content
//      spacing. That is a COPIED CONSTANT. In one column `AdaptiveCardGrid` renders a `VStack`
//      whose spacing REPLACES the panel's rhythm — so if `EchoelPanel` ever moves to, say, 12,
//      the portrait Sound panel silently keeps 14 and drifts from every other panel, on the
//      PRIMARY surface, with nothing failing. A copied constant with no guard is how that ships.
//
// ⛔ HONEST LIMIT — read before trusting a green. This proves the layout is WRITTEN. It cannot
// prove two columns are legible on any real device, that the column break lands between sensible
// parameters, or that the founder prefers it. Device-verify is open, and landscape specifically.
//
// ⚠️ WHY A SOURCE SCAN: `soundPanel` is a `private` member of a view, `@testable import` grants
// `internal` not `private`, and there is no simulator here. House pattern — see
// `ChipStripScrollsToSelectionTests`, `SaveDoorNamingTests`, `LibraryAutosaveSectionTests`.

import Foundation
import XCTest

final class SoundPanelReflowsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let panelChrome = "Sources/Echoelmusic/Studio/EchoelPanel.swift"

    /// The panel's content spacing, copied into every `AdaptiveCardGrid(spacing:)` call in
    /// `soundPanel`. If you change one, change both — that is the whole point of this constant
    /// existing in a test rather than only in two source files that never look at each other.
    private static let panelContentSpacing = "14"

    /// ⭐ THE REFLOW ITSELF. One test for every group: a panel where only some groups
    /// reflow is its own defect (a ragged half-width, half-full-width column), and no single
    /// assertion describes that.
    func testEveryParameterGroupInTheSoundPanelReflows() throws {
        let body = try soundPanelBody()
        // ⛔ NO OPENING PAREN IN THIS FRAGMENT, and the reason is the most likely regression
        // this file will ever see. Both filters used to match `"AdaptiveCardGrid("` — so a
        // seventh group written as the BARE `AdaptiveCardGrid { … }` (the form used twice
        // elsewhere in this same file, i.e. exactly what copy-pasting from `mixerPanel`
        // produces) was counted by NEITHER test. It would render portrait at 10 pt inside a
        // 14 pt panel: the silent, single-surface, primary-surface drift this file exists to
        // prevent, arriving by the most probable authoring route. Without the paren, the next
        // test below now REQUIRES `spacing: 14` on every occurrence and the bare form fails.
        let grids = body.filter { $0.contains("AdaptiveCardGrid") }
        XCTAssertGreaterThanOrEqual(grids.count, 7, """
        `soundPanel` has \(grids.count) `AdaptiveCardGrid` groups, expected at least 7 \
        (Tone · Unison · Filter · Envelope A/D/S/R · Space & vibrato · Level · Sub/Bass).

        A group left unwrapped renders full-width while its neighbours are two-up — a ragged \
        panel is worse than a consistently narrow one. If a group was deliberately removed or \
        merged, lower this number in the same commit and say which.
        """)
    }

    /// ⛔ THE COPIED CONSTANT. This is the assertion most likely to fire, and firing is correct:
    /// it means someone changed the panel rhythm in one of the two places.
    func testTheGridsPassThePanelsOwnContentSpacing() throws {
        let body = try soundPanelBody()
        let calls = body.filter { $0.contains("AdaptiveCardGrid") }
        XCTAssertFalse(calls.isEmpty, "no `AdaptiveCardGrid` in `soundPanel` — see the test above")
        for call in calls {
            XCTAssertTrue(call.contains("spacing: \(Self.panelContentSpacing)"), """
            an `AdaptiveCardGrid` in `soundPanel` does not pass the panel's content spacing \
            (`spacing: \(Self.panelContentSpacing)`): \(call.trimmingCharacters(in: .whitespaces))

            In ONE column the grid renders a `VStack` whose spacing REPLACES the panel's own. \
            The default (10) would silently tighten the iPhone PORTRAIT rows — the primary \
            surface — in exchange for nothing, because portrait does not reflow at all.
            """)
        }
    }

    /// The other half of the same coupling: the number copied above must still be the number
    /// `EchoelPanel` actually uses. Without this, both sides can drift and both tests stay green.
    func testThePanelStillUsesThatSpacingForItsContent() throws {
        let chrome = try codeLines(Self.panelChrome)
        let hits = chrome.filter {
            $0.contains("VStack(alignment: .leading, spacing: \(Self.panelContentSpacing))")
                && $0.contains("content()")
        }
        XCTAssertEqual(hits.count, 2, """
        expected BOTH of `EchoelPanel`'s content stacks (the force-open branch and the \
        DisclosureGroup branch) to use `spacing: \(Self.panelContentSpacing)`, found \(hits.count).

        `soundPanel` copies this number into every `AdaptiveCardGrid(spacing:)` call so its \
        portrait rhythm matches every other panel. If the panel rhythm changed, update \
        `panelContentSpacing` here AND the calls in `soundPanel` — otherwise portrait drifts \
        on one surface only, and nothing else fails.
        """)
    }

    /// ⚠️ THE DEFAULT MUST STAY 10, or this slice silently re-spaces the caller that came
    /// before it: `mixerPanel`. Note the honest reason: it is NOT that "10 was right for cards"
    /// — `mixerPanel`'s grid sits in `EchoelPanel`'s 14 pt stack, so it never matched 10 by
    /// design. It simply SHIPPED at 10, and re-spacing a panel nobody asked about is not this
    /// slice's business. (`weatherRow` was the second such caller until #359 step 2 moved its
    /// Image card into `visualPanel`; a grid with one card left has nothing to arrange, so the
    /// grid went with it. Its own 8 pt local stack is why it, too, never matched 10.)
    func testTheGridDefaultIsUnchangedForTheCardCallers() throws {
        let grid = try adaptiveCardGridBody()
        let inits = grid.filter { $0.contains("init(spacing: CGFloat") }
        XCTAssertEqual(inits.count, 1, """
        expected exactly one `init(spacing:)` inside `AdaptiveCardGrid`, found \(inits.count)
        """)
        for line in inits {
            XCTAssertTrue(line.contains("= 10"), """
            `AdaptiveCardGrid`'s spacing no longer defaults to 10: \
            \(line.trimmingCharacters(in: .whitespaces))

            `mixerPanel` calls it WITHOUT a spacing argument and shipped at 10 before #292 \
            Slice 2 existed. Changing the default re-spaces a panel that nobody asked to \
            change. Pass the new value at the new call site instead.
            """)
        }
    }

    /// ⛔ WITHOUT THIS, THE FILE DOES NOT GUARD ITS OWN HEADLINE CLAIM. The three tests above
    /// prove the call sites pass 14 and that `EchoelPanel` uses 14 — and nothing proved the WIRE
    /// between them. Change the grid's one-column branch back to a literal `VStack(spacing: 10)`
    /// and every one of them stays green while every portrait row in `soundPanel` tightens to
    /// 10: precisely the silent, portrait-only drift the header calls "THE COUPLING".
    ///
    /// The scan is deliberately scoped to `AdaptiveCardGrid`'s own body — a whole-file match on
    /// `spacing: spacing` would pass on any unrelated forwarding elsewhere in 6000 lines.
    func testTheSpacingArgumentActuallyReachesBothLayoutBranches() throws {
        let grid = try adaptiveCardGridBody()
        for fragment in ["VStack(alignment: .leading, spacing: spacing)", "count: columns), spacing: spacing)"] {
            XCTAssertTrue(grid.contains { $0.contains(fragment) }, """
            `AdaptiveCardGrid` no longer forwards its `spacing` argument to `\(fragment)`.

            A hard-coded number in either branch makes the whole `spacing:` parameter \
            decorative: callers keep passing 14, the tests keep passing, and the layout \
            silently uses something else. The ONE-COLUMN branch is the dangerous one — that \
            is iPhone portrait, the primary surface, and it does not reflow, so nothing else \
            about it would look different enough to notice.
            """)
        }
    }

    /// Lines of the `AdaptiveCardGrid` declaration, from `private struct` to the next file-scope
    /// declaration. Scoping the init search matters: a whole-file match on `init(spacing: CGFloat`
    /// would redden the BLOCKING bundle if any other type in this file ever gained such an init —
    /// a red gate for a non-regression, with a message naming the wrong type.
    private func adaptiveCardGridBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private struct AdaptiveCardGrid") }) else {
            XCTFail("`AdaptiveCardGrid` is gone from \(Self.studio) — it is the only reflow "
                    + "primitive in the app. If it was renamed, move this guard with it.")
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("private ") || $0.hasPrefix("struct ") }
            ?? lines.endIndex
        return Array(lines[start..<end])
    }

    /// Lines of `soundPanel`, from its declaration to the next member declaration. Scoping
    /// matters: `AdaptiveCardGrid` legitimately appears in one other panel in this
    /// 6000-line file, and a whole-file scan would pass on those while `soundPanel` itself
    /// had been reverted.
    private func soundPanelBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var soundPanel") }) else {
            XCTFail("`soundPanel` is gone from \(Self.studio) — that is the live timbre editor "
                    + "behind the Sound chip. If it was renamed, move this guard with it.")
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    private ") } ?? lines.endIndex
        return Array(lines[start..<end])
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Load-bearing here: the ⭐ block
    /// inside `soundPanel` explains the grid by NAME (`AdaptiveCardGrid`, `spacing: 14`), so
    /// without the filter all four tests would pass on the explanation after the code it
    /// explains had been reverted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
