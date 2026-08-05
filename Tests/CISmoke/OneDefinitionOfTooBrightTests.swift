// OneDefinitionOfTooBrightTests.swift
// Echoel — #416. Two copies of "the finger scene is too bright" lived in one file and drifted.
//
// ⭐ WHAT DRIFTED, AND WHY THE DIRECTION IS THE WHOLE POINT. `CameraRPPGBioPublisher` decides
// twice whether the lit fingertip is flooded:
//   · `isWashedOut(brightness:red:)` — the STATE MACHINE's line. Above it the exposure is
//     handed back to auto so the lock can recover instead of sitting dead.
//   · `acquisitionCue` — the SENTENCE ON SCREEN. It carried its own hand-written pair.
// The red halves stayed equal (`> 0.92`). The brightness halves did not: the state machine
// said 0.72, the coaching said 0.85. So across 0.72…0.85 the machine was re-settling BECAUSE
// it judged the scene flooded, while the screen said nothing about light at all.
//
// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH ENDED "— telling the player to press HARDER into
// the one condition its own recovery path was firing on." That is FALSE of every shipped
// string: the three fall-through cues are "Hold still — keep your finger steady", "Press
// gently and hold still" and "Hold still — finding your pulse…". The middle one asks for
// LIGHTER pressure. The sentence also silently dropped `.holdStill` from the list — and that
// omission carried the weight, because `CameraRPPGBioPublisher`'s own attribution of this band
// is "finger lightening / re-grip" and the analyzer's is "hard-press / re-grip", i.e.
// `.holdStill` was arguably the RIGHT message there and #416 preempts it. Whether
// "Press a little lighter" should own that transient is a device/wording call recorded with
// #304/#410, not settled by this commit. The false sentence stood in four places at once
// (here, the source, the commit message, CLAUDE.md) — a rhetorically satisfying claim that
// nobody checked against `PulseCue.fullHint`.
//
// ⛔ WHAT THIS FILE DOES NOT CLAIM, stated here because the surrounding tasks are about
// acquisition and the next session will otherwise read this as their fix. The founder's failed
// session sat at bright ≈ 0.30 (log 2487), so nothing here would have changed it. (The first
// version added "under BOTH thresholds, old and new" — true of 0.72 and 0.85, but this file
// holds THREE brightness lines and 0.30 is ABOVE the third, `strictLockBrightness` = 0.28.)
// A lock that is legal-but-too-bright to yield a pulse is #304/#410 and needs a device decision
// about the permissive ceiling. This file closes ONE self-contradiction of two, not the
// acquisition problem: at brightness 0.65 the lock is still refused with no cue on screen.
//
// ⛔ HONEST LIMITS, and this block is only worth having if it is EXHAUSTIVE — a limits list that
// omits a known hole is the failure this repo has paid for more than once.
//   · The second half is a SOURCE SCAN. It proves the call is written, not that the amber cue
//     reaches the header. (⛔ The first version blamed "needs a live `AVCaptureSession`" — the
//     property is readable on a bare publisher and returns `.coverLens`. The real blocker is
//     that `analyzer` is an `@ObservationIgnored private let` with no injection seam, so the
//     cue cannot be STEERED. Naming the wrong blocker sends the next session to a device for
//     what is a one-line test seam.) House pattern: `SoundPromptHasADoorTests`,
//     `SoundPanelReflowsTests`.
//   · The scan is scoped to ONE property. A helper `private var brightnessCue` carrying its own
//     literal, one function away, passes both assertions.
//   · `codeLines` strips `//` only, not `/* */`. A block comment containing a brace inside the
//     cue would truncate the extracted body silently.
//   · The behavioural half is green on BOTH sides of #416 — see its own header. Only the scan
//     pins this change.
//   · The marker list in `comparisonMarkers` matches SPACED comparisons. `>=` and `<=` are
//     caught (they contain `>` / `<`), but `analyzer.brightness>0.85` — no space — is NOT.
//     The narrowness is real but bounded: hoisting to a local (`let b = analyzer.brightness;
//     if b > 0.85`) only makes sense once the `isWashedOut(` call is gone, which the first
//     assertion catches. So the surviving evasion is "keep the call AND add an unspaced second
//     literal". Widening to a regex would cost the whole file's plain-string legibility for
//     that one case; if it ever happens, widen then and say so here.
//   · Neither half can say whether "Press a little lighter" is the RIGHT sentence for a flooded
//     scene — that is a device judgement.

