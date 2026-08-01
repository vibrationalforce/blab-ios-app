// ControlBoundaryIsInteractiveTests.swift
// Echoel — was man antippen kann, sieht auch antippbar aus.
//
// WHAT THIS GUARDS (#367). `EchoelTheme` declares two boundary tokens and states the rule
// about itself: `border` is DECORATIVE — hairlines, dividers, a panel card's outline, 1.16:1
// against black — and its own doc says "Do not use it on anything tappable". `borderStrong`
// is the INTERACTIVE one, ~3.7:1, "the outline that says this is a control".
//
// Three always-on chrome CONTROLS were drawn with the decorative token:
//   · the primary transport Play/Pause (`WorkspaceView`) — 44×48, the biggest and most-used
//     control in the app. It renders in `EchoelStudioView.startControlRow` beside
//     `startButton` and `PulseMonitorMiniLive`, and BOTH of those already used
//     `borderStrong`. (⛔ The first version of this line, and the fix comment in
//     `WorkspaceView` itself, named the 30×32 "•••" as its neighbour. That control lives in
//     `TransportBar`, two rows and a divider above — the adjacency was read off the FILE,
//     not off the screen. Same defect as the grid this session attributed to the wrong panel
//     three times; being about a token instead of a layout did not make it a different
//     mistake.);
//   · the tempo lock (`BodyTempoField`);
//   · the Clips tile (`HeaderMonitors`), whose two sibling tiles were already correct.
// So the founder's chrome screenshot had, in one row, tiles outlined like buttons next to
// tiles outlined like dividers — and the single most important control was the faintest.
//
// ⚠️ THE BOUNDARY THIS FILE PINS IS "CONTROL", NOT "STROKE", and that distinction is the
// whole point. `BodyTempoField` keeps TWO `border` strokes on purpose: they outline the
// FOLLOWING tempo READOUT, and the comment there says why — "a tap opens nothing (it follows
// the body)". A reading is ornament. `WorkspaceView` likewise keeps `border` on two
// `Divider()`s, which is literally what the token is for. This file asserts those SURVIVE,
// because the cheap wrong fix here is a grep-and-replace sweep — exactly the #364 mistake,
// where a finding built from 113 call sites concluded the app was misusing a colour and the
// real violation count was one.
//
// ⚠️ AND IT PINS A COUNT THE PROSE COULD NOT. The token's applied-to list called them "the
// three always-on header tiles" — one settled-sounding phrase that was wrong in both
// directions at once: the third tile was still decorative, and a FOURTH always-on element in
// the same file (`PulseMonitorMini`) was already interactive and had never been listed. A
// contract that counts its members in prose cannot be checked by reading it. This counts.
//
// Source-text scan; no simulator. `Tests/CISmoke` is the blocking bundle. SKIPS rather than
// passes if the tree is not at this file's compile-time path.

import Foundation
import XCTest
@testable import Echoelmusic

final class ControlBoundaryIsInteractiveTests: XCTestCase {

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let tempo     = "Sources/Echoelmusic/Studio/BodyTempoField.swift"
    private static let monitors  = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"
    private static let theme     = "Sources/Echoelmusic/Studio/EchoelTheme.swift"

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

