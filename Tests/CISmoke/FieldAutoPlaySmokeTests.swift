// FieldAutoPlaySmokeTests.swift
// Echoel — the Field can play itself (founder 2026-07-29, "Es soll auch eine Möglichkeit
// geben wie der Synth selbst spielt ohne das man Touch bedienen muss. Natürlich mit mehreren
// Parametern"), in the BLOCKING bundle.
//
// WHAT IS BEING TESTED, and what deliberately is not. `FieldAutoPlay` emits POSITIONS on the
// play surface — normalised x/y plus a velocity — and nothing else. It does not know about
// pitch, keys, scales or voices. That is the whole design decision: a generated touch is meant
// to enter the surface where a finger does, so key-quantisation, Ultrasync, Life and Level
// apply to it with no second code path to keep in step.
//
// ⚠️ Not wired yet — but the gap is small: the DECISION cores are already public and reusable
// (`TouchPitchMap`, `TouchQuantizer.plan`, `TouchPitchMap.microVariation`), and Level is a gain
// on the shared voice that anything routed there inherits. What the wiring slice must hoist is
// the private DISPATCH in `TouchInstrumentUIView.sound(...)`. See the source file's header;
// two earlier versions of this note overstated the gap in exactly the same direction.
//
// So these tests pin the SHAPE of the movement, which is the part a listener actually hears:
// does it travel, does it stay inside the surface, does it repeat identically, does a
// parameter of zero mean "off" rather than "something small". None of that can be checked by
// reading the code, and all of it is audible immediately.
//
// The honest limit: this proves the generator moves sensibly. Whether it sounds MUSICAL is a
// device judgement and is not claimed here.

import XCTest
@testable import Echoelmusic

final class FieldAutoPlaySmokeTests: XCTestCase {

    private func params(
        motion: FieldAutoPlay.Motion = .pendulum,
        density: Float = 1,
        span: Float = 1,
        centre: Float = 0.5,
        band: Float = 0.5,
        bandDrift: Float = 0,
        voices: Int = 1,
        periodSteps: Int = 16
    ) -> FieldAutoPlay.Params {
        FieldAutoPlay.Params(motion: motion, density: density, span: span, centre: centre,
                             band: band, bandDrift: bandDrift, voices: voices,
                             periodSteps: periodSteps)
    }

    private func sweep(_ p: FieldAutoPlay.Params, steps: Int = 32,
                       seed: UInt64 = 7) -> [FieldAutoPlay.Touch] {
        (0..<steps).flatMap { FieldAutoPlay.touches(atStep: $0, params: p, seed: seed) }
    }

    // MARK: - It stays on the surface

    /// THE ONE THAT CANNOT BE CHECKED BY EYE. Every emitted point, under every motion, at
    /// every extreme of span and centre, must land inside the unit square — because `x` and
    /// `y` are fed straight to `TouchPitchMap`, where an out-of-range value is not a visual
    /// glitch but a wrong or crashing pitch lookup. A wide span centred at an edge is exactly
    /// where naive travel maths walks off the surface.
    func testEveryGeneratedTouchStaysInsideTheSurface() {
        for motion in FieldAutoPlay.Motion.allCases {
            for centre in [Float(0), 0.15, 0.5, 0.85, 1] {
                for span in [Float(0), 0.5, 1] {
                    let p = params(motion: motion, span: span, centre: centre,
                                   band: 0.9, bandDrift: 1, voices: 3)
                    for t in sweep(p, steps: 64) {
                        XCTAssertTrue((0...1).contains(t.x),
                                      "\(motion) centre \(centre) span \(span) → x \(t.x)")
                        XCTAssertTrue((0...1).contains(t.y),
                                      "\(motion) centre \(centre) span \(span) → y \(t.y)")
                        XCTAssertTrue((0...1).contains(t.velocity), "velocity \(t.velocity)")
                    }
                }
            }
        }
    }

