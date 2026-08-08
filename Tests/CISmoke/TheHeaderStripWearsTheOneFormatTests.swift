// TheHeaderStripWearsTheOneFormatTests.swift
// Echoel — #502 slice 1. `CompositionHeaderStrip` joins the one chrome-control format.
//
// ⭐ THE ASK. Founder, 2026-08-08, second red outline on the v10.79.377 (2494) screenshot:
// *"Den anderen rot umrandeten Bereich noch einmal auf Usability und kompactheit im
// einheitlichen Design intelligent anordnen und aufräumen."* The outline covers every band
// between the brand header and the panel content — eight of them, ~273 pt, roughly 36 % of the
// usable screen on an iPhone 15 before any content begins (arithmetic over constants; see
// `scratchpads/PLAN_TIDY_THE_INSTRUMENT_BAND_2026-08-08.md`).
//
// ⭐ WHAT THE PLAN'S COUNCIL PICKED, and why this file guards THAT rather than compactness.
// Measured before anything moved, the outline contained FOUR control grammars, and three of
// them were founder-decided: the `EchoelIconTile` rows (#481/#482 — *"die sollen immer
// gleichgroß sein"*), the transport row's four deliberate shapes (#307, #305, #455), and the
// chip pills. The fourth was this strip — `Text(caption).font(11).dim` + a bare
// `Picker(.menu)`, the ONE surface in that outline with no fill, no border, no radius and no
// tap floor. It was built 2026-07-14 and simply did not take part in #481/#483. So slice 1 is
// the grammar, not the height: nothing is hidden, nothing is reordered, and no founder
// decision is reversed.
//
// ⚠️ HONEST LIMIT, FIRST: THIS IS UNIFORMITY, NOT COMPACTNESS, AND IT COSTS +4 pt. The
// controls go from ~22 pt tall to the 44 pt HIG floor (#113); the bar's own
// `.padding(.vertical, 4)` is dropped in the same slice because each 44 pt frame already
// leaves 6 pt of margin around its 32 pt chip, so the band renders 40 → 44 rather than 40 →
// 52. Width grows too: 12 pt of chip padding on six controls is +144 pt against −20 pt from
// the row gap dropping 12 → 8, in a bar that already scrolls horizontally — further to
// scroll, nothing clipped. Both numbers are arithmetic over constants, not a rendered
// measurement. The real compaction (removing a band) reverses a written 2026-07-14 founder
// decision and is registered as hold-for-founder in the plan, not done here.
//
// ⚠️ AND WHAT THIS FILE CANNOT DO, said before what it can. Every assertion is a SOURCE SCAN.
// There is no simulator here and `CompositionHeaderStrip` builds behind `#if
// canImport(SwiftUI)`, so "the bar looks even on a device", "a thumb hits the 44 pt", "the
// borders do not read as noise at six-in-a-row" and "VoiceOver still reads caption then value
// in a useful order" are four device looks and all four are open.
//
// ⚠️ HONEST GRADING, measured against the parent tree (`HEAD` at the time of writing) by
// transcribing `SourceText.codeOnly` and driving every assertion against both trees rather
// than asserting it:
//   · ONE regression — the chip is absent on the parent — reported by FOUR assertions
//     (1a…1d). Three of those four are red by ANCHOR ABSENCE (`chromed` and
//     `controlTapHeight` do not exist there at all), which is one absence reported four
//     times, not four findings (#486). Counting them as four would be the #433 defect in the
//     flattering direction.
//   · THREE are COUNTERWEIGHTS, green on both sides (2a, 2b, 2c) — and they are the half that
//     earns its place going forward: they reject the three tidy-ups this slice invites.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, ON EXACTLY ONE ASSERTION, and that is
// measured rather than assumed (#484/#485 each had to retract the stronger claim, #486
// twice). `chromed: false` occurs **3× raw / 1× stripped** in this struct — the two extra are
// the retraction prose this slice writes to explain why the A4 row is the single exception.
// A raw scan would be red on CORRECT code. `EchoelTheme.borderStrong` is 1/1 either way,
// because the prose names it without the type prefix. Same #486/#491 collision as ever: this
// repo writes down what it did, and a counting scan meets its own explanation.

