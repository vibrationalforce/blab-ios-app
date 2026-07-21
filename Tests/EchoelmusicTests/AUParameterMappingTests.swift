// AUParameterMappingTests.swift
// AUv3-structure block U1 — the PURE mapping from a hosted AU parameter's
// metadata to an EchoelParameterRegistry descriptor. This is the foundation of
// "die AUv3-Struktur sitzt": once a hosted plugin's parameters map to the SAME
// ParameterDescriptor shape as internal DDSP params, per-track automation is
// identical for internal and external. Foundation-only so CI verifies every
// rule without a real AudioUnit instance (the live KVO bridge is U2).

import XCTest
import Foundation
@testable import Echoelmusic

final class AUParameterMappingTests: XCTestCase {

    /// Build a FourCC OSType from a 4-char string (mirrors AudioComponentDescription).
    private func osType(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for b in s.utf8.prefix(4) { result = (result << 8) | UInt32(b) }
        return result
    }

    // MARK: - Stable keyPath

    func testKeyPath_isStableAndReadable() {
        let kp = AUParameterMapping.keyPath(manufacturer: osType("Echl"),
                                            subType: osType("bass"), address: 3)
        XCTAssertEqual(kp, "au.Echl.bass.3")
        // Every registry keyPath is "modul.sektion.parameter"-ish — au-prefixed,
        // dotted, and never empty.
        XCTAssertTrue(kp.hasPrefix("au."))
    }

    func testFourCC_roundTripsPrintableCodes() {
        XCTAssertEqual(AUParameterMapping.fourCC(osType("aufx")), "aufx")
        XCTAssertEqual(AUParameterMapping.fourCC(osType("Echl")), "Echl")
    }

    func testFourCC_sanitizesNonAlphanumeric() {
        // A 4-char code with space/punctuation bytes must not break the keyPath:
        // each non-alnum byte becomes '_', position preserved.
        XCTAssertEqual(AUParameterMapping.fourCC(osType("f x!")), "f_x_")
        XCTAssertEqual(AUParameterMapping.fourCC(0), "____")               // zero code → all placeholders
    }

    func testKeyPath_nonAlnumCodeStaysDotSafe() {
        let kp = AUParameterMapping.keyPath(manufacturer: 0, subType: osType("f x!"), address: 12)
        // Exactly 3 dot-separated tokens after "au", none containing a stray dot/space.
        let tokens = kp.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(tokens.first, "au")
        XCTAssertEqual(tokens.count, 4)
        XCTAssertFalse(tokens.contains { $0.contains(" ") })
    }

    // MARK: - Descriptor mapping

    func testDescriptor_carriesAURangesAndUnit() {
        let d = AUParameterMapping.descriptor(
            manufacturer: osType("Echl"), subType: osType("filt"), address: 1,
            displayName: "Cutoff", minValue: 20, maxValue: 20_000, defaultValue: 440,
            unit: "Hz", valueStrings: nil)
        XCTAssertEqual(d.keyPath, "au.Echl.filt.1")
        XCTAssertEqual(d.displayName, "Cutoff")
        XCTAssertEqual(d.min, 20); XCTAssertEqual(d.max, 20_000)
        XCTAssertEqual(d.defaultValue, 440); XCTAssertEqual(d.unit, "Hz")
        XCTAssertNil(d.valueLabels)
        // Round-trips through the registry's normalize/denormalize.
        XCTAssertEqual(d.denormalized(d.normalized(440)), 440, accuracy: 1e-2)
    }

    func testDescriptor_valueStringsBecomeLabels() {
        let d = AUParameterMapping.descriptor(
            manufacturer: osType("Echl"), subType: osType("osc "), address: 7,
            displayName: "Waveform", minValue: 0, maxValue: 2, defaultValue: 0,
            unit: "", valueStrings: ["Sine", "Saw", "Square"])
        XCTAssertEqual(d.valueLabels, ["Sine", "Saw", "Square"])
    }

    func testDescriptor_emptyDisplayNameFallsBackToKeyPath() {
        let d = AUParameterMapping.descriptor(
            manufacturer: osType("Echl"), subType: osType("mod "), address: 5,
            displayName: "", minValue: 0, maxValue: 1, defaultValue: 0.5,
            unit: "", valueStrings: nil)
        XCTAssertEqual(d.displayName, d.keyPath, "a nameless AU param still shows something")
    }

