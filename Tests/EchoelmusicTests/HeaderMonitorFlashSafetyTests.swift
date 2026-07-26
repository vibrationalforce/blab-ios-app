// HeaderMonitorFlashSafetyTests.swift
// The immersive header tile pulses its brightness at the heart rate. WCAG epilepsy
// guidance + the app's OWN law cap visual flashing at 3 Hz — so the pulse rate must be
// clamped no matter how fast the measured heart rate is (a real >180 BPM would otherwise
// drive the tile past the safe rate). These pin that clamp.

#if canImport(SwiftUI)
import XCTest
@testable import Echoelmusic

// `@MainActor`: `ImmersiveMonitorMini` is declared `@MainActor` (HeaderMonitors.swift:251),
// so even this pure static is main-actor-isolated and a nonisolated test body cannot call
// it — a hard Swift 6 error. Isolating the test is the smaller of the two fixes; the
// alternative would be `nonisolated static func` in Sources, which is arguably the truer
// statement about a function this pure, but it edits a shipping WCAG-safety law to satisfy
// a test, and the behaviour is identical either way.
@MainActor
final class HeaderMonitorFlashSafetyTests: XCTestCase {

    func testPulseRate_belowCap_isHeartRateInHz() {
        // 120 BPM = 2 Hz, under the 2.5 Hz ceiling → passes through unchanged.
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 120), 2.0, accuracy: 1e-9)
    }

    func testPulseRate_atAndAboveCap_isClampedToTheSharedCeiling() {
        // 150 BPM = 2.5 Hz sits exactly on the ceiling; 180/240 BPM would be 3.0/4.0 Hz and
        // MUST clamp down to it (never at or above the 3 Hz WCAG limit).
        //
        // Reads `FlashGuard.maxPulseRateHz` instead of the three hardcoded 2.5s this used
        // to carry. Those were the LAST copies of the ceiling: the constant was hoisted so
        // no test would validate a duplicate of the value it proves, and this file — which
        // the hoisting diff never opened — kept doing exactly that. They were also an
        // obstruction: TIGHTENING the ceiling to 2.0 would have turned them red, i.e. a
        // change that makes the app safer failing its own safety test.
        for bpm in [150.0, 180.0, 240.0] {
            XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: bpm),
                           FlashGuard.maxPulseRateHz, accuracy: 1e-9,
                           "\(bpm) BPM must clamp to the shared ceiling")
        }
        // Guard the OTHER direction too, so the clamp cannot be "fixed" into flattening
        // normal pulses: a resting rate must pass through untouched.
        XCTAssertEqual(ImmersiveMonitorMini.flashSafePulseRate(heartRateBPM: 60),
                       1.0, accuracy: 1e-9)
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
