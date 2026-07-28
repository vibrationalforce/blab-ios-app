// FXChainParamGlideTests.swift
// Echoel — the tone filter must GLIDE for the body and SNAP for a document change (#138 Slice 2).
//
// THE DEFECT. No `EchoelFXChain` stage smoothed its own parameters. `FXBioModulator` writes
// the filter at 30 Hz off a bio carrier that itself only updates at ~10 Hz, so a body-driven
// sweep was a staircase with ten steps a second — and on a resonant filter every step is an
// audible edge rather than a sweep. A gain that moves in jumps IS the distortion.
//
// THE SHAPE OF THE FIX, and the half that is easy to get wrong: `EchoelFXChain.filterCutoff`
// is now the authoritative CONTROL-PLANE number and `filterL/filterR.cutoff` is an audio
// mirror stepped once per block. Gliding the SVF field in place would have been the obvious
// fix and would have broken three things at once — `FXBioModulator` captures its modulation
// BASE from that field, `FXPreset` saves from it, `EchoelFXView` seeds its fader from it. All
// three would have read a value caught mid-sweep. `testTarget_isNotDisturbedByTheGlide` is
// the falsifier for that, and it is the test that matters most here.
//
// Every expected value below is from a bit-accurate Float32 simulation of the shipped
// arithmetic, not from a tolerance picked to make the test pass.

import XCTest
@testable import Echoelmusic

final class FXChainParamGlideTests: XCTestCase {

    private let sr: Float = 48000

    /// Run `blocks` render blocks of `frames` samples through the chain (silence — the glide
    /// does not care what the audio is, and silence keeps every other stage out of it).
    private func run(_ fx: EchoelFXChain, blocks: Int, frames: Int) {
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        for _ in 0..<blocks { fx.processBuffer(left: &l, right: &r, frameCount: frames) }
    }

    // MARK: - It glides

