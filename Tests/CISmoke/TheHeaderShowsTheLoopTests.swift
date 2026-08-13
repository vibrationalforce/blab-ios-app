// TheHeaderShowsTheLoopTests.swift
// Echoel — the loop length lives in the brand header, and the read stays in its leaf. #490/#501.
//
// ⭐ THE ASK. Founder, 2026-08-07, screenshot of v10.79.374 (2491): a scribble over the colour
// bars top-left, a circle around the E mark, and a long arrow running from the scribble down to
// the circled `1.1.1 / loop 1/8` readout. *"E Logo wieder nach rechts, die bunten Balken weg
// stattdessen die Anzeige für die Loop Länge und der Balken."* Three clauses, one change:
//   · `HeaderSpectrumStrip` is GONE — file deleted, not merely unmounted.
//   · `TransportPositionView` MOVED into that slot — it is not copied there; `EchoelStudioView`
//     lost its third line in the same commit (one readout, one address, #416).
//   · the brand block moved to the TRAILING end, after the monitor tiles.
//
// ⭐ AND THEN THE THIRD CLAUSE WAS REVERSED ONE DAY LATER. Founder, 2026-08-08, screenshot of
// v10.79.377 (2494): the mark and "Echoelmusic v10.79.377 (2494)" circled at the trailing edge,
// a long arc sweeping LEFT with two arrowheads landing at the loop readout — *"Die obere Reihe
// so anordnen wie gezeigt mit Pfeilen natürlich optimal ausgerichtet das Logo und Echoelmusic
// ist wie auf der Website."* The other two clauses of #490 are untouched and still pinned here.
//
// ⭐ AND THEN AGAIN, LATER THE SAME DAY (#516). Screenshot of v10.79.379 (2496): a circle round
// the brand at the LEADING edge, a circle round the `1.1.1 / loop 1/8` readout, and an arc with
// an arrowhead at EACH end between them — *"Den Schriftzug Echoelmusic wieder in die Mitte und
// dementsprechend mit der Takt Anzeige tauschen."* Two arrowheads is the SWAP grammar (a single
// arrowhead has meant MIGRATE since #411), and the sentence states it twice ("in die Mitte" +
// "tauschen"), so nothing is inferred. The row is now **position · brand · monitors**.
//
// ⭐ AND THEN A FIFTH TIME, AND THIS ONE IS NOT A REORDER (#528). Founder, 2026-08-12, screenshot
// of v10.79.384 (2501): a circle drawn tightly around the `E` TILE — the wordmark visibly OUTSIDE
// it — and a red arc with a SINGLE arrowhead sweeping left onto the loop bar at the far edge. One
// arrowhead is MIGRATE (#411), so the mark alone moves to the leading edge and the wordmark keeps
// the middle it was given at #516. Row is **mark · position · wordmark · monitors**. Reading it
// as "move the block" would reproduce #501 and undo a four-day-old sentence; the smaller circle
// is the whole disambiguation, and he has circled the block WITH the wordmark before.
//
// ⛔ EVERY EARLIER PLACEMENT MOVED WHOLE CHILDREN; THIS ONE CHANGED WHAT A CHILD IS. That is why
// #528 ADDS `testTheMarkLeadsTheHeaderAndIsNotAControl` instead of adjusting the ordering methods
// again — measured against this tree, all three pre-existing methods stay GREEN, because the DOOR
// (`openWebsite()`) never moved. The mark's position was therefore unwatched, and folding it back
// into the button would have passed the entire bundle.
//
// ⛔ THAT IS THE THIRD PLACEMENT OF THE BRAND IN TWO DAYS — trailing (#490), leading (#501),
// middle (#516, which is where #384 had it on 2026-08-02). This file keeps ADJUSTING the two
// ordering assertions rather than deleting them, for the same reason each time: a guard that
// vanishes when its subject moves leaves the ordering unwatched in every direction, and this
// header has now been re-arranged by explicit founder ask FIVE times. **What no session may do
// is read one of those notes as the settled design and "restore" it.** The invariant across all
// five is the LAW, not the layout: one greedy flank, no `Spacer`, no `ZStack`, readout is a leaf.
//
// ⭐ THE PRICE #501 PAID OFF IS NOT RE-BORROWED, and the monitor assertion is what proves it.
// #490 priced the brand at the trailing edge as *"a website link — not a 44 pt control — sits in
// the thumb corner"*; #501 repaid that by giving the corner to the monitor tiles. #516 is a
// TWO-CHILD swap, so the tiles are still trailing-most and the thumb corner is still a 44 pt
// control (#113). Reordering them "for symmetry" would silently re-borrow that cost, which is
// why `testTheBrandSitsBetweenTheReadoutAndTheTiles` pins BOTH boundaries and not just one.
//
// ⛔ WHY DELETING THE STRIP WAS HONEST AND NOT DESTRUCTIVE, because it was itself a founder ask
// five days old (#384) and reversing one deserves a reason on the record. The spectrum was a
// SECOND COPY: `AnalysisSpectrumView` carried the same ring, the same bands and the same
// frequency→visible-light colours, at a size where the number beside it is readable. Every
// collaborator it used (`EchoelRealFFT`, `SpectrumAnalysis`, `SpectralColor`,
// `AudioEngine.copyLatestOutputSamples`) keeps other callers, so nothing was orphaned. What the
// header lost is a duplicate; what it gained is the one fact a performer needs at a glance with
// both hands busy, which existed nowhere else on screen.
//
// ⚠️ AND THE OTHER COPY IS GONE TOO SINCE #575 — this paragraph said "in the Field panel", in
// the PRESENT tense, as the load-bearing half of a deletion argument. On 2026-08-13 the founder
// circled the whole Signal block and wrote *"Das Brauch da nicht sein"*; `AnalysisSpectrumView`
// is now PARKED (file intact, doorless on purpose, one line to restore). So the app currently
// shows NO spectrum anywhere.
//
// ⭐ THAT DOES NOT WEAKEN THE DELETION, and saying why is the point of this note. The header
// strip went because the founder asked for it, twice — first for it, then against it — not
// because a duplicate existed; the duplicate merely made it cheap. What HAS changed is that
// "cheap" no longer applies: restoring a spectrum is now a real decision about where it lives,
// not a choice between two copies. A session reading the old sentence would have gone looking
// for a Field-panel spectrum, found none, and concluded the deletion had been wrong.
//
// ⚠️ THE HIGHEST-STAKES HALF IS THE FREEZE LAW, and it is why this guard exists at all rather
// than being left to the diff. `TransportPositionView` reads `transport.position` — ~10 Hz at
// 120 BPM — and its new host is `WorkspaceView.topBar`, the ROOT chrome, an ancestor of EVERY
// surface in the app. Mounting a leaf there registers nothing; only its own body reads. Inlining
// its two labels into the header instead — the tempting "simplification" for a two-label view —
// rebuilds `WorkspaceView.body` ten times a second and tears down any open `.menu` Picker in the
// instrument below. That is 10.76.50, and it took four attempts to find because three audits
// scoped to `EchoelStudioView` while the read was one level up. `AnyView` is not an observation
// boundary; only a separate `View` struct is.
//
// ⚠️ HONEST GRADING FOR #516, measured against ITS parent (the #501 tree) rather than asserted,
// by transcribing `SourceText.codeOnly` and driving every assertion against both trees:
//   · **TWO** assertions are regressions, and they are the two the swap moved: the ORDER (parent
//     has brand before the readout) and the flank's OWNER (parent applies it to the readout).
//   · ⛔ AND THAT SECOND ONE WAS ONLY TRUE AFTER THE MEASUREMENT FIXED IT. As first written, the
//     owner check was `flank > brand && flank < firstTile` — GREEN on the parent, because there
//     the readout sits between the brand and the tiles and its modifier falls inside that window.
//     So the method could not fail for its stated reason (#367) while this very paragraph called
//     it a regression: the #433 defect and the #367 defect in one place, and the only thing that
//     surfaced it was driving both trees rather than asserting the grade. The window now ends at
//     the next sibling child. **A grading claim is itself an assertion, and it gets measured.**
//   · **THREE** are COUNTERWEIGHTS, green on both sides: the mount, the deleted file, and the
//     no-live-read rule. Saying so is the point (#433) — they cannot catch this commit; they
//     exist so the NEXT tidy-up cannot quietly undo #490's half while everyone looks elsewhere.
//   · The flank COUNT stays exactly 1 across #490 → #501 → #516 and has never been the thing
//     that moved; only its owner and alignment have. That is why the count and the owner are two
//     separate `XCTAssert`s in one method rather than one compound check — they fail for
//     different reasons and a reader needs to know which.
//   · A guard's grade is a property of the tree it is measured against, not of the guard: the
//     ordering assertion has now been a regression three times running, each time in a different
//     direction, without its subject ever changing.
//
// ⚠️ HONEST GRADING FOR #528, measured against its parent (`b2d9ea2`) rather than asserted, by
// transcribing `SourceText.codeOnly` and driving every assertion in BOTH this file and
// `ChromeDynamicTypeTests` against both trees. Unusually, it is worth stating what the numbers do
// NOT mean before what they do:
//   · **ONE** assertion here flips — the new `testTheMarkLeadsTheHeaderAndIsNotAControl` (parent:
//     mark at index 60, readout at 19). **FOUR** are counterweights, green on both sides.
//   · ⚠️ AND "RED ON THE PARENT" DOES NOT MEAN THE PARENT WAS DEFECTIVE HERE, which is the
//     difference between this slice and most of the chain. The parent is the layout the founder
//     asked for on 2026-08-08; it is red only because the ask changed on 2026-08-12. Calling that
//     a regression caught would be the #433 defect in the flattering direction — the guard pins a
//     NEW fact, it did not find an old fault.
//   · In `ChromeDynamicTypeTests` the same is true of the two assertions #528 rewrites (the
//     `HStack(spacing: 8)` count 3 → 2, and the VoiceOver-hiding rule). What IS a real catch is
//     the *old* form of the second one: `XCTAssertFalse(… accessibilityHidden(true))` was GREEN on
//     the parent and would have gone RED on this correct tree — found by grepping `Tests/CISmoke`
//     before editing the surface, which is the #456 step and the only reason it was not a red gate.
//
// ⚠️ HONEST LIMITS, first rather than last. Every assertion here is a SOURCE-TEXT SCAN. There is
// no simulator in the blocking bundle, so this proves where text stands — never that the header
// reads well, never that the loop readout is legible at chrome size, and never that a Picker
// stays open on a device. NEEDS-FOUNDER-VERIFY: does the row read as "position · brand ·
// monitors", and does the wordmark look CENTRED? It is centred in the SLACK, not in the bar —
// arithmetic on `WorkspaceView` puts it ~24 pt left of true centre, because its two neighbours
// are not the same width and one greedy flank cannot know that. If that reads as off-centre, the
// fix is a founder call (a second flank is banned here for reasons pinned above). Also: does
// "Echoelmusic" still read at 14 pt once `minimumScaleFactor(0.7)` has had its way on a 360 pt
// phone — it is now the child that YIELDS under compression, where the readout used to be. And:
// start biofeedback, play, open the Genre or Key menu below and leave it open for several
// seconds — does it stay?
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, ON **TWO** ASSERTIONS SINCE #501, RE-MEASURED
// ON THE #516 TREE (raw sees 2 greedy flanks and stripped 1; raw sees `@AppStorage` inside the
// bar and stripped does not — unchanged by the swap, because the swap moved children rather than
// prose) — measured each time rather than assumed, and the history is the lesson. #490's first
// version named the
// WRONG collision (the #443 defect, committed in the act of claiming a method): it said a raw
// scan would count the retracted trailing flank as a second `maxWidth: .infinity`, and it would
// not, because that quotation was wrapped across two comment lines so the substring never
// formed. That correction was right on the day it was written. **#501 rewrote that retraction
// onto one physical line, and the substring now forms.** Measured on this tree: raw sees TWO
// greedy flanks and stripped sees one; raw also sees `@AppStorage` leak into the header (the
// comment introducing the readout says the leaf "reads `Transport` and `@AppStorage` only") and
// stripped does not. So the stripper is load-bearing on the flank COUNT *and* on the
// counterweight — a raw scan would be red on CORRECT code, twice. The general form is the #486
// collision: this repo writes down what it removed, so a negative scan meets its own obituary —
// and a "this collision does not form" note has a shelf life of exactly one reflow.
// ⭐ RE-MEASURED ON THE #528 TREE AND IT IS NOW **THREE** COLLISIONS, not two: raw sees 2 greedy
// flanks and stripped 1; raw sees a `ZStack` in the bar and stripped none; raw sees THREE
// `accessibilityHidden(true)` and stripped one, because this slice's retraction notes quote the
// modifier while explaining why it is back. The shelf-life sentence above earned itself again in
// one commit.
// ⚠️ AND THE NEIGHBOUR THAT ASSERTS ON THAT THIRD ONE DOES **NOT** USE THIS STRIPPER.
// `ChromeDynamicTypeTests` has its own private `codeLines` (drop whole `//` lines — one of the
// ~60 copies #460 measured), which KEEPS trailing comments. Its new "exactly one hidden element"
// count is verdict-identical today only because every quotation of the modifier in `topBar` is on
// a whole comment LINE. A retraction written as a trailing comment would turn that guard red on
// correct code. The fix is the #460 migration; it is not folded in here because that file also
// asserts on `lines[i - 1]` relations, and `codeOnly` preserves line count while its own stripper
// deletes lines — so the swap moves indices and is a migration, not a one-line tidy-up.
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class TheHeaderShowsTheLoopTests: XCTestCase {

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let topBarDeclaration = "private var topBar: some View {"

    // MARK: - 1. the founder's arrow landed

    func testTheHeaderMountsTheLoopReadout() throws {
        let bar = try topBar()
        XCTAssertTrue(bar.contains { $0.contains("TransportPositionView()") }, """
            `WorkspaceView.topBar` no longer mounts `TransportPositionView`.

            The founder's 2026-08-07 arrow ran from the scribbled-out colour bars in this header \
            down to the circled `1.1.1 / loop 1/8` readout: the loop length belongs up here. \
            Without this line the header's leading flank is empty again AND the readout has no \
            home at all — `EchoelStudioView` gave up its third line for this move.

            Bar scanned (comments blanked by SourceText.codeOnly):
            \(bar.joined(separator: "\n"))
            """)
    }

    /// The bars are gone as a FILE, not merely unmounted.
    ///
    /// Unmounting alone would leave a 180-line leaf that reads the live audio ring and that
    /// nothing constructs — the doorless-surface class this repo keeps having to re-discover.
    /// Asserting the file's absence is what makes "weg" mean weg.
    func testTheColourBarsAreGoneAsAFile() throws {
        let root = try repoRoot()
        let strip = root.appendingPathComponent("Sources/Echoelmusic/Studio/HeaderSpectrumStrip.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: strip.path), """
            `HeaderSpectrumStrip.swift` is back.

            The founder asked for the colour bars to go (2026-08-07, "die bunten Balken weg"). \
            If they are wanted again, that is a fresh founder ask and this guard should be \
            deleted in the same commit as the restoration — not left to fail.

            Note what made the removal cheap AT THE TIME: the same measurement also shipped \
            in `AnalysisSpectrumView`, so the header copy was a duplicate and not a \
            capability. That is no longer true — #575 parked the Field-panel spectrum on a \
            second founder instruction, so today the app shows no spectrum at all. The \
            deletion still stands (he asked for it), but restoring a spectrum is now a \
            decision about WHERE it lives, not a choice between two copies.
            """)

        let bar = try topBar()
        XCTAssertFalse(bar.contains { $0.contains("HeaderSpectrumStrip(") }, """
            `topBar` constructs `HeaderSpectrumStrip` again.
            \(bar.joined(separator: "\n"))
            """)
    }

    // MARK: - 2. "wieder in die Mitte und … mit der Takt Anzeige tauschen"

    /// The brand block sits BETWEEN the readout and the monitor tiles — the founder's swap.
    ///
    /// ⛔ THIS ASSERTION HAS NOW BEEN WRITTEN THREE WAYS IN TWO DAYS: `brand > lastTile` (#490),
    /// `brand < firstTile` (#501), and this — `readout < brand < firstTile` (#516). Each time it
    /// was ADJUSTED rather than deleted, and each time for the same reason: a guard that vanishes
    /// when its subject moves leaves the ordering unwatched. It is now STRONGER than either
    /// predecessor, because it pins both boundaries at once: the earlier forms constrained the
    /// brand against ONE neighbour and said nothing about the other.
    ///
    /// ⭐ THE SECOND BOUNDARY IS NOT DECORATION. It is what keeps #501's repayment of #490's
    /// price: the tiles must stay trailing-most so the thumb corner holds a 44 pt control (#113)
    /// rather than a website link. A one-sided assertion would let a future "symmetry" tidy-up
    /// move the tiles inward while the ordering test stayed green.
    ///
    /// ⚠️ WHAT IS **NOT** CLAIMED, and it is the likeliest thing a reader will assume: that the
    /// wordmark is centred in the BAR. It is centred in the SLACK between its two neighbours,
    /// which differ in width, so it sits ~24 pt to the left of true centre. The arithmetic is on
    /// the brand block in `WorkspaceView`; true centring needs a second greedy flank, which is
    /// banned. Nor is it claimed that the wordmark matches the website's typography — the site
    /// sets `uppercase` + 3 px tracking, which does not fit the chrome's width budget. This
    /// asserts the ORDER, which is what the founder's double-headed arc drew.
    func testTheBrandSitsBetweenTheReadoutAndTheTiles() throws {
        let bar = try topBar()
        guard let brand = bar.firstIndex(where: { $0.contains("openWebsite()") }) else {
            return XCTFail("`topBar` no longer calls `openWebsite()` — the brand block is gone")
        }
        guard let readout = bar.firstIndex(where: { $0.contains("TransportPositionView()") }) else {
            return  // the mount test above already reported the real failure
        }
        guard let firstTile = bar.firstIndex(where: { $0.contains("MonitorMini") }) else {
            return XCTFail("`topBar` mounts no `…MonitorMini` tile — the output monitors are gone")
        }
        XCTAssertLessThan(readout, brand, """
            The brand block is built BEFORE the loop readout in `topBar`.

            Founder 2026-08-08, an arc with an arrowhead at each end between the circled brand \
            and the circled readout: *"Den Schriftzug Echoelmusic wieder in die Mitte und \
            dementsprechend mit der Takt Anzeige tauschen."* The readout leads, the brand takes \
            the middle. If the two were swapped back, that is a fresh founder ask and this \
            assertion should be adjusted in the same commit — not deleted.

            readout at index \(readout), brand at index \(brand).
            \(bar.joined(separator: "\n"))
            """)
        XCTAssertLessThan(brand, firstTile, """
            A monitor tile is built BEFORE the brand block in `topBar`.

            The tiles must stay trailing-most. That is not cosmetic: #490 priced the brand in \
            the thumb corner as *"a website link — not a 44 pt control"*, and #501 repaid it by \
            putting the tiles back there. The 2026-08-08 swap deliberately touched only the two \
            children to their LEFT, so this boundary must not move with it.

            brand at index \(brand), first monitor tile at index \(firstTile).
            \(bar.joined(separator: "\n"))
            """)
    }

    // MARK: - 2b. "das E ganz nach links" — the 2026-08-12 arrow (#528)

    /// The mark is the LEADING child, ahead of the loop readout, and it is decorative.
    ///
    /// ⭐ THE ASK. Founder, 2026-08-12, screenshot of v10.79.384 (2501): a circle drawn tightly
    /// around the `E` TILE — the wordmark "Echoelmusic" is visibly OUTSIDE it — and a red arc
    /// with a SINGLE arrowhead sweeping left onto the loop bar at the far edge. One arrowhead is
    /// MIGRATE (#411); two would have been the SWAP grammar of #516. So the circled thing moves
    /// to where the arrow lands, and what he circled is the mark alone.
    ///
    /// ⛔ THE READING THAT MOVES THE WHOLE BLOCK IS THE ONE TO RESIST, and it is the likelier
    /// mistake because it is the simpler edit. Mark AND wordmark at the leading edge reproduces
    /// the #501 layout exactly, undoing *"Den Schriftzug Echoelmusic wieder in die Mitte"* —
    /// four days old, stated twice in one sentence. He has circled the brand WITH the wordmark
    /// before (#501) and did not this time. Splitting is the reading that leaves both asks true.
    ///
    /// ⚠️ THIS IS THE FIFTH PLACEMENT AND THE FIRST THAT IS NOT A REORDER OF THE SAME CHILDREN —
    /// #384 middle, #490 trailing, #501 leading, #516 middle, #528 split. Every earlier one moved
    /// whole children, so the three ordering assertions in this file kept working by adjustment.
    /// This one changed what a "child" IS, which is why it needs an assertion of its own rather
    /// than an edit to `testTheBrandSitsBetweenTheReadoutAndTheTiles`: that method's subject is
    /// where the DOOR sits, and the door did not move.
    ///
    /// ⭐ AND THAT IS EXACTLY WHY IT IS NEEDED — measured, not assumed. Driving the three
    /// pre-existing methods against this tree, ALL THREE stay green: the door anchor
    /// (`openWebsite()`) is still between readout and tiles, the flank is still on its chain, and
    /// nothing live leaked in. So the mark's position was UNWATCHED, and folding it back into the
    /// button would have passed every guard in this bundle.
    func testTheMarkLeadsTheHeaderAndIsNotAControl() throws {
        let bar = try topBar()
        guard let mark = bar.firstIndex(where: { $0.contains("EchoelLogoMark()") }) else {
            return XCTFail("""
                `topBar` no longer builds `EchoelLogoMark()`. The founder's 2026-08-12 arrow put \
                the mark at the leading edge; if it was folded back into the brand button or \
                removed, that is a fresh ask and this method should be rewritten with it.
                """)
        }
        guard let readout = bar.firstIndex(where: { $0.contains("TransportPositionView()") }) else {
            return  // the mount test above already reported the real failure
        }
        XCTAssertLessThan(mark, readout, """
            The mark is built AFTER the loop readout in `topBar` (mark \(mark), readout \
            \(readout)). The arrow landed on the loop bar at the FAR edge, so the mark leads.
            \(bar.joined(separator: "\n"))
            """)
        guard let brand = bar.firstIndex(where: { $0.contains("openWebsite()") }) else {
            return  // the ordering test above already reported the real failure
        }
        XCTAssertLessThan(mark, brand, """
            The mark is built after the wordmark's button (mark \(mark), brand \(brand)) — the \
            two are on the wrong sides of the readout.
            """)
        // ⚠️ THE COUNTERWEIGHT, and it is the half that makes the two assertions above mean
        // something (#343). "The mark leads" is satisfied by a tree that ALSO deleted the
        // website link, or the wordmark, or the version — leaving a bare glyph at the leading
        // edge and no brand at all. The door and its announcement are pinned here so that
        // cannot pass quietly.
        XCTAssertTrue(bar.contains { $0.contains("Text(\"Echoelmusic\")") }, """
            The wordmark is gone from `topBar`. The mark moving to the leading edge was a \
            re-arrangement, not a removal — "Echoelmusic" stays in the middle (#516).
            """)
        XCTAssertTrue(bar.contains { $0.contains("accessibilityLabel(\"Echoelmusic \\(Self.versionString)\")") }, """
            The brand button's accessibility label changed or is gone. It is the ONE spoken \
            announcement of the brand in this bar: the leading mark is `.accessibilityHidden`, \
            so if this label goes, VoiceOver loses the brand and the website door entirely.
            """)
    }

    /// Exactly ONE greedy flank, and since #516 it is the BRAND's.
    ///
    /// ⛔ THE COUNT WAS **TWO** UNTIL #490 and has been 1 ever since; the OWNER has moved twice.
    /// Two greedy flanks are what centred the brand geometrically — they split the leftover width
    /// evenly. That form is banned, so with one flank the brand is centred in the SLACK instead
    /// (~24 pt left of true centre; arithmetic on the brand block in `WorkspaceView`).
    ///
    /// ⚠️ THE REASON A SECOND FLANK STAYS BANNED HAS NOW BEEN RE-STATED UNDER THREE LAYOUTS, and
    /// it is worth naming because the sentence reads identically each time and could be mistaken
    /// for stale prose: under #490 it would have pulled the brand off the TRAILING edge; under
    /// #501 off the LEADING one; under #516 it would split the slack the brand centres in, so the
    /// wordmark would drift with whatever width happens to be left. Three layouts, one rule.
    ///
    /// ⚠️ ALIGNMENT IS DELIBERATELY NOT PINNED — it has been `.leading`, then `.center`, and is a
    /// look. The COUNT and the OWNER are the invariant, and they fail for different reasons, so
    /// they are two assertions rather than one compound check.
    ///
    /// The count is pinned HERE and nowhere else (`ChromeDynamicTypeTests` points at this file
    /// rather than repeating the number), so a future layout change has one place to update.
    func testExactlyOneGreedyFlankAndItIsTheBrand() throws {
        let bar = try topBar()
        let greedy = bar.enumerated().filter { $0.element.contains("maxWidth: .infinity") }
        XCTAssertEqual(greedy.count, 1, """
            Expected exactly one `.frame(maxWidth: .infinity)` in `topBar`, found \
            \(greedy.count): \(greedy.map { $0.element.trimmingCharacters(in: .whitespaces) }).

            One flank is what lets the brand centre between the readout and the monitors. TWO \
            would split the slack and let the wordmark drift — the layout the founder has now \
            moved away from three times. ZERO would collapse every child to its content and \
            leave the whole bar hugging the leading side.
            """)

        guard let flank = greedy.first?.offset,
              let brand = bar.firstIndex(where: { $0.contains("openWebsite()") }),
              let readout = bar.firstIndex(where: { $0.contains("TransportPositionView()") }),
              let firstTile = bar.firstIndex(where: { $0.contains("MonitorMini") }) else {
            return  // the ordering test above already reported the real failure
        }
        // ⚠️ A RANGE, NOT AN INDEX, and that is not laziness: the brand is a multi-line `Button`
        // whose modifier chain runs ~20 lines past `openWebsite()`, so the `readout`/`readout + 1`
        // adjacency the previous owner used cannot work here.
        //
        // ⛔ AND THE FIRST VERSION OF THIS RANGE COULD NOT FAIL FOR ITS OWN STATED REASON (#367).
        // It read `flank > brand && flank < firstTile` — which is satisfied on the #501 tree too,
        // where the flank belongs to the READOUT: there the readout sits BETWEEN the brand and
        // the tiles, so its modifier lands inside a window meant to hold only the brand's chain.
        // Measured against `c0cd34d`: brand 32, flank 71, first tile 111 — green, on a tree whose
        // flank is not the brand's. The whole method would have been a counterweight wearing a
        // regression test's clothes, and its own docstring would have claimed otherwise.
        //
        // The window therefore ends at the NEXT SIBLING CHILD, not at the tiles: the first other
        // known mount that appears after the brand. Everything strictly between is the brand's own
        // chain — comments are blanked by `SourceText.codeOnly`, so nothing else lives in there.
        let nextSibling = [readout, firstTile].filter { $0 > brand }.min() ?? bar.count
        XCTAssertTrue(flank > brand && flank < nextSibling, """
            The greedy flank is not applied to the brand block.

            It sits at index \(flank); the brand starts at \(brand) and the next sibling child is \
            built at \(nextSibling) (readout \(readout), first monitor tile \(firstTile)), so the \
            brand's own modifier chain is the open range between them. The modifier has to be the \
            brand's, because that is what makes the brand the element that absorbs the leftover \
            width and therefore the one that sits in the middle. Back on the readout it would pin \
            the brand against the tiles; on the monitor cluster the tiles would spread and both of \
            its neighbours would be squeezed.
            """)
    }

    // MARK: - 3. the counterweight: the header must stay still

    /// ⛔ GREEN BEFORE THIS COMMIT AND GREEN AFTER — this cannot catch today's code, and saying
    /// so is the point. It stands against the next edit, not this one: the loop readout is two
    /// `Text`s and a capsule, so "why is this a whole `struct`, fold it in" is a plausible tidy-up
    /// that a reviewer would wave through. Folding it in puts a ~10 Hz read in the ROOT chrome —
    /// an ancestor of every surface — and every rebuild tears down an open `.menu` Picker in the
    /// instrument below (10.76.50, four attempts to diagnose). `AnyView` is not a boundary.
    func testTheHeaderItselfReadsNothingLive() throws {
        let bar = try topBar()
        // ⛔ THE FIRST VERSION OF THIS LIST WAS BLIND TO THE FREEZE THAT ACTUALLY SHIPPED IN THIS
        // PROPERTY. It named only the playhead constructs — and per CLAUDE.md, 10.76.50 was
        // `WorkspaceView.topBar` reading `cameraRPPG.waveform` / `detectedBPM` / `isLocked` to
        // feed `PulseMonitorMini`. So the file whose whole job is "the header must stay still" did
        // not cover the one construct that made it move. Measured before adding: all five camera
        // tokens below are absent from `topBar` today, so this stays green and gains the case it
        // was written for. `cameraRPPG.isRunning` is deliberately NOT here — it is start/stop, it
        // is the tile's `active:` argument, and `LockCueDoesNotShoveTheControls` REQUIRES it.
        for construct in ["transport.position", "loopBars", "@AppStorage", "TimelineView",
                          "cameraRPPG.waveform", "cameraRPPG.detectedBPM",
                          "cameraRPPG.confidence", "cameraRPPG.displayBPM", "latestBio"] {
            let leaked = bar.filter { $0.contains(construct) }
            XCTAssertTrue(leaked.isEmpty, """
                `\(construct)` appeared inside `WorkspaceView.topBar`: \
                \(leaked.map { $0.trimmingCharacters(in: .whitespaces) }).

                This body is the ROOT chrome. A live read here rebuilds `WorkspaceView.body` at \
                the value's rate, and every rebuild tears down any open `.menu` Picker in the \
                surface below — the 10.76.50 freeze. The loop readout must stay a separate \
                `View` struct that reads `Transport` in ITS OWN body; `TransportPositionView` is \
                non-`private` for exactly that reason.
                """)
        }
    }

    // MARK: - reading the source

    /// `topBar`'s code lines, from its declaration to the `}` at its own indentation.
    ///
    /// Structural rather than a line count: the rationale block above `topBar` is 40+ lines and
    /// grows every time this header is touched. Stopping at "the next `private var`" would be a
    /// guess about what the next declaration's author types; `WorkspaceView` is 1000+ lines, so
    /// a window that ran on would report unrelated code under this file's name.
    private func topBar() throws -> [String] {
        let lines = try codeLines(Self.workspace)
        guard let start = lines.firstIndex(where: { $0.contains(Self.topBarDeclaration) }) else {
            throw XCTSkip("""
                `\(Self.topBarDeclaration)` is gone from \(Self.workspace) — if the header was \
                restructured this file should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(lines[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = lines[(start + 1)...].firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `topBar` has no closing brace at its own indentation — the file was reformatted \
                or the member restructured, and reading on would inspect the wrong lines
                """)
        }
        return Array(lines[(start + 1)..<end])
    }

    /// Code lines only — comments blanked by the ONE shared stripper (#453). Load-bearing and
    /// measured; see this file's header for the exact collision it prevents.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return SourceText.codeOnly(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent(Self.workspace).path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this file inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
