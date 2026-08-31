// ATempoJumpDoesNotPullTheAccentForwardTests.swift
// Echoel — #933. Blocking bundle, because the other suite is compiled by NO gate (#208)
// and this pins a RENDER-BLOCK behaviour, the class of defect a source scan cannot see.
//
// §1 LIMIT: END-TO-END BEHAVIOUR, the strong kind. Every claim drives the real
// `renderOnAudioThread` through the `_testRender` seam and reads the samples it wrote.
// Nothing here is a text scan except claim 5, which is labelled as one.
//
// WHAT IT RECORDS. `MetronomeVoice`'s beat scheduler advanced its counter with a single
// `sampleCounter -= perBeat`. `perBeat` is re-derived on the MainActor in `bpm`'s `didSet`
// and lands BETWEEN buffers, so after a tempo JUMP the counter still carries what it had
// accumulated toward the OLD, longer beat. One subtraction leaves it a whole beat or more
// ahead and the beat test fires again on the very next FRAME — repeatedly.
//
// ⭐ THE AUDIBLE SYMPTOM IS NOT THE BURST — that was my first reading and the measurement
// disagreed with it. Simulated through the real envelope: at 60 → 180 BPM the three
// retriggers land in three consecutive SAMPLES and the click's peak shifts by 2 samples,
// which nobody can hear. What IS audible is that each spurious retrigger also advances
// `beatIndex`. Measured on the exact loop, `beatsPerBar` 4, counter one sample short of the
// next beat:
//
//     buggy: clicks at +0 (idx 1), +1 (idx 2), +2 (idx 3), then +16000 → idx 0 = ACCENT
//     fixed: clicks at +0 (idx 1), +16000 (idx 2), +32000 (idx 3), +48000 → idx 0 = ACCENT
//
// So the accent arrives TWO BEATS EARLY — 16 000 against 48 000, a 32 000-frame gap, which
// is two new beats. (⛔ #933b: this read "three", contradicted by the trace three lines above
// it — a claim and its own refutation in one block, §2 #425.) The bar is permanently out of phase with the
// player's count. That is the assertion below, and it is directly readable in the samples:
// the accent is rendered at 1568 Hz with envelope 1.0, a plain beat at 1046 Hz with 0.7.
//
// ⭐ WHY IT WENT UNHEARD, which is also why claim 3 exists: a GLIDE shrinks `perBeat` by a
// sliver per step, and a glide is how the tempo usually moves here (`Transport
// .onTempoChange(id: "metronome")` fires up to ~20 Hz during one). Measured 120 → 124: one
// click, correct spacing, identical under both implementations. Only a JUMP — a field edit,
// a loaded project, the flow servo's 40…160 clamp — reaches it. And it is not rare when it
// is reached: the spurious count is `floor(sampleCounter / perBeat) − 1` with the counter
// uniform over the old beat, so a 3× jump misfires on ONE THIRD of jumps — swept over all
// 48 000 alignments of a 60 → 180 jump on the parent tree: 33.4 %.
//
// ⛔ THAT MINUS ONE IS A CORRECTION (#933b). `floor(…)` is the TOTAL fire count, one of which
// is the legitimate beat; I published its `P(≥1) = 66.7 %` as the misfire rate — twice the
// true figure, in the alarming direction, with the arithmetic sitting in the sentence itself.
//
// ⚠️ WHY NOT THE EXISTING `clickOnsets` DETECTOR from the non-blocking suite: it requires 64
// consecutive exact zeros between clicks, and a burst has NO zeros between its retriggers —
// it reports the whole burst as ONE onset. A guard built on it would have been green on the
// defect, for a reason its message never states (#367). The peak-amplitude reading below was
// chosen BECAUSE the simulation showed it separates the two cases: 0.5951 against 0.4158,
// a 43 % gap, so the 0.50 threshold is not a tuned constant but the midpoint of a measured
// split (#442 — the expectation is derived, not read off one run).
//
// ⛔ FORBIDS NOTHING ABOUT TEMPO POLICY (#364). It does not say the bar must survive a tempo
// change — that is a musical decision and preserving the phase is the one the code makes.
// It says only that a tempo change must not SILENTLY ADVANCE the beat counter. If a future
// slice deliberately resyncs the bar on every tempo change, claim 1 goes red and its message
// says so; that is then a decision to record, not a bug to hide.
//
// ⚠️ HONEST LIMITS. 6 tests. They prove the SCHEDULER and the rendered samples; they cannot
// prove it sounds right in a room. Whether a tempo jump during a live take now keeps the
// accent where the player counts it is a DEVICE PROBE (§1) and stays open —
// NEEDS-FOUNDER-VERIFY: run the click, jump the tempo by a field edit rather than a glide,
// listen for whether the accent stays on the one.
//
// ⭐ GRADING (§3), transcribed in Python against THREE implementations — the parent (`-=`
// only), this tree's fold, and an unconditional zeroing — driving the scheduler AND the
// envelope AND this file's own onset detector rather than reasoning about them. The third
// tree is not decoration: it is the "obvious simplification" a later reader will try, and
// until #933b nothing here could tell it apart from the fold.
//
//                          parent      fold (here)   zeroing
//   claim 1                RED 0.5951  green 0.4158  green      the accent, pulled forward
//   claim 2, 1st           RED 0.4158  green 0.5951  green      the accent, missing
//   claim 2, 2nd           green       green         green
//   claim 3, first gap     green 22452 green 22452   RED 23226  folding vs zeroing
//   claim 3, later gaps    green       green         green
//   claim 4                green 0.5951 green 0.4158 green      (parent's number is the
//                                                               pulled accent in-window)
//   claim 6                RED 0.5951  green 0.4158  green      the neighbouring alignment
//   claim 5                forward — it names a line this commit creates
//
// So the honest count is ONE FINDING reported by THREE assertions — claims 1, 2's first half
// and 6 all see the same displacement, from three angles (#486), not three findings. Claim 3's
// first gap is a COUNTERWEIGHT against a different tree entirely. Claims 2's second half, 3's
// later gaps and 4 are green everywhere and are the content: without 4 a voice that stopped
// clicking would satisfy claim 1.
//
// ⛔ THREE OF THESE ROWS ARE #933b CORRECTIONS OF MY OWN FIRST GRADING, all in the flattering
// direction §3 names. I had claim 2 down as a pure counterweight (its first half is a
// regression); I printed the parent's 0.5951 for claim 4 on BOTH trees; and I claimed claim 3
// guarded against zeroing while it discarded the only spacing that shows it — on a zeroing
// tree the whole behavioural half of this file was green.

