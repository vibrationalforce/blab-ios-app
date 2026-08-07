// OneChromeControlHeightTests.swift
// Echoel — every chrome button is ONE size, and the readout beside them deliberately is not.
//
// WHAT THIS GUARDS (#481). Founder 2026-08-07, two screenshots with the transport row
// circled: *"Die größe der Buttons anpassen, die sollen immer gleichgroß sein. Orientiere
// dich an denen oben rechts."* Measured on the tree before the change:
//
//     startButton              64 × 56      EchoelStudioView
//     PlaybackToggleButton     44 × 48      WorkspaceView
//     BodyTempoField (compact) 76 × 32 · lock 30 × 32
//     TransportOverflowMenu    30 × 32      WorkspaceView
//     header tiles             38/38/54 × 32, tap frame 44   HeaderMonitors
//
// Three heights in one row. The header tiles — the founder's named reference — already
// agreed with each other, so #481 makes their size the one definition
// (`EchoelTheme.controlHeight` / `controlTapHeight`) and points every chrome button at it.
// This is the #416 shape: one decision (how tall is a chrome control) that used to be
// spelled in six files with nothing noticing when they disagreed.
//
// ⭐ THE HALF THAT EARNS THIS FILE IS THE COUNTERWEIGHT, NOT THE PIN. The obvious tidy-up
// after a "make them all the same size" commit is to finish the job on the one control that
// is still different — `PulseMonitorMini`, the analysis pill sharing that row at
// `minHeight: 48`. Doing that would be wrong twice over, and neither reason is visible from
// the pill's own frame line: its pulse trace is pinned at 34 pt and cannot fit inside 32,
// and the founder asked ONE WEEK EARLIER (#305, *"etwas größere Anzeige für Analyse ist
// besser"*) for that readout to be bigger. A display among controls is the hardware grammar
// this row copies. `testTheAnalysisReadoutIsNotSweptIntoTheButtonSize` is what stands
// between the next tidy-up and reversing a founder ask.
//
// ⚠️ HONEST LIMIT, FIRST AND NOT LAST: every assertion here is a SOURCE-TEXT SCAN. There is
// no simulator in this environment and the blocking bundle is `Tests/CISmoke`, so nothing
// here renders a view or measures a rectangle. A green means the sizes are still SPELLED as
// one definition — never that the row LOOKS even on a device, never that a finger lands on
// the 44 pt box. That remains a founder sighting.
//
// ⚠️ SECOND LIMIT: if the checkout is not at the path this file was compiled from it SKIPS
// rather than passes — a silent green on an unscanned tree is the `continue-on-error` lie
// the `doctor` skill exists to catch (#472: a `try` behind a directory-wide skip turned a
// deletion into a green).

import Foundation
import XCTest

