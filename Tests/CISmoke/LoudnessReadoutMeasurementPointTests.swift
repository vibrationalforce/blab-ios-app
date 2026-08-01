// LoudnessReadoutMeasurementPointTests.swift
// Echoel — #316. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ READ THIS FIRST — #316b MOVED THE MEASUREMENT, SO THE NEXT BLOCK IS HISTORY. The EBU
// R128 tap now sits on `AutoMixChain.chainOutputNode` (the limiter's output) and the four
// values are published as `masterOutput…` with the −1 dB trim added back. The LEVEL BARS
// stay pre-chain, deliberately, because `masterLevel` is the auto-gain's input. The live
// invariants are the last four tests in this file; the three pre-chain guards below now
// only re-arm if the tap is reverted (`testTheDetailedMeterIsInstalledOnTheChainOutput`
// exists because the name-only predicate does NOT notice such a revert on its own).
//
// ⭐ THE ONE PAIRING THIS FILE EXISTS FOR — as it stood before #316b: `MasterLoudnessGrid`
// showed EBU R128 numbers that `AudioEngine.installMeterTap()` measured at `masterMixer` —
// the node `AutoMixChain.insert` takes as its `from:`. Everything the master chain does
// happened AFTER that point:
//
//     masterMixer ──[tap]──▶ EQ ▶ auto-gain ▶ PeakLimiter ▶ mainMixerNode (×0.89 ≈ −1 dB)
//
// The NUMBER is legitimate — it is the loudness of the mix being made. A target VERDICT on
// it is not, and it is wrong in a systematic direction, which is what makes it dangerous:
//
//   · the auto-gain reads the SAME pre-chain signal and drives `gain ≈ target − reading`
//     (clamped ±6 dB), so the verdict reports the deviation the chain is about to remove:
//     the raw mix painted "too quiet" is exactly the one lifted ONTO target, while a raw
//     mix that reads on target leaves ≈ 1 dB under it;
//   · the true peak is read BEFORE the brick-wall limiter, i.e. before the one stage whose
//     job is to stop that peak from ever reaching the output.
//
// So #316 removed both verdict colours and put the measurement point on screen. This file
// pins that the moving parts can never drift apart:
//
//   · a verdict back while no post-chain measurement exists → the false-verdict trap returns
//   · disclosure gone while no post-chain measurement exists → the numbers read as output
//   · post-chain measurement exists but the colours stay neutral → harmless, deliberately
//     NOT failed here (a correct measurement with neutral colours is honest; see
//     `testTheVerdictFunctionsSurviveTheirCallerlessPeriod` for why the functions are kept)
//
// ⛔ THE FIRST DRAFT ASKED THE WRONG QUESTION, and review caught it before it could do harm.
// It decided "pre-chain" by looking for `masterMixer.installTap(` in `AudioEngine.swift`.
// But the fix `MasterLoudnessGrid`'s own header recommends is a SECOND tap on the limiter's
// output — which LEAVES `masterMixer.installTap(` in place, deliberately, because
// `_outputRing` (the FFT visual) and the #193 timing instrument must stay on that closure.
// So the guard would have gone red on the correct fix while its failure message told the
// author to perform it. A guard that fires on the right answer is worse than no guard.
//
// THE PREDICATE IS THEREFORE THE THING THAT ACTUALLY DECIDES THE VERDICT'S VALIDITY: does
// `AudioEngine` publish a post-chain measurement at all? #316b must name that publisher with
// a symbol containing `masterOutputLUFS`; the same contract is written at the bottom of
// `MasterLoudnessGrid.swift`'s header. This cannot be satisfied by accident, which is the
// point — the tap's LOCATION could be.
//
// ⚠️ WHAT THIS FILE CANNOT REACH, so the coverage is not overread: it cannot build the view,
// cannot prove the caption is visible, and cannot observe a single sample. It reads SOURCE
// TEXT for tokens. That is weaker than a behavioural test and stronger than nothing — and
// with no local toolchain and an audio graph that only exists on a device, it is the only
// level at which this pairing is checkable from here at all.
//
// No `@testable import Echoelmusic`: this file references no app symbol, and importing it
// would couple a text guard to the app module building. Same shape as `NoDoorlessStudioViewsTests`
// and `ContentPipelineClaimsTests`.

