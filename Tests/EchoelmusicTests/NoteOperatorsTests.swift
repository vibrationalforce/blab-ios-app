// NoteOperatorsTests.swift
// Echoel — per-note operators (chance / repeats+ramp / occurrence), the
// "Ableton 20" A1 model. Everything must be DETERMINISTIC: same seed + loop
// index → identical hits, across processes (no Hasher, no Math.random).

import XCTest
import Foundation
@testable import Echoelmusic

final class NoteOperatorsTests: XCTestCase {

    private let fixedID = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!

    private func note(length: Int = 480, velocity: Float = 0.8) -> Note {
        Note(id: fixedID, pitch: 60, startTick: 0, lengthTicks: length, velocity: velocity)
    }

    // MARK: Defaults / transparency

    func testDefault_isTransparent_playsPlainlyEveryLoop() {
        let ops = NoteOperators()
        XCTAssertTrue(ops.isDefault)
        for loop in 0..<8 {
            let hits = ops.hits(for: note(), loopIndex: loop, seed: 42)
            XCTAssertEqual(hits, [NoteHit(offsetTicks: 0, lengthTicks: 480, velocity: 0.8)],
                           "default operators must be a no-op on loop \(loop)")
        }
    }

    func testInit_clampsEverything() {
        let ops = NoteOperators(chance: 7, repeats: 999, repeatRamp: -9,
                                occurrencePeriod: 0, occurrencePhase: 5)
        XCTAssertEqual(ops.chance, 1)
        XCTAssertEqual(ops.repeats, NoteOperators.repeatsRange.upperBound)
        XCTAssertEqual(ops.repeatRamp, -1)
        XCTAssertEqual(ops.occurrencePeriod, 1)
        XCTAssertEqual(ops.occurrencePhase, 0, "phase must clamp inside the period")
        let nan = NoteOperators(chance: .nan, repeatRamp: .infinity)
        XCTAssertEqual(nan.chance, 1); XCTAssertEqual(nan.repeatRamp, 0)
    }

    // MARK: Occurrence

    func testOccurrence_everySecondLoop_phase1() {
        let ops = NoteOperators(occurrencePeriod: 2, occurrencePhase: 1)
        for loop in 0..<8 {
            let hits = ops.hits(for: note(), loopIndex: loop, seed: 1)
            if loop % 2 == 1 {
                XCTAssertEqual(hits.count, 1, "loop \(loop) is the matching phase")
            } else {
                XCTAssertTrue(hits.isEmpty, "loop \(loop) must be silent")
            }
        }
    }

    // MARK: Chance

    func testChance_isDeterministic_sameInputsSameOutcome() {
        let ops = NoteOperators(chance: 0.5)
        for loop in 0..<16 {
            let a = ops.hits(for: note(), loopIndex: loop, seed: 99)
            let b = ops.hits(for: note(), loopIndex: loop, seed: 99)
            XCTAssertEqual(a, b, "chance roll must be reproducible (loop \(loop))")
        }
    }

    func testChance_zeroNeverPlays_oneAlwaysPlays() {
        let never = NoteOperators(chance: 0)
        let always = NoteOperators(chance: 1)
        for loop in 0..<16 {
            XCTAssertTrue(never.hits(for: note(), loopIndex: loop, seed: 7).isEmpty)
            XCTAssertFalse(always.hits(for: note(), loopIndex: loop, seed: 7).isEmpty)
        }
    }

    func testChance_halfPlaysRoughlyHalfOverManyLoops() {
        let ops = NoteOperators(chance: 0.5)
        let played = (0..<400).filter { !ops.hits(for: note(), loopIndex: $0, seed: 3).isEmpty }.count
        XCTAssertGreaterThan(played, 140, "0.5 chance must not starve")
        XCTAssertLessThan(played, 260, "0.5 chance must not saturate")
    }

    func testChance_variesAcrossLoops_notFrozen() {
        // The dice roll must differ per loop pass (a frozen roll would play
        // all-or-nothing forever — the point is a living pattern).
        let ops = NoteOperators(chance: 0.5)
        let outcomes = Set((0..<32).map { ops.hits(for: note(), loopIndex: $0, seed: 3).isEmpty })
        XCTAssertEqual(outcomes.count, 2, "both play and silence must occur across loops")
    }

    // MARK: Repeats + ramp

