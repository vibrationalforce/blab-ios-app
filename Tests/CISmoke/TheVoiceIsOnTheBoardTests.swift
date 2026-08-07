// TheVoiceIsOnTheBoardTests.swift
// Echoel — #485. Blocking bundle.
//
// ⭐ THE ASK, and it is smaller than it sounds: the founder wants training for coherent
// breathing plus chanting / humming / toning / singing, and said it "braucht einen
// zusätzlichen Mixer-Slot für Audio-in". The CAPABILITY was already there — live monitoring
// with the FeedbackGuard duck has shipped since #298/#299, engine path and all. What was
// missing is that its only door sat behind the MASTER panel, i.e. under the sum of the
// layers instead of beside them. So the one layer a performer makes with their own body was
// the only audible layer absent from the board #330 built to hold every audible layer.
//
// ⚠️ HONEST GRADING, because the flattering version — "three regressions, three
// counterweights" — is available and would be false. Counted rather than remembered: FIVE
// of the six methods are red against the pre-#485 tree, and all five for the SAME cheap
// reason, which is that `micMixStrip` does not exist there so the extractor returns "" and
// the non-empty assertion fires first. That is not five findings; it is one absence,
// reported five times. The sixth (`testTheEngineStillReportsWhetherMonitoringEngaged`) is
// green on both sides.
//
// So the backward-facing value of this file is close to nil, and its worth is entirely
// FORWARD: each method names one specific, plausible, well-intentioned next edit and stands
// against it. Grading them by which ones happen to redden a tree that predates the code they
// describe would be the #433 self-misgrading defect in the file that cites it.
//
// ⭐ THE COUNTERWEIGHT THAT MATTERS IS THE FEEDBACK-GUARD ONE, and it is the exact shape of
// this repo's most expensive UI bug. `AudioInputPickerView` shows a live "guard is ducking"
// dot, and copying it here reads as an obvious improvement. It is the 10.76.41/50 freeze
// verbatim: `feedbackGuardActive` is written from the ~15 Hz meter poll, and `mixStripCard`
// takes a NON-escaping `@ViewBuilder`, so this content is evaluated inside `mixerPanel` —
// the body that hosts every `.menu` Picker of the instrument. The picker sheet is a leaf
// with no Picker in it; the Mix board is not. Same value, two hosts, only one of them safe.
//
// ⛔ `SourceText.codeOnly` IS PROPHYLACTIC HERE, AND THE FIRST DRAFT OF THIS PARAGRAPH SAID
// "LOAD-BEARING" — the exact overclaim #484 had to retract one commit ago, made again in the
// file that cites it. Measured instead of asserted: stripped and raw text give IDENTICAL
// verdicts on all 15 assertions, 0 differences. The reason is worth writing down because it
// is not obvious and it will stop being true: the extractor anchors on the DECLARATION line,
// and `micMixStrip`'s doc block — which does name `feedbackGuardActive`, twice — sits ABOVE
// it, i.e. outside every extracted block. The strip's body carries no comments today. Add
// one that mentions the flag and the stripper becomes the only thing between this guard and
// a green earned by prose. It stays for that, and because #453 made one definition of
// "code, not prose" for the whole blocking bundle; a private exception is the defect that
// slice removed.
//
// ⛔ WHAT THIS FILE CANNOT DO, first rather than last. Every assertion is a SOURCE SCAN.
// There is no simulator in this lane and `micMixStrip` is `private` in a SwiftUI view. It
// cannot show that the strip renders, that the toggle engages a real mic, that the duck is
// audible, or that monitoring your own voice through this route is latency-acceptable — all
// device-verify, all open. It also asserts nothing about whether the board is COMPLETE:
// `MixBoardOwnsEveryLevelTests` says out loud why a pinned strip count is a bad test, and
// that judgement stands.

import Foundation
import XCTest

final class TheVoiceIsOnTheBoardTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let stripAnchor = "private var micMixStrip: some View {"

    // MARK: - The strip is on the board (regression)

    func testTheMicStripIsMountedInsideTheMixBoard() throws {
        let panel = try block(startingAt: "private var mixerPanel: some View {")
        XCTAssertFalse(panel.isEmpty, """
        no `mixerPanel` declaration found in \(Self.studio). If it was renamed, rename it \
        here in the same commit (#456) — a scan whose anchor is gone reports a green it did \
        not earn.
        """)
        XCTAssertTrue(panel.contains("micMixStrip"), """
        the Mix board no longer mounts `micMixStrip`. The founder asked for the microphone \
        to be a mixer slot; the capability has existed since #298 and the only thing #485 \
        added was a door BESIDE the other layers instead of underneath them. Removing the \
        mount puts the mic back behind the Master panel without deleting anything, so \
        nothing else in the tree would notice.
        """)
    }

    // MARK: - The toggle may not lie (regression)

    /// `isInputMonitoring` is `private(set)` and stays false when `setInputMonitoring`
    /// refuses (mic permission denied, no valid input format). Nothing else in this strip
    /// mutates observable state, so without the refusal write the body is never invalidated
    /// and the `Toggle` keeps SHOWING on while the mic is not being read.
    func testTheToggleRecordsARefusalSoItCannotKeepShowingOn() throws {
        let strip = try block(startingAt: Self.stripAnchor)
        XCTAssertFalse(strip.isEmpty, "no `micMixStrip` declaration found in \(Self.studio)")

        XCTAssertTrue(strip.contains("setInputMonitoring"), """
        the mic strip's toggle no longer goes through `AudioEngine.setInputMonitoring`. \
        There is no other way in: `isInputMonitoring` is `private(set)`, and the session \
        claim, the graph connection and the FeedbackGuard arming all live in that method.
        """)
        XCTAssertTrue(strip.contains("micMonitorRefused"), """
        the mic strip's toggle no longer records a refused enable. `setInputMonitoring` \
        returns false on a denied mic permission and leaves `isInputMonitoring` false — so \
        with nothing writing observable state, the toggle shows "on" over a microphone that \
        is not being read. That is a lying control (#135/#164/#227) on the one row where \
        "it says it is listening" is the worst thing in this app to be wrong about. If the \
        revert is made to happen some other way, move this assertion to it — do not delete it.
        """)
    }

    /// The premise the refusal path is built on, pinned in the file that owns it. If
    /// `setInputMonitoring` stopped reporting failure, the assertion above would still pass
    /// while guarding nothing.
    func testTheEngineStillReportsWhetherMonitoringEngaged() throws {
        let code = try code(of: Self.engine)
        XCTAssertTrue(code.contains("func setInputMonitoring(_ on: Bool) -> Bool"), """
        `AudioEngine.setInputMonitoring` no longer returns whether it engaged. Every caller \
        then has to assume success, and a denied microphone permission becomes invisible in \
        both doors at once.
        """)
        XCTAssertTrue(code.contains("public private(set) var isInputMonitoring"), """
        `isInputMonitoring` is no longer `private(set)`. That looks like a convenience and \
        is the opposite: a UI that can assign it directly can put the flag into a state the \
        audio graph is not in, which is precisely the divergence the refusal path exists to \
        prevent.
        """)
    }

    // MARK: - Counterweights (green on both sides, and that is the point)

    /// ⭐ THE ONE THIS FILE IS FOR. Copying `AudioInputPickerView`'s live guard dot onto the
    /// Mix board reads as an obvious improvement and is the 10.76.41/50 freeze.
    func testTheStripDoesNotReadTheFifteenHertzFeedbackFlag() throws {
        let strip = try block(startingAt: Self.stripAnchor)
        XCTAssertFalse(strip.isEmpty, "no `micMixStrip` declaration found in \(Self.studio)")
        XCTAssertFalse(strip.contains("feedbackGuardActive"), """
        the mic strip reads `audioEngine.feedbackGuardActive`. That flag is written from the \
        ~15 Hz meter poll while monitoring runs, and `mixStripCard` takes a NON-escaping \
        `@ViewBuilder` — so this content is evaluated inside `mixerPanel`, which is inside \
        the body that hosts every `.menu` Picker of the instrument. Every rebuild tears down \
        an open Picker popover: that is the shipped "kann plötzlich nicht mehr auswählen" \
        freeze, arriving the moment the performer switches their mic on. The live indicator \
        belongs in `AudioInputPickerView`, a leaf sheet with no Picker in it. If a live \
        readout is genuinely wanted here, it goes in its OWN leaf `View` struct that reads \
        the engine in its own body — not inline in this builder.
        """)
    }

    /// The board must not grow the body's presentation chain. It has 14 modifiers on it and
    /// the metadata-decoder limit is what the black screen of 10.76.34 was.
    func testTheStripReusesTheExistingInputSheetInsteadOfAddingOne() throws {
        let strip = try block(startingAt: Self.stripAnchor)
        XCTAssertFalse(strip.isEmpty, "no `micMixStrip` declaration found in \(Self.studio)")
        XCTAssertTrue(strip.contains("showInput = true"), """
        the mic strip no longer hands off to the existing input sheet. Choosing WHICH input \
        (built-in / wired / USB / Bluetooth, each with its own monitoring latency) lives in \
        `AudioInputPickerView`; duplicating any part of that here would be a second copy \
        rather than a second door.
        """)
        for modifier in [".sheet(", ".fullScreenCover(", ".alert(", ".fileImporter("] {
            XCTAssertFalse(strip.contains(modifier), """
            the mic strip declares its own `\(modifier)`. `EchoelStudioView` already carries \
            14 presentation modifiers on its body chain, and three sheets added at \
            10.76.25/27/29 pushed the aggregate generic type past the SwiftUI metadata \
            decoder's stack limit — SIGSEGV before the first render, which presents as a \
            black screen. Reuse a slot (`showInput` is right here) or consolidate the chain \
            into one `.sheet(item:)` enum FIRST.
            """)
        }
    }

    /// Every `EchoelValueField` on a reachable row states its own grid (#440/#443). The mic
    /// level is a new reachable row, so it inherits that law rather than the default of 4.
    /// `EveryReachableRowStatesItsGridTests` sweeps the whole tree; this pins the value,
    /// which that sweep deliberately does not.
    func testTheLevelRowUsesTheSameTwoDecimalGridAsEveryOtherStrip() throws {
        let strip = try block(startingAt: Self.stripAnchor)
        XCTAssertFalse(strip.isEmpty, "no `micMixStrip` declaration found in \(Self.studio)")
        XCTAssertTrue(strip.contains("decimals: 2"), """
        the mic level row does not state `decimals: 2`. `EchoelValueField.decimals` is the \
        SNAP GRID, not the display width, and it defaults to 4 — so an unstated row offers \
        four decimal places of monitor gain while Bass, Pad, Field and Click all offer two. \
        A row that omits it is the exact defect #427 and #430 each swept up after the fact.
        """)
        XCTAssertTrue(strip.contains("range: 0...1"), """
        the mic level row no longer spans 0…1. `AudioEngine.inputMonitorGain`'s `didSet` \
        clamps to that range, so a wider field would show and persist numbers the engine \
        silently discards — "adjustable but inert", the class this repo keeps removing.
        """)
    }

    // MARK: - Helpers

    /// The text of a declaration, from `anchor` to its matching close brace, with comments
    /// removed first. Brace-counted rather than line-counted so an inserted line cannot
    /// silently truncate the scan, and it returns "" when the anchor is missing so callers
    /// fail loudly instead of passing on an empty slice (#367).
    private func block(startingAt anchor: String) throws -> String {
        let src = try code(of: Self.studio)
        guard let start = src.range(of: anchor) else { return "" }
        var depth = 0
        var index = src.index(before: start.upperBound)   // the anchor's own `{`
        while index < src.endIndex {
            let ch = src[index]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { return String(src[start.lowerBound...index]) }
            }
            index = src.index(after: index)
        }
        return ""
    }

    /// File contents with comments stripped by the ONE shared stripper (#453) — a single
    /// compiler-order pass, so a `//` inside a string literal is not treated as a comment.
    private func code(of path: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(path)
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    /// Gates on the DIRECTORY, not on each file: a `fileExists` bracket around every read
    /// turns the very catastrophe this bundle exists for into a green SKIP (#472).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }
}
