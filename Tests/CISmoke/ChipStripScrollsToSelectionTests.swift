// ChipStripScrollsToSelectionTests.swift
// Echoel — #291. #290 took the front-plate chip strip from five chips to nine, and
// `visibleChips` can append a tenth. Nine chips at their real widths (Atkinson Hyperlegible
// Bold labels, each in a 44 pt minimum tap frame, 6 pt apart, 20 pt row padding) come to
// roughly 590 pt against a ~393 pt portrait phone — and `EchoelStudioView` is deliberately
// NOT Dynamic-Type-clamped and additionally scales with `StudioZoom`. The strip overflows,
// with `showsIndicators: false`.
//
// ⭐ WHAT THAT BREAKS, and why it needs a guard rather than a comment. Two separate claims
// this repo has already spent cycles on stop being true the moment the strip overflows:
//   1. `visibleChips` exists so the strip never shows an unselected state — but it appends
//      the active menu LAST, i.e. off the right edge. Opening Bio from the pulse pill then
//      selects a chip nobody can see.
//   2. #272/#290 argued a permanent "Save/Export" chip names saving and recording more
//      strongly than the buried "•••" entry it replaced. `.export` is the ninth chip. Behind
//      a hidden-indicator horizontal scroll it is *less* findable than the "•••" glyph — the
//      founder's original complaint ("Session speichern und Loops aufnehmen fehlt") one
//      layer over.
// `SaveDoorNamingTests` proves `.export` is in the array. Nothing proved it can be REACHED.
//
// ⚠️ WHY A SOURCE SCAN. `menuBar` is a `private` member of a view; `@testable import` grants
// `internal`, not `private`, and there is no simulator here. House pattern:
// `SaveDoorNamingTests`, `LibraryAutosaveSectionTests`, `ChromeDynamicTypeTests`.
//
// ⛔ HONEST LIMIT — read this before trusting a green. This proves the scroll mechanism is
// WRITTEN. It cannot prove the strip actually overflows on any given device, that the
// animation lands, or that the centred chip is legible. The ~590 pt above is computed from
// the constants, not measured. Device-verify is open.

import Foundation
import XCTest

final class ChipStripScrollsToSelectionTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⭐ THE MECHANISM. All three parts in ONE test on purpose: a `ScrollViewReader` with no
    /// `scrollTo`, or a `scrollTo` with no trigger, is decoration — and neither assertion
    /// alone describes the defect.
    func testTheChipStripScrollsTheSelectedChipIntoView() throws {
        let body = try menuBarBody()
        // ⛔ NO CLOSING PAREN ON THE `onChange` FRAGMENT. The first version pinned
        // `"onChange(of: displayedMenu)"` including it, so adding a perfectly benign
        // `initial:`/`_:` argument would have reddened the BLOCKING bundle for no defect —
        // a guard that fails on a non-regression is worse than no guard, because the next
        // person deletes it instead of reading it.
        for fragment in ["ScrollViewReader", "onChange(of: displayedMenu", "scrollTo("] {
            XCTAssertTrue(body.contains { $0.contains(fragment) }, """
            `menuBar` no longer contains `\(fragment)`. Without all three the selected chip \
            is not brought into view, and on a nine-chip strip that overflows a ~393 pt phone \
            the app shows a tab strip with no visible selection — and hides "Save/Export", \
            the ninth chip, behind a scroll gesture with no indicator (#272 all over again).

            If the strip was made to FIT instead (fewer chips, shorter labels, a wrapping \
            layout), delete this file in that commit — do not leave a guard for a mechanism \
            the code no longer has.
            """)
        }
    }

    /// ⛔ THE ANCHOR MUST BE THE `id`, NOT THE ENUM — the one way this fix can compile and do
    /// nothing at all. `StudioMenu` is a `String`-backed enum, hence `Hashable`, so
    /// `scrollTo(menu)` type-checks; but `ForEach` over `Identifiable` data registers each row
    /// under `element.id`, and `AnyHashable(StudioMenu.export) != AnyHashable("export")`. The
    /// lookup misses forever, with no warning and no other gate to catch it.
    func testTheScrollAnchorIsTheIdentifierNotTheEnumCase() throws {
        let body = try menuBarBody()
        let calls = body.filter { $0.contains("scrollTo(") }
        XCTAssertFalse(calls.isEmpty, "no `scrollTo(` in `menuBar` — see the test above")
        for call in calls {
            XCTAssertTrue(call.contains(".id"), """
            a `scrollTo` in `menuBar` does not pass an `.id`: \(call.trimmingCharacters(in: .whitespaces))
            `ForEach(visibleChips)` anchors rows under `StudioMenu.id` (the raw `String`). \
            Passing the enum itself compiles and silently never matches.
            """)
        }
    }

    /// Lines of `menuBar`'s body: from its declaration to the next member declaration.
    /// Scoping matters — `scrollTo` and `ScrollViewReader` may legitimately appear elsewhere
    /// in this 6000-line file, and a whole-file scan would pass on those while `menuBar`
    /// itself had been reverted.
    private func menuBarBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var menuBar") }) else {
            XCTFail("`menuBar` is gone from \(Self.studio) — that is the front-plate chip "
                    + "strip. If it was renamed, move this guard with it.")
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

    /// Every line of `path` that is not a whole-line comment. Load-bearing here: the ⭐ and ⛔
    /// prose inside `menuBar` names `ScrollViewReader`, `scrollTo` and `.id` explicitly, so
    /// without the filter both tests would pass on the explanation after the code it explains
    /// had been deleted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
