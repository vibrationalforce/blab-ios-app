// ModRouteSensitivityTests.swift
// AU2 ("Bio fühlt sich zu neutral an"): pins the ModRoute input SENSITIVITY
// window that remaps [inputLow…inputHigh] → [0…1] before invert/curve/depth, so a
// route can span its destination from the body's ACTUAL operating range instead
// of only the fraction the raw source moves. Golden-gate: the identity window
// (0…1) leaves every pre-AU2 route byte-identical.

import XCTest
@testable import Echoelmusic

final class ModRouteSensitivityTests: XCTestCase {

    private func frame(coh: Float = 0.5, hr: Float = 120) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: 0.5,
            breathRate: 12, breathPhase: 0.5, coherence: coh,
            motionEnergy: 0.5, source: .fallback
        )
    }
    private func dest(_ k: String) -> ModDestination { ModDestination(k) }

    // MARK: - Golden gate: identity window changes nothing

    func testIdentityWindow_isDefault_andByteIdentical() {
        let r = ModRoute(source: .coherence, destination: dest("x"), mode: .live)
        XCTAssertEqual(r.inputLow, 0)
        XCTAssertEqual(r.inputHigh, 1)
        // Same expectations as the pre-AU2 live/depth/invert tests.
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 1.0)), 1.0, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.0)), 0.0, accuracy: 1e-6)
    }

    // MARK: - Expansion: narrow operating range → full scale

    func testWindow_expandsOperatingRangeToFullScale() {
        let r = ModRoute(source: .coherence, destination: dest("x"), inputLow: 0.3, inputHigh: 0.6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.3)), 0.0, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.45)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.6)), 1.0, accuracy: 1e-6)
    }

    func testWindow_clampsOutsideTheWindow() {
        let r = ModRoute(source: .coherence, destination: dest("x"), inputLow: 0.3, inputHigh: 0.6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.1)), 0.0, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.9)), 1.0, accuracy: 1e-6)
    }

    // MARK: - Degenerate window → identity (no divide-by-zero)

    func testDegenerateWindow_fallsBackToIdentity() {
        let r = ModRoute(source: .coherence, destination: dest("x"), inputLow: 0.6, inputHigh: 0.3)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.5, accuracy: 1e-6)
        let zeroWidth = ModRoute(source: .coherence, destination: dest("x"), inputLow: 0.4, inputHigh: 0.4)
        XCTAssertEqual(ModulationMatrix.output(for: zeroWidth, frame: frame(coh: 0.5)), 0.5, accuracy: 1e-6)
    }

    // MARK: - Composition with depth + invert

    func testWindow_composesWithDepth() {
        // window [0,0.5] maps coh 0.5 → 1.0, depth 0.5 → 0.5.
        let r = ModRoute(source: .coherence, destination: dest("x"), depth: 0.5, inputLow: 0, inputHigh: 0.5)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.5, accuracy: 1e-6)
    }

    func testWindow_composesWithInvert() {
        // window [0.3,0.6] maps coh 0.6 → 1.0, invert → 0.0.
        let r = ModRoute(source: .coherence, destination: dest("x"), invert: true, inputLow: 0.3, inputHigh: 0.6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.6)), 0.0, accuracy: 1e-6)
    }

    // MARK: - Init clamps window bounds into [0,1]

    func testInit_clampsWindowBoundsIntoUnit() {
        let r = ModRoute(source: .coherence, destination: dest("x"), inputLow: -0.5, inputHigh: 2.0)
        XCTAssertEqual(r.inputLow, 0)
        XCTAssertEqual(r.inputHigh, 1)
    }

    // MARK: - Codable: round-trip + additive decode of pre-AU2 JSON

    func testCodable_roundTripsWindow() throws {
        let r = ModRoute(source: .coherence, destination: dest("x"), inputLow: 0.3, inputHigh: 0.6)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(ModRoute.self, from: data)
        XCTAssertEqual(back.inputLow, 0.3, accuracy: 1e-6)
        XCTAssertEqual(back.inputHigh, 0.6, accuracy: 1e-6)
    }

    func testCodable_preAU2JSON_decodesIdentityWindow() throws {
        // A route encoded before AU2 has no inputLow/inputHigh keys → defaults.
        let r = ModRoute(source: .coherence, destination: dest("x"), inputLow: 0.3, inputHigh: 0.6)
        let data = try JSONEncoder().encode(r)
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "inputLow")
        dict.removeValue(forKey: "inputHigh")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let back = try JSONDecoder().decode(ModRoute.self, from: stripped)
        XCTAssertEqual(back.inputLow, 0, "missing key → identity low")
        XCTAssertEqual(back.inputHigh, 1, "missing key → identity high")
    }
}
