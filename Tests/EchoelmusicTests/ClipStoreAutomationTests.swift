// ClipStoreAutomationTests.swift
// Automation-in-Spur L1 / S1 (Founder REIHENFOLGE item 1): pins the clip-scoped
// automation write-back `ClipStore.setClipAutomation(id:lanes:)`. The clip already
// CARRIES + PLAYS `Clip.automation` (setClipAutomation from every launch path);
// this store mutation is the missing EDITING seam (the draw-into-clip editor's S2
// write-back). Pure store contract, Linux-CI testable.
//
// Pattern (from PrimaryRollClipStoreTests): ClipStore persists to the shared
// App-Group fallback, so every test snapshots the slots it touches and restores
// them, and uses a fresh clip id per case.

import XCTest
@testable import Echoelmusic

@MainActor
final class ClipStoreAutomationTests: XCTestCase {

    private func snapshot(_ store: ClipStore) -> [Clip?] { store.slots }

    private func restore(_ store: ClipStore, _ before: [Clip?]) {
        for i in 0..<ClipStore.slotCount {
            if let c = before[i] { store.setClip(at: i, c) } else { store.clear(at: i) }
        }
    }

    private func lane(_ parameter: String, value: Double = 0.5) -> AutomationLane {
        var l = AutomationLane(parameter: parameter)
        l.addPoint(tick: 0, value: value)
        l.addPoint(tick: 480, value: 1 - value)
        return l
    }

    private func midiClip() -> Clip { Clip(name: "auto-\(UUID())", kind: .midi) }
    private func audioClip() -> Clip {
        Clip(name: "auto-\(UUID())", kind: .audio, mediaRef: "/tmp/x.wav")
    }

    // MARK: - Write

    func testSetClipAutomation_writesLanes_returnsTrue() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        let clip = midiClip()
        store.setClip(at: 0, clip)

        let lanes = [lane("ddsp.filter.cutoff")]
        let ok = store.setClipAutomation(id: clip.id, lanes: lanes)

        XCTAssertTrue(ok)
        XCTAssertEqual(store.clip(id: clip.id)?.automation, lanes)
    }

    func testSetClipAutomation_unknownID_returnsFalse_writesNothing() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        let clip = midiClip()
        store.setClip(at: 0, clip)

        let ok = store.setClipAutomation(id: UUID(), lanes: [lane("mix.level")])

        XCTAssertFalse(ok)
        XCTAssertTrue(store.clip(id: clip.id)?.automation.isEmpty ?? false,
                      "an unknown id must not touch any clip's automation")
    }

    func testSetClipAutomation_identicalLanes_returnsTrue_stateUnchanged() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        let lanes = [lane("reverb.mix")]
        var clip = midiClip()
        clip.automation = lanes
        store.setClip(at: 0, clip)

        // Writing VALUE-equal lanes back returns true and leaves the state
        // unchanged (the no-persist side of the guard is not observable here —
        // the suite has no persist spy, same limitation as updateComposerMelody).
        let ok = store.setClipAutomation(id: clip.id, lanes: lanes)

        XCTAssertTrue(ok)
        XCTAssertEqual(store.clip(id: clip.id)?.automation, lanes)
    }

    func testSetClipAutomation_replacesExistingLanes() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        var clip = midiClip()
        clip.automation = [lane("ddsp.osc.brightness", value: 0.2)]
        store.setClip(at: 0, clip)

        let replacement = [lane("ddsp.filter.cutoff", value: 0.9)]
        let ok = store.setClipAutomation(id: clip.id, lanes: replacement)

        XCTAssertTrue(ok)
        XCTAssertEqual(store.clip(id: clip.id)?.automation, replacement,
                       "whole-value replace — old lanes are gone, not merged")
    }

    func testSetClipAutomation_emptyClearsLanes() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        var clip = midiClip()
        clip.automation = [lane("mix.level")]
        store.setClip(at: 0, clip)

        let ok = store.setClipAutomation(id: clip.id, lanes: [])

        XCTAssertTrue(ok)
        XCTAssertTrue(store.clip(id: clip.id)?.automation.isEmpty ?? false)
    }

    // MARK: - Kind-agnostic (automation plays whenever the clip plays)

    func testSetClipAutomation_appliesToAudioClip() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        let clip = audioClip()
        store.setClip(at: 0, clip)

        let lanes = [lane("mix.level", value: 0.75)]
        let ok = store.setClipAutomation(id: clip.id, lanes: lanes)

        XCTAssertTrue(ok, "automation is kind-agnostic — an audio clip carries it too")
        XCTAssertEqual(store.clip(id: clip.id)?.automation, lanes)
    }

    // MARK: - Persistence round-trip (survives a fresh store load)

    func testSetClipAutomation_survivesReload() {
        let store = ClipStore()
        let before = snapshot(store); defer { restore(store, before) }
        let clip = midiClip()
        store.setClip(at: 0, clip)
        let lanes = [lane("ddsp.filter.cutoff", value: 0.33)]
        _ = store.setClipAutomation(id: clip.id, lanes: lanes)

        // A fresh store reads the same App-Group file → the lanes persisted.
        let reloaded = ClipStore()
        XCTAssertEqual(reloaded.clip(id: clip.id)?.automation, lanes)
    }
}
