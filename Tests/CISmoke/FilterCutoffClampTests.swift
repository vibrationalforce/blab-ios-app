// FilterCutoffClampTests.swift
// Echoel — #294. Blocking bundle.
//
// ⭐ THE ONE PROPERTY THIS FILE EXISTS FOR: `EchoelDDSP.filterCutoff` is a PERSISTENT one-pole
// accumulator (`filterCutoff = filterCutoff * 0.97 + targetCutoff * 0.03`, ~10×/s while bio
// runs). It was the only bio mapping in `applyBioReactive` whose result feeds itself, and it was
// the only one whose value was not clamped. That combination is the #22/#29 permanent-silence
// class: one non-finite value and the accumulator is non-finite FOREVER — `inf * 0.97` is still
// inf, `NaN * 0.97` is still NaN — with no recovery short of re-applying a patch, and no error
// anywhere. The fix makes the accumulator self-healing; these tests are what stops a later
// "simplification" from quietly taking that away again.
//
// ⚠️ NO DEMONSTRATED PRODUCER, AND SAYING SO IS PART OF THE FINDING. Nothing shipped writes a
// non-finite `SynthPatch.filterCutoff`: the Sound panel writes through an `EchoelValueField`
// bounded to 20…18000, `SoundPrompt` sanitises, and a JSON decode of a non-conforming float
// throws rather than yielding NaN. So this is hardening, with the same standing as #92 (which
// sanitised the bio INPUTS of the same function, also without a demonstrated producer). It is
// NOT a tuning change and must never be reported as one.
//
// ⛔ WHY THE ASSERTIONS BELOW USE THE ANCHOR AND `apply(to:)` RATHER THAN POKING `filterCutoff`:
// the poison has two doors, and the first version of this fix only saw one. Clamping
// `targetCutoff` would leave the other wide open, because `ResolvedPatch.apply(to:)` writes the
// raw patch cutoff straight into the accumulator one line before it sets the anchor. Both doors
// are exercised here.

import Foundation
import XCTest
@testable import Echoelmusic

final class FilterCutoffClampTests: XCTestCase {

    private func runBio(_ synth: EchoelDDSP, frames: Int = 3, coherence: Float = 0.5) {
        for _ in 0..<frames {
            synth.applyBioReactive(coherence: coherence, hrvVariability: 0.5, heartRate: 0.5,
                                   breathPhase: 0.5, breathDepth: 0.5)
        }
    }

    // MARK: - The accumulator recovers

    /// ⭐ THE ONE THAT MATTERS. Poison the accumulator directly (the `apply(to:)` door) and give
    /// it one ordinary bio frame: it must be back in the audible domain.
    func testNonFiniteCutoffDoesNotPersistInTheAccumulator() {
        for poison in [Float.nan, Float.infinity, -Float.infinity] {
            let synth = EchoelDDSP()
            synth.filterCutoff = poison
            synth.bioBaseFilterCutoff = 2000
            runBio(synth, frames: 1)
            XCTAssertTrue(synth.filterCutoff.isFinite, """
            one bio frame after a \(poison) cutoff the accumulator is still \
            \(synth.filterCutoff). A one-pole that feeds itself never recovers on its own — this \
            is the permanent-silence shape (#22/#29), and it is silent in the logs too.
            """)
            XCTAssertTrue(EchoelDDSP.cutoffRange.contains(synth.filterCutoff), """
            recovered to \(synth.filterCutoff) Hz, outside the audible domain \
            \(EchoelDDSP.cutoffRange).
            """)
        }
    }

    /// The second door: a non-finite ANCHOR, i.e. the value the bio target is built from.
    func testNonFiniteAnchorCannotPoisonTheAccumulator() {
        for poison in [Float.nan, Float.infinity] {
            let synth = EchoelDDSP()
            synth.filterCutoff = 1200
            synth.bioBaseFilterCutoff = poison
            runBio(synth, frames: 5)
            XCTAssertTrue(synth.filterCutoff.isFinite, """
            a \(poison) `bioBaseFilterCutoff` drove the accumulator to \(synth.filterCutoff) \
            over five frames.
            """)
        }
    }

    // MARK: - Nothing that ships is touched

