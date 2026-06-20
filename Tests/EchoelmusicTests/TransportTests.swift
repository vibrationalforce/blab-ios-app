// TransportTests.swift
// Echoel — the unified clock's pure control plane: tempo/swing clamping, the
// derived position fields (beat / ppqTick / absoluteStep), the bar wrap on the
// 15→0 boundary, and priority-ordered subscription (arrangement-before-melody).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class TransportTests: XCTestCase {

    func testTempo_clampsToRange() {
        let t = Transport()
        t.setTempo(10);  XCTAssertEqual(t.tempo, Transport.minTempo)
        t.setTempo(999); XCTAssertEqual(t.tempo, Transport.maxTempo)
        t.setTempo(128); XCTAssertEqual(t.tempo, 128, accuracy: 1e-9)
    }

    func testSwing_clampsToHalf() {
        let t = Transport()
        t.setSwing(-1); XCTAssertEqual(t.swing, 0, accuracy: 1e-9)
        t.setSwing(9);  XCTAssertEqual(t.swing, 0.5, accuracy: 1e-9)
    }

    func testPosition_derivedFields() {
        let p = TransportPosition(bar: 2, step: 6)
        XCTAssertEqual(p.beat, 1)                       // 6 / 4
        XCTAssertEqual(p.ppqTick, 36)                   // 6 * 6
        XCTAssertEqual(p.absoluteStep, 2 * 16 + 6)
    }

    func testTick_advancesStepWithinBar() {
        let t = Transport()
        t.play()
        for s in 1..<16 { t.tick(step: s) }
        XCTAssertEqual(t.position.bar, 0)
        XCTAssertEqual(t.position.step, 15)
        XCTAssertEqual(t.position.beat, 3)
    }

    func testTick_wrapsToNextBarOnReturnToZero() {
        let t = Transport()
        t.play()
        for s in 1..<16 { t.tick(step: s) }
        t.tick(step: 0)                                 // 15 → 0 = bar boundary
        XCTAssertEqual(t.position.bar, 1)
        XCTAssertEqual(t.position.step, 0)
    }

    func testStepSubscriber_firesInPriorityOrder() {
        let t = Transport()
        var order: [String] = []
        t.addStepSubscriber("melody", priority: 10) { _ in order.append("melody") }
        t.addStepSubscriber("arrangement", priority: 0) { _ in order.append("arrangement") }
        t.play()
        t.tick(step: 1)
        XCTAssertEqual(order, ["arrangement", "melody"])  // lower priority first
    }

    func testStepSubscriber_receivesPosition() {
        let t = Transport()
        var seen: TransportPosition?
        t.addStepSubscriber("x") { seen = $0 }
        t.play()
        t.tick(step: 5)
        XCTAssertEqual(seen, TransportPosition(bar: 0, step: 5))
    }

    func testRemovedSubscriber_doesNotFire() {
        let t = Transport()
        var fired = 0
        t.addStepSubscriber("x") { _ in fired += 1 }
        t.removeSubscriber("x")
        t.play()
        t.tick(step: 1)
        XCTAssertEqual(fired, 0)
    }

    func testReaddingSameID_replacesNotDuplicates() {
        let t = Transport()
        var count = 0
        t.addStepSubscriber("x") { _ in count += 1 }
        t.addStepSubscriber("x") { _ in count += 1 }   // replaces
        t.play()
        t.tick(step: 1)
        XCTAssertEqual(count, 1)
    }

    func testPlay_resetsPosition() {
        let t = Transport()
        t.play(); t.tick(step: 1); t.tick(step: 2)
        t.play()
        XCTAssertTrue(t.isPlaying)
        XCTAssertEqual(t.position, .zero)
    }

    func testStop_resetsPositionAndFiresStopSubscribers() {
        let t = Transport()
        var stopped = false
        t.addStopSubscriber("flush") { stopped = true }
        t.play(); t.tick(step: 4)
        t.stop()
        XCTAssertFalse(t.isPlaying)
        XCTAssertEqual(t.position, .zero)
        XCTAssertTrue(stopped)
    }

    func testSeek_setsPositionWithoutChangingPlayState() {
        let t = Transport()
        XCTAssertFalse(t.isPlaying)
        t.seek(toBar: 3, step: 8)
        XCTAssertFalse(t.isPlaying)
        XCTAssertEqual(t.position, TransportPosition(bar: 3, step: 8))
        // A subsequent wrap continues from the sought bar.
        t.tick(step: 0)
        XCTAssertEqual(t.position.bar, 4)
    }
}
#endif
