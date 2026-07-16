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

    func testWanted_appleGeneratorTrap_isIgnored_thirdPartyGeneratorHosts() {
        // Founder 2026-07-16: a lane assigned AUAudioFilePlayer on a pre-v272
        // build (persisted in the timeline document) instantiated fine and then
        // stayed permanently MUTE — file-player API units never sound from
        // notes. wanted() drops the trap so the built-in voice takes the lane
        // back; a THIRD-PARTY generator instrument keeps hosting (many real
        // instruments register with that type).
        let trap = AUPluginRef(name: "AUAudioFilePlayer", manufacturerName: "Apple",
                               componentType: 0x6175_676E,          // 'augn'
                               componentSubType: 0x6166_706C,
                               componentManufacturer: 0x6170_706C,  // 'appl'
                               isInstrument: true)
        XCTAssertTrue(trap.isAppleGeneratorTrap)
        let thirdParty = AUPluginRef(name: "Gen", manufacturerName: "Maker",
                                     componentType: 0x6175_676E,          // 'augn'
                                     componentSubType: 0x74657374,
                                     componentManufacturer: 0x54455354,   // not Apple
                                     isInstrument: true)
        XCTAssertFalse(thirdParty.isAppleGeneratorTrap)
        XCTAssertFalse(instRef().isAppleGeneratorTrap, "music devices never match")

        let trapped = TimelineLane(name: "Mute", kind: .midi, instrument: trap)
        let hosted = TimelineLane(name: "Gen", kind: .midi, instrument: thirdParty)
        let wanted = LaneAUAssignment.wanted(lanes: [trapped, hosted], rollLane: nil)
        XCTAssertNil(wanted[trapped.id], "the trap lane falls back to the built-in voice")
        XCTAssertNotNil(wanted[hosted.id])
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

    func testWanted_filtersBeforeCap_rogueInstrumentDoesNotEatACapSlot() {
        // [fx, INST, fx, fx, fx]: all four true effects compete for the 3 slots.
        let lane = TimelineLane(name: "L", kind: .midi, instrument: instRef(),
                                effects: [fxRef("A"), instRef("Rogue"),
                                          fxRef("B"), fxRef("C"), fxRef("D")])
        let a = LaneAUAssignment.wanted(lanes: [lane], rollLane: nil)[lane.id]
        XCTAssertEqual(a?.effects.map(\.name), ["A", "B", "C"])
    }

    func testWanted_nilRollLane_hostsAnyEligibleLane() {
        let lane = TimelineLane(name: "L", kind: .midi, instrument: instRef())
        XCTAssertNotNil(LaneAUAssignment.wanted(lanes: [lane], rollLane: nil)[lane.id])
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

    func testEquality_effectORDERChangesAssignment() {
        // Insert order IS the signal path — reordering must rebuild the chain.
        let inst = instRef()
        XCTAssertNotEqual(
            LaneAUAssignment(instrument: inst, effects: [fxRef("A"), fxRef("B")]),
            LaneAUAssignment(instrument: inst, effects: [fxRef("B"), fxRef("A")]))
    }

    func testUnitCount_isInstrumentPlusStages() {
        XCTAssertEqual(LaneAUAssignment(instrument: instRef()).unitCount, 1)
        XCTAssertEqual(LaneAUAssignment(instrument: instRef(),
                                        effects: [fxRef("A"), fxRef("B")]).unitCount, 3)
    }
}
