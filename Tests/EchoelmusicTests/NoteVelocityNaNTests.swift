// NoteVelocityNaNTests.swift
// Echoel — ONE law, pinned at every place a note's velocity is clamped:
// a NaN must never come back out of a clamp.
//
// WHY THIS IS NOT PEDANTRY, and why it only became reachable now. CLAUDE.md states
// the rule and the reason: `max(x, y)` is `y >= x ? y : x`, so the argument ORDER
// decides NaN behaviour. `max(0, NaN)` returns 0 (safe) but `max(NaN, 0)` returns
// NaN — and `min(max(v, 0), 1)`, the idiom used throughout the note model, is the
// unsafe order. A NaN therefore passed straight through every one of those clamps.
//
// It used to be harmless-ish because nothing downstream cared much. Since 6f2932d it
// does: `EchoelPolyDDSP.spawnVoice` computes `pow(v / nominalVelocity, expo * curve)`
// from exactly this number and stores the result as the voice's `velocityGain`. A NaN
// there yields a NaN gain, NaN samples, and poisoned oscillator/filter state — the
// permanent-silence class this project has already shipped twice (#22, #29). Making
// the faders audible is what put a note's velocity on the audio path for real.
//
// THE FIX IS THE EXISTING UTILITY, not a new one: `Core/FloatingPointClamp.swift`'s
// `clamped(to:)` maps NaN to the range's lower bound. Note the consequence, stated
// plainly because it differs per site: for `Note`/`NoteHit` the lower bound is 0, so a
// broken velocity yields a SILENT note; for BioComposer's humanizers the range is
// 0.05...1 (their documented musical window), so a broken velocity yields the quietest
// audible note. Both fail predictably instead of poisoning a voice — that is the point.
//
// NOT changed, and deliberately so: `NoteTransform`, `IntroAttenuation` and the mixer
// bake in `EchoelStudioView` all write `min(1, max(0, …))` — the SAFE order, which
// already collapses NaN to 0. They are listed here so a later reader does not "fix"
// working code, and so the difference between the two spellings stays on the record.

import XCTest
@testable import Echoelmusic

final class NoteVelocityNaNTests: XCTestCase {

    // MARK: The model type itself

