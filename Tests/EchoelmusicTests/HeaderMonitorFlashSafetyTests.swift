// HeaderMonitorFlashSafetyTests.swift
// The immersive header tile pulses its brightness at the heart rate. WCAG epilepsy
// guidance + the app's OWN law cap visual flashing at 3 Hz — so the pulse rate must be
// clamped no matter how fast the measured heart rate is (a real >180 BPM would otherwise
// drive the tile past the safe rate). These pin that clamp.

#if canImport(SwiftUI)
import XCTest
@testable import Echoelmusic

final class HeaderMonitorFlashSafetyTests: XCTestCase {

    func testPulseRate_belowCap_isHeartRateInHz() {
        // 120 BPM = 2 Hz, under the 2.5 Hz ceiling → passes through unchanged.
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 120), 2.0, accuracy: 1e-9)
    }

    func testPulseRate_atAndAboveCap_isClampedToCeiling() {
        // 150 BPM = 2.5 Hz sits exactly on the ceiling; 180/240 BPM would be 3.0/4.0 Hz
        // and MUST clamp down to 2.5 Hz (never at or above the 3 Hz WCAG limit).
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 150), 2.5, accuracy: 1e-9)
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 180), 2.5, accuracy: 1e-9)
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 240), 2.5, accuracy: 1e-9)
    }

    func testPulseRate_neverReachesTheThreeHertzLimit_acrossFullRange() {
        // The hard law: for ANY plausible (or implausibly high) heart rate, the flash rate
        // stays strictly below 3 Hz.
        for bpm in stride(from: 0.0, through: 400.0, by: 5.0) {
            XCTAssertLessThan(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: bpm), 3.0,
                              "flash rate must stay below the 3 Hz WCAG ceiling at \(bpm) BPM")
        }
    }

    func testPulseRate_lowHeartRate_hasAFloor() {
        // A missing/zero reading floors at 40 BPM so the tile still gently breathes
        // (never a frozen 0 Hz), consistent with the render default.
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 0),
                       40.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 30),
                       40.0 / 60.0, accuracy: 1e-9)
    }
}
#endif
