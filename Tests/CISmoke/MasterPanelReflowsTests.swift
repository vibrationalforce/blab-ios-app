// MasterPanelReflowsTests.swift
// Echoel — #292 Slice 5. `masterPanel` gets its first adaptive group: the two delivery
// choices ("Target" loudness · "Tone" character) reflow to two columns on a wide layout.
//
// SOURCE-TEXT SCAN (see Tests/CISmoke/CLAUDE.md §1): `masterPanel` is a `private` member of a
// view no test bundle can instantiate, and there is no simulator here. This proves the layout
// is WRITTEN, never that it renders well — device-verify stays open, landscape specifically.
//
// WHY ONLY TWO ROWS, when the sibling slices grid-wrapped whole panels: `masterPanel` is not a
// parameter surface. Its other children are churn-isolating LEAVES (`MasterVolumeField`,
// `MasterLoudnessGrid`, `AudioTimingRow` — each exists so a 60 Hz/automation write re-renders
// only itself, never the menu-hosting studio body) or full-measure rows (a wrapping caption, the
// release-all button, the two re-door buttons). Sweeping any of those into a half-width cell is
// the regression `MoodPanelReflowsTests` claim 3 condemns — worse than never reflowing. The two
// pickers are the panel's only pair of same-height parameter rows, so they are the whole slice.
//
// ⚠️ WHAT THIS FILE GUARDS:
//   1. Exactly ONE `AdaptiveCardGrid` exists in `masterPanel` and it passes `spacing: 14` —
//      the panel content spacing, because in ONE column the grid's `VStack` REPLACES the
//      host's rhythm and the default (10) would silently tighten iPhone portrait.
//      (The coupling between "14" and `EchoelPanel`'s own spacing is owned by
//      `SoundPanelReflowsTests` for the whole primitive — not re-guarded here, #416.)
//   2. Both delivery rows are INSIDE that grid.
//   3. The leaves and full-measure rows stay OUTSIDE it (the likelier regression: the obvious
//      tidy-up sweeps everything in).
//
// HONEST GRADING (§3, against parent 7566479): claim 1 + claim 2 are red on the parent by ONE
// anchor absence (`masterPanel` has no `AdaptiveCardGrid` there) — one finding, reported by
// three assertions (#486). Claim 3's five fragments are COUNTERWEIGHTS, green on both trees.
// Transcribed in Python against parent and worktree before push (§0); not run by any local
// toolchain — CI is the only compiler.

import Foundation
import XCTest

