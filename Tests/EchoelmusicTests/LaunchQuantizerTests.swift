// LaunchQuantizerTests.swift
// Echoel — bar-quantized Session launching: the pure defer decision, immediate
// launch when stopped or unquantized, and deferred firing on the bar boundary.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class LaunchQuantizerTests: XCTestCase {

    private func grid(_ hits: [(Int, Int)]) -> [[Bool]] {
        var g = Array(repeating: Array(repeating: false, count: 16), count: 8)
        for (t, s) in hits { g[t][s] = true }
        return g
    }
    private func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: 16), count: 8)
    }
    private func feedBar(_ q: LaunchQuantizer) {
        for s in 1...15 { q.transportStep(s) }
        q.transportStep(0)
    }
    private func drumClip() -> Clip {
        Clip(name: "D", drums: DrumPattern(steps: grid([(0, 0)]), accents: emptyGrid()))
    }

    // MARK: - Pure decision

    func testShouldDeferOnlyWhilePlayingAndQuantized() {
        XCTAssertTrue(LaunchQuantizer.shouldDefer(isPlaying: true, quantizeEnabled: true))
        XCTAssertFalse(LaunchQuantizer.shouldDefer(isPlaying: false, quantizeEnabled: true))
        XCTAssertFalse(LaunchQuantizer.shouldDefer(isPlaying: true, quantizeEnabled: false))
        XCTAssertFalse(LaunchQuantizer.shouldDefer(isPlaying: false, quantizeEnabled: false))
    }

    // MARK: - Immediate launch

    func testRequestWhenStoppedLaunchesAndStartsTransport() {
        let pattern = PatternEngine()
        let roll = PianoRollModel()
        let q = LaunchQuantizer()
        q.request(drumClip(), pattern: pattern, pianoRoll: roll)
        XCTAssertTrue(pattern.steps[0][0], "clip loaded immediately when stopped")
        XCTAssertTrue(pattern.isPlaying, "transport starts on a tap from stopped")
        XCTAssertNil(q.pendingClipID)
        pattern.stop()
    }

    func testRequestWithQuantizeOffLaunchesImmediately() {
        let pattern = PatternEngine()
        let roll = PianoRollModel()
        pattern.play()
        let q = LaunchQuantizer()
        q.quantizeEnabled = false
        q.request(drumClip(), pattern: pattern, pianoRoll: roll)
        XCTAssertTrue(pattern.steps[0][0], "unquantized launch is immediate")
        XCTAssertNil(q.pendingClipID)
        pattern.stop()
    }

    // MARK: - Deferred launch

    func testRequestWhilePlayingQueuesUntilBarBoundary() {
        let pattern = PatternEngine()
        let roll = PianoRollModel()
        pattern.play() // currentStep resets to 0; steps still empty
        let q = LaunchQuantizer()
        let clip = drumClip()
        q.request(clip, pattern: pattern, pianoRoll: roll)
        XCTAssertEqual(q.pendingClipID, clip.id, "the tapped clip is queued")
        XCTAssertFalse(pattern.steps[0][0], "live pattern unchanged until the bar")

        feedBar(q) // wrap to 0 → fire
        XCTAssertTrue(pattern.steps[0][0], "queued clip fires on the bar boundary")
        XCTAssertNil(q.pendingClipID)
        pattern.stop()
    }

    func testCancelPendingDropsTheQueuedLaunch() {
        let pattern = PatternEngine()
        let roll = PianoRollModel()
        pattern.play()
        let q = LaunchQuantizer()
        q.request(drumClip(), pattern: pattern, pianoRoll: roll)
        XCTAssertNotNil(q.pendingClipID)
        q.cancelPending()
        XCTAssertNil(q.pendingClipID)
        feedBar(q)
        XCTAssertFalse(pattern.steps[0][0], "cancelled launch never fires")
        pattern.stop()
    }
}
#endif