    /// Non-finite parameters must not produce non-finite positions. Bio values feed these
    /// (a rate from the pulse, a span from breath depth), and a single bad rPPG frame has
    /// twice put a NaN into this app's audio path (#29, #176). The boundary is here.
    ///
    /// ⚠️ `density` is held FINITE on purpose. The first version of this test set every
    /// parameter to NaN including density — and a NaN density clamps to 0, which stops the
    /// generator, which empties the array, which makes the loop below assert nothing at all.
    /// It passed while testing nothing. Density gets its own zero-case test; this one has to
    /// produce touches to be worth running, so it asserts that it did.
    func testNonFiniteParametersCannotProduceNonFinitePositions() {
        let p = params(density: 0.9, span: .infinity, centre: .nan,
                       band: .nan, bandDrift: .infinity)
        let touches = sweep(p, steps: 16)
        XCTAssertFalse(touches.isEmpty, "nothing was generated — this test would prove nothing")
        for t in touches {
            XCTAssertTrue(t.x.isFinite && t.y.isFinite && t.velocity.isFinite,
                          "a non-finite parameter leaked into a position")
            XCTAssertTrue((0...1).contains(t.x) && (0...1).contains(t.y))
        }
    }

    // MARK: - It actually moves

    /// A generator that emits the same point forever is a drone, not a player. The three
    /// SHAPED motions sweep the surface by construction and must cover most of it.
    func testEachShapedMotionReallyTravels() {
        for motion in [FieldAutoPlay.Motion.rise, .fall, .pendulum] {
            let xs = sweep(params(motion: motion), steps: 32).map { $0.x }
            let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
            XCTAssertGreaterThan(spread, 0.8,
                                 "\(motion) only covered \(spread) of the surface — that is a drone")
        }
    }

    /// `.drift` gets a much lower bar, and the number is measured rather than wished for: a
    /// bounded random walk genuinely may not roam far inside one period, and at the shipped
    /// step size seed 7 covers 0.281 while seed 99 covers 0.692. An earlier version of this
    /// test lumped drift in with the shaped motions at a 0.3 bar — it would have gone red on
    /// a perfectly healthy walk. The bar that means something here is "it moved at all",
    /// because a drift stuck on one spot is the actual defect.
    func testDriftMovesEvenThoughItDoesNotSweep() {
        for seed in [UInt64(1), 7, 99] {
            let xs = sweep(params(motion: .drift), steps: 32, seed: seed).map { $0.x }
            let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
            XCTAssertGreaterThan(spread, 0.1, "drift with seed \(seed) barely moved (\(spread))")
        }
    }

    /// `.hold` is the one motion that must NOT travel: it is how a player parks the generator
    /// on one note and shapes it with the other controls. Pinned so a future "improvement"
    /// cannot quietly add drift to it.
    func testHoldStaysPut() {
        let xs = Set(sweep(params(motion: .hold), steps: 32).map { $0.x })
        XCTAssertEqual(xs.count, 1, "hold must emit one position, not a narrow wander")
    }

    /// Rise and fall must be genuine opposites, not the same curve with a different name.
    func testRiseAndFallAreMirrorImages() {
        let up = sweep(params(motion: .rise), steps: 16).map { $0.x }
        let down = sweep(params(motion: .fall), steps: 16).map { $0.x }
        XCTAssertEqual(up.count, down.count)
        for (a, b) in zip(up, down) {
            XCTAssertEqual(a + b, 1, accuracy: 1e-5, "fall must mirror rise about the centre")
        }
    }

    // MARK: - The parameters mean what they say

    /// Density 0 means SILENCE, not "a few". A generator that keeps trickling notes at zero
    /// is a control that cannot be turned off — and this one runs unattended, so the user
    /// cannot simply stop touching it.
    func testDensityZeroIsSilence() {
        XCTAssertTrue(sweep(params(density: 0), steps: 64).isEmpty,
                      "density 0 must stop the generator completely")
    }

    /// Density 1 fires every step; density must be monotonic in between, or the dial fights
    /// the hand that turns it.
    func testDensityRisesMonotonically() {
        var previous = 0
        for d in stride(from: Float(0), through: 1, by: 0.1) {
            let count = sweep(params(density: d), steps: 32).count
            XCTAssertGreaterThanOrEqual(count, previous,
                                        "density \(d) produced FEWER notes than a lower setting")
            previous = count
        }
        XCTAssertGreaterThan(previous, 0)
    }

    /// Span 0 collapses the travel to a single column — the "one note, played over and over"
    /// setting. Distinct from `.hold`, which also freezes the phase.
    func testSpanZeroCollapsesToOneColumn() {
        let xs = Set(sweep(params(motion: .pendulum, span: 0, centre: 0.3), steps: 32).map { $0.x })
        XCTAssertEqual(xs.count, 1)
        XCTAssertEqual(xs.first ?? -1, 0.3, accuracy: 1e-5, "span 0 must sit ON the centre")
    }

