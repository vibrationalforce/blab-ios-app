// MusicMediaMappingTests.swift
// Echoel — the music→media converter runtime: a sounding chord becomes a DMX colour
// (SpectralColor) and an ADM-OSC object position (pitch→azimuth/elevation, level→
// distance/gain). Pure, socket-free — verifies channel counts, ranges, and that the
// mapping actually tracks pitch + loudness.

#if canImport(Network) && canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class MusicMediaMappingTests: XCTestCase {

    private func frame(_ notes: [(Double, Double)], master: Double = 0.8) -> MusicalFrame {
        MusicalFrame(notes: notes.map { MusicalNote(frequencyHz: $0.0, amplitude: $0.1) },
                     masterLevel: master)
    }

    // MARK: Light

    func testDMX_channelCounts_perResolution() {
        let f = frame([(440, 1)])
        XCTAssertEqual(MusicMediaMap.dmxChannels(forMusic: f, resolution: .eightBit).count, 4)
        XCTAssertEqual(MusicMediaMap.dmxChannels(forMusic: f, resolution: .sixteenBit).count, 8)
    }

    func testDimmer_tracksMasterLevel() {
        let quiet = MusicMediaMap.dimmerUnit(forMusic: frame([(440, 1)], master: 0.0))
        let loud  = MusicMediaMap.dimmerUnit(forMusic: frame([(440, 1)], master: 1.0))
        XCTAssertEqual(quiet, 0.3, accuracy: 1e-6)   // always lit
        XCTAssertEqual(loud, 1.0, accuracy: 1e-6)
        XCTAssertGreaterThan(loud, quiet)
    }

    func testDMX_colourDiffersByPitch() {
        // Two different pitch classes should not produce identical RGB.
        let c = MusicMediaMap.dmxChannels(forMusic: frame([(261.63, 1)]), resolution: .eightBit) // C
        let a = MusicMediaMap.dmxChannels(forMusic: frame([(440.0, 1)]), resolution: .eightBit)   // A
        XCTAssertNotEqual(Array(c[1...3]), Array(a[1...3]))   // R/G/B differ
    }

    // MARK: Spatial

    func testADM_messageShape_andRanges() {
        let msgs = MusicMediaMap.admMessages(forMusic: frame([(440, 1)]), object: 2)
        XCTAssertEqual(msgs.count, 4)
        XCTAssertEqual(msgs[0].0, "/adm/obj/2/position/azimuth")
        XCTAssertEqual(msgs[3].0, "/adm/obj/2/gain")
        for (_, v) in msgs { XCTAssertTrue(v.isFinite) }
        let az = msgs[0].1, el = msgs[1].1, dist = msgs[2].1, gain = msgs[3].1
        XCTAssertTrue((-180...180).contains(az))
        XCTAssertTrue((-90...90).contains(el))
        XCTAssertTrue((0...1).contains(dist))
        XCTAssertTrue((0...1).contains(gain))
    }

    func testADM_pitchClass_drivesAzimuth() {
        // C (pitch-class 0) → -180; A (pitch-class 9) → -180 + 9/12*360 = 90.
        let cAz = MusicMediaMap.admMessages(forMusic: frame([(261.63, 1)]), object: 1)[0].1
        let aAz = MusicMediaMap.admMessages(forMusic: frame([(440.0, 1)]), object: 1)[0].1
        XCTAssertEqual(cAz, -180, accuracy: 1.0)
        XCTAssertEqual(aAz, 90, accuracy: 1.0)
    }

    func testADM_louder_pullsCloser() {
        let near = MusicMediaMap.admMessages(forMusic: frame([(440, 1)], master: 1.0), object: 1)[2].1
        let far  = MusicMediaMap.admMessages(forMusic: frame([(440, 1)], master: 0.1), object: 1)[2].1
        XCTAssertLessThan(near, far)   // distance smaller when louder
    }

    func testADM_usesLoudestNote() {
        // Quiet low note + loud high note → azimuth from the loud one (A4, pc 9 → 90).
        let msgs = MusicMediaMap.admMessages(forMusic: frame([(130.81, 0.1), (440, 1.0)]), object: 1)
        XCTAssertEqual(msgs[0].1, 90, accuracy: 1.0)
    }
}
#endif
