// SleepingChainDoesNotHoardAudioTests.swift
// Echoel — falling asleep empties the signal path, so nothing stale can burst later. BLOCKING. #389.
//
// THE DEFECT, and it is the house's OWN rule applied one level up. `EchoelFXChain` states the
// SWITCH-CRACKLE RULE at the top of its own file (founder: "knistert beim Umschalten von
// Dingen"): a bypassed stage is skipped entirely, so its delay lines FREEZE holding old audio,
// and re-enabling it later would burst that stale audio into the mix — therefore every enable
// flag resets its stage on the rising edge. `PolySynthVoice`'s 2.5 s idle skip does exactly the
// same thing to the WHOLE chain and did NOT reset anything. `EchoelFXChain.noteRenderSkipped`'s
// own SCOPE paragraph said so in as many words and left it for its own slice: "The time-based
// stages (delay, reverb, tape) also freeze across a skip and can burst stale audio on resume …
// This hook is where such a fix would attach."
//
// ⭐ WHY THE REVERB TANK IS THE REAL PATH AND THE DELAY IS NOT — this was measured before it was
// built, and it corrects the task's own title. The idle skip engages only after 2.5 s of output
// below 1e-5, and:
//   • DELAY — already safe, and the existing argument in `PolySynthVoice` holds: the window
//     (2.5 s) is longer than `EchoelDelay`'s maximum gap (2.0 s), so if no repeat crossed the
//     floor within one full gap, every later repeat is peak × feedback (≤0.95) × damping,
//     i.e. strictly quieter.
//   • REVERB TAIL — also safe: a reverb tail decays MONOTONICALLY, so while it is audible the
//     output is above the floor and the counter resets every block. No tail is ever cut, however
//     long. ⛔ The first draft justified this with "`rt60` clamped to [0.1 … 30] s" — read off
//     `EchoelFDNReverb`, which has **ZERO instantiations in `Sources/`** (`grep -rn
//     "EchoelFDNReverb("` returns nothing; it is test-only DSP, like `EchoelModalBank` since
//     #167). The chain's reverb is `EchoelReverb` — Freeverb combs, decay knob `roomSize`. The
//     conclusion was right and its evidence came from a file with no production path, which is
//     the failure this repo pays for most often. The monotone-decay argument needs no number.
//   • REVERB TANK AT LOW MIX — the actual hole. The skip measures the chain OUTPUT. With
//     `reverb.mix` near zero the output can sit under the floor while the tank still holds
//     energy. Sleep then freezes that energy while the 30 Hz bio driver keeps writing
//     parameters; the next time something raises the mix, seconds-old audio walks out.
//     #386 is what made this reachable from the normal case — before it, nothing moved the
//     mix during ordinary play.
//
// WHAT SLEEPING MEANS, stated once so the fix is not mistaken for data loss: the chain's own
// `reset()` doc defines reset as "the signal path is empty". Entering sleep is the moment that
// becomes TRUE — everything the reset discards is, by the proof above, already inaudible at the
// current settings. The only way to ever hear it again is a later parameter change, and hearing
// it then means hearing 2.5-second-old audio. That is the burst, not the music.
//
// ⭐ A REAL BEHAVIOURAL TEST, not a source scan — unusual for this bundle and worth it here.
// `EchoelFXChain` is Foundation-only and `@testable import` reaches it, so this drives actual
// float buffers through the actual stages. It fails on the real symptom (audible output from a
// chain that was fed nothing), not on the presence of a line of code.
//
// NEEDS-FOUNDER-VERIFY: play until the take goes fully silent, wait ~3 s, then raise Reverb mix
// (or let a bio route raise it). No echo or wash of the previous take may appear — only silence
// until the next note.

import Foundation
import XCTest
@testable import Echoelmusic

final class SleepingChainDoesNotHoardAudioTests: XCTestCase {

    private let sampleRate: Float = 48000
    private let block = 512

    // MARK: - The defect, reproduced end to end

