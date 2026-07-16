// NoteTests.swift
// Echoelmusic — the shared Note model + piano-roll editing API.

import XCTest
@testable import Echoelmusic

final class NoteTests: XCTestCase {

    func testInit_clampsLengthAndVelocity() {
        let a = Note(pitch: 60, startStep: 0, lengthSteps: 0, velocity: 2)
        XCTAssertEqual(a.lengthSteps, 1, "length clamps to >= 1")
        XCTAssertEqual(a.velocity, 1, "velocity clamps to <= 1")

        let b = Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: -1)
        XCTAssertEqual(b.lengthSteps, 4)
        XCTAssertEqual(b.velocity, 0, "velocity clamps to >= 0")
    }

    func testEndStepAndCovers() {
        let note = Note(pitch: 60, startStep: 4, lengthSteps: 3)
        XCTAssertEqual(note.endStep, 7, "endStep is start + length (exclusive)")
        XCTAssertFalse(note.covers(step: 3))
        XCTAssertTrue(note.covers(step: 4), "start is inclusive")
        XCTAssertTrue(note.covers(step: 6))
        XCTAssertFalse(note.covers(step: 7), "end is exclusive")
    }

    func testCodableRoundTrip() throws {
        let note = Note(pitch: 67, startStep: 2, lengthSteps: 5, velocity: 0.7)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded, note)
    }

    // MARK: PPQ precision

    func testStepInit_mapsToTicks() {
        let n = Note(pitch: 60, startStep: 2, lengthSteps: 4)
        XCTAssertEqual(n.startTick, 2 * Note.ticksPerStep)
        XCTAssertEqual(n.lengthTicks, 4 * Note.ticksPerStep)
        // Step views round-trip exactly for on-grid notes.
        XCTAssertEqual(n.startStep, 2)
        XCTAssertEqual(n.lengthSteps, 4)
    }

    func testTickInit_subStepReadsAsOneStep() {
        // A note half a step long, starting a quarter-step in.
        let n = Note(pitch: 60, startTick: Note.ticksPerStep / 4,
                     lengthTicks: Note.ticksPerStep / 2)
        XCTAssertEqual(n.startStep, 0, "rounds to nearest step")
        XCTAssertEqual(n.lengthSteps, 1, "sub-step length still reads as one step")
        XCTAssertEqual(n.endTick, Note.ticksPerStep / 4 + Note.ticksPerStep / 2)
    }

    func testTickInit_clampsToValidRange() {
        let n = Note(pitch: 200, startTick: -10, lengthTicks: 0, velocity: 9)
        XCTAssertEqual(n.pitch, 127)
        XCTAssertEqual(n.startTick, 0)
        XCTAssertEqual(n.lengthTicks, 1)
        XCTAssertEqual(n.velocity, 1)
    }

    func testNudgeClampsAtZero() {
        let n = Note(pitch: 60, startStep: 1)
        XCTAssertEqual(n.nudged(byTicks: -10).startTick, Note.ticksPerStep - 10)
        XCTAssertEqual(n.nudged(byTicks: -100000).startTick, 0, "clamps at 0")
    }

    func testQuantizeStartToGrid() {
        // 10 ticks past the second step → snaps back to the step boundary.
        let n = Note(pitch: 60, startTick: Note.ticksPerStep * 2 + 10, lengthTicks: 120)
        let q = n.quantizedStart(toTicks: Note.ticksPerStep)
        XCTAssertEqual(q.startTick, Note.ticksPerStep * 2)
    }

    func testCodable_decodesLegacyStepOnlyClip() throws {
        // A clip persisted by a pre-PPQ build (only startStep/lengthSteps).
        let legacy = #"{"id":"\#(UUID().uuidString)","pitch":64,"startStep":3,"lengthSteps":2,"velocity":0.5}"#
        let decoded = try JSONDecoder().decode(Note.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.pitch, 64)
        XCTAssertEqual(decoded.startTick, 3 * Note.ticksPerStep)
        XCTAssertEqual(decoded.lengthTicks, 2 * Note.ticksPerStep)
    }

    func testCodable_tickRoundTripPreservesSubStep() throws {
        let note = Note(pitch: 60, startTick: 50, lengthTicks: 70, velocity: 0.7)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded.startTick, 50)
        XCTAssertEqual(decoded.lengthTicks, 70)
        XCTAssertEqual(decoded, note)
    }
}

