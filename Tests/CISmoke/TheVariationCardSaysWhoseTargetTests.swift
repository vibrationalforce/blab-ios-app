// TheVariationCardSaysWhoseTargetTests.swift
// Echoel — #645: the variation card put a DESIRE in the reader's mouth that nobody expressed.
//
// WHAT THIS GUARDS, and it is the strongest claim the #627 honesty family has had to correct.
// Every earlier one was a statement about a READING — "your body is at 62 %", "four body
// channels shape the timbre", "what your body is doing to the sound". This one is a statement
// about a WANT: "Ideas from your pulse — tap to keep. **Your body wants** a full groove." It
// rendered unconditionally, and `targetDensity` traces `BioComposer.musicalState` → the composer
// input → `bus.usableBio()` — the demo generator's fabricated frame under the Simulation source,
// and the engine's own default with no source at all. So on a demo session the card told the
// player their body wanted something, when no body had been read.
//
// ⚠️ REACHABLE, unlike the surface #644 fixed. `variationsCard` is mounted in `tempoToolsPanel`,
// which the "Tempo & variations" chip opens; the "Explore" button inside it is what builds a
// board. Stated because the previous slice in this family was on a PARKED surface and had to say
// so — this one carries the opposite fact and it should be just as explicit.
//
// ⭐ `.body` KEEPS "wants" WORD FOR WORD. The anthropomorphism is the founder's shipped voice and
// it is true when a real body was read. Only the SUBJECT moves — rewriting a sentence that is
// already honest is the over-correction this family has retracted twice (#480, #491).
//
// ⭐ AND THE THREE-STATE ENUM IS REUSED, not re-declared. `BioNarrationDriver` (#644) already owns
// "a real body / the demo generator / nobody"; a second enum for the second surface would be
// exactly the #416 defect. Its NAME still says "narration" — see the widened doc on the type for
// why that is disclosed rather than renamed away one commit after it landed.
//
// ⚠️ THE no-board BRANCH IS DELIBERATELY NOT MARKED, and claim 4 pins it. "Variations of the same
// groove — your body curates, you pick." renders BEFORE any exploration exists, so it claims
// nothing about a current reading — it says what the control is for. Marking it would imply a
// demo is running when none is. Same decision as the two instructional FX strings (#641 claim 5)
// and the reason this family's remaining risk is over-correction, not under-correction.
//
// KIND (§1): **MIXED.** Claims 1–2 DRIVE `BioVariationMaze.boardSentence(driver:density:)`, a
// pure static on a `Sequencer/` type — END-TO-END, the strong kind. Claims 3–5 are SOURCE-TEXT
// SCANS, because `variationsCard` is a `private var` on a SwiftUI struct this bundle cannot
// mount.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (c65472d):
//   · **3 RED-ON-PARENT BY MEASUREMENT** — 3a (the view renders the pure sentence), 3b (the
//     driver is written beside the board) and 5a (the old unconditional literal is gone from the
//     view). 3c (exactly one `mazeDriver` write) is red there too, but for the SAME absence as
//     3b — `mazeDriver` does not exist on the parent — so it is booked as part of one finding,
//     not a fourth (#486). Both reviewers re-drove the three above independently.
//   · **6 FORWARD, BEHAVIOURAL (1a–1c, 2a–2c)** — the three sentences and the three subjects.
//     They cannot be red-on-parent: `boardSentence` does not exist there, so a bundle containing
//     them does not compile. Written down rather than counted (#642).
//   · **2 COUNTERWEIGHTS, green on both trees** — 4a (the no-board invitation is untouched) and
//     4b (`densityWord`'s four words are unchanged, so the slice moved the subject and not the
//     scale).
//   · **Stripper: TRAGEND — 1 of the 6 scan verdicts flips raw-vs-stripped, 0 of 6 on the
//     parent.** (Six, not five: the review pass added 3c. Re-driven after every needle change
//     the reviewers asked for — a grading block written before the last edit is a memory.)
//     Driven, and the flipping claim is **3b**: `SourceText.codeOnly` blanks the
//     three-line comment this slice put BETWEEN the two writes while preserving line count, so
//     the stripped walk lands on the driver write and the raw walk lands on my own explanation.
//     ⛔ The first draft of this block named **5a** and gave a reason that measurement refutes
//     twice: 5a scans `EchoelStudioView.swift`, while the ⛔ retraction that quotes the old
//     sentence lives in `BioVariationMaze.swift`, and that retraction does not carry the `\\(`
//     the needle requires anyway. It also counted **4** verdicts where the file declares five.
//     Both halves were reasoned, not run — the third mislabelled grading block in three cycles,
//     and the only one whose real cause was a comment I wrote in the same commit.
//
// ⚠️ KNOWN LIMIT, REGISTERED RATHER THAN FIXED: `mazeDriver` refreshes only on an Explore
// tap. Explore under Camera, then switch to Simulation without re-exploring, and the card keeps
// saying "your body" — UNDER-marking, the dangerous direction. It is still strictly better than
// what shipped (unconditionally wrong in 100 % of demo sessions vs. wrong only between a source
// change and the next Explore, where the button relabels to "New"), and the marking is accurate
// about the DISPLAYED data: `targetDensity` was computed at explore time and that board is the
// board on screen. What is stale is the present tense of "wants" agreeing with the current
// source. ⛔ DO NOT RECORD THIS AS "the same limit `StudioCaption.driver` already has" — it is
// the same SHAPE with a decisive difference the review measured: `caption.driver` is rewritten
// by `generate()`, which the evolve tick re-enters roughly every 30 s during a take, so the
// narration SELF-HEALS. This one does not. Calling them identical is the flattering direction.
//
// ⚠️ #364: a different honest shape is not forbidden. Dropping "wants" everywhere, folding the
// sentence into the board rows, or marking at the card level would all satisfy the law and turn
// claims 1/2 red — that is the moment to rewrite this file. What is forbidden silently is a card
// that tells a player what their body wants when no body was read.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVariationCardSaysWhoseTargetTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    // ⛔ A `maze` path constant stood here and NOTHING used it. The three sentences live in
    // `BioVariationMaze.swift`, but claims 1–2 DRIVE them — a source scan of the same file
    // would be the weaker duplicate of an end-to-end assertion, and an unused anchor reads as
    // coverage while proving nothing (§1).

    // MARK: - 1–2  the three sentences, driven

    /// 1 — FORWARD. Only the real-body branch may say "your body", and it must still say it.
    func testOnlyAMeasuredBodyIsToldWhatItWants() {
        let body = BioVariationMaze.boardSentence(driver: .body, density: "a full groove")
        XCTAssertEqual(body, "Ideas from your pulse — tap to keep. Your body wants a full groove.",
                       """
                       The real-body sentence changed. It is the founder's shipped voice and it \
                       is TRUE when a body was read; this slice moves the SUBJECT for the other \
                       two states and rewrites nothing here.
                       """)
        for driver in [BioNarrationDriver.simulatedDemo, .nothingMeasured] {
            let s = BioVariationMaze.boardSentence(driver: driver, density: "a full groove")
            XCTAssertFalse(s.contains("Your body wants"), """
                \(driver) still tells the player what their body wants. Nothing measured their \
                body — this is a DESIRE put in the reader's mouth, the strongest claim this \
                family has had to correct.
                """)
            XCTAssertFalse(s.contains("from your pulse"), """
                \(driver) still sources the ideas from the player's pulse. The target density \
                came from the demo generator or from the engine's own default.
                """)
        }
    }

    /// 2 — FORWARD. Each of the other two names ITS driver, and the density word survives all
    /// three so the card still explains WHY the ideas are ranked as they are.
    func testTheOtherTwoNameTheirOwnDriver() {
        let demo = BioVariationMaze.boardSentence(driver: .simulatedDemo, density: "a calm groove")
        XCTAssertTrue(demo.contains("simulated demo source") && demo.contains("not your body"), """
            The demo sentence no longer names the demo generator. Every other surface in this \
            family marks it; a card that ranks ideas against a fabricated target and says \
            nothing is the defect #645 removed.
            """)
        let none = BioVariationMaze.boardSentence(driver: .nothingMeasured, density: "something dense")
        XCTAssertTrue(none.contains("No pulse was measured"), """
            The no-reading sentence names somebody again. With no frame the target is the \
            ENGINE's default — naming any body invents the reason the ideas are ranked this way. \
            This is the state a `Bool` could not express one slice ago (#644).
            """)
        for (driver, word) in [(BioNarrationDriver.body, "a full groove"),
                               (.simulatedDemo, "a calm groove"),
                               (.nothingMeasured, "something dense")] {
            XCTAssertTrue(BioVariationMaze.boardSentence(driver: driver, density: word)
                            .contains(word), """
                \(driver) dropped the density word. The card's whole job is to explain WHY these \
                six ideas and not others; the subject changed, the explanation must not vanish.
                """)
        }
    }

    // MARK: - 3–5  the wiring, and what must not change

    /// 3a/3b — REGRESSION, measured red on the parent.
    func testTheCardRendersThePureSentenceFromAnAdjacentWrite() throws {
        let studio = try codeText(Self.studio)
        XCTAssertTrue(squeezed(studio).contains("BioVariationMaze.boardSentence("), """
            `variationsCard` no longer renders the pure sentence. A literal here is a second \
            definition of the same decision, free to drift from the three the type owns (#416).
            """)
        let lines = studio.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let boardAt = lines.firstIndex(where: {
            $0.contains("mazeBoard = BioVariationMaze.explore(")
        }) else {
            return XCTFail("""
                `mazeBoard = BioVariationMaze.explore(` is gone from \(Self.studio) — re-anchor \
                this scan rather than letting it pass on nothing (#454).
                """)
        }
        // ⚠️ NEXT NON-BLANK CODE LINE, never a fixed window — `SourceText.codeOnly` blanks
        // comments while PRESERVING line count, so any window rots as the prose between the two
        // writes grows (#408). #644's first draft used `+ 8` and had already eaten three slots
        // with its own retraction block.
        let next = lines[(boardAt + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(next?.trimmingCharacters(in: .whitespaces),
                       "mazeDriver = BioExplanation.driver(for: made.frame)", """
            The driver write is no longer the statement immediately after the board write. Two \
            writes that can drift apart describe two different explorations, and the card then \
            names the driver of a board that is no longer on screen.
            """)
        // 3c — adjacency is worthless without exclusivity. A SECOND `mazeDriver = …` anywhere
        // (an `onChange(of: bioSource)`, a stop handler) leaves 3b green while destroying the
        // guarantee its message claims. The sibling guard for the identical decision pins this
        // at `TheNarrationHeadingNamesItsDriverTests` and this file had dropped it (#645 review).
        // ⚠️ COUNT THE ASSIGNMENT, NOT THE TOKEN: the `@State` declaration and the render site
        // both contain `mazeDriver`. Squeezed, the declaration reads `mazeDriver:BioNarrationD…`
        // and the render site `driver:mazeDriver,` — neither carries `mazeDriver=`, so the
        // needle selects assignments alone. Verified 1 on the worktree, 0 on the parent.
        let writes = squeezed(studio).components(separatedBy: "mazeDriver=").count - 1
        XCTAssertEqual(writes, 1, """
            `mazeDriver` is assigned \(writes) times, not once. Exactly one write, beside the \
            board write, is what makes the card's subject describe the board on screen.
            """)
    }

    /// 4a/4b — COUNTERWEIGHT. The no-board invitation and the density scale are untouched.
    func testTheInvitationAndTheScaleAreLeftAlone() throws {
        let studio = try codeText(Self.studio)
        // ⚠️ THE FRAGMENT, NOT THE SENTENCE (#364). Pinning the whole line reds on any copy
        // edit — a comma, an em-dash — and a guard that forbids ordinary correct work gets
        // deleted with the law inside it. What this claim owns is that the branch stays
        // UNMARKED, and "your body curates" is the smallest text that carries exactly that.
        XCTAssertTrue(studio.contains("your body curates"), """
            The no-board invitation was reworded or marked. It renders BEFORE any exploration \
            exists, so it claims nothing about a current reading — it says what the control is \
            for. A "sweep the file for the word body" cleanup is how this one gets taken.
            """)
        for word in ["something sparse", "a calm groove", "a full groove", "something dense"] {
            XCTAssertTrue(studio.contains("\"\(word)\""), """
                `densityWord` lost "\(word)". This slice moves the sentence's SUBJECT; the scale \
                that explains WHY six ideas were ranked is not part of that decision.
                """)
        }
    }

    /// 5a — REGRESSION. The unconditional claim is gone from the view.
    func testTheUnconditionalClaimIsGoneFromTheView() throws {
        // ⚠️ THE NEEDLE IS THE PHRASE, NOT THE INTERPOLATION. The first draft asked for
        // `Your body wants \\(`, which a re-inlining as `"Your body wants " + densityWord(…)`
        // walks straight past while 3a stays green (it only needs the pure call to exist
        // SOMEWHERE in the file). Measured: the phrase occurs 0× in this file's code today and
        // 1× on the parent, so widening costs nothing and closes the concatenation hole.
        XCTAssertFalse(try codeText(Self.studio).contains("Your body wants"), """
            `EchoelStudioView` builds the "Your body wants …" sentence again. The three forms \
            are owned by `BioVariationMaze.boardSentence`; a literal here is a second definition \
            and, on the shipped tree, was the unconditional one (#416).
            """)
    }

    // MARK: - source access

    private struct MazeAnchorMissing: Error { let reason: String }

    private func squeezed(_ code: String) -> String { code.filter { !$0.isWhitespace } }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MazeAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
