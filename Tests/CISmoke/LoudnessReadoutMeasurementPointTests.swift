// LoudnessReadoutMeasurementPointTests.swift
// Echoel — #316. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE ONE PAIRING THIS FILE EXISTS FOR: `MasterLoudnessGrid` shows EBU R128 numbers that
// `AudioEngine.installMeterTap()` measures at `masterMixer` — the node `AutoMixChain.insert`
// takes as its `from:`. Everything the master chain does happens AFTER that point:
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