    /// Voices are simultaneous, not sequential: the point of more than one is a chord under
    /// the finger that isn't there. They must also be at DIFFERENT places, or they are one
    /// voice played N times at N times the level.
    func testVoicesAreSimultaneousAndSpreadApart() {
        let atOneStep = FieldAutoPlay.touches(atStep: 3, params: params(voices: 3), seed: 7)
        XCTAssertEqual(atOneStep.count, 3)
        XCTAssertEqual(Set(atOneStep.map { $0.x }).count, 3, "three voices stacked on one spot")
    }

    /// One voice must produce exactly one point — the ordinary case, and the one where an
    /// off-by-one in the spread maths would be least visible.
    func testASingleVoiceEmitsASinglePoint() {
        XCTAssertEqual(FieldAutoPlay.touches(atStep: 5, params: params(voices: 1), seed: 7).count, 1)
    }

    /// Nonsense voice counts must not crash or explode. `voices: 0` is the interesting one:
    /// it reads as "off", and the caller should not have to special-case it.
    func testDegenerateVoiceCountsAreSafe() {
        XCTAssertTrue(FieldAutoPlay.touches(atStep: 1, params: params(voices: 0), seed: 7).isEmpty)
        XCTAssertLessThanOrEqual(
            FieldAutoPlay.touches(atStep: 1, params: params(voices: 999), seed: 7).count,
            FieldAutoPlay.maxVoices,
            "an absurd voice count must be capped, not honoured — this feeds note-ons")
    }

    // MARK: - It repeats

    /// Deterministic from (step, params, seed), including the seeded `.drift` walk. Without
    /// this a take cannot be reproduced, and neither can a bug report.
    func testTheSameSeedProducesTheSamePerformance() {
        for motion in FieldAutoPlay.Motion.allCases {
            let p = params(motion: motion, bandDrift: 0.5, voices: 2)
            let a = sweep(p, steps: 24, seed: 99)
            let b = sweep(p, steps: 24, seed: 99)
            XCTAssertEqual(a, b, "\(motion) is not reproducible from its seed")
        }
    }

    /// …and a different seed must actually differ, or the seed is decoration. Only `.drift`
    /// consumes it — the other motions are deterministic curves by design, which is why this
    /// asserts on drift alone rather than pretending all four are random.
    func testTheSeedOnlyChangesTheMotionThatUsesIt() {
        let p = params(motion: .drift)
        XCTAssertNotEqual(sweep(p, steps: 24, seed: 1), sweep(p, steps: 24, seed: 2),
                          "drift must follow its seed")

        let curve = params(motion: .pendulum)
        XCTAssertEqual(sweep(curve, steps: 24, seed: 1), sweep(curve, steps: 24, seed: 2),
                       "a fixed curve must not secretly depend on the seed")
    }

    // MARK: - It cannot be handed something that kills it

    /// THE CRASH ONE. `periodSteps` is a plain `Int` on a public struct with a memberwise
    /// init, so any caller — a bio mapping, a UI field, a corrupted preset — can hand over
    /// `Int.max`. Downstream, `period * 3` builds the vertical wander's slower cycle, and
    /// Swift TRAPS on integer overflow: that is a hard crash mid-performance, not an odd
    /// sound. The `.drift` walk is the second path — it iterates once per cell, so a huge
    /// period is a huge loop on the caller's thread.
    ///
    /// This test would have crashed the whole bundle before the cap existed, which is the
    /// right kind of failure for this class of defect: loud, immediate, unmissable.
    func testAnAbsurdTraverseLengthIsCappedInsteadOfTrappingOrHanging() {
        for motion in FieldAutoPlay.Motion.allCases {
            for steps in [Int.max, Int.max / 2, 100_000, 0, -7] {
                let p = params(motion: motion, bandDrift: 1, periodSteps: steps)
                // A deliberately large step index, so the fold and the drift walk both run
                // against a real cell rather than cell 0.
                let touches = FieldAutoPlay.touches(atStep: 5_000, params: p, seed: 7)
                // Non-vacuity guard, and this file has already paid for its absence once (see
                // the NaN test above): every assertion below lives inside the loop, so an
                // empty array would make this pass while proving nothing.
                XCTAssertEqual(touches.count, 1,
                               "\(motion) at periodSteps \(steps) generated nothing")
                for t in touches {
                    XCTAssertTrue((0...1).contains(t.x) && (0...1).contains(t.y),
                                  "\(motion) at periodSteps \(steps) left the surface")
                }
            }
        }
    }