    /// ⚠️ THE HALF THAT IS EASY TO CLAIM AND EASY TO SKIP. A clamp added for a value nobody
    /// produces must be provably invisible to every value people DO produce.
    ///
    /// The headroom is measured, not assumed: the highest cutoff in any shipped patch is 6500 Hz
    /// and the largest bio factor is 1.3, so the target peaks at 8450 Hz — under half the
    /// ceiling. This test re-derives that from the patches themselves, so it reddens if a future
    /// preset is written close enough to the ceiling for the clamp to start biting silently.
    func testNoShippedPatchComesNearTheClamp() {
        var worst: (label: String, hz: Float) = ("none", 0)
        for entry in shippedPatches {
            let peak = entry.patch.filterCutoff * 1.3   // the largest `cutoffFactor`
            if peak > worst.hz { worst = (entry.label, peak) }
        }
        XCTAssertLessThan(worst.hz, EchoelDDSP.cutoffRange.upperBound, """
        \(worst.label) peaks at \(worst.hz) Hz under maximum coherence, at or above the clamp \
        ceiling \(EchoelDDSP.cutoffRange.upperBound). The clamp would start SHAPING that patch \
        instead of only catching impossible values — which is a tuning change wearing a \
        robustness fix's clothes. Either the preset is wrong or this clamp needs a decision, \
        but do not let it happen quietly.
        """)
    }

    /// Byte-identity where it counts: with a patch anchor set and a neutral reading, the
    /// accumulator must still converge on the patch's own cutoff.
    func testNeutralCoherenceStillConvergesOnThePatchCutoff() {
        let synth = EchoelDDSP()
        synth.filterCutoff = 2000
        synth.bioBaseFilterCutoff = 2000
        runBio(synth, frames: 20)
        XCTAssertEqual(synth.filterCutoff, 2000, accuracy: 1, """
        a resting-neutral reading settled at \(synth.filterCutoff) Hz instead of the patch's \
        2000 Hz — the anchor law (`coherence 0.5` → exactly the patch cutoff) broke.
        """)
    }

    // MARK: - The domain has four copies; they must agree

    /// ⛔ `SoundPrompt` holds its own `min(max(x, 20), 18_000)` and the Sound panel's knob holds
    /// its own `20...18000`. Folding those into `EchoelDDSP.cutoffRange` is a separate errand
    /// (a DSP constant should not be dragged into a UI range on a robustness slice), so this
    /// asserts the AGREEMENT behaviourally instead of leaving it to hope. If it reddens, the
    /// copies drifted — reconcile them, do not relax this.
    ///
    /// The sanitiser itself is `private`, which `@testable` does NOT reach; it runs
    /// unconditionally at the end of `apply(_:to:)`, so an EMPTY prompt is the honest way in —
    /// no vocabulary word matches, nothing is shaped, only the clamp executes.
    func testSoundPromptSanitiserAgreesWithTheEngineDomain() {
        var tooHigh = SynthPatch.factory[0]
        tooHigh.filterCutoff = 999_999
        var tooLow = SynthPatch.factory[0]
        tooLow.filterCutoff = -5

        XCTAssertEqual(SoundPrompt.apply("", to: tooHigh).filterCutoff,
                       EchoelDDSP.cutoffRange.upperBound, accuracy: 0.001, """
        `SoundPrompt` clamps the cutoff ceiling to a different value than the engine's \
        \(EchoelDDSP.cutoffRange.upperBound) Hz. Two copies of one domain have drifted.
        """)
        XCTAssertEqual(SoundPrompt.apply("", to: tooLow).filterCutoff,
                       EchoelDDSP.cutoffRange.lowerBound, accuracy: 0.001, """
        `SoundPrompt` clamps the cutoff floor to a different value than the engine's \
        \(EchoelDDSP.cutoffRange.lowerBound) Hz.
        """)
    }

    /// Every patch the app can hand the engine without the user typing anything. Saved
    /// `PatchStore` patches are deliberately out of scope — see `PatchVibratoAnchorTests`,
    /// which carries the same caveat for the same reason.
    private var shippedPatches: [(label: String, patch: SynthPatch)] {
        SynthPatch.factory.map { (label: "factory “\($0.name)”", patch: $0) }
        + MusicStyle.offered.map { (label: "genre “\($0.rawValue)”", patch: $0.synthPatch) }
    }
}
