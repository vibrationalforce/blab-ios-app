// MoodPanelReflowsTests.swift
// Echoel — #292 Slice 3. `moodPanel` is the second-longest parameter surface in the studio
// (eight mood dimensions plus two role-rhythm pickers) and, until this slice, it was one column
// at ANY width — the same defect `SoundPanelReflowsTests` describes for the Sound panel:
// `EchoelValueField` is `HStack { label; Spacer(minLength: 8); valueBox }` and `menuPanelHost`
// offers `maxWidth: .infinity`, so a landscape row puts a name against the far left edge and the
// number it names against the far right. (⚠️ That row shape is CONDITIONAL since #353e: above an
// accessibility text size the field stacks its label above the box and drops the width pin. The
// description holds below that threshold, which is where the two-column rule applies —
// `AdaptiveCardGrid` forces one column at accessibility sizes, so the two never meet.)
//
// ⚠️ WHAT THIS FILE GUARDS, and what it deliberately does NOT.
//   1. The grids exist in `moodPanel` and pass `spacing: 14`.
//   2. Every one of the eight mood knobs is INSIDE a grid. A panel where some rows reflow and
//      others do not is worse than one that never reflows — that is the ragged half-width /
//      full-width column the Slice-2 file condemns, and counting grids alone cannot see it.
//   3. The preset bar, the weather block and the caption stay OUTSIDE. This is the half that a
//      grep-for-`AdaptiveCardGrid` guard is blind to, and it is the likelier regression: the
//      obvious "tidy-up" for this panel is to sweep everything into the grid, which would put a
//      multi-line Toggle-plus-mixers sub-section into a half-width cell.
//
// It does NOT re-guard the coupling between `spacing: 14` and `EchoelPanel`'s own content
// spacing, nor the `AdaptiveCardGrid` default of 10, nor that the argument reaches both layout
// branches. `SoundPanelReflowsTests` owns all three for the whole primitive, and a second copy of
// a constant is how two guards drift into disagreeing about the same fact. If the panel rhythm
// ever changes, THAT file goes red and this one's call sites are in the same commit.
//
// ⛔ HONEST LIMIT — read before trusting a green. This proves the layout is WRITTEN. It cannot
// prove two columns are legible on a device, that the column break lands between sensible
// parameters, or that the founder prefers it. Device-verify is open, landscape specifically.
//
// ⚠️ WHY A SOURCE SCAN: `moodPanel` is a `private` member of a view, `@testable import` grants
// `internal` not `private`, and there is no simulator here. House pattern — see
// `SoundPanelReflowsTests`, `ChipStripScrollsToSelectionTests`, `SaveDoorNamingTests`.

import Foundation
import XCTest

