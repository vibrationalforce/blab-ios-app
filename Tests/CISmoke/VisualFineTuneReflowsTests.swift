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
// ⭐ THE SECOND HOST NOW HAS A DOOR (#747), and this block used to say the opposite. From the
// tools-grid removal until 2026-08-22, `visualVJOverlay` was mounted only inside
// `.fullScreenCover(isPresented: $showVisual)` and `showVisual` had no writer of `true` anywhere
// in `Sources/` — open task #270. #747 added a visible "Full screen" button in `visualPanel`, so
// the overlay is reachable and the task is closed.
//
// ⭐ THE ASYMMETRY THIS BLOCK NAMED IS GONE, and its disappearance STRENGTHENS claim 4 rather
// than retiring it. The old reading: hardcoding **8** re-spaced the reachable panel (a live cost)
// while hardcoding **14** re-spaced only a surface nobody could open (bookkeeping). Both call
// sites are reachable now, so the no-default rule defends two live surfaces in both directions —
// the argument got simpler, not weaker. Kept as history because the reasoning is the reusable
// part: a parameter whose second consumer is unreachable is half a defence, and saying which
// half is what stops a later session from "simplifying" it back to a literal.
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
//   5. Both call sites pass a spacing, and the overlay's argument matches the overlay's OWN stack.
//   6. The overlay has EXACTLY ONE visible door, and its label is pinned. ⭐ REWRITTEN BY #747:
//      until then this item read "the overlay is still doorless" and was a counterweight built
//      to go red on the day of the re-door, with the prose bill in its message. It fired, the
//      bill was paid in that same commit (#456), and the claim turned around: the door must
//      exist (zero = a lost capability, not a lost plan), there must be exactly ONE of it
//      (two = a second entrance to one surface — the #290 trap: a second door to `bioPanel` was
//      shipped in 2026-07-12 and pulled two days later), and
//      it must be a labelled Button rather than a hidden gesture — the cover's own top bar
//      cites WCAG 2.2 for that. **The guard working looks exactly like this, not like a green.**
//   7. The donut normalisation and that door are MUTUALLY EXCLUSIVE — and #747 is the commit
//      that made the pairing real, so here is what it actually did with the three CODE
//      obligations this item warned about:
//        · `normaliseUnreachableDonutMode()` and its call site: DELETED, exactly as that
//          function's own doc block ordered. Keeping it would have stamped a player's donut
//          choice back to `false` on every launch — the honest normalisation turning into a
//          silent state-eater the moment a door existed.
//        · the "Donuts" pill in `visualLookStrip`: **NOT restored, deliberately.** ⛔ The #227
//          tombstone justified it with "the pill was the overlay's last look control", and that
//          premise did not survive measurement: the cover's top bar already carries a working
//          `spectralDonuts.toggle()` button. Restoring the pill would have built a SECOND
//          control for one state — the same #290 trap item 6 now guards against for the door
//          itself. A note with a checkable rationale gets checked before it causes work.
//        · flipping `StudioDefaultKeys.visualSpectralDonuts` back to `true`: NOT done, and
//          `VisualLookTruthTests.testAFreshInstallDoesNotClaimTheDonutRenderer` is NOT flipped.
//          Its assertion is still true and now states a CHOICE rather than a limitation: a fresh
//          install opens on the Metal field, the identity look, and donut mode is something a
//          player picks. Only that test's prose needed correcting.
//      The old parenthetical about claim 6's "nine" is retired with the claim it described; the
//      lesson survives in item 6 — a count of scattered sentences is a number this repo does not
//      write down, and #709 restated "nine" three times as though it were a census.
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
// ⭐ THE OVERLAY'S DEVICE CHECK IS REAL AGAIN AS OF #747, and the way it got here is the useful
// part. It was first written as a founder ask — "the overlay still fits its cap in landscape …
// Device-verify is open, landscape and the VJ overlay specifically" — while NOBODY COULD OPEN THE
// OVERLAY. An impossible ask is worse than a vague one: it would have cost a device session to
// discover that, sitting in the register a session reads when triaging the NEEDS-FOUNDER-VERIFY
// backlog. It was WITHDRAWN rather than reworded, with a note saying it becomes real on the day
// the overlay gets a door and that claim 6 would go red and say so. #747 built the door and
// claim 6 did exactly that.
//
// **NEEDS-FOUNDER-VERIFY (#747), now genuinely performable:** open Field → "Full screen",
// rotate to landscape, and check that the VJ overlay's two columns still read (the width maths
// below says 261 pt per column at the 560 pt cap). Also worth one look: the floating window
// disappears while the cover is up and comes back on close — that is the single-`MetalBioView`
// GPU rule in `.onChange(of: showVisual)`, and it has never run on a device.
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

    /// ⭐ Claim 6 — REWRITTEN BY #747, and the rewrite is the point of it having existed.
    ///
    /// It used to assert `testTheVJOverlayIsStillDoorless`: `showVisual` had no writer of `true`
    /// anywhere in `Sources/`, so the whole VJ control panel was unreachable (open task #270).
    /// That claim was a COUNTERWEIGHT built to go RED on the day the overlay was re-doored, with
    /// the prose bill in its failure message. #747 built the door — a visible "Full screen"
    /// button in `visualPanel` — so the claim fired exactly as designed and this file paid the
    /// bill it named. **That is the guard working, not the guard failing.**
    ///
    /// ⚠️ WHAT THE OLD CLAIM DECIDED, and what replaces it. It was the premise claims 1–5 rested
    /// on: passing 8 to the overlay was bookkeeping "for the day the door returns", while passing
    /// 14 to the inline panel was a live guarantee. That asymmetry is GONE — both call sites are
    /// now reachable, so `spacing` defends two live surfaces and claim 5 got stronger without
    /// changing a line. The honest-limit block's landscape device check on the overlay, which
    /// this file had to RETRACT as an impossible founder ask, becomes a real request today.
    ///
    /// The assertion now runs the normal way round: the door must EXIST, and there must be
    /// exactly ONE of it. A second true-writer is a second door to one surface (#290) — the trap
    /// that pulled a second `bioPanel` door in 2026-07-14 — and it is the likeliest next regression,
    /// because a fullscreen toggle is an obvious thing to also put in a header.
    ///
    /// The scan stays word-bounded: `showVisualSettings`, `showVisualFineTune` and
    /// `showVisualControls` share the prefix and are live, settable flags.
    ///
    /// ⚠️ `SourceText.codeOnly` IS STILL ONLY PROPHYLACTIC HERE — measured on this tree, not
    /// assumed. ⛔ I first wrote the opposite: that #747's new prose (the deleted normaliser's
    /// tombstone, the door's own comment) would make raw text count comment lines as writers and
    /// fail the count assertion. Measured, raw and stripped agree exactly — **3 assignment-shaped
    /// lines and 1 true-writer in both** — because those notes say "gives `showVisual` a setter",
    /// never the assignment form the scanner matches. A rationale that upgrades a guard's
    /// dependency is a claim like any other and needs the same one command. It stops being
    /// prophylactic the day somebody quotes `showVisual` followed by `= true` in a retraction;
    /// that is why the notes #747 adds **to `EchoelStudioView.swift`** describe the writers
    /// instead of quoting one. (This file may quote it freely — the scan reads the studio file,
    /// not its own source. Naming which file the rule binds is the difference between a rule and
    /// a superstition.)
    func testTheVJOverlayHasExactlyOneVisibleDoor() throws {
        let lines = try studioLines()
        let writers = lines.filter { flagAssignments(in: $0) }
        // #367: anchor first. A rename would empty the list and let everything below pass on
        // nothing, which is how a guard stops being able to fail for its stated reason.
        XCTAssertFalse(writers.isEmpty, """
        no assignment to `showVisual` in \(Self.studio) — the flag was renamed or removed.

        Re-anchor this claim on the new name; do NOT delete it. If the fullscreen visual cover \
        went away entirely, delete claim 5's overlay half and this one together, and sweep the \
        prose in the same commit — including this file's header, which now describes a REACHABLE
        overlay.
        """)
        let openers = writers.filter { isTrueWriter($0) }
        XCTAssertEqual(openers.count, 1, """
        `showVisual` has \(openers.count) writers of a value other than `false`, not one:
        \(openers.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        ZERO means the door was removed and the overlay is unreachable again. That is a real \
        regression against ship-gate 4 ("visual live + contemplative on device") — the surface \
        behind the cover is fully built, so losing the setter loses a capability, not a plan. \
        Restore the button in `visualPanel`; and note the donut normalisation does NOT come back \
        with it (claim 7 owns that pairing and will be red in the same run).

        TWO OR MORE means a second door to one surface (#290): a header toggle plus the panel \
        button, say. Pick one and delete the other. The 2026-07-14 removal of `bioPanel`'s second \
        door is the precedent — a second entrance to a surface that already has one reads as a bug \
        to the player long before it reads as convenience. (Phrased without the word this repo \
        bans there: `TheBioPanelDoorIsThePulsePillTests` went RED on the first draft of these \
        three lines, which is the guard doing its job on prose I wrote by habit.)
        """)
        // The cover's own top bar cites WCAG 2.2 against gating controls behind a hidden
        // gesture. A `showVisual = true` reachable only from a long-press would satisfy the
        // assertion above and still repeat the defect this codebase names, so the door's LABEL
        // is pinned too — a labelled Button is what makes it discoverable.
        let labelled: Bool = lines.contains(where: { $0.contains("Text(\"Full screen\")") })
        XCTAssertTrue(labelled, """
        the "Full screen" label is gone from \(Self.studio) while `showVisual` still has a \
        writer of `true`.

        If the door was RENAMED, re-anchor this needle. If it became a gesture (long-press, \
        swipe, a tap on the header monitor), that is the defect the cover's own top bar argues \
        against in its comments: "don't gate controls behind a hidden gesture" (WCAG 2.2). \
        Restore a visible, labelled control.
        """)
    }

    /// ⭐ Claim 7 — the PAIRING claim 6 could not make, and the reason this commit exists.
    ///
    /// Claim 6 goes red at the re-door and its message lists nine PROSE files. It names ZERO code
    /// obligations, and there are AT LEAST THREE: restore the "Donuts" pill in `visualLookStrip`
    /// behind `showsDonutState` (see below — NOT at both mounts), DELETE
    /// `normaliseUnreachableDonutMode()` together with the line that calls it, and flip
    /// `StudioDefaultKeys.visualSpectralDonuts` back with `VisualLookTruthTests`
    /// `.testAFreshInstallDoesNotClaimTheDonutRenderer`, whose own message asks for exactly that.
    ///
    /// ⛔ "TWO, WRITTEN ONLY IN DOC COMMENTS INSIDE `EchoelStudioView`" IS WHAT THIS SAID FIRST,
    /// and both halves were wrong (#710 review finding 2). The third obligation is a `Sources/`
    /// change in a different file, and of the two that ARE in `EchoelStudioView` the pill one is
    /// a `//` body comment inside `visualLookStrip`, not a `///` doc comment. A count stated as
    /// complete is the failure this whole file argues against; "at least three, and here they
    /// are" is the honest form.
    ///
    /// Obey claim 6 to the letter and the second half still ships wrong: the pill returns, a
    /// player switches Donuts on, and the next launch stamps it back off. A control that moves,
    /// persists and is silently undone — the exact failure class
    /// `LeadMixDoorAndNormalisationTests` was written to prevent ONE STORE DOWN, on a normaliser
    /// whose own doc comment calls itself "the same shape and same reason" as that one. The lead
    /// pairing has a guard; its donut twin had none. This is that guard.
    ///
    /// ⛔ "THE LEAD PAIRING HAS A GUARD IN BOTH DIRECTIONS" IS WHAT THIS SAID, and measuring it
    /// was the one thing #709 did not do (#710 review finding 1). That file read RAW source with
    /// a bare token, which also matched two prose comments and the declaration — so its
    /// "normalisation missing" direction could not fire on a deleted call. Writing an unchecked
    /// "X is guarded too" into a commit whose whole subject is unchecked standing claims is the
    /// failure itself; the note is left where it was made.
    ///
    /// ⭐ AND IT IS REPAIRED — #711, one cycle later, gave that file `codeOnly` and the same
    /// `func`-keyword exclusion. The two are now the SAME shape, so the sentence that stood here
    /// ("This claim is the STRICTER shape … not a copy of it") is withdrawn: it was true for two
    /// commits and describes nothing today. ⚠️ #711 did not move it, which is the #456/#472
    /// lesson landing on the very pair of files that were arguing about it — the repair was made
    /// in one file and its description lived in the other. Caught by the #712 review.
    ///
    /// ⚠️ THE TWO DIRECTIONS ARE NOT THE SAME KIND, graded separately (#433/#464/#486):
    ///   · door absent + normalisation deleted → RED, and this half COULD always have been red.
    ///     Deleting a doorless `private` helper is an ordinary tidy-up. A REGRESSION guard.
    ///   · door present + normalisation kept → RED. Green today and green after a CORRECT
    ///     re-door, so that half is a COUNTERWEIGHT with an expiry, the same shape as claim 6.
    ///
    /// It does not forbid the re-door (#364): a commit that adds the door AND removes the
    /// normalisation passes. Driven against four deliberately broken trees before it was written
    /// — call deleted → red · door without the deletion → red · both together → green · a `//`
    /// COMMENT mentioning the assignment → green, which is where the `codeOnly` pass in
    /// `studioLines()` earns its keep. ⛔ That last one first read "a prose-only mention", which
    /// claims more cover than exists (#710 review finding 5): `codeOnly` does NOT blank the body
    /// of a `"""` literal — `SourceText`'s own header says so — and `EchoelStudioView` already
    /// writes such literals. The same assignment inside one would turn this claim, and claim 6,
    /// red on a correct tree. See `isTrueWriter`, where both limits now live once.
    ///
    /// ⚠️ THE PILL GOES BACK AT ONE MOUNT, NOT TWO, and getting this wrong would re-create the
    /// exact defect #227 removed (#710 review finding 3). `visualLookStrip` is mounted twice:
    /// inline in the Field panel with `showsDonutState: false`, and in the VJ overlay with
    /// `true`. The inline panel's visual is `FloatingVisualWindow`, which does not read
    /// `spectralDonuts` AT ALL — a pill there would fill, the readout would say "Donuts", and
    /// nothing on screen would change, which is precisely what #227 deleted. The re-door changes
    /// what the OVERLAY can show; it changes nothing about the inline panel. So: behind
    /// `showsDonutState`. The source line being paraphrased ("Restore it there, not only inline")
    /// is ambiguous read alone; the `showsDonutState` parameter doc resolves it.
    ///
    /// ⚠️ IT CANNOT SEE THE PILL, and the message says so rather than implying full cover. The
    /// pill is a view control; a token scan would pin a spelling, not a capability. That
    /// obligation is carried in the failure text, where the person doing the re-door reads it.
    ///
    /// ⚠️ TWO RENAMES, TWO DIFFERENT OUTCOMES, and neither is a silent pass. Renaming the FLAG
    /// leaves `normalises` untouched at `true` while `hasDoor` reads `false`, so this claim would
    /// pass on nothing — the #367 hole — except that claim 6 anchors on exactly that and goes RED
    /// first, in this same file. (⛔ This sentence first said "both sides read `false`". The
    /// conclusion was right and the mechanism was not; `normalises` does not depend on the flag.
    /// A reason given for a true conclusion is checked here too — #710 review finding 6.)
    /// Deliberately NOT re-anchored here (#416: one definition of that fact). Renaming the
    /// NORMALISER instead turns this claim red with the "NEITHER present" branch, which is a red
    /// for a true reason under a slightly wrong name; the repair is the same either way.
    func testTheDonutNormalisationExpiresExactlyWhenTheDoorReturns() throws {
        let lines = try studioLines()
        let hasDoor = lines.contains { isTrueWriter($0) }
        // The declaration carries the same token; the obligation is the CALL, so exclude it.
        // ⛔ ANCHORED ON `func`, NOT ON `private` (#710 review finding 4). The first draft
        // excluded lines containing "private func", so dropping the access modifier — or
        // splitting it onto its own line — would have made the DECLARATION read as a call and
        // handed a false green to the one direction this claim grades as a regression guard.
        let normalises = lines.contains {
            $0.contains("normaliseUnreachableDonutMode()")
                && !$0.contains("func normaliseUnreachableDonutMode")
        }

        XCTAssertNotEqual(hasDoor, normalises, """
        The fullscreen visual door and its donut normalisation are out of step. \
        door=\(hasDoor) normalisation=\(normalises).

        BOTH present: `showVisual` has a real writer, so the overlay's Donuts toggle is reachable \
        again — while `normaliseUnreachableDonutMode()` still stamps `visual.spectralDonuts` back \
        to `false` on every launch (the call sits in `.onAppear`). In THIS commit: delete that \
        function AND the line that calls it; restore the "Donuts" pill in `visualLookStrip` \
        behind `showsDonutState`, i.e. at the OVERLAY mount only — the overlay has no \
        `visualLookCustomizer` under it, so the pill was its last look control, while the inline \
        Field panel renders `FloatingVisualWindow`, which does not read `spectralDonuts` at all, \
        so a pill there is the #227 lie again; and flip \
        `StudioDefaultKeys.visualSpectralDonuts` with `VisualLookTruthTests`.

        NEITHER present: `visual.spectralDonuts` is persisted, still has no reachable writer, and \
        now nothing repairs an install that stored `true` before #227 — those players keep the \
        launch look-snap skipped, with no control able to undo it. Restore the call, or restore \
        the door in the same commit. Third legitimate tree, and the one this message used to \
        misdirect: the donut renderer was RETIRED outright (key, `SpectralDonutView`, the cover \
        branch). Then delete this claim together with the key, the way claim 5's overlay half and \
        claim 6 retire together.
        """)
    }

    /// True when `line` both assigns to the flag AND is not the `= false` form — the ONE spelling
    /// of "this is a door" in this file, so claims 6 and 7 cannot drift into disagreeing about
    /// what a door is (#416/#453). Claim 6 asks whether any such line exists at all; claim 7
    /// pairs the answer against the normalisation.
    ///
    /// ⚠️ TWO HONEST LIMITS, shared by both callers (#710 review findings 5 and 9).
    ///   · The `= false` needle is whitespace-sensitive. `showVisual=false` satisfies
    ///     `flagAssignments` (a bare `=` is accepted) but not this test, so a reformat of an
    ///     existing false-writer reads as a door → RED on a correct tree. A single line carrying
    ///     BOTH forms reads as no door → false green. Both are cheap to fix the day either shape
    ///     appears; neither is invented ahead of a real case (#367).
    ///   · `SourceText.codeOnly` blanks `//` and `/* */`, NOT the body of a Swift `"""` literal —
    ///     its own header says so and explains why the omission is deliberate. Every line inside
    ///     such a literal is scanned as CODE, and `EchoelStudioView` already writes them. So the
    ///     stripper protects against a COMMENT quoting the assignment, not against any prose.
    private func isTrueWriter(_ line: String) -> Bool {
        flagAssignments(in: line) && !line.contains("= false")
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