import Foundation
import XCTest
#if canImport(AVFoundation) && canImport(Observation)
@testable import Echoelmusic
#endif

final class OneDefinitionOfTooBrightTests: XCTestCase {

    // The publisher's whole FILE is `#if canImport(AVFoundation) && canImport(Observation)`, so
    // the behavioural half must carry the SAME pair — not just AVFoundation, which is the guard
    // most siblings here use for a type that only needs that one. The scanning half is
    // deliberately OUTSIDE any guard: it reads text and must run wherever the bundle builds.
    #if canImport(AVFoundation) && canImport(Observation)
    private typealias Pub = CameraRPPGBioPublisher

    // MARK: - The definition itself (real behaviour, no scan)

    /// ⛔ THIS IS NOT THE REGRESSION, and its first version said it was. The header read
    /// "⭐ THE REGRESSION, AS BEHAVIOUR … goes red the moment anyone raises the brightness line
    /// back". It exercises ONLY `isWashedOut`, which was 0.72 before #416, is 0.72 after, and
    /// was not touched by that commit — so this test is **green on both sides of the change it
    /// claims to pin**. Worse, the same predicate is already swept in the non-blocking suite
    /// (`Tests/EchoelmusicTests/RPPGExposureLockTests.swift`).
    ///
    /// It is kept for the one thing it does earn: moving that pin into the BLOCKING bundle, so
    /// the line the coaching now depends on cannot move without a red gate. **Only the source
    /// scan below distinguishes pre- from post-#416.** A behavioural test of the cue itself is
    /// not writable today — not for the reason the header first gave ("needs a live
    /// AVCaptureSession"; the property is readable on a bare publisher and returns `.coverLens`)
    /// but because `analyzer` is an `@ObservationIgnored private let` with no injection seam, so
    /// the cue cannot be STEERED. That is a one-line test seam, not a device trip.
    func testTheBandTheCoachingUsedToMissIsWashedOut() {
        for value in stride(from: 0.73, through: 0.85, by: 0.01) {
            let b = Float(value)
            XCTAssertTrue(Pub.isWashedOut(brightness: b, red: 0.5), """
            brightness \(b) does not read as washed out.

            This is the 0.72…0.85 band #416 closed: the state machine re-settles the exposure \
            here, and before #416 the on-screen coaching did not mention brightness at all until \
            0.85 — it told the player to press harder instead. If the brightness line genuinely \
            moved up, move it because a device log says so, and rewrite this test with that \
            log's numbers rather than deleting it.
            """)
        }
    }

    /// The healthy band this file's own prose names ("Healthy PPG brightness is ~0.1–0.4") must
    /// NOT read as washed out. Without this the test above is satisfiable by a predicate that
    /// returns true everywhere — a cue that shouts "too bright" at a perfect placement.
    func testAHealthyFingerSceneIsNotWashedOut() {
        for value in stride(from: 0.10, through: 0.40, by: 0.05) {
            let b = Float(value)
            XCTAssertFalse(Pub.isWashedOut(brightness: b, red: 0.5), """
            brightness \(b) reads as washed out, but this file calls 0.1–0.4 the healthy PPG \
            range. A predicate that fires here turns the coaching into a permanent false alarm \
            on a good placement.
            """)
        }
    }

    /// The red channel is the OTHER half and was never the one that drifted — pinned so a future
    /// edit cannot quietly drop it while the brightness half keeps both tests above green.
    func testAClippedRedChannelIsWashedOutOnItsOwn() {
        XCTAssertTrue(Pub.isWashedOut(brightness: 0.20, red: 0.95), """
        a clipping red channel (0.95) on an otherwise dark scene no longer reads as washed out.

        Brightness and red are two independent ways the AC pulse gets swamped; dropping either \
        leaves half the condition unreported to both the recovery path and the player.
        """)
        XCTAssertFalse(Pub.isWashedOut(brightness: 0.20, red: 0.50), """
        a dark scene with an unremarkable red channel reads as washed out — then the predicate \
        is not discriminating and every assertion in this file is vacuous.
        """)
    }
    #endif

    // MARK: - The coaching must ASK, not re-decide

