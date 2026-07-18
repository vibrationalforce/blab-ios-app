import XCTest
@testable import Echoelmusic

/// Tests for the pure `BreathArp` — breath phase → direction, depth → density,
/// chord → the walked pitches. Pins determinism and the musical invariants.
final class BreathArpTests: XCTestCase {

    private let cMajor = [60, 64, 67]   // C E G

    // MARK: - Direction from breath phase

    func testDirection_inhaleClimbsExhaleDescends() {
        XCTAssertEqual(BreathArp.direction(breathPhase: 0.0), .up)
        XCTAssertEqual(BreathArp.direction(breathPhase: 0.49), .up)
        XCTAssertEqual(BreathArp.direction(breathPhase: 0.5), .down)
        XCTAssertEqual(BreathArp.direction(breathPhase: 1.0), .down)
        XCTAssertEqual(BreathArp.direction(breathPhase: .nan), .up)   // fail-neutral
    }

    func testPattern_ascendingStartsLowDescendingStartsHigh() {
        let up = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                   breathPhase: 0.1, breathDepth: 1.0)
        XCTAssertEqual(up.first?.pitch, 60, "inhale arp starts on the lowest chord tone")
        let down = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                     breathPhase: 0.9, breathDepth: 1.0)
        XCTAssertEqual(down.first?.pitch, 67, "exhale arp starts on the highest chord tone")
    }

    // MARK: - Density from breath depth

    func testDensity_countMatchesActiveSteps() {
        for depth: Float in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let notes = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                          breathPhase: 0.2, breathDepth: depth)
            XCTAssertEqual(notes.count, BreathArp.activeSteps(depth: depth, steps: 16),
                           "note count must equal the even-spread active-step count (depth \(depth))")
        }
    }

    func testDensity_deepBreathFillsEveryStep() {
        let notes = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                      breathPhase: 0.2, breathDepth: 1.0)
        XCTAssertEqual(notes.count, 16)
    }

    func testDensity_shallowBreathStillSoundsAtLeastOnce() {
        let notes = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                      breathPhase: 0.2, breathDepth: 0.0)
        XCTAssertEqual(notes.count, 1, "a shallow breath is sparse but never silent")
    }

    // MARK: - Pitch walk stays in the chord

    func testPattern_everyPitchIsAChordTone() {
        let notes = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                      breathPhase: 0.3, breathDepth: 0.8)
        let chord = Set(cMajor)
        for n in notes { XCTAssertTrue(chord.contains(n.pitch), "arp wraps within the chord") }
    }

    // MARK: - Timing

    func testPattern_timingSitsOnTheGrid() {
        let start = 480
        let stepTicks = Note.ticksPerStep
        let notes = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                      breathPhase: 0.2, breathDepth: 1.0,
                                      startTick: start, stepTicks: stepTicks)
        for (i, n) in notes.enumerated() {
            XCTAssertEqual(n.startTick, start + i * stepTicks)
            XCTAssertEqual(n.lengthTicks, stepTicks)
        }
    }

    // MARK: - Determinism + edge cases

    func testPattern_isDeterministic() {
        let a = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                  breathPhase: 0.3, breathDepth: 0.6, startTick: 240)
        let b = BreathArp.pattern(chordPitches: cMajor, steps: 16,
                                  breathPhase: 0.3, breathDepth: 0.6, startTick: 240)
        XCTAssertEqual(a, b, "same window must produce identical notes, ids included")
    }

    func testPattern_emptyChordOrZeroStepsYieldsNothing() {
        XCTAssertTrue(BreathArp.pattern(chordPitches: [], steps: 16,
                                        breathPhase: 0.2, breathDepth: 1).isEmpty)
        XCTAssertTrue(BreathArp.pattern(chordPitches: cMajor, steps: 0,
                                        breathPhase: 0.2, breathDepth: 1).isEmpty)
    }

    func testPattern_dropsOutOfRangePitches() {
        let notes = BreathArp.pattern(chordPitches: [-5, 60, 200, 64], steps: 16,
                                      breathPhase: 0.2, breathDepth: 1.0)
        for n in notes {
            XCTAssertTrue([60, 64].contains(n.pitch), "only in-range chord tones survive")
        }
    }

    func testPattern_velocityFailsNeutralAndFloors() {
        let notes = BreathArp.pattern(chordPitches: cMajor, steps: 4,
                                      breathPhase: 0.2, breathDepth: 1.0, velocity: .nan)
        for n in notes {
            XCTAssertTrue(n.velocity.isFinite)
            XCTAssertGreaterThanOrEqual(n.velocity, 0.05)
        }
    }
}
