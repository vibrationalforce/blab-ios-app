// TheMeasuredLatencyReachesTheScreenTests.swift
// Echoel — the monitor latency the founder was promised is a NUMBER ON SCREEN, not only a
// line in an exported log. #663.
//
// WHY THIS EXISTS. The founder asked (2026-08-20) for "alle Latenzen und Kombinationen
// optimiert für Sessions". #653–#657 made that measurable and wrote it to `echoel_diag.log`,
// which answers only AFTER an export — the wrong moment, because the decision he is making
// ("cable or Bluetooth?") happens while the picker is open. This slice puts the same numbers
// in the picker, and the point of the guard is that they are the SAME numbers: one gathering
// (`currentSessionLatency`) and one sum (`latencyFloorSeconds`), so the screen and the file
// cannot drift (#416). Four spellings of that sum is what this file's predecessor found.
//
// ⚠️ HONEST LIMITS. 6 tests, 25 `XCTAssert*` (re-derive, do not re-type:
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// ). Tests 1–3 are END-TO-END BEHAVIOUR on shipped value types — the sum and both rendered
// strings are driven with real inputs, including the non-finite ones a session answers with
// mid-teardown. Tests 4–6 are SOURCE-TEXT SCANS, because the graph and the view sit on a
// `@MainActor` no test host here can run honestly.
// What NO test here can prove: that the number is CORRECT on hardware. `AVAudioSession`
// reports the values; this pins that we add them once, drop what we cannot measure, and say
// when the result is partial. Whether iOS's answer matches the ear is a device probe.

import XCTest
@testable import Echoelmusic