    /// The accent must survive a SHORT traverse. Integer division makes `period / 4` equal 0
    /// for periods 1–3 and 1 for 4–7, and the old `max(1, …)` floored all of them to 1 — and
    /// `cell % 1 == 0` is true for every cell, so the downbeat silently disappeared and
    /// everything came out at one velocity. A short traverse is exactly where a player still
    /// expects to hear a "one".
    ///
    /// ⚠️ 5, 6 and 7 are in this list deliberately. The first version swept 2, 3, 4, 8, 16 —
    /// because its comment said the break was at "4 or less". It is 1–7, so the sweep skipped
    /// exactly the half of the range the wrong number hid. A test built from a mistaken
    /// description tests the description, not the code.
    func testTheDownbeatSurvivesAShortTraverse() {
        for period in [2, 3, 4, 5, 6, 7, 8, 16] {
            let velocities = Set(sweep(params(periodSteps: period), steps: period * 2)
                                    .map { $0.velocity })
            XCTAssertEqual(velocities.count, 2,
                           "a \(period)-cell traverse played every note at one velocity")
        }
    }

    /// A one-cell traverse is the degenerate end and must not throw the accent away either —
    /// there is only one cell, and it is a downbeat.
    func testASingleCellTraverseIsAllDownbeat() {
        let velocities = Set(sweep(params(periodSteps: 1), steps: 8).map { $0.velocity })
        XCTAssertEqual(velocities, [0.78])
    }

    // MARK: - It survives being saved

    /// The format stamp is WRITTEN (#189). Without it, the first change that cannot be made
    /// additively has no way to tell an old payload from a new one — and by then every save
    /// already in the wild is unstamped forever.
    func testTheFormatStampIsWritten() throws {
        let data = try JSONEncoder().encode(FieldAutoPlay.Params())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, FieldAutoPlay.Params.currentSchemaVersion)
    }

    /// A payload written before a dial existed must load with that dial's DEFAULT, not throw
    /// the whole setting away — the additive-decode law (#163/#170/#189). Here: a minimal
    /// pre-stamp payload with three of eight dials and no version.
    func testAPreStampPayloadLoadsWithDefaultsForEverythingMissing() throws {
        let old = #"{"motion":"rise","density":0.9,"voices":3}"#
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self,
                                         from: try XCTUnwrap(old.data(using: .utf8)))
        XCTAssertEqual(p.motion, .rise)
        XCTAssertEqual(p.density, 0.9, accuracy: 1e-6)
        XCTAssertEqual(p.voices, 3)
        // Untouched by the payload → the factory defaults, not zeros.
        XCTAssertEqual(p.span, FieldAutoPlay.Params().span, accuracy: 1e-6)
        XCTAssertEqual(p.periodSteps, FieldAutoPlay.Params().periodSteps)
    }

    /// A motion whose case no longer exists must fall back, not throw. `decodeIfPresent` does
    /// NOT cover this — it absorbs ABSENCE, and an unknown raw value throws `dataCorrupted`.
    /// That distinction is why the decoder uses `try?`, and it is worth a test because the
    /// two read almost identically at the call site.
    func testAnUnknownMotionFallsBackInsteadOfLosingTheWholeSetting() throws {
        let future = #"{"motion":"spiral","density":0.4,"periodSteps":24}"#
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self,
                                         from: try XCTUnwrap(future.data(using: .utf8)))
        XCTAssertEqual(p.motion, FieldAutoPlay.Params().motion, "unknown motion must fall back")
        XCTAssertEqual(p.density, 0.4, accuracy: 1e-6, "the rest of the setting must survive")
        XCTAssertEqual(p.periodSteps, 24)
    }

    /// And a monster traverse must be clamped at the BOUNDARY too, so it never sits in memory
    /// looking like a legal value waiting for something to multiply it.
    func testADecodedPayloadCannotCarryAMonsterTraverse() throws {
        let hostile = #"{"periodSteps":9223372036854775807}"#
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self,
                                         from: try XCTUnwrap(hostile.data(using: .utf8)))
        XCTAssertEqual(p.periodSteps, FieldAutoPlay.maxPeriodSteps)

        let negative = #"{"periodSteps":-4}"#
        let q = try JSONDecoder().decode(FieldAutoPlay.Params.self,
                                         from: try XCTUnwrap(negative.data(using: .utf8)))
        XCTAssertGreaterThanOrEqual(q.periodSteps, 1)
    }
}
