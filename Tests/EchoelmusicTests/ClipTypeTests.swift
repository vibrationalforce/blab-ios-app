// ClipTypeTests.swift
// Echoel — the typed clip layer for the DMMW arrangement: clip kinds, honest
// playability, per-kind emptiness, and backward-compatible decode of old clips.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class ClipTypeTests: XCTestCase {

    func testClipKind_casesAndPlayability() {
        XCTAssertEqual(Set(ClipKind.allCases), [.midi, .audio, .video, .visual])
        XCTAssertTrue(ClipKind.midi.isPlayable)
        XCTAssertFalse(ClipKind.audio.isPlayable)   // engines not shipped → not playable yet
        XCTAssertFalse(ClipKind.video.isPlayable)
        XCTAssertFalse(ClipKind.visual.isPlayable)
    }

    func testDefaultKind_isMidi() {
        XCTAssertEqual(Clip(name: "x").kind, .midi)
    }

    func testOldClipJSON_decodesAsMidi_backCompat() throws {
        // A clip saved before `kind`/`mediaRef` existed.
        let json = """
        {"id":"A1000000-0000-0000-0000-0000000000FF","name":"Legacy","colorIndex":2}
        """.data(using: .utf8)!
        let clip = try JSONDecoder().decode(Clip.self, from: json)
        XCTAssertEqual(clip.kind, .midi)
        XCTAssertEqual(clip.name, "Legacy")
        XCTAssertEqual(clip.colorIndex, 2)
        XCTAssertNil(clip.mediaRef)
    }

    func testTypedClip_roundTrips() throws {
        let clip = Clip(name: "Scene", colorIndex: 1, kind: .video, mediaRef: "Movies/intro.mov")
        let data = try JSONEncoder().encode(clip)
        let back = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(back, clip)
        XCTAssertEqual(back.kind, .video)
        XCTAssertEqual(back.mediaRef, "Movies/intro.mov")
    }

    func testIsEmpty_perKind() {
        // MIDI: empty without pattern content.
        XCTAssertTrue(Clip(name: "m", kind: .midi).isEmpty)
        XCTAssertFalse(Clip(name: "m", kind: .midi,
                            melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)])).isEmpty)
        // Media kinds: empty until they carry a reference.
        XCTAssertTrue(Clip(name: "a", kind: .audio).isEmpty)
        XCTAssertFalse(Clip(name: "a", kind: .audio, mediaRef: "Audio/loop.wav").isEmpty)
    }
}
#endif
