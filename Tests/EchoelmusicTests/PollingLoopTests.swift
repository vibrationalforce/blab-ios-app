import XCTest
@testable import Echoelmusic

@MainActor
final class PollingLoopTests: XCTestCase {

    func testStart_invokesBodyRepeatedly() async {
        let loop = PollingLoop()
        var count = 0
        loop.start(interval: .milliseconds(20)) { count += 1 }
        try? await Task.sleep(for: .milliseconds(120))
        loop.stop()
        XCTAssertGreaterThanOrEqual(count, 2, "body should run several times over 120ms at 20ms interval")
    }

    func testStop_haltsInvocation() async {
        let loop = PollingLoop()
        var count = 0
        loop.start(interval: .milliseconds(20)) { count += 1 }
        try? await Task.sleep(for: .milliseconds(60))
        loop.stop()
        let snapshot = count
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(count, snapshot, "no further invocations after stop()")
    }

    func testStart_isIdempotent() async {
        let loop = PollingLoop()
        var count = 0
        loop.start(interval: .milliseconds(20)) { count += 1 }
        loop.start(interval: .milliseconds(20)) { count += 1000 } // must be ignored
        try? await Task.sleep(for: .milliseconds(80))
        loop.stop()
        XCTAssertLessThan(count, 1000, "second start() must not replace the running body")
    }

    func testIsRunning_reflectsLifecycle() {
        let loop = PollingLoop()
        XCTAssertFalse(loop.isRunning)
        loop.start(interval: .seconds(1)) { }
        XCTAssertTrue(loop.isRunning)
        loop.stop()
        XCTAssertFalse(loop.isRunning)
    }
}
