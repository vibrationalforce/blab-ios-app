// ArrangementPlayerTests.swift
// Echoel — the arrangement engine driving the live transport. Feeds bars by
// hand (no clock) and asserts the player loads the right clip at each section
// boundary, advances its playhead, loops, and finishes. Bar-advance math itself
// is covered purely in ArrangementTests; here we verify the wiring to the live
// PatternEngine + PianoRollModel + ClipStore.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class ArrangementPlayerTests: XCTestCase {

    /// 8 tracks × 16 steps, all off except the cells in `hits` (track,step).
    private func grid(_ hits: [(Int, Int)]) -> [[Bool]] {
        var g = Array(repeating: Array(repeating: false, count: 16), count: 8)
        for (t, s) in hits { g[t][s] = true }
        return g
    }

    private func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: 16), count: 8)
    }

    /// Simulate one full bar of transport: steps 1…15 then the wrap to 0.
    private func feedBar(_ player: ArrangementPlayer) {
        for s in 1...15 { player.transportStep(s) }
        player.transportStep(0)
    }

    private func makeClips() -> (ClipStore, Clip, Clip) {
        let clips = ClipStore()
        let drumClip = Clip(
            name: "Drums",
            drums: DrumPattern(steps: grid([(0, 0), (2, 4)]), accents: emptyGrid())
        )
        let melodyClip = Clip(
            name: "Melody",
            melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.9)])
        )
        clips.setClip(at: 0, drumClip)
        clips.setClip(at: 1, melodyClip)
        return (clips, drumClip, melodyClip)
    }

    func testPlayLoadsFirstSectionClip() {
        let (clips, drumClip, _) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 1)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        player.play(store: store, clips: clips, pattern: pattern, pianoRoll: roll)

        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(pattern.steps[0][0], "section A's drum clip is loaded on play")
        XCTAssertTrue(pattern.steps[2][4])
        player.stop()
        store.clearAll()
    }

    func testJumpSeeksToSectionAndLoadsItsClip() {
        let (clips, drumClip, melodyClip) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 4)
        store.addSection(clipID: melodyClip.id, name: "B", lengthBars: 4)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        player.play(store: store, clips: clips, pattern: pattern, pianoRoll: roll)
        XCTAssertEqual(player.currentIndex, 0)

        // Tap-to-seek straight to section B without waiting out section A's bars.
        player.jump(to: 1)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(roll.notes.first?.pitch, 60, "section B's melody clip loaded immediately")
        XCTAssertFalse(pattern.steps[0][0], "section A's drums replaced")

        player.stop()
        store.clearAll()
    }

    func testJumpIsNoOpWhenStopped() {
        let (clips, drumClip, melodyClip) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 4)
        store.addSection(clipID: melodyClip.id, name: "B", lengthBars: 4)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        // Never started → jump must do nothing (the list is the editor when stopped).
        player.jump(to: 1)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentIndex, 0)
        store.clearAll()
    }

    func testAdvancesToNextSectionAtBarBoundary() {
        let (clips, drumClip, melodyClip) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 1)
        store.addSection(clipID: melodyClip.id, name: "B", lengthBars: 1)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        player.loopEnabled = false
        player.play(store: store, clips: clips, pattern: pattern, pianoRoll: roll)
        XCTAssertEqual(player.currentIndex, 0)

        // Complete bar 1 → cross into section B (the melody clip).
        feedBar(player)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(roll.notes.count, 1, "section B's melody is loaded")
        XCTAssertEqual(roll.notes.first?.pitch, 60)
        XCTAssertFalse(pattern.steps[0][0], "drum clip replaced by melody-only clip")

        player.stop()
        store.clearAll()
    }

    func testFinishesWhenNotLooping() {
        let (clips, drumClip, _) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 1)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        player.loopEnabled = false
        player.play(store: store, clips: clips, pattern: pattern, pianoRoll: roll)

        feedBar(player) // completes the only section → finished
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(pattern.isPlaying, "transport stops when a non-looping song ends")
        store.clearAll()
    }

    func testLoopsBackToStart() {
        let (clips, drumClip, melodyClip) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 1)
        store.addSection(clipID: melodyClip.id, name: "B", lengthBars: 1)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        player.loopEnabled = true
        player.play(store: store, clips: clips, pattern: pattern, pianoRoll: roll)

        feedBar(player) // → B
        XCTAssertEqual(player.currentIndex, 1)
        feedBar(player) // → loop back to A
        XCTAssertEqual(player.currentIndex, 0)
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(pattern.steps[0][0], "looping reloads section A's drum clip")

        player.stop()
        store.clearAll()
    }

    func testTwoBarSectionHoldsBeforeAdvancing() {
        let (clips, drumClip, melodyClip) = makeClips()
        let store = ArrangementStore()
        store.clearAll()
        store.addSection(clipID: drumClip.id, name: "A", lengthBars: 2)
        store.addSection(clipID: melodyClip.id, name: "B", lengthBars: 1)

        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let player = ArrangementPlayer()
        player.loopEnabled = false
        player.play(store: store, clips: clips, pattern: pattern, pianoRoll: roll)

        feedBar(player) // bar 1 of 2 → still section A
        XCTAssertEqual(player.currentIndex, 0)
        feedBar(player) // bar 2 of 2 → advance to B
        XCTAssertEqual(player.currentIndex, 1)

        player.stop()
        store.clearAll()
    }
}
#endif