    /// Code lines only. The prose in this repo names both tokens constantly — including the
    /// comments this very commit added next to the fixed lines — so matching comments would
    /// make the guard react to explanations instead of to code.
    private func code(_ source: [String]) -> [String] {
        source.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.isEmpty
        }
    }

    /// `EchoelTheme.border` as an ARGUMENT, never matching `borderStrong`. The delimiter is
    /// what does the work: `borderStrong,` is not `border,`.
    private func usesDecorativeToken(_ line: String) -> Bool {
        line.contains("EchoelTheme.border,") || line.contains("EchoelTheme.border)")
    }

    /// The declaration's own lines, ending at the next TOP-LEVEL declaration.
    ///
    /// ⛔ The first version of this helper took its terminators as `contains` needles and was
    /// handed `"\nstruct "` — a string no single line can ever contain. The window therefore
    /// ran to end-of-file, and the transport test would have scanned every later struct in
    /// `WorkspaceView` too: it would have gone red for the `Divider()` strokes 400 lines
    /// below, which this same file asserts must STAY decorative. Two of this file's own
    /// tests would have contradicted each other. Terminators are matched as a PREFIX of the
    /// trimmed line now, so they mean what they read as.
    ///
    /// ⛔ AND IT USED TO **SKIP** WHEN THE OPENING WAS NOT FOUND, which made the one test using
    /// it self-disarming: rename `PlaybackToggleButton`, or merely reformat its declaration
    /// line, and the guard went silently green forever. Two sibling tests in this same file
    /// already used `XCTFail` for exactly that case — the right idiom was three screens away
    /// and not applied here. A source-text guard may skip when the TREE is absent (it has
    /// nothing to read); it must never skip because the THING IT GUARDS moved.
    private func declaration(_ source: [String], opening: String) throws -> [String] {
        guard let start = source.firstIndex(where: { $0.contains(opening) }) else {
            XCTFail("""
                declaration '\(opening)' not found — it was renamed or reformatted. Re-point \
                this guard at the new spelling; do NOT delete the test. Until you do, the \
                control it pins has no guard at all.
                """)
            return []
        }
        let terminators = ["struct ", "private struct ", "final class ", "extension ", "enum "]
        var end = source.count
        var i = start + 1
        while i < source.count {
            let t = source[i].trimmingCharacters(in: .whitespaces)
            if terminators.contains(where: { t.hasPrefix($0) }) {
                end = i
                break
            }
            i += 1
        }
        return Array(source[start..<end])
    }

    // MARK: - The three controls that were wrong

    func testThePrimaryTransportButtonIsOutlinedAsAControl() throws {
        let body = code(try declaration(try lines(Self.workspace),
                                        opening: "struct PlaybackToggleButton: View {"))
        let offenders = body.filter(usesDecorativeToken)
        XCTAssertTrue(offenders.isEmpty, """
            #367: the app's primary Play/Pause is outlined with the DECORATIVE token again. \
            `EchoelTheme.border` is 1.16:1 and its own doc says "Do not use it on anything \
            tappable"; its two real on-screen neighbours in `startControlRow` — `startButton` \
            and `PulseMonitorMiniLive` — both use `borderStrong`. Offending line(s): \
            \(offenders.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        // ⛔ THE ABSENCE ASSERT ALONE WAS THE ONLY VACUOUS TEST IN THIS FILE. Deleting the
        // whole `.overlay(...)` — no outline at all — satisfied it. The other five assert
        // COUNTS or a non-empty set and cannot be passed by removal. This one now says what
        // it actually wants: not "no decorative stroke" but "an interactive stroke".
        XCTAssertTrue(body.contains { $0.contains("EchoelTheme.borderStrong") }, """
            #367: the primary Play/Pause has no `borderStrong` stroke. If the outline was \
            removed rather than converted, the button reads as an unbounded glyph — which is \
            not what "outline it as a control" asked for.
            """)
    }

    func testTheTempoLockIsOutlinedAsAControl() throws {
        let source = code(try lines(Self.tempo))
        // ⛔ `lockBPM ? EchoelTheme.accent` matches TWICE in this file, and the FIRST hit is
        // the glyph's `.foregroundStyle` (accent-or-`dim`), not the outline. Keying on the
        // ternary alone made this guard read the wrong line and fail on a correct fix. The
        // needle has to name the thing being asserted about: the stroke.
        guard let lock = source.first(where: {
            $0.contains("strokeBorder(lockBPM ? EchoelTheme.accent")
        }) else {
            return XCTFail("the tempo lock's stroke line is gone — re-point this guard")
        }
        XCTAssertTrue(lock.contains("EchoelTheme.borderStrong"), """
            #367: the tempo lock's idle outline is decorative again. Found: \
            '\(lock.trimmingCharacters(in: .whitespaces))'
            """)
    }

    func testEveryAlwaysOnHeaderElementIsOutlinedAsAControl() throws {
        let source = code(try lines(Self.monitors))
        let offenders = source.filter(usesDecorativeToken)
        XCTAssertTrue(offenders.isEmpty, """
            #367: an always-on header element is back on the decorative token. Every element \
            in this file is chrome that is on screen at all times and every one of them is \
            tappable. Offending line(s): \
            \(offenders.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        let interactive = source.filter { $0.contains("EchoelTheme.borderStrong") }
        XCTAssertEqual(interactive.count, 4, """
            #367: this file should carry exactly FOUR interactive outlines — the pulse \
            monitor, Immersive, Lux, Clips. Found \(interactive.count). If a fifth chrome \
            element was added, add it to `EchoelTheme.borderStrong`'s applied-to list in the \
            same commit and raise this number; that list is the contract and it has already \
            drifted twice.
            """)
    }

    // MARK: - The boundary: what must STAY decorative

    func testTheFollowingTempoReadoutStaysDecorative() throws {
        let source = code(try lines(Self.tempo))
        let ornament = source.filter(usesDecorativeToken)
        XCTAssertEqual(ornament.count, 2, """
            #367: `BodyTempoField` should keep exactly TWO decorative strokes — the compact \
            and the wide FOLLOWING tempo readout, which the file itself describes as \
            something where "a tap opens nothing (it follows the body)". Found \
            \(ornament.count). If this dropped to 0, someone swept the file with a \
            find-and-replace and repainted a READING as a control; that is the #364 mistake, \
            not a fix.
            """)
    }

    func testDividersStayDecorative() throws {
        let source = code(try lines(Self.workspace))
        let dividers = source.filter { $0.contains("Divider()") && $0.contains("EchoelTheme.border") }
        XCTAssertFalse(dividers.isEmpty, """
            #367: the transport bar's `Divider()`s no longer use `border`. A divider is the \
            single clearest case the decorative token exists for — if these became \
            `borderStrong`, the rule has been applied by keyword rather than by meaning.
            """)
        for line in dividers {
            XCTAssertFalse(line.contains("borderStrong"), """
                #367: a `Divider()` was promoted to the interactive token: \
                '\(line.trimmingCharacters(in: .whitespaces))'
                """)
        }
    }

    // MARK: - The contract has to name what it now covers

    func testTheTokenContractNamesItsNewMembers() throws {
        let doc = try lines(Self.theme)
        // ⛔ `static let borderStrong` ALSO matches `borderStrongOpacity`, which is declared
        // 50 lines earlier — so the obvious needle anchored this window on the wrong symbol
        // and searched a region the contract is not in. Match the colour's initializer.
        guard let at = doc.firstIndex(where: { $0.contains("static let borderStrong = Color(") }) else {
            return XCTFail("`borderStrong`'s declaration is gone from EchoelTheme")
        }
        // ⛔ THIS WINDOW WAS `at - 45`, A MAGIC NUMBER, AND IT NEARLY BIT WITHIN ONE COMMIT.
        // The three phrases sat ~24 lines inside it; the #367 Nachlese added a 16-line
        // paragraph to `border`'s doc directly above, cutting the margin to 8. One more
        // paragraph and this test goes RED because someone wrote a COMMENT — a false red on
        // the blocking bundle, which is how a gate gets switched off. The contract is, by
        // construction, everything between the two declarations; say that instead of guessing
        // a distance.
        guard let from = doc.firstIndex(where: { $0.contains("static let border  = Color(") }),
              from < at else {
            return XCTFail("""
                `border`'s declaration is gone or moved below `borderStrong` — this window is \
                defined as the span between them and no longer means anything. Re-point it.
                """)
        }
        let contract = doc[from..<at].joined(separator: " ")
        for member in ["transport Play/Pause", "tempo lock", "pulse monitor"] {
            XCTAssertTrue(contract.contains(member), """
                #367: `borderStrong`'s applied-to list no longer names "\(member)". That list \
                calls itself the contract, and its own paragraph records that it has drifted \
                twice — once by naming door buttons before they were converted, once by \
                counting "the three always-on header tiles" when one of the three was still \
                decorative and a fourth element was missing entirely.
                """)
        }
    }
}
