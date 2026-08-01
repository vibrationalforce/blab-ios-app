// OneRedForRecordingTests.swift
// Echoel — "a take is running" is one colour, in one token, everywhere.
//
// WHAT THIS GUARDS (#363). The single most repeated state indicator in the app had THREE
// reds, in three files that never appear on screen together — which is exactly why no
// review caught it:
//   · `Color.red` (the SYSTEM red, which Apple is free to move between OS versions) —
//     the floating window's REC dot, its WAV glyph, its video glyph, and the studio's
//     fullscreen record button
//   · an inline `Color(red: 0.86, green: 0.22, blue: 0.20)` — the header's recording pip
//     and its border
//   · `EchoelTheme.danger` — everywhere else in the app that means red at all
//
// ⭐ WHY A SEPARATE TOKEN AND NOT JUST `danger`. "A take is running" and "something is
// wrong" are different messages that happen to share a colour today. `FloatingVisualWindow`
// shows both within two lines of each other: the running WAV clock (recording) and
// "WAV FAILED" (danger). One shared token means a later retune of the error red silently
// repaints every recording indicator in the app. Two names, one value, keeps that a
// decision rather than a side effect — and this file pins both halves, so "one value"
// cannot quietly become two again either.
//
// ⚠️ THE CONTRAST CLAIM, STATED HONESTLY. The kept red measures better than the retired
// one (5.50:1 vs 4.64:1 on black), but a 7 pt pip is NON-TEXT: WCAG 1.4.11 asks 3:1, and
// BOTH cleared it. So this was never an accessibility failure being fixed — it was a free
// choice between two adequate values, and the stronger one won. Writing it the other way
// round would have been the more satisfying sentence and the false one. The maths is still
// pinned below, because the floor that matters is the one nobody is watching: a future
// retune toward a darker red could cross 3:1 with nothing to stop it.
//
// ⚠️ A green here does not mean the strip looks right. There is no simulator in this
// environment and `Tests/CISmoke` is the blocking bundle, so nothing renders. If the
// checkout is not at the path this file was compiled from it SKIPS rather than passes.

import Foundation
import XCTest

final class OneRedForRecordingTests: XCTestCase {

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