import Foundation
import XCTest

final class LoudnessReadoutMeasurementPointTests: XCTestCase {

    private static let grid   = "Sources/Echoelmusic/Studio/MasterLoudnessGrid.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let target = "Sources/Echoelmusic/Studio/LoudnessTarget.swift"

    /// TRUE once `AudioEngine` publishes a loudness measured AFTER the master chain. Until
    /// then every number this grid shows is the chain's input, and no target verdict on it
    /// can be honest. See the ⛔ block above for why this is not a question about the tap.
    private func hasPostChainMeasurement() throws -> Bool {
        try source(Self.engine).contains("masterOutputLUFS")
    }

    func testATargetVerdictIsNotRenderedFromThePreChainSignal() throws {
        let code = try source(Self.grid)
        // Receiver included on purpose — the deletion tombstone in that file names the two
        // functions as `LoudnessTarget.compliance` (capital T), and a bare `compliance(`
        // would match the prose that explains why they are gone.
        let judges = code.contains("target.compliance(") || code.contains("target.truePeakExceeds(")
        let postChain = try hasPostChainMeasurement()

        XCTAssertFalse(!postChain && judges, """
            The loudness readout is colouring its numbers against the delivery target while \
            `AudioEngine` still has no post-chain measurement — so the verdict is computed \
            on the master chain's INPUT.
            That verdict reports the deviation the chain is about to REMOVE: `AutoMixChain` \
            reads the same pre-chain tap and applies `target − reading` (±6 dB), so a mix \
            painted "too quiet" is exactly the one the auto-gain lifts ONTO target, and the \
            true peak is judged before the limiter that catches it.
            Publish the post-chain reading first (#316b, symbol containing `masterOutputLUFS`), \
            or leave the numbers uncoloured as #316 left them.
            """)
    }

    /// The verdict is not the only way to paint a lie. `readout`'s `color:` seam is kept
    /// deliberately, so this pins that NOTHING hand-rolls a threshold into it either — an
    /// inline `masterLUFSIntegrated > -13 ? danger : text` would pass the token test above
    /// while re-introducing exactly what #316 removed.
    func testEveryReadoutStaysNeutralUntilTheMeasurementMoves() throws {
        // Hoisted rather than written `try !hasPostChainMeasurement()`: `try` in front of a
        // prefix operator is the kind of parse this bundle cannot afford to get wrong — it
        // is the only gate that compiles these files, and a red one costs a whole cycle.
        let postChain = try hasPostChainMeasurement()
        guard !postChain else { return }   // silent by design once the measurement is correct
        // `.map(String.init)` before filtering: `Substring.contains(_: StringProtocol)` and
        // `trimmingCharacters` both resolve through Foundation, and this bundle is the ONLY
        // gate that compiles these files — a plain `String` costs nothing and removes the
        // overload question entirely.
        let calls = try source(Self.grid)
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("readout(\"") }

