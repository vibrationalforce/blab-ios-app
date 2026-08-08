//
//  TwoFreshnessRegimesAreDeliberateTests.swift
//  Echoelmusic — CISmoke (blocking bundle)
//
//  #499. There are TWO freshness regimes on ONE bio bus, they are both correct, and until this
//  commit the comment that justified one of them claimed they were the same thing.
//
//  MEASURED, NOT ASSUMED:
//  · GATED (`EngineBus.usableBio()`, per-source freshness window) — `FXBioModulator.tick`,
//    `ModulationEngine.tick`, and the composer's `makeComposerInput`.
//  · UNGATED (`bus.latestBio` raw, deduped on `frame.timestamp`) — the two producers that
//    shape the instrument's OWN timbre: `BioReactiveSynthVoice.applyLatestIfFresh` and
//    `PolySynthVoice.applyLatestIfFresh`. Neither file contains the string `usableBio` at all
//    (`grep -c` = 0 in both).
//
//  The sentence that was in `FXBioModulator` read: "Now every sound-shaping bio gate is the one
//  authority: a frame usable to the engine is usable to the FX, and a frame the engine drops
//  (`nil`) disengages the FX bio routes too." The engine drops nothing — `usableBio()` returning
//  nil is what the gated readers see; the timbre never calls it. It was the load-bearing
//  justification for the gate, and it asserted the opposite of the code beside it.
//
//  ⭐ WHY THIS IS A PROSE FIX AND NOT A CODE FIX. An FX route is an ADDITIVE offset the user
//  explicitly asked for, so holding one off a body that stopped arriving is a stale claim and it
//  fades to base. Timbre has no release path: the producers dedupe, so a frozen source is a
//  no-op that PARKS the timbre at the last body, and zeroing it would claim the engine dropped
//  the channel when it did not (the argument is written out at `AlwaysOnBioChannel.reading`, and
//  #503 put the parking on screen as "held"). Two different right answers.
//
//  ⚠️ SO THE VISIBLE RESIDUE IS REGISTERED, NOT REPAIRED: on a frozen camera source (6 s window)
//  the FX offsets release while the timbre stays parked, and only the timbre half says so on
//  screen. Unifying either direction is an AUDIBLE change that needs a hearing test — which is
//  precisely what the false sentence invited someone to do as a consistency cleanup. This file
//  makes either direction go red.
//
//  ⚠️ HONEST GRADING (#433), and it is the #489 shape rather than the usual one: NONE of these
//  four assertions is a regression. All four are green on the parent tree, because #499 changed
//  a comment and nothing else. The one needle that WOULD have been a regression — "the false
//  sentence is gone" — is impossible to write: it was a comment, `SourceText.codeOnly` strips it
//  from both trees, and a raw scan would go RED on correct code because the retraction this
//  commit writes quotes the false sentence verbatim in order to withdraw it. Saying that plainly
//  is the point; classifying forward guards as regressions is the defect #433 names.
//
//  ⚠️ AND THE LIMIT FIRST: every assertion is a SOURCE-TEXT SCAN. Nothing runs. That the FX
//  offsets audibly release, that the timbre audibly parks, and that the disagreement is or is not
//  a problem for a player are all hearing tests, and all three stay open.
//
//  ⛔ `SourceText.codeOnly` (#453) IS PROPHYLACTIC HERE, measured rather than claimed — the
//  over-claim #484/#485 each retracted once and #486 twice. Raw vs stripped, both trees:
//  **0 of 8 needle verdicts differ**. The near miss is two-sided and will stop being a miss:
//  (a) `bus.latestBio` appears in RAW PROSE in both producer files (their headers describe the
//  poll), so without stripping a tree that DELETED the code line and kept the header would pass
//  the positive needle — the #343 trap; (b) the negative `usableBio` needle is one comment away
//  from red, and the obvious comment to write in those files is "we deliberately do NOT call
//  `usableBio()`". The helper stays because #453 made ONE definition of "code, not prose" for
//  this whole bundle.
//

import Foundation
import XCTest

final class TwoFreshnessRegimesAreDeliberateTests: XCTestCase {