import Foundation
import XCTest
@testable import Echoelmusic

/// Thrown when a scan anchor is gone. An uncaught error in a `throws` test FAILS — `XCTSkip`
/// would have been green on a tree that lost the whole surface (the #454 lesson).
private struct StripAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

final class TheHeaderStripWearsTheOneFormatTests: XCTestCase {

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"

    /// The five tokens that ARE the format. Every one of them is read from `EchoelTheme`, so a
    /// design change moves all six controls at once — which is the entire point of #481/#483
    /// and the reason a literal here would be a regression even if it rendered identically.
    private static let chipTokens = ["EchoelTheme.fill",
                                     "EchoelTheme.borderStrong",
                                     "cornerRadius: EchoelTheme.radius",
                                     "EchoelTheme.controlHeight",
                                     "EchoelTheme.controlTapHeight"]

    // MARK: - 1. the format lives in ONE place

    /// 1a. RED on the parent, for its stated reason: the helper exists there and paints
    /// nothing. This is the assertion the slice is about.
    func testTheLabeledHelperCarriesTheWholeFormat() throws {
        let helper = try labeledHelper()
        for token in Self.chipTokens {
            XCTAssertTrue(helper.contains(token), """
                `CompositionHeaderStrip.labeled` no longer reads `\(token)`.

                #502 slice 1 put the one chrome-control format INSIDE this helper so the six \
                controls of the strip are uniform by construction rather than by six edits \
                agreeing with each other (#416 — the defect that gave the transport row three \
                heights). If a control genuinely needs to look different, that is a founder-\
                visible design call: rewrite this file with it rather than deleting the check.

                Helper scanned (comments blanked by SourceText.codeOnly):
                \(helper)
                """)
        }
    }

    /// 1b. RED on the parent by ANCHOR ABSENCE — `controlTapHeight` is not in that helper at
    /// all. Named as such rather than counted as an independent finding (#486).
    ///
    /// The tap floor is deliberately OUTSIDE the `chromed` condition. A4 is a control too, and
    /// its 32 pt box is exactly as far under the 44 pt HIG floor (#113) as the pickers were.
    /// Folding it in would look tidier and would silently exempt the one row in this bar where
    /// a mis-tap costs something real: it retunes every voice and it is persisted (see the
    /// `horizontalScrub: false` block, which exists because a stray SCROLL already did that).
    func testTheTapFloorIsNotGatedOnTheChipTreatment() throws {
        let helper = try labeledHelper()
        // `components(separatedBy:)`, not `split(separator:)`: the latter has several
        // overloads (Character, Collection, RegexComponent) and this bundle has no local
        // compiler to disambiguate against — #488 lost a whole gate cycle to one line of
        // Swift syntax that could not be checked here.
        let tapLines = helper.components(separatedBy: "\n")
            .filter { $0.contains("EchoelTheme.controlTapHeight") }
        XCTAssertFalse(tapLines.isEmpty, """
            `CompositionHeaderStrip.labeled` applies no `EchoelTheme.controlTapHeight` frame — \
            every control in this always-visible bar is back under the 44 pt HIG floor (#113).
            """)
        for line in tapLines {
            XCTAssertFalse(line.contains("chromed"), """
                The 44 pt tap floor is gated on `chromed`: \(line)

                That exempts the A4 concert-pitch row — the ONE control in this bar where a \
                mis-tap retunes every voice and persists. The chip PAINT is conditional \
                because `EchoelValueField` already draws the identical box; the HIT AREA is \
                not, because A4 is as small a target as the pickers were.
                """)
        }
    }