    /// One block must MOVE the filter, not jump it. From 2000 toward 8000 at 256 frames the
    /// coefficient is 0.10117, so the first block lands at 2607.05 — measured, not estimated.
    func testCutoff_movesGradually_notInOneStep() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        run(fx, blocks: 1, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 2607.05, accuracy: 0.5,
                       "one block should advance ~10 % of the way, not arrive")
        XCTAssertEqual(fx.filterR.cutoff, fx.filterL.cutoff, "both channels move together")
    }

    /// And it must ARRIVE — exactly, not asymptotically near. `ParamGlide`'s settle threshold
    /// is relative (|target|·1e-5) precisely so a cutoff heading for a five-digit value does
    /// not park a few Hz short forever; an absolute-only epsilon is unreachable at that
    /// magnitude. 200 blocks ≈ 1.07 s, comfortably past the ~105 blocks it actually needs.
    func testCutoff_arrivesExactly() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        run(fx, blocks: 200, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 8000, "the glide must land on the target, not near it")
    }

    /// THE RATE LAW. The same wall-clock time must produce the same value whatever buffer the
    /// host hands us — otherwise the sound depends on the audio session's I/O size, which the
    /// user never chose. 20 blocks of 240 and 5 blocks of 960 are both exactly 0.1 s.
    ///
    /// This is the assertion a "cache the coefficient once at init" shortcut fails: it would
    /// keep the 240-frame coefficient and run the 960-frame chain four times too slow.
    /// Measured: 7187.98779296875 against 7187.98828125 — ONE Float32 step apart, not
    /// bit-identical (the earlier wording here overstated it). Different step counts on the
    /// same exponential cannot round identically in general; the hairline tolerance below is
    /// what the claim actually supports.
    func testGlide_isRateIndependent_acrossBufferSizes() {
        let small = EchoelFXChain(sampleRate: sr)
        small.filterEnabled = true; small.filterCutoff = 8000
        run(small, blocks: 20, frames: 240)

        let large = EchoelFXChain(sampleRate: sr)
        large.filterEnabled = true; large.filterCutoff = 8000
        run(large, blocks: 5, frames: 960)

        XCTAssertEqual(small.filterL.cutoff, 7187.988, accuracy: 0.05)
        XCTAssertEqual(large.filterL.cutoff, small.filterL.cutoff, accuracy: 0.05,
                       "0.1 s is 0.1 s — the host's buffer size must not change the glide")
    }

    /// Resonance rides the same coefficient. Pinned separately because a fix that only wired
    /// the cutoff would pass every test above and still leave the more audible parameter —
    /// resonance steps are what turn a sweep into a series of clicks — stepping.
    func testResonance_glidesToo() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterResonance = 0.9
        run(fx, blocks: 20, frames: 240)
        XCTAssertEqual(fx.filterL.resonance, 0.8188, accuracy: 0.001)
    }

    // MARK: - The control plane is undisturbed

    /// THE ONE THAT MATTERS MOST. The target must read back as the value that was SET, even
    /// while the audio is still on its way there. Three things depend on it: the bio driver
    /// captures its modulation base from the target, `FXPreset` saves it, and the UI fader
    /// seeds from it. If the glide wrote back into the target, the driver would latch a
    /// mid-sweep value and modulate around that random intermediate for the rest of the
    /// session — a slow, untraceable drift rather than an obvious break.
    func testTarget_isNotDisturbedByTheGlide() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        fx.filterResonance = 0.9
        run(fx, blocks: 1, frames: 256)                 // mid-glide on purpose
        XCTAssertEqual(fx.filterCutoff, 8000, "target is what the user set")
        XCTAssertEqual(fx.filterResonance, 0.9)
        XCTAssertNotEqual(fx.filterL.cutoff, 8000, "…and the audio is still on its way")
    }

    // MARK: - The three snap edges

    /// `setFilter` is the document-level change — preset load, genre switch, character stamp.
    /// Gliding there would be WRONG rather than merely slow: the new sound would arrive as a
    /// 50 ms sweep out of the old one, an artefact belonging to neither.
    func testSetFilter_snaps_soAPresetLoadDoesNotSweep() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.setFilter(mode: .lowpass, cutoff: 12000, resonance: 0.7)
        XCTAssertEqual(fx.filterL.cutoff, 12000, "a preset must land, not sweep in")
        XCTAssertEqual(fx.filterL.resonance, 0.7, accuracy: 1e-6)
        XCTAssertEqual(fx.filterCutoff, 12000, "and the target follows it")

        // A fence against the shape this USED to have — `setFilter` writing the SVF
        // directly next to the snap, so the assertions above passed with the snap deleted.
        // That direct write is gone (`setFilter` is now targets + mode + one snap), so the
        // lines above already fail without it; this block guards the regression back.
        run(fx, blocks: 1, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 12000, "and the next block must not undo it")
    }

    /// `reset()` means the signal path is empty — there is nothing to glide FROM, so a glide
    /// would sweep the first audio after the reset up out of a stale value. The TARGETS must
    /// survive: reset clears state, it does not change what the user set.
    func testReset_snapsTheMirror_andLeavesTheTargetAlone() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        run(fx, blocks: 1, frames: 256)                 // mid-glide
        fx.reset()
        XCTAssertEqual(fx.filterL.cutoff, 8000, "reset lands on the target")
        XCTAssertEqual(fx.filterCutoff, 8000, "and does not clear it")

        // Same fence as `testSetFilter_snaps…`, for the same historical shape.
        run(fx, blocks: 1, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 8000, "and the next block must not pull it back")
    }

    /// THE THIRD EDGE, and the one a reimplementation would miss. `FXBioModulator.enableStage`
    /// flips `filterEnabled` the first time a bio route contributes. Without a snap, the first
    /// audible thing after the body takes hold would be a sweep up from whatever the glide
    /// last held — the stale-value artefact, arriving exactly when the user is listening for
    /// the body to engage.
    func testEnablingTheFilter_snaps_noSweepFromAStaleValue() {
        let fx = EchoelFXChain(sampleRate: sr)
        // Deliberately NOT enabled while the target moves — the glide is idle and the mirror
        // holds the old value, which is exactly the stale state the snap has to absorb.
        fx.filterCutoff = 6000
        fx.filterResonance = 0.8
        XCTAssertEqual(fx.filterL.cutoff, 2000, "precondition: the mirror is still stale")

        fx.filterEnabled = true
        XCTAssertEqual(fx.filterL.cutoff, 6000, "enabling must land on the target immediately")
        XCTAssertEqual(fx.filterL.resonance, 0.8, accuracy: 1e-6)

        // And the very first block after enabling must not move it back off the target.
        run(fx, blocks: 1, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 6000)
    }

    /// THE FOURTH FREEZE PATH, which is not in `EchoelFXChain` at all and was missed twice:
    /// once by the first cut of this slice, and once by the fix for that miss, which only
    /// covered the `fxEnabled` gate. There are THREE ways a `PolySynthVoice` block returns
    /// without reaching this chain — `hasEverSounded`, the 2.5 s `renderIdle` skip, and the
    /// `fxEnabled` gate — and only the last has a control-plane setter; the other two are
    /// decided on the audio thread. So the resume snap is driven from the render side, by
    /// `noteRenderSkipped()`, and this is the contract that pins it.
    ///
    /// Scope note, stated rather than implied: this covers the CHAIN half. The four call
    /// sites in the two voices are compile-verified only — exercising them needs an
    /// `AudioBufferList` render harness this file does not have.
    func testAResumeAfterASkippedRenderLands_insteadOfSweepingFromAStaleValue() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        run(fx, blocks: 1, frames: 256)                 // sounding: mid-glide at 2607
        // …the voice goes idle. It keeps rendering silence and says so, but no block
        // reaches this chain, while the body keeps moving the target.
        for _ in 0..<10 { fx.noteRenderSkipped() }
        fx.filterCutoff = 400
        XCTAssertEqual(fx.filterL.cutoff, 2607.05, accuracy: 0.5,
                       "precondition: no blocks reach the chain, so the mirror is frozen")

        run(fx, blocks: 1, frames: 256)                 // the first block after the wake
        XCTAssertEqual(fx.filterL.cutoff, 400, "the wake block must land, not sweep 2607 → 400")
        XCTAssertEqual(fx.filterCutoff, 400, "and the target is untouched by its own snap")

        // The flag is CONSUMED, not sticky: the next block must glide again, or every
        // block after a single skip would jump and the whole slice would be undone.
        fx.filterCutoff = 8000
        run(fx, blocks: 1, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 1168.93, accuracy: 0.5,
                       "400 + 7600·0.1011747 — gliding again, not snapping")
    }

    /// A non-finite target must not reach the SVF through a SNAP either — `snapFilterToTarget`
    /// publishes `ParamGlide.value` (the last finite value) rather than the target field, so
    /// the guard in `ParamGlide.snap` cannot be walked around. Writing the raw target is the
    /// shape this used to have. Honest about the stake: `EchoelSVFilter` sanitizes a
    /// non-finite `cutoff` to 1 kHz in `updateCoefficients`, so the raw write was a filter
    /// silently parked at a substitute frequency, NOT the permanent silence an earlier
    /// version of this comment claimed. One guard at one choke point is still the right
    /// shape — but do not let a downstream guard be the only thing standing.
    func testSnapFilterToTarget_doesNotPublishANonFiniteTarget() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = .nan
        fx.snapFilterToTarget()
        XCTAssertTrue(fx.filterL.cutoff.isFinite, "a NaN must never reach the SVF via a snap")
        XCTAssertEqual(fx.filterL.cutoff, 2000, "it holds the last good value")
    }

    /// A BYPASSED filter must not be glided. This is not a micro-optimisation: the rising-edge
    /// snap in `filterEnabled`'s `willSet` justifies itself by "the audio thread is skipping
    /// this stage right now", and advancing the glide of a skipped stage would make that
    /// statement false. It also spends up to four `tanf` per block on silence.
    func testABypassedFilter_isNotGlided() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterCutoff = 8000                          // filterEnabled deliberately left false
        run(fx, blocks: 10, frames: 256)
        XCTAssertEqual(fx.filterL.cutoff, 2000, "nobody hears this stage — do not step it")
    }

    // MARK: - Degenerate inputs

    /// A zero-length block must not step the glide (and must not divide by zero deriving the
    /// step rate). `processBuffer` clamps `n` against the buffers, so an empty buffer reaches
    /// `advanceFilterGlide(frameCount: 0)`.
    func testZeroLengthBlock_doesNotAdvanceOrCrash() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        // TWO arrays, not one passed twice: `inout` forbids overlapping access, so
        // `processBuffer(left: &e, right: &e, …)` is a compile error, not a clever shortcut.
        var emptyL: [Float] = []
        var emptyR: [Float] = []
        fx.processBuffer(left: &emptyL, right: &emptyR, frameCount: 0)
        XCTAssertEqual(fx.filterL.cutoff, 2000, "no frames, no time, no movement")
    }

    /// A non-finite target must be HELD, not propagated: this feeds a recursive filter, where
    /// one NaN is permanent silence. `ParamGlide.advance` ignores it; the assertion here is
    /// that nothing on the chain's path defeats that.
    func testNonFiniteTarget_isHeld_notPropagatedIntoTheFilter() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = .nan
        run(fx, blocks: 4, frames: 256)
        XCTAssertTrue(fx.filterL.cutoff.isFinite, "a NaN target must never reach the SVF")
        XCTAssertEqual(fx.filterL.cutoff, 2000, "it holds the last good value")
    }

    /// The mono entry point is the bio synth's path (`BioReactiveSynthVoice`) — the voice the
    /// body drives most directly, so it is the one that must NOT be left un-glided.
    func testMonoEntryPoint_advancesTheGlideToo() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.filterEnabled = true
        fx.filterCutoff = 8000
        var buf = [Float](repeating: 0, count: 256)
        fx.processBufferMono(&buf, frameCount: 256)
        XCTAssertEqual(fx.filterL.cutoff, 2607.05, accuracy: 0.5)
    }
}
