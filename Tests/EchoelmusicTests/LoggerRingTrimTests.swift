// LoggerRingTrimTests.swift
// Echoel — the trim rule behind the in-memory log ring.
//
// THE DEFECT (#216, resource half). `ProfessionalLogger` kept 10 000 `LogEntry` values —
// each a UUID + Date + two enums + three Strings + a Dictionary — in an array with TWO
// readers, `getRecentEntries` and `exportLogs(since:)`, NEITHER of which has a caller
// anywhere in the repo (the diagnostics sheet reads `EchoelCrashLog`). Write-only, for the
// life of the process.
//
// The sharper half was not the memory. The trim was `removeFirst(count - max)`, and
// `Array.removeFirst` is O(n): once the buffer was full, EVERY log call shifted ~10 000
// elements down to make room for one. Cost that grows with how long the app has been
// running, on a path that is supposed to be free.
//
// WHAT IS PINNED HERE, narrowly: the pure `trimCount` rule. The actual trim runs inside
// the logger's `queue.async` against a global singleton, which no unit test can observe
// deterministically — so nothing below proves the call site uses this function, and a
// revert of that one line would leave these green. Nor do they pin the CAP: every test
// passes `cap` explicitly, so restoring `maxEntries = 10_000` also leaves them green.
// What they do catch is the mistake the rule exists to prevent: trimming exactly to the
// cap, which puts the O(n) shift back on every append.

import XCTest
@testable import Echoelmusic

final class LoggerRingTrimTests: XCTestCase {

    /// Below and at the cap, nothing is dropped — the buffer is allowed to fill.
    func testNothingIsTrimmedUntilTheCapIsExceeded() {
        XCTAssertEqual(EchoelLogger.trimCount(currentCount: 0, cap: 400), 0)
        XCTAssertEqual(EchoelLogger.trimCount(currentCount: 399, cap: 400), 0)
        XCTAssertEqual(EchoelLogger.trimCount(currentCount: 400, cap: 400), 0,
                       "exactly at the cap is not over it")
    }

    /// THE REGRESSION TEST. One entry over the cap must trim down to the LOW-WATER mark,
    /// not back to the cap. Trimming to the cap is the old behaviour in disguise: the next
    /// append is over again, so the O(n) shift runs on every single log call forever.
    func testOverflowTrimsToALowWaterMark_notBackToTheCap() {
        let cap = 400
        let drop = EchoelLogger.trimCount(currentCount: cap + 1, cap: cap)
        let remaining = (cap + 1) - drop
        XCTAssertEqual(remaining, 300, "¾ of the cap")
        XCTAssertLessThan(remaining, cap,
                          "if this equals the cap, every following append pays the memmove "
                          + "again — which is the defect, not the fix")
    }

    /// And the amortisation is the actual benefit, so state it as a number: after one trim
    /// there must be room for many cheap appends before the next one.
    func testATrimBuysManyCheapAppendsBeforeTheNext() {
        let cap = 400
        var count = cap + 1
        count -= EchoelLogger.trimCount(currentCount: count, cap: cap)
        var cheapAppends = 0
        // Append FIRST, then test the post-append count. The first version tested the
        // pre-append count and so counted the append that TRIGGERS the next trim as a
        // cheap one — it computed 101 and asserted 100, i.e. it failed. Nothing told me:
        // this suite is non-blocking (#208), so a red test here reddens no gate. Review
        // caught it by tracing the loop by hand.
        while true {
            count += 1
            if EchoelLogger.trimCount(currentCount: count, cap: cap) > 0 { break }
            cheapAppends += 1
        }
        XCTAssertEqual(cheapAppends, 100, "cap/4 appends between shifts, not one")
    }

    /// Degenerate caps must not produce a negative or over-large drop — `removeFirst(n)`
    /// traps on both.
    func testDegenerateCapsCannotProduceAnInvalidDrop() {
        XCTAssertEqual(EchoelLogger.trimCount(currentCount: 5, cap: 0), 0,
                       "a zero cap disables trimming rather than emptying the buffer")
        XCTAssertEqual(EchoelLogger.trimCount(currentCount: 5, cap: -3), 0)
        // cap 1 → lowWater clamps to 1, so a 2-entry buffer drops exactly one.
        XCTAssertEqual(EchoelLogger.trimCount(currentCount: 2, cap: 1), 1)
        for count in 0...50 {
            for cap in 1...8 {
                let drop = EchoelLogger.trimCount(currentCount: count, cap: cap)
                XCTAssertGreaterThanOrEqual(drop, 0, "count \(count) cap \(cap)")
                XCTAssertLessThanOrEqual(drop, count,
                                         "dropping more than the buffer holds traps "
                                         + "in removeFirst — count \(count) cap \(cap)")
            }
        }
    }
}
