// SpatialSceneOSCTests.swift
// Echoel — S2 of the spatial expansion: golden-file tests. A fixed scene must
// produce EXACTLY these (address, value) pairs per dialect — the address
// strings are the contract with external renderers, so any drift is a break.

import XCTest
@testable import Echoelmusic

final class SpatialSceneOSCTests: XCTestCase {

    /// The fixed golden scene: two objects with exact, clamp-free values.
    private func goldenScene() -> SpatialScene {
        var scene = SpatialScene()
        scene.upsert(SpatialObject(id: "voice",
                                   position: SpatialPosition(azimuth: -30, elevation: 10, distance: 0.8),
                                   gain: 1.0))
        scene.upsert(SpatialObject(id: "sub",
                                   position: SpatialPosition(azimuth: 45, elevation: -15, distance: 0.25),
                                   gain: 0.25))
        return scene
    }

    // MARK: - ADM-OSC golden file (1-based objects, same namespace the live sender ships)

    func testADMGoldenMessages() {
        let messages = SpatialSceneOSCFormatter.messages(for: goldenScene(), dialect: .admOSC)
        let expected: [(String, Float)] = [
            ("/adm/obj/1/position/azimuth", -30),
            ("/adm/obj/1/position/elevation", 10),
            ("/adm/obj/1/position/distance", 0.8),
            ("/adm/obj/1/gain", 1.0),
            ("/adm/obj/2/position/azimuth", 45),
            ("/adm/obj/2/position/elevation", -15),
            ("/adm/obj/2/position/distance", 0.25),
            ("/adm/obj/2/gain", 0.25),
        ]
        XCTAssertEqual(messages.count, expected.count)
        for (got, want) in zip(messages, expected) {
            XCTAssertEqual(got.address, want.0)
            XCTAssertEqual(got.value, want.1, accuracy: 1e-5, "value for \(want.0)")
        }
    }

    // MARK: - ADM-OSC Cartesian golden file (1-based objects, x/y/z instead of az/el/dist)

    func testADMCartesianGoldenMessages() {
        let messages = SpatialSceneOSCFormatter.messages(for: goldenScene(), dialect: .admOSCCartesian)
        // Cartesian derived from the SAME positions: x right, y front, z up, ×distance.
        // voice(az -30, el 10, d 0.8) · sub(az 45, el -15, d 0.25).
        let expected: [(String, Float)] = [
            ("/adm/obj/1/position/x", 0.393923),
            ("/adm/obj/1/position/y", 0.682295),
            ("/adm/obj/1/position/z", 0.138919),
            ("/adm/obj/1/gain", 1.0),
            ("/adm/obj/2/position/x", -0.170753),
            ("/adm/obj/2/position/y", 0.170753),
            ("/adm/obj/2/position/z", -0.064705),
            ("/adm/obj/2/gain", 0.25),
        ]
        XCTAssertEqual(messages.count, expected.count)
        for (got, want) in zip(messages, expected) {
            XCTAssertEqual(got.address, want.0)
            XCTAssertEqual(got.value, want.1, accuracy: 1e-4, "value for \(want.0)")
        }
        // Cartesian dialect must never emit the polar address tokens.
        XCTAssertFalse(messages.contains { $0.address.contains("azimuth")
                                        || $0.address.contains("elevation")
                                        || $0.address.contains("distance") })
    }

    func testADMCartesianFrontObjectIsPureY() {
        // An object dead-front at unit distance sits on +y only (x≈0, z≈0) — the
        // sanity anchor for the coordinate convention.
        var scene = SpatialScene()
        scene.upsert(SpatialObject(id: "front",
                                   position: SpatialPosition(azimuth: 0, elevation: 0, distance: 1),
                                   gain: 1.0))
        let m = SpatialSceneOSCFormatter.messages(for: scene, dialect: .admOSCCartesian)
        func value(_ suffix: String) -> Float? { m.first { $0.address.hasSuffix(suffix) }?.value }
        XCTAssertEqual(value("/position/x") ?? .nan, 0, accuracy: 1e-5)
        XCTAssertEqual(value("/position/y") ?? .nan, 1, accuracy: 1e-5)
        XCTAssertEqual(value("/position/z") ?? .nan, 0, accuracy: 1e-5)
    }

    func testADMCartesianEmptySceneProducesNoMessages() {
        XCTAssertTrue(SpatialSceneOSCFormatter.messages(for: SpatialScene(), dialect: .admOSCCartesian).isEmpty)
    }

    // MARK: - IEM golden file (0-based sources, degrees + dB, NO distance)

    func testIEMGoldenMessages() {
        let messages = SpatialSceneOSCFormatter.messages(for: goldenScene(), dialect: .iem)
        let expected: [(String, Float)] = [
            ("/MultiEncoder/azimuth0", -30),
            ("/MultiEncoder/elevation0", 10),
            ("/MultiEncoder/gain0", 0),              // linear 1.0 = 0 dB
            ("/MultiEncoder/azimuth1", 45),
            ("/MultiEncoder/elevation1", -15),
            ("/MultiEncoder/gain1", -12.0412),       // 20·log10(0.25)
        ]
        XCTAssertEqual(messages.count, expected.count)
        for (got, want) in zip(messages, expected) {
            XCTAssertEqual(got.address, want.0)
            XCTAssertEqual(got.value, want.1, accuracy: 1e-3, "value for \(want.0)")
        }
        // The dialect contract: no distance address ever appears.
        XCTAssertFalse(messages.contains { $0.address.contains("distance") })
    }

    func testIEMCustomPluginRoot() {
        var scene = SpatialScene()
        scene.upsert(SpatialObject(id: "a"))
        let messages = SpatialSceneOSCFormatter.messages(
            for: scene, dialect: .iemMultiEncoder(plugin: "RoomEncoder"))
        XCTAssertEqual(messages.first?.address, "/RoomEncoder/azimuth0")
    }

    // MARK: - dB conversion contract (floor is part of the dialect)

    func testDecibelConversionAndFloor() {
        XCTAssertEqual(SpatialSceneOSCFormatter.decibels(fromLinear: 1.0), 0, accuracy: 1e-5)
        XCTAssertEqual(SpatialSceneOSCFormatter.decibels(fromLinear: 0.5), -6.0206, accuracy: 1e-3)
        XCTAssertEqual(SpatialSceneOSCFormatter.decibels(fromLinear: 0), -60)
        // Tiny but nonzero gains hit the -60 floor instead of running away.
        XCTAssertEqual(SpatialSceneOSCFormatter.decibels(fromLinear: 1e-9), -60)
    }

    // MARK: - Edges

    func testEmptySceneProducesNoMessages() {
        let scene = SpatialScene()
        XCTAssertTrue(SpatialSceneOSCFormatter.messages(for: scene, dialect: .admOSC).isEmpty)
        XCTAssertTrue(SpatialSceneOSCFormatter.messages(for: scene, dialect: .iem).isEmpty)
    }

    func testIndexBasesDifferPerDialect() {
        var scene = SpatialScene()
        scene.upsert(SpatialObject(id: "only"))
        let adm = SpatialSceneOSCFormatter.messages(for: scene, dialect: .admOSC)
        let iem = SpatialSceneOSCFormatter.messages(for: scene, dialect: .iem)
        // ADM objects are 1-based, IEM sources 0-based — both are the
        // renderers' own conventions, asserted so nobody "harmonizes" them.
        XCTAssertTrue(adm.allSatisfy { $0.address.hasPrefix("/adm/obj/1/") })
        XCTAssertTrue(iem.allSatisfy { $0.address.hasSuffix("0") })
    }
}