    func testDescriptor_degenerateRangeIsWidenedSoNormalizeIsSafe() {
        // Some AUs report min==max for an unused/placeholder param.
        let d = AUParameterMapping.descriptor(
            manufacturer: osType("Echl"), subType: osType("xxxx"), address: 9,
            displayName: "Dead", minValue: 0, maxValue: 0, defaultValue: 0,
            unit: "", valueStrings: nil)
        XCTAssertGreaterThan(d.max, d.min, "min==max must be widened so max>min")
        // No divide-by-zero in normalize, no NaN.
        let n = d.normalized(0)
        XCTAssertTrue(n.isFinite)
        XCTAssertEqual(d.defaultValue, 0, accuracy: 1e-9, "default stays in the widened range")
    }

    func testDescriptor_degenerateRangeWidenedEvenAtLargeMin() {
        // Above ~2^24 a flat `min + 1` no-ops in Float32 (ULP > 1). The
        // magnitude-scaled widen must still produce max > min so the invariant
        // holds and normalize stays safe (review U1, MEDIUM finding).
        let big: Float = 50_000_000   // > 2^24 ≈ 16.77M, where min+1 == min
        let d = AUParameterMapping.descriptor(
            manufacturer: osType("Echl"), subType: osType("freq"), address: 4,
            displayName: "Huge", minValue: big, maxValue: big, defaultValue: big,
            unit: "Hz", valueStrings: nil)
        XCTAssertGreaterThan(d.max, d.min, "widen must survive Float32 precision at large min")
        XCTAssertTrue(d.normalized(big).isFinite)
        XCTAssertTrue(d.denormalized(0.5).isFinite)
    }

    // MARK: - Array mapping (U2: the whole parameterTree at once)

    func testDescriptors_mapsWholeTreeInOrder() {
        let params = [
            AUParamMeta(address: 0, displayName: "Cutoff", minValue: 20, maxValue: 20_000,
                        defaultValue: 440, unit: "Hz", valueStrings: nil),
            AUParamMeta(address: 1, displayName: "Wave", minValue: 0, maxValue: 2,
                        defaultValue: 0, unit: "", valueStrings: ["Sine", "Saw", "Sq"]),
        ]
        let ds = AUParameterMapping.descriptors(manufacturer: osType("Echl"),
                                                subType: osType("synt"), params: params)
        XCTAssertEqual(ds.map(\.keyPath), ["au.Echl.synt.0", "au.Echl.synt.1"],
                       "order preserved, address is the leaf")
        XCTAssertEqual(ds[1].valueLabels, ["Sine", "Saw", "Sq"])
        XCTAssertEqual(ds[0].max, 20_000)
    }

    func testDescriptors_emptyTree_isEmpty() {
        XCTAssertTrue(AUParameterMapping.descriptors(manufacturer: osType("Echl"),
                                                     subType: osType("synt"), params: []).isEmpty)
    }

    @MainActor
    func testDescriptors_registerIntoRegistry_isQueryable() {
        let reg = EchoelParameterRegistry()
        let ds = AUParameterMapping.descriptors(
            manufacturer: osType("Echl"), subType: osType("filt"),
            params: [AUParamMeta(address: 3, displayName: "Reso", minValue: 0, maxValue: 1,
                                 defaultValue: 0.3, unit: "", valueStrings: nil)])
        reg.register(ds)
        XCTAssertNotNil(reg.descriptor(for: "au.Echl.filt.3"))
        XCTAssertEqual(reg.search(query: "reso").first?.keyPath, "au.Echl.filt.3")
    }

    func testDescriptor_defaultClampedIntoRange() {
        let d = AUParameterMapping.descriptor(
            manufacturer: osType("Echl"), subType: osType("amp "), address: 2,
            displayName: "Level", minValue: 0, maxValue: 1, defaultValue: 9,
            unit: "", valueStrings: nil)
        XCTAssertEqual(d.defaultValue, 1, accuracy: 1e-9, "out-of-range default is clamped")
    }
}