    func testNote_stepInit_clampsANaNVelocityToSilenceRatherThanPassingItThrough() {
        let n = Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: .nan)
        XCTAssertFalse(n.velocity.isNaN, "a NaN must not survive the clamp")
        XCTAssertEqual(n.velocity, 0, "NaN maps to the range's lower bound: a silent note")
    }

    func testNote_tickInit_clampsANaNVelocityToSilence() {
        let n = Note(pitch: 60, startTick: 0, lengthTicks: 480, velocity: .nan)
        XCTAssertFalse(n.velocity.isNaN)
        XCTAssertEqual(n.velocity, 0)
    }

    /// Belt-and-braces: a standard `JSONEncoder` REFUSES to write NaN, so a stock Echoel
    /// save file cannot contain one. The decoder is still hardened, because a note can
    /// arrive from an import or a hand-edited file, and a poisoned velocity that reaches
    /// the voice is silent-forever rather than merely wrong.
    func testNote_decoder_clampsANaNVelocityToSilence() throws {
        let json = Data(#"{"pitch":60,"startTick":0,"lengthTicks":480,"velocity":"nan"}"#.utf8)
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                    negativeInfinity: "-inf",
                                                                    nan: "nan")
        let n = try dec.decode(Note.self, from: json)
        XCTAssertFalse(n.velocity.isNaN)
        XCTAssertEqual(n.velocity, 0)
    }

    /// `NoteHit` is what the operator engine actually hands the sequencer — the roll's
    /// note is only the template. A clamp here that leaks NaN reaches the voice directly.
    func testNoteHit_clampsANaNVelocityToSilence() {
        let hit = NoteHit(offsetTicks: 0, lengthTicks: 480, velocity: .nan)
        XCTAssertFalse(hit.velocity.isNaN)
        XCTAssertEqual(hit.velocity, 0)
    }

    // MARK: The reachable path — the composer's per-note dynamics

    /// THE ONE THAT IS ACTUALLY REACHABLE IN PRODUCTION. These three multiply a note's
    /// velocity by a bio-derived factor and re-clamp; a single non-finite bio value (a
    /// bad rPPG frame) therefore wrote NaN into the take. The composer is where a NaN
    /// gets MADE, so the clamp there is the one that has to hold.
    func testShapeBarDynamics_cannotEmitANaNVelocity() {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: .nan)]
        let out = BioComposer.shapeBarDynamics(notes, depth: 0.5, stepCount: 16)
        XCTAssertFalse(out[0].velocity.isNaN, "a NaN in must not be a NaN out")
        XCTAssertEqual(out[0].velocity, 0.05, accuracy: 1e-6,
                       "this clamp's window is [0.05, 1] — NaN lands on its floor, not on 0")
    }

    func testHumanizeVelocity_cannotEmitANaNVelocity() {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: .nan)]
        let out = BioComposer.humanizeVelocity(notes, amount: 1, seed: 7)
        XCTAssertFalse(out[0].velocity.isNaN)
        XCTAssertEqual(out[0].velocity, 0.05, accuracy: 1e-6)
    }

    func testHrvHumanize_cannotEmitANaNVelocity() {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: .nan)]
        let out = BioComposer.hrvHumanize(notes, hrvNormalized: 1, seed: 7)
        XCTAssertFalse(out[0].velocity.isNaN)
        XCTAssertEqual(out[0].velocity, 0.05, accuracy: 1e-6)
    }

    // MARK: Negative controls — the clamps must still clamp ordinary values

    /// If the NaN guard were implemented by short-circuiting too early, these would go
    /// red. They are the reason this is a swap to `clamped(to:)` and not an `isNaN`
    /// early-return bolted in front of the existing expression.
    func testOrdinaryVelocitiesAreUnaffectedByTheNaNGuard() {
        XCTAssertEqual(Note(pitch: 60, startStep: 0, velocity: 0.42).velocity, 0.42, accuracy: 1e-6)
        XCTAssertEqual(Note(pitch: 60, startStep: 0, velocity: 5).velocity, 1, "still clamps above")
        XCTAssertEqual(Note(pitch: 60, startStep: 0, velocity: -5).velocity, 0, "still clamps below")
        XCTAssertEqual(NoteHit(offsetTicks: 0, lengthTicks: 480, velocity: 0.42).velocity,
                       0.42, accuracy: 1e-6)
    }

    /// The composer's floor is a real musical decision, not an artefact of the NaN fix:
    /// a genuinely quiet note still gets lifted to 0.05, exactly as before.
    func testComposerFloorStillAppliesToFiniteValues() {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.001)]
        let out = BioComposer.humanizeVelocity(notes, amount: 1, seed: 7)
        XCTAssertEqual(out[0].velocity, 0.05, accuracy: 1e-6,
                       "0.001 · (1 ± 0.18) is still below the 0.05 floor")
    }

    /// The humanize AMOUNT is the other way a NaN entered the composer's velocity maths:
    /// a NaN jitter made `1 + v * span` NaN for EVERY note in the take, not just one.
    func testHumanizer_clampsANaNJitterToNoJitter() {
        XCTAssertEqual(Humanizer(timingTicks: 0, velocityJitter: .nan).velocityJitter, 0,
                       "a broken jitter amount means no humanization, not a broken take")
    }

    /// INFINITY is the other non-finite input, and it was ALREADY handled correctly by
    /// the old spelling (`max(inf, 0)` is inf, `min(inf, 1)` is 1). Pinned so the swap
    /// to `clamped(to:)` is proven not to have changed it.
    func testInfinityStillClampsToTheUpperBound() {
        XCTAssertEqual(Note(pitch: 60, startStep: 0, velocity: .infinity).velocity, 1)
        XCTAssertEqual(Note(pitch: 60, startStep: 0, velocity: -.infinity).velocity, 0)
    }
}
