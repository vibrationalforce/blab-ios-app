// TheHeaderShowsTheLoopTests.swift
// Echoel — the loop length lives in the brand header, and the read stays in its leaf. #490.
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
// ⚠️ HONEST GRADING, measured against the parent tree rather than asserted:
//   · FOUR assertions are genuine regressions — the mount, the deleted file, the flank count,
//     and the brand's position. Each is red before this commit and green after.
//   · ONE is a COUNTERWEIGHT, green on both sides: the header must contain no live read. It
//     cannot catch today's code; it exists because the obvious next tidy-up ("it's just two
//     labels, fold them in") is exactly the ship-blocker above.
//
// ⚠️ HONEST LIMITS, first rather than last. Every assertion here is a SOURCE-TEXT SCAN. There is
// no simulator in the blocking bundle, so this proves where text stands — never that the header
// reads well, never that the loop readout is legible at chrome size beside three 44 pt tiles,
// and never that a Picker stays open on a device. NEEDS-FOUNDER-VERIFY: does the header read as
// "position · monitors · brand" rather than as three unrelated things? And: start biofeedback,
// play, open the Genre or Key menu below and leave it open for several seconds — does it stay?
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE — measured, and the first version of this
// paragraph named the WRONG collision, which is the #443 defect committed in the act of claiming
// a method. It said a raw scan would count the retracted trailing flank as a second
// `maxWidth: .infinity`. It would not: that quotation is wrapped across two comment lines, so
// the substring never forms. Running both forms over the same file: raw and stripped agree on
// the flank count (1), on the mount, on the ordering and on the deleted strip — they differ on
// exactly ONE assertion, `testTheHeaderItselfReadsNothingLive`, because the comment introducing
// the readout says the leaf "reads `Transport` and `@AppStorage` only". Raw: leaked. Stripped:
// clean. So the stripper is genuinely load-bearing, on the counterweight rather than on the
// count — the same collision #486 hit, and the reason this repo cannot run negative scans on raw
// text: it writes down what it removed, so the scan meets its own obituary.
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

    // MARK: - 2. "E Logo wieder nach rechts"

    /// The brand block is the LAST child of the bar.
    ///
    /// This is the assertion that carries the founder's first clause, and it needs saying
    /// because the instruction only means something in this exact form: BEFORE this commit the
    /// brand already sat between the greedy flank and the monitor cluster, so "right of where it
    /// is" and "right of the tiles" are the same sentence. Anything less is a no-op that would
    /// have looked like compliance.
    ///
    /// The tiles keep the trailing EDGE deliberately — they are controls with a 44 pt tap floor
    /// (#113) and the brand is a link to a website. Putting a link where the thumb expects the
    /// visual toggle would be the worse trade, and it is the "tidier" arrangement, so it is
    /// pinned rather than remembered.
    func testTheBrandBlockSitsAfterTheMonitorTiles() throws {
        let bar = try topBar()
        guard let brand = bar.firstIndex(where: { $0.contains("openWebsite()") }) else {
            return XCTFail("`topBar` no longer calls `openWebsite()` — the brand block is gone")
        }
        guard let lastTile = bar.lastIndex(where: { $0.contains("MonitorMini") }) else {
            return XCTFail("`topBar` mounts no `…MonitorMini` tile — the output monitors are gone")
        }
        XCTAssertGreaterThan(brand, lastTile, """
            The brand block is built BEFORE the last monitor tile in `topBar`.

            Founder 2026-08-07: *"E Logo wieder nach rechts"*. It has to come after the tiles — \
            before them is where it already was, so that ordering is the instruction unfulfilled.

            brand at index \(brand), last monitor tile at index \(lastTile).
            \(bar.joined(separator: "\n"))
            """)
    }

    /// Exactly ONE greedy flank, and it is the readout.
    ///
    /// ⛔ THIS NUMBER WAS **TWO** UNTIL #490 and it is not a cosmetic edit. Two greedy flanks are
    /// what CENTRED the brand block: they split the leftover width evenly, so the block sat in
    /// the geometric middle and both sides compressed before anything could overlap. With the
    /// brand at the trailing edge there is nothing left to centre, so the trailing flank was
    /// removed — leaving it would make the readout and the tile cluster split the slack and push
    /// the brand back towards the middle, undoing the one thing the founder asked for.
    ///
    /// The count is pinned HERE and nowhere else (`ChromeDynamicTypeTests` points at this file
    /// rather than repeating the number), so a future layout change has one place to update.
    func testExactlyOneGreedyFlankAndItIsTheReadout() throws {
        let bar = try topBar()
        let greedy = bar.enumerated().filter { $0.element.contains("maxWidth: .infinity") }
        XCTAssertEqual(greedy.count, 1, """
            Expected exactly one `.frame(maxWidth: .infinity)` in `topBar`, found \
            \(greedy.count): \(greedy.map { $0.element.trimmingCharacters(in: .whitespaces) }).

            One flank is what pushes the monitors and the brand against the trailing edge. TWO \
            would split the slack and re-centre the brand — the layout the founder just moved \
            away from. ZERO would let the leading readout shrink to its content and leave the \
            whole bar hugging the leading side.
            """)

        guard let flank = greedy.first?.offset,
              let readout = bar.firstIndex(where: { $0.contains("TransportPositionView()") }) else {
            return  // the mount test above already reported the real failure
        }
        XCTAssertEqual(flank, readout + 1, """
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
        for construct in ["transport.position", "loopBars", "@AppStorage", "TimelineView"] {
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
