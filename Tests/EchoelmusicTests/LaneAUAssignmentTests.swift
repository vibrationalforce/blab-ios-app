// LaneAUAssignmentTests.swift
// H9a — the pure per-lane hosting-intent laws (Linux-CI-tested): which lanes
// want a hosted chain, how the effect list is filtered/capped, and that
// assignment equality is the reconcile's change-detection currency.

import XCTest
@testable import Echoelmusic

final class LaneAUAssignmentTests: XCTestCase {

    private func instRef(_ name: String = "Inst") -> AUPluginRef {
        AUPluginRef(name: name, manufacturerName: "Test",
                    componentType: 0x61756D75, componentSubType: 0x74657374,
                    componentManufacturer: 0x54455354, isInstrument: true)
    }

    private func fxRef(_ name: String) -> AUPluginRef {
        AUPluginRef(name: name, manufacturerName: "Test",
                    componentType: 0x61756678, componentSubType: 0x74657374,
                    componentManufacturer: 0x54455354, isInstrument: false)
    }

    // MARK: - wanted() filter laws

    func testWanted_excludesRollBioAndNonMIDILanes() {
        let roll = TimelineLane(name: "Roll", kind: .midi, instrument: instRef())
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true, instrument: instRef())
        let audio = TimelineLane(name: "Audio", kind: .audio, instrument: instRef())
        let secondary = TimelineLane(name: "MIDI 2", kind: .midi, instrument: instRef())
        let wanted = LaneAUAssignment.wanted(lanes: [roll, bio, audio, secondary],
                                             rollLane: roll.id)
        XCTAssertEqual(Array(wanted.keys), [secondary.id],
                       "only the secondary MIDI lane hosts (roll = global AUv3Host's channel)")
    }

    func testWanted_effectRefInInstrumentSlot_isIgnored() {
        let lane = TimelineLane(name: "L", kind: .midi, instrument: fxRef("NotAnInstrument"))
        XCTAssertTrue(LaneAUAssignment.wanted(lanes: [lane], rollLane: nil).isEmpty,
                      "pre-H9 law unchanged: lane.instrument must BE an instrument")
    }

    func testWanted_effectsWithoutInstrument_areHonestlyDeferred() {
        // A rack-voice lane has no per-lane node boundary — effects stay data.
        let lane = TimelineLane(name: "L", kind: .midi, effects: [fxRef("Delay")])
        XCTAssertTrue(LaneAUAssignment.wanted(lanes: [lane], rollLane: nil).isEmpty)
    }

    func testWanted_filtersInstrumentsOutOfEffectList_keepsOrder() {
        let lane = TimelineLane(name: "L", kind: .midi, instrument: instRef(),
                                effects: [fxRef("A"), instRef("Rogue"), fxRef("B")])
        let a = LaneAUAssignment.wanted(lanes: [lane], rollLane: nil)[lane.id]
        XCTAssertEqual(a?.effects.map(\.name), ["A", "B"],
                       "an instrument ref in the insert list is dropped, order preserved")
    }

    func testWanted_capsEffectsPerLane_firstStagesWin() {
        let fx = (0..<5).map { fxRef("FX\($0)") }
        let lane = TimelineLane(name: "L", kind: .midi, instrument: instRef(), effects: fx)
        let a = LaneAUAssignment.wanted(lanes: [lane], rollLane: nil)[lane.id]
        XCTAssertEqual(a?.effects.map(\.name), ["FX0", "FX1", "FX2"])
        XCTAssertEqual(LaneAUAssignment.maxEffectsPerLane, 3)
    }

    // MARK: - Change-detection currency

    func testEquality_effectEditChangesAssignment() {
        let inst = instRef()
        let bare = LaneAUAssignment(instrument: inst)
        let withFX = LaneAUAssignment(instrument: inst, effects: [fxRef("Delay")])
        XCTAssertNotEqual(bare, withFX,
                          "adding/removing an effect must read as a CHANGED assignment (chain rebuild)")
        XCTAssertNotEqual(withFX, LaneAUAssignment(instrument: inst, effects: [fxRef("Verb")]))
        XCTAssertEqual(withFX, LaneAUAssignment(instrument: inst, effects: [fxRef("Delay")]))
    }

    func testUnitCount_isInstrumentPlusStages() {
        XCTAssertEqual(LaneAUAssignment(instrument: instRef()).unitCount, 1)
        XCTAssertEqual(LaneAUAssignment(instrument: instRef(),
                                        effects: [fxRef("A"), fxRef("B")]).unitCount, 3)
    }
}