        XCTAssertFalse(calls.isEmpty, "no `readout(\"…\")` call found — did the grid change shape?")
        for call in calls {
            XCTAssertTrue(call.contains("EchoelTheme.text)"), """
                A loudness readout is painted with something other than `EchoelTheme.text` \
                while the measurement is still pre-chain: \(call.trimmingCharacters(in: .whitespaces))
                Any colour here is a verdict, whether it comes from `LoudnessTarget` or from \
                an inline threshold. Neutral until #316b moves the measurement point.
                """)
        }
    }

    func testThePreChainMeasurementPointIsStatedOnScreen() throws {
        let code = try source(Self.grid)
        // Anchored to the RENDERED string, not the bare phrase. A bare `contains` would be
        // satisfied by any future tombstone comment mentioning "before the master chain" —
        // and in a repo where every deletion leaves a tombstone, that is close to inevitable.
        // The caption could then be deleted with the guard still green.
        let discloses = code.contains("Text(\"Measured before the master chain")
        let postChain = try hasPostChainMeasurement()

        XCTAssertFalse(!postChain && !discloses, """
            The numbers are still measured at the master chain's input, but nothing on screen \
            says so any more.
            Without that line the four readouts read as the loudness of what leaves the \
            device — the exact claim the file header carried, and that was false, until #316. \
            If the caption was reworded, update the token in this test in the SAME commit; \
            once a post-chain measurement exists this guard falls silent on its own.
            """)
    }

    /// ⭐ THE INVARIANT FOR THE OTHER SIDE OF #316b, added the moment the measurement moved.
    ///
    /// Three of the tests above are written to fall silent once a post-chain measurement
    /// exists — which is now. Left at that, this file would still be in the bundle, still
    /// green, and checking nothing about the state it just entered: exactly the "a silent
    /// guard is indistinguishable from a passing one" failure the `doctor` skill exists for.
    /// The pre-chain guards STAY (they re-arm the moment someone reverts the tap), and this
    /// one takes over the live half.
    ///
    /// The claim is now the mirror image: the screen must not still say "before", and must
    /// say where the numbers actually come from. A caption is the only thing standing
    /// between four bare numbers and a reader assuming they describe the output — which was
    /// true before #316b and would be false in the other direction if the caption rotted.
    func testTheOnScreenPointMatchesWhereTheTapActuallySits() throws {
        guard try hasPostChainMeasurement() else { return }   // pre-chain guards own that case
        let code = try source(Self.grid)

        XCTAssertFalse(code.contains("Text(\"Measured before the master chain"), """
            `AudioEngine` publishes a post-chain measurement (#316b moved the tap to \
            `AutoMixChain.chainOutputNode`), but the caption still tells the reader the \
            numbers are taken BEFORE the chain. That is now false in the opposite direction \
            — it understates a correct readout instead of overstating a wrong one, which is \
            no better: it invites someone to "fix" the measurement point a second time.
            """)
        XCTAssertTrue(code.contains("Text(\"The four numbers are measured at the output of the master chain"), """
            The post-chain measurement exists but the grid no longer states its measurement \
            point on screen. Four bare LUFS/dBTP numbers read as the loudness of what leaves \
            the device whether or not that is what they are — #316 put the sentence there for \
            exactly that reason and #316b changed which sentence is true, not whether one is \
            needed. If the wording was changed, update this token in the SAME commit.
            The token says "The four numbers" on purpose: an earlier draft opened with a bare \
            "Measured at the output of the master chain", which read as a claim about the \
            whole panel and was wrong about the two level bars, which are pre-chain.
            """)
    }

    /// The trim is the one gain downstream of the tap, so the readouts have to add it back.
    /// Pinning that it is DERIVED, not typed twice: two hand-written 0.89s that must agree
    /// is the same shape as the two one-pole literals #332 spent a slice merging, and the
    /// first version of `outputTrimDb` had it — caught while writing, pinned so it cannot
    /// come back.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST PINNED ONLY ONE OF THE TWO ENDS, while its own
    /// failure message named both. It asserted the dB derivation and said nothing about the
    /// NODE GAIN — so re-typing `mainMixerNode.outputVolume = 0.89` produced exactly the
    /// drift the message describes, with the test green. Both ends are asserted now.
    func testTheOutputTrimIsOneConstant() throws {
        let code = try source(Self.engine)
        XCTAssertTrue(code.contains("= 20 * log10f(outputTrimLinear)"), """
            `outputTrimDb` no longer derives from `outputTrimLinear`. If it was re-typed as \
            a literal (`20 * log10f(0.89)`), the node gain and the meter offset can now drift \
            apart silently — the readout would claim a trim the output does not apply, or \
            miss one it does. Derive it.
            Anchored on the `= ` so a tombstone comment quoting the old expression cannot \
            satisfy this on its own; in a repo where every deletion leaves a tombstone, a \
            bare code fragment is close to guaranteed to reappear as prose.
            """)
        XCTAssertTrue(code.contains("mainMixerNode.outputVolume = AudioEngine.outputTrimLinear"), """
            The output trim is applied to `mainMixerNode` as a LITERAL again instead of from \
            `outputTrimLinear`. That is the other end of the same pair: the readouts add \
            `outputTrimDb` back on the assumption that this exact gain is what the graph \
            applies. Two hand-written 0.89s that must agree is the defect, whichever side \
            gets re-typed.
            """)
    }

    /// ⭐ THE HOLE THE #316b REVIEW FOUND IN THIS FILE'S CENTRAL PREDICATE.
    ///
    /// `hasPostChainMeasurement()` keys on a SYMBOL NAME, and #316b's commit message claimed
    /// the pre-chain guards "re-sharpen themselves the moment someone turns the tap back".
    /// They do not: reverting `installMeterTap` to `masterMixer` leaves `masterOutputLUFS`
    /// in the file (in code AND in prose), so the predicate stays true, all three fall
    /// silent, and nothing goes red. The names and the tap could drift apart completely.
    ///
    /// This asserts the tap's NODE directly. That only became safe once #316b chose MOVE
    /// over DUPLICATE — the objection in this file's ⛔ header (a `masterMixer.installTap(`
    /// check fires red on the correct fix) killed the first draft of exactly such a guard.
    /// Note it is still a live objection for the naive form: `masterMixer.installTap(` IS
    /// present today, deliberately, for the cheap pre-chain LEVEL tap. So the assertion is
    /// about which node the DETAILED meter reads, not about which nodes are tapped at all.
    func testTheDetailedMeterIsInstalledOnTheChainOutput() throws {
        let code = try source(Self.engine)
        XCTAssertTrue(code.contains("autoMixChain.chainOutputNode ?? masterMixer"), """
            `installMeterTap()` no longer resolves its node through \
            `AutoMixChain.chainOutputNode`, so the EBU R128 readout is measuring the master \
            chain's INPUT again while `AudioEngine` still publishes it under `masterOutput…` \
            names and still adds the −1 dB trim. That combination is worse than the state \
            #316 disclosed: the numbers would be pre-chain AND labelled as output.
            """)
        XCTAssertTrue(code.contains("meterNode.installTap("), """
            The detailed meter tap is no longer installed on `meterNode`. Whatever it is \
            installed on now, the pairing this file exists for — screen caption, property \
            names, measurement point — is no longer decidable from here.
            """)
    }

    /// The other half of that split, and the one with an audio consequence rather than a
    /// documentation one: the cheap RMS pair must STAY on `masterMixer`, because
    /// `masterLevel` is what `AutoMixChain.connectMeter` measures and the auto-gain acts
    /// upstream of the moved meter. #316b briefly moved it and closed that loop — with a
    /// proportional control law and no integrator, the stage then settles at half its
    /// computed correction and never reaches the target anywhere inside its ±6 dB window.
    func testTheLevelMetersStayUpstreamOfTheAutoGain() throws {
        let code = try source(Self.engine)
        XCTAssertTrue(code.contains("masterMixer.installTap("), """
            The pre-chain level tap is gone. `masterLevel` feeds \
            `autoMixChain.connectMeter` (the auto-gain's measurement) and the auto-gain's \
            `gainNode` sits UPSTREAM of the R128 meter's node — so a `masterLevel` written \
            from the moved tap makes that stage measure its own output. `steadyGainDB` is \
            proportional, not integrating, so the error never closes: it delivers half.
            Whatever replaced this, it must feed the auto-gain from BEFORE the chain.
            """)
        XCTAssertTrue(code.contains("levelsComeFromPreChainTap"), """
            The flag that keeps the level meters and the R128 meter on different nodes is \
            gone. Both readings then come from one tap again — which is only correct in the \
            chain-not-installed fallback, where a single node cannot host two taps anyway.
            """)
    }

    /// The verdict functions now have ZERO callers in `Sources/`. That is deliberate, not
    /// dead weight: they are the ready-made, already-tested verdict for whoever moves the
    /// tap. A tidy-up that deletes them turns a one-line restoration into a re-derivation.
    func testTheVerdictFunctionsSurviveTheirCallerlessPeriod() throws {
        let code = try source(Self.target)
        XCTAssertTrue(code.contains("func compliance(integratedLUFS"), """
            `LoudnessTarget.compliance(integratedLUFS:floor:)` is gone. It was kept without \
            callers on purpose (#316) so the measurement-point fix can re-colour the readout \
            without re-deriving the tolerance rules. `LoudnessTargetTests` covers it.
            """)
        XCTAssertTrue(code.contains("func truePeakExceeds("), """
            `LoudnessTarget.truePeakExceeds(_:floor:)` is gone — same reason as \
            `compliance` above. Restore it rather than re-implementing the ceiling check.
            """)
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
