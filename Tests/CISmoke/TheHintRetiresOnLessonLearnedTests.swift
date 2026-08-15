// TheHintRetiresOnLessonLearnedTests.swift
// Echoel — #604 (GUI-Board Scheibe 1, from the #603 UX audit's debt #2).
//
// WHAT THIS GUARDS. `InstrumentHintOverlay` — the app's ONLY statement of the core
// mechanic ("Start the music, then a finger on the back camera / Touch the image to
// play notes") — used to write `seen = true` after ONE ~4.5 s showing. Miss it once and
// no surface ever taught the gestures again; the #603 UX audit ranked that the
// second-worst debt in the app. The NEW retire law has two arms, both pinned here:
//   · LEARNED: `startBioSource()` writes `instrumentHintSeen` — the user found Start,
//     which is step 1 of the hint's own first sentence;
//   · CAPPED: after `instrumentHintShowCap` showings the overlay retires itself — the
//     old once-ever contract's REAL point (no endless nagging) kept without its cost.
//
// ⚠️ LIMIT — SOURCE-TEXT SCAN. Nothing here runs the task, counts real showings, or
// proves the timing/fade on device. Copy truth stays owned by
// `FirstInstructionIsTrueTests` (#416 — one guard per decision; this file deliberately
// does not re-scan the hint's strings), the fullscreen gate by
// `TheFrontDoorIsDecidedBeforeItIsAskedTests`.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (e4f9953) and this tree
// (#433/#464). 11 assertions in 4 tests, hand-counted: claims 1 (3) + 2 (5) + 3 (1) +
// 4 (2). On THIS tree all 11 pass. Against the #604 PARENT (e4f9953): SIX were red as
// ONE finding (#486) — keystore entries (3), counter + cap-retire (2), start-path
// write (1), all born with #604, FORWARD. The TWO #604b additions (fade-sleep needle +
// its ordering) are FORWARD against 4ae39e4 — the 700 ms sleep was born with #604b
// (the original #604 shipped one sleep and its cap-retire hard-cut the cap-th showing;
// found in review). Claim 2's exactly-one count is GREEN on the parent TOO, but for
// the WRONG reason (#367, named rather than hidden): the parent's one `seen = true` is
// the retired display-contract write this law replaces. The count only means what its
// message says TOGETHER with the needles above it — alone it cannot tell the old law
// from the new. Claim 4's two are COUNTERWEIGHTS, green on both trees. ZERO
// regressions claimed, because zero exist. `SourceText.codeOnly` is LOAD-BEARING,
// MEASURED (#453): 1 of the claim-2 verdicts flips raw-vs-stripped on this tree — the
// retired contract's phrase `seen = true` survives in the overlay's #604 comment
// ("collapses this very `if !seen` branch — written up front it would…"); claim 2's
// exactly-one count is true only of CODE. The #491 collision in its standard form.
// The two #604b needles do not flip: the 700 ms literal appears only in code (the
// neighbouring comments spell it "700 ms").

import Foundation
import XCTest

final class TheHintRetiresOnLessonLearnedTests: XCTestCase {

    private static let window = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let keys = "Sources/Echoelmusic/Core/StudioDefaultKeys.swift"

    // MARK: - claim 1 — the keys and the cap live in the keystore (H15 + #416)

    func testTheRetireStateLivesInTheKeystore() throws {
        let keys = try source(Self.keys)
        XCTAssertTrue(keys.contains("StudioDefault(key: \"onboard.instrumentHintSeen\", value: false)"), """
            The hint's retire flag left the keystore (or its default moved). Two views \
            write/read it (overlay + startBioSource) — H15: one declaration, in Core. \
            The key STRING must stay "onboard.instrumentHintSeen": renaming it would \
            re-show the hint to every user who already retired it.
            """)
        XCTAssertTrue(keys.contains("StudioDefault(key: \"onboard.instrumentHintShows\", value: 0)"), """
            The showing counter left the keystore. Without it the cap arm of the retire \
            law has no state and the hint either nags forever or regresses to once-ever.
            """)
        XCTAssertTrue(keys.contains("instrumentHintShowCap = 5"), """
            The showing cap moved or changed. If this is a deliberate retune, update \
            this needle AND `StudioDefaultKeysTests` in the same commit — the cap is the \
            surviving half of the old once-ever contract (its anti-nagging point).
            """)
    }

