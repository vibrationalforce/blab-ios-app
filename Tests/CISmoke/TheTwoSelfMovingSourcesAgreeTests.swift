// TheTwoSelfMovingSourcesAgreeTests.swift
// Echoel — #562. Two slices, one cycle apart, put a claim and its own refutation on the same
// screen. This file is the repair and the tripwire.
//
// WHAT HAPPENED, because the shape of it matters more than the string. #559 mounted the
// automation readout at the bottom of `soundPanel`, and with nothing recorded it printed
// "Nothing is automated yet — no parameter is moving on its own." #560 put a line at the TOP of
// the same panel: "Your body also shapes this sound … Brightness, Harmonics, Noise, Cutoff,
// Vibrato depth and Vibrato rate move around the values you set here." One panel, one scroll
// apart, saying that parameters move by themselves and that none do.
//
// ⭐ WHY NEITHER REVIEW CAUGHT IT. Each sentence is TRUE about its own subject — one is about
// automation lanes, the other about the always-on bio path — and each was written in a slice
// that only had its own subject in view. #425 is normally a within-slice law ("a slice must not
// contain a claim and its own refutation"); this is the ACROSS-slice form, where the
// contradiction is assembled by a second commit that never touches the first one's file. The
// composing surface is the only place it exists, so the only guard that can see it is one that
// asks the SCREEN rather than either source.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1 and 2 are END-TO-END BEHAVIOUR over public Foundation-only value types — they
//     drive the shipped strings, not a description of them.
//   · claim 3 is a SOURCE-TEXT SCAN: it establishes that the two strings really do land on ONE
//     panel, which is what makes claims 1 and 2 about anything at all. Without it this file
//     guards a contradiction between two sentences that might not share a screen.
//   · DEVICE PROBE, open and untouched: whether the two lines READ as one answer at opposite
//     ends of a long panel, or whether the empty-automation line should sit next to the body
//     line instead. That is a layout judgement and needs eyes.
//
// ⚠️ HONEST GRADING, transcribed in Python against the parent (`9404919`) and this tree; the
// file compiles against both, because every symbol it names already existed:
//   · ONE DEFECTIVE STRING, THREE RED ASSERTIONS, **ONE FINDING** (#486). On the parent
//     `emptySentence` reads "Nothing is automated yet — no parameter is moving on its own.",
//     which fails three of the seven assertions here: it denies motion in general, it never
//     names automation as its subject, and it never names the body. They are three required
//     REPAIRS of one sentence, not three defects.
//   · The other four assertions are COUNTERWEIGHTS, green on both trees: the body-shaped set is
//     non-empty, the sentence is not blank, and claim 3's two mounts. Claim 3 is the one that
//     makes the rest mean anything — it establishes that the two lines share a screen.
//   · ⛔ AND MY DRAFT OF THIS BLOCK CALLED CLAIM 2 A COUNTERWEIGHT "green on both". Measured, it
//     is red on the parent: the old sentence names no other source. The difference matters
//     because a counterweight and a regression make opposite promises about what the parent
//     tree looked like. This time the transcription ran BEFORE the block was committed and
//     corrected it — which is the whole point of the rule two slices ago; the draft was wrong
//     in the FLATTERING direction (#433), claiming the old text already did something it did
//     not, and only the run said otherwise.
//   · STRIPPER — measured, not assumed: **PROPHYLAKTISCH, 0 of 4 verdicts flip** (claim 3's two
//     needles × 2 trees). Claims 1 and 2 are behavioural and never touch the stripper.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheTwoSelfMovingSourcesAgreeTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - claim 1 (REGRESSION) — the empty list may not deny what the panel above asserts

    /// The contradiction, driven rather than described. The body line names concrete row
    /// labels; the automation line must not make a blanket denial that covers them.
    func testTheEmptyAutomationLineDoesNotDenyTheBodyLine() {
        let empty = AutomationStatus.emptySentence.lowercased()
        let bodyRows = BioShapedParameter.shapedByTheBody.flatMap(\.soundPanelRows)
        XCTAssertFalse(bodyRows.isEmpty, """
            No parameter is reported as body-shaped, so this test has no contradiction left to \
            guard. That is a real change — see `TheBodyShapedRowsAreNamedOnceTests` — and this \
            file should be revisited in the same commit rather than left passing on nothing.
            """)
        XCTAssertFalse(empty.contains("no parameter is moving on its own"), """
            The empty-automation line denies that any parameter moves on its own, on a panel \
            whose own body line says \(bodyRows.count) of its rows do — \
            \(bodyRows.joined(separator: ", ")). Both sentences are true about their own \
            subject and the SCREEN is false; that is #425 assembled across two slices. The line \
            must scope its denial to automation ("nothing is replaying a curve"), not to motion \
            in general.
            """)
        XCTAssertTrue(empty.contains("automation"), """
            The empty-automation line no longer names automation as its subject. A strip that \
            reports on curves has to say so, or its denial reads as a statement about the whole \
            instrument — which is exactly how it collided with the body line.
            """)
    }

    // MARK: - claim 2 (COUNTERWEIGHT) — and it answers the question instead of going quiet

    /// The assertion that blocks the cheap repair. Deleting the offending clause satisfies
    /// claim 1 and leaves a player looking at an empty list with their question intact: the
    /// sound IS changing, and the strip that just told them nothing is automated is the last
    /// place they will look for why. The sentence has to name the other source.
    func testTheEmptyLineNamesTheOtherSelfMovingSource() {
        let empty = AutomationStatus.emptySentence.lowercased()
        XCTAssertTrue(empty.contains("body"), """
            The empty-automation line no longer names the body. With nothing recorded, the \
            always-on bio path is the ONLY other writer of these parameters — \
            `applyBioReactive` recomputes them per render block from their `bioBase*` anchors — \
            so "no automation" plus silence about the body leaves the player's real question \
            ("why is this moving?") answered by neither line on the panel. If a THIRD \
            self-moving source ever appears, this sentence becomes wrong again and this is the \
            assertion that should be widened rather than deleted.
            """)
        XCTAssertFalse(AutomationStatus.emptySentence.isEmpty,
                       "an empty string would satisfy every negative assertion above")
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the two lines really do share one screen

    /// Without this, claims 1 and 2 guard a contradiction between two sentences that might not
    /// meet. If either line moves to another surface the collision is gone and this whole file
    /// is about a screen that no longer exists — so it goes red and says which half moved.
    func testBothLinesAreMountedOnTheSamePanel() throws {
        let body = try soundPanelBody()
        XCTAssertTrue(body.contains("BioShapedParameter.soundPanelSentence"), """
            `soundPanel` no longer renders the body-shaped line. If it moved to another \
            surface, the contradiction this file guards moved with it — re-anchor here in the \
            same commit, or retire the file deliberately (#456).
            """)
        XCTAssertTrue(body.contains("AutomationStatusStrip()"), """
            `soundPanel` no longer mounts the automation strip, which is where \
            `emptySentence` is rendered. Same reasoning as above: this file exists because the \
            two lines share a screen.
            """)
    }

    // MARK: - source access

    private struct SourceAnchorMissing: Error { let reason: String }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// Brace-matched body of `soundPanel` (#408).
    private func soundPanelBody() throws -> String {
        let code = try codeText(Self.studio)
        guard let anchor = code.range(of: "private var soundPanel: some View"),
              let open = code.range(of: "{", range: anchor.upperBound..<code.endIndex) else {
            throw SourceAnchorMissing(reason: """
                `private var soundPanel: some View` was not found in \(Self.studio). Re-anchor \
                rather than letting this scan pass on nothing (#454).
                """)
        }
        var depth = 0
        var i = open.lowerBound
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.lowerBound...i]) }
            }
            i = code.index(after: i)
        }
        throw SourceAnchorMissing(reason: "`soundPanel`'s braces do not close")
    }
}
