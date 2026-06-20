// HapticEngineTests.swift
// Echoelmusic — the CoreHaptics player for the BioHaptics cue kernel.
// CI/headless has no Taptic Engine, so these cover the capability-gated,
// crash-safe paths + the data-only cue→pattern translation (no hardware needed).

#if canImport(CoreHaptics)
import XCTest
@testable import Echoelmusic

@available(iOS 13.0, macOS 11.0, *)
@MainActor
final class HapticEngineTests: XCTestCase {

    func testInit_doesNotCrash_andIsNotRunning() {
        let engine = HapticEngine()
        _ = engine.supportsHaptics   // a stable Bool on any host
        XCTAssertFalse(engine.isRunning)
    }

    func testPlay_whenNotRunning_isSafeNoOp() {
        let engine = HapticEngine()
        // No start() → not running → must not crash.
        engine.play(BioHaptics.beat(isDownbeat: true))
        engine.play(BioHaptics.breathPulse(breathPhase: 0.5, coherence: 0.5))
        XCTAssertFalse(engine.isRunning)
    }

    func testStart_onUnsupportedHardware_staysNotRunning() {
        // On CI there is no haptic hardware → start() is a no-op, never throws.
        let engine = HapticEngine()
        if !engine.supportsHaptics {
            engine.start()
            XCTAssertFalse(engine.isRunning)
        }
    }

    func testPattern_buildsForTransientAndContinuous() throws {
        // CHHapticPattern construction is data-only — valid without a device.
        let downbeat = try HapticEngine.pattern(for: BioHaptics.beat(isDownbeat: true))
        let accent = try HapticEngine.pattern(for: BioHaptics.beat(isDownbeat: false, accent: true))
        let breath = try HapticEngine.pattern(
            for: BioHaptics.breathPulse(breathPhase: 0.5, coherence: 0.2, duration: 0.1))
        XCTAssertNotNil(downbeat)
        XCTAssertNotNil(accent)
        XCTAssertNotNil(breath)
    }
}
#endif
