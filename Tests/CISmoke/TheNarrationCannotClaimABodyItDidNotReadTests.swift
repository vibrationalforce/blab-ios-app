// TheNarrationCannotClaimABodyItDidNotReadTests.swift
// Echoel — #506. The no-body narration existed, was tested, and its only caller could not reach it.
//
// WHAT WENT WRONG. `BioExplanation.text(for:tempo:)` is a plain-English narration of the
// bio→sound mapping, written with unusual care for the case where the body was NOT read: it
// drops every clause it cannot measure, opens with "tempo holds at N BPM; no pulse measured
// yet", and deliberately removes the phrase " from your live signal," when nothing was
// measured. Five tests in the non-blocking suite pin those branches.
//
// Its ONE production caller was `if let frame { caption.text = … }`. So the branch that exists
// precisely for `body == nil` could never be reached from the app — and the gate left something
// worse behind than unreachability: nothing else writes or clears `caption.text`, so a take
// composed with no body kept narrating the PREVIOUS take's heart rate. That is #503's defect
// one surface up: a reading that stopped arriving, still presented as live.
//
// ⭐ HOW BIG THIS IS, MEASURED, NOT GUESSED. `body=0` is not a corner case in this product —
// device log 2494 (v10.79.377) recorded it in EVERY generate breadcrumb for ~475 s (#500).
// The rPPG acquisition is the binding constraint (#304/#410/#415), so a take with no body is
// the NORMAL first minute, not the exception.
//
// ⛔ HONEST LIMIT — READ THIS BEFORE TRUSTING A GREEN, because this file looks broader than it
// is. The chain is DOORLESS TODAY. `StudioCaptionView` is mounted only inside
// `liveNarrationBanner`, and that property has exactly ONE occurrence in `Sources/` — its own
// declaration, zero mount sites (task #326). So nothing here is visible to a user right now,
// and this slice fixes a MECHANISM, not a live screen. It is written anyway for the reason
// #429/#433/#444/#470 were: the sentence is wrong whether or not a door exists, and a door
// that arrives later must not land on a silent contradiction. Claim 5 states the doorlessness
// as an assertion so that re-dooring the banner is a decision somebody makes on purpose.
//
// ⚠️ WHICH HALF IS REAL BEHAVIOUR AND WHICH IS A SCAN. `BioExplanation` and `BioSampleFrame`
// are `public`, Foundation-only value types, so claims 1–3 drive the SHIPPED function
// end-to-end. Claims 4a/4b/5 are SOURCE SCANS — `caption` is `@State` on a SwiftUI view this
// bundle cannot instantiate. That the narration ever RENDERS, and that it reads well aloud,
// are device checks, and both are moot until the banner has a door.
//
// ⚠️ HONEST GRADING (#433), transcribed against the parent tree rather than asserted. The file
// does not COMPILE against the pre-#506 tree at all (#464 situation, said plainly instead of
// dressed up): claims 1–3 call `text(for: nil, tempo:)`, and the parameter was non-optional
// there, so NO claim in this file has a verdict on the parent. Transcribed by hand
// (Python re-implementation of `SourceText.codeOnly`, run against `git show HEAD:` and the
// worktree):
//   · THREE would be red for their STATED reason — 4a (the gated form is present on the
//     parent), 4b and 4c (neither optional signature exists there).
//   · ONE is an ANCHOR, green on BOTH trees: the parent's `if let frame { caption.text = … }`
//     literally CONTAINS the substring claim 4a-positive looks for. On its own it proves
//     nothing (#343); it earns its place only paired with the statement-level check.
//   · ONE is a COUNTERWEIGHT, green on both: the doorlessness premise (claim 5).
//
// ⚠️ `SourceText.codeOnly` IS PROPHYLACTIC HERE, and that is MEASURED rather than assumed
// (#484/#485 each had to retract the stronger claim once, #486 twice): raw vs stripped differ
// in **0 of 5** needle verdicts across both trees. It is one keystroke from load-bearing —
// the ⛔ retraction this slice writes into `EchoelStudioView` describes the removed gate as
// `if let frame { … }` with an ellipsis ON PURPOSE, so the needle never forms in prose. Write
// it out in full there and claim 4a goes RED on correct code.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheNarrationCannotClaimABodyItDidNotReadTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let director = "Sources/Echoelmusic/Sequencer/BioMusicDirector.swift"

    // MARK: - Behaviour: the shipped function, driven end to end

    /// Claim 1 — with NO frame at all, the narration says so and claims nothing about the person.
    /// This is the branch #500 makes the common one, and before this slice it was unreachable
    /// from the app.
    func testWithNoFrameTheNarrationSaysNoPulseWasMeasured() {
        let t = BioExplanation.text(for: nil, tempo: 120)
        XCTAssertTrue(t.contains("no pulse measured yet"), """
        a take composed with no body did not say so: \(t)
        """)
        for fabricated in ["unsteady signal", "breathing", "coherence", "BPM sets a"] {
            XCTAssertFalse(t.contains(fabricated), """
            narrated '\(fabricated)' from a body that was never read: \(t)
            """)
        }
    }

    /// Claim 2 — and it must not credit a live signal one clause after saying there is none.
    /// The exact defect `measuredAnything` exists to prevent, now reachable for a nil frame.
    func testWithNoFrameTheTailDoesNotCreditALiveSignal() {
        let t = BioExplanation.text(for: nil, tempo: 120)
        XCTAssertFalse(t.contains("from your live signal"), """
        promised music 'from your live signal' for a take that read no body: \(t)
        """)
        // The tail describes the ENGINE and is still there — the sentence must stay useful,
        // not collapse to a bare apology.
        XCTAssertTrue(t.contains("morphs in at the bar line"), """
        dropped the engine description along with the body claim: \(t)
        """)
    }

    /// Claim 3 — the COUNTERWEIGHT to claims 1–2 and the reason they are not enough on their
    /// own: removing the live-signal credit unconditionally would satisfy both of them while
    /// silently telling a body that IS being read that it is not driving anything.
    func testAMeasuredBodyIsStillToldItIsDriving() {
        let t = BioExplanation.text(for: Self.frame(hr: 62, coherence: 0.8, breath: 6), tempo: 90)
        XCTAssertTrue(t.contains("from your live signal"), """
        a fully measured body was not credited: \(t)
        """)
        XCTAssertTrue(t.contains("62 BPM"), "dropped the measured heart rate: \(t)")
        XCTAssertFalse(t.contains("no pulse measured yet"), """
        claimed no pulse for a frame carrying 62 BPM: \(t)
        """)
    }

    /// Claim 6 — #634b. The narration is the HARDEST surface of the #627 family to mark and
    /// the one where being unmarked costs most: the other seven are cells, where a dim tag
    /// beside a number qualifies it by adjacency. This is a running sentence spoken in the
    /// voice of "EchoelAI", so an unmarked demo produced a paragraph of specific claims about
    /// the reader's body — an integer BPM, a coherence verdict, a breathing description — and
    /// closed with the literal possessive "from your live signal".
    ///
    /// ⛔ `measuredAnything` COULD NOT CATCH IT, and claims 1–3 above are exactly why: they
    /// pin whether a channel was READ, never where the reading came from. `BioSimulator`
    /// satisfies every `hasMeasured…` gate by construction, so the demo passes all three.
    func testTheDemoSourceIsNamedRatherThanClaimedAsTheListenersBody() {
        let demo = BioSampleFrame(timestamp: 1, heartRateBPM: 62, hrvNormalized: 0.5,
                                  breathRate: 6, breathPhase: 0.25, coherence: 0.8,
                                  motionEnergy: 0, source: .fallback)
        let t = BioExplanation.text(for: demo, tempo: 90)
        XCTAssertFalse(t.contains("from your live signal"), """
        the narration used the possessive form for a frame the demo generator produced: \(t)
        """)
        XCTAssertTrue(t.contains("from the demo signal"), """
        …and it must still credit SOMETHING — silently dropping the clause would satisfy the \
        assertion above while telling a demo listener nothing about where the sound comes \
        from. Naming the source is the fix; deleting the sentence is not: \(t)
        """)
        XCTAssertTrue(t.hasPrefix("EchoelAI (demo signal) — "), """
        the marker must LEAD. Placed anywhere else it corrects a claim the reader has already \
        accepted — the same ordering law the VoiceOver prefixes follow (#629b): \(t)
        """)
    }

    /// Claim 7 — the COUNTERWEIGHT to claim 6, and it is the one that matters: the cheap way
    /// to satisfy claim 6 is to strip the possessive everywhere, which would tell a REAL body
    /// that it is not driving anything. Claim 3 already pins the phrase; this pins the PREFIX,
    /// which claim 3 predates and does not see.
    func testAMeasuredBodyIsNotLabelledAsADemo() {
        let t = BioExplanation.text(for: Self.frame(hr: 62, coherence: 0.8, breath: 6), tempo: 90)
        XCTAssertTrue(t.hasPrefix("EchoelAI — "), """
        a real measured frame was prefixed as a demo — the mirror of the bug claim 6 fixes, \
        and the more damaging direction: it tells a listener their own pulse is fake: \(t)
        """)
        XCTAssertFalse(t.contains("demo signal"), "…and the demo wording must not leak in: \(t)")
    }

    // MARK: - Wiring: the caller must not gate the honesty off again

    /// Claim 4a — the write is a STATEMENT, not the body of an `if let`. This is the whole fix,
    /// and the statement-level form is what makes it checkable: the removed version read
    /// `if let frame { caption.text = BioExplanation.text(…) }`, which CONTAINS the same
    /// substring a naive positive scan would look for. Anchoring on the start of the trimmed
    /// line separates the two without a second needle.
    func testTheNarrationIsWrittenForEveryTakeNotOnlyForABodiedOne() throws {
        let lines = try studioCode().split(separator: "\n", omittingEmptySubsequences: false)
        let writes = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("caption.text = BioExplanation.text(") }
        // #367: anchor first. A rename empties the list and the loop below would pass on
        // nothing — which is how a guard stops being able to fail for its stated reason.
        XCTAssertFalse(writes.isEmpty, """
        no `caption.text = BioExplanation.text(` anywhere in \(Self.studio).

        Either the narration write was renamed — re-anchor this claim — or it was DELETED, in \
        which case delete claims 4a/4b and the `BioExplanation` half of this file together, \
        deliberately, and say so in CLAUDE.md. Do not let this skip.
        """)
        for line in writes {
            XCTAssertTrue(line.hasPrefix("caption.text"), """
            the narration write is conditional again: \(line)

            Gating it on a frame is exactly #506: `BioExplanation.text` handles the no-body \
            case itself (claims 1–2), and a gate both hides that branch AND leaves the \
            PREVIOUS take's heart rate on screen, because nothing else writes or clears \
            `caption.text`. Pass the optional through instead of guarding it.
            """)
        }
    }

    /// Claim 4b — belt and braces on the exact historical shape, named so a future reader knows
    /// which form was removed. Green on this tree only because the retraction comment in the
    /// source writes the gate with an ellipsis; see the `SourceText.codeOnly` note in the header.
    func testTheRemovedGateDoesNotComeBackVerbatim() throws {
        XCTAssertFalse(try studioCode().contains("if let frame { caption.text"), """
        the `if let frame { caption.text … }` gate is back in \(Self.studio).
        """)
    }

    /// Claim 4c — and the callee has to be able to accept "no body" at all. Without this, a
    /// later "tidy-up" could make the parameter non-optional again and claim 4a would have to
    /// be reverted with it; this makes that a compile-visible decision instead.
    func testBothEntryPointsAcceptAnUnmeasuredBody() throws {
        let code = try directorCode()
        XCTAssertTrue(code.contains("text(for f: BioSampleFrame?, tempo: Double)"), """
        `BioExplanation.text` no longer accepts a nil frame — the no-body narration is \
        unreachable from the app again.
        """)
        XCTAssertTrue(code.contains("init(from f: BioSampleFrame?)"), """
        `BioStateSummary` no longer accepts a nil frame. Nil is not a new case here: it is \
        all-three-fields-unmeasured, which every clause already handles. Re-introducing a \
        separate `unmeasured` constant would be a SECOND definition of the same fact (#416), \
        and synthesising a zeroed `BioSampleFrame` would be worse — that file's own doc \
        explains why a 0 must never be read as a low value.
        """)
    }

    // MARK: - The premise the rest of this file rests on

    /// Claim 5 — the COUNTERWEIGHT, and the premise every claim above quietly assumes.
    /// Green before this commit and after it: `liveNarrationBanner` has exactly ONE occurrence
    /// in the studio source — its own declaration — so `StudioCaptionView` is never mounted and
    /// none of this is visible to a user today (task #326).
    ///
    /// It runs the OPPOSITE way round from the rest of the file: it is here to go RED when the
    /// banner is MOUNTED, which is a good change and exactly the moment the "doorless" prose in
    /// the header above, in `StudioCaptionView`, and in task #326 becomes false at once (#456).
    func testTheNarrationBannerIsStillUnmounted() throws {
        let code = try studioCode()
        let occurrences = code.components(separatedBy: "liveNarrationBanner").count - 1
        XCTAssertEqual(occurrences, 1, """
        `liveNarrationBanner` now appears \(occurrences)× in \(Self.studio) — it used to be \
        just its own declaration.

        If it has been MOUNTED: welcome, and update the prose in the same commit — the ⛔ \
        HONEST LIMIT block at the top of this file, the doorless note in \
        StudioCaptionView.swift, and task #326. The narration's device checks (does it render, \
        does it read well aloud) become real at that moment, and claims 1–4 stop being a \
        mechanism fix and start describing a screen.

        If it was DELETED instead: delete this claim with it, and decide deliberately whether \
        `BioExplanation` keeps a caller at all.
        """)
    }

    // MARK: - Helpers

    private static func frame(hr: Float, coherence: Float, breath: Float) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1,
                       heartRateBPM: hr,
                       hrvNormalized: 0.5,
                       breathRate: breath,
                       breathPhase: 0.25,
                       coherence: coherence,
                       motionEnergy: 0,
                       source: .cameraPPG)
    }

    private func studioCode() throws -> String { try code(at: Self.studio) }
    private func directorCode() throws -> String { try code(at: Self.director) }

    private func code(at relativePath: String) throws -> String {
        let path = try treeRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The skip is scoped to the TREE, never to a file (#454): a `fileExists` bracket around
    /// each read would turn the very deletion this file guards against into a green skip.
    private func treeRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}
