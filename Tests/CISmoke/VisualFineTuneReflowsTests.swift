// VisualFineTuneReflowsTests.swift
// Echoel — #292 Slice 4. The visual fine-tune rows reflow to two columns, and BOTH surfaces that
// render them keep their own portrait rhythm.
//
// WHAT WAS WRONG. `visualAdjustFields` renders seven `EchoelValueField` rows and was one column at
// ANY width — the same defect `SoundPanelReflowsTests` and `MoodPanelReflowsTests` describe for
// their panels: the field is `HStack { label; Spacer(minLength: 8); valueBox }`, so a wide row puts
// a name against the far left edge and the number it names against the far right. (⛔ That sentence
// said "inside a container offering `maxWidth: .infinity`" and it was inherited from
// `SoundPanelReflowsTests` without being re-read against the SECOND host this slice adds: the
// overlay is capped at `.frame(maxWidth: 560)`. The defect is the same; the reason given for it was
// only half true, which matters because that cap is what finding 3 below turns on.)
//
// ⭐ WHAT MAKES THIS SLICE DIFFERENT FROM THE OTHER TWO, and the reason it is worth a file of its
// own rather than a third copy: this ViewBuilder has **two hosts with different container
// spacings**. `visualPanel` renders it inside `EchoelPanel` (`spacing: 14`); `visualVJOverlay` —
// the stage overlay over the fullscreen visual — renders it inside its own `VStack(spacing: 8)`,
// height-capped at 360 pt. In ONE column an `AdaptiveCardGrid` renders a `VStack` whose spacing
// REPLACES the host's, so a fixed literal inside the ViewBuilder would silently re-space one of
// the two in PORTRAIT — the primary surface, which does not reflow at all and would therefore pay
// the whole cost for none of the benefit. Hence `spacing` is a PARAMETER with NO DEFAULT, and the
// sharpest claim in this file is claim 4: an argument no call site writes appears in no diff
// (#440/#443), so a default would reintroduce exactly that risk invisibly.
//
// ⛔ AND THE SECOND HOST HAS NO DOOR — measured, and the whole ⭐ block above read as if it did.
// `visualVJOverlay` is mounted in exactly one place, inside `.fullScreenCover(isPresented:
// $showVisual)`, and `showVisual` has NO writer of `true` anywhere in `Sources/`: word-bounded, the
// flag has two writers in code, its own `@State` initialiser and the close button, and both assign
// `false`. So the overlay cannot be reached today (that is open task #270; `NoDoorlessStudioViewsTests`
// cites it as the live proof of what reference-counting cannot catch).
//
// ⭐ THAT MAKES THE NO-DEFAULT RULE ASYMMETRIC RATHER THAN WEAKER, and naming the asymmetry is the
// point: hardcoding **8** re-spaces the REACHABLE panel — a live cost, today, on the primary
// surface — while hardcoding **14** re-spaces only a surface nobody can open. The ⭐ block above
// silently assumed the first direction when it said "the primary surface … would pay the whole
// cost". So the parameter protects something live in exactly ONE direction, and is bookkeeping for
// the day the door returns in the other. Both halves are worth keeping; only one is worth calling
// a defence.
//
// ⚠️ WHAT THIS FILE GUARDS, and what it deliberately does NOT.
//   1. Two grids exist in `visualAdjustFields` and both pass the PARAMETER, not a number.
//   2. All six fine-tune rows are INSIDE a grid. A surface where some rows reflow and others do
//      not is worse than one that never reflows — the ragged half-width/full-width column
//      `MoodPanelReflowsTests` condemns, and counting grids alone cannot see it.
//   3. Energy, the disclosure Button and the Detail caveat caption stay OUTSIDE. This is the half
//      a grep-for-`AdaptiveCardGrid` is blind to, and it is the likelier regression: the obvious
//      tidy-up is to sweep everything into one grid, which would put a wrapping sentence into a
//      half-width cell beside a parameter row.
//   4. `spacing` is an argument with no default.
//   5. Both call sites pass a spacing, and the overlay's argument matches the overlay's OWN stack.
//   6. The overlay is still doorless — the PREMISE claims 5 and the honest-limit block rest on.
//      A COUNTERWEIGHT, not a regression: green before this commit and after it. It exists so
//      that re-dooring `showVisual` goes red and pulls the doorlessness prose into the same
//      commit instead of leaving it quietly false (#456). Its failure message names the NINE
//      files that carry that prose today rather than a count, because a count of scattered
//      sentences is a number this repo has learned not to write down.
//
// It does NOT re-assert that `EchoelPanel`'s content spacing is 14 — `SoundPanelReflowsTests`
// owns that fact (`testThePanelStillUsesThatSpacingForItsContent`), and a second copy of a
// constant is how two guards drift into disagreeing about the same thing (#416). If the panel
// rhythm changes, THAT file goes red and this file's `14` is in the same commit.
//
// ⛔ WHICH CLAIMS CAN ACTUALLY FAIL, said plainly rather than dressed up as five regressions —
// and the honest answer is less flattering than the obvious one. On the pre-slice tree the member
// was `private var visualAdjustFields: some View`, so `fineTuneBody()` cannot find its anchor and
// claims 1, 2 AND 3 all fail loudly (it throws rather than skipping, the #442 rule). That makes
// claim 3 look like a regression, and it is NOT one: the PROPERTY it asserts held before this
// slice too (nothing was in a grid, so nothing wrong was in a grid). It is a COUNTERWEIGHT against
// the sweep-everything-into-one-grid tidy-up, and its pre-slice redness is an artefact of the
// signature change, not evidence it caught anything. Claims 4 and 5 do not use the anchor and are
// red for their own reasons (no such declaration, no such call sites).
//
// ⛔ HONEST LIMIT — read before trusting a green. Every claim here is a SOURCE SCAN. SwiftUI
// layout is not reachable from this bundle, so "two columns are legible on a device" and "the
// column break lands between sensible parameters" are device checks, open on the inline panel.
//
// ⛔ AND THE THIRD ITEM IN THAT LIST WAS AN IMPOSSIBLE FOUNDER ASK, which is worse than a vague
// one. It read: "the overlay still fits its cap in landscape … Device-verify is open, landscape
// and the VJ overlay specifically." Nobody can open the VJ overlay (claim 6), so that request
// could never be satisfied — it would have cost a device session to discover that, and it sat in
// the register a session reads when triaging the NEEDS-FOUNDER-VERIFY backlog. Withdrawn rather
// than reworded: the overlay's device check becomes real on the day it gets a door, and the day it
// gets a door claim 6 goes red and says so.
//
// ⚠️ AND THE OVERLAY'S BINDING CAP IS ITS WIDTH, NOT ITS HEIGHT — the first draft of the line
// above named only `.frame(maxHeight: 360)`, which is the cap you notice, not the one that
// decides whether two columns read. `visualVJOverlay` is also `.frame(maxWidth: 560)`. From the
// shipped constants: content width `560 − 28` (its `.padding(14)`) = 532; two `.flexible()`
// columns with `AdaptiveCardGrid`'s 10 pt gutter = **261 pt each**. An `EchoelValueField` row
// below the accessibility threshold costs `valueWidth(150) + HStack spacing(12) + Spacer
// minLength(8) + the box's own padding` before the label gets anything, so the label band is
// **tight but workable at default type and narrow at large type** — and `columns` only falls back
// to 1 at `typeSize.isAccessibilitySize`, so a LARGE-but-not-accessibility size (`.xxxLarge`)
// still draws two columns into 261 pt with a `@ScaledMetric` box that has grown ~35 %. The inline
// panel is uncapped and has no such band (~425 pt columns in landscape on a Pro Max); this
// exposure is specific to the overlay and therefore LATENT, not live — the first draft called it
// "new", which reads as shipped. Numbers are ARITHMETIC FROM CONSTANTS, not a measurement — the
// point is that the band is nameable and belongs in front of a device on the day the overlay has
// one, not that it is proven to break.