    /// ⭐ THE ONE THAT WOULD HAVE CAUGHT IT. Charge the tank at a mix low enough that the chain
    /// OUTPUT stays under the idle floor — the exact condition under which the voice decides to
    /// sleep — then sleep, then raise the mix the way a bio route does. A chain that hoarded the
    /// energy answers with audio it was never fed.
    func testRaisingTheMixAfterSleepCannotResurrectTheOldTake() {
        let chain = makeChain(reverbMix: 0.0008)

        // Charge: a loud burst goes in, but at ~0 mix almost nothing comes out.
        var quietestOutput: Float = 0
        for _ in 0..<24 {
            var l = burst(), r = burst()
            chain.processBuffer(left: &l, right: &r, frameCount: block)
            quietestOutput = max(quietestOutput, peak(l, r))
        }
        XCTAssertGreaterThan(quietestOutput, 0, """
            the charging phase produced literal digital zero, so this test never set up the \
            condition it claims to test. Check that the reverb is enabled and being fed.
            """)

        // Sleep. This is the transition `PolySynthVoice` performs when the idle counter expires.
        chain.noteRenderSleeping()

        // Resume the way the bio driver does: the mix comes up, and NOTHING is fed in.
        chain.reverb.mix = 0.9
        var maxAfter: Float = 0
        for _ in 0..<24 {
            var l = [Float](repeating: 0, count: block)
            var r = [Float](repeating: 0, count: block)
            chain.processBuffer(left: &l, right: &r, frameCount: block)
            maxAfter = max(maxAfter, peak(l, r))
        }

        XCTAssertLessThan(maxAfter, 1e-6, """
            a chain that was fed nothing produced \(maxAfter) after waking (#389).

            That is the previous take's energy, held in the reverb tank across a sleep and let \
            out by a mix change — the stale burst the SWITCH-CRACKLE RULE at the top of \
            EchoelFXChain.swift exists to prevent, arriving through the idle skip instead of \
            through a bypass toggle. Falling asleep must empty the signal path.
            """)
    }

    /// The same hole one stage earlier, because delay and reverb are reached by different
    /// parameters and a fix that only drained one would still pass the test above.
    func testTheDelayLineIsEmptyAfterSleepToo() {
        let chain = makeChain(reverbMix: 0)
        chain.delayEnabled = true
        chain.delay.timeSeconds = 0.75
        chain.delay.feedback = 0.9
        chain.delay.mix = 0.0008

        for _ in 0..<24 {
            var l = burst(), r = burst()
            chain.processBuffer(left: &l, right: &r, frameCount: block)
        }
        chain.noteRenderSleeping()
        chain.delay.mix = 0.9

        var maxAfter: Float = 0
        for _ in 0..<40 {          // > 0.75 s at 512/48k, so a held repeat would have to appear
            var l = [Float](repeating: 0, count: block)
            var r = [Float](repeating: 0, count: block)
            chain.processBuffer(left: &l, right: &r, frameCount: block)
            maxAfter = max(maxAfter, peak(l, r))
        }
        XCTAssertLessThan(maxAfter, 1e-6, """
            the delay line still held audio across a sleep and released it when the mix rose \
            (\(maxAfter)) — same defect as the reverb tank, different stage (#389).
            """)
    }

    // MARK: - The fix must not become a mute

    /// ⛔ THE FAILURE MODE OF THE FIX ITSELF, and the reason this test exists next to the two
    /// above: "drain everything on sleep" is one careless edit away from "drain everything on
    /// every skipped block", which would silence the instrument's first note after any pause.
    /// Sleeping empties the path; it must not disable it.
    func testTheChainStillPassesAudioAfterWaking() {
        let chain = makeChain(reverbMix: 0.25)
        chain.noteRenderSleeping()

        var l = burst(), r = burst()
        chain.processBuffer(left: &l, right: &r, frameCount: block)
        XCTAssertGreaterThan(peak(l, r), 0.01, """
            the chain produced (near) silence for a full-scale burst on the block after waking \
            (#389). Draining on sleep must leave the chain able to process — if this fails, the \
            drain is being applied to every skipped block, or a stage was left disabled.
            """)
    }

