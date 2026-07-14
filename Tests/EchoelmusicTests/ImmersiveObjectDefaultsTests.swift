// ImmersiveObjectDefaultsTests.swift
// Echoel — Tests for the pure immersive-placement mapper.
//
// Foundation + XCTest only (Linux-CI portable). No engine, no audio, no UI.

import XCTest
@testable import Echoelmusic

final class ImmersiveObjectDefaultsTests: XCTestCase {

    // MARK: Even spread — no two lanes collide in azimuth

    func testAzimuths_spreadWithoutCollision_acrossManyLaneCounts() {
        // For several ring sizes, every lane of the same instrument gets a distinct azimuth.
        for laneCount in [2, 3, 4, 5, 6, 8, 12, 16] {
            var azimuths: [Float] = []
            for laneIndex in 0..<laneCount {
                let pos = ImmersiveObjectDefaults.defaultPosition(for: .drums,
                                                                  laneIndex: laneIndex,
                                                                  laneCount: laneCount)
                azimuths.append(pos.azimuth)
            }
            let unique = Set(azimuths.map { $0.bitPattern })
            XCTAssertEqual(unique.count, laneCount,
                           "laneCount \(laneCount): expected \(laneCount) distinct azimuths, got \(unique.count) — \(azimuths)")
        }
    }

    func testAzimuths_areEvenlyStepped_forNeutralInstrument() {
        // drums scale = 0.85; base step for laneCount 4 is 90°, so scaled step = 76.5°.
        let count = 4
        var azimuths: [Float] = []
        for i in 0..<count {
            azimuths.append(ImmersiveObjectDefaults.defaultPosition(for: .drums,
                                                                    laneIndex: i,
                                                                    laneCount: count).azimuth)
        }
        // Expected bases: -135,-45,45,135 → *0.85 → -114.75,-38.25,38.25,114.75
        XCTAssertEqual(azimuths[0], -114.75, accuracy: 0.001)
        XCTAssertEqual(azimuths[1],  -38.25, accuracy: 0.001)
        XCTAssertEqual(azimuths[2],   38.25, accuracy: 0.001)
        XCTAssertEqual(azimuths[3],  114.75, accuracy: 0.001)
        // Steps are equal.
        let step1 = azimuths[1] - azimuths[0]
        let step2 = azimuths[2] - azimuths[1]
        let step3 = azimuths[3] - azimuths[2]
        XCTAssertEqual(step1, step2, accuracy: 0.001)
        XCTAssertEqual(step2, step3, accuracy: 0.001)
    }

    func testSingleLane_andEmptyRing_centreFront() {
        // A lone lane sits at front centre (azimuth 0), whatever the index.
        let one = ImmersiveObjectDefaults.defaultPosition(for: .polySynth, laneIndex: 0, laneCount: 1)
        XCTAssertEqual(one.azimuth, 0, accuracy: 0.0001)
        // Degenerate (<=0) count must not trap or divide by zero — pinned to centre.
        let zero = ImmersiveObjectDefaults.defaultPosition(for: .drums, laneIndex: 3, laneCount: 0)
        XCTAssertEqual(zero.azimuth, 0, accuracy: 0.0001)
        let negative = ImmersiveObjectDefaults.defaultPosition(for: .drums, laneIndex: 1, laneCount: -5)
        XCTAssertEqual(negative.azimuth, 0, accuracy: 0.0001)
    }

    // MARK: Bass is more central / front than pads

    func testBass_moreCentralAndFront_thanPads() {
        // Same lane slot, same ring: compare the low end (subBass) to the pad (polySynth).
        let count = 6
        for laneIndex in 0..<count {
            let bass = ImmersiveObjectDefaults.defaultPosition(for: .subBass,
                                                               laneIndex: laneIndex,
                                                               laneCount: count)
            let pad = ImmersiveObjectDefaults.defaultPosition(for: .polySynth,
                                                              laneIndex: laneIndex,
                                                              laneCount: count)
            // More central: smaller azimuth magnitude (closer to front). Lane 0/... where
            // the base azimuth is non-zero this is strict; guard against the exact-centre case.
            if abs(pad.azimuth) > 0.0001 {
                XCTAssertLessThan(abs(bass.azimuth), abs(pad.azimuth),
                                  "lane \(laneIndex): bass should be more central than pad")
            }
            // More front: nearer distance and lower (front-low) elevation.
            XCTAssertLessThan(bass.distance, pad.distance,
                              "lane \(laneIndex): bass should sit nearer/more forward than pad")
            XCTAssertLessThan(bass.elevation, pad.elevation,
                              "lane \(laneIndex): bass should sit lower than pad")
        }
    }

