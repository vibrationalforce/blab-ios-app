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

    /// The capture→launch round-trip ClipView performs: snapshot the live beat +
    /// melody into a Clip, then launch it into fresh engines and get it back.
    func testCaptureLaunchRoundTrip() {
        let pattern = PatternEngine()
        pattern.setStep(track: 1, step: 4, on: true)
        pattern.setAccent(track: 1, step: 4, on: true)
        let roll = PianoRollModel()
        _ = roll.add(pitch: 62, startStep: 2, lengthSteps: 3, velocity: 0.6)

        // capture (what ClipView.capture does)
        let clip = Clip(
            name: "Take",
            drums: DrumPattern(steps: pattern.steps, accents: pattern.accents),
            melody: MelodyClip(notes: roll.notes)
        )

        // launch into fresh engines (what ClipView.launch does)
        let pattern2 = PatternEngine()
        let roll2 = PianoRollModel()
        if let d = clip.drums { pattern2.load(steps: d.steps, accents: d.accents) }
        if let m = clip.melody { roll2.load(m.notes) }

        XCTAssertEqual(pattern2.steps, pattern.steps)
        XCTAssertEqual(pattern2.accents, pattern.accents)
        XCTAssertEqual(roll2.notes.map { $0.pitch }, [62])
        XCTAssertEqual(roll2.notes.first?.lengthSteps, 3)
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

    /// Slice A ownership law: the composer write-back may touch ONLY clips the
    /// composer created (`composerOwned`); a user clip is refused untouched.
    func testUpdateComposerMelody_refusesUserClip_writesOwnClip() {
        let store = ClipStore()
        let userNotes = [Note(pitch: 60, startStep: 0)]
        let user = Clip(name: "User take", melody: MelodyClip(notes: userNotes))
        let owned = Clip(name: "Lane take", melody: MelodyClip(notes: []),
                         composerOwned: true)
        store.setClip(at: 0, user)
        store.setClip(at: 1, owned)

        let composed = [Note(pitch: 64, startStep: 4)]
        XCTAssertFalse(store.updateComposerMelody(id: user.id, notes: composed))
        XCTAssertEqual(store.slots[0]?.melody?.notes, userNotes)   // never clobbered

        XCTAssertTrue(store.updateComposerMelody(id: owned.id, notes: composed))
        XCTAssertEqual(store.slots[1]?.melody?.notes, composed)
    }

    /// Back-compat: clips persisted before the ownership mark decode as
    /// user-owned (`false`) — the safe side of the never-clobber law.
    func testComposerOwned_decodesFalseForLegacyClip() throws {
        let legacy = Clip(name: "Old", melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)]))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "composerOwned")   // simulate a pre-Slice-A document
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertFalse(decoded.composerOwned)
    }
}
#endif
