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

    // Cold + probe FAILED → -3000 = invalidComponentID is a registry FIND miss (the
    // component did not RESOLVE in this process), NOT proof the appex is launch-denied
    // (grill 2026-07-20 refuted that). With 0 third-party from every vendor the
    // decisive action is priming another host (AUM/GarageBand) then rescanning —
    // reinstall is only the fallback if AUM ALSO can't open our plugin. The OSStatus
    // code stays surfaced for triage.
    func testGuidance_coldProbeFailed_saysPrimeThenRescan_reinstallOnlyAsFallback() {
        let d = AUv3ScanDiagnostic(rawComponentCount: 28, thirdPartyCount: 0,
                                   ownAUv3Present: false, scanAttempt: 4,
                                   selfProbe: .failed(domain: "NSOSStatusErrorDomain", code: -3000))
        let g = d.guidance
        let lower = g.lowercased()
        XCTAssertTrue(lower.contains("aum") || lower.contains("garageband"),
                      "primary action is priming another AU host")
        XCTAssertTrue(lower.contains("rescan"), "then rescan in Echoel")
        // Reinstall must be framed as the FALLBACK ('only if'), not the first move.
        if let reinstallRange = lower.range(of: "reinstall") {
            let before = lower[lower.startIndex..<reinstallRange.lowerBound]
            XCTAssertTrue(before.contains("only if"),
                          "reinstall is the fallback, not the primary instruction")
        }
        XCTAssertTrue(g.contains("-3000"), "surface the OSStatus code for device triage")
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
        XCTAssertTrue(lower.contains("provisioning") || lower.contains("app store connect"),
                      "routes to the portal/provisioning cause")
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