final class OneChromeControlHeightTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree absent — this test inspects source text, so it SKIPS "
                          + "rather than reporting a green it did not earn")
        }
        return root
    }

    /// Code lines only. Load-bearing here and not prophylaxis (#453): the prose written for
    /// #481 QUOTES every old literal it replaced — "44 × 48", "height: 56" — inside the very
    /// comments that explain the new spelling, so a raw-text scan would fail on correct code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static let theme    = "Sources/Echoelmusic/Studio/EchoelTheme.swift"
    private static let monitors = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"
    private static let studio   = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let tempo    = "Sources/Echoelmusic/Studio/BodyTempoField.swift"
    private static let tile     = "Sources/Echoelmusic/Studio/EchoelIconTile.swift"

    // MARK: - The definition

    /// The two numbers are pinned because they are not ours to pick: they are what the three
    /// header tiles were already doing when the founder pointed at them, and 44 is the HIG
    /// floor (#113). A commit that changes either is changing the founder's reference, and
    /// should have to say so.
    func testTheOneSizeIsTheHeaderTilesSize() throws {
        let lines = try codeLines(Self.theme)
        XCTAssertTrue(lines.contains { $0.contains("static let controlHeight: CGFloat = 32") }, """
            EchoelTheme.controlHeight is no longer 32. That number is not a preference — it \
            is the visible height the three header tiles (clips · Lux · immersive) already \
            shared when the founder said "Orientiere dich an denen oben rechts" on \
            2026-08-07. Changing it re-sizes every chrome button in the app at once, which \
            is the point of the constant; do it deliberately and move this expectation in \
            the same commit.
            """)
        XCTAssertTrue(lines.contains { $0.contains("static let controlTapHeight: CGFloat = 44") }, """
            EchoelTheme.controlTapHeight is no longer 44. 44 pt is Apple's HIG tap floor and \
            the reason #113 exists; below it the chrome buttons stop being reliably hittable \
            while looking unchanged, which is the least debuggable class of UI defect.
            """)
    }

    // MARK: - Every chrome button reads it

    /// One case per control, anchored on a token unique to THAT control (#408) rather than on
    /// a bare `height:` that any frame in an 8000-line file could satisfy. Uniqueness is
    /// asserted, not assumed — the #408 defect was an anchor that matched a declaration
    /// instead of a call site, and it only surfaced when the guard went red on correct code.
    func testEveryChromeButtonReadsTheSharedHeight() throws {
        let cases: [(file: String, anchor: String, what: String)] = [
            (Self.monitors,  ".frame(width: 54, height: EchoelTheme.controlHeight)",
             "the immersive header tile"),
            (Self.studio,    ".frame(height: EchoelTheme.controlHeight)",
             "the start ▶/■ button (was FloatingVisualLayout.startButtonHeight = 56)"),
            (Self.workspace, ".frame(width: 44, height: EchoelTheme.controlHeight)",
             "the playback ⏸ button (was 44×48)"),
            // ⛔ THE `"•••"` CASE MOVED FILES WITH #482, not away. It used to be
            // `.frame(width: 30, height: EchoelTheme.controlHeight)` spelled inside
            // `TransportOverflowMenu`; the chip is now `EchoelIconTile`, so the height is read
            // once in the tile and the menu reads the tile. That is the same decision in a
            // smaller number of places, which is what #481 was for — but it means the anchor
            // has to follow the geometry rather than the control.
            (Self.tile,      ".frame(height: EchoelTheme.controlHeight)",
             "the shared chrome tile (the \"•••\" and the five action chips read it)"),
            (Self.tempo,     ".frame(width: 76, height: EchoelTheme.controlHeight)",
             "the compact tempo readout"),
            (Self.tempo,     ".frame(width: compact ? 30 : 34, height: EchoelTheme.controlHeight)",
             "the tempo-lock chip"),
        ]
        for c in cases {
            let lines = try codeLines(c.file)
            let hits = lines.filter { $0.contains(c.anchor) }.count
            XCTAssertEqual(hits, 1, """
                \(c.what): expected exactly one `\(c.anchor)` in \(c.file), found \(hits). \
                Zero means the control went back to a literal height and the row is uneven \
                again (founder 2026-08-07). More than one means this anchor no longer names \
                a single control, so the assertion above it is measuring something else — \
                re-anchor before trusting it.
                """)
        }
    }

    /// The header tiles are the REFERENCE, so both 38-wide ones must be on the constant too.
    /// Split from the case above only because they share one anchor and a count of 2 is the
    /// assertion rather than an ambiguity.
    func testBothSmallHeaderTilesAreOnTheConstant() throws {
        let lines = try codeLines(Self.monitors)
        let hits = lines.filter { $0.contains(".frame(width: 38, height: EchoelTheme.controlHeight)") }.count
        XCTAssertEqual(hits, 2, """
            Expected exactly 2 header tiles at 38 × controlHeight (clips and Lux), found \
            \(hits). These two plus the 54-wide immersive tile are the size the founder \
            named as the reference; if one drifts back to a literal, the thing every other \
            control is being measured against has itself moved.
            """)
    }

    // MARK: - Where the tap frame sits (order, not presence)

    /// ⭐ POSITION, NOT PRESENCE — and this is the assertion that would catch the plausible
    /// mistake rather than the careless one. `.frame(height: controlTapHeight)` must come
    /// AFTER the background and border, exactly as the header tiles spell it. Written BEFORE
    /// them the chip is PAINTED 44 tall: the picture grows and the hit area does not, which
    /// is the precise opposite of the #113 idiom and looks like a bug fix in a diff.
    ///
    /// ⚠️ WHAT THIS CANNOT SEE: that the resulting rectangle is 44 pt, or that a finger lands
    /// in it. It sees that the modifier is spelled after the paint, which is the only part
    /// that regresses textually.
    func testTheTapFrameComesAfterThePaintOnBothTransportButtons() throws {
        let studio = try codeLines(Self.studio)
        guard let paint = studio.firstIndex(where: {
            $0.contains("running ? EchoelTheme.fill : EchoelTheme.text")
        }) else {
            return XCTFail("""
                the start button's background line is gone from EchoelStudioView, so this \
                test has nothing to order against. If the button was restyled, re-anchor \
                here in the same commit rather than deleting the check.
                """)
        }
        guard let tap = studio.firstIndex(where: {
            $0.contains(".frame(height: EchoelTheme.controlTapHeight)")
        }) else {
            return XCTFail("""
                the start button lost its `.frame(height: EchoelTheme.controlTapHeight)`. \
                Its visible chip is \(32) pt tall — 73 % of the HIG 44 pt floor — so without \
                the tap frame the app's primary transport control is under the floor while \
                looking identical.
                """)
        }
        XCTAssertGreaterThan(tap, paint, """
            The start button's 44 pt tap frame moved ABOVE its `.background(...)`. That does \
            not enlarge the hit area — it enlarges the PICTURE: the rounded rect is then \
            painted 44 pt tall and the button stops matching the header tiles it was just \
            made to match. Put the frame back after the background and the border.
            """)

        let ws = try codeLines(Self.workspace)
        guard let wsPaint = ws.firstIndex(where: {
            $0.contains("transport.isPlaying ? EchoelTheme.accent : EchoelTheme.borderStrong")
        }), let wsTap = ws.firstIndex(where: {
            $0.contains(".frame(height: EchoelTheme.controlTapHeight)")
        }) else {
            return XCTFail("""
                the playback ⏸ button lost either its border line or its \
                `.frame(height: EchoelTheme.controlTapHeight)`. The tap frame must live \
                INSIDE the Button's label — a Button's hit area is its label's content \
                shape, so a frame applied outside `label:` changes layout and not hitting.
                """)
        }
        XCTAssertGreaterThan(wsTap, wsPaint, """
            The playback ⏸ button's tap frame moved above its border overlay — same defect \
            as the start button above: the chip gets painted 44 tall instead of the hit area \
            growing.
            """)
    }

    // MARK: - The shared tile (#482)

    /// `EchoelIconTile` is the row the founder asked for, in one declaration: *"alles … im
    /// selben Button Format in eine Reihe unter dem Play etc zusammengefasst"* (2026-08-07).
    /// Six chips read it — Record, Keep last, Export MIDI, Save, Open, "•••" — so a literal
    /// creeping back in here re-sizes six controls at once and nothing else would notice.
    ///
    /// Three claims, and the ORDER one is the load-bearing one for the same reason it is on
    /// the two transport buttons: written before the paint, the chip is DRAWN 44 tall instead
    /// of the hit area growing.
    func testTheSharedTileReadsBothConstantsInTheRightOrder() throws {
        let lines = try codeLines(Self.tile)
        guard let paint = lines.firstIndex(where: { $0.contains(".background(RoundedRectangle") })
        else {
            return XCTFail("""
                EchoelIconTile lost its `.background(RoundedRectangle…)`. If the chip was \
                restyled, re-anchor here in the same commit — this test's ordering claim has \
                nothing to measure against otherwise.
                """)
        }
        guard let tap = lines.firstIndex(where: {
            $0.contains("minHeight: EchoelTheme.controlTapHeight")
        }) else {
            return XCTFail("""
                EchoelIconTile lost its `minHeight: EchoelTheme.controlTapHeight`. That frame \
                IS the 44 pt floor for six chrome controls at once, and for the "•••" it is \
                the ONLY thing that works: a `Menu` presents from its label's layout bounds, \
                so the `contentShape` outset it carried before #482 was almost certainly a \
                no-op (`TapTargetFloorTests` says so in its own header).
                """)
        }
        XCTAssertGreaterThan(tap, paint, """
            EchoelIconTile's 44 pt frame moved ABOVE its background. That does not enlarge \
            the hit area — it enlarges the PICTURE, and it does so for every chip in the row \
            at once. Put it back after the background and the border.
            """)
        XCTAssertTrue(lines.contains { $0.contains(".frame(height: EchoelTheme.controlHeight)") }, """
            EchoelIconTile no longer pins its visible height to `EchoelTheme.controlHeight`. \
            That constant is the size of the three header tiles the founder pointed at on \
            2026-08-07 ("Orientiere dich an denen oben rechts"); a literal here silently \
            un-does #481 for the whole action row.
            """)
    }

    /// COUNTERWEIGHT. The point of the tile is that call sites stop spelling the chip. The
    /// obvious next edit — "this one needs to be a bit wider / rounder / brighter, I'll just
    /// add the modifiers at the call site" — is how the transport row grew three heights in
    /// the first place, and it would pass every assertion above.
    func testTheActionRowDoesNotRespellTheChip() throws {
        let studio = try codeLines(Self.studio)
        guard let open = studio.firstIndex(where: {
            $0.contains("private var quickActionRow: some View {")
        }) else {
            return XCTFail("""
                `quickActionRow` is gone from EchoelStudioView. That is the row the founder \
                asked for on 2026-08-07 ("in eine Reihe unter dem Play etc zusammengefasst"); \
                if it was renamed, move this anchor in the same commit rather than deleting \
                the check — five actions and the "•••" live in it.
                """)
        }
        // Terminate on the next member declaration, not on a brace count: the row is long and
        // comment-heavy, and a brace counter over comment-stripped lines is the fragile half.
        let end = studio[(open + 1)...].firstIndex { $0.contains("    private var ") || $0.contains("    private func ") }
            ?? studio.endIndex
        let row = studio[(open + 1)..<end]
        XCTAssertEqual(row.filter { $0.contains("EchoelIconTile(") }.count, 4, """
            `quickActionRow` should construct `EchoelIconTile` exactly four times (Record, \
            Export MIDI, Save, Open). Keep last builds its own inside `KeepLastLoopButton` \
            because it reads `pattern.tempo` in its own body (freeze law), and the "•••" \
            builds one inside `TransportOverflowMenu`. A different count means an action was \
            added or removed without this expectation moving with it.
            """)
        for bad in [".background(", ".overlay(", "cornerRadius", "RoundedRectangle"] {
            XCTAssertFalse(row.contains { $0.contains(bad) }, """
                `quickActionRow` spells `\(bad)` itself. The whole point of `EchoelIconTile` \
                is that the chip is declared ONCE — a call site that paints its own \
                background is how this row ended up with three different heights before \
                #481, and it would pass every other assertion in this file.
                """)
        }
    }

    // MARK: - Counterweight: the readout is NOT a button

    /// The analysis pill deliberately keeps `minHeight: 48` and is the one thing in that row
    /// that must NOT be swept into the uniform size. Two independent reasons, either alone
    /// sufficient — and neither is visible from the frame line itself, which is exactly why
    /// this is a test and not a comment:
    ///
    ///   1. `PulseTrace` inside it is pinned at 34 pt. 34 does not fit in 32.
    ///   2. The founder asked one week earlier (#305) for that readout to be BIGGER, not
    ///      smaller. A commit that shrinks it obeys the 2026-08-07 sentence by reversing the
    ///      2026-07-31 one.
    ///
    /// It is `minHeight` and not `height` for a third reason (#262): the pill carries TEXT,
    /// so at accessibility sizes it must GROW rather than let ≈53 pt digits spill past its
    /// border. `controlHeight` is a hard chip size for icon-only chrome and must never be
    /// applied to a text-bearing row.
    func testTheAnalysisReadoutIsNotSweptIntoTheButtonSize() throws {
        let lines = try codeLines(Self.monitors)
        XCTAssertTrue(lines.contains { $0.contains(".frame(minHeight: 48)") }, """
            PulseMonitorMini lost its `.frame(minHeight: 48)`. If this was "finishing" the \
            #481 uniform-size pass: don't. Its own pulse trace is `.frame(height: 34)` and \
            will not fit in a 32 pt chip, and the founder asked for this readout to be \
            LARGER on 2026-07-31 (#305, "etwas größere Anzeige für Analyse ist besser"). It \
            is a display among controls, not the odd one out.
            """)
        XCTAssertTrue(lines.contains { $0.contains(".frame(height: 34)") }, """
            The pulse trace is no longer pinned at 34 pt — which removes half the reason the \
            assertion above exists. If the trace was genuinely re-sized, re-derive whether \
            the pill can now share `controlHeight` and say so here; do not leave a \
            counterweight standing on a premise that has quietly gone.
            """)
        XCTAssertFalse(lines.contains { $0.contains("minHeight: EchoelTheme.controlHeight") }, """
            A text-bearing row is using `controlHeight` as its minimum. That constant is a \
            hard chip size for ICON-ONLY chrome; using it on anything that carries text \
            re-opens the #262 defect where ≈53 pt Dynamic Type spills past the drawn border.
            """)
    }

    // MARK: - Counterweight: the lock's hit area still adds up

    /// `BodyTempoField`'s lock is the one control that reaches 44 pt by OUTSET rather than by
    /// its own frame: 32 (chip) + 6 + 6 = 44 exactly, and `TapTargetFloorTests` pins both the
    /// outset and the 6 pt gap it grows into. That arithmetic silently depends on
    /// `controlHeight` — raise the constant and the outset over-reaches, lower it and the
    /// lock drops under the floor. Neither file says so; this does.
    func testTheOutsetLockStillReachesTheFloor() throws {
        let lines = try codeLines(Self.theme)
        guard lines.contains(where: { $0.contains("static let controlHeight: CGFloat = 32") }) else {
            return XCTFail("""
                controlHeight is no longer 32, so the tempo lock's hit height is no longer \
                32 + 6 + 6 = 44. Re-measure `contentShape(Rectangle().inset(by: -6))` in \
                BodyTempoField against the new value in the same commit — the outset is \
                sized against this constant and nothing else checks the sum.
                """)
        }
        let lock = try codeLines(Self.tempo)
        XCTAssertTrue(lock.contains { $0.contains("contentShape(Rectangle().inset(by: -6))") }, """
            The tempo lock lost its −6 outset. Its chip is controlHeight (32) tall and it is \
            the only chrome control without a tap frame of its own, so the outset IS its \
            floor: without it the control deciding whether the tempo follows the body is the \
            smallest target in the always-visible chrome.
            """)
    }
}
