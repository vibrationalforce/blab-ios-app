// AppGroupStoreTests.swift
// Echoel — locks the load() contract that A4 (decode-failure telemetry) touched:
// an ABSENT file is a silent nil, a valid file round-trips, and a present-but-
// undecodable file returns nil (the catch path that now also logs) WITHOUT crashing.
// The log itself is a side-effect we don't assert; the behavioral contract is what
// must hold so a schema change can't turn a decode failure into a crash.

import XCTest
@testable import Echoelmusic

final class AppGroupStoreTests: XCTestCase {

    // Unique subdirectory per test run so cases don't collide on the shared container.
    private func store() -> AppGroupStore {
        AppGroupStore(subdirectory: "AppGroupStoreTests-\(UUID().uuidString)")
    }

    func testLoad_absentFile_returnsNilSilently() {
        let s = store()
        XCTAssertNil(s.load([Int].self, name: "never-saved"))
    }

    func testSaveLoad_validRoundTrip() {
        let s = store()
        let value = ["kick", "snare", "hat"]
        XCTAssertTrue(s.save(value, name: "pattern"))
        XCTAssertEqual(s.load([String].self, name: "pattern"), value)
        s.delete(name: "pattern")
    }

    func testLoad_presentButUndecodable_returnsNilNotCrash() {
        // Write one shape, read as an incompatible shape → decode throws → the catch
        // path logs (side-effect) and returns nil. This is the data-loss signal path.
        let s = store()
        XCTAssertTrue(s.save(["a", "b"], name: "mismatch"))     // a JSON array of strings
        XCTAssertNil(s.load(Int.self, name: "mismatch"))        // decoded as Int → fails → nil
        // The file is still there and still round-trips at its real type (we didn't nuke it).
        XCTAssertEqual(s.load([String].self, name: "mismatch"), ["a", "b"])
        s.delete(name: "mismatch")
    }

    func testDelete_removesFile() {
        let s = store()
        XCTAssertTrue(s.save(42, name: "answer"))
        XCTAssertEqual(s.load(Int.self, name: "answer"), 42)
        s.delete(name: "answer")
        XCTAssertNil(s.load(Int.self, name: "answer"))
    }
}
