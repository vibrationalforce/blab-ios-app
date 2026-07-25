// ClipNativeDurationTests.swift
// The persisted per-clip native media duration (audio/video import measures it; the
// transport players read it for .exhausted / EOF). Pins the Codable round-trip AND
// backward-compat: clips saved before the field decode with nativeDurationSeconds nil.

import XCTest
@testable import Echoelmusic

final class ClipNativeDurationTests: XCTestCase {

    func testRoundTrip_preservesNativeDuration() throws {
        let clip = AudioClipFactory.clip(name: "loop", mediaRef: "/a/loop.wav",
                                         colorIndex: 1, nativeDurationSeconds: 3.75)
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(decoded.nativeDurationSeconds ?? -1, 3.75, accuracy: 1e-9)
        XCTAssertEqual(decoded.mediaRef, "/a/loop.wav")
        XCTAssertEqual(decoded.kind, .audio)
    }

    func testNil_whenNotMeasured() throws {
        // An unmeasured clip carries no duration (via the audio factory's nil default —
        // the video factory was removed in the pure-instrument cut).
        let clip = AudioClipFactory.clip(name: "take", mediaRef: "/a/take.wav")
        let decoded = try JSONDecoder().decode(Clip.self, from: try JSONEncoder().encode(clip))
        XCTAssertNil(decoded.nativeDurationSeconds, "unmeasured clips carry no duration")
    }

    /// A clip saved BEFORE the field existed (JSON without the key) decodes cleanly
    /// with nativeDurationSeconds == nil — no library is lost on upgrade.
    func testLegacyJSON_withoutKey_decodesNil() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"old","colorIndex":0,"kind":"audio",
         "mediaRef":"/old/clip.wav","automation":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Clip.self, from: legacy)
        XCTAssertNil(decoded.nativeDurationSeconds)
        XCTAssertEqual(decoded.mediaRef, "/old/clip.wav")
        XCTAssertEqual(decoded.kind, .audio)
    }
}
