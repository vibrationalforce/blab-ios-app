// ClipTests.swift
// Echoel — clip model + pattern load round-trip + melody MIDI export.

import XCTest
@testable import Echoelmusic

final class ClipTests: XCTestCase {

    func testClipCodableRoundTrip() throws {
        let clip = Clip(
            name: "Verse",
            colorIndex: 2,
            drums: DrumPattern(
                steps: Array(repeating: Array(repeating: false, count: 16), count: 8),
                accents: Array(repeating: Array(repeating: false, count: 16), count: 8)
            ),
            melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8)])
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(decoded, clip)
    }

    func testIsEmpty() {
        let empty = Clip(name: "x")
        XCTAssertTrue(empty.isEmpty)

        let withMelody = Clip(name: "y", melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)]))
        XCTAssertFalse(withMelody.isEmpty)
    }

    func testMelodyMIDIExportProducesValidHeader() {
        let notes = [
            Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.9),
            Note(pitch: 64, startStep: 0, lengthSteps: 4, velocity: 0.7)
        ]
        let data = MIDIFileExporter.export(notes: notes, tempo: 120)
        XCTAssertGreaterThan(data.count, 22, "should contain header + track")
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8), "valid SMF header")
    }
}

@MainActor
final class PatternLoadTests: XCTestCase {

    func testLoadRoundTrip() {
        let a = PatternEngine()
        a.setStep(track: 0, step: 0, on: true)
        a.setStep(track: 3, step: 8, on: true)
        a.setAccent(track: 0, step: 0, on: true)

        let b = PatternEngine()
        b.load(steps: a.steps, accents: a.accents)
        XCTAssertEqual(b.steps, a.steps)
        XCTAssertEqual(b.accents, a.accents)
    }

    func testLoadRejectsWrongDimensions() {
        let engine = PatternEngine()
        let original = engine.steps
        engine.load(steps: [[true]], accents: [[true]]) // wrong shape
        XCTAssertEqual(engine.steps, original, "malformed clip is ignored")
    }
}

#if canImport(AVFoundation) && canImport(Accelerate)
@MainActor
final class ClipStoreTests: XCTestCase {

    func testSetAndClear() {
        let store = ClipStore()
        let clip = Clip(name: "Test", melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)]))
        store.setClip(at: 0, clip)
        XCTAssertEqual(store.slots[0]?.name, "Test")
        store.clear(at: 0)
        XCTAssertNil(store.slots[0])
    }
}
#endif