#if canImport(AVFoundation)
import AVFoundation
import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class ATempoJumpDoesNotPullTheAccentForwardTests: XCTestCase {

    /// Peak of a plain beat is `0.7 * level`, of an accent `1.0 * level`. At `level` 0.6 the
    /// measured peaks are 0.4158 and 0.5951; 0.50 is the midpoint, not a tuned value.
    private static let level: Float = 0.6
    private static let accentThreshold: Float = 0.50

    private static let framesPerBeatAt60 = 48_000
    private static let framesPerBeatAt180 = 16_000

    // MARK: - 1: THE FINDING — a tempo jump must not advance the beat counter

    func testAJumpFromSixtyToOneEightyDoesNotBringTheAccentTwoBeatsEarly() {
        let m = armed(bpm: 60)
        // Sit one sample short of the next beat at 60 BPM: the stale counter is then at its
        // maximum, the worst case FOR THE PARENT (three fires). ⛔ #933b: it is also the
        // LUCKIEST alignment for the repair — 48 000 is an exact multiple of 16 000, so `fmod`
        // returns exactly 0 and no residue survives. Claim 6 drives the neighbouring
        // alignment, where one extra fire does survive, so this file cannot report the repair
        // as cleaner than it is.
        _ = render(m, frames: Self.framesPerBeatAt60 - 1)
        m.bpm = 180
        let after = render(m, frames: Self.framesPerBeatAt180 + 400)

        let click = peak(in: after, around: Self.framesPerBeatAt180, width: 400)
        XCTAssertLessThan(click, Self.accentThreshold, """
            The click one new beat after a 60 → 180 BPM jump peaks at \(click), which is the \
            ACCENT level (~\(1.0 * Self.level)), not a plain beat (~\(0.7 * Self.level)).

            The beat counter was advanced by the tempo change itself: `sampleCounter` still \
            held its count toward the OLD 48 000-frame beat, one `-= perBeat` left it two \
            whole new beats ahead, and the scheduler fired on the next two FRAMES — pulling \
            the accent two beats early and leaving the bar permanently out of phase.

            The repair is in `MetronomeVoice.renderOnAudioThread`: fold the leftover with \
            `truncatingRemainder` when it is still >= `perBeat` after the subtraction (`fmod`, \
            audio-thread legal). If instead a slice DELIBERATELY resynced the bar on a tempo \
            change, this claim is doing its job — record that decision and move this file's \
            header prose with it (#456), do not relax the threshold.
            """)
    }

    // MARK: - 2: counterweight — the accent still exists, and lands where it belongs

    /// ⚠️ WITHOUT THIS, CLAIM 1 PASSES ON A VOICE THAT NEVER ACCENTS AT ALL — the flattering
    /// green. It also fixes WHERE the accent belongs after the jump: three plain beats, then
    /// the downbeat, because the bar's phase is preserved across a tempo change by design.
    func testTheAccentStillArrivesOnTheFourthBeatAfterTheJump() {
        let m = armed(bpm: 60)
        _ = render(m, frames: Self.framesPerBeatAt60 - 1)
        m.bpm = 180
        let after = render(m, frames: 3 * Self.framesPerBeatAt180 + 400)

        let accent = peak(in: after, around: 3 * Self.framesPerBeatAt180, width: 400)
        XCTAssertGreaterThan(accent, Self.accentThreshold, """
            Three beats after the jump the click peaks at \(accent) — a plain beat, not the \
            accent. Either the accent stopped being rendered at all (which would make claim 1 \
            vacuously green) or the bar's phase is no longer preserved across a tempo change. \
            Read claim 1's verdict first: if it is green and this is red, the counter is being \
            advanced somewhere ELSE than the tempo change.
            """)
        let plain = peak(in: after, around: 2 * Self.framesPerBeatAt180, width: 400)
        XCTAssertLessThan(plain, Self.accentThreshold, """
            The beat before the downbeat also reads as an accent (\(plain)) — every beat is \
            being accented, so the accent carries no information and claim 1 proves nothing.
            """)
    }

    // MARK: - 3: counterweight — the common path is untouched

    /// ⭐ A GLIDE STEP IS THE ORDINARY CASE and must behave exactly as before: `perBeat`
    /// shrinks by a sliver, one subtraction is enough, the fold never runs. This is also the
    /// claim that goes red if someone "simplifies" the fold into an unconditional reset —
    /// zeroing the counter would discard the sub-beat phase, which shows up here as a wrong
    /// spacing between the first two clicks.
    ///
    /// ⛔ MY FIRST DRAFT ASSERTED A PEAK AT `perBeat` FRAMES AND WOULD HAVE BEEN RED ON A
    /// CORRECT TREE — the #367 failure in its own right. After a 120 → 124 step the first
    /// click fires EARLY (the counter had already passed the shorter new beat), leaving a
    /// residue, so the next click lands 22 452 frames later, not 23 226. The grid is only
    /// exact from the SECOND click on. Simulated through the real envelope, both trees:
    /// onsets [0, 22452, 45678, 68904], spacings [22452, 23226, 23226]. The assertion is
    /// written from that arithmetic, not from a guess (#442).
    func testAGlideSizedStepStillProducesTheOrdinaryBeatGrid() {
        let m = armed(bpm: 120)
        _ = render(m, frames: 24_000 - 1)          // one sample short of the 120 BPM beat
        let perBeat = Int(MetronomeVoice.samplesPerBeat(bpm: 124).rounded())
        m.bpm = 124
        let after = render(m, frames: 3 * perBeat + 600)
        let onsets = clickOnsets(in: after)

        XCTAssertGreaterThanOrEqual(onsets.count, 3, """
            A 120 → 124 BPM glide step produced \(onsets.count) clicks in three beats' worth \
            of frames (onsets \(onsets)). The ordinary path — the one the tempo actually takes \
            here, since a glide fires this setter up to ~20 times a second — must be unchanged \
            by the jump repair.
            """)
        guard onsets.count >= 3 else { return }
        // ⚠️ #933d — TYPED AND NAMED, because the anonymous `$0` form made the compiler
        // spend 522 ms type-checking this one expression and 556 ms on the whole method
        // (limit 200 ms), which `Build for Testing` reported as a warning on the very
        // commit that added the file. `Range<Int>.map` with two subscripts and a
        // subtraction leaves the element type open until the end; stating `[Int]` and
        // naming the index closes it up front. Not a correctness fix — a warning I
        // introduced and can remove in one line.
        let spacings: [Int] = (1..<onsets.count).map { index -> Int in
            onsets[index] - onsets[index - 1]
        }

        // ⭐ THE FIRST GAP IS WHAT DISTINGUISHES FOLDING FROM ZEROING, and until #933b this
        // claim threw it away. The counter had already passed the shorter new beat, so the
        // first click fires early and leaves a residue; the second click then lands 22 452
        // frames later, not a full 23 226. Zeroing discards that residue and produces an exact
        // `perBeat` here. Both numbers measured through the real envelope and this file's own
        // onset detector, on all three implementations.
        XCTAssertLessThanOrEqual(abs(spacings[0] - 22_452), 2, """
            The first gap after a 120 -> 124 glide step is \(spacings[0]), not the 22 452 \
            that phase-preserving folding produces (all spacings: \(spacings)).

            A value near 23 226 means the leftover is being ZEROED rather than folded: that \
            throws the sub-beat phase away and silently re-times the grid. Every OTHER \
            behavioural claim in this file stays green on a zeroing tree — this assertion is \
            the only one that sees it, so do not relax it.
            """)

        for spacing in spacings.dropFirst() {
            // ⚠️ NOT `XCTAssertEqual(_:_:accuracy:)`. Both sides are `Int`, and that overload
            // is declared over `FloatingPoint`/`Numeric` — nothing in this bundle uses it with
            // an integer, so it is exactly the unverifiable-by-eye construct that cost #930c a
            // red gate. An explicit difference compiles under any overload set.
            XCTAssertLessThanOrEqual(abs(spacing - perBeat), 2, """
                Beat spacing after a glide step is \(spacing), not \(perBeat) (all spacings: \
                \(spacings)). The FIRST gap is legitimately shorter and is checked separately \
                above; from the second click on the grid must be exact, because the glide is \
                the ordinary path and the jump repair must not touch it. If ONLY this is red \
                while the first-gap assertion is green, the beat PERIOD is wrong — look at \
                `samplesPerBeat`, not at the fold.
                """)
        }
    }

    // MARK: - 4: counterweight — a jump does not silence the click either

    /// The cheapest way to make claim 1 green is to stop clicking. Pin that it does not.
    func testTheJumpStillLeavesAudibleClicks() {
        let m = armed(bpm: 60)
        _ = render(m, frames: Self.framesPerBeatAt60 - 1)
        m.bpm = 180
        let after = render(m, frames: Self.framesPerBeatAt180 + 400)
        let loudest = after.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(loudest, 0.1, """
            The whole buffer after the tempo jump peaks at \(loudest) — effectively silence. \
            Claim 1 would be green for the wrong reason (#367). The metronome must keep \
            sounding across a tempo change.
            """)
    }

    // MARK: - 6: the honest limit — the fold bounds the damage, it does not remove it

    /// ⚠️ ONE SAMPLE OVER FROM CLAIM 1 AND THE REPAIR STOPS BEING PERFECT. At `48 000 - 2`
    /// the folded remainder is 15 999, one short of the new beat, so the very next frame fires
    /// again: the fold leaves ONE extra click where the parent left two. Swept exhaustively
    /// over every alignment, the share of jumps with two fires inside 10 ms falls from
    /// 34.3 % to 2.0 % (60 -> 180), 50.7 % to 2.0 % (40 -> 160) and 90.3 % to 6.3 %
    /// (20 -> 400); the worst case falls from three, four and TWENTY fires to two in every
    /// case — never worse than the parent anywhere, but not zero. (⛔ #933c: 34.4 % here
    /// came from a sweep of every seventh alignment under a sentence that said "every";
    /// the grid belongs to the number, #448.)
    ///
    /// ⛔ IT PINS THE BOUND, NOT THE RESIDUE (#364). Asserting "the accent lands one beat
    /// early here" would make a future COMPLETE repair go red — the trap this bundle keeps
    /// paying for. The claim is the weaker statement that survives such a repair: the accent
    /// is never on the FIRST new beat. Parent 0.5951 there, this tree 0.4158.
    func testTheNeighbouringAlignmentKeepsTheAccentOffTheFirstNewBeat() {
        let m = armed(bpm: 60)
        _ = render(m, frames: Self.framesPerBeatAt60 - 2)
        m.bpm = 180
        let after = render(m, frames: Self.framesPerBeatAt180 + 400)

        let click = peak(in: after, around: Self.framesPerBeatAt180, width: 400)
        XCTAssertLessThan(click, Self.accentThreshold, """
            One sample away from claim 1's alignment the accent is back on the first new beat \
            (peak \(click)). Claim 1 alone would still be green there — 48 000 is an exact \
            multiple of 16 000, the one alignment where the fold leaves no residue at all. A \
            repair that only works on that alignment is not a repair.
            """)
    }

    // MARK: - 5: the repair is named where it lives

    /// ⚠️ SOURCE-TEXT SCAN, labelled as such (§1). The behaviour claims above cannot say WHY
    /// the tree is correct, and the fold is one line that reads like a redundant safety check
    /// — exactly the shape a later tidy-up removes. This pins the mechanism so its removal is
    /// a red with an explanation attached.
    func testTheFoldIsStillInTheRenderBlock() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Audio/MetronomeVoice.swift"))
        XCTAssertTrue(code.contains("truncatingRemainder(dividingBy: perBeat)"), """
            The leftover fold is gone from `MetronomeVoice.renderOnAudioThread`. A single \
            `sampleCounter -= perBeat` cannot absorb a tempo jump: see claim 1. If it was \
            replaced by a different mechanism that keeps the beat counter honest, re-anchor \
            this claim on that instead of deleting it — the behaviour claims above stay the \
            real proof.
            """)
    }

    // MARK: - driving the real render block

    /// One voice, armed, at a starting tempo. `enabled`'s `didSet` sets `pendingResync`, so
    /// the first rendered frame is a downbeat — the same entry point the app uses.
    private func armed(bpm: Double) -> MetronomeVoice {
        let m = MetronomeVoice()
        m.level = Self.level
        m.beatsPerBar = 4
        m.accentDownbeat = true
        m.bpm = bpm
        m.enabled = true
        return m
    }

    /// Renders through the same raw-`AudioBufferList` seam the `AVAudioSourceNode` closure
    /// uses. The buffer is poisoned first so "wrote nothing" cannot read as "wrote silence".
    private func render(_ m: MetronomeVoice, frames: Int) -> [Float] {
        let out = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        out.initialize(repeating: 1234.5, count: frames)
        let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        abl.pointee.mNumberBuffers = 1
        abl.pointee.mBuffers.mNumberChannels = 1
        abl.pointee.mBuffers.mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        abl.pointee.mBuffers.mData = UnsafeMutableRawPointer(out)
        defer {
            out.deinitialize(count: frames)
            out.deallocate()
            abl.deallocate()
        }
        m._testRender(frameCount: frames, audioBufferList: abl)
        return Array(UnsafeBufferPointer(start: out, count: frames))
    }

    /// Largest magnitude in `[index, index + width)`, clamped to the buffer. A click's peak
    /// arrives within ~12 frames of its onset, so 400 is generous; the window is wide rather
    /// than exact because the point is WHICH click sounds there, not its sample offset.
    private func peak(in samples: [Float], around index: Int, width: Int) -> Float {
        let lo = max(0, index)
        let hi = min(samples.count, index + width)
        guard lo < hi else { return 0 }
        return samples[lo..<hi].map { abs($0) }.max() ?? 0
    }

    /// Frame indices where a click STARTS: a non-zero sample after a long run of exact
    /// zeros. The envelope decays below the render's `1e-4` floor between clicks at these
    /// tempi and the output is then written as exactly 0, so the gaps are real — measured
    /// 11 500-sample tail against a 23 226-frame beat at 124 BPM.
    ///
    /// ⚠️ IT CANNOT SEE A BURST, and that is why claim 1 does not use it: retriggers one
    /// sample apart leave NO zeros between them, so the whole burst reads as ONE onset. Used
    /// here only where the clicks are a full beat apart.
    private func clickOnsets(in samples: [Float]) -> [Int] {
        var onsets: [Int] = []
        var zeroRun = 64   // the start of the buffer counts as "after silence"
        for (index, sample) in samples.enumerated() {
            if sample == 0 {
                zeroRun += 1
            } else {
                if zeroRun >= 64 { onsets.append(index) }
                zeroRun = 0
            }
        }
        return onsets
    }

    private struct AnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
#endif