#if canImport(SwiftUI)
@MainActor
final class PianoRollModelTests: XCTestCase {

    func testAdd_clampsLengthToBarBoundary() {
        let model = PianoRollModel()
        let note = model.add(pitch: 60, startStep: 14, lengthSteps: 8)
        XCTAssertEqual(note.lengthSteps, PianoRollModel.stepCount - 14,
                       "length is clamped so the note never crosses the loop boundary")
    }

    func testNoteAtPitchStep_findsCoveringNote() {
        let model = PianoRollModel()
        model.add(pitch: 60, startStep: 4, lengthSteps: 4) // covers 4..7
        XCTAssertNotNil(model.note(atPitch: 60, step: 6))
        XCTAssertNil(model.note(atPitch: 60, step: 8))
        XCTAssertNil(model.note(atPitch: 61, step: 6), "different pitch")
    }

    func testRemoveAndEdit() {
        let model = PianoRollModel()
        let note = model.add(pitch: 62, startStep: 0, lengthSteps: 2, velocity: 0.5)
        model.setVelocity(id: note.id, 0.9)
        model.setLength(id: note.id, lengthSteps: 6)
        let edited = model.notes.first { $0.id == note.id }
        XCTAssertEqual(edited?.velocity, 0.9)
        XCTAssertEqual(edited?.lengthSteps, 6)

        model.remove(id: note.id)
        XCTAssertTrue(model.notes.isEmpty)
    }

    // MARK: - move (#58 Slice 2: drag-to-reposition)

    func testMove_repositionsPitchAndStart_preservingLength() {
        let model = PianoRollModel()
        let note = model.add(pitch: 60, startStep: 2, lengthSteps: 3, velocity: 0.7)
        model.move(id: note.id, toPitch: 67, toStartStep: 5)
        let m = model.notes.first { $0.id == note.id }
        XCTAssertEqual(m?.pitch, 67)
        XCTAssertEqual(m?.startStep, 5)
        XCTAssertEqual(m?.lengthSteps, 3, "length is preserved by a move")
        XCTAssertEqual(m?.velocity, 0.7, "velocity is untouched by a move")
    }

    func testMove_clampsPitchToRollRange() {
        let model = PianoRollModel()
        let note = model.add(pitch: 60, startStep: 0)
        model.move(id: note.id, toPitch: 999, toStartStep: 0)
        XCTAssertEqual(model.notes.first?.pitch, PianoRollModel.highPitch)
        model.move(id: note.id, toPitch: -5, toStartStep: 0)
        XCTAssertEqual(model.notes.first?.pitch, PianoRollModel.lowPitch)
    }

    func testMove_clampsStartSoTailStaysInBar() {
        let model = PianoRollModel()
        let note = model.add(pitch: 60, startStep: 0, lengthSteps: 4)
        // Pushing a 4-step note to step 15 must clamp so it ends at the boundary.
        model.move(id: note.id, toPitch: 60, toStartStep: 15)
        XCTAssertEqual(model.notes.first?.startStep, PianoRollModel.stepCount - 4)
        // Negative start clamps to 0.
        model.move(id: note.id, toPitch: 60, toStartStep: -3)
        XCTAssertEqual(model.notes.first?.startStep, 0)
    }

