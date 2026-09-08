// VisualFineTuneReflowsTests.swift
// Echoel — #292 Slice 4. The visual fine-tune rows reflow to two columns, and BOTH surfaces that
// render them keep their own portrait rhythm.
//
// WHAT WAS WRONG. `visualAdjustFields` rendered seven `EchoelValueField` rows (nine since #853 —
// Texture + Glitter joined the second grid) and was one column at
// ANY width — the same defect `SoundPanelReflowsTests` and `MoodPanelReflowsTests` describe for
// their panels: the field is `HStack { label; Spacer(minLength: 8); valueBox }`, so a wide row puts
// a name against the far left edge and the number it names against the far right. (⛔ That sentence
// said "inside a container offering `maxWidth: .infinity`" and it was inherited from
// `SoundPanelReflowsTests` without being re-read against the SECOND host this slice adds: the
// overlay is capped at `.frame(maxWidth: 560)`. The defect is the same; the reason given for it was
// only half true, which matters because that cap is what finding 3 below turns on.)
//
// ⭐ WHAT MADE THIS SLICE DIFFERENT FROM THE OTHER TWO: this ViewBuilder had **two hosts with
// different container spacings**. `visualPanel` renders it inside `EchoelPanel` (`spacing: 14`);
// `visualVJOverlay` — the stage overlay over the fullscreen visual — rendered it inside its own
// `VStack(spacing: 8)`, height-capped at 360 pt. In ONE column an `AdaptiveCardGrid` renders a
// `VStack` whose spacing REPLACES the host's, so a fixed literal inside the ViewBuilder would
// silently re-space one of the two in PORTRAIT.
//
// ⛔ THERE IS ONE HOST NOW (#1069 deleted the overlay with the fullscreen cover), AND THE
// PARAMETER STAYS. That is not sentiment: with one caller, a default is the tempting cleanup and
// the invisible one — an argument no call site writes appears in no diff (#440/#443), so the next
// second host would inherit the Field panel's rhythm without anyone deciding it. Claim 4 is
// unchanged and is now the sharpest thing in the file; claim 5 keeps the surviving half.
//
// ⛔ THE SECOND HOST'S DOOR HISTORY — DOORLESS, THEN DOORED (#747), THEN MOVED (#1067) — ENDED
// WITH THE HOST (#1069). It is kept in three lines rather than deleted, because the SHAPE recurs:
// `visualVJOverlay` was mounted only inside `.fullScreenCover(isPresented: $showVisual)`, a flag
// with no writer of `true` (open task #270); #747 gave it a visible "Full screen" button; #1067
// pointed that same button at the FLOATING WINDOW's size; #1069 deleted the cover and the overlay
// with it, on the founder's *"alles zu einem Ding zusammen gefasst"*. The button is still there
// and still labelled — claim 6 is about THE DOOR, which survived all four moves.
//
// ⚠️ THE LESSON THAT OUTLIVES IT: a surface can go doorless → doored → doorless → deleted inside
// six weeks, and this header was WRONG IN BOTH DIRECTIONS along the way. That is why the claims
// are anchored on the DOOR and the CALL SITE rather than on a flag — a flag is a spelling, and a
// spelling is what stops existing.
//
// ⛔ THE ASYMMETRY ARGUMENT IS RETIRED WITH ITS SECOND HOST. It said hardcoding **8** would
// re-space a surface nobody can open while hardcoding **14** re-spaces the reachable panel. With
// one host there is no asymmetry — and the case for the parameter is now the plain #440/#443 one
// above, which is stronger, not weaker.
//
// ⚠️ WHAT THIS FILE GUARDS, and what it deliberately does NOT.
//   1. Two grids exist in `visualAdjustFields` and both pass the PARAMETER, not a number.
//   2. All nine fine-tune rows are INSIDE a grid (six at #292 Slice 4; Texture + Glitter
//      joined with #853, Structure with #853B). A surface where some rows reflow and others do
//      not is worse than one that never reflows — the ragged half-width/full-width column
//      `MoodPanelReflowsTests` condemns, and counting grids alone cannot see it.
//   3. Energy, the disclosure Button and the Detail caveat caption stay OUTSIDE. This is the half
//      a grep-for-`AdaptiveCardGrid` is blind to, and it is the likelier regression: the obvious
//      tidy-up is to sweep everything into one grid, which would put a wrapping sentence into a
//      half-width cell beside a parameter row.
//   4. `spacing` is an argument with no default.
//   5. The one call site passes its own container's spacing, and the argument stays required.
//      (⛔ It read "Both call sites … the overlay's OWN stack" until #1069 deleted the overlay.)
//   6. The FULLSCREEN DOOR exists exactly once and is labelled, and no SECOND fullscreen chrome
//      exists. ⭐ REWRITTEN THREE TIMES — #747 turned it from "the overlay is still doorless" into
//      "there is a door", #1067 moved that door from the cover to the floating window's size, and
//      #1069 replaced the expiring `showVisual` counterweight with the stronger question it was
//      a proxy for (a vanished flag scans vacuously green forever, #926). The subject is THE
//      DOOR, not the flag it
//      writes: zero call sites = a lost capability, two = a second entrance to one surface (the
//      #290 trap — a second `bioPanel` door shipped 2026-07-12 and was pulled two days later),
//      and it must stay a labelled Button rather than a hidden gesture (WCAG 2.2). A counterweight
//      pins that the OLD cover really is unreachable, and it is written to expire with S3c.
//      The claim's own doc carries the full history. **The guard working looks like a red, not
//      like a green.**
//   7. The donut normalisation stays DELETED, and the reason changed under it. It used to be
//      paired with the cover's door (`XCTAssertNotEqual`) because the donut look was reachable
//      only from the cover's top-bar glyph. #1065 gave that look its OWN switch in the Field
//      panel, so the two facts came apart, and #1067 made the old pairing read
//      `NotEqual(false, false)` — red on a tree where the look is MORE reachable, not less. What
//      survives is the half that was ever a regression guard: restoring
//      `normaliseUnreachableDonutMode()` would stamp a player's chosen look off on every launch
//      (the `LeadMixDoorAndNormalisationTests` failure class). A counterweight echoes "the switch
//      exists" from `TheDonutLookSurvivesTheCoverTests`, which owns that fact, so this claim
//      cannot pass over a tree where switch and normaliser vanished together.
//      Two decisions from #747 still stand and are not re-litigated here: the "Donuts" pill was
//      NOT restored to `visualLookStrip` (a second control for one state — item 6's trap), and
//      `StudioDefaultKeys.visualSpectralDonuts` stays `false`, which states a CHOICE (a fresh
//      install opens on the Metal field, the identity look) rather than a limitation.
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
// ⛔ THE OVERLAY'S DEVICE CHECK WAS REAL FOR ONE ERA (#747) AND IS WITHDRAWN AGAIN (#1067). The
// history is the useful part, because this ask has now been impossible, possible, and impossible
// again. It was first written while NOBODY COULD OPEN THE OVERLAY — an impossible ask is worse
// than a vague one, because it costs a device session to discover, sitting in the register a
// session reads when triaging the NEEDS-FOUNDER-VERIFY backlog. It was WITHDRAWN rather than
// reworded, with a note saying it becomes real on the day the overlay gets a door. #747 built
// that door, claim 6 went red and said so, and the ask was reinstated. #1067 moved the door to
// the floating window, so the overlay is unreachable once more and the ask is withdrawn a second
// time rather than left to burn a session. **Do not reinstate it: S3c deletes the overlay.**
//
// **NEEDS-FOUNDER-VERIFY (#1067), and it replaces the one above:** tap Field → "Full screen" and
// check that the FLOATING WINDOW fills the display rather than a second screen appearing over it
// — one surface with one chrome bar, which is the whole point of the slice. The old cover's
// landscape column check and the `.onChange(of: showVisual)` GPU dance are no longer reachable
// and must not be asked for.
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

    /// The nine rows behind "Fine tune", by their label literal (Texture/Glitter since #853,
    /// Structure since #853B).
    private static let fineTuneLabels = ["Intensity", "Detail", "Motion", "Spread",
                                         "Hue", "Saturation", "Texture", "Glitter",
                                         "Structure"]

    // MARK: - The reflow

    /// ⭐ Claim 1. Two grids, and both carry the parameter rather than a number — a literal here
    /// is the whole defect this slice exists to prevent, one surface deep.
    func testTheFineTuneRowsSitInGridsThatCarryTheParameter() throws {
        let body = try fineTuneBody()
        let grids = body.filter { $0.contains("AdaptiveCardGrid") }
        XCTAssertEqual(grids.count, 2, """
        `visualAdjustFields` has \(grids.count) `AdaptiveCardGrid` groups, expected exactly 2.

        The nine fine-tune rows are split across two grids so the Detail caveat caption can sit \
        BETWEEN them at full width. Two cards fill exactly one two-column row, so the split costs \
        nothing to look at. If they were merged, the caption lands in a half-width cell — read \
        the doc block on `visualAdjustFields(spacing:)` before changing this number.
        """)
        for call in grids {
            XCTAssertTrue(call.contains("spacing: spacing"), """
            an `AdaptiveCardGrid` in `visualAdjustFields` passes something other than the \
            `spacing` PARAMETER: \(call.trimmingCharacters(in: .whitespaces))

            This ViewBuilder had two hosts with different container spacings (14 in `EchoelPanel`, \
            8 in `visualVJOverlay` until #1069 deleted the overlay). In one column the grid's \
            spacing REPLACES the host's, so a \
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
    /// Energy is separated from the nine by a caption and the disclosure Button, so a grid around
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

    /// ⭐ Claim 5 — ⛔ THE COUPLING THIS CLAIM WAS ABOUT NO LONGER HAS TWO ENDS (#1069).
    ///
    /// It asserted that BOTH hosts of `visualAdjustFields(spacing:)` pass their own container's
    /// spacing — `visualPanel` 14, `visualVJOverlay` 8 — and walked back from the overlay's call
    /// to its hosting `VStack` to prove the argument matched the stack. That was the sharpest
    /// half of this file.
    ///
    /// S3c deleted `visualVJOverlay` with the fullscreen cover, and the previous version of this
    /// claim said in its own `XCTFail` what to do then: *"If the overlay was removed (open task
    /// #270), delete this half with it."* Followed literally. Keeping it would have been red on a
    /// correct tree in the blocking bundle — the #650/#960 shape, three times recorded here.
    ///
    /// ⭐ WHAT SURVIVES IS NOT NOTHING, and it is the half that can still regress. One caller is
    /// the moment a defaulted argument looks harmless, and a default no call site writes appears
    /// in no diff (#440/#443) — so the parameter must stay REQUIRED and the one caller must still
    /// pass its own host's number. The `EchoelPanel` = 14 fact stays owned by
    /// `SoundPanelReflowsTests` (#416); this only asks that the call passes it.
    func testTheOneHostPassesItsOwnContainerSpacing() throws {
        let code = try studioLines()
        let calls = code.filter { $0.contains("visualAdjustFields(spacing:") && !$0.contains("func ") }
        XCTAssertEqual(calls.count, 1, """
        expected exactly one call site of `visualAdjustFields(spacing:)` — the inline \
        `visualPanel` — found \(calls.count).

        ZERO means the fine-tune rows left the Field panel; that is a regression against the \
        founder's ask that Field keep every function (#1068), not a tidy-up.

        TWO OR MORE means a second surface renders the same rows again. That is allowed, but the \
        new host's container spacing has to be DECIDED and passed, never copied: in one column \
        the grid's spacing REPLACES the host's, so an inherited number silently re-spaces one of \
        the two. That is exactly the drift this claim used to hold for the deleted VJ overlay.
        """)
        let arguments = Set(calls.map { $0.trimmingCharacters(in: .whitespaces) })
        XCTAssertTrue(arguments.contains("visualAdjustFields(spacing: 14)"), """
        no call site passes `spacing: 14`. That is `EchoelPanel`'s content spacing, and \
        `visualPanel` renders inside one — passing anything else re-spaces the panel in \
        portrait. (`SoundPanelReflowsTests` owns the claim that `EchoelPanel` still uses 14; if \
        that number moved, this one moves in the same commit.)
        """)
        // COUNTERWEIGHT (#367): the argument must stay REQUIRED. With one caller left, adding a
        // default is the tempting cleanup and the invisible one — no diff would show it.
        XCTAssertTrue(code.contains(where: { $0.contains("func visualAdjustFields(spacing: CGFloat)") }), """
        `visualAdjustFields(spacing:)` no longer declares a plain required `CGFloat`. If a \
        DEFAULT was added, remove it: an argument no call site writes appears in no diff \
        (#440/#443), and the next second host would then inherit the Field panel's rhythm \
        without anyone deciding that. If the signature legitimately changed, re-anchor here.
        """)
    }

    // MARK: - The premise the rest of this file rests on

    /// ⭐ Claim 6 — REWRITTEN TWICE, and both rewrites are the point of it having existed.
    ///
    /// #747: it used to assert the VJ overlay was DOORLESS — `showVisual` had no writer of `true`
    /// anywhere in `Sources/`. That was a counterweight built to go RED on the day the overlay was
    /// re-doored, and it fired exactly as designed.
    ///
    /// ⭐ #1067 (S3b) MOVED THE DOOR RATHER THAN REMOVING IT, and that is the distinction this
    /// claim now has to carry. The "Full screen" button is still there, still labelled, still in
    /// `visualPanel` — it no longer raises the fullscreen COVER, it resizes the ONE floating
    /// window (`openFullscreenVisual()`). So `showVisual` HAD zero true-writers again (⛔ and since
    /// #1069 the flag itself is gone with the cover — #1109), and reading
    /// that as "the door was removed" — which the previous message did, in capitals — would be
    /// exactly backwards on a tree that just delivered the founder's ask ("alles zu einem Ding
    /// zusammen gefasst"). The subject of this claim is THE DOOR, not the flag it used to write.
    ///
    /// The cover is now UNREACHABLE BUT PRESENT, deliberately: the Council's three-way split
    /// (`scratchpads/PLAN_ONE_VISUAL_SURFACE_2026-09-07.md` §4) keeps it one slice longer so the
    /// new path can be checked on device before anything irreversible happens. S3c deletes it.
    ///
    /// ⛔ THE `.disabled(visualRecorder.isRecording)` NEEDLE THAT STOOD HERE IS DELETED, ON ITS
    /// OWN INSTRUCTION. It said: "IF THE COVER IS GONE — the `.fullScreenCover` was retired and
    /// the button now writes the floating window's size — this assertion has done its job and
    /// SHOULD be deleted in that same commit". The second half of that condition is met exactly;
    /// the first is met in substance, which is what the hazard cared about — the button can no
    /// longer mount a second `capturesVideo: true` renderer, because it no longer mounts anything.
    /// Keeping it would forbid the fix that makes it unnecessary (#364), which its own paragraph
    /// says in as many words.
    ///
    /// The scan stays word-bounded: `showVisualSettings`, `showVisualFineTune` and
    /// `showVisualControls` share the prefix and are live, settable flags.
    func testTheFullscreenVisualHasExactlyOneVisibleDoor() throws {
        let lines = try studioLines()
        // #367: anchor first. A rename would empty the list and let everything below pass on
        // nothing, which is how a guard stops being able to fail for its stated reason.
        let doors = lines.filter {
            $0.contains("openFullscreenVisual()") && !$0.contains("func ")
        }
        XCTAssertEqual(doors.count, 1, """
        `openFullscreenVisual()` has \(doors.count) call sites in \(Self.studio), not one:
        \(doors.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        ZERO means the fullscreen door is gone and the field can no longer be filled to the \
        screen from the panel. That is a real regression against ship-gate 4 ("visual live + \
        contemplative on device"). If the method was RENAMED, re-anchor this needle here and in \
        `ChromeBudgetFitsTests.testTheStudioSideDoorOnlyEverWritesFullscreen`, which pins what it \
        writes.

        TWO OR MORE means a second door to one surface (#290): a header toggle plus the panel \
        button, say. Pick one and delete the other. The 2026-07-14 removal of `bioPanel`'s second \
        door is the precedent — a second entrance to a surface that already has one reads as a \
        bug to the player long before it reads as convenience.
        """)

        // The cover's own top bar cites WCAG 2.2 against gating controls behind a hidden
        // gesture. A door reachable only from a long-press would satisfy the assertion above and
        // still repeat the defect this codebase names, so the door's LABEL is pinned too.
        let labelled: Bool = lines.contains(where: { $0.contains("Text(\"Full screen\")") })
        XCTAssertTrue(labelled, """
        the "Full screen" label is gone from \(Self.studio) while `openFullscreenVisual()` still \
        has a call site.

        If the door was RENAMED, re-anchor this needle. If it became a gesture (long-press, \
        swipe, a tap on the header monitor), that is the defect the cover's own top bar argues \
        against in its comments: "don't gate controls behind a hidden gesture" (WCAG 2.2). \
        Restore a visible, labelled control.
        """)

        // COUNTERWEIGHT (#367) — ⛔ THE PREVIOUS ONE EXPIRED EXACTLY AS WRITTEN. It scanned for a
        // true-writer of `showVisual` and said: "If `showVisual` no longer EXISTS (S3c shipped),
        // delete this counterweight and claim 5's overlay half in that same commit". S3c is this
        // commit (#1069); both were deleted, and the header swept with them.
        //
        // The replacement asks the STRONGER question the old one was a proxy for: is there a
        // second fullscreen chrome at all? A scan for a vanished flag would be vacuously green
        // forever (#926) — the flag cannot come back under that name — while a second
        // `.fullScreenCover` over the visual is the thing the founder asked to be rid of and the
        // thing a future slice could plausibly re-add.
        let secondChrome = lines.filter {
            $0.contains(".fullScreenCover(") && !$0.contains("$showMeditation")
        }
        XCTAssertTrue(secondChrome.isEmpty, """
        a second fullscreen chrome is back in \(Self.studio): \
        \(secondChrome.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        #1069 deleted the visual cover on the founder's *"aktuell gibt es fullscreen Mode das \
        soll aber alles zu einem Ding zusammen gefasst werden"*. Two chromes over one renderer \
        is what was removed, and it brought back the two-renderers-one-recorder hazard #1031 \
        blocked. It also costs a presentation slot at the 10.76.34 metadata ceiling.

        `showMeditation`'s cover is excluded on purpose: it is a different surface, it predates \
        all of this, and it has no setter that can open it. If a NEW fullscreen surface is \
        genuinely wanted, that is a decision with a founder line, not a refactor — widen this \
        needle deliberately and say why here.
        """)
    }

    /// ⭐ Claim 7 — THE PAIRING IS SEVERED, and saying why is the whole of this rewrite.
    ///
    /// It used to assert `XCTAssertNotEqual(hasDoor, normalises)`: the donut look was reachable
    /// ONLY through the fullscreen cover's top-bar glyph, so "is there a door" and "does the app
    /// stamp `visual.spectralDonuts` back to false on launch" had to move together, or a player
    /// would flip a switch that the next launch silently undid.
    ///
    /// ⭐ #1065 GAVE THE LOOK ITS OWN DOOR — a `Toggle(isOn: $spectralDonuts)` in the Field panel,
    /// which is not behind the cover and does not care whether the cover exists. From that commit
    /// on, the two facts are independent: the normalisation must stay deleted because a REACHABLE
    /// two-way switch exists, not because a particular modal does. #1067 then made the old
    /// coupling actively misleading — `showVisual` had no true-writer any more (the flag went
    /// with the cover in #1069 — #1109), so the old
    /// assertion read `NotEqual(false, false)` and went red on a tree where the donut look is
    /// MORE reachable than when the claim was written, not less.
    ///
    /// What survives is the half that was ever a regression guard: a doorless-looking `private`
    /// helper is an ordinary thing to tidy back in, and doing so would stamp a player's chosen
    /// look off on every launch — the `LeadMixDoorAndNormalisationTests` failure class, one store
    /// down.
    ///
    /// ⚠️ THE COUNTERWEIGHT RESTATES A FACT ANOTHER FILE OWNS, deliberately (#367 over #416).
    /// `TheDonutLookSurvivesTheCoverTests` is the home of "the switch exists"; without a local
    /// echo of it, this claim would pass on a tree where the switch AND the normaliser are both
    /// gone — which is the exact silent state the original pairing existed to catch. The echo is
    /// one needle, and its message points at the owner rather than re-arguing the case.
    func testTheDonutNormalisationStaysDeletedBecauseTheLookHasItsOwnDoor() throws {
        let lines = try studioLines()
        // The declaration would carry the same token; the obligation is the CALL, so exclude it.
        // ⛔ ANCHORED ON `func`, NOT ON `private` (#710 review finding 4): dropping the access
        // modifier, or splitting it onto its own line, would make the DECLARATION read as a call.
        let normalises = lines.contains {
            $0.contains("normaliseUnreachableDonutMode()")
                && !$0.contains("func normaliseUnreachableDonutMode")
        }
        XCTAssertFalse(normalises, """
        `normaliseUnreachableDonutMode()` is being called again in \(Self.studio).

        That function stamps `visual.spectralDonuts` back to `false` on every launch. It was
        correct exactly while the look had no reachable writer (#227 → #747); since #1065 the \
        Field panel carries a two-way switch, so restoring the call means a player turns the \
        donut look on, closes the app, and finds it off — a control that moves, persists and is \
        silently undone. Delete the call. If the donut renderer is being RETIRED outright \
        (the key, `SpectralDonutView`, the switch), delete this claim with them rather than \
        satisfying it.
        """)

        // COUNTERWEIGHT (#367): the reason the deletion is allowed to stand. Owned by
        // `TheDonutLookSurvivesTheCoverTests`; echoed here so this claim cannot pass over a tree
        // where switch and normaliser vanished together.
        let switched = lines.contains { $0.contains("Toggle(isOn: $spectralDonuts)") }
        XCTAssertTrue(switched, """
        no reachable switch for the donut look in \(Self.studio), and no normalisation either — \
        so a persisted `visual.spectralDonuts == true` can neither be turned off by the player \
        nor repaired at launch. That is the silent state the old pairing existed to catch.

        `TheDonutLookSurvivesTheCoverTests` owns this fact and will be red in the same run with \
        a fuller message; fix it there, and this echo follows.
        """)
    }

    // ⛔ `isTrueWriter` AND `flagAssignments(in:)` STOOD HERE AND ARE DELETED (#1069), together
    // with roughly 30 lines of doc arguing how to tell a `showVisual = true` from a
    // `showVisualControls.toggle()` by word boundary. The flag they parsed does not exist any
    // more: S3c deleted the fullscreen cover it drove.
    //
    // ⚠️ THE ARGUMENT IS WORTH KEEPING EVEN THOUGH THE CODE IS NOT, because the next
    // flag-scanning guard will need it: a prefix match on a flag name matches every LONGER
    // identifier that starts with it, and this file had three live ones (`showVisualSettings`,
    // `showVisualFineTune`, `showVisualControls`). Unbounded, the scan would have read a live
    // toggle as a door and gone red on a correct tree. Word-bound first, then decide.
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
