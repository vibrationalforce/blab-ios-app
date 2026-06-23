// ColabPayloadTests.swift
// Echoel — Live Colabo wire format. Pure Foundation/Codable (no MultipeerConnectivity),
// so ci.yml EXECUTES these on Linux.

import XCTest
import Foundation
@testable import Echoelmusic

final class ColabPayloadTests: XCTestCase {

    private func sampleProject() -> Project {
        Project(
            name: "Jam", styleRaw: "dubTechno", keyRoot: 5, scaleRaw: "minor", bpm: 122,
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 4, a4Hz: 440, artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 62, startStep: 0, lengthSteps: 2, velocity: 0.7)],
            drumSteps: [[true, false]], drumAccents: [[false, false]]
        )
    }

    func testSessionPayloadRoundTrips() {
        let original = ColabPayload(kind: "session", senderName: "Studio iPhone", project: sampleProject())
        guard let data = original.encoded() else { return XCTFail("encode failed") }
        let back = ColabPayload.decode(data)
        XCTAssertEqual(back, original)
        XCTAssertEqual(back?.project?.bpm, 122)
        XCTAssertEqual(back?.senderName, "Studio iPhone")
    }

    func testDecodeInvalidDataIsNil() {
        XCTAssertNil(ColabPayload.decode(Data("nope".utf8)))
    }

    func testPayloadWithoutProjectStillRoundTrips() {
        let ping = ColabPayload(kind: "hello", senderName: "Peer")
        guard let data = ping.encoded() else { return XCTFail("encode failed") }
        XCTAssertEqual(ColabPayload.decode(data), ping)
        XCTAssertNil(ColabPayload.decode(data)?.project)
    }
}