    /// 1c. RED on the parent by anchor absence (0 ≠ 1). This is the #416 half: not "the
    /// format exists" but "it exists ONCE". A future control that hand-rolls its own border at
    /// its call site is exactly how a bar drifts back into four grammars, and it is invisible
    /// in a diff that only adds lines.
    func testNoCallSiteRollsItsOwnBorder() throws {
        let strip = try stripStruct()
        let borders = strip.components(separatedBy: "EchoelTheme.borderStrong").count - 1
        XCTAssertEqual(borders, 1, """
            `CompositionHeaderStrip` spells `EchoelTheme.borderStrong` \(borders) times, \
            expected exactly 1 (inside `labeled`).

            More than one means a control paints its own chip beside the shared one — the \
            drift #481/#483 closed for the rest of the chrome. Zero means the format left the \
            bar entirely.
            """)
    }

    /// 1d. RED on the parent by anchor absence. The exception must stay exactly one, and it
    /// must be the row that already has the box: `EchoelValueField` paints the same `radius`,
    /// the same `fill` and the same `borderStrong` (read its `valueBox`), so chroming it would
    /// draw a second border around the first. It is not an opt-out from the format — it is the
    /// row that always had it.
    func testExactlyOneRowOptsOutOfTheChipAndItIsTheOneWithItsOwnBox() throws {
        let strip = try stripStruct()
        let optOuts = strip.components(separatedBy: "chromed: false").count - 1
        XCTAssertEqual(optOuts, 1, """
            `CompositionHeaderStrip` has \(optOuts) `chromed: false` call sites, expected 1.

            More than one is the format leaking away a row at a time. Zero means the A4 field \
            gets a second border painted around the one `EchoelValueField` already draws.
            """)
        // The opt-out must be the A4 row specifically — otherwise a later edit could move it
        // to a Picker and still pass the count above.
        guard let range = strip.range(of: "chromed: false") else {
            throw StripAnchorMissing(reason: "no `chromed: false` to locate — the count "
                                     + "assertion above should have caught this first")
        }
        let after = String(strip[range.upperBound...].prefix(2_000))
        XCTAssertTrue(after.contains("EchoelValueField("), """
            The one `chromed: false` row does not build an `EchoelValueField` within the next \
            2 000 characters — the exception moved to a control that does NOT bring its own \
            box, so that control is now unpainted while A4 is double-painted.
            """)
    }

    // MARK: - 2. counterweights — green on both sides, and that is the point

    /// 2a. `minHeight`, NEVER a hard `height`, for anything in this bar. `EchoelTheme`'s own
    /// doc draws the line: `controlHeight` is a hard chip size for ICON-ONLY chrome
    /// (`EchoelIconTile` uses it that way, correctly, in its own file); everything that
    /// carries TEXT uses a minimum so it can grow. A hard height here re-opens the
    /// accessibility-size overflow #262 closed — the text does not shrink, it overspills and
    /// the next bar's opaque background paints over it.
    func testTheBarUsesTheTokenAsAFloorNotAFixedHeight() throws {
        let text = try source(Self.workspace)
        XCTAssertFalse(text.contains(".frame(height: EchoelTheme.controlHeight"), """
            `WorkspaceView` pins `.frame(height: EchoelTheme.controlHeight…)`.

            This bar carries TEXT — Genre, Key, Scale, Tone system, Note names, Mode and the \
            A4 value. As a fixed height the token is also a CEILING, and at accessibility text \
            sizes the content overflows it (#262). Icon-only chrome may pin it; this may not.
            """)
        XCTAssertFalse(text.contains("maxHeight: EchoelTheme.controlHeight"), """
            `WorkspaceView` caps at `maxHeight: EchoelTheme.controlHeight`. Beside the \
            surviving minimum that is the fixed height again, spelled so the check above \
            stays green.
            """)
    }

    /// 2b. THE FREEZE LAW, and this bar is the reason it matters here rather than in general:
    /// it hosts six `.menu` Pickers. A high-frequency `@Observable` read anywhere in its
    /// `body` registers the whole host as an observer and tears down an open popover on every
    /// rebuild (10.76.41/50). `transport` IS in this struct — deliberately, read only in
    /// `modeBinding`'s `set` closure, so the ~10 Hz tempo churn never subscribes the host. The
    /// tempting simplification is to read it in `body` and drop the closure.
    func testThePickerHostDoesNotReadTheLiveTransport() throws {
        let body = try stripBody()
        XCTAssertFalse(body.contains("transport."), """
            `CompositionHeaderStrip.body` reads `transport.` directly.

            This body hosts six `.menu` Pickers. `transport.tempo` runs along with the body \
            while the tempo is unlocked, so reading it here rebuilds the host ~10×/s and tears \
            down any open Picker popover — the freeze the founder reported twice \
            (10.76.41/50). The seed for `lockedBPM` belongs in `modeBinding`'s `set` closure, \
            which is where it is.

            Body scanned:
            \(body)
            """)
    }

