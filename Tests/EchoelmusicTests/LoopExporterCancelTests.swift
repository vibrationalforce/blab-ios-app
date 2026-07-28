// LoopExporterCancelTests.swift
// Echoel — the abort contract. Founder 2026-07-28: "Es ist schon wichtig das man die
// Aufnahme dann auch abbrechen kann, wenn man sich verspielt hat."
//
// Driving a real capture needs an AudioEngine + BeatPlayer, so what is pinned here is the
// part that is pure STATE and that a future edit could quietly break: WHEN the abort is
// offered. Both directions matter equally —
//   · offering it when nothing can be stopped is a lying control (the tap does nothing);
//   · withholding it while a take runs is the defect this change exists to fix.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class LoopExporterCancelTests: XCTestCase {

    func testAFreshExporter_offersNoAbort() {
        let exporter = LoopExporter()
        XCTAssertEqual(exporter.status, .idle)
        XCTAssertFalse(exporter.isCancellable, "there is nothing to abort before a take starts")
    }

    func testCancelOnIdle_isASilentNoOp_notAStateChange() {
        // The button is disabled here, but a stray call (double tap, a future caller that
        // forgets to check) must not push the exporter into some half-state.
        let exporter = LoopExporter()
        exporter.cancel()
        XCTAssertEqual(exporter.status, .idle)
        XCTAssertFalse(exporter.isCancellable)
    }

    func testResetFromIdle_staysIdle_andStillOffersNoAbort() {
        let exporter = LoopExporter()
        exporter.reset()
        XCTAssertEqual(exporter.status, .idle)
        XCTAssertFalse(exporter.isCancellable)
    }

    // NOT TESTED HERE, stated so the gap is known rather than assumed covered: that a
    // running capture actually stops, that the temp file is deleted, and that the
    // transport is left stopped. All three need a live AudioEngine + BeatPlayer, which
    // this suite cannot stand up. They are device-verify items — see the commit body.
}
#endif
