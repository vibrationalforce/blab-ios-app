// AUv3ScanDiagnosticTests.swift
// Pins the founder-visible AUv3 discovery diagnostic — the on-screen twin of the
// device-log breadcrumb, readable off a device paste without a log. The self-probe
// discriminates: (a) the process's component LIST is stale though iOS serves the
// appex (INSTANTIATE OK → "fully quit + reopen"), vs. (b) the own component did NOT
// RESOLVE in this process (FAILED, -3000 = invalidComponentID = a registry find
// miss BEFORE any launch — NOT the refuted "appex launch-denied" reading; grill
// 2026-07-20). With 0 third-party from every vendor, (b)'s decisive action is
// priming another host then rescanning, reinstall only as fallback. The report also
// carries the build stamp so a paste is pinnable to a build. guidance/report are
// pure + deterministic, so they are fully CI-verifiable off-device.

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

    // PROFESSIONAL STANCE (founder 2026-07-21: "No AUM/rescan guidance … stay
    // professional"): cold guidance states an HONEST cause but must NEVER tell the
    // user to open a competitor host, tap Rescan, reinstall, or restart the phone.
    // Cold + INSTANTIATE OK → registry serves the appex, the list is refreshing.
    func testGuidance_coldInstantiateOK_isCalmNoWorkaround() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .instantiateOK)
        let g = d.guidance.lowercased()
        XCTAssertTrue(g.contains("refresh") || g.contains("list"))
        for banned in ["aum", "garageband", "rescan", "reinstall", "restart", "swipe"] {
            XCTAssertFalse(g.contains(banned), "no workaround instruction: '\(banned)'")
        }
    }

    // Cold + probe FAILED (unstamped bundle) → honest cause + OSStatus for triage,
    // NO user workaround steps.
    func testGuidance_coldProbeFailed_isHonestCauseNoWorkaround() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000))
        let g = d.guidance
        let lower = g.lowercased()
        XCTAssertTrue(g.contains("-3000"), "surface the OSStatus code for device triage")
        for banned in ["aum", "garageband", "rescan", "reinstall", "restart", "swipe"] {
            XCTAssertFalse(lower.contains(banned), "no workaround instruction: '\(banned)'")
        }
    }

    // Bundle-probe DISCRIMINATOR (founder 2026-07-21, reboot refuted): when the
    // -3000 probe fails AND the embedded-appex fact shows our .appex IS present +
    // declares echl, the app is built right and the fault is iOS-side registration
    // (portal/provisioning) — the guidance must say so, and must NOT tell the founder
    // to reboot/reinstall (they already rebooted many times).
    func testGuidance_probeFailed_appexEmbedded_pointsAtPortalNotReboot() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 101, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000),
                                   bundledAUv3: "EchoelmusicAUv3=Echo/augn/echl")
        let g = d.guidance
        let lower = g.lowercased()
        XCTAssertTrue(lower.contains("embedded"), "states the appex IS embedded")
        XCTAssertTrue(lower.contains("inter-app audio") && lower.contains("app id"),
                      "routes to the documented Inter-App Audio App-ID gate (the portal lever)")
        XCTAssertFalse(lower.contains("open aum"),
                       "priming AUM is not the action when the bundle is proven correct")
    }

    // The mirror case: probe failed AND the .appex is genuinely absent from the
    // installed bundle → a build/embed miss, not a portal issue.
    func testGuidance_probeFailed_appexAbsent_pointsAtBuild() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 101, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000),
                                   bundledAUv3: "no .appex embedded")
        let lower = d.guidance.lowercased()
        XCTAssertTrue(lower.contains("not embedded"), "states the appex is missing from the bundle")
        XCTAssertTrue(lower.contains("build") || lower.contains("plugins"),
                      "routes to the build/embed step")
    }

    // The embedded-appex fact rides in the pastable report when stamped, so a device
    // paste alone splits build-miss from registration-miss. Absent (default "") ⇒ no
    // stray "Embedded:" clause.
    func testReport_carriesEmbeddedAppexWhenStamped() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 101, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000),
                                   rawMakers: ["Apple"], buildVersion: "v10.79.330 (2440)",
                                   bundledAUv3: "EchoelmusicAUv3=Echo/augn/echl")
        XCTAssertTrue(d.report.contains("Embedded: EchoelmusicAUv3=Echo/augn/echl"),
                      "the embedded-appex fact rides in the report")
        let plain = AUv3ScanDiagnostic(rawComponentCount: 10, thirdPartyCount: 0,
                                       ownAUv3Present: false, scanAttempt: 1)
        XCTAssertFalse(plain.report.contains("Embedded:"),
                       "no embedded clause when the field is unstamped")
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

    // The build stamp, when present, rides in the report so a pasted device line is
    // pinnable to a build (grill 2026-07-20: "try N maps to no build number"). Absent
    // (default "") ⇒ no stray prefix, so older/test paths still read cleanly.
    func testReport_carriesBuildStampWhenPresent() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 42, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000),
                                   rawMakers: ["Apple"], buildVersion: "v10.79.312 (2421)")
        let r = d.report
        XCTAssertTrue(r.contains("v10.79.312 (2421)"), "the build stamp pins the scan to a build")
        // The refuted 'appex unregistered' phrasing must be gone; the honest label stays.
        XCTAssertFalse(r.lowercased().contains("appex unregistered"),
                       "the refuted launch-denial reading must not reappear")
        XCTAssertTrue(r.lowercased().contains("unresolved") || r.contains("-3000"),
                      "surfaces the resolve-miss honestly with its code")
    }

    func testReport_noBuildStamp_hasNoStrayPrefix() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 10, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 1)
        XCTAssertTrue(d.report.contains("scan[try 1]: iOS returned"),
                      "with no build stamp the line flows straight from try-count to counts")
    }

    // MARK: - Load-failure message (founder-visible "won't open" triage)

    // PROFESSIONAL STANCE (founder 2026-07-21: "stay professional"): a plugin that
    // fails at LOAD/open time shows a CALM human reason — the raw OSStatus domain#code
    // is NOT dumped on screen (it lives in the load-path breadcrumb + os_log the
    // device log carries). The visible message must name the plugin + reason, no jargon.
    func testLoadFailureMessage_isCalmNoRawOSStatusJargon() {
        let msg = AUv3ScanDiagnostic.loadFailureMessage(
            name: "Zeeon", localized: "The operation couldn’t be completed.")
        XCTAssertTrue(msg.contains("Zeeon"), "names the plugin that failed")
        XCTAssertTrue(msg.contains("The operation couldn’t be completed."), "keeps the human reason")
        XCTAssertFalse(msg.contains("-3000"), "no raw OSStatus code on screen")
        XCTAssertFalse(msg.lowercased().contains("nsosstatuserrordomain"), "no error-domain jargon on screen")
        XCTAssertFalse(msg.contains("["), "no bracketed technical suffix")
    }

    // The human-readable localizedDescription is the whole visible message.
    func testLoadFailureMessage_keepsTheHumanReadableReason() {
        let msg = AUv3ScanDiagnostic.loadFailureMessage(
            name: "BigReverb", localized: "Unsupported channel layout.")
        XCTAssertTrue(msg.contains("Unsupported channel layout."))
        XCTAssertTrue(msg.contains("BigReverb"))
    }
}
