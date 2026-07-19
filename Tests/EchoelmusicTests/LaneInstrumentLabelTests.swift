// LaneInstrumentLabelTests.swift
// item 3 (externe AUv3 sichtbar): pins the pure track-head Belegung formatter —
// external instrument wins over built-in, FX chain summarized as "N FX", empty
// lane returns nil (no fabricated label).

import XCTest
@testable import Echoelmusic

final class LaneInstrumentLabelTests: XCTestCase {

    private func au(_ name: String, instrument: Bool) -> AUPluginRef {
        AUPluginRef(name: name, manufacturerName: "Acme",
                    componentType: 0, componentSubType: 1, componentManufacturer: 2,
                    isInstrument: instrument)
    }

    // MARK: - instrumentName

    func testInstrumentName_externalWinsOverBuiltin() {
        let name = LaneInstrumentLabel.instrumentName(
            instrument: au("Zebra2", instrument: true), builtin: .polySynth)
        XCTAssertEqual(name, "Zebra2")
    }

    func testInstrumentName_builtinWhenNoExternal() {
        XCTAssertEqual(LaneInstrumentLabel.instrumentName(instrument: nil, builtin: .subBass),
                       "EchoelBass")
    }

    func testInstrumentName_nilWhenNeither() {
        XCTAssertNil(LaneInstrumentLabel.instrumentName(instrument: nil, builtin: nil))
    }

    // MARK: - effectsSummary

    func testEffectsSummary_emptyIsNil() {
        XCTAssertNil(LaneInstrumentLabel.effectsSummary([]))
    }

    func testEffectsSummary_countLabel() {
        XCTAssertEqual(LaneInstrumentLabel.effectsSummary([au("Blackhole", instrument: false)]), "1 FX")
        XCTAssertEqual(LaneInstrumentLabel.effectsSummary(
            [au("A", instrument: false), au("B", instrument: false), au("C", instrument: false)]), "3 FX")
    }

    // MARK: - summary composition

    func testSummary_instrumentAndEffects() {
        let s = LaneInstrumentLabel.summary(
            instrument: au("Diva", instrument: true), builtin: nil,
            effects: [au("Pro-Q", instrument: false), au("Pro-C", instrument: false)])
        XCTAssertEqual(s, "Diva · 2 FX")
    }

    func testSummary_instrumentOnly() {
        XCTAssertEqual(LaneInstrumentLabel.summary(instrument: nil, builtin: .drums, effects: []),
                       "EchoelDrums")
    }

    func testSummary_effectsOnlyNoInstrument() {
        XCTAssertEqual(LaneInstrumentLabel.summary(
            instrument: nil, builtin: nil, effects: [au("Valhalla", instrument: false)]),
            "1 FX")
    }

    func testSummary_emptyLaneIsNil() {
        XCTAssertNil(LaneInstrumentLabel.summary(instrument: nil, builtin: nil, effects: []))
    }

    // MARK: - lane convenience overload

    func testSummary_forLane_readsLaneFields() {
        var lane = TimelineLane(name: "Lead", kind: .midi)
        lane.builtinInstrument = .polySynth
        lane.effects = [au("Delay", instrument: false)]
        XCTAssertEqual(LaneInstrumentLabel.summary(for: lane), "EchoelSynth · 1 FX")
    }
}
