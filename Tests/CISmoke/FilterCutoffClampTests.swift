// FilterCutoffClampTests.swift
// Echoel — #294. Blocking bundle.
//
// ⭐ THE ONE PROPERTY THIS FILE EXISTS FOR: `EchoelDDSP.filterCutoff` is a PERSISTENT one-pole
// accumulator (`filterCutoff = filterCutoff * 0.97 + targetCutoff * 0.03`, ~10×/s while bio
// runs) that was fed unclamped. One non-finite value and it stays non-finite FOREVER —
// `inf * 0.97` is still inf, `NaN * 0.97` is still NaN — with no recovery short of re-applying
// a patch. The fix makes it self-healing; these tests stop a later "simplification" from
// quietly taking that away.
//
// ⛔ TWO CLAIMS IN THE FIRST VERSION OF THIS HEADER WERE FALSE, both caught by the mandatory
// reviewers within the hour, and both are the kind that survive because nothing executes them:
//   1. "the only bio mapping whose result feeds itself" — `_smoothedBrightness` and
//      `_smoothedAmplitude` are self-feeding one-poles in the same function. The load-bearing
//      distinction is NOT self-feeding: it is that `filterCutoff` is a `public var` anyone can
//      write, while those two are `private` and fed only from already-clamped locals. Get that
//      wrong and a later session adding a PUBLIC smoothed parameter reads this as "safe
//      because it is not the cutoff".
//   2. "the #22/#29 permanent-silence class". The accumulator half was true, the CONSEQUENCE
//      was not: the render clamp intercepted the value every sample, so pre-fix a NaN cutoff
//      pinned the filter at 20 Hz (inaudible, but a dark filter, recoverable) and `+inf`
//      opened it fully — audible and benign. The case the old text named as permanent silence
//      was never silent. The fix prevents a MILDER failure than advertised.
//
// ⚠️ NO DEMONSTRATED PRODUCER, AND SAYING SO IS PART OF THE FINDING. Nothing shipped writes a
// non-finite `SynthPatch.filterCutoff`: the Sound panel writes through an `EchoelValueField`
// bounded to 20…18000, `SoundPrompt` sanitises, and a JSON decode of a non-conforming float
// throws rather than yielding NaN. So this is hardening, with the same standing as #92 (which
// sanitised the bio INPUTS of the same function, also without a demonstrated producer). It is
// NOT a tuning change and must never be reported as one.
//
// ⛔ AND THE HEADER LIED ABOUT THE FILE ITSELF. It said "the assertions below use the anchor and
// `apply(to:)` rather than poking `filterCutoff`" — and the very next test pokes `filterCutoff`
// directly, while `ResolvedPatch` appeared nowhere in the file. The claim that "both doors are
// exercised" was true only by analogy. `testApplyDoorCannotLeaveAPoisonedAccumulator` below now
// goes through the REAL production writer, so the sentence and the code agree.
//
// The two doors are real: the anchor, and `ResolvedPatch.apply(to:)`, which writes the raw patch
// cutoff straight into the accumulator one line before it sets the anchor. Clamping
// `targetCutoff` instead of the assignment would have left the second wide open.

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

    /// The `apply(to:)` door, through the ACTUAL production writer rather than by analogy — the
    /// header used to claim this existed before it did.
    func testApplyDoorCannotLeaveAPoisonedAccumulator() {
        var poisoned = SynthPatch.factory[0]
        poisoned.filterCutoff = .nan
        let synth = EchoelDDSP()
        poisoned.resolved().apply(to: synth)
        runBio(synth, frames: 1)
        XCTAssertTrue(synth.filterCutoff.isFinite, """
        a patch carrying a NaN cutoff went through `ResolvedPatch.apply(to:)` and left the \
        accumulator at \(synth.filterCutoff) after a bio frame. `apply(to:)` writes the raw \
        value into `filterCutoff` one line before it sets the anchor, so a clamp on \
        `targetCutoff` alone would not catch this.
        """)
    }

    /// The second door: a non-finite ANCHOR, i.e. the value the bio target is built from.
    ///
    /// ⚠️ THIS ASSERTS `isFinite` AND NOT MORE, ON PURPOSE, AND THE LIMIT IS WORTH STATING: a
    /// `+inf` anchor passes the `> 0` gate, so `targetCutoff` is `inf` on every frame and the
    /// accumulator pins at exactly 18000 — finite, in range, and stuck at maximum brightness
    /// with no recovery. That is bounded, not healed. Asserting recovery here would assert
    /// something the code does not do; the honest place for that is the comment, and it is
    /// there.
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
    /// ⛔ THE FIRST VERSION MULTIPLIED BY 1.3 AND WOULD HAVE REDDENED 12 % TOO LATE — in the one
    /// test whose stated job is to redden BEFORE the clamp starts shaping. There is a second
    /// live multiplier ahead of the bio one: `RoleRhythm.TimbreTrim.trimmed` scales the cutoff
    /// by up to 1.12 (`.driving`) on `applyTakeSound`, i.e. on every Generate and every preset
    /// recall, and THAT trimmed value is what becomes `bioBaseFilterCutoff`. The real chain is
    /// 1.12 × 1.3 = 1.456, so the clamp starts biting at 18000 / 1.456 ≈ 12.4 kHz, not the
    /// ~13.8 kHz the comment claimed. A 13 kHz preset would already have been clamped in the
    /// app while this test stayed green.
    ///
    /// ⚠️ It also silently excluded `PatchLibrary`, which holds the highest cutoff in the repo
    /// (8000 Hz, "Crystal") — above the 6500 Hz I called the maximum. It is doorless dead data
    /// today (`git grep PatchLibrary -- Sources` finds only its own file), so nothing shipped
    /// was mis-measured, but "any shipped patch" was the wrong claim and the blind spot was
    /// free to close.
    ///
    /// ⛔ AND IT HAPPENED AGAIN, in the shape the paragraph above was written to prevent. #349
    /// added a THIRD live multiplier at the same site: `weatherToned` composes a
    /// `WeatherMood.ToneTrim` into the very same `applyTakeSound` push, contributing up to
    /// ×1.36 (`maxToneCutoffDeviation`). It did not redden — 8000 × 1.456 = 11.6 kHz was far
    /// from the clamp — so nothing here failed; the number simply stopped describing the app.
    /// The lesson is that this constant is a MIRROR of the push chain in
    /// `EchoelStudioView.applyTakeSound`, and anything appended there belongs here in the same
    /// commit. Headroom is now ~2.2 kHz instead of ~6.4, which is the honest reason a fourth
    /// multiplier needs a decision rather than an edit.
    func testNoShippedPatchComesNearTheClamp() {
        /// `RoleRhythm` timbre trim (≤1.12) × `WeatherMood.ToneTrim` (≤1.36, #349)
        /// × the bio `cutoffFactor` rail (1.3). One mirror of `applyTakeSound`'s push chain.
        let liveChain: Float = 1.12 * 1.36 * 1.3
        var worst: (label: String, hz: Float) = ("none", 0)
        for entry in shippedPatches {
            let peak = entry.patch.filterCutoff * liveChain
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

    /// Every `SynthPatch` compiled into the binary. `PatchLibrary` is included even though it is
    /// doorless dead data today (zero consumers outside its own file) — it holds the repo's
    /// highest cutoff, so leaving it out is how a preset drifts toward the ceiling unseen, and
    /// including it costs nothing. Saved `PatchStore` patches remain out of scope; they are not
    /// compiled in, and `PatchVibratoAnchorTests` carries the same caveat for the same reason.
    private var shippedPatches: [(label: String, patch: SynthPatch)] {
        SynthPatch.factory.map { (label: "factory “\($0.name)”", patch: $0) }
        + MusicStyle.offered.map { (label: "genre “\($0.rawValue)”", patch: $0.synthPatch) }
        + PatchLibrary.all.map { (label: "library “\($0.patch.name)”", patch: $0.patch) }
    }
}
