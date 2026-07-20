// AUv3ScanDiagnosticTests.swift
// Pins the founder-visible AUv3 discovery diagnostic — the on-screen twin of the
// device-log breadcrumb. The whole point is that the NEXT TestFlight build lets
// the founder read WHICH of the two cold-registry causes they hit without pasting
// a log: (a) the process's component LIST is stale though iOS serves the appex
// (self-probe INSTANTIATE OK → "fully quit + reopen"), vs. (b) the appex is
// genuinely unregistered on the device (self-probe FAILED → reinstall/restart).
// guidance is pure + deterministic, so it is fully CI-verifiable off-device.

import XCTest
@testable import Echoelmusic

final class AUv3ScanDiagnosticTests: XCTestCase {

    // Third-party units present ⇒ discovery works, not cold — regardless of probe.
    func testNotCold_whenThirdPartyPresent() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 40, thirdPartyCount: 3,
                                   ownAUv3Present: false, scanAttempt: 1, selfProbe: nil)
        XCTAssertFalse(d.isCold)
    }

    // Our OWN appex visible ⇒ the registry serves out-of-process units to us ⇒ not cold.
    func testNotCold_whenOwnAUv3Present() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 30, thirdPartyCount: 0,
                                   ownAUv3Present: true, scanAttempt: 4, selfProbe: nil)
        XCTAssertFalse(d.isCold)
    }

    func testCold_whenNoThirdPartyAndNoOwn() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4, selfProbe: nil)
        XCTAssertTrue(d.isCold)
    }

    // Cold, probe not yet run → guidance says the self-test is still running,
    // and does NOT yet prescribe reinstall vs. restart (we don't know which).
    func testGuidance_coldProbePending_saysProbeRunning() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4, selfProbe: nil)
        let g = d.guidance.lowercased()
        XCTAssertTrue(g.contains("self-test") || g.contains("checking"))
        XCTAssertTrue(g.contains("0 third-party"))
    }

    // Cold + INSTANTIATE OK → the registry DOES serve the appex; the component
    // list is stale for this process → the fix is a full quit+reopen, NOT reinstall.
    func testGuidance_coldInstantiateOK_saysReopenNotReinstall() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .instantiateOK)
        let g = d.guidance.lowercased()
        XCTAssertTrue(g.contains("reopen") || g.contains("quit"))
        XCTAssertTrue(g.contains("stale") || g.contains("list"))
        XCTAssertFalse(g.contains("reinstall"), "INSTANTIATE OK ⇒ registration is fine, do not tell the user to reinstall")
    }

    // Cold + probe FAILED → the appex is not registered on THIS device → reinstall /
    // restart the device; the OSStatus code is surfaced for triage.
    func testGuidance_coldProbeFailed_saysReinstallAndShowsCode() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000))
        let g = d.guidance
        XCTAssertTrue(g.lowercased().contains("reinstall") || g.lowercased().contains("not registered"))
        XCTAssertTrue(g.contains("-3000"), "surface the OSStatus code for device triage")
    }

    // A non-cold diagnostic yields no cold guidance to show (the browser only shows
    // guidance while cold), so guidance is empty when discovery is healthy.
    func testGuidance_notCold_isEmpty() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 40, thirdPartyCount: 5,
                                   ownAUv3Present: true, scanAttempt: 1, selfProbe: nil)
        XCTAssertTrue(d.guidance.isEmpty)
    }

    // MARK: - Copyable report (one-tap founder→developer hand-off)

    // The report is the deciding fact in one pastable line: how many units iOS
    // returned, how many third-party, whether our own appex showed, the probe
    // verdict, AND the manufacturer NAMES iOS handed this process. If that maker
    // list is Apple-only while AUM shows dozens, iOS is serving an Apple-only
    // registry to this app; if it names real makers absent from the list, our
    // filter dropped them. Pure/deterministic ⇒ CI-verifiable off-device.
    func testReport_namesTheMakersAndCounts() {
        let d = AUv3ScanDiagnostic(
            rawComponentCount: 42, thirdPartyCount: 0, ownAUv3Present: false,
            scanAttempt: 4, selfProbe: .instantiateOK,
            rawMakers: ["Apple", "Moog Music Inc.", "Imaginando"])
        let r = d.report
        XCTAssertTrue(r.contains("42"), "carries the raw component count")
        XCTAssertTrue(r.contains("0 third-party"), "carries the third-party count")
        XCTAssertTrue(r.contains("not visible"), "states own AUv3 visibility")
        XCTAssertTrue(r.contains("Moog Music Inc."), "names the makers iOS returned")
        XCTAssertTrue(r.contains("Imaginando"))
        XCTAssertTrue(r.lowercased().contains("instantiate-ok") || r.lowercased().contains("list stale"),
                      "carries the self-probe verdict")
    }

    // Empty maker list must read as an explicit "none", not a dangling "[]" the
    // founder can't interpret.
    func testReport_emptyMakers_readsAsNone() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 0, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 0)
        XCTAssertTrue(d.report.contains("[none]"), "empty maker set reads as a legible none")
    }

    // MARK: - Load-failure message (founder-visible "won't open" triage)

    // When a plugin is DISCOVERED but fails at LOAD/open time (founder 2026-07-19:
    // "wird in AUM erkannt aber lässt sich nicht öffnen"), localizedDescription
    // hides the OSStatus behind a vague string. The load-failure message must
    // surface the raw domain#code so a device screenshot pins the cause.
    func testLoadFailureMessage_carriesTheRawOSStatusCode() {
        let msg = AUv3ScanDiagnostic.loadFailureMessage(
            name: "Zeeon", domain: "NSOSStatusErrorDomain", code: -3000,
            localized: "The operation couldn’t be completed.")
        XCTAssertTrue(msg.contains("Zeeon"), "names the plugin that failed")
        XCTAssertTrue(msg.contains("-3000"), "surfaces the OSStatus code that localizedDescription hides")
        XCTAssertTrue(msg.contains("NSOSStatusErrorDomain"), "surfaces the error domain")
    }

    // The human-readable localizedDescription is kept alongside the code — the code
    // is for triage, the prose is for the founder.
    func testLoadFailureMessage_keepsTheHumanReadableReason() {
        let msg = AUv3ScanDiagnostic.loadFailureMessage(
            name: "BigReverb", domain: "com.acme.fx", code: -1,
            localized: "Unsupported channel layout.")
        XCTAssertTrue(msg.contains("Unsupported channel layout."))
        XCTAssertTrue(msg.contains("BigReverb"))
    }
}
