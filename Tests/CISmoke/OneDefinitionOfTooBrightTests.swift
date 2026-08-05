// OneDefinitionOfTooBrightTests.swift
// Echoel — #416. Two copies of "the finger scene is too bright" lived in one file and drifted.
//
// ⭐ WHAT DRIFTED, AND WHY THE DIRECTION IS THE WHOLE POINT. `CameraRPPGBioPublisher` decides
// twice whether the lit fingertip is flooded:
//   · `isWashedOut(brightness:red:)` — the STATE MACHINE's line. Above it the exposure is
//     handed back to auto so the lock can recover instead of sitting dead.
//   · `acquisitionCue` — the SENTENCE ON SCREEN. It carried its own hand-written pair.
// The red halves stayed equal (`> 0.92`). The brightness halves did not: the state machine
// said 0.72, the coaching said 0.85. So across 0.72…0.85 the machine was declaring the frame
// flooded and re-settling it, while the screen said "Press gently and hold still" or "Hold
// still — finding your pulse…" — telling the player to press HARDER into the one condition its
// own recovery path was firing on. Nobody wrote that contradiction. It is what two copies of a
// number do once one of them is edited.
//
// ⛔ WHAT THIS FILE DOES NOT CLAIM, stated here because the surrounding tasks are about
// acquisition and the next session will otherwise read this as their fix. The founder's failed
// session sat at bright ≈ 0.30 (log 2487) — under BOTH thresholds, old and new — so nothing
// here would have changed it. A lock that is legal-but-too-bright to yield a pulse is #304/#410
// and needs a device decision about the permissive ceiling. This file closes a self-contradiction,
// not the acquisition problem.
//
// ⛔ HONEST LIMITS. The second half is a SOURCE SCAN — it proves the call is written, not that
// the amber cue reaches the header (`acquisitionCue` needs a live `AVCaptureSession`, and there
// is no simulator here). House pattern: `SoundPromptHasADoorTests`, `SoundPanelReflowsTests`.
// And neither half can say whether "Press a little lighter" is the RIGHT sentence for a flooded
// scene — that is a device judgement.

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

    /// ⭐ THE REGRESSION, AS BEHAVIOUR. Every value in 0.72…0.85 must read as washed out. That
    /// band is exactly what the old coaching copy excluded, so this goes red the moment anyone
    /// raises the brightness line back toward the number the cue used to carry.
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
            ["brightness >", "brightness <", "redChannel >", "redChannel <"]
                .contains { line.contains($0) }
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
    /// string appearing in two places measures the wrong one (#408 shipped that mistake: it
    /// anchored on a name that matched the declaration before the call site).
    private static let cueAnchor = "var acquisitionCue: PulseCue {"

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
