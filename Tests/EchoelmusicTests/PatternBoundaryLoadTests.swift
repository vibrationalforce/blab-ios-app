// PatternBoundaryLoadTests.swift
// Echoel — boundary-staged drum loads (founder 2026-07-06B "organisch und
// professionell"): a live re-seed must never chop the sounding bar. While playing,
// `loadAtBoundary` STAGES the groove for the next downbeat; stopped, it loads
// immediately. Foundation-only (no AVFoundation), so ci.yml EXECUTES this on Linux.
// The timer-driven downbeat application itself is exercised on device/CI-macOS via
// the running instrument; here we pin the pure staging semantics that surround it.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class PatternBoundaryLoadTests: XCTestCase {

    /// A full-size grid with one recognizable marker cell per track.
    private func grid(marker: Bool) -> [[Bool]] {
        var g = [[Bool]](repeating: [Bool](repeating: false, count: PatternEngine.stepCount),
                         count: PatternEngine.trackCount)
        if marker {
            for t in 0..<PatternEngine.trackCount { g[t][0] = true }
        }
        return g
    }

    func testStopped_loadAtBoundary_appliesImmediately() {
        let pattern = PatternEngine()
        pattern.loadAtBoundary(steps: grid(marker: true), accents: grid(marker: false))
        XCTAssertTrue(pattern.steps[0][0], "stopped → the grid must be present before playback starts")
    }

    func testPlaying_loadAtBoundary_stagesInsteadOfCutting() {
        let pattern = PatternEngine()
        pattern.play()
        pattern.loadAtBoundary(steps: grid(marker: true), accents: grid(marker: false))
        XCTAssertFalse(pattern.steps[0][0], "playing → the sounding bar must NOT be chopped mid-bar")
        pattern.stop()   // also cancels the real timer source (test hygiene)
        XCTAssertTrue(pattern.steps[0][0], "stop() must flush the staged groove so the next play starts on the newest pattern")
    }

    func testImmediateLoad_supersedesStagedGroove() {
        let pattern = PatternEngine()
        pattern.play()
        pattern.loadAtBoundary(steps: grid(marker: true), accents: grid(marker: false))
        pattern.load(steps: grid(marker: false), accents: grid(marker: false))   // explicit load wins
        pattern.stop()
        XCTAssertFalse(pattern.steps[0][0], "an explicit immediate load must drop any staged groove")
    }

    func testClear_dropsStagedGroove() {
        let pattern = PatternEngine()
        pattern.play()
        pattern.loadAtBoundary(steps: grid(marker: true), accents: grid(marker: false))
        pattern.clear()
        pattern.stop()
        XCTAssertFalse(pattern.steps[0][0], "a cleared grid must not resurrect a staged groove")
    }
}
