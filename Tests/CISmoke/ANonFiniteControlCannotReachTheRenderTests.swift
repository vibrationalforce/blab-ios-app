// ANonFiniteControlCannotReachTheRenderTests.swift
// Echoel — a NaN at a control boundary must fail quiet, never trap or latch silence. #588.
//
// WHAT THIS GUARDS. Two control boundaries clamped with `Swift.min(Swift.max(v, lo), hi)` —
// the idiom this repo's own CLAUDE.md law names as NaN-transparent (`max(NaN, 0)` is NaN;
// argument order decides). Both sit on the render path:
//
//   · `EchoelDelay.processStereo` — `fb` multiplies the delay-line WRITE-BACK, so one NaN frame
//     poisons the entire line and only `reset()` heals it: the shipped permanent-silence class
//     (`AudioOutputGuard` mutes the output; the line stays poisoned underneath).
//   · `SamplerVoice`'s render state — `configurePlayback` stored the raw fraction, and the render
//     block computes `Int(startFrac * Float(count))`, where `Int(Float.nan)` is a Swift TRAP.
//     Not silence: a CRASH, on the audio thread.
//
// ⛔ AND THE DELAY ONE OUTLIVED ITS OWN DIAGNOSIS BY A MONTH, which is the part worth a guard.
// The `spread` line in the same function was switched to the NaN-safe `clamped(to:)` earlier,
// and the comment beside it said, in effect: the two lines above are still unsafe, but fixing
// them is "a separate change with its own audible surface". That second half was WRONG — for
// finite inputs `clamped(to:)` and `min(max(…))` are bit-identical, so there was no audible
// surface to fear — and the caution kept the more dangerous half of the defect (the write-back
// multiplier) alive while sitting three lines under its cure. A stale caution that overstates
// the cost of a repair is how a known hole outlives its diagnosis.
//
// Both are LATENT: no shipped producer emits NaN into these fields today. They are closed on
// engineering.md's boundary rule — non-finite at a DSP/bio boundary is an edge case, not an
// impossibility — and because both failure modes (permanent silence; an audio-thread trap) are
// the two worst outcomes this codebase knows.
//
// ⚠️ HONEST LIMITS.
//   · 5 tests, 7 assertion statements (`grep -c`, measured; two run inside loops — 512 and
//     2 000 executions). Tests 1–3 are END-TO-END BEHAVIOUR on the
//     shipped `EchoelDelay` — real instance, real frames, NaN in the control fields. Tests 4–5
//     are SOURCE-TEXT SCANS for `SamplerVoice`: driving its render block needs installed sample
//     slabs and trigger plumbing, which a smoke test should not fake; the setter is the ONLY
//     writer of all three fields, so pinning the setter's sanitization pins the render's input.
//   · NOT covered: a NaN in the AUDIO INPUT samples (as opposed to control fields) still writes
//     into the delay line — that is a different boundary with a real cost per frame, owned by
//     the sanitize-at-the-boundary pattern in `applyBioReactive`, not by this slice.
//
// ⭐ GRADING (§3). ONE finding, two boundaries, verified by transcription against the parent
// (the behavioural tests name no new symbol, so they COMPILE against the parent). On the parent,
// `fb = min(max(NaN, 0), 0.95)` is NaN, `wL = inL + lpL * NaN` is NaN from frame 0 — but the
// transcription showed the FIRST DRAFT of test 1 still green there, because at the default
// 0.375 s the read tap never reaches a poisoned sample inside a short run. The test as shipped
// shortens the time target and runs past the glide, and is a true REGRESSION red on the parent;
// test 2 is red there on frame 0 (`m` multiplies the output directly); test 4's needles are red
// by the old spelling. Test 3 got the same time-target treatment for the mirrored reason — at
// the default time a broken ceiling could not have grown inside the test window.
//   · 6 assertions are COUNTERWEIGHTS, green on both trees (#343): finite values still clamp to
//     the same bounds they always did — the repair's whole claim is "bit-identical for finite
//     inputs", and these are the assertions that would catch it being wrong.
//   · Stripper: **PROPHYLAKTISCH (0 of 4 scan needles flip)** — measured, and the measurement
//     overturned my own first draft of this line, which claimed TRAGEND "by construction"
//     because the #588 comment quotes the old idiom in prose. It quotes it as `min(max(…))`;
//     the negative needle searches for `Swift.min(Swift.max(` with the module prefix, and the
//     prose never spells the prefix. A grading claimed from construction instead of from the
//     drive is exactly the class this bundle's §3 exists to stop — same lesson, smaller stakes.

import Foundation
import XCTest
@testable import Echoelmusic

final class ANonFiniteControlCannotReachTheRenderTests: XCTestCase {

    // MARK: - END-TO-END: the delay's control fields