final class MasterPanelReflowsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The panel's content spacing — asserted as the ARGUMENT the grid passes. Its other half
    /// (that `EchoelPanel` still uses this number) is `SoundPanelReflowsTests`' claim, on purpose.
    private static let panelContentSpacing = "14"

    /// ⭐ THE REFLOW ITSELF (claim 1).
    func testTheMasterPanelHasExactlyOneGridAndItPassesThePanelSpacing() throws {
        let body = try masterPanelBody()
        let grids = body.filter { $0.contains("AdaptiveCardGrid") }
        XCTAssertEqual(grids.count, 1, """
        `masterPanel` has \(grids.count) `AdaptiveCardGrid` groups, expected exactly 1 (the
        Target · Tone delivery pair). Zero = the reflow was reverted — pull the two CLAUDE.md
        counters ("5 von 10") back down in the same commit. Two or more = a leaf or a
        full-measure row was probably swept into a grid; read the header's WHY ONLY TWO ROWS
        before raising this number.
        """)
        for call in grids {
            XCTAssertTrue(call.contains("spacing: \(Self.panelContentSpacing)"), """
            the `AdaptiveCardGrid` in `masterPanel` does not pass the panel's content spacing \
            (`spacing: \(Self.panelContentSpacing)`): \(call.trimmingCharacters(in: .whitespaces))

            In ONE column the grid renders a `VStack` whose spacing REPLACES the panel's own. \
            The default (10) would silently tighten iPhone PORTRAIT — the primary surface — in \
            exchange for nothing, because portrait does not reflow at all.
            """)
        }
    }

    /// ⛔ THE HALF A GRID COUNT CANNOT SEE (claim 2): both rows must be inside, or the panel
    /// renders one half-width choice beside nothing.
    func testBothDeliveryRowsSitInsideTheGrid() throws {
        let body = try masterPanelBody()
        let ranges = gridRanges(in: body)
        for fragment in ["labeledRow(\"Target\")", "labeledRow(\"Tone\")"] {
            let hits = body.indices.filter { body[$0].contains(fragment) }
            XCTAssertEqual(hits.count, 1, """
            expected exactly one `\(fragment)` row in `masterPanel`, found \(hits.count). If the \
            row was renamed or moved on purpose, move this guard with it in the same commit.
            """)
            for i in hits {
                XCTAssertTrue(ranges.contains { $0.contains(i) }, """
                `\(fragment)` sits OUTSIDE the `AdaptiveCardGrid` in `masterPanel`. It renders \
                full width while its sibling is a half-width cell — the ragged layout the \
                sibling reflow guards condemn. Put both delivery rows in the one grid.
                """)
            }
        }
    }

    /// ⛔ THE OTHER DIRECTION, and the likelier regression (claim 3). Each of these wants the
    /// full measure or is a churn-isolating leaf; a half-width cell breaks either property.
    func testTheLeavesAndFullMeasureRowsStayOutsideTheGrid() throws {
        let body = try masterPanelBody()
        let ranges = gridRanges(in: body)
        for fragment in ["MasterVolumeField()", "MasterLoudnessGrid()", "AudioTimingRow(",
                         "panicAllNotesOff()", "masterDoorButton"] {
            let hits = body.indices.filter { body[$0].contains(fragment) }
            guard !hits.isEmpty else {
                XCTFail("`\(fragment)` is gone from `masterPanel`. If it moved on purpose, move "
                        + "this guard with it — do not leave a check for a row that is no "
                        + "longer there.")
                continue
            }
            XCTAssertFalse(hits.contains { i in ranges.contains { $0.contains(i) } }, """
            `\(fragment)` is now INSIDE the `AdaptiveCardGrid` in `masterPanel`.

            At a regular width that renders it as a half-width cell beside a parameter row. \
            The volume field and the loudness numbers are churn-isolating leaves (their whole \
            point is re-rendering alone), the timing row and the caption wrap, and the release/\
            door buttons are full-width chrome. All of them stay outside the reflow grid.
            """)
        }
    }

    /// Half-open index ranges covering each `AdaptiveCardGrid { … }` in `body`, keyed on
    /// INDENTATION: the grid opens at some column and closes at the first later line that is a
    /// bare `}` in that same column. Safe only because it runs over one already-extracted panel
    /// body (the `MoodPanelReflowsTests` helper, with its single-line-grid failure kept).
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
                an `AdaptiveCardGrid` in `masterPanel` has no closing `}` at its own \
                indentation: \(body[i].trimmingCharacters(in: .whitespaces))

                This scan brackets each grid by indentation and assumes it spans several lines. \
                A single-line grid is not a defect — it just cannot be bracketed this way. Split \
                it across lines, or replace this helper with a brace-depth counter.
                """)
                continue
            }
            out.append(i..<close)
        }
        return out
    }

    /// Lines of `masterPanel`, from its declaration to the next member declaration. Scoping
    /// matters: `AdaptiveCardGrid` legitimately appears in four other panels in this file, and a
    /// whole-file scan would pass on those while `masterPanel` itself had been reverted.
    private func masterPanelBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var masterPanel") }) else {
            XCTFail("`masterPanel` is gone from \(Self.studio) — that is the output surface "
                    + "behind the Master door. If it was renamed, move this guard with it.")
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    private ") } ?? lines.endIndex
        return Array(lines[start..<end])
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels up).
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

    /// Comment-stripped lines of `path`, via the ONE stripper (`SourceText.codeOnly`, §2 —
    /// line count preserved). Measured PROPHYLAKTISCH (0 of 8 verdicts flip raw vs stripped,
    /// both trees): the grid's doc comment inside `masterPanel` names `spacing: 14` and this
    /// file, but not the word the grid count filters on. It stays stripped anyway — the next
    /// comment edit inside the panel is exactly what would make an unstripped count lie.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return SourceText.codeOnly(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
