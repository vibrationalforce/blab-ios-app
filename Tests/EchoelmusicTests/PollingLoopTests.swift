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

    // MARK: - PollingRateCeiling (the bio-poll ceiling, #197c)

    /// The whole point of the type: it may SLOW a loop, never speed one up. The
    /// `high` tier publishes 15 Hz while every governed loop is nominally 10 Hz, so a
    /// "target" reading would make a charging phone poll faster to save battery.
    /// Compared in seconds, not by `Duration` equality: `Duration.seconds(1.0 / hz)`
    /// goes through a binary Double, so demanding attosecond-exact equality with a
    /// `.milliseconds` literal would pin a rounding detail of the toolchain, not the
    /// policy this test is about.
    private func assertSeconds(_ d: Duration, _ expected: Double,
                               _ message: String, line: UInt = #line) {
        let seconds = Double(d.components.seconds)
                    + Double(d.components.attoseconds) * 1e-18
        XCTAssertEqual(seconds, expected, accuracy: 1e-6, message, line: line)
    }

    func testCeiling_neverShortensTheNominalInterval() {
        let nominal = Duration.milliseconds(100)
        assertSeconds(PollingRateCeiling.interval(nominal: nominal, ceilingHz: 15), 0.1,
                      "a ceiling ABOVE the nominal rate must leave the loop untouched")
        assertSeconds(PollingRateCeiling.interval(nominal: nominal, ceilingHz: 10), 0.1,
                      "a ceiling AT the nominal rate must leave the loop untouched")
    }

    func testCeiling_lengthensWhenBelowNominal() {
        // The minimal tier's 5 Hz against the 10 Hz control-plane loops.
        assertSeconds(PollingRateCeiling.interval(nominal: .milliseconds(100), ceilingHz: 5),
                      0.2, "5 Hz must stretch a 10 Hz loop to 200 ms")
    }

    /// A ceiling of 0 is the launch default and must mean "uncapped", not "never run".
    /// Negative and non-finite values arrive from arithmetic on an unknown battery
    /// level and must degrade to the same harmless answer rather than to a divide.
    func testCeiling_nonPositiveOrNonFiniteMeansUncapped() {
        let nominal = Duration.milliseconds(100)
        for hz: Double in [0, -1, .nan, .infinity, -.infinity] {
            XCTAssertEqual(PollingRateCeiling.interval(nominal: nominal, ceilingHz: hz), nominal,
                           "ceilingHz \(hz) must be treated as uncapped")
        }
    }

    /// A denormal-small ceiling would ask for an interval `Duration.seconds(_:)` cannot
    /// represent. It must clamp, not trap — this is a public pure function.
    func testCeiling_absurdlySmallRateClampsInsteadOfOverflowing() {
        assertSeconds(PollingRateCeiling.interval(nominal: .milliseconds(100),
                                                  ceilingHz: 1e-300),
                      5, "an unrepresentable ceiling must clamp to slowestInterval")
    }

    func testSetBioHz_normalisesJunkToUncapped() {
        PollingRateCeiling.setBioHz(5)
        XCTAssertEqual(PollingRateCeiling.bioHz, 5, accuracy: 0.0001)
        PollingRateCeiling.setBioHz(.nan)
        XCTAssertEqual(PollingRateCeiling.bioHz, 0, "NaN must fall back to uncapped")
        PollingRateCeiling.setBioHz(-3)
        XCTAssertEqual(PollingRateCeiling.bioHz, 0, "a negative rate must fall back to uncapped")
        PollingRateCeiling.setBioHz(0)   // leave the shared holder as found
    }

    /// The behaviour the fix exists for: the ceiling reaches a loop that is ALREADY
    /// running. Baking the interval at `start()` is why `bioHz` had no consumer.
    func testGovernedLoop_slowsWhileRunning() async {
        let loop = PollingLoop()
        var count = 0
        PollingRateCeiling.setBioHz(0)
        loop.start(interval: .milliseconds(20), governedByBioCeiling: true) { count += 1 }
        try? await Task.sleep(for: .milliseconds(100))
        let fastRuns = count
        PollingRateCeiling.setBioHz(5)            // 200 ms — far longer than the window
        try? await Task.sleep(for: .milliseconds(100))
        let slowRuns = count - fastRuns
        loop.stop()
        PollingRateCeiling.setBioHz(0)
        XCTAssertGreaterThan(fastRuns, slowRuns,
                             "a ceiling published mid-run must throttle the live loop")
        XCTAssertLessThanOrEqual(slowRuns, 2, "at 5 Hz at most ~1 tick fits in 100 ms")
    }

    /// The default must stay bit-identical for every un-opted-in call site.
    func testUngovernedLoop_ignoresTheCeiling() async {
        let loop = PollingLoop()
        var count = 0
        PollingRateCeiling.setBioHz(1)            // would mean one tick per second
        loop.start(interval: .milliseconds(20)) { count += 1 }
        try? await Task.sleep(for: .milliseconds(120))
        loop.stop()
        PollingRateCeiling.setBioHz(0)
        XCTAssertGreaterThanOrEqual(count, 2, "an un-opted-in loop must keep its own rate")
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