    func testSubBass_isNearFrontLowPointSource() {
        let pos = ImmersiveObjectDefaults.defaultPosition(for: .subBass, laneIndex: 2, laneCount: 4)
        // Base for lane 2 of 4 = 45°, *0.20 = 9° — clearly toward front centre.
        XCTAssertEqual(pos.azimuth, 9, accuracy: 0.001)
        XCTAssertLessThan(pos.elevation, 0)          // below the ear line
        let obj = ImmersiveObjectDefaults.defaultObject(for: .subBass,
                                                        laneID: UUID(),
                                                        laneIndex: 2,
                                                        laneCount: 4)
        XCTAssertLessThan(obj.extent, 0.1)           // point source (focused)
        XCTAssertLessThan(obj.roomSend, 0.2)         // direct, little room
    }

    func testPads_areWideBackAndImmersive() {
        let padObj = ImmersiveObjectDefaults.defaultObject(for: .polySynth,
                                                           laneID: UUID(),
                                                           laneIndex: 0,
                                                           laneCount: 4)
        let bassObj = ImmersiveObjectDefaults.defaultObject(for: .subBass,
                                                            laneID: UUID(),
                                                            laneIndex: 0,
                                                            laneCount: 4)
        XCTAssertGreaterThan(padObj.extent, bassObj.extent)     // wider apparent size
        XCTAssertGreaterThan(padObj.roomSend, bassObj.roomSend) // more room = more immersive
        XCTAssertGreaterThan(padObj.position.distance, bassObj.position.distance) // set back
    }

    // MARK: Determinism

    func testDeterministic_identicalInputsGiveIdenticalOutput() {
        for instrument in TrackInstrument.allCases {
            let a = ImmersiveObjectDefaults.defaultPosition(for: instrument, laneIndex: 3, laneCount: 7)
            let b = ImmersiveObjectDefaults.defaultPosition(for: instrument, laneIndex: 3, laneCount: 7)
            XCTAssertEqual(a, b, "position must be deterministic for \(instrument)")
        }
    }

    func testDeterministic_objectStableForSameLaneID() {
        let id = UUID()
        let a = ImmersiveObjectDefaults.defaultObject(for: .polySynth, laneID: id, laneIndex: 2, laneCount: 5)
        let b = ImmersiveObjectDefaults.defaultObject(for: .polySynth, laneID: id, laneIndex: 2, laneCount: 5)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, id.uuidString, "object id must be the lane UUID string")
    }

    func testDifferentLaneIDs_produceDifferentObjectIDs() {
        let id1 = UUID(), id2 = UUID()
        let o1 = ImmersiveObjectDefaults.defaultObject(for: .drums, laneID: id1, laneIndex: 0, laneCount: 3)
        let o2 = ImmersiveObjectDefaults.defaultObject(for: .drums, laneID: id2, laneIndex: 0, laneCount: 3)
        XCTAssertNotEqual(o1.id, o2.id)
    }

    // MARK: Total coverage — every case maps, never traps, always legal

    func testEveryInstrumentCase_mapsWithoutTrapping_andStaysInRange() {
        let counts = [0, 1, 2, 4, 9]
        for instrument in TrackInstrument.allCases {
            for laneCount in counts {
                // Probe indices in range, at the edges, and out of range.
                for laneIndex in [-3, 0, max(0, laneCount - 1), laneCount, 100] {
                    let pos = ImmersiveObjectDefaults.defaultPosition(for: instrument,
                                                                      laneIndex: laneIndex,
                                                                      laneCount: laneCount)
                    XCTAssertTrue(pos.azimuth.isFinite && pos.azimuth >= -180 && pos.azimuth <= 180)
                    XCTAssertTrue(pos.elevation.isFinite && pos.elevation >= -90 && pos.elevation <= 90)
                    XCTAssertTrue(pos.distance.isFinite && pos.distance >= 0 && pos.distance <= 1)

                    let obj = ImmersiveObjectDefaults.defaultObject(for: instrument,
                                                                    laneID: UUID(),
                                                                    laneIndex: laneIndex,
                                                                    laneCount: laneCount)
                    XCTAssertEqual(obj.position, pos, "object position must match defaultPosition")
                    XCTAssertTrue(obj.extent >= 0 && obj.extent <= 1)
                    XCTAssertTrue(obj.gain >= 0 && obj.gain <= 1)
                    XCTAssertTrue(obj.roomSend >= 0 && obj.roomSend <= 1)
                }
            }
        }
    }
}
