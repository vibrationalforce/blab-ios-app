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
// So the accent arrives THREE BEATS EARLY and the bar is permanently out of phase with the
// player's count. That is the assertion below, and it is directly readable in the samples:
// the accent is rendered at 1568 Hz with envelope 1.0, a plain beat at 1046 Hz with 0.7.
//
// ⭐ WHY IT WENT UNHEARD, which is also why claim 3 exists: a GLIDE shrinks `perBeat` by a
// sliver per step, and a glide is how the tempo usually moves here (`Transport
// .onTempoChange(id: "metronome")` fires up to ~20 Hz during one). Measured 120 → 124: one
// click, correct spacing, identical under both implementations. Only a JUMP — a field edit,
// a loaded project, the flow servo's 40…160 clamp — reaches it. And it is not rare when it
// is reached: the spurious count is `floor(sampleCounter / perBeat)` with the counter
// uniform over the old beat, so a 3× jump misfires on TWO THIRDS of jumps.
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
// ⭐ GRADING (§3), transcribed in Python against BOTH trees, driving the scheduler and the
// envelope rather than reasoning about them — and the transcription corrected my own first
// grading, in the flattering direction §3 names:
//
//   claim 1        red at parent (peak@+16000 = 0.5951, the accent), green here (0.4158)
//   claim 2, 1st   red at parent (peak@+48000 = 0.4158, a plain beat), green here (0.5951)
//   claim 2, 2nd   green on both (0.4158)
//   claim 3        green on both (onsets [0, 22452, 45678, 68904] on each)
//   claim 4        green on both (0.5951)
//   claim 5        forward — it names a line this commit creates
//
// So the honest count is ONE FINDING reported by TWO assertions (#486), not two findings:
// claim 1 sees the accent arrive early and claim 2's first assertion sees it MISSING where it
// belongs — the same displacement from both ends. I had written claim 2 down as a pure
// counterweight because that is what I intended it to be; it is one only in its second half.
// Claims 3 and 4 are the real counterweights, and they are the content: without 4 a tree that
// stopped clicking entirely would satisfy claim 1, and without 3 a "fix" that zeroed the
// counter on every beat would too.

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

    func testAJumpFromSixtyToOneEightyDoesNotBringTheAccentThreeBeatsEarly() {
        let m = armed(bpm: 60)
        // Sit one sample short of the next beat at 60 BPM, so the stale counter is at its
        // maximum — the worst case, and the one the arithmetic above is written for.
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
            the accent three beats early and leaving the bar permanently out of phase.

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
        let spacings = (1..<onsets.count).map { onsets[$0] - onsets[$0 - 1] }
        for spacing in spacings.dropFirst() {
            // ⚠️ NOT `XCTAssertEqual(_:_:accuracy:)`. Both sides are `Int`, and that overload
            // is declared over `FloatingPoint`/`Numeric` — nothing in this bundle uses it with
            // an integer, so it is exactly the unverifiable-by-eye construct that cost #930c a
            // red gate. An explicit difference compiles under any overload set.
            XCTAssertLessThanOrEqual(abs(spacing - perBeat), 2, """
                Beat spacing after a glide step is \(spacing), not \(perBeat) (all spacings: \
                \(spacings)). The FIRST gap is legitimately shorter — the first click fires \
                early because the counter had already passed the shorter new beat — so only \
                the later ones are checked. A wrong spacing here means the leftover was \
                ZEROED rather than folded: zeroing throws away the sub-beat phase and pushes \
                the grid out by up to a full beat. Fold, do not zero.
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
