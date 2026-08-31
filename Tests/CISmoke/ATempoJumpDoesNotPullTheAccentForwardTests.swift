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
// click, correct spacing, identical under the parent and #933's fold; #934 moves the first
// click after every glide step, which is the point — see claim 3. Only a JUMP — a field edit,
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
// ⚠️ HONEST LIMITS. 8 tests. They prove the SCHEDULER and the rendered samples; they cannot
// prove it sounds right in a room. Whether a tempo change during a live take now keeps the
// accent where the player counts it is a DEVICE PROBE (§1) and stays open —
// NEEDS-FOUNDER-VERIFY: run the click, change the tempo by a field edit rather than a glide,
// in BOTH directions, and listen for whether the beat in progress stays where it belongs.
//
// ⭐ GRADING (§3), transcribed in Python against FOUR implementations, driving the scheduler,
// the envelope and this file's own onset detector rather than reasoning about them. The four
// are the parent (`-=` only), #933's fold, #934's proportional rescale (this tree), and an
// unconditional zeroing — the "obvious simplification" a later reader will try.
//
//                       parent      fold        rescale (here)  zeroing
//   claim 1             RED 0.5951  green       green           green
//   claim 2, 1st        RED 0.4158  green       green           RED 0.4158
//   claim 2, 2nd        green       green       green           green
//   claim 3 first click RED 11 225  RED 11 225  green 11 612    RED 23 225
//   claim 3 spacings    green       green       green           green
//   claim 4             green       green       green           green
//   claim 6             RED 0.5951  green       green           green
//   claim 7 tempo DROP  RED none    RED none    green 479       RED none
//   claims 5, 8         forward — they name lines this commit and #933 create
//
// **Only this tree is green on every claim**, and that is the property worth having: each of
// the three alternatives is a real strategy someone could write, and the file says which one a
// tree is running rather than only that something is wrong.
//
// ⛔ CLAIM 3 HAD TO BE REWRITTEN FOR #934 AND THAT IS THE MOST INSTRUCTIVE ROW HERE. Its #933b
// form pinned a first gap of 22 452 at the one-sample-short alignment — where rescaling and
// zeroing BOTH produce exactly `perBeat`, so the discriminator collapsed the moment the repair
// improved, and it would have gone RED on correct code. Mid-beat separates all three by
// construction. **A guard written against two implementations can be blind to a third, and a
// guard written against the CURRENT one can go red when the code gets better** — both happened
// to this single claim, one cycle apart.
//
// ⛔ THREE ROWS ARE #933b CORRECTIONS OF MY FIRST GRADING, all in the flattering direction §3
// names: claim 2 was booked as a pure counterweight (its first half is a regression); claim 4
// printed the parent's 0.5951 for both trees; and claim 3 was described as the guard against
// zeroing while discarding the only spacing that shows it.

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

    // MARK: - 3: the three-way discriminator — folding vs rescaling vs zeroing

    /// ⭐ ONE ASSERTION THAT TELLS ALL THREE IMPLEMENTATIONS APART, which is what this claim
    /// had to become once #934 replaced the fold with a proportional rescale. Drive a glide
    /// step with the counter HALFWAY through the old beat (12 000 of a 24 000-frame beat at
    /// 120 BPM), then step to 124 BPM and find the first click. Simulated through the real
    /// envelope and this file's own onset detector:
    ///
    ///     fold      first onset 11 225   (absolute count kept — the beat is cut short)
    ///     rescale   first onset 11 612   (the FRACTION is kept — this tree)
    ///     zero      first onset 23 225   (the position is thrown away — a whole new beat)
    ///
    /// ⛔ THE PREVIOUS VERSION PINNED 22 452 AND WOULD HAVE GONE RED ON #934's CORRECT TREE.
    /// It used the one-sample-short alignment, where rescaling and zeroing BOTH produce a first
    /// gap of exactly `perBeat` — the discriminator collapsed the moment the repair improved.
    /// Mid-beat separates them by construction, because that is where "kept the fraction",
    /// "kept the count" and "kept nothing" are three different numbers.
    func testTheFirstClickAfterAGlideStepTellsTheThreeStrategiesApart() {
        let m = armed(bpm: 120)
        _ = render(m, frames: 12_000)              // ~halfway through the 120 BPM beat
        let perBeat = Int(MetronomeVoice.samplesPerBeat(bpm: 124).rounded())
        m.bpm = 124
        let after = render(m, frames: 3 * perBeat + 600)
        let onsets = clickOnsets(in: after)

        XCTAssertFalse(onsets.isEmpty, """
            A 120 -> 124 BPM glide step produced no click at all in three beats of frames. \
            The ordinary path — the one the tempo actually takes here, since a glide fires \
            this setter up to ~20 times a second — must keep sounding.
            """)
        guard let first = onsets.first else { return }
        XCTAssertLessThanOrEqual(abs(first - 11_612), 2, """
            The first click after a mid-beat glide step lands at frame \(first) (onsets \
            \(onsets.prefix(4))). The three known strategies put it in three different places:

              11 225  the leftover was FOLDED — the absolute sample count was kept, so the \
            beat in progress is cut short.
              11 612  the counter was RESCALED — the fraction of the beat is kept. This is \
            what #934 ships and what this claim expects.
              23 225  the counter was ZEROED — the position was thrown away and the player \
            waits a whole new beat.

            Read the number before changing anything: it says which of the three the tree is \
            doing, and only one of them is a defect.
            """)
        let spacings: [Int] = (1..<onsets.count).map { index -> Int in
            onsets[index] - onsets[index - 1]
        }
        for spacing in spacings {
            XCTAssertLessThanOrEqual(abs(spacing - perBeat), 2, """
                Beat spacing after a glide step is \(spacing), not \(perBeat) (all spacings: \
                \(spacings)). Once the first click has landed the grid must be exact, whatever \
                strategy placed that first one. If ONLY this is red while the first-click \
                assertion is green, the beat PERIOD is wrong — look at `samplesPerBeat`, not \
                at the rescale.
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

    // MARK: - 6: the alignment next door — the repair is not an artefact of one lucky offset

    /// ⚠️ CLAIM 1 SITS ON THE LUCKIEST ALIGNMENT THERE IS, so on its own it proves very little.
    /// 48 000 is an exact multiple of 16 000, the one offset where #933's fold happened to
    /// leave no residue at all. One sample over, at `48 000 - 2`, the fold's remainder is
    /// 15 999 — one short of the new beat — and the very next frame fires again. This claim
    /// re-asks claim 1's question at that offset, where a fold-shaped repair is measurably
    /// imperfect and #934's rescale is not.
    ///
    /// ⭐ THE PERCENTAGES BELOW ARE THE FOLD'S HISTORY, not this tree's behaviour (#934 made
    /// the fold unreachable — see claim 5). Swept exhaustively over every alignment, the fold
    /// moved the share of jumps with two fires inside 10 ms from 34.3 % to 2.0 % (60 -> 180),
    /// 50.7 % to 2.0 % (40 -> 160) and 90.3 % to 6.3 % (20 -> 400), worst case three, four and
    /// TWENTY fires down to two. The rescale takes all three to zero. (⛔ #933c: 34.4 % here
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

    // MARK: - 7: the direction #933 never touched — a tempo DROP

    /// ⭐ THE FOLD ONLY EVER RAN WHEN THE BEAT GOT SHORTER, so nothing in this file described
    /// what happens when it gets LONGER — and there the old behaviour was arguably worse. A
    /// player 99 % of the way through a beat at 180 BPM who drops to 60 BPM should hear the
    /// click almost at once; keeping the absolute count makes them wait 32 160 frames, two
    /// thirds of a second, because 15 840 samples is only a third of the way into the new
    /// beat. Simulated through the real envelope, counter at 99 %:
    ///
    ///     fold      no click in the first 3 000 frames  (it arrives at 32 159)
    ///     zero      no click in the first 3 000 frames  (it arrives at 47 999)
    ///     rescale   click at frame 479                  (10 ms — where the player expects it)
    ///
    /// ⚠️ This is the claim that makes #934 a REPAIR rather than a refinement: #933 measured
    /// only the shortening direction and reported itself as "never worse than the parent
    /// anywhere tested" — true, and it had not tested this direction at all.
    func testATempoDropLandsTheClickWhereThePlayerIsInTheBeat() {
        let m = armed(bpm: 180)
        _ = render(m, frames: 15_840)              // 99 % through the 16 000-frame beat
        m.bpm = 60
        let after = render(m, frames: 3_000)
        let onsets = clickOnsets(in: after)

        // ⚠️ NOT `XCTAssertEqual(_:_:accuracy:)` — both sides are `Int` and no test in this
        // bundle uses that overload with integers (#930c cost a red gate to exactly this class
        // of "looks fine by eye"). An explicit difference compiles under any overload set.
        let firstOnset = onsets.first ?? -1
        XCTAssertLessThanOrEqual(abs(firstOnset - 479), 4, """
            After dropping 180 -> 60 BPM at 99 % of a beat the first click is at frame \
            \(firstOnset) (-1 = nowhere in 3 000 frames; onsets \(onsets)).

            NOWHERE means the counter kept its absolute sample count (or was zeroed): 15 840 \
            samples is only a third of the way into a 48 000-frame beat, so the player waits \
            two thirds of a second for a beat they were about to finish. Expected ~479 — the \
            proportional position, 1 % of the new beat.

            Do not relax this into "a click eventually arrives". The number IS the behaviour: \
            it says the beat in progress kept its POSITION and not its sample count.
            """)
    }

    // MARK: - 8: the mechanism is named where it lives

    /// ⚠️ SOURCE-TEXT SCAN, labelled as such (§1). Claim 7 proves the behaviour; this pins the
    /// one line that produces it, because a rescale reads like a redundant safety check next to
    /// the fold it made unreachable — exactly the shape a later tidy-up removes.
    func testTheProportionalRescaleIsStillInTheRenderBlock() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Audio/MetronomeVoice.swift"))
        XCTAssertTrue(code.contains("sampleCounter *= perBeat / lastPerBeat"), """
            The proportional rescale is gone from `MetronomeVoice.swift`. Without \
            it a tempo change strands the beat counter at an absolute sample count that means \
            something different at the new tempo — see claims 3 and 7 for what that sounds like \
            in each direction. If a different mechanism now keeps the counter's POSITION across \
            a tempo change, re-anchor here rather than deleting; the behaviour claims stay the \
            real proof.
            """)
        XCTAssertTrue(code.contains("if lastPerBeat > 0"), """
            The division guard on `lastPerBeat` is gone. A zero or negative divisor makes the \
            counter inf or NaN, and a NaN counter can never satisfy `sampleCounter >= perBeat` \
            again — the click stops forever while every sample stays a perfectly finite 0, the \
            silent-death mode `samplesPerBeat`'s own doc describes. Guard the division; do not \
            argue from the clamp two types away.
            """)
    }

    // MARK: - 5: the floor under the repair, kept deliberately unreachable

    /// ⚠️ SOURCE-TEXT SCAN, labelled as such (§1). ⛔ THIS CLAIM'S MESSAGE USED TO SAY "a single
    /// `sampleCounter -= perBeat` cannot absorb a tempo jump: see claim 1", and #934 made that
    /// false: with the rescale in place the counter never enters the beat branch more than one
    /// beat over, so deleting the fold entirely leaves claims 1, 2, 3, 4, 6 and 7 ALL green. The
    /// fold is no longer the repair — it is an unreachable FLOOR, and a floor that no behaviour
    /// claim can feel needs its reason written down or the next tidy-up removes it correctly by
    /// every test and wrongly by intent.
    ///
    /// ⭐ WHY KEEP IT: `sampleCounter` is the one piece of state that survives across buffers on
    /// the audio thread. If a future edit adds a second writer — a seek, a loop wrap, a resync
    /// that lands mid-beat — the rescale only normalises what a TEMPO change did, and the fold
    /// is what stops an arbitrary overshoot from firing a burst of retriggers. It costs one
    /// compare per beat and cannot change behaviour while the rescale is correct.
    func testTheOverflowFloorIsStillInTheRenderBlock() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Audio/MetronomeVoice.swift"))
        XCTAssertTrue(code.contains("truncatingRemainder(dividingBy: perBeat)"), """
            The overflow floor is gone from `MetronomeVoice.swift`. It is unreachable while the \
            proportional rescale (claim 8) is in place, so no behaviour claim in this file goes \
            red without it — that is exactly why it is pinned here and not left to the tests. It \
            bounds ANY future writer of `sampleCounter` to one retrigger instead of a burst. If \
            the counter has genuinely gained a single owner that cannot overshoot, delete both \
            this claim and the line together, in one commit, with that argument written down.
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