    /// The per-block hook and the once-per-sleep hook are different things and must stay so.
    /// `noteRenderSkipped` runs thousands of times while asleep; if IT drained, the cost would
    /// be paid every block for nothing, and the two would be impossible to tell apart later.
    func testThePerBlockSkipHookDoesNotDrain() {
        let chain = makeChain(reverbMix: 0.0008)
        for _ in 0..<24 {
            var l = burst(), r = burst()
            chain.processBuffer(left: &l, right: &r, frameCount: block)
        }
        chain.noteRenderSkipped()      // the per-block hook — must NOT empty the tank
        chain.reverb.mix = 0.9

        var maxAfter: Float = 0
        for _ in 0..<8 {
            var l = [Float](repeating: 0, count: block)
            var r = [Float](repeating: 0, count: block)
            chain.processBuffer(left: &l, right: &r, frameCount: block)
            maxAfter = max(maxAfter, peak(l, r))
        }
        XCTAssertGreaterThan(maxAfter, 1e-6, """
            `noteRenderSkipped` now drains the chain (#389). It is called on EVERY skipped \
            block, so draining there pays a full buffer clear thousands of times per sleep and \
            erases the distinction between "this block was skipped" and "the voice went to \
            sleep". The drain belongs in `noteRenderSleeping`, which fires once.
            """)
    }

    // MARK: - The caller

    /// ⛔ SOURCE-SCANNED ON PURPOSE, and only this one assertion is. The transition lives inside
    /// `PolySynthVoice`'s render block behind `nonisolated(unsafe)` audio-thread state that no
    /// test can drive without a running engine — so the behavioural tests above prove the chain
    /// keeps its half of the contract, and this proves the voice actually calls it. Without it,
    /// all four pass while nothing in the app ever sleeps cleanly.
    func testTheVoiceDrainsTheChainWhenItFallsAsleep() throws {
        let voice = try codeLines("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        guard let idx = voice.firstIndex(where: {
            $0.contains("idleQuietFrames >= Self.idleFrameThreshold")
        }) else {
            return XCTFail("""
                the idle-sleep transition is gone from `PolySynthVoice` — \
                `idleQuietFrames >= Self.idleFrameThreshold` no longer appears. If the skip was \
                removed, remove this guard with it; if it moved, move this guard too.
                """)
        }
        // The drain must sit in the transition itself, not somewhere else in the file that
        // happens to mention it: the whole point is "once, at the moment of falling asleep".
        let window = voice[idx..<min(idx + 4, voice.endIndex)]
        XCTAssertTrue(window.contains(where: { $0.contains("noteRenderSleeping()") }), """
            `PolySynthVoice` no longer drains the FX chain where it sets `renderIdle = true` \
            (#389).

            The chain-side tests in this file would all still pass — they drive the chain \
            directly. The app would go back to freezing the reverb tank and the delay line for \
            the whole sleep, and to letting a later mix change walk seconds-old audio out.
            transition: \(window.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    // MARK: - Helpers

    private func makeChain(reverbMix: Float) -> EchoelFXChain {
        let chain = EchoelFXChain(sampleRate: sampleRate)
        chain.reverbEnabled = true
        chain.reverb.mix = reverbMix
        // `roomSize`, NOT `decayTime` — the chain's reverb is `EchoelReverb` (Freeverb combs,
        // whose decay knob is `roomSize`), not `EchoelFDNReverb` (which is the one with
        // `decayTime` clamped to [0.1 … 30] s). The first draft of this file wrote `decayTime`
        // here, having read the tail bound off the WRONG reverb while diagnosing #389. With no
        // local compiler that is a CI-only failure, so it is recorded rather than quietly fixed.
        chain.reverb.roomSize = 0.9
        // Off, so the assertions measure the time-based stages and not a limiter's recovery or
        // a saturator's colour. `limiterEnabled` defaults to TRUE — leaving it on would clamp
        // the burst and blunt the very peak these tests compare against.
        chain.limiterEnabled = false
        chain.compressorEnabled = false
        return chain
    }

    /// A full-scale-ish noise burst. Deterministic (a fixed recurrence, no `Random`) so a
    /// failure reproduces exactly — the house rule for anything that can end up in CI.
    private func burst() -> [Float] {
        var out = [Float](repeating: 0, count: block)
        var state: UInt32 = 0x9E3779B9
        for i in 0..<block {
            state = state &* 1_664_525 &+ 1_013_904_223
            out[i] = Float(Int32(bitPattern: state)) / Float(Int32.max) * 0.5
        }
        return out
    }

    private func peak(_ l: [Float], _ r: [Float]) -> Float {
        var p: Float = 0
        for v in l where abs(v) > p { p = abs(v) }
        for v in r where abs(v) > p { p = abs(v) }
        return p
    }

    private func codeLines(_ path: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — the caller assertion inspects \
                source text, so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
