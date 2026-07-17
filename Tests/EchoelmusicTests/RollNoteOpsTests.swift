// RollNoteOpsTests.swift
// Echoel — pins the pure piano-roll selection operators (R1, PLAN_ROLL_PRO.md).
// Foundation-only: every op is deterministic value math on [Note] inside the
// one fixed 16-step bar (1920 PPQ ticks). Laws pinned here:
//   • bar-window invariants (no tick < 0, no end > barTicks) for every op
//   • reverse∘reverse = identity, invert∘invert = identity (in-window)
//   • halfTime∘doubleTime is NOT an identity in general (drop + floor, documented)
//   • ramp monotonicity, echo decay, snapToScale idempotence + in-scale results
//   • stableSeed order-independence (the Bio-Humanize seed)

import XCTest
@testable import Echoelmusic

final class RollNoteOpsTests: XCTestCase {

    private let bar = RollNoteOps.barTicks              // 1920
    private let low = 36
    private let high = 84

    private func n(_ pitch: Int, _ startTick: Int, _ lengthTicks: Int,
                   v: Float = 0.8) -> Note {
        Note(pitch: pitch, startTick: startTick, lengthTicks: lengthTicks, velocity: v)
    }

    /// Bar-window invariant every op must keep.
    private func assertInBar(_ notes: [Note], _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        for note in notes {
            XCTAssertGreaterThanOrEqual(note.startTick, 0, "\(label): tick < 0",
                                        file: file, line: line)
            XCTAssertLessThanOrEqual(note.endTick, bar, "\(label): end > bar",
                                     file: file, line: line)
            XCTAssertGreaterThanOrEqual(note.lengthTicks, 1, "\(label): empty note",
                                        file: file, line: line)
        }
    }

    /// Musical content ignoring ids (echo mints fresh ids by design).
    private func content(_ notes: [Note]) -> [[Int]] {
        notes.map { [$0.pitch, $0.startTick, $0.lengthTicks, Int($0.velocity * 10_000)] }
            .sorted { a, b in a.lexicographicallyPrecedes(b) }
    }

    // MARK: - Reverse

    func testReverse_MirrorsTimeIncludingLength() {
        let input = [n(60, 0, 240), n(64, 480, 120)]
        let out = RollNoteOps.reverse(input)
        // Note ending at 240 now starts at 1920-240 = 1680; length preserved.
        XCTAssertEqual(out[0].startTick, 1680)
        XCTAssertEqual(out[0].lengthTicks, 240)
        XCTAssertEqual(out[1].startTick, 1920 - 600)
        XCTAssertEqual(out[1].lengthTicks, 120)
        assertInBar(out, "reverse")
    }

    func testReverse_TwiceIsIdentity() {
        let input = [n(60, 0, 240), n(64, 480, 120), n(48, 1800, 120), n(52, 37, 91)]
        XCTAssertEqual(RollNoteOps.reverse(RollNoteOps.reverse(input)), input)
    }

    func testReverse_IsDeterministic() {
        let input = [n(60, 300, 200), n(50, 100, 50)]
        XCTAssertEqual(RollNoteOps.reverse(input), RollNoteOps.reverse(input))
    }

    // MARK: - Invert

    func testInvertPitch_MirrorsAroundSelectionCentre() {
        let input = [n(60, 0, 120), n(64, 120, 120), n(67, 240, 120)]
        let out = RollNoteOps.invertPitch(input, lowPitch: low, highPitch: high)
        // sum = 60+67 = 127: 60→67, 64→63, 67→60. Time untouched.
        XCTAssertEqual(out.map(\.pitch), [67, 63, 60])
        XCTAssertEqual(out.map(\.startTick), input.map(\.startTick))
    }

    func testInvertPitch_TwiceIsIdentity_WhenNoClampFires() {
        let input = [n(60, 0, 120), n(64, 120, 120), n(67, 240, 240), n(71, 480, 120)]
        let twice = RollNoteOps.invertPitch(
            RollNoteOps.invertPitch(input, lowPitch: low, highPitch: high),
            lowPitch: low, highPitch: high)
        XCTAssertEqual(twice, input)
    }

    func testInvertPitch_ClampsToWindow() {
        // sum = 36+84 = 120 → both map onto each other (window edges), stays in.
        let edge = [n(36, 0, 120), n(84, 120, 120)]
        let out = RollNoteOps.invertPitch(edge, lowPitch: low, highPitch: high)
        XCTAssertEqual(out.map(\.pitch), [84, 36])
        for note in out {
            XCTAssertTrue((low...high).contains(note.pitch))
        }
    }

    // MARK: - Legato

    func testLegato_ExtendsEachNoteToNextStart_LastToBarEnd() {
        let input = [n(60, 0, 60), n(64, 480, 60), n(67, 960, 60)]
        let out = RollNoteOps.legato(input)
        XCTAssertEqual(out[0].lengthTicks, 480)     // to next start
        XCTAssertEqual(out[1].lengthTicks, 480)
        XCTAssertEqual(out[2].endTick, bar)         // last → bar end
        assertInBar(out, "legato")
    }