    // MARK: - claim 2 — the overlay counts, and only the CAP arm retires there

    func testTheOverlayCountsAndCapsButDoesNotRetireOnDisplay() throws {
        let code = try source(Self.window)
        XCTAssertTrue(code.contains("shows += 1"), """
            The overlay no longer counts its showings. The cap arm of the retire law \
            reads this counter; without the increment the hint shows forever for a user \
            who never presses Start — the nagging the cap exists to bound.
            """)
        XCTAssertTrue(code.contains("if shows >= StudioDefaultKeys.instrumentHintShowCap { seen = true }"), """
            The cap-retire is gone from the overlay (or stopped asking the keystore's \
            ONE cap definition, #416). This line must also stay AFTER the fade sleeps — \
            `seen = true` collapses the `if !seen` branch, so written before the sleeps \
            it vanishes the cap-th showing the instant it appears (caught in review of \
            this very slice).
            """)
        // #604b — the ORIGINAL #604 shipped with ONE sleep: the cap-retire ran in the
        // same MainActor turn the ease-out STARTED, so the cap-th showing ended in a
        // hard cut (the small sibling of the very defect the placement comment names).
        let fadeSleep = "try? await Task.sleep(nanoseconds: 700_000_000)"
        XCTAssertTrue(code.contains(fadeSleep), """
            The fade sleep is gone from the overlay. Without it the cap-retire write \
            collapses `if !seen` before the 0.6 s ease-out renders a frame — the cap-th \
            showing becomes a hard cut (#604b). If the ease-out duration ever grows past \
            0.7 s, grow this sleep with it.
            """)
        // Ordering via first-range comparison — sound because BOTH needles are unique in
        // this file (the 700 ms literal exists nowhere else in Sources/; `seen = true`
        // is counted ==1 below). The `if let` fail-open is covered by the two contains
        // assertions above going red first (#367, named).
        if let fade = code.range(of: fadeSleep),
           let cap = code.range(of: "if shows >= StudioDefaultKeys.instrumentHintShowCap { seen = true }") {
            XCTAssertTrue(fade.lowerBound < cap.lowerBound, """
                The fade sleep moved BELOW the cap-retire — in that order it delays \
                nothing: `seen = true` has already collapsed the branch before the sleep \
                runs, and the cap-th showing hard-cuts again (#604b).
                """)
        }
        XCTAssertEqual(occurrences(of: "seen = true", in: code), 1, """
            `seen = true` appears more than once in FloatingVisualWindow — a second \
            writer is either the old once-ever display contract returning (the #604 \
            regression) or a new retire arm nobody documented. One cap-arm write; the \
            LEARNED arm lives in `startBioSource()`, not here.
            """)
    }

    // MARK: - claim 3 — the LEARNED arm sits on the start path

    func testStartingBioRetiresTheHint() throws {
        let code = try source(Self.studio)
        let body = slice(code, from: "private func startBioSource() async {", to: "\n    }")
        XCTAssertTrue(body.contains("instrumentHintSeen = true"), """
            `startBioSource()` no longer retires the instrument hint. That write IS the \
            lesson-learned arm: the user found Start (step 1 of the hint's sentence), so \
            the whisper's job is done. Without it the hint keeps showing until the cap \
            for exactly the users who no longer need it.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHTS, #343) — the premises that survive the rewrite

    func testTheOldContractsLoadBearingPartsSurvive() throws {
        let code = try source(Self.window)
        XCTAssertTrue(code.contains("try? await Task.sleep(nanoseconds: 4_500_000_000)"), """
            The hold sleep lost its `try?` (or its duration anchor moved). The swallow \
            is load-bearing exactly as in the old contract: a mid-hold fullscreen exit \
            cancels the task, and only the swallowed CancellationError lets the final \
            cap-retire write run.
            """)
        XCTAssertTrue(code.contains(".allowsHitTesting(false)"), """
            The hint overlay lost `allowsHitTesting(false)`. With the hint now showing \
            on up to \(5) fullscreen entries instead of once, an overlay that swallowed \
            the first play-touch would be five times the defect it was under the old \
            contract.
            """)
    }

    // MARK: - source access

    private struct AnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func slice(_ code: String, from: String, to: String) -> String {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            return ""
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