final class MoodPanelReflowsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The panel's content spacing. Its OTHER half — that `EchoelPanel` still uses this number —
    /// is asserted in `SoundPanelReflowsTests`, on purpose (see the header).
    private static let panelContentSpacing = "14"

    /// ⭐ THE REFLOW ITSELF.
    func testTheMoodPanelPutsItsParameterRowsInGrids() throws {
        let body = try moodPanelBody()
        let grids = body.filter { $0.contains("AdaptiveCardGrid") }
        XCTAssertGreaterThanOrEqual(grids.count, 2, """
        `moodPanel` has \(grids.count) `AdaptiveCardGrid` groups, expected at least 2 \
        (the eight mood dimensions · the two role-rhythm pickers).

        If the two were deliberately merged into one, lower this number in the same commit and \
        say why — but read the ⛔ block at the second grid first: it is split so that a NINTH \
        mood dimension cannot land beside a taller `labeledRow` Picker.
        """)
        for call in grids {
            XCTAssertTrue(call.contains("spacing: \(Self.panelContentSpacing)"), """
            an `AdaptiveCardGrid` in `moodPanel` does not pass the panel's content spacing \
            (`spacing: \(Self.panelContentSpacing)`): \(call.trimmingCharacters(in: .whitespaces))

            In ONE column the grid renders a `VStack` whose spacing REPLACES the panel's own. \
            The default (10) would silently tighten iPhone PORTRAIT — the primary surface — in \
            exchange for nothing, because portrait does not reflow at all.
            """)
        }
    }

    /// ⛔ THE HALF A GRID COUNT CANNOT SEE. Wrapping SOME rows is not a smaller version of this
    /// slice, it is a different and worse layout: two-up rows interleaved with full-width ones.
    func testEveryMoodKnobIsInsideAGrid() throws {
        let body = try moodPanelBody()
        let ranges = gridRanges(in: body)
        let knobs = body.indices.filter { body[$0].contains("moodKnob(") }
        XCTAssertEqual(knobs.count, 8, """
        expected the eight mood dimensions in `moodPanel`, found \(knobs.count) `moodKnob(` rows.

        If a dimension was added or removed, update this number in the same commit — and check \
        the ⛔ block at the second grid, which explains what an ODD count does to the layout.
        """)
        for i in knobs {
            XCTAssertTrue(ranges.contains { $0.contains(i) }, """
            a mood knob sits OUTSIDE every `AdaptiveCardGrid` in `moodPanel`: \
            \(body[i].trimmingCharacters(in: .whitespaces))

            It renders full width while its neighbours are two-up. Put it in one of the grids, \
            or — if it genuinely belongs at full width — say so where it sits and lower the \
            count above.
            """)
        }
    }

    /// ⛔ THE OTHER DIRECTION, and the likelier regression. The obvious tidy-up for this panel is
    /// to sweep everything into the grid. `weatherRow` is a multi-line sub-section (a Toggle, a
    /// permission line, a mixer group, an attribution link) and the caption wraps; both want the
    /// full measure, and the preset bar is chrome, not a parameter.
    func testTheHeadersAndTheWeatherBlockStayOutsideTheGrids() throws {
        let body = try moodPanelBody()
        let ranges = gridRanges(in: body)
        // ⛔ THE CAPTION FRAGMENT IS THE CAPTION'S FIRST WORD, and the first version of this
        // comment claimed that made the guard reword-proof. It does not: the first word is the
        // part a reword changes FIRST, and the miss path below is `XCTFail`, not a soft skip.
        // The honest statement is that rewording this caption costs TWO guards — this one and
        // `WeatherIsAMoodRubricTests`, which pins the longer "Friendly ↔ scary (tension)". That
        // is acceptable (both are one-line edits in the same commit) but it is not free, and a
        // comment that says it is free is how the next person is surprised.
        //
        // ⛔ ALL occurrences, not the first. `firstIndex` would let a SECOND `moodPresetBar`
        // added inside a grid pass while the original stayed outside — the copy-paste shape
        // this guard exists to catch. (`weatherRow` is covered bundle-wide by
        // `WeatherIsAMoodRubricTests`, which asserts exactly one; the other two had nothing.)
        for fragment in ["moodPresetBar", "weatherRow", "Text(\"Friendly"] {
            let hits = body.indices.filter { body[$0].contains(fragment) }
            guard !hits.isEmpty else {
                XCTFail("`\(fragment)` is gone from `moodPanel`. If it moved on purpose, move "
                        + "this guard with it — do not leave a check for a row that is no "
                        + "longer there.")
                continue
            }
            XCTAssertFalse(hits.contains { i in ranges.contains { $0.contains(i) } }, """
            `\(fragment)` is now INSIDE an `AdaptiveCardGrid` in `moodPanel`.

            At a regular width that renders it as a half-width cell beside a parameter row. The \
            preset bar is chrome, `weatherRow` is a multi-line sub-section with its own Toggle \
            and mixer group, and the caption wraps — all three want the full measure. Headers, \
            sub-sections and explanations stay outside the reflow grid.
            """)
        }
    }

    /// Half-open index ranges covering each `AdaptiveCardGrid { … }` in `body`, keyed on
    /// INDENTATION: the grid opens at some column and closes at the first later line that is a
    /// bare `}` in that same column. Every child sits deeper, so no child can be mistaken for the
    /// close. This is scoped to one already-extracted panel body, which is what makes an
    /// indentation rule safe here — it would not be over a 6000-line file.
    ///
    /// ⛔ IT ASSUMES A MULTI-LINE GRID, and says so out loud instead of failing quietly. A
    /// one-line `AdaptiveCardGrid(spacing: 14) { moodKnob("X", $y) }` has no bare `}` at the
    /// opening indent, so no range would be produced — and the FIRST version just skipped it,
    /// which made `testEveryMoodKnobIsInsideAGrid` report "a mood knob sits OUTSIDE every
    /// `AdaptiveCardGrid`" about a knob that is visibly inside one. A guard that fails with the
    /// wrong diagnosis costs more than one that does not fail: the reader goes looking for a
    /// layout regression that never happened. The explicit failure below names the real cause.
    private func gridRanges(in body: [String]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for i in body.indices where body[i].contains("AdaptiveCardGrid") {
            let indent = body[i].prefix { $0 == " " }.count
            let close = body[(i + 1)...].firstIndex {
                $0.trimmingCharacters(in: .whitespaces) == "}"
                    && $0.prefix { c in c == " " }.count == indent
            }
            guard let close else {
                XCTFail("""
                an `AdaptiveCardGrid` in `moodPanel` has no closing `}` at its own indentation: \
                \(body[i].trimmingCharacters(in: .whitespaces))

                This scan brackets each grid by indentation and therefore assumes the grid spans \
                several lines. A single-line grid is not a defect — it just cannot be bracketed \
                this way. Split it across lines, or replace this helper with a brace-depth counter.
                """)
                continue
            }
            out.append(i..<close)
        }
        return out
    }

    /// Lines of `moodPanel`, from its declaration to the next member declaration. Scoping
    /// matters: `AdaptiveCardGrid` legitimately appears in two other panels in this file, and a
    /// whole-file scan would pass on those while `moodPanel` itself had been reverted.
    private func moodPanelBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var moodPanel") }) else {
            XCTFail("`moodPanel` is gone from \(Self.studio) — that is the composition-character "
                    + "surface behind the Mood chip. If it was renamed, move this guard with it.")
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

    /// Every line of `path` that is not a whole-line comment. Load-bearing twice over here: the
    /// ⭐ and ⛔ blocks inside `moodPanel` name `spacing: 14`, `bassRhythmRow` and `LazyVGrid`
    /// explicitly, and stripping them is also what keeps the indentation scan above from taking a
    /// commented-out brace for a grid's closing line.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