    func testMove_missingID_isNoOp() {
        let model = PianoRollModel()
        let note = model.add(pitch: 60, startStep: 2, lengthSteps: 2)
        model.move(id: UUID(), toPitch: 70, toStartStep: 8)   // unknown id
        XCTAssertEqual(model.notes.first?.pitch, 60)
        XCTAssertEqual(model.notes.first?.startStep, 2)
        _ = note
    }

    func testRollSelection_collapsesZeroToNone_oneToSingle_manyToGroup() {
        // The invariant the marquee relies on: exactly-one collapses to .single
        // (so a 1-note marquee is editable, not an editor-less dead state), and
        // .group only ever holds ≥2. Fixes the two reviewer MEDIUMs structurally.
        let a = UUID(), b = UUID()
        XCTAssertEqual(RollSelection(ids: []), .none)
        XCTAssertEqual(RollSelection(ids: [a]), .single(a))
        XCTAssertEqual(RollSelection(ids: [a, b]), .group([a, b]))
        XCTAssertTrue(RollSelection.single(a).contains(a))
        XCTAssertFalse(RollSelection.single(a).contains(b))
        XCTAssertTrue(RollSelection.group([a, b]).contains(b))
        XCTAssertEqual(RollSelection.single(a).single, a)
        XCTAssertNil(RollSelection.none.group)
    }

    func testRemoveIDs_deletesTheSet_keepsOthers_emptyIsNoOp() {
        let model = PianoRollModel()
        let a = model.add(pitch: 60, startStep: 0)
        let b = model.add(pitch: 62, startStep: 4)
        let c = model.add(pitch: 64, startStep: 8)
        model.remove(ids: [])                        // no-op
        XCTAssertEqual(model.notes.count, 3)
        model.remove(ids: [a.id, c.id])              // group delete
        XCTAssertEqual(model.notes.map(\.id), [b.id], "only b survives")
    }

    func testLoadReplacesNotes() {
        let model = PianoRollModel()
        model.add(pitch: 60, startStep: 0)
        model.load([Note(pitch: 72, startStep: 8, lengthSteps: 2)])
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.notes.first?.pitch, 72)
    }

    // MARK: - Multi-bar arrangement (bar-cycling) — the audit-flagged gap

    func testLoadArrangement_stoppedLoadsFirstBar() {
        let model = PianoRollModel()
        let bars = [[Note(pitch: 60, startStep: 0)],
                    [Note(pitch: 62, startStep: 0)],
                    [Note(pitch: 64, startStep: 0)]]
        model.loadArrangement(bars, playing: false)
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.notes.first?.pitch, 60, "stopped → bar 0 is present before playback")
    }

    func testLoadArrangement_singleBarFallsBackToPlainLoad() {
        let model = PianoRollModel()
        model.loadArrangement([[Note(pitch: 67, startStep: 4)]], playing: false)
        XCTAssertEqual(model.notes.first?.pitch, 67)
        // A single-bar arrangement exports as exactly one bar (no cycling).
        XCTAssertEqual(model.arrangementForExport().bars, 1)
    }

    func testLoadArrangement_emptyIsSafe() {
        let model = PianoRollModel()
        model.loadArrangement([], playing: false)
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertEqual(model.arrangementForExport().bars, 1)
    }

    func testArrangementForExport_offsetsEachBarByOneWholeBar() {
        let model = PianoRollModel()
        // Three distinct 1-note bars; each should land in its own bar on export.
        let bars = [[Note(pitch: 60, startStep: 0)],
                    [Note(pitch: 62, startStep: 0)],
                    [Note(pitch: 64, startStep: 0)]]
        model.loadArrangement(bars, playing: false)
        let out = model.arrangementForExport()
        XCTAssertEqual(out.bars, 3, "an N-bar arrangement exports as N bars")
        XCTAssertEqual(out.notes.count, 3)
        let barTicks = PianoRollModel.stepCount * Note.ticksPerStep
        let byPitch = Dictionary(uniqueKeysWithValues: out.notes.map { ($0.pitch, $0.startTick) })
        XCTAssertEqual(byPitch[60], 0, "bar 0 stays at tick 0")
        XCTAssertEqual(byPitch[62], barTicks, "bar 1 is offset one whole bar")
        XCTAssertEqual(byPitch[64], 2 * barTicks, "bar 2 is offset two whole bars")
    }

    func testClearStopsCyclingAndEmptiesRoll() {
        let model = PianoRollModel()
        model.loadArrangement([[Note(pitch: 60, startStep: 0)],
                               [Note(pitch: 62, startStep: 0)]], playing: false)
        model.clear()
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertEqual(model.arrangementForExport().bars, 1,
                       "a cleared roll is a single (empty) bar, not a stale N-bar cycle")
    }
}