    func testRepeats_fourEvenHits_flatRamp() {
        let ops = NoteOperators(repeats: 4)
        let hits = ops.hits(for: note(length: 480, velocity: 0.8), loopIndex: 0, seed: 1)
        XCTAssertEqual(hits.count, 4)
        XCTAssertEqual(hits.map(\.offsetTicks), [0, 120, 240, 360])
        XCTAssertEqual(hits.map(\.lengthTicks), [120, 120, 120, 120])
        for h in hits { XCTAssertEqual(h.velocity, 0.8, accuracy: 1e-6) }
    }

    func testRepeats_crescendoRamp_lastHitIsScaled() {
        let ops = NoteOperators(repeats: 3, repeatRamp: 0.5)
        let hits = ops.hits(for: note(length: 300, velocity: 0.6), loopIndex: 0, seed: 1)
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits[0].velocity, 0.6, accuracy: 1e-6, "first hit keeps the note velocity")
        XCTAssertEqual(hits[1].velocity, 0.75, accuracy: 1e-6, "midpoint of the ramp")
        XCTAssertEqual(hits[2].velocity, 0.9, accuracy: 1e-6, "last hit ×(1+ramp)")
    }

    func testRepeats_decrescendoToZero_clampsNotNegative() {
        let ops = NoteOperators(repeats: 2, repeatRamp: -1)
        let hits = ops.hits(for: note(velocity: 0.8), loopIndex: 0, seed: 1)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[1].velocity, 0, accuracy: 1e-6)
    }

    func testRepeats_shortNote_hitLengthNeverBelowOneTick() {
        let ops = NoteOperators(repeats: 32)
        let hits = ops.hits(for: note(length: 8), loopIndex: 0, seed: 1)
        XCTAssertEqual(hits.count, 32)
        XCTAssertTrue(hits.allSatisfy { $0.lengthTicks >= 1 })
    }

    // MARK: Determinism across notes

    func testDifferentNotes_getIndependentDiceRolls() {
        // Two notes with 0.5 chance must not be locked together — otherwise a
        // whole chord would flicker as one unit.
        let ops = NoteOperators(chance: 0.5)
        let other = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                         pitch: 64, startTick: 0, lengthTicks: 480, velocity: 0.8)
        var differed = false
        for loop in 0..<64 {
            let a = ops.hits(for: note(), loopIndex: loop, seed: 5).isEmpty
            let b = ops.hits(for: other, loopIndex: loop, seed: 5).isEmpty
            if a != b { differed = true; break }
        }
        XCTAssertTrue(differed, "distinct note IDs must produce independent rolls")
    }

    // MARK: Codable / Note integration

    func testNote_withoutOperators_encodesByteIdenticalToLegacyShape() throws {
        // The operators key must be ABSENT for plain notes so pre-operator
        // builds read new clips unchanged.
        let n = note()
        let data = try JSONEncoder().encode(n)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("operators"))
    }

    func testNote_operatorsRoundTrip() throws {
        var n = note()
        n.operators = NoteOperators(chance: 0.7, repeats: 3, repeatRamp: 0.25,
                                    occurrencePeriod: 4, occurrencePhase: 2)
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(decoded, n)
        XCTAssertEqual(decoded.operators?.repeats, 3)
    }

    func testLegacyNoteJSON_decodesWithNilOperators() throws {
        let legacy = Data("""
        {"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","pitch":60,
         "startTick":0,"lengthTicks":480,"velocity":0.8,"role":"harmony"}
        """.utf8)
        let n = try JSONDecoder().decode(Note.self, from: legacy)
        XCTAssertNil(n.operators)
    }

    func testOperatorsJSON_missingFieldsDecodeAsDefaults() throws {
        let partial = Data(#"{"chance":0.4}"#.utf8)
        let ops = try JSONDecoder().decode(NoteOperators.self, from: partial)
        XCTAssertEqual(ops.chance, 0.4)
        XCTAssertEqual(ops.repeats, 1)
        XCTAssertEqual(ops.occurrencePeriod, 1)
    }

    func testUUIDFold_isStableAcrossCalls() {
        // Process-stable seeding is the whole contract — Hasher would break it.
        XCTAssertEqual(NoteOperators.fold(fixedID), NoteOperators.fold(fixedID))
        XCTAssertNotEqual(NoteOperators.fold(fixedID), NoteOperators.fold(UUID()))
    }

    // MARK: Bio-bent chance (A4 — coherence moves the dice threshold)

    func testBioBentChance_neutralAtMidCoherence() {
        let ops = NoteOperators(chance: 0.6)
        XCTAssertEqual(ops.bioBentChance(coherence: 0.5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(ops.bioBentChance(coherence: nil), 0.6, accuracy: 1e-9)
    }

    func testBioBentChance_highCoherenceFillsOut_lowThins() {
        let ops = NoteOperators(chance: 0.5)
        XCTAssertEqual(ops.bioBentChance(coherence: 1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ops.bioBentChance(coherence: 0.0), 0.0, accuracy: 1e-9)
        XCTAssertGreaterThan(ops.bioBentChance(coherence: 0.8), 0.5)
        XCTAssertLessThan(ops.bioBentChance(coherence: 0.2), 0.5)
    }

    func testBioBentChance_neverBendsCertainty() {
        // Muted stays muted, certain stays certain, plain notes never flicker.
        XCTAssertEqual(NoteOperators(chance: 0).bioBentChance(coherence: 1.0), 0)
        XCTAssertEqual(NoteOperators(chance: 1).bioBentChance(coherence: 0.0), 1)
    }

    func testBioBentChance_clampsAndGuardsBadInput() {
        let ops = NoteOperators(chance: 0.9)
        XCTAssertEqual(ops.bioBentChance(coherence: 7), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ops.bioBentChance(coherence: .nan), 0.9, accuracy: 1e-9)
    }

    func testHits_withCoherenceOne_playsAnyNonZeroChance() {
        // Threshold 0.5 + bend +0.5 = 1 → the roll (< 1) always passes.
        let ops = NoteOperators(chance: 0.5)
        for loop in 0..<16 {
            XCTAssertFalse(ops.hits(for: note(), loopIndex: loop, seed: 7,
                                    coherence: 1.0).isEmpty)
        }
    }

    func testHits_withCoherenceZero_silencesHalfChance() {
        let ops = NoteOperators(chance: 0.5)
        for loop in 0..<16 {
            XCTAssertTrue(ops.hits(for: note(), loopIndex: loop, seed: 7,
                                   coherence: 0.0).isEmpty)
        }
    }

    // MARK: Playback gate (PianoRollModel.operatorAllows — the wiring law)

    func testGate_plainNote_alwaysPlays() {
        let n = note()   // operators == nil
        for pass in [-1, 0, 1, 7] {
            XCTAssertTrue(PianoRollModel.operatorAllows(n, loopPass: pass, seed: 1))
        }
    }

    func testGate_occurrence_gatesAlternatePasses() {
        var n = note()
        n.operators = NoteOperators(occurrencePeriod: 2, occurrencePhase: 0)
        XCTAssertTrue(PianoRollModel.operatorAllows(n, loopPass: 0, seed: 1))
        XCTAssertFalse(PianoRollModel.operatorAllows(n, loopPass: 1, seed: 1))
        XCTAssertTrue(PianoRollModel.operatorAllows(n, loopPass: 2, seed: 1))
    }

    func testGate_negativeLoopPass_clampsToFirstPass() {
        // Before the first bar wrap the model's clock reads −1 — the gate must
        // treat that as pass 0 (play, if phase 0 matches), never crash or gate.
        var n = note()
        n.operators = NoteOperators(occurrencePeriod: 4, occurrencePhase: 0)
        XCTAssertTrue(PianoRollModel.operatorAllows(n, loopPass: -1, seed: 1))
    }

    func testGate_defaultOperators_identicalToNil() {
        var withDefault = note()
        withDefault.operators = NoteOperators()
        for pass in 0..<4 {
            XCTAssertEqual(
                PianoRollModel.operatorAllows(withDefault, loopPass: pass, seed: 9),
                PianoRollModel.operatorAllows(note(), loopPass: pass, seed: 9))
        }
    }

    // MARK: A5 — bio-per-note expression (coherence + breath shape dynamics)

    func testExpression_depthZero_isIdentity() {
        let ops = NoteOperators()   // all depths 0
        for c: Double in [0, 0.5, 1] {
            let e = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: c, breath: 0.5)
            XCTAssertEqual(e, NoteExpression(), "no depth → identity regardless of body")
        }
    }

    func testExpression_nilBio_isIdentity() {
        // No body at all → identity even with depths set (mirrors the bioBentChance nil-guard).
        let ops = NoteOperators(velocityDepth: 1, timingDepth: 1, filterDepth: 1)
        let e = ops.expression(for: note(), loopIndex: 3, seed: 1, coherence: nil, breath: nil)
        XCTAssertEqual(e, NoteExpression())
    }

    func testExpression_neutralAtMidCoherence() {
        // Coherence 0.5 + breath at a cycle end (hump 0) → the un-bent centre (scale 1),
        // parity with testBioBentChance_neutralAtMidCoherence.
        let ops = NoteOperators(velocityDepth: 0.5)
        let e = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: 0.5, breath: 0)
        XCTAssertEqual(e.velocityScale, 1, accuracy: 1e-6)
    }

    func testExpression_highCoherenceLiftsVelocity_lowThins() {
        let ops = NoteOperators(velocityDepth: 0.5)
        let hi = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: 0.9, breath: nil)
        let lo = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: 0.1, breath: nil)
        XCTAssertGreaterThan(hi.velocityScale, 1, "settled body lifts velocity")
        XCTAssertLessThan(lo.velocityScale, 1, "unsettled body thins it")
        // Symmetric around the centre.
        XCTAssertEqual(hi.velocityScale - 1, 1 - lo.velocityScale, accuracy: 1e-6)
    }

    func testExpression_isDeterministic_sameInputsSameOutput() {
        let ops = NoteOperators(velocityDepth: 0.5, timingDepth: 0.5, filterDepth: 0.5)
        let a = ops.expression(for: note(), loopIndex: 4, seed: 77, coherence: 0.7, breath: 0.3)
        let b = ops.expression(for: note(), loopIndex: 4, seed: 77, coherence: 0.7, breath: 0.3)
        XCTAssertEqual(a, b, "process-stable: SeededRNG + UUID-fold, never Hasher")
    }

    func testExpression_decorrelatedFromChanceRoll() {
        // The expression jitter (on micro-timing) uses a DISTINCT salt, so it is not
        // locked to the chance roll's play/silence outcome — a whole gated chord must
        // not swell/thin as one block.
        let ops = NoteOperators(chance: 0.5, timingDepth: 0.8)
        var chancePlaysButTimingNegative = false
        var chanceSilentButTimingPositive = false
        for loop in 0..<128 {
            let plays = !ops.hits(for: note(), loopIndex: loop, seed: 5).isEmpty
            let timing = ops.expression(for: note(), loopIndex: loop, seed: 5,
                                        coherence: 0.5, breath: 0.5).timingOffsetTicks
            if plays && timing < 0 { chancePlaysButTimingNegative = true }
            if !plays && timing > 0 { chanceSilentButTimingPositive = true }
        }
        XCTAssertTrue(chancePlaysButTimingNegative && chanceSilentButTimingPositive,
                      "timing jitter must not track the chance dice")
    }

    func testExpression_clampsAndGuardsBadInput() {
        let ops = NoteOperators(velocityDepth: 1, timingDepth: 1, filterDepth: 1)
        for (c, b): (Double, Double) in [(7, 3), (.nan, -5), (-2, .infinity)] {
            let e = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: c, breath: b)
            XCTAssertTrue(e.velocityScale.isFinite)
            XCTAssertGreaterThanOrEqual(e.velocityScale, NoteOperators.velScaleMin)
            XCTAssertLessThanOrEqual(e.velocityScale, NoteOperators.velScaleMax)
            XCTAssertLessThanOrEqual(abs(e.timingOffsetTicks), NoteOperators.maxTimingTicks)
            if let br = e.brightness { XCTAssertTrue(br >= 0 && br <= 1) }
        }
    }

    func testExpression_breathShaping_humpNotSaw() {
        // sin hump: phase 0 and 1 are the cycle-end value; phase 0.5 is the peak.
        let ops = NoteOperators(velocityDepth: 0.5)
        let atZero = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: 0.5, breath: 0)
        let atOne = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: 0.5, breath: 1)
        let atHalf = ops.expression(for: note(), loopIndex: 0, seed: 1, coherence: 0.5, breath: 0.5)
        XCTAssertEqual(atZero.velocityScale, atOne.velocityScale, accuracy: 1e-6, "cycle ends match")
        XCTAssertGreaterThan(atHalf.velocityScale, atZero.velocityScale, "mid-breath is the peak")
    }

    func testExpression_isDefaultIncludesExpressionDepths() {
        XCTAssertTrue(NoteOperators().isDefault)
        XCTAssertFalse(NoteOperators(velocityDepth: 0.3).isDefault)
        XCTAssertFalse(NoteOperators(timingDepth: 0.3).isDefault)
        XCTAssertFalse(NoteOperators(filterDepth: 0.3).isDefault)
    }

    func testOperatorsJSON_chanceOnly_byteIdenticalAfterExpressionFields() throws {
        // A chance/repeat operator must serialize with NO *Depth key, so its JSON stays
        // byte-identical to pre-A5 (old builds keep ignoring absent keys).
        let ops = NoteOperators(chance: 0.7, repeats: 3, repeatRamp: 0.25)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(ops), encoding: .utf8))
        XCTAssertFalse(json.contains("Depth"), "no expression key emitted for a chance-only operator")
    }

    func testOperators_expressionRoundTrip() throws {
        let ops = NoteOperators(chance: 0.8, velocityDepth: 0.4, timingDepth: -0.3, filterDepth: 0.6)
        let back = try JSONDecoder().decode(NoteOperators.self, from: JSONEncoder().encode(ops))
        XCTAssertEqual(back, ops)
        // Legacy JSON without the depth keys decodes to zero depths.
        let legacy = try JSONDecoder().decode(NoteOperators.self, from: Data(#"{"chance":0.5}"#.utf8))
        XCTAssertEqual(legacy.velocityDepth, 0)
        XCTAssertEqual(legacy.timingDepth, 0)
        XCTAssertEqual(legacy.filterDepth, 0)
    }

    // MARK: A5 gate helper (PianoRollModel.noteExpression)

    func testGate_noteExpression_plainNote_isIdentity() {
        let n = note()   // operators == nil
        for pass in [-1, 0, 5] {
            let e = PianoRollModel.noteExpression(n, loopPass: pass, seed: 1,
                                                  coherence: 0.9, breath: 0.5)
            XCTAssertEqual(e, NoteExpression(), "a plain note never expresses")
        }
    }

    func testGate_noteExpression_scalesVelocityWithCoherence() {
        var n = note()
        n.operators = NoteOperators(velocityDepth: 0.5)
        let hi = PianoRollModel.noteExpression(n, loopPass: 0, seed: 1, coherence: 0.9, breath: nil)
        let lo = PianoRollModel.noteExpression(n, loopPass: 0, seed: 1, coherence: 0.1, breath: nil)
        let none = PianoRollModel.noteExpression(n, loopPass: 0, seed: 1, coherence: nil, breath: nil)
        XCTAssertGreaterThan(hi.velocityScale, 1)
        XCTAssertLessThan(lo.velocityScale, 1)
        XCTAssertEqual(none.velocityScale, 1, "no body → identity")
    }

    // MARK: - A1 per-note Chance paint-lane (PianoRollModel.setChance / .chance)

    @MainActor
    func testSetChance_createsClampedOperators_andReadsBack() {
        let m = PianoRollModel()
        m.add(pitch: 60, startStep: 0)
        guard let id = m.notes.first?.id else { return XCTFail("note missing") }
        XCTAssertEqual(m.chance(id: id), 1, "a plain note reads full chance")

        m.setChance(id: id, 1.7)                       // out of range → clamps to 1 → default → nil
        XCTAssertNil(m.notes.first?.operators, "chance 1 stays a plain note")

        m.setChance(id: id, 0.5)
        XCTAssertEqual(m.notes.first?.operators?.chance, 0.5)
        XCTAssertEqual(m.chance(id: id), 0.5, "read-back matches")
    }

    @MainActor
    func testSetChance_collapsesToNilWhenDefault_butKeepsOtherOperators() {
        let m = PianoRollModel()
        m.add(pitch: 62, startStep: 0)
        guard let id = m.notes.first?.id else { return XCTFail("note missing") }

        // A note that already ratchets (inject repeats via the public op path).
        m.applyOp(ids: [id]) { sel in
            sel.map { var n = $0; n.operators = NoteOperators(repeats: 4); return n }
        }
        // Setting chance must PRESERVE the repeats.
        m.setChance(id: id, 0.8)
        XCTAssertEqual(m.notes.first?.operators?.chance, 0.8)
        XCTAssertEqual(m.notes.first?.operators?.repeats, 4, "chance edit preserves repeats")

        // Back to chance 1 while repeats>1 stays a NON-default operator (not nil).
        m.setChance(id: id, 1)
        XCTAssertEqual(m.notes.first?.operators?.repeats, 4, "still ratcheting → operators survive")

        // Reset repeats too → now default → collapses to nil (byte-identical plain note).
        m.applyOp(ids: [id]) { sel in
            sel.map { var n = $0; n.operators = nil; return n }
        }
        m.setChance(id: id, 0.5)
        m.setChance(id: id, 1)
        XCTAssertNil(m.notes.first?.operators, "fully default operator bag collapses to nil")
    }
}