    /// THE REGRESSION. NaN feedback used to reach the write-back multiply; the line was then
    /// poisoned for good. Now it clamps to the range's lower bound and the output stays finite.
    ///
    /// ⛔ THE FIRST DRAFT OF THIS TEST COULD NOT FAIL ON THE PARENT (#367), and transcription is
    /// what caught it: it ran 512 frames at the DEFAULT 0.375 s delay — 18 000 samples — so the
    /// read tap never reached a poisoned position and the output stayed finite on BOTH trees.
    /// The write-back was NaN from frame 0 either way; the test just never looked where it
    /// landed. Hence: a short time target, run long enough for the 40 ms time-glide to settle
    /// AND for the tap to wrap into samples written during this test.
    func testNaNFeedbackProducesFiniteOutput() {
        let d = EchoelDelay(sampleRate: 48_000)
        d.feedback = .nan
        d.mix = 0.5
        d.timeSeconds = 0.005   // ~240 samples once the glide settles
        for i in 0..<20_000 {
            let x: Float = i % 7 == 0 ? 0.5 : 0.1
            let (l, r) = d.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite,
                          "Frame \(i): NaN in the feedback CONTROL reached the output — the "
                          + "write-back multiplier is the permanent-silence path.")
            if !(l.isFinite && r.isFinite) { return }   // one report, not twenty thousand
        }
    }

    /// Same boundary, second field. A NaN mix would put NaN directly on the output sum.
    func testNaNMixProducesFiniteOutput() {
        let d = EchoelDelay(sampleRate: 48_000)
        d.mix = .nan
        let (l, r) = d.processStereo(0.25, 0.25)
        XCTAssertTrue(l.isFinite && r.isFinite)
    }

    /// COUNTERWEIGHT — the repair's whole claim is "bit-identical for finite inputs". An
    /// out-of-range finite feedback must clamp to the same 0.95 ceiling as always (the ceiling
    /// is what keeps the feedback loop from self-oscillating past unity), and a legal value
    /// must pass through untouched. If either moved, this slice changed the sound.
    func testFiniteValuesStillClampToTheSameBounds() {
        let d = EchoelDelay(sampleRate: 48_000)
        d.feedback = 2.0   // must behave as 0.95, exactly as before #588
        d.mix = 1.0
        d.timeSeconds = 0.005   // same reasoning as the NaN test: the loop must actually
                                // recirculate many times inside the test, or a broken ceiling
                                // could never grow past the assertion and this counterweight
                                // would be green for a reason other than its named one (#367).
                                // ~240-sample period → hundreds of passes in 30 000 frames;
                                // 2× per pass would overflow to infinity almost immediately.
        var last: Float = 0
        for i in 0..<30_000 {
            let x: Float = i == 0 ? 1.0 : 0.0
            (last, _) = d.processStereo(x, x)
            XCTAssertTrue(last.isFinite && abs(last) < 8,
                          "Frame \(i): a >1 feedback escaped the 0.95 ceiling — the loop is "
                          + "running away, which means the finite path changed.")
            if !(last.isFinite && abs(last) < 8) { return }
        }
    }

    // MARK: - SOURCE-TEXT: the sampler's setter (the render's only writer)

    func testTheSamplerSetterSanitizesAllThreeFields() throws {
        let src = try source("Sources/Echoelmusic/Sequencer/SamplerVoice.swift")
        XCTAssertTrue(src.contains("let s = startFrac.clamped(to: 0...0.999)"),
                      "`Int(startFrac * Float(count))` in the render block is a Swift TRAP for "
                      + "NaN — the setter is the only writer, so it must sanitize.")
        XCTAssertTrue(src.contains("self.endFrac = endFrac.clamped(to: (s + 0.001)...1)"))
        XCTAssertTrue(src.contains("self.rate = rate.clamped(to: 0.25...4)"))
    }

    /// The retracted spelling must not return AT THIS SETTER. Scoped to the function body by
    /// anchoring on its signature (#408): `min(max(…))` elsewhere in the file is legal — only
    /// this setter feeds the `Int(…)` conversion.
    func testTheOldNaNTransparentSpellingIsGoneFromTheSetter() throws {
        let src = try source("Sources/Echoelmusic/Sequencer/SamplerVoice.swift")
        guard let fn = src.range(of:
            "func configurePlayback(startFrac: Float, endFrac: Float, reverse: Bool, rate: Float)")
        else { return XCTFail("The render-state setter was renamed — re-anchor (#454).") }
        let body = src[fn.upperBound...].prefix(700)
        XCTAssertFalse(body.contains("Swift.min(Swift.max("),
                       "The NaN-transparent clamp idiom is back in the one setter whose output "
                       + "reaches an `Int(_:)` conversion on the audio thread.")
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct BoundaryAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw BoundaryAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
