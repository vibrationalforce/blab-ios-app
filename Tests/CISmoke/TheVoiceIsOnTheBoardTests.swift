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
// ⚠️ HONEST GRADING. Six of the SEVEN methods are red against the pre-#485 tree and the
// seventh (`testTheEngineStillReportsWhetherMonitoringEngaged`) is green on both sides — but
// they are NOT six of a kind, and the first draft of this paragraph said they were.
//
// ⛔ The first draft (six methods then) read: "all five for the SAME cheap reason … the
// extractor returns "" and the non-empty assertion fires first … one absence reported five
// times", and concluded "the backward-facing value of this file is close to nil". Both #485
// reviewers measured it independently and it was FOUR of that kind, not five:
// `testTheMicStripIsMountedInsideTheMixBoard` extracts `mixerPanel`, which exists on the
// parent and is 4427 characters — its non-empty assertion PASSES, and it goes red on
// `.contains("micMixStrip")`, i.e. for exactly the reason its name states. It is a genuine
// mount regression. The error was in the SAFE direction — it undersold the file — and that
// is the only reason it is a footnote rather than a retraction, but understating your own
// evidence is still the #433 self-misgrading defect, and it happened in the paragraph headed
// "counted rather than remembered".
//
// Current state, counted: FIVE absence artefacts (this file's anchors do not exist on the
// parent), ONE real mount finding, ONE green-on-both-sides premise. The two methods added by
// the #485 review — the `@ViewBuilder` pin and the engine-gated refusal message — are red
// against `e95ac86` too, but for their own stated reasons rather than for a missing anchor.
//
// The rest of the file's worth really is FORWARD: each method names one specific, plausible,
// well-intentioned next edit and stands against it.
//
// ⭐ THE COUNTERWEIGHT THAT MATTERS IS THE FEEDBACK-GUARD ONE. `AudioInputPickerView` shows
// a live "guard is ducking" dot, and copying it here reads as an obvious improvement.
// `feedbackGuardActive` is written from the ~15 Hz meter poll, so a read would enrol a body
// as a 15 Hz observer for as long as monitoring runs — and this board's five strips carry
// eight draggable `EchoelValueField`s, which is a live scrub-anchoring hazard (#375/#376).
//
// ⛔ AND THE FIRST DRAFT NAMED THE WRONG BODY: "evaluated inside `mixerPanel` — the body that
// hosts every `.menu` Picker of the instrument … the 10.76.41/50 freeze verbatim." The
// premise (`mixStripCard`'s builder is non-escaping) is true; the conclusion does not follow.
// TWO escaping boundaries sit above this content — `mixerPanel` goes through `panel("Mix",…)`
// into `EchoelPanel`, which invokes its builder in its OWN body, and the strips sit inside
// `AdaptiveCardGrid`, which does the same. The read lands on `AdaptiveCardGrid`, never on
// `EchoelStudioView.body`. This panel also hosts no `Picker` and no `.menu` at all. The
// honest size was already in the tree, written by #298's Nachlese at
// `AudioEngine.updateFeedbackGuard`: "No `.menu` Picker lives in that sheet, so this was
// never the 10.76.50 freeze — but it is the same mechanism." #485 escalated that into "the
// freeze verbatim", re-acquiring a misconception `EchoelStudioView` already carries a ⛔ note
// to kill. Same mechanism, one panel away, one refactor from being the freeze — and the
// DECISION to omit the flag is unchanged by the correction.
//
// ⛔ `SourceText.codeOnly` IS PROPHYLACTIC HERE, AND THE FIRST DRAFT OF THIS PARAGRAPH SAID
// "LOAD-BEARING" — the exact overclaim #484 had to retract one commit ago, made again in the
// file that cites it. Measured instead of asserted: stripped and raw text give IDENTICAL
// verdicts on all 17 assertions (15 before the #485 review added two), 0 differences. The reason is worth writing down because it
// is not obvious and it will stop being true: the extractor anchors on the DECLARATION line,
// and `micMixStrip`'s doc block — which does name `feedbackGuardActive`; ONCE, not "twice"
// as the first draft of this very sentence said, measured with `grep -c` — sits ABOVE
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

    /// ⭐ ADDED BY THE #485 REVIEW, and it is the kind of gap only a compiler-less lane
    /// produces: `@ViewBuilder` on `micMixStrip` is load-bearing for the NON-iOS build ONLY.
    /// The declaration opens with `#if os(iOS)` and has no `#else`, so off iOS the block is
    /// empty and only the builder transform gives it a type (`buildBlock()` → `EmptyView`).
    /// On iOS the body is a single expression, which makes the attribute look removable —
    /// and removing it breaks the other platform with "no return statements … from which to
    /// infer an underlying type", a failure no reviewer of the iOS diff would see.
    func testTheMicStripKeepsTheViewBuilderItsNonIOSBuildNeeds() throws {
        let src = try code(of: Self.studio)
        guard let anchor = src.range(of: Self.stripAnchor) else {
            return XCTFail("no `micMixStrip` declaration found in \(Self.studio)")
        }
        let head = String(src[..<anchor.lowerBound]).suffix(200)
        XCTAssertTrue(head.contains("@ViewBuilder"), """
        `micMixStrip` no longer carries `@ViewBuilder`. On iOS its body is one expression, so \
        the attribute reads as removable — but the declaration is `#if os(iOS)` with no \
        `#else`, and off iOS the builder transform is the only thing that gives the empty \
        block a type. Either keep the attribute or give the `#if` an `#else { EmptyView() }`, \
        in the same commit.
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
        XCTAssertTrue(strip.contains("micMonitorRefused && !audioEngine.isInputMonitoring"), """
        the refusal message is no longer gated on the ENGINE as well as the flag. Dropping \
        the `!audioEngine.isInputMonitoring` half looks like a simplification and re-opens a \
        VISIBLE contradiction the #485 review found: refuse here, open "Choose input…", grant \
        and switch monitoring on inside `AudioInputPickerView` (which knows nothing about \
        this `@State`), dismiss — and the card renders the Toggle ON together with "could not \
        start". Two doors onto one engine; the engine is the single source of truth for "is \
        it listening", and this also clears the milder staleness after granting permission in \
        Settings and coming back.
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
        ~15 Hz meter poll while monitoring runs, so this enrols `AdaptiveCardGrid`'s body — \
        the five mix strips, carrying eight draggable `EchoelValueField`s — as a 15 Hz \
        observer for as long as the performer's mic is on. It is NOT the 10.76.41/50 freeze: \
        `mixerPanel` reaches this content through TWO escaping builders (`EchoelPanel` and \
        `AdaptiveCardGrid`, each invoking it in its own body), and this panel hosts no \
        `.menu` Picker at all. It is the same mechanism one panel away, with a live \
        scrub-anchoring hazard (#375/#376) in the churning subtree — the cost \
        `AudioEngine.updateFeedbackGuard` already names for `AudioInputPickerView`. If a live \
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
        clamps the value it writes to the mixer into that range (the stored property itself \
        is left alone, and nothing persists it), so a wider field would SHOW numbers the \
        engine silently discards — "adjustable but inert", the class this repo keeps \
        removing.
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