    /// ⭐ THE DRIFT GUARD. `acquisitionCue` must reach its brightness verdict by calling
    /// `isWashedOut`, and must not compare a brightness or red value itself. Comments are
    /// stripped first, so the ⛔ block above the call — which quotes the old numbers on purpose —
    /// cannot stand in for code. Reverting #416 makes this red.
    func testTheCoachingAsksTheStateMachineInsteadOfCarryingItsOwnNumber() throws {
        let body = try acquisitionCueBody()
        // An empty body means `acquisitionCueBody()` already recorded the REAL failure (anchor
        // missing or ambiguous). Running the two assertions below on it would add two more
        // messages that name the wrong cause — "no longer calls isWashedOut" is misleading when
        // the truth is that the property could not be located at all.
        guard !body.isEmpty else { return }

        XCTAssertTrue(body.contains { $0.contains("isWashedOut(") }, """
        `acquisitionCue` no longer calls `isWashedOut` — it decides "too bright" on its own again.

        That is the #416 state exactly. The two definitions then drift apart silently, and the \
        direction of the last drift had the screen contradicting the recovery path. If the cue \
        genuinely needs a different line from the exposure recovery, give that line a NAMED \
        predicate next to `isWashedOut` and point this test at it — do not inline a literal.

        The body it found was:
        \(body.joined(separator: "\n"))
        """)

        let comparisons = body.filter { line in
            Self.comparisonMarkers.contains { line.contains($0) }
        }
        XCTAssertTrue(comparisons.isEmpty, """
        `acquisitionCue` compares a brightness/red value directly:
        \(comparisons.joined(separator: "\n"))

        A second threshold here is how #416 happened. Route the question through a named \
        predicate so the state machine and the sentence on screen cannot disagree.
        """)
    }

    // MARK: - Source access

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    /// The declaration line is the anchor, and it must be UNIQUE — a scan that anchors on a
    /// string appearing in two places measures the wrong one (#408 MADE that mistake and was
    /// caught by running — "THE FIRST VERSION OF THIS TEST FAILED", says its own header. The
    /// first version of this line said "#408 shipped" it, which is the opposite of the record: it
    /// anchored on a name that matched the declaration before the call site).
    private static let cueAnchor = "var acquisitionCue: PulseCue {"

    /// A brightness/red comparison written INSIDE the cue — the thing #416 removed. Hoisted to a
    /// stored constant rather than a literal inside the `filter` closure: this bundle already
    /// went red once because an assertion expression was too expensive to type-check (`3379bb3`),
    /// and a nested literal in a closure is the cheapest such site to remove. Its known hole is
    /// documented in the ⛔ HONEST LIMITS block at the top of this file — keep the two in sync.
    private static let comparisonMarkers = [
        "brightness >", "brightness <", "redChannel >", "redChannel <"
    ]

    /// The statements inside `acquisitionCue`, comments stripped, braces balanced from the
    /// anchor. Brace counting runs on the STRIPPED lines on purpose: a brace inside a comment
    /// would otherwise close the body early and the scan would silently look at three lines.
    private func acquisitionCueBody() throws -> [String] {
        let lines = try codeLines(Self.publisher)
        let anchors = lines.indices.filter { lines[$0].contains(Self.cueAnchor) }
        guard anchors.count == 1, let start = anchors.first else {
            XCTFail("""
            expected exactly one line containing "\(Self.cueAnchor)" in \(Self.publisher), \
            found \(anchors.count).

            With zero, the property was renamed and this file is measuring nothing. With more \
            than one, the anchor is ambiguous and the body below may not be the cue's.
            """)
            return []
        }

        var depth = 0
        var out: [String] = []
        for line in lines[start...] {
            let opens = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count
            let wasOpen = depth > 0
            depth += opens - closes
            if wasOpen { out.append(line) }
            if wasOpen && depth <= 0 { return out }
        }
        XCTFail("`acquisitionCue`'s braces never balanced — the body could not be read")
        return out
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`). Skips rather
    /// than passing when the tree is absent: a green earned without reading source is the exact
    /// dishonesty this bundle exists to prevent.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — the scanning half cannot report a green")
        }
        return root
    }

    /// Non-empty lines with whole-line and trailing comments removed. The quote-parity check
    /// approximates "is this `//` inside a string literal"; it is imperfect in both directions
    /// (see `SoundPromptHasADoorTests` for the measured cases), which is tolerable here because
    /// `acquisitionCue` contains no string literals at all.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let r = line.range(of: "//") {
                let before = line[line.startIndex..<r.lowerBound]
                if before.filter({ $0 == "\"" }).count % 2 == 0 {
                    line = String(before)
                }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }
}