    /// 2c. THE #343 COUNTERWEIGHT, and the one that makes the rest mean anything. Every
    /// assertion above is satisfied by a strip that lost all seven of its controls — the
    /// format would be "consistent" across nothing. This pins that the bar still BUILDS the
    /// musical identity the 2026-07-14 decision put in the chrome ("lebt HIER in der Chrome,
    /// immer sichtbar, eine dünne Zeile"), and that every control reaches the screen through
    /// the shared helper rather than beside it.
    func testTheBarStillBuildsAllSevenControlsThroughTheHelper() throws {
        let strip = try stripStruct()
        for caption in ["Genre", "Key", "Scale", "Tone system", "Note names", "Mode"] {
            XCTAssertTrue(strip.contains("labeled(\"\(caption)\")"), """
                `CompositionHeaderStrip` no longer builds `labeled("\(caption)")`.

                Either the control is gone — which reverses the 2026-07-14 decision that the \
                musical identity lives in the chrome, and is a founder call, not a tidy-up — \
                or it is built OUTSIDE the shared helper, which is how the bar drifts back \
                into more than one grammar.
                """)
        }
        XCTAssertTrue(strip.contains("labeled(\"A4\", chromed: false)"), """
            The A4 concert-pitch row is no longer built as `labeled("A4", chromed: false)`.

            It is the seventh control and the one exception; if it left the helper entirely it \
            also left the 44 pt tap floor, on the row where a stray gesture retunes every \
            voice and persists (#391).
            """)
    }

    // MARK: - extraction

    private func stripStruct() throws -> String {
        try declarationBody(of: "struct CompositionHeaderStrip: View {", in: Self.workspace)
    }

    private func stripBody() throws -> String {
        let strip = try stripStruct()
        guard let body = braceBody(of: "var body: some View {", in: strip) else {
            throw StripAnchorMissing(reason: """
                `CompositionHeaderStrip` has no `var body: some View {` — re-anchor this scan; \
                do not leave it silent.
                """)
        }
        return body
    }

    /// Anchored on the helper's SIGNATURE TAIL rather than on `private func labeled`, because
    /// the signature spans lines and the closing `-> some View {` is the brace this scan needs.
    private func labeledHelper() throws -> String {
        let strip = try stripStruct()
        let key = "@ViewBuilder content: () -> Content) -> some View {"
        guard let helper = braceBody(of: key, in: strip) else {
            throw StripAnchorMissing(reason: """
                `CompositionHeaderStrip` no longer declares a `labeled(_:chromed:content:)` \
                helper ending in `\(key)` — the shared format has no home. Re-anchor this \
                scan; do not leave it silent.
                """)
        }
        return helper
    }

    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let body = braceBody(of: key, in: text) else {
            throw StripAnchorMissing(reason: """
                `\(key)` not found in \(relativePath) — renamed, reflowed or removed. \
                Re-anchor this scan; do not leave it silent.
                """)
        }
        return body
    }

    private func braceBody(of key: String, in text: String) -> String? {
        guard let start = text.range(of: key) else { return nil }
        var depth = 1
        var body = ""
        var i = start.upperBound
        while i < text.endIndex, depth > 0 {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            body.append(c)
            i = text.index(after: i)
        }
        XCTAssertEqual(depth, 0, "unbalanced braces while extracting `\(key)` — scan is unsound")
        return body
    }

    /// Comments blanked via the ONE shared definition (#453) — a private stripper here would
    /// be the twelfth copy that file exists to end.
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw StripAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
