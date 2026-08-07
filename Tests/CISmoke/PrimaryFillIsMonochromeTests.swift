// PrimaryFillIsMonochromeTests.swift
// Echoel — the bio-green means "your body"; a confirm button does not.
//
// WHAT THIS GUARDS (#364). `EchoelTheme` states the rule about itself: "in-app PRIMARY
// buttons fill with `.text`, NOT `.accent`. The bio-green `accent` is reserved for the
// body's live signal … never as page chrome." The keypad's OK key broke it — a solid
// bio-green field behind a black "OK". That keypad opens from EVERY `EchoelValueField` in
// the app, so it was simultaneously the most-seen green surface and the one with the least
// to do with the body: it confirms a number, whether that number is a cutoff, a tempo or a
// pan. A reserved colour that shows up on the most generic control in the product has
// stopped reserving anything.
//
// ⛔ THE FINDING THAT LED HERE WAS MOSTLY WRONG, AND THE TEST EXISTS PARTLY TO SAY SO. #364
// was filed off a grep: 113 `accent` call sites, therefore "green is being used as page
// chrome". Reading the CONTAINERS instead of the token, nearly every one of those is a case
// the rule explicitly allows — a `Toggle`/`Slider` tint (active state), an on/off glyph
// colour, a signal-bar fill (the value itself), or a row label inside a system `List`, where
// colour is the only thing that says a row is tappable. The literal violation on a reachable
// surface was exactly ONE. So this file pins the ONE, and pins the written boundary that
// stops the next sweep — mine included — from repainting an app that was already obeying its
// own rule.
//
// ⚠️ THIS IS NOT AN ACCESSIBILITY FIX and the numbers below say why: black on bio-green
// already read 11.59:1, black on off-white reads 15.89:1. Both clear every floor. The change
// is coherence, and calling it a11y would be the more flattering sentence and the less true
// one. What the contrast maths IS here for is the trap the change opens: `.text` fill with a
// `.text` label would be 1.00:1 — invisible — so the black label is now load-bearing in a way
// it was not when the fill was green.
//
// ⚠️ Source-text scan plus arithmetic on numbers PARSED from the token file (never
// hand-copied — the theme file makes that point about itself). No simulator; `Tests/CISmoke`
// is the blocking bundle. SKIPS rather than passes if the tree is not at this file's
// compile-time path.

import Foundation
import XCTest
@testable import Echoelmusic

final class PrimaryFillIsMonochromeTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func lines(_ path: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Code only — the theme file's prose quotes the very idioms this scans for.
    private func codeLines(_ path: String) throws -> [String] {
        try lines(path).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let pad   = "Sources/Echoelmusic/Studio/EchoelNumberPad.swift"
    private static let theme = "Sources/Echoelmusic/Studio/EchoelTheme.swift"

    /// Files that are chrome on a REACHABLE path — the root shell, the always-on header, the
    /// floating visual, and the two controls every panel is built from. Doorless surfaces
    /// (`ProUnlockView`, `SessionView`, `MeditationView`) are deliberately absent: they are
    /// parked, and pinning a colour in a view nobody can open is upkeep without a user.
    private static let chrome = [
        "Sources/Echoelmusic/Studio/EchoelStudioView.swift",
        "Sources/Echoelmusic/Studio/WorkspaceView.swift",
        "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift",
        "Sources/Echoelmusic/Studio/EchoelNumberPad.swift",
        "Sources/Echoelmusic/Studio/EchoelValueField.swift",
        "Sources/Echoelmusic/Studio/HeaderMonitors.swift",
        "Sources/Echoelmusic/Studio/BioStripView.swift",
        "Sources/Echoelmusic/Studio/BodyTempoField.swift",
        // #482 — the one shared chip format, six call sites. Added by the #482 Nachlese: it
        // is clean today (`EchoelTheme.text`/`fill`, no accent), and it is the single most
        // repeated chrome surface in the app, so leaving it out of this sweep would mean an
        // accent fill reached six controls at once with nothing looking.
        "Sources/Echoelmusic/Studio/EchoelIconTile.swift"
    ]

    // MARK: - The one violation, pinned

    func testTheKeypadConfirmKeyFillsWithTheMonochromePrimary() throws {
        let code = try codeLines(Self.pad)
        guard let ok = code.firstIndex(where: { $0.contains("private var okKey") }) else {
            return XCTFail("""
                `okKey` is gone from EchoelNumberPad. It is the keypad's only primary action \
                and the reason this file exists; if it was renamed, re-anchor here in the \
                same commit.
                """)
        }
        let body = code[ok..<Swift.min(ok + 8, code.endIndex)].joined(separator: " ")
        XCTAssertTrue(body.contains("tint: EchoelTheme.text"), """
            The keypad's OK key no longer fills with `EchoelTheme.text`. The website CI this \
            palette mirrors makes every primary action off-white-on-black, and `EchoelTheme` \
            says so in its own comment — bio-green is reserved for the body's live signal, \
            and a key that confirms a filter cutoff is not that.
            """)
        XCTAssertFalse(body.contains("tint: EchoelTheme.accent"), """
            The keypad's OK key is bio-green again. This keypad opens from every \
            `EchoelValueField` in the app, so it is the single most-seen surface the accent \
            can appear on — and the one with the least to do with the body.
            """)
        XCTAssertTrue(body.contains("EchoelTheme.onPrimary"), """
            The OK key's label is no longer `onPrimary` (black). With an off-white FILL this \
            is not a style detail: a `.text` label on a `.text` fill is 1.00:1, i.e. an \
            invisible button. The black label became load-bearing the moment the fill stopped \
            being green.
            """)
    }

    // MARK: - The maths, from the token file's own literals

    /// WCAG 2.x relative luminance for an sRGB triple.
    private func luminance(_ rgb: [Double]) -> Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])
    }

    private func contrast(_ a: Double, _ b: Double) -> Double {
        let hi = Swift.max(a, b), lo = Swift.min(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Every decimal literal on a line, in order. Used to read `accent`'s components out of
    /// the source rather than retyping them here — the theme file already argues that a
    /// hand-copied literal lets the renderer drift while the suite stays green.
    private func decimals(in line: String) -> [Double] {
        var out: [Double] = []
        var cur = ""
        for ch in line {
            if ch.isNumber || ch == "." {
                cur.append(ch)
            } else {
                if let v = Double(cur) { out.append(v) }
                cur = ""
            }
        }
        if let v = Double(cur) { out.append(v) }
        return out
    }

    func testTheMonochromePrimaryReadsBetterThanTheGreenItReplaced() throws {
        let theme = try lines(Self.theme)
        guard let accentLine = theme.first(where: { $0.contains("static let accent") }) else {
            return XCTFail("`EchoelTheme.accent` is gone — re-anchor this test with it.")
        }
        let parts = decimals(in: accentLine)
        XCTAssertGreaterThanOrEqual(parts.count, 3, """
            Could not read three colour components out of the `accent` declaration: \
            "\(accentLine.trimmingCharacters(in: .whitespaces))". If it became a named or \
            asset colour, this arithmetic has to be re-sourced rather than deleted.
            """)
        guard parts.count >= 3 else { return }

        let green = luminance([parts[0], parts[1], parts[2]])
        let c = EchoelTheme.textComponent
        let offWhite = luminance([c, c, c])
        let black = luminance([0, 0, 0])

        let onOffWhite = contrast(black, offWhite)
        let onGreen = contrast(black, green)

        XCTAssertGreaterThanOrEqual(onOffWhite, 4.5, """
            A black label on the off-white primary fill reads \
            \(String(format: "%.2f", onOffWhite)):1, under the 4.5:1 WCAG 1.4.3 floor for \
            text. If `text` was darkened, the primary button is the first place it breaks.
            """)
        XCTAssertGreaterThan(onOffWhite, onGreen, """
            The off-white primary (\(String(format: "%.2f", onOffWhite)):1) no longer reads \
            better than the bio-green it replaced (\(String(format: "%.2f", onGreen)):1). \
            The #364 change was argued as coherence FIRST and legibility second, in that \
            order and honestly — but it was never meant to cost contrast.
            """)

        // The trap the change opens, stated as arithmetic rather than trust.
        let sameOnSame = contrast(offWhite, offWhite)
        XCTAssertEqual(sameOnSame, 1.0, accuracy: 0.0001, """
            Sanity: a `.text` label on a `.text` fill is \(sameOnSame):1. This is why the OK \
            key's `onPrimary` label is asserted separately above.
            """)
    }

    // MARK: - No new green hero fills on a reachable surface

    func testNoReachableChromeFillsAButtonBackgroundWithTheAccent() throws {
        for path in Self.chrome {
            let offenders = try codeLines(path).filter {
                $0.contains("background(") && $0.contains("fill(EchoelTheme.accent)")
            }
            XCTAssertTrue(offenders.isEmpty, """
                \(path) paints a solid bio-green BACKGROUND behind content: \
                \(offenders.first?.trimmingCharacters(in: .whitespaces) ?? ""). That is the \
                one shape the rule in `EchoelTheme` actually forbids — a filled green area \
                under a label. Tints, on/off glyph colours and meter fills are all still \
                fine; see the boundary note beside the `accent` declaration before changing \
                anything on the strength of this failure.
                """)
        }
    }

    // MARK: - The boundary note has to survive, or the sweep repeats

    func testTheAccentBoundaryIsWrittenDownWhereTheTokenIs() throws {
        let joined = try lines(Self.theme).joined(separator: " ")
        XCTAssertTrue(joined.contains("WHAT THE RULE COVERS, EXACTLY"), """
            The note that bounds the accent rule is gone from `EchoelTheme`. Without it the \
            rule reads as "green is banned outside bio", which is how #364 was filed in the \
            first place — a grep of 113 call sites that would have repainted toggles, faders \
            and list affordances that were never in scope. The rule and its limits have to \
            live in the same place, or the next sweep re-derives the wrong one.
            """)
        XCTAssertTrue(joined.contains("READ THE WORD NUMERIC"), """
            The boundary note no longer points at CLAUDE.md's `EchoelValueField` precedent. \
            That cross-reference is the argument, not decoration: both are cases where \
            obeying a rule's letter would break the thing the rule exists to protect.
            """)
    }
}
