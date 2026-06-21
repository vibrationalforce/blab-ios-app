// AUv3HostTests.swift
// Echoel — AUv3 discovery: the pure split/de-dupe/sort that powers the plugin browser
// (the actual device scan depends on installed AUs, so we test the categorization).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class AUv3HostTests: XCTestCase {

    private func au(_ name: String, instrument: Bool, id: String? = nil) -> HostedAUInfo {
        HostedAUInfo(id: id ?? "m.\(name)", name: name, manufacturer: "m", isInstrument: instrument)
    }

    func testSplit_separatesInstrumentsAndEffects_sorted() {
        let infos = [au("Zeta", instrument: true), au("alpha", instrument: false),
                     au("Beta", instrument: true), au("Omega", instrument: false)]
        let s = AUv3Host.split(infos)
        XCTAssertEqual(s.instruments.map(\.name), ["Beta", "Zeta"])   // alpha-sorted, case-insensitive
        XCTAssertEqual(s.effects.map(\.name), ["alpha", "Omega"])
    }

    func testSplit_dedupesByID() {
        let infos = [au("Synth", instrument: true, id: "dup"),
                     au("Synth (copy)", instrument: true, id: "dup")]
        XCTAssertEqual(AUv3Host.split(infos).instruments.count, 1)
    }

    func testSplit_empty() {
        let s = AUv3Host.split([])
        XCTAssertTrue(s.instruments.isEmpty)
        XCTAssertTrue(s.effects.isEmpty)
    }
}
#endif
