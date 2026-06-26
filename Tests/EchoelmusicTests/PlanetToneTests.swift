//
//  PlanetToneTests.swift
//  Echoelmusic — Cousto planetary tones as a creative Kammerton tuning.
//

import XCTest
@testable import Echoelmusic

final class PlanetToneTests: XCTestCase {

    func testEarthYear_isCSharp_andTunesA4ToAbout432() {
        let earth = PlanetTones.named("earth-year")
        XCTAssertNotNil(earth)
        XCTAssertEqual(earth?.nearestNoteName, "C#")
        XCTAssertEqual(earth?.a4Hz ?? 0, 432.1, accuracy: 0.5)   // OM 136.10 → A ≈ 432
    }

    func testVenus_isA_andTunesNearA442() {
        let venus = PlanetTones.named("venus")
        XCTAssertEqual(venus?.nearestNoteName, "A")
        XCTAssertEqual(venus?.a4Hz ?? 0, 442.5, accuracy: 0.6)
    }

    func testAllPlanets_a4WithinKammertonRange() {
        // Every planet tunes A to within ±50¢ of 440 (415.3…466.2) — inside the
        // Kammerton field's 380…500 range, so selecting one is always valid.
        for p in PlanetTones.all {
            XCTAssertGreaterThanOrEqual(p.a4Hz, 415.0, "\(p.name) a4 too low")
            XCTAssertLessThanOrEqual(p.a4Hz, 467.0, "\(p.name) a4 too high")
            XCTAssertTrue(p.a4Hz.isFinite)
        }
    }

    func testCatalogue_isCompleteAndUnique() {
        XCTAssertEqual(PlanetTones.all.count, 13)
        XCTAssertEqual(Set(PlanetTones.all.map(\.id)).count, 13, "ids unique")
        XCTAssertEqual(Set(PlanetTones.all.map(\.name)).count, 13, "names unique")
        for p in PlanetTones.all { XCTAssertGreaterThan(p.toneHz, 0) }
    }

    func testNearestNote_roundTripsToToneHz() {
        // a4Hz is defined so the tone sits exactly on its nearest note: re-deriving the
        // note frequency from a4Hz + nearestMidi must reproduce toneHz.
        for p in PlanetTones.all {
            let noteHz = p.a4Hz * pow(2.0, Double(p.nearestMidi - 69) / 12.0)
            XCTAssertEqual(noteHz, p.toneHz, accuracy: 0.01, "\(p.name)")
        }
    }
}
