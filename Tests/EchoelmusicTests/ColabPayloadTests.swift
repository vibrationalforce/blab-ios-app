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
            // #493 — the tone system now travels with a take alongside `a4Hz`, and the
            // initialiser deliberately gives it NO default (#440/#443). A shared session states
            // what it was played in; `nil` means "this take predates the field".
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 4, a4Hz: 440,
            toneSystemID: "edo12", moodFields: nil, artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 62, startStep: 0, lengthSteps: 2, velocity: 0.7)],
            rawTake: nil,
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

    // MARK: - Bio peek (E5: side-by-side live numbers, no cross-person score)

    func testBioPayloadRoundTrips() {
        let peek = BioPeek(bpm: 72, coherence: 0.61, hrvNormalized: 0.44, breathRate: 5.5)
        let original = ColabPayload(kind: "bio", senderName: "Stage iPhone", bio: peek)
        guard let data = original.encoded() else { return XCTFail("encode failed") }
        let back = ColabPayload.decode(data)
        XCTAssertEqual(back, original)
        XCTAssertEqual(back?.bio?.bpm, 72)
        XCTAssertNil(back?.project, "a bio ping never carries a session")
    }

    func testOldPayloadWithoutBioFieldStillDecodes() {
        // Forward compatibility: a pre-E5 sender's JSON has no "bio" key.
        let legacy = Data(#"{"kind":"session","senderName":"Old"}"#.utf8)
        let back = ColabPayload.decode(legacy)
        XCTAssertNotNil(back)
        XCTAssertNil(back?.bio)
    }

    func testBioPayloadIsTiny() {
        // Streams at 2–3 Hz — the wire format must stay a few hundred bytes.
        let peek = BioPeek(bpm: 72.4, coherence: 0.61, hrvNormalized: 0.44, breathRate: 5.5)
        let data = ColabPayload(kind: "bio", senderName: String(repeating: "N", count: 63),
                                bio: peek).encoded()
        XCTAssertNotNil(data)
        XCTAssertLessThan(data?.count ?? .max, 512)
    }
}
