// ClipHighlightSelectorTests.swift
// EchoelPublish slice 1 — pin the pure best-window selection that will pick the shareable
// 15-second clip out of a session's liveliness timeline. Deterministic, Foundation-only.

import XCTest
@testable import Echoelmusic

final class ClipHighlightSelectorTests: XCTestCase {

    private typealias Sel = ClipHighlightSelector
    private typealias S = ClipHighlightSelector.Sample

    // Uniformly-sampled timeline helper: one sample per second, energies as given.
    private func timeline(_ energies: [Float], step: Double = 1) -> [S] {
        energies.enumerated().map { S(time: Double($0.offset) * step, energy: $0.element) }
    }

    func testEmpty_returnsNil() {
        XCTAssertNil(Sel.bestWindow(samples: [], length: 15))
    }

    func testShorterThanLength_returnsWholeSpan() {
        // 5 s of samples, asking for a 15 s clip → the whole session span is the clip.
        let w = Sel.bestWindow(samples: timeline([1, 1, 1, 1, 1, 1]), length: 15)
        XCTAssertEqual(w, Sel.Window(start: 0, end: 5))
    }

    func testPeakInMiddle_windowCoversPeak() {
        // Quiet … loud burst around t=20…24 … quiet. 40 s session, 6 s clip.
        var e = [Float](repeating: 0.1, count: 41)
        for i in 20...24 { e[i] = 5.0 }
        guard let w = Sel.bestWindow(samples: timeline(e), length: 6) else {
            return XCTFail("expected a window")
        }
        // The chosen 6 s window must contain the whole 20…24 burst.
        XCTAssertLessThanOrEqual(w.start, 20)
        XCTAssertGreaterThanOrEqual(w.end, 24)
        XCTAssertEqual(w.duration, 6, accuracy: 1e-9)
    }

    func testPeakAtEnd_windowCoversEnd() {
        var e = [Float](repeating: 0.1, count: 31)
        for i in 27...30 { e[i] = 4.0 }
        guard let w = Sel.bestWindow(samples: timeline(e), length: 5) else {
            return XCTFail("expected a window")
        }
        XCTAssertGreaterThanOrEqual(w.end, 30, "window must reach the end-of-session burst")
    }

    func testTie_prefersEarliestWindow() {
        // Two identical bursts (t=5…6 and t=25…26). The earlier one must win (determinism).
        var e = [Float](repeating: 0.0, count: 31)
        e[5] = 3; e[6] = 3
        e[25] = 3; e[26] = 3
        guard let w = Sel.bestWindow(samples: timeline(e), length: 4) else {
            return XCTFail("expected a window")
        }
        XCTAssertLessThan(w.start, 10, "a tie must resolve to the earliest max window")
    }

    func testNonFiniteAndNegativeEnergy_treatedAsZero_doesNotWin() {
        // A NaN/inf/negative spike must NOT attract the window; the real (finite) burst wins.
        var e = [Float](repeating: 0.0, count: 31)
        e[2] = .nan; e[3] = .infinity; e[4] = -100      // garbage cluster near the start
        e[20] = 2; e[21] = 2; e[22] = 2                 // the genuine highlight
        guard let w = Sel.bestWindow(samples: timeline(e), length: 5) else {
            return XCTFail("expected a window")
        }
        // The chosen window must cover the genuine burst (20…22) and sit nowhere near the
        // garbage cluster (2…4) — proving NaN/inf/negative energy scored as 0.
        XCTAssertLessThanOrEqual(w.start, 20, "window must include the real burst start")
        XCTAssertGreaterThanOrEqual(w.end, 22, "window must include the real burst end")
        XCTAssertGreaterThan(w.start, 4, "garbage cluster must not attract the window")
    }

    func testUnsortedInput_isHandled() {
        // Same middle burst, but samples delivered out of order → identical result.
        var e = [Float](repeating: 0.1, count: 41)
        for i in 20...24 { e[i] = 5.0 }
        let shuffledButDeterministic = timeline(e).reversed().map { $0 }
        guard let w = Sel.bestWindow(samples: shuffledButDeterministic, length: 6) else {
            return XCTFail("expected a window")
        }
        XCTAssertLessThanOrEqual(w.start, 20)
        XCTAssertGreaterThanOrEqual(w.end, 24)
    }

    func testNonUniformSamples_windowNeverEndsPastSession() {
        // Sparse quiet head, then a loud pair at t=28 and t=30 (= session end). The winning
        // left-anchor (t=28) would give [28,33] — 3 s past the end — without the clamp.
        let s = [S(time: 0, energy: 0.1), S(time: 10, energy: 0.1),
                 S(time: 28, energy: 5), S(time: 30, energy: 5)]
        guard let w = Sel.bestWindow(samples: s, length: 5) else { return XCTFail("expected a window") }
        XCTAssertLessThanOrEqual(w.end, 30, "clip must never reference audio past the session end")
        XCTAssertEqual(w.duration, 5, accuracy: 1e-9, "the full clip length is preserved")
        XCTAssertGreaterThanOrEqual(w.start, 0)
    }

    func testNonFiniteTimestamp_isDropped() {
        // A NaN-timestamped sample (with huge energy) must be ignored entirely, not poison
        // the span. The remaining finite session (0…2 s) is shorter than 15 s → whole span.
        let s = [S(time: .nan, energy: 100),
                 S(time: 0, energy: 1), S(time: 1, energy: 1), S(time: 2, energy: 1)]
        XCTAssertEqual(Sel.bestWindow(samples: s, length: 15), Sel.Window(start: 0, end: 2))
    }

    func testDefaultLength_is15Seconds() {
        // 60 s flat session → any 15 s window is optimal; the earliest (start 0) wins, and the
        // default length must be 15 (the vision's clip length).
        let w = Sel.bestWindow(samples: timeline([Float](repeating: 1, count: 61)))
        XCTAssertEqual(w?.duration, 15, "default clip length must be 15 s")
        XCTAssertEqual(w?.start, 0, accuracy: 1e-9, "a flat session resolves the tie to the start")
    }
}