    func testLegato_ChordSharesNextStart() {
        // Two notes at the same start (a chord) both extend to the next start.
        let input = [n(60, 0, 60), n(64, 0, 200), n(67, 720, 60)]
        let out = RollNoteOps.legato(input)
        XCTAssertEqual(out[0].lengthTicks, 720)
        XCTAssertEqual(out[1].lengthTicks, 720)
        XCTAssertEqual(out[2].endTick, bar)
    }

    // MARK: - Double / Half time

    func testDoubleTime_ScalesTicksAndDropsWhatFallsOut() {
        let input = [n(60, 0, 240), n(64, 480, 240), n(67, 1200, 240)]
        let out = RollNoteOps.doubleTime(input)
        // 1200×2 = 2400 ≥ 1920 → dropped; the rest double exactly.
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].startTick, 0)
        XCTAssertEqual(out[0].lengthTicks, 480)
        XCTAssertEqual(out[1].startTick, 960)
        XCTAssertEqual(out[1].lengthTicks, 480)
        assertInBar(out, "doubleTime")
    }

    func testDoubleTime_ClampsStraddlingTailToBarEnd() {
        let out = RollNoteOps.doubleTime([n(60, 900, 300)])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].startTick, 1800)
        XCTAssertEqual(out[0].endTick, bar)         // 1800+600 clamped to 1920
    }

    func testHalfTime_CompressesAndKeepsWindow() {
        let input = [n(60, 0, 480), n(64, 960, 480), n(67, 1919, 1)]
        let out = RollNoteOps.halfTime(input)
        XCTAssertEqual(out[0].startTick, 0)
        XCTAssertEqual(out[0].lengthTicks, 240)
        XCTAssertEqual(out[1].startTick, 480)
        XCTAssertEqual(out[2].lengthTicks, 1)       // floors at 1 tick
        assertInBar(out, "halfTime")
    }

    /// Documented contract: halfTime∘doubleTime is NOT an inverse pair —
    /// doubleTime DROPS notes past the bar and halfTime's integer division
    /// floors odd ticks, so round-trips lose material/precision by design.
    func testHalfTimeAfterDoubleTime_IsNotGuaranteedIdentity() {
        let input = [n(60, 0, 240), n(67, 1200, 240)]   // 2nd falls out at ×2
        let roundTrip = RollNoteOps.halfTime(RollNoteOps.doubleTime(input))
        XCTAssertNotEqual(roundTrip.count, input.count)
        // And the odd-tick floor: 37 → ×2 = 74 → ÷2 = 37 survives, but 37 ÷ 2
        // first (halfTime) = 18 → ×2 = 36 ≠ 37.
        let odd = [n(60, 37, 100)]
        XCTAssertNotEqual(RollNoteOps.doubleTime(RollNoteOps.halfTime(odd)), odd)
    }

    // MARK: - Velocity ramp

    func testVelocityRamp_IsLinearOverTimeOrder_AndMonotone() {
        // Deliberately unsorted input — the ramp follows TIME order.
        let input = [n(64, 960, 120, v: 0.5), n(60, 0, 120, v: 0.5),
                     n(62, 480, 120, v: 0.5), n(65, 1440, 120, v: 0.5)]
        let out = RollNoteOps.velocityRamp(input, from: 0.2, to: 0.8)
        let byTime = out.sorted { $0.startTick < $1.startTick }
        XCTAssertEqual(byTime.first?.velocity ?? -1, 0.2, accuracy: 1e-5)
        XCTAssertEqual(byTime.last?.velocity ?? -1, 0.8, accuracy: 1e-5)
        for i in 1..<byTime.count {
            XCTAssertGreaterThan(byTime[i].velocity, byTime[i - 1].velocity,
                                 "ramp up must be strictly increasing over time")
        }
        // Down-ramp mirrors.
        let down = RollNoteOps.velocityRamp(input, from: 0.8, to: 0.2)
            .sorted { $0.startTick < $1.startTick }
        for i in 1..<down.count {
            XCTAssertLessThan(down[i].velocity, down[i - 1].velocity)
        }
    }

    func testVelocityRamp_SingleNoteGetsFrom_AndClampsToUnit() {
        let out = RollNoteOps.velocityRamp([n(60, 0, 120, v: 0.5)], from: 1.5, to: 2)
        XCTAssertEqual(out[0].velocity, 1.0)        // clamped
    }

    // MARK: - Echo

    func testEcho_AddsDecayingCopiesInsideTheBar() {
        let input = [n(60, 0, 240, v: 0.8)]
        let out = RollNoteOps.echo(input, times: 2, decay: 0.5)
        XCTAssertEqual(out.count, 3)                // original + 2 copies
        // Original untouched (same id, same velocity).
        XCTAssertEqual(out[0], input[0])
        // Copies at start + k·length, velocity decaying multiplicatively.
        XCTAssertEqual(out[1].startTick, 240)
        XCTAssertEqual(out[1].velocity, 0.4, accuracy: 1e-5)
        XCTAssertEqual(out[2].startTick, 480)
        XCTAssertEqual(out[2].velocity, 0.2, accuracy: 1e-5)
        XCTAssertNotEqual(out[1].id, input[0].id)   // copies are NEW notes
        assertInBar(out, "echo")
    }

    func testEcho_DropsCopiesPastBarEnd_AndFloorsVelocity() {
        // Note near the bar end: only copies starting < barTicks survive.
        let out = RollNoteOps.echo([n(60, 1800, 240, v: 0.8)], times: 4, decay: 0.5)
        XCTAssertEqual(out.count, 1)                // start+240 = 2040 ≥ 1920 → none
        // Deep decay floors at the musical minimum, never a dead note.
        let quiet = RollNoteOps.echo([n(60, 0, 120, v: 0.1)], times: 3, decay: 0.1)
        for copy in quiet.dropFirst() {
            XCTAssertGreaterThanOrEqual(copy.velocity, 0.05)
        }
        assertInBar(quiet, "echo-quiet")
    }

    func testEcho_MusicalContentIsDeterministic() {
        let input = [n(60, 0, 240, v: 0.8), n(64, 480, 120, v: 0.6)]
        let a = RollNoteOps.echo(input, times: 2, decay: 0.6)
        let b = RollNoteOps.echo(input, times: 2, decay: 0.6)
        XCTAssertEqual(content(a), content(b))      // ids fresh, music identical
    }

    // MARK: - Snap to scale

    func testSnapToScale_AllResultsInKey_AndIdempotent() {
        let key = MusicalKey(root: 0, scale: .major)     // C major
        let input = [n(61, 0, 120), n(63, 120, 120), n(66, 240, 120), n(60, 360, 120)]
        let once = RollNoteOps.snapToScale(input, key: key, lowPitch: low, highPitch: high)
        for note in once {
            XCTAssertTrue(key.contains(note.pitch), "pitch \(note.pitch) not in key")
            XCTAssertTrue((low...high).contains(note.pitch))
        }
        // Idempotent: snapping a snapped selection changes nothing.
        XCTAssertEqual(RollNoteOps.snapToScale(once, key: key,
                                               lowPitch: low, highPitch: high), once)
    }

    func testSnapToScale_TieResolvesDownward() {
        // C major: C#4 (61) is 1 from C (60) and 1 from D (62) → downward wins.
        let key = MusicalKey(root: 0, scale: .major)
        let out = RollNoteOps.snapToScale([n(61, 0, 120)], key: key,
                                          lowPitch: low, highPitch: high)
        XCTAssertEqual(out[0].pitch, 60)
    }

    func testSnapPitch_FoldsIntoWindowInScale() {
        // Pentatonic minor on A (root 9). A pitch below the window must fold
        // UP by octaves and still land in scale.
        let key = MusicalKey(root: 9, scale: .pentatonicMinor)
        let p = RollNoteOps.snapPitch(30, key: key, lowPitch: low, highPitch: high)
        XCTAssertTrue((low...high).contains(p))
        XCTAssertTrue(key.contains(p))
    }

    // MARK: - Bio-Humanize seed

    func testStableSeed_IsOrderIndependent_AndContentSensitive() {
        let a = [n(60, 0, 120, v: 0.8), n(64, 480, 240, v: 0.6)]
        let b = [a[1], a[0]]                        // same notes, swapped order
        XCTAssertEqual(RollNoteOps.stableSeed(for: a), RollNoteOps.stableSeed(for: b))
        // A velocity change (e.g. a previous humanize pass) re-seeds.
        var c = a
        c[0].velocity = 0.81
        XCTAssertNotEqual(RollNoteOps.stableSeed(for: a), RollNoteOps.stableSeed(for: c))
        // Ids do NOT affect the seed (musical content only).
        let sameMusicNewIDs = a.map {
            Note(pitch: $0.pitch, startTick: $0.startTick,
                 lengthTicks: $0.lengthTicks, velocity: $0.velocity)
        }
        XCTAssertEqual(RollNoteOps.stableSeed(for: a),
                       RollNoteOps.stableSeed(for: sameMusicNewIDs))
    }

    /// The wired twist end-to-end at the core level: hrvHumanize with the
    /// stable seed is deterministic and velocity-only (reuses H3 — pinned
    /// deeper in BioComposerHumanizeTests; this guards the R1 seam).
    func testBioHumanizeSeam_DeterministicVelocityOnly() {
        let input = [n(60, 0, 240, v: 0.8), n(64, 480, 120, v: 0.6)]
        let seed = RollNoteOps.stableSeed(for: input)
        let a = BioComposer.hrvHumanize(input, hrvNormalized: 0.5, seed: seed)
        let b = BioComposer.hrvHumanize(input, hrvNormalized: 0.5, seed: seed)
        XCTAssertEqual(a, b)
        for (orig, out) in zip(input, a) {
            XCTAssertEqual(orig.pitch, out.pitch)
            XCTAssertEqual(orig.startTick, out.startTick)
            XCTAssertEqual(orig.lengthTicks, out.lengthTicks)
            XCTAssertTrue((0.05...1).contains(out.velocity))
        }
    }
}
