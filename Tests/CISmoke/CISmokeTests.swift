// CISmokeTests.swift
// Walking-skeleton test that proves the CI test PLUMBING works end-to-end:
// xcodegen generates a unit-test target, xcodebuild builds it for the iOS
// simulator, `@testable import Echoelmusic` links the app module, and XCTest
// actually RUNS an assertion. Until 2026-07-20 the 294-file suite ran in NO
// workflow (project.yml declared no test target) — "gates green" only meant the
// app compiled. This tiny target de-risks the plumbing in isolation from the
// question of whether all 294 real test files compile on the iOS-sim target;
// Slice 2 repoints the target at Tests/EchoelmusicTests once this is green.

import XCTest
@testable import Echoelmusic

final class CISmokeTests: XCTestCase {

    /// Proves the test bundle links the app module and runs on the simulator by
    /// exercising a real, pure, core symbol (not a tautology).
    func testAppModuleLinksAndRuns() {
        // MusicalKey is core, pure, deterministic: C-minor root, degree 0 at
        // octave 4 is MIDI 60 by construction (MIDI 60 = C4).
        let key = MusicalKey(root: 0, scale: .minor)
        XCTAssertEqual(key.degree(0, octave: 4), 60,
                       "app module is linked and a real core symbol executes")

        // A second pure symbol added this session — a passing tone snaps down to
        // the nearest chord tone (root) in scale-degree space.
        XCTAssertEqual(
            BioComposer.nearestChordDegree(1, tones: [0, 2, 4], degreesPerOctave: 7), 0,
            "the composition core is reachable from the test target")
    }
}