    private static let fxDriver = "Sources/Echoelmusic/Tools/FXBioModulator.swift"
    private static let modBrain = "Sources/Echoelmusic/Core/ModulationEngine.swift"
    private static let producers = [
        "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift",
        "Sources/Echoelmusic/Tools/PolySynthVoice.swift",
    ]

    // MARK: - 1. the gated half stays gated

    /// The FX driver asks the per-source window. Removing this to "match the timbre" is the
    /// cleanup the false sentence invited, and it would hold an explicit user offset off a body
    /// that stopped arriving.
    func testTheFXDriverStillAsksTheFreshnessWindow() throws {
        let src = try source(Self.fxDriver)
        XCTAssertTrue(src.contains("bus?.usableBio()"), """
            `FXBioModulator.tick` no longer gates on `usableBio()`.

            If the gate was dropped on purpose, that is an AUDIBLE change — an FX route would \
            keep applying its offset off a frame the composer already treats as no body — and it \
            needs a hearing test plus an update to the account in that file, not this assertion \
            deleted.
            """)
    }

    /// …and so does the mod-brain, which is the surviving TRUE half of the FX driver's comment.
    ///
    /// Without this, the sentence "the SAME per-source window the mod-brain uses" could quietly
    /// become false with nothing to notice — the #343 shape, one file over.
    func testTheModBrainStillAsksTheSameWindow() throws {
        let src = try source(Self.modBrain)
        XCTAssertTrue(src.contains("bus.usableBio()"), """
            `ModulationEngine.tick` no longer gates on `usableBio()`.

            `FXBioModulator` cites it by name as the reason its own window is per-source. Fix \
            that comment in the same commit.
            """)
    }

    // MARK: - 2. the ungated half stays ungated

    /// Both timbre producers read the snapshot RAW. Adding a gate here "for consistency" is the
    /// other direction of the same cleanup, and it is the more damaging one: it would collapse
    /// the timbre to the bare patch the moment a source freezes.
    func testTheTimbreProducersStillReadTheBusRaw() throws {
        for path in Self.producers {
            let src = try source(path)
            XCTAssertTrue(src.contains("bus.latestBio"), """
                \(path) no longer reads `bus.latestBio`.

                The always-on timbre path is what "your body plays it" means; a producer that \
                stopped reading the snapshot has lost the capability, not tidied it.
                """)
            XCTAssertFalse(src.contains("usableBio"), """
                \(path) now gates on `usableBio()`.

                That is an AUDIBLE change, not a consistency fix: the producers dedupe on \
                `frame.timestamp`, so today a frozen source PARKS the timbre at the last body. \
                Gating would instead drop every channel back to the patch mid-performance — and \
                `AlwaysOnBioChannel.reading` plus the "held" row shipped in #503 both describe \
                the parking as the honest behaviour. Decide it with a hearing test.
                """)
        }
    }

    /// The dedupe is load-bearing for the PARKING argument, not housekeeping.
    ///
    /// `applyBioReactive` accumulates into one-pole state, so re-applying the same stale frame at
    /// the 10 Hz poll rate instead of the ~1 Hz publish rate changes the smoothing trajectory —
    /// the 10×-rate class of defect #315/#332/#336 were each one instance of. Without the dedupe,
    /// "a frozen source is a no-op" stops being true and parking stops being free.
    func testBothProducersStillDedupeOnTheTimestamp() throws {
        for path in Self.producers {
            let src = try source(path)
            XCTAssertTrue(src.contains("frame.timestamp != lastTimestamp"), """
                \(path) no longer dedupes on `frame.timestamp`.

                A raw 10 Hz read WITHOUT the dedupe re-drives the one-pole bio smoothers ten \
                times per publish, which is the rate defect #315/#332/#336 each fixed once. It \
                also breaks the premise that a frozen source costs nothing.
                """)
        }
    }

    // MARK: - source access

    /// Comment-stripped source, or a throw when a scanned file has moved.
    ///
    /// The skip is scoped to the TREE, not the file (#454): skipping whenever a scanned FILE is
    /// missing would turn every claim here green the moment somebody renames one, and a skip
    /// PASSES CI.
    private func source(_ relativePath: String) throws -> String {
        let path = try treeRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

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
