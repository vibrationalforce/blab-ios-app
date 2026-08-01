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
// pins that the three moving parts can never drift apart:
//
//   · verdicts back while the tap is still pre-chain → the false-verdict trap above returns
//   · tap moved but no verdicts → harmless, and deliberately NOT failed here (a correct
//     measurement with neutral colours is honest; see `testTheVerdictFunctionsSurvive`)
//   · tap still pre-chain but the on-screen disclosure gone → the numbers read as output
//
// ⚠️ WHAT THIS FILE CANNOT REACH, so the coverage is not overread: it cannot build the view,
// cannot prove the caption is visible, and cannot observe a single sample. It reads SOURCE
// TEXT for tokens. That is weaker than a behavioural test and stronger than nothing — and
// with no local toolchain and an audio graph that only exists on a device, it is the only
// level at which this pairing is checkable from here at all.

import Foundation
import XCTest
@testable import Echoelmusic

final class LoudnessReadoutMeasurementPointTests: XCTestCase {

    private static let grid   = "Sources/Echoelmusic/Studio/MasterLoudnessGrid.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let target = "Sources/Echoelmusic/Studio/LoudnessTarget.swift"

    /// TRUE while the meter tap still sits on the master chain's INPUT. The receiver is part
    /// of the token on purpose: `installTap(` alone would also match a tap on the node the
    /// fix is supposed to move to, so the guard would go quiet at exactly the moment it is
    /// meant to open the door.
    private func tapIsPreChain() throws -> Bool {
        try source(Self.engine).contains("masterMixer.installTap(")
    }

    func testATargetVerdictIsNotRenderedFromThePreChainSignal() throws {
        let code = try source(Self.grid)
        // Receiver included for the same reason as above — the deletion tombstone in that
        // file names the two functions, and a bare `compliance(` would match the prose that
        // explains why they are gone.
        let judges = code.contains("target.compliance(") || code.contains("target.truePeakExceeds(")
        let preChain = try tapIsPreChain()

        XCTAssertFalse(preChain && judges, """
            The loudness readout is colouring its numbers against the delivery target while \
            the meter tap is still on `masterMixer` — the master chain's INPUT.
            That verdict reports the deviation the chain is about to REMOVE: `AutoMixChain` \
            reads the same pre-chain signal and applies `target − reading` (±6 dB), so a mix \
            painted "too quiet" is exactly the one the auto-gain lifts ONTO target, and the \
            true peak is judged before the limiter that removes it.
            Either move the measurement to the chain's output first (#316b — note that this \
            one tap is also the sole writer of `_outputRing` and the host of the #193 timing \
            instrument, so re-pointing it moves two unrelated passengers), or leave the \
            numbers uncoloured as #316 left them.
            """)
    }

    func testThePreChainMeasurementPointIsStatedOnScreen() throws {
        let code = try source(Self.grid)
        let discloses = code.contains("before the master chain")

        XCTAssertFalse(try tapIsPreChain() && !discloses, """
            The meter tap is still on `masterMixer`, but nothing on screen says so any more.
            Without that line the four numbers read as the loudness of what leaves the \
            device, which is the exact claim the file header carried — and was false — until \
            #316. If the caption was reworded, update the token in this test in the SAME \
            commit; if the tap moved, this guard falls silent on its own.
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