import Foundation
import XCTest

final class VisualFineTuneReflowsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The six rows behind "Fine tune", by their label literal.
    private static let fineTuneLabels = ["Intensity", "Detail", "Motion", "Spread",
                                         "Hue", "Saturation"]

    // MARK: - The reflow

    /// ⭐ Claim 1. Two grids, and both carry the parameter rather than a number — a literal here
    /// is the whole defect this slice exists to prevent, one surface deep.
    func testTheFineTuneRowsSitInGridsThatCarryTheParameter() throws {
        let body = try fineTuneBody()
        let grids = body.filter { $0.contains("AdaptiveCardGrid") }
        XCTAssertEqual(grids.count, 2, """
        `visualAdjustFields` has \(grids.count) `AdaptiveCardGrid` groups, expected exactly 2.

        The six fine-tune rows are split across two grids so the Detail caveat caption can sit \
        BETWEEN them at full width. Two cards fill exactly one two-column row, so the split costs \
        nothing to look at. If they were merged, the caption lands in a half-width cell — read \
        the doc block on `visualAdjustFields(spacing:)` before changing this number.
        """)
        for call in grids {
            XCTAssertTrue(call.contains("spacing: spacing"), """
            an `AdaptiveCardGrid` in `visualAdjustFields` passes something other than the \
            `spacing` PARAMETER: \(call.trimmingCharacters(in: .whitespaces))

            This ViewBuilder has two hosts with different container spacings (14 in `EchoelPanel`, \
            8 in `visualVJOverlay`). In one column the grid's spacing REPLACES the host's, so a \
            literal here silently re-spaces one of the two surfaces in portrait — where nothing \
            reflows and there is therefore no benefit to pay for.
            """)
        }
    }

    /// ⛔ Claim 2 — the half a grid count cannot see. Wrapping SOME rows is not a smaller version
    /// of this slice, it is a different and worse layout.
    func testEveryFineTuneRowIsInsideAGrid() throws {
        let body = try fineTuneBody()
        let ranges = gridRanges(in: body)
        for label in Self.fineTuneLabels {
            let hits = body.indices.filter { body[$0].contains("label: \"\(label)\"") }
            XCTAssertEqual(hits.count, 1, """
            expected exactly one `label: "\(label)"` row in `visualAdjustFields`, found \
            \(hits.count). If the row was renamed or removed, move this guard with it.
            """)
            for i in hits {
                XCTAssertTrue(ranges.contains { $0.contains(i) }, """
                the "\(label)" row sits OUTSIDE every `AdaptiveCardGrid` in \
                `visualAdjustFields`.

                It renders full width while its neighbours are two-up. Put it in one of the two \
                grids, or — if it genuinely belongs at full width — say so where it sits and \
                remove it from `fineTuneLabels` here, in the same commit.
                """)
            }
        }
    }

    /// ⛔ Claim 3 — the COUNTERWEIGHT, and the likelier regression. Green before this slice and
    /// after it: it exists so the obvious tidy-up ("put everything in one grid") goes red.
    ///
    /// Energy is separated from the six by a caption and the disclosure Button, so a grid around
    /// it would order a SINGLE card — and a grid that orders one card orders nothing (#359 step 2
    /// deleted one for exactly that reason). The Detail caveat wraps and wants the full measure.
    func testEnergyTheDisclosureAndTheCaveatStayOutsideTheGrids() throws {
        let body = try fineTuneBody()
        let ranges = gridRanges(in: body)
        for fragment in ["label: \"Energy\"", "showVisualFineTune.toggle()",
                         "Text(\"Detail shapes"] {
            let hits = body.indices.filter { body[$0].contains(fragment) }
            guard !hits.isEmpty else {
                XCTFail("`\(fragment)` is gone from `visualAdjustFields`. If it moved on purpose, "
                        + "move this guard with it — do not leave a check for something that is "
                        + "no longer there.")
                continue
            }
            XCTAssertFalse(hits.contains { i in ranges.contains { $0.contains(i) } }, """
            `\(fragment)` is now INSIDE an `AdaptiveCardGrid` in `visualAdjustFields`.

            At a regular width that renders it as a half-width cell beside a parameter row. \
            Energy is alone between two full-width children (a grid of one card orders nothing), \
            the disclosure Button carries a 44 pt tap target, and the Detail caveat wraps. All \
            three want the full measure.
            """)
        }
    }

    // MARK: - The parameter

    /// ⭐ Claim 4 — the sharpest one. A default would make the risk invisible: an argument no
    /// call site writes appears in no diff. Same reasoning as #443 for `EchoelFXView.field`.
    func testTheSpacingIsAnArgumentWithNoDefault() throws {
        let code = try studioLines()
        let decls = code.filter { $0.contains("func visualAdjustFields(") }
        XCTAssertEqual(decls.count, 1, """
        expected exactly one declaration of `visualAdjustFields(spacing:)`, found \(decls.count).
        """)
        guard let decl = decls.first else { return }
        XCTAssertTrue(decl.contains("spacing: CGFloat"), """
        `visualAdjustFields` no longer takes a `spacing: CGFloat`: \
        \(decl.trimmingCharacters(in: .whitespaces))

        Its two hosts space their content differently (14 vs 8). Without the parameter the grids \
        inside would impose one rhythm on both in portrait — see the ⭐ block on the declaration.
        """)
        XCTAssertFalse(decl.contains("spacing: CGFloat ="), """
        `spacing` has grown a DEFAULT: \(decl.trimmingCharacters(in: .whitespaces))

        A defaulted argument is written by no call site and therefore appears in no diff. That is \
        exactly how 33 FX rows silently inherited the wrong grid before #443. Make each host say \
        its own number.
        """)
    }

    /// ⭐ Claim 5 — the coupling that can drift silently: the overlay's argument against the
    /// overlay's OWN stack. The panel's `14` is checked here only for presence; the fact that 14
    /// is `EchoelPanel`'s content spacing belongs to `SoundPanelReflowsTests`, on purpose (#416).
    func testBothHostsPassTheirOwnContainerSpacing() throws {
        let code = try studioLines()
        let calls = code.filter { $0.contains("visualAdjustFields(spacing:") && !$0.contains("func ") }
        XCTAssertEqual(calls.count, 2, """
        expected exactly two call sites of `visualAdjustFields(spacing:)` — the inline \
        `visualPanel` and the fullscreen `visualVJOverlay` — found \(calls.count).

        Both surfaces render the SAME definitions so they can never drift apart; a third caller \
        needs its own container spacing decided, not copied.
        """)
        let arguments = Set(calls.map { $0.trimmingCharacters(in: .whitespaces) })
        XCTAssertTrue(arguments.contains("visualAdjustFields(spacing: 14)"), """
        no call site passes `spacing: 14`. That is `EchoelPanel`'s content spacing, and \
        `visualPanel` renders inside one — passing anything else re-spaces the inline panel in \
        portrait. (`SoundPanelReflowsTests` owns the claim that `EchoelPanel` still uses 14; if \
        that number moved, this one moves in the same commit.)
        """)
        XCTAssertTrue(arguments.contains("visualAdjustFields(spacing: 8)"), """
        no call site passes `spacing: 8`, the spacing of `visualVJOverlay`'s own stack.
        """)

        // The other end of the coupling, and the one nothing else in this bundle holds.
        //
        // ⛔ IT WALKS BACK TO THE HOSTING STACK RATHER THAN SCANNING THE MEMBER. The first draft
        // asserted the literal appeared SOMEWHERE in `visualVJOverlay`. It is unique there today,
        // but that is luck: `VStack(alignment: .leading, spacing: 8)` occurs several times
        // elsewhere in this file, so a second one arriving in the overlay would let someone
        // re-space the ACTUAL hosting stack while the claim stayed green — precisely the drift
        // this file's header calls "the coupling that can drift silently".
        let overlay = try memberBody(startingWith: "private var visualVJOverlay")
        guard let callIndex = overlay.firstIndex(where: {
            $0.contains("visualAdjustFields(spacing:") && !$0.contains("func ")
        }) else {
            XCTFail("`visualVJOverlay` no longer calls `visualAdjustFields(spacing:)`. If the "
                    + "overlay was removed (open task #270), delete this half with it.")
            return
        }
        guard let stackIndex = overlay[..<callIndex].lastIndex(where: { $0.contains("VStack(") })
        else {
            XCTFail("no `VStack(` above the `visualAdjustFields(spacing:)` call in "
                    + "`visualVJOverlay` — this half assumes the call has a stack host.")
            return
        }
        XCTAssertTrue(overlay[stackIndex].contains("spacing: 8"), """
        the stack HOSTING the fine-tune rows in `visualVJOverlay` is \
        `\(overlay[stackIndex].trimmingCharacters(in: .whitespaces))`, which does not carry \
        `spacing: 8` — while the call below it still passes 8.

        In one column the grids inside adopt the argument, so the fine-tune rows would sit at a \
        different rhythm from every other child of the overlay; in two columns the seam between \
        the two grids would become visible. Move both, or neither.
        """)
    }

    // MARK: - The premise the rest of this file rests on

    /// ⭐ Claim 6 — the COUNTERWEIGHT, and the premise everything above quietly assumed. Green
    /// before this commit and after it: `showVisual` has had no writer of `true` since the tools
    /// grid that set it was deleted, so the whole VJ control panel is unreachable (open task
    /// #270). That fact is load-bearing in two directions and was written down in neither.
    ///
    /// It decides what claims 1–5 MEAN: passing 8 to a surface nobody can open is bookkeeping,
    /// while passing 14 to the inline panel is a live guarantee. And it decides what this file may
    /// ASK OF A HUMAN — the honest-limit block used to request a landscape device check of the
    /// overlay, which nobody could perform.
    ///
    /// So the assertion runs the other way round from the rest of the file: it is here to go RED
    /// when the overlay is RE-DOORED, which is a good change and exactly the moment the prose
    /// calling it "latent" or "doorless (#270)" becomes false in nine files at once (#456).
    ///
    /// The scan is word-bounded on purpose: `showVisualSettings`, `showVisualFineTune` and
    /// `showVisualControls` all share the prefix and are live, settable flags. A `contains` would
    /// collect them and this claim would fail on correct code.
    ///
    /// ⚠️ `SourceText.codeOnly` IS PROPHYLACTIC FOR THIS CLAIM, measured rather than assumed
    /// (the over-claim #484/#485 each retracted once and #486 twice): raw vs stripped differ in
    /// **0 of 4** verdicts across both trees, because nothing in this repo writes the assignment
    /// form in prose today. It stops being prophylactic the moment somebody does — a retraction
    /// quoting `showVisual` followed by `= true` would be collected as a writer and turn this
    /// claim RED on correct code. That is why the notes this commit adds describe the writers
    /// instead of quoting one.
    func testTheVJOverlayIsStillDoorless() throws {
        let writers = try studioLines().filter { line in
            flagAssignments(in: line)
        }
        // #367: anchor first. A rename would empty the list and let the loop below pass on
        // nothing, which is how a guard stops being able to fail for its stated reason.
        XCTAssertFalse(writers.isEmpty, """
        no assignment to `showVisual` in \(Self.studio) — the flag was renamed or removed.

        Re-anchor this claim on the new name; do NOT delete it. If the fullscreen visual cover \
        went away entirely, delete claim 5's overlay half and this one together, and sweep the \
        "doorless (#270)" prose in the same commit.
        """)
        for line in writers {
            XCTAssertTrue(line.contains("= false"), """
            `showVisual` now has a writer that is not `= false`: \
            \(line.trimmingCharacters(in: .whitespaces))

            That re-doors `visualVJOverlay` — a real capability, and a welcome one. It also makes \
            a pile of prose false in one step, so update it in THIS commit: the "doorless"/"latent"\
             notes on `visualPresetRow` and `visualAdjustFields(spacing:)`, the ⛔ blocks in this \
            file's header, `NoDoorlessStudioViewsTests` (which cites this overlay as its live \
            proof), `SectionHeadingIsOneTreatmentTests`, `WeatherIsAMoodRubricTests`, \
            `TapTargetFloorTests`, `VisualLookTruthTests`, the un-settable-slot note in \
            `ResetSoundClearsWhatTheLaunchLineReportsTests` (the modal budget gains a live slot), \
            CLAUDE.md's #292-Slice-4 paragraph, and open task #270. The overlay's landscape \
            device check becomes real at the same moment — see the honest-limit block above.
            """)
        }
    }

    /// True when `line` assigns to the `showVisual` flag itself — `=` or `.toggle()`, and never a
    /// longer identifier that merely starts with the same characters.
    private func flagAssignments(in line: String) -> Bool {
        let flag = "showVisual"
        var searchStart = line.startIndex
        while let range = line.range(of: flag, range: searchStart..<line.endIndex) {
            searchStart = range.upperBound
            let tail = line[range.upperBound...]
            // A longer identifier (`showVisualControls`) — not this flag.
            if let next = tail.first, next.isLetter || next.isNumber || next == "_" { continue }
            let rest = tail.drop(while: { $0 == " " })
            if rest.hasPrefix(".toggle()") { return true }
            if rest.hasPrefix("="), !rest.hasPrefix("==") { return true }
        }
        return false
    }

    // MARK: - Helpers

    /// Half-open index ranges covering each `AdaptiveCardGrid { … }`, keyed on INDENTATION: the
    /// grid opens at some column and closes at the first later line that is a bare `}` in that
    /// same column. Every child sits deeper, so no child can be mistaken for the close. Safe here
    /// because it is scoped to one already-extracted member body — it would not be over a
    /// 9000-line file.
    ///
    /// ⛔ IT ASSUMES A MULTI-LINE GRID and says so out loud rather than failing quietly. A
    /// one-line grid produces no range, and a silent skip would make claim 2 report "sits OUTSIDE
    /// every grid" about a row that is visibly inside one — a guard failing with the wrong
    /// diagnosis costs more than one that does not fail, because the reader goes looking for a
    /// layout regression that never happened. (Borrowed, with its lesson, from
    /// `MoodPanelReflowsTests`.)
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
                an `AdaptiveCardGrid` in `visualAdjustFields` has no closing `}` at its own \
                indentation: \(body[i].trimmingCharacters(in: .whitespaces))

                This scan brackets each grid by indentation and therefore assumes the grid spans \
                several lines. A single-line grid is not a defect — it just cannot be bracketed \
                this way. Split it across lines, or replace this helper with a brace counter.
                """)
                continue
            }
            out.append(i..<close)
        }
        return out
    }

    private func fineTuneBody() throws -> [String] {
        try memberBody(startingWith: "private func visualAdjustFields(")
    }

    /// The lines of the member whose declaration contains `anchor`, brace-matched from its
    /// declaration to its closing brace.
    ///
    /// Brace-matched rather than "up to the next `private `" (the older house pattern) because
    /// this member's declaration carries `@ViewBuilder` first, so the modifier-prefix rule that
    /// works for `moodPanel` does not apply here — and a member scan that ends at the wrong line
    /// silently widens or narrows every claim above it. Comments are stripped first, so a brace
    /// inside prose cannot close the body.
    private func memberBody(startingWith anchor: String) throws -> [String] {
        let lines = try studioLines()
        guard let start = lines.firstIndex(where: { $0.contains(anchor) }) else {
            XCTFail("""
            no member matching `\(anchor)` in \(Self.studio).

            This guard covers the visual fine-tune rows and the overlay that shares them. If the \
            member was renamed, move the guard with it — do NOT relax the anchor, which would \
            leave a test that passes on nothing.
            """)
            throw AnchorMissing()
        }
        var depth = 0
        var out: [String] = []
        for i in lines[start...].indices {
            out.append(lines[i])
            depth += lines[i].filter { $0 == "{" }.count
            depth -= lines[i].filter { $0 == "}" }.count
            if depth == 0, i > start { return out }
        }
        XCTFail("`\(anchor)` never closes in \(Self.studio) — the brace scan ran off the end.")
        throw AnchorMissing()
    }

    private struct AnchorMissing: Error {}

    /// `EchoelStudioView.swift` with comments blanked, split into lines. Load-bearing here twice
    /// over: this file's own subject matter is quoted at length in that file's ⛔/⭐ blocks
    /// (`AdaptiveCardGrid`, `spacing: 14`, `visualAdjustFields`), so a raw scan would count prose
    /// as code — and blanking rather than deleting keeps the indices usable across helpers.
    private func studioLines() throws -> [String] {
        let url = try repoRoot().appendingPathComponent(Self.studio)
        let text = try String(contentsOf: url, encoding: .utf8)
        return SourceText.codeOnly(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
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
}
