// SynthPatchTests.swift
// Echoel — patch round-trip + apply/capture against the DDSP synth.

import XCTest
@testable import Echoelmusic

final class SynthPatchTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let patch = SynthPatch.factory[1] // Bright Lead
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SynthPatch.self, from: data)
        XCTAssertEqual(decoded, patch)
    }

    func testFactoryIDsAreStable() {
        let a = SynthPatch.factory.map { $0.id }
        let b = SynthPatch.factory.map { $0.id }
        XCTAssertEqual(a, b, "factory ids must be stable across accesses/relaunches")
        XCTAssertEqual(Set(a).count, a.count, "factory ids are unique")
    }
}

#if canImport(Accelerate)
final class SynthPatchApplyTests: XCTestCase {

    func testApplyThenCapture() {
        let synth = EchoelDDSP(sampleRate: 48000)
        var patch = SynthPatch(name: "Test")
        patch.brightness = 0.7
        patch.attack = 0.1
        patch.harmonicity = 0.5
        patch.filterCutoff = 1234
        patch.reverbMix = 0.4
        patch.spectralShape = "bright"

        patch.apply(to: synth)
        XCTAssertEqual(synth.brightness, 0.7, accuracy: 0.001)
        XCTAssertEqual(synth.attack, 0.1, accuracy: 0.001)
        XCTAssertEqual(synth.harmonicity, 0.5, accuracy: 0.001)
        XCTAssertEqual(synth.filterCutoff, 1234, accuracy: 0.5)
        XCTAssertEqual(synth.reverbMix, 0.4, accuracy: 0.001)
        XCTAssertEqual(synth.spectralShape.rawValue, "bright")

        let captured = SynthPatch(name: "Captured", from: synth)
        XCTAssertEqual(captured.brightness, 0.7, accuracy: 0.001)
        XCTAssertEqual(captured.attack, 0.1, accuracy: 0.001)
        XCTAssertEqual(captured.spectralShape, "bright")
    }
}
#endif