/// TIE AT THE WRAP (founder 2026-07-09 "Vermeide stolpern"): the pure matcher
/// that decides which sounds carry straight across the loop boundary instead of
/// re-articulating (the every-bar dip/swell + voice-steal clicks on a Fläche).
@MainActor
final class WrapTieTests: XCTestCase {

    func testSamePitchSameVoiceTies() {
        let e = UUID(), s = UUID()
        let ties = PianoRollModel.wrapTies(ending: [(e, 60, 1)], starting: [(s, 60, 1)])
        XCTAssertEqual(ties, [PianoRollModel.TiePair(endID: e, startID: s)],
                       "a pitch ending on the bar line while the same pitch starts = one sound")
    }

    func testDifferentPitchDoesNotTie() {
        let ties = PianoRollModel.wrapTies(ending: [(UUID(), 60, 1)],
                                           starting: [(UUID(), 62, 1)])
        XCTAssertTrue(ties.isEmpty, "a chord change re-articulates normally")
    }

    func testDifferentVoiceDoesNotTie() {
        // Same pitch on the lead voice vs the pad voice = two instruments — the
        // ending one must release, the starting one must attack.
        let ties = PianoRollModel.wrapTies(ending: [(UUID(), 60, 1)],
                                           starting: [(UUID(), 60, 2)])
        XCTAssertTrue(ties.isEmpty)
    }

    func testFullBarNotePrefersTyingToItself() {
        // A full-bar note meets ITSELF at the wrap (same id in ending + starting).
        // With another same-pitch candidate present it must still self-tie, so the
        // pairing is stable and the other pair matches each other.
        let drone = UUID(), otherEnd = UUID(), otherStart = UUID()
        let ties = PianoRollModel.wrapTies(
            ending: [(otherEnd, 60, 1), (drone, 60, 1)],
            starting: [(drone, 60, 1), (otherStart, 60, 1)])
        XCTAssertEqual(ties.count, 2, "unisons pair one-to-one")
        XCTAssertTrue(ties.contains(PianoRollModel.TiePair(endID: drone, startID: drone)),
                      "the continuing note ties to itself")
        XCTAssertTrue(ties.contains(PianoRollModel.TiePair(endID: otherEnd, startID: otherStart)))
    }

    func testUnisonPairsOneToOne() {
        // Two ending unisons + one starting: exactly ONE ties, the other releases.
        let e1 = UUID(), e2 = UUID(), s1 = UUID()
        let ties = PianoRollModel.wrapTies(ending: [(e1, 60, 1), (e2, 60, 1)],
                                           starting: [(s1, 60, 1)])
        XCTAssertEqual(ties.count, 1)
        XCTAssertEqual(Set(ties.map(\.endID)).count, 1, "each ending note is consumed at most once")
    }

    func testEmptySidesProduceNoTies() {
        XCTAssertTrue(PianoRollModel.wrapTies(ending: [], starting: [(UUID(), 60, 1)]).isEmpty)
        XCTAssertTrue(PianoRollModel.wrapTies(ending: [(UUID(), 60, 1)], starting: []).isEmpty)
    }
}
#endif