    private func codeLines(_ path: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Every file that draws chrome. Scanned as a set so a NEW file reintroducing a system
    /// red is caught, not just the four this slice touched.
    private static let chromeFiles = [
        "Sources/Echoelmusic/Studio/EchoelStudioView.swift",
        "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift",
        "Sources/Echoelmusic/Studio/HeaderMonitors.swift",
        "Sources/Echoelmusic/Studio/BioStripView.swift"
    ]

    private static let theme = "Sources/Echoelmusic/Studio/EchoelTheme.swift"

    // MARK: - The token

    func testTheRecordingTokenExistsAndMatchesTheDangerValue() throws {
        let theme = try codeLines(Self.theme)
        let red = "Color(red: 0.90, green: 0.30, blue: 0.30)"
        XCTAssertTrue(theme.contains { $0.contains("static let recording = \(red)") }, """
            `EchoelTheme.recording` is gone or changed value. It is the one red for "a take \
            is running" — the REC dot, the running WAV and video glyphs, the header pip. If \
            you are retuning it deliberately, update the ratio assertion below in the SAME \
            commit; it is computed from these exact components and will otherwise pass while \
            describing a colour that no longer ships.
            """)
        XCTAssertTrue(theme.contains { $0.contains("static let danger  = \(red)") }, """
            `danger` and `recording` no longer share a value. That is ALLOWED — they are two \
            names precisely so they can diverge — but it must be a decision someone made, \
            not a drift. Change this assertion in the same commit and say which one moved.
            """)
    }

    /// The floor nobody watches. A 7 pt pip is non-text (WCAG 2.1 SC 1.4.11 → 3:1); the
    /// "WAV FAILED" label that uses the same components IS text (SC 1.4.3 → 4.5:1). The
    /// stricter of the two governs, so 4.5 is asserted.
    ///
    /// The components are re-typed here rather than read from `EchoelTheme` because the
    /// token is a `Color`, which exposes nothing to compute from. The test above is what
    /// binds them: it fails the moment the source stops spelling these numbers.
    func testTheRecordingRedClearsTheTextFloorOnBothGrounds() {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
            0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(_ a: Double, _ b: Double) -> Double {
            let (hi, lo) = a > b ? (a, b) : (b, a)
            return (hi + 0.05) / (lo + 0.05)
        }
        let red = luminance(0.90, 0.30, 0.30)
        let black = luminance(0, 0, 0)                      // EchoelTheme.bg
        let surface = luminance(0.055, 0.055, 0.070)        // EchoelTheme.surface

        let onBlack = contrast(red, black)
        XCTAssertGreaterThanOrEqual(onBlack, 4.5, """
            The recording red reads \(String(format: "%.2f", onBlack)):1 on the page ground, \
            under the 4.5:1 WCAG text floor. It is not only a pip: "WAV FAILED" is TEXT in \
            this colour family, and the failure message a performer must read mid-take is \
            the worst possible place for a marginal contrast.
            """)
        let onSurface = contrast(red, surface)
        XCTAssertGreaterThanOrEqual(onSurface, 4.5, """
            The recording red reads \(String(format: "%.2f", onSurface)):1 on `surface`, \
            under the 4.5:1 floor. The header pip sits on a panel fill, not on the page.
            """)
    }

    // MARK: - Nothing bypasses it

    func testNoChromeFileDrawsASystemOrInlineRed() throws {
        for path in Self.chromeFiles {
            let lines = try codeLines(path)
            let systemRed = lines.filter { $0.contains("Color.red") }
            XCTAssertTrue(systemRed.isEmpty, """
                \(path) draws `Color.red`. That is the SYSTEM red — Apple's, not Echoel's, \
                and free to shift between OS versions, so the app's recording indicators \
                would drift apart on an OS update with no commit to blame. Use \
                `EchoelTheme.recording` (a take is running) or `EchoelTheme.danger` \
                (something is wrong) and pick by MEANING. Offending line(s): \
                \(systemRed.map { $0.trimmingCharacters(in: .whitespaces) })
                """)
            let inlineRed = lines.filter { $0.contains("Color(red: 0.86, green: 0.22") }
            XCTAssertTrue(inlineRed.isEmpty, """
                \(path) reintroduced the retired inline header red \
                (0.86/0.22/0.20). One state, one token — see `EchoelTheme.recording`.
                """)
        }
    }

    // MARK: - The bio strip rejoined the app

    func testTheBioStripUsesTheBrandFaceAndTheSharedSurface() throws {
        let strip = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        XCTAssertFalse(strip.contains { $0.contains("design: .monospaced") }, """
            `BioStripView` set a monospaced SYSTEM face again. The SAME heart rate is shown \
            in `HeaderMonitors` and `BodyTempoField` in Atkinson Hyperlegible, so a system \
            face here means one number in two typefaces on one screen. Digits are held \
            steady by `.monospacedDigit()` per value — a tabular-figures request — which is \
            the house idiom and does not need a monospaced DESIGN (that also monospaced the \
            labels and units, which nothing asked for).
            """)
        XCTAssertTrue(strip.contains { $0.contains("EchoelTheme.font(12)") }, """
            `BioStripView` no longer sets the brand face on the strip. Every readout in this \
            app is Atkinson; the densest numeric one opting out was backwards, given that \
            the face is bundled precisely for legibility.
            """)
        XCTAssertFalse(strip.contains { $0.contains("Color(red: 0.07, green: 0.07, blue: 0.09)") }, """
            The strip's own panel grey is back. It was one step lighter than \
            `EchoelTheme.surface` (0.055/0.055/0.070) and justified nowhere, so the strip sat \
            a shade proud of every panel it neighbours — the kind of drift that reads as \
            sloppiness without anyone being able to name what is wrong.
            """)
        XCTAssertTrue(strip.contains { $0.contains(".background(EchoelTheme.surface)") }, """
            `BioStripView` no longer fills with the shared `surface` token.
            """)
    }
}
