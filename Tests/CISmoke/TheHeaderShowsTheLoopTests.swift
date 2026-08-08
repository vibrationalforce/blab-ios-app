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
// ist wie auf der Website."* So the row is now **brand · position · monitors**, which is the
// order `docs/index.html` builds its `.nav-logo` in (mark, gap, name — the first column of the
// nav grid). The other two clauses of #490 are untouched and still pinned here.
//
// ⭐ WHY THIS FILE INVERTS ONE ASSERTION RATHER THAN LOSING IT. The founder is free to reverse
// himself; a guard that simply disappears when its subject moves leaves nothing watching. And
// the reversal repays a cost #490 wrote down in this very file: *"the PRICE is that a website
// link — not a 44 pt control — sits in the thumb corner."* With the brand leading, the monitor
// tiles hold the trailing edge again and they ARE the 44 pt controls (#113). The ordering is
// still pinned, only its direction changed — and the price note is now a paid one.
//
// ⛔ WHY DELETING THE STRIP WAS HONEST AND NOT DESTRUCTIVE, because it was itself a founder ask
// five days old (#384) and reversing one deserves a reason on the record. The spectrum was a
// SECOND COPY: `AnalysisSpectrumView` in the Field panel is the same ring, the same bands and
// the same frequency→visible-light colours, at a size where the number beside it is readable.
// Every collaborator it used (`EchoelRealFFT`, `SpectrumAnalysis`, `SpectralColor`,
// `AudioEngine.copyLatestOutputSamples`) keeps other callers, so nothing was orphaned. What the
// header lost is a duplicate; what it gained is the one fact a performer needs at a glance with
// both hands busy, which existed nowhere else on screen.
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
// ⚠️ HONEST GRADING FOR #501, measured against ITS parent (the #490 tree) rather than asserted,
// by transcribing `SourceText.codeOnly` and driving every assertion against both trees:
//   · **ONE** assertion is a regression — the brand's position. Parent: brand at index 83, tiles
//     at [46, 48, 57]; child: brand at 32, tiles at [111, 113, 122].
//   · **FOUR** are COUNTERWEIGHTS, green on both sides: the mount, the deleted file, the flank
//     count + its owner, and the no-live-read rule. Saying so is the point (#433) — they cannot
//     catch this commit; they exist so the NEXT tidy-up cannot quietly undo #490's half while
//     everyone is looking at #501's half.
//   · Note the flank assertion changed CATEGORY without changing a character: it was a
//     regression for #490 (two flanks → one) and is a counterweight now (one flank, moved from
//     leading to centre alignment). A guard's grade is a property of the tree it is measured
//     against, not of the guard.
//
// ⚠️ HONEST LIMITS, first rather than last. Every assertion here is a SOURCE-TEXT SCAN. There is
// no simulator in the blocking bundle, so this proves where text stands — never that the header
// reads well, never that the loop readout is legible at chrome size between a wordmark and three
// 44 pt tiles, and never that a Picker stays open on a device. NEEDS-FOUNDER-VERIFY: does the
// row read as "brand · position · monitors" — one lockup, one measurement, one control cluster —
// and does "Echoelmusic" still read at 14 pt once `minimumScaleFactor(0.7)` has had its way on a
// 360 pt phone? And: start biofeedback, play, open the Genre or Key menu below and leave it open
// for several seconds — does it stay?
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, ON **TWO** ASSERTIONS SINCE #501 — measured
// each time rather than assumed, and the history is the lesson. #490's first version named the
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

            Note the reason the removal was cheap: the SAME measurement still ships in \
            `AnalysisSpectrumView` (Field panel), at a size where its number is readable. The \
            header copy was a duplicate, not a capability.
            """)

        let bar = try topBar()
        XCTAssertFalse(bar.contains { $0.contains("HeaderSpectrumStrip(") }, """
            `topBar` constructs `HeaderSpectrumStrip` again.
            \(bar.joined(separator: "\n"))
            """)
    }

    // MARK: - 2. "das Logo und Echoelmusic ist wie auf der Website"

    /// The brand block is the FIRST child of the bar — the website's lockup order.
    ///
    /// ⛔ THIS ASSERTION WAS `brand > lastTile` UNTIL #501 AND IS NOW ITS MIRROR. It is the same
    /// property under a reversed founder decision one day later, kept rather than deleted: a
    /// guard that vanishes when its subject moves leaves the ordering unwatched in both
    /// directions, and this ordering has now been asked for explicitly twice.
    ///
    /// ⛔ THE DOC THIS REPLACES ALSO HAD A HISTORY WORTH KEEPING, because it is the reason the
    /// #113 argument is stated carefully here rather than waved. Under #490 it first claimed
    /// *"the tiles keep the trailing EDGE deliberately — they are controls with a 44 pt tap
    /// floor (#113)"* while the assertion below it required the opposite; that was corrected to
    /// name the PRICE instead (*"a website link — not a 44 pt control — sits in the thumb
    /// corner"*). #501 does not re-argue #113 — it simply makes that price zero again, because
    /// the tiles are trailing-most once more. An ergonomic claim is only worth making when the
    /// code underneath it is actually in that shape.
    ///
    /// ⚠️ WHAT IS **NOT** CLAIMED: that the wordmark matches the website's typography. It does
    /// not, deliberately — the site sets `uppercase` + 3 px tracking, which does not fit the
    /// chrome's width budget. The arithmetic is on the brand block in `WorkspaceView`. This
    /// asserts the ORDER, which is what the founder's arc drew; the type is a device look.
    func testTheBrandBlockLeadsTheHeader() throws {
        let bar = try topBar()
        guard let brand = bar.firstIndex(where: { $0.contains("openWebsite()") }) else {
            return XCTFail("`topBar` no longer calls `openWebsite()` — the brand block is gone")
        }
        guard let firstTile = bar.firstIndex(where: { $0.contains("MonitorMini") }) else {
            return XCTFail("`topBar` mounts no `…MonitorMini` tile — the output monitors are gone")
        }
        XCTAssertLessThan(brand, firstTile, """
            The brand block is built AFTER a monitor tile in `topBar`.

            Founder 2026-08-08, arc sweeping left from the circled brand: *"das Logo und \
            Echoelmusic ist wie auf der Website"*. The website's `.nav-logo` is the FIRST column \
            of its nav grid, so the brand leads and the monitors take the trailing edge — which \
            also returns the 44 pt controls (#113) to the thumb corner.

            brand at index \(brand), first monitor tile at index \(firstTile).
            \(bar.joined(separator: "\n"))
            """)
    }

    /// Exactly ONE greedy flank, and it is the readout.
    ///
    /// ⛔ THIS NUMBER WAS **TWO** UNTIL #490 and it is not a cosmetic edit. Two greedy flanks are
    /// what CENTRED the brand block: they split the leftover width evenly, so the block sat in
    /// the geometric middle and both sides compressed before anything could overlap. Once the
    /// brand took an EDGE there was nothing left to centre, so the second flank was removed.
    ///
    /// ⚠️ AND THE REASON SURVIVED #501 WITH ITS SIGN FLIPPED, which is worth naming because the
    /// sentence reads identically either way and could therefore be mistaken for stale prose:
    /// under #490 a second flank would have pulled the brand off the TRAILING edge; today it
    /// would pull it off the LEADING one. Either way the brand stops sitting where the founder
    /// put it. What DID change is the flank's alignment — `.leading` as the first child,
    /// `.center` as the middle one — and this test deliberately does not pin that: alignment is
    /// a look, the count and the owner are the invariant.
    ///
    /// The count is pinned HERE and nowhere else (`ChromeDynamicTypeTests` points at this file
    /// rather than repeating the number), so a future layout change has one place to update.
    func testExactlyOneGreedyFlankAndItIsTheReadout() throws {
        let bar = try topBar()
        let greedy = bar.enumerated().filter { $0.element.contains("maxWidth: .infinity") }
        XCTAssertEqual(greedy.count, 1, """
            Expected exactly one `.frame(maxWidth: .infinity)` in `topBar`, found \
            \(greedy.count): \(greedy.map { $0.element.trimmingCharacters(in: .whitespaces) }).

            One flank is what pins the brand to the leading edge and the monitors to the \
            trailing one. TWO would split the slack and pull the brand back off its edge — the \
            layout the founder moved away from, twice, in opposite directions. ZERO would let \
            the readout shrink to its content and leave the whole bar hugging the leading side \
            with the monitors adrift in the middle.
            """)

        guard let flank = greedy.first?.offset,
              let readout = bar.firstIndex(where: { $0.contains("TransportPositionView()") }) else {
            return  // the mount test above already reported the real failure
        }
        // ⚠️ `readout` OR `readout + 1`, not `+ 1` alone: the modifier may be chained on the same
        // physical line. The strict form was correct on the day it was written and would have
        // turned a correct tree red on a plausible reformat — a guard must fail for its stated
        // reason (#367), and "someone joined two lines" is not the reason.
        XCTAssertTrue(flank == readout || flank == readout + 1, """
            The greedy flank is not applied to `TransportPositionView`.

            It sits at index \(flank); the readout is built at index \(readout). The modifier has \
            to be the readout's own, because that is what makes the readout the element that \
            absorbs the leftover width. On the monitor cluster instead, the tiles would spread \
            and the loop position would be squeezed against the leading edge.
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
