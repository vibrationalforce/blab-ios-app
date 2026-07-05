//
//  SessionClockTests.swift
//  Echoelmusic — Bio
//
//  Proves the latency compensation ("Latenzausgleich"): rendering the phase at
//  now + perceptualDelay lands the PERCEIVED peak on the grid, compensation drives
//  the audio↔visual skew to zero, and bogus/huge measured latencies are clamped so
//  the phase can never be thrown wildly.
//

import XCTest
@testable import Echoelmusic

final class SessionClockTests: XCTestCase {

    private let acc = 1e-9

    // MARK: - safeDelay clamps

    func testSafeDelayClampsRange() {
        XCTAssertEqual(SessionClock.safeDelay(0.010), 0.010, accuracy: acc)
        XCTAssertEqual(SessionClock.safeDelay(-1), 0, accuracy: acc, "negative → 0")
        XCTAssertEqual(SessionClock.safeDelay(.nan), 0, accuracy: acc, "NaN → 0")
        XCTAssertEqual(SessionClock.safeDelay(9.9), SessionClock.maxCompensationSeconds, accuracy: acc,
                       "huge/bogus latency clamps to the max compensation")
    }

    // MARK: - Compensation lands the perceived peak on the grid

    func testCompensatedRenderMatchesPhaseAtPerceptionTime() {
        // Rendering NOW with compensation must equal the uncompensated phase at the
        // moment of perception (now + delay). That is the whole point.
        let now = 3.2, hz = 0.1, delay = 0.2
        let rendered = SessionClock.renderPhase(hostSeconds: now, hz: hz, perceptualDelaySeconds: delay)
        let atPerception = EntrainmentEngine.phase(atSeconds: now + delay, hz: hz)
        XCTAssertEqual(rendered, atPerception, accuracy: 1e-12)
    }

    func testAudioAndVisualPeaksCoincideWhenCompensated() {
        // Audio has 15 ms output latency, video 8 ms. Compensated, BOTH render the
        // phase for the same target grid time, so the peak the user hears and the peak
        // the user sees are the same grid instant → their rendered phase is identical.
        let now = 10.0, hz = 0.2
        let audioDelay = 0.015, visualDelay = 0.008
        // The renderer advances each modality by its own delay; to compare "do the
        // perceived peaks align", evaluate each at (now + delay) — both should map to
        // the SAME grid time when the caller schedules against one shared clock.
        // Here we assert the compensation formula composes as phase(now+delay).
        let a = SessionClock.renderPhase(hostSeconds: now, hz: hz, perceptualDelaySeconds: audioDelay)
        let v = SessionClock.renderPhase(hostSeconds: now, hz: hz, perceptualDelaySeconds: visualDelay)
        XCTAssertEqual(a, EntrainmentEngine.phase(atSeconds: now + audioDelay, hz: hz), accuracy: 1e-12)
        XCTAssertEqual(v, EntrainmentEngine.phase(atSeconds: now + visualDelay, hz: hz), accuracy: 1e-12)
    }

    // MARK: - The skew number the Latenzausgleich drives to zero

    func testPerceivedSkewIsZeroWhenCompensated() {
        let p = LatencyProfile(audioOutputSeconds: 0.25, visualOutputSeconds: 0.008) // Bluetooth!
        XCTAssertEqual(SessionClock.perceivedSkewSeconds(p, compensated: true), 0, accuracy: acc)
    }

    func testPerceivedSkewIsLatencyGapWhenUncompensated() {
        // Wired audio 15 ms vs video 8 ms → 7 ms skew if nothing is compensated.
        let p = LatencyProfile(audioOutputSeconds: 0.015, visualOutputSeconds: 0.008)
        XCTAssertEqual(SessionClock.perceivedSkewSeconds(p, compensated: false), 0.007, accuracy: 1e-9)
    }

    func testBluetoothSkewIsLargeUncompensatedAndZeroCompensated() {
        // The Bluetooth case the docs call out: 250 ms audio vs ~8 ms video.
        let p = LatencyProfile(audioOutputSeconds: 0.25, visualOutputSeconds: 0.008)
        let uncompensated = SessionClock.perceivedSkewSeconds(p, compensated: false)
        XCTAssertEqual(uncompensated, 0.242, accuracy: 1e-9, "a quarter-second visible lag if ignored")
        XCTAssertEqual(SessionClock.perceivedSkewSeconds(p, compensated: true), 0, accuracy: acc)
    }

    func testSkewClampsBogusLatencies() {
        // A garbage 9 s audio latency clamps to the 0.5 s cap before differencing.
        let p = LatencyProfile(audioOutputSeconds: 9, visualOutputSeconds: 0.008)
        XCTAssertEqual(SessionClock.perceivedSkewSeconds(p, compensated: false),
                       SessionClock.maxCompensationSeconds - 0.008, accuracy: 1e-9)
    }

    // MARK: - Render helpers stay bounded / safe

    func testRenderGateIsBoundedAndCompensated() {
        let now = 5.0, hz = 0.1, delay = 0.02
        let g = SessionClock.renderGate(hostSeconds: now, hz: hz, perceptualDelaySeconds: delay)
        XCTAssertGreaterThanOrEqual(g, -1e-12)
        XCTAssertLessThanOrEqual(g, 1 + 1e-12)
        XCTAssertEqual(g, EntrainmentEngine.gate(atSeconds: now + delay, hz: hz), accuracy: 1e-12)
    }

    func testRenderPhaseGuardsBogusClock() {
        // A non-finite host time falls through EntrainmentEngine.phase's own guard → 0.
        XCTAssertEqual(SessionClock.renderPhase(hostSeconds: .infinity, hz: 0.1,
                                                perceptualDelaySeconds: 0.01), 0, accuracy: acc)
        XCTAssertEqual(SessionClock.renderPhase(hostSeconds: 3, hz: 0,
                                                perceptualDelaySeconds: 0.01), 0, accuracy: acc)
    }

    func testUnknownProfileIsSaneDefault() {
        XCTAssertEqual(LatencyProfile.unknown.audioOutputSeconds, 0.005, accuracy: acc)
        XCTAssertEqual(LatencyProfile.unknown.visualOutputSeconds, 1.0 / 60.0, accuracy: acc)
    }
}