final class TheMeasuredLatencyReachesTheScreenTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"

    // MARK: - 1. The floor is a sum, and it drops what it cannot measure

    func testTheFloorAddsTheThreePartsAndSkipsTheUnmeasurable() {
        // 1.5 ms in + 5 ms buffer + 2.5 ms out = 9 ms.
        let full = AudioConfiguration.latencyFloorSeconds(ioBufferSeconds: 0.005,
                                                          inputSeconds: 0.0015,
                                                          outputSeconds: 0.0025,
                                                          inputAvailable: true)
        XCTAssertEqual(full, 0.009, accuracy: 1e-9, """
            The floor is no longer in + ONE buffer period + out. That sum is the only reason \
            the log line and the picker can print the same number (#663).
            """)

        // No input ROUTE. The input term must not be counted — and #654 exists because this
        // file once reported that case as a measured zero.
        let noInput = AudioConfiguration.latencyFloorSeconds(ioBufferSeconds: 0.005,
                                                             inputSeconds: 0.0015,
                                                             outputSeconds: 0.0025,
                                                             inputAvailable: false)
        XCTAssertEqual(noInput, 0.0075, accuracy: 1e-9,
                       "an absent input route still contributed its latency to the floor.")

        // A session queried mid-teardown answers with anything. A route rebuild is exactly
        // when this fires, so NaN and negative are edge cases here, not impossibilities.
        let broken = AudioConfiguration.latencyFloorSeconds(ioBufferSeconds: .nan,
                                                            inputSeconds: -1,
                                                            outputSeconds: 0.0025,
                                                            inputAvailable: true)
        XCTAssertEqual(broken, 0.0025, accuracy: 1e-9, """
            A non-finite or negative part reached the sum. `floor=nanms` on screen reads as a \
            broken app; the contract is to DROP the part and report `complete == false`.
            """)
        XCTAssertTrue(broken.isFinite, "the floor became non-finite, which no format can render.")
    }

    // MARK: - 2. A partial sum says it is partial

    func testAPartialFloorIsMarkedAndACompleteOneIsNot() {
        let complete = AudioConfiguration.LatencyReadout(
            floorMilliseconds: 9, bufferMilliseconds: 5, inputMilliseconds: 1.5,
            outputMilliseconds: 2.5, route: "Built-In Microphone→Speaker", complete: true,
            codec: .wideband)
        XCTAssertEqual(complete.floorText, "9.0 ms",
                       "a complete measurement gained a qualifier it has not earned.")

        let partial = AudioConfiguration.LatencyReadout(
            floorMilliseconds: 7.5, bufferMilliseconds: 5, inputMilliseconds: nil,
            outputMilliseconds: 2.5, route: "none→Speaker", complete: false,
            codec: .wideband)
        XCTAssertEqual(partial.floorText, "7.5+ ms", """
            A PARTIAL floor printed as if it were the whole measurement. The `+` is the entire \
            honesty of this readout: the sum silently dropped a part it could not measure, and \
            a bare "7.5 ms" claims a lower latency than the hardware can deliver (#654).
            """)
    }

    // MARK: - 3. The breakdown distinguishes "no answer" from "zero"

    func testTheBreakdownPrintsADashForWhatCouldNotBeMeasured() {
        let r = AudioConfiguration.LatencyReadout(
            floorMilliseconds: 7.5, bufferMilliseconds: 5, inputMilliseconds: nil,
            outputMilliseconds: 2.5, route: "none→Speaker", complete: false,
            codec: .wideband)
        XCTAssertEqual(r.breakdownText, "in — · buffer 5.0 · out 2.5 ms · none→Speaker", """
            An unanswerable part stopped rendering as `—`. If it renders as `0.0` the reader \
            is told the hardware costs nothing, which is the exact defect #654 removed from \
            the log line — repeated on the surface a human actually looks at.
            """)

        let full = AudioConfiguration.LatencyReadout(
            floorMilliseconds: 9, bufferMilliseconds: 5, inputMilliseconds: 1.5,
            outputMilliseconds: 2.5, route: "Mic→HI-X25BT", complete: true,
            codec: .wideband)
        XCTAssertEqual(full.breakdownText, "in 1.5 · buffer 5.0 · out 2.5 ms · Mic→HI-X25BT",
                       "the breakdown stopped naming the route that produced the number.")
    }

    // MARK: - 4. ONE sum, ONE gathering

    func testTheScreenAndTheLogReadTheSameSumAndTheSameGathering() throws {
        let code = try Self.codeText(Self.config)

        XCTAssertEqual(Self.occurrences(of: "static func latencyFloorSeconds", in: code), 1, """
            `latencyFloorSeconds` is declared \(Self.occurrences(of: "static func latencyFloorSeconds", in: code)) \
            times. It exists because the same sum had four spellings in this file and only one \
            of them filtered non-finite values (#416/#663).
            """)
        XCTAssertTrue(code.contains("let floorSeconds = latencyFloorSeconds("), """
            `latencyLine` stopped calling the shared sum and computes its own again. The log \
            and the picker would then be free to print different numbers for one route — which \
            is worse than either being wrong, because neither can be checked against the other.
            """)

        XCTAssertEqual(Self.occurrences(of: "private static func currentSessionLatency", in: code), 1,
                       "the single gathering of the platform's latency facts is gone or duplicated.")
        XCTAssertTrue(code.contains("static func latencySnapshot"), "the on-screen readout is gone.")
        // #663 folded `measureLatency()` in: it added the three terms raw, so a session
        // queried mid-teardown made `latencyStats()` print `nan`. Pinned because "one sum"
        // is only true while this call site exists.
        // ⛔ #665: this comment said "#663 folded the LAST unfiltered spelling" and the
        // message below said "the FOURTH spelling". Both were wrong, and #664 measured it:
        // there were THREE spellings, #663 folded TWO, and the third — `Total Latency:` in
        // `configureAudioSession` — it never touched. #664 folded that one. So "last" became
        // true only at #664, and "fourth" was never true.
        // ⭐ The reason this needed its own slice is the point: #664 corrected the count where
        // the REASONING lives (`AudioConfiguration.swift`) and left both copies standing here,
        // in the message that FIRES. That is exactly what #662 was about, one commit later.
        XCTAssertTrue(code.contains("return latencyFloorSeconds(ioBufferSeconds: audioSession"), """
            `measureLatency()` went back to adding the three latency terms itself. It was one \
            of three spellings of one decision and the only one with no non-finite filter; \
            the shared sum is what keeps the log and the picker from printing different \
            numbers for one route.
            """)
        // Both consumers must go through the gathering. If either stops, the drift this whole
        // file guards against is back and nothing else would notice.
        // ⛔ #663: the first draft of this assertion counted `currentSessionLatency()` and
        // expected 2. It is 3 — the DECLARATION line contains the same substring, so the
        // guard would have been red on a correct tree the day it was written. Driven in
        // Python against the worktree before committing, which is the only reason it was not.
        // Anchored on the CALL form instead, which the declaration cannot match.
        XCTAssertEqual(Self.occurrences(of: "= currentSessionLatency()", in: code), 2, """
            Expected exactly two callers of `currentSessionLatency()` — `latencySnapshot` (the \
            screen) and `latencyBreadcrumb` (the log). Found \
            \(Self.occurrences(of: "= currentSessionLatency()", in: code)). A third consumer is \
            fine, but it has to be added here deliberately; a consumer that VANISHED means one \
            surface started gathering for itself, and the screen and the log can then disagree \
            about one route without anything noticing.
            """)
    }

    // MARK: - 5. The freeze law: the read lives in a leaf

    func testTheReadoutIsReadInItsOwnLeafAndNotInThePickerBody() throws {
        let code = try Self.codeText(Self.picker)

        XCTAssertTrue(code.contains("private struct MonitorLatencyRow: View"), """
            `MonitorLatencyRow` is gone. It is a separate `View` for the 10.76.41/50 reason, \
            not for tidiness: `AudioInputPickerView` hosts Pickers, and a value read in THAT \
            body registers the whole body as an observer — every change tears down an open \
            `.menu` popover. Folding the row back into the parent body is the freeze bug.
            """)
        XCTAssertTrue(code.contains("MonitorLatencyRow()"), "the row is declared but never mounted.")
        // #664 (review): the copy was unguarded, while the commit body claimed "the screen
        // says that sentence out loud". `floor` is not `total` — hardware in + out + ONE
        // buffer period is a LOWER BOUND on what the ear hears, and a reader who takes the
        // number for the round trip will conclude the app is faster than it is. That is the
        // same over-claim #654 removed from the log line; here it is on the surface a human
        // actually looks at, so it is pinned rather than trusted.
        XCTAssertTrue(code.contains("Lower bound — hardware plus one buffer"), """
            The readout stopped saying that the number is a LOWER BOUND. Without it "9.0 ms" \
            reads as the round trip, which is the stronger claim the measurement cannot make.
            """)
        XCTAssertTrue(code.contains("\"Monitor latency\""),
                      "the readout lost its label, so the number on screen names nothing.")

        // The reads must sit AFTER the leaf's declaration — i.e. inside it, not in the parent.
        let leaf = try XCTUnwrap(code.range(of: "private struct MonitorLatencyRow: View"),
                                 "cannot anchor the leaf; re-anchor before trusting claim 5.")
        let above = String(code[code.startIndex..<leaf.lowerBound])
        // ⛔ #664 (review): without this sentinel the claim is position-dependent. The leaf is
        // last in the file today, so `above` is the whole parent. A normal leaf-first refactor
        // that moves the struct up would make `above` EMPTY — the `== 0` below would then pass
        // on nothing while a genuine ancestor read, now BELOW the anchor, went unseen (#454).
        XCTAssertTrue(above.contains("struct AudioInputPickerView"), """
            The leaf is declared BEFORE `AudioInputPickerView`, so the "nothing above the leaf \
            reads the snapshot" claim below is measuring an empty or partial slice. Re-anchor \
            it on the parent's own body before trusting it.
            """)
        XCTAssertEqual(Self.occurrences(of: "latencySnapshot()", in: above), 0, """
            `latencySnapshot()` is called ABOVE the leaf's declaration — i.e. somewhere in \
            `AudioInputPickerView` itself. That is the ancestor read the freeze law forbids.
            """)
        XCTAssertEqual(Self.occurrences(of: "latencySnapshot()", in: code), 2, """
            Expected exactly two reads (on appear, on route change). Found \
            \(Self.occurrences(of: "latencySnapshot()", in: code)). A third read is legitimate \
            — refreshing after the monitoring toggle would be one — but it has to be added \
            here deliberately, because the number this guard exists to prevent is not 3, it is \
            a POLL. Raise the count and say which event the new read answers (#364/#664).
            """)
    }

    // MARK: - 6. No poll, and the cross-thread hop is kept

    func testTheReadoutIsEventDrivenAndHopsToTheMainActor() throws {
        let code = try Self.codeText(Self.picker)
        let leaf = try XCTUnwrap(code.range(of: "private struct MonitorLatencyRow: View"),
                                 "cannot anchor the leaf; re-anchor before trusting claim 6.")
        let body = String(code[leaf.lowerBound...])
        // ⛔ #664 (review): `routeChangeNotification` and `.receive(on: DispatchQueue.main)` are
        // NOT unique in this file — `AudioInputPickerView` carries its own hop. If the leaf were
        // moved above its use site, `body` would become the whole file and the parent's copies
        // would satisfy both assertions below even if the leaf had lost its hop entirely. The
        // slice is pinned to the tail by requiring the parent to sit outside it.
        XCTAssertFalse(body.contains("struct AudioInputPickerView"), """
            The slice examined for claim 6 contains `AudioInputPickerView` itself, so the \
            parent's own route-change hop can satisfy assertions meant to be about the leaf. \
            Re-anchor on the leaf's own body (#454/#664).
            """)

        XCTAssertFalse(body.contains("Timer.publish") || body.contains("TimelineView"), """
            The latency readout acquired a POLL. `AVAudioSession` latency changes only when \
            the route changes; a timer here would rebuild a view inside a Picker-hosting sheet \
            on a schedule, which is precisely the 10.76.41 freeze — introduced to refresh a \
            number that cannot change between route changes.
            """)
        XCTAssertTrue(body.contains("routeChangeNotification"),
                      "the readout no longer refreshes when the route changes, so it goes stale.")
        XCTAssertTrue(body.contains(".receive(on: DispatchQueue.main)"), """
            The route-change hop to the main queue is gone. `AVAudioSession` posts this \
            notification from its OWN thread and this closure writes `@State` on a \
            `@MainActor` view — the sibling refresh at the top of the same file carries the \
            identical hop for the identical reason.
            """)
    }

    // MARK: - Helpers

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func codeText(_ path: String) throws -> String {
        SourceText.codeOnly(try repoText(path))
    }

    private static func repoText(_ path: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw NSError(domain: "TheMeasuredLatencyReachesTheScreenTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey:
                        "cannot find \(path) walking up from #filePath — re-anchor (#454)."])
    }
}
