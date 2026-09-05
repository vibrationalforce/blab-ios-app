// TheBufferFollowsTheGrantedRateTests.swift
// Echoel — #961. Blocking bundle. MIXED: claims 1–5 are **SOURCE-TEXT SCANS**
// (`Tests/CISmoke/CLAUDE.md` §1) over `Sources/Echoelmusic/Audio/AudioConfiguration.swift`
// through `SourceText.codeOnly`; claim 6 is **EXECUTED BEHAVIOUR** on the pure static helper.
// Nothing here touches `AVAudioSession` — configuring a real session inside the bundle would
// fight every other test for a process-global.
//
// ⭐ THE DEFECT, MEASURED. `setPreferredIOBufferDuration` takes SECONDS, and iOS turns those
// seconds back into FRAMES at the rate the hardware actually runs. `ioBufferDuration(for:)`
// exists to do the frame→second conversion and takes the rate as a parameter — and every one
// of the five sites in the file passed `preferredSampleRate`, the ASPIRATION handed to
// `setPreferredSampleRate` a few lines earlier and never read back. A parameter that exists
// and that nothing ever varies is the Doctor §C shape one level below a view: the mechanism
// reads as live in every file that mentions it, and no caller can select it.
//
// The consequence is a number, not a worry: 512 frames at an asked 48000 Hz is 10.67 ms, and
// on a device that grants 44100 Hz iOS turns 10.67 ms back into 470 frames. The player who
// chose 512 receives 470 and is told 10.67 ms by the `IO Buffer Duration` line, which prints
// the session's own (granted) value. #855 recorded the founder measuring "23 ms against a
// 10.7 ms choice"; that is the same divergence observed from the reporting end.
//
// ⚠️ WHAT THIS SLICE DOES **NOT** DO, and the omission is deliberate rather than forgotten.
// FOUR other sites still divide by `preferredSampleRate` (two inline re-asserts in the
// category transitions, two latency ESTIMATES). The two re-asserts are #855's own repair and
// changing them is a second behaviour change on a second path; the two estimates are reports,
// not requests, and correcting a report is a different argument from correcting an ask. One
// Ralph slice, one path. Claim 4 pins that the pre-activation ask STAYS — this guard must not
// be read as "the constant is banned".
//
// ⚠️ NOT DEVICE-VERIFIED. Whether iOS honours a buffer re-ask on an already-active session,
// and what it grants, is an on-device fact. What is proven here is that the app now asks with
// the rate it was actually given instead of the one it wanted. NEEDS-FOUNDER-VERIFY: the next
// `echoel_diag.log` carries one `session: rate asked … granted …` line per configure — if the
// two numbers differ, every latency figure in that log was computed at the wrong one.
//
// DRIVEN (Python transcription of `SourceText.codeOnly` plus each source predicate, run
// against `git show <rev>:Sources/Echoelmusic/Audio/AudioConfiguration.swift` for each tree):
//
//   | tree                | RED source claims | of |
//   |---------------------|-------------------|----|
//   | da2bb3e (#959b)     | 5                 | 6  |
//   | 7c0595b (#960)      | 5                 | 6  |
//   | worktree (#961)     | 0                 | 6  |
//
// ⛔ I FIRST WROTE 4 IN THAT COLUMN FROM REASONING AND THE DRIVEN RUN SAID 5. Claim 6 is red
// on the parents too — there is no `catch` inside `configureAudioSession` there, because there
// is no re-ask to fail. Correct, and named correctly by its own message; but the number was a
// guess, and a table typed from memory is the #941 defect this bundle keeps catching.
// Claim 4 is GREEN on all three trees, which is what a counterweight should be.
//
// AND EACH CLAIM WAS SHOWN TO FAIL FOR ITS OWN REASON (#367) by mutating the worktree:
//
//   read-back moved above `setActive`        → c1
//   re-ask divides by the aspiration again   → c2 (and c4, which then counts two)
//   tolerance gate removed                   → c3
//   pre-activation ask deleted               → c4
//   new line numbered `configure 5/4`        → c5
//   refused re-ask sent to `log.audio`       → c5 + c6
//
// The two spillovers are real signals, not noise: both mutations move a needle that a second
// claim pins by an exact count.

import XCTest
@testable import Echoelmusic

final class TheBufferFollowsTheGrantedRateTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"

    private func source() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(Self.config), encoding: .utf8))
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The body of `configureAudioSession`, bounded by the next `static func` rather than by a
    /// character count. #408: a fixed window is a date — the one in this file's neighbour broke
    /// at 720 characters after a single comment edit.
    private func configureBody(_ code: String) throws -> String {
        let fn = "static func configureAudioSession"
        XCTAssertEqual(occurrences(of: fn, in: code), 1,
                       "`\(fn)` is no longer unique — every window below would open elsewhere (#408).")
        let start = try XCTUnwrap(code.range(of: fn),
                                  "`\(fn)` is gone — re-anchor this file (§4).")
        let rest = code[start.upperBound...]
        let end = rest.range(of: "\n    static func")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - 1. The granted rate is read, and it is read AFTER activation

    func testTheGrantedRateIsReadBackAfterTheSessionIsActive() throws {
        let body = try configureBody(try source())
        guard let activate = body.range(of: "setActive(true, options: .notifyOthersOnDeactivation)"),
              let readBack = body.range(of: "let grantedRate = audioSession.sampleRate") else {
            XCTFail("""
                `configureAudioSession` no longer activates the session, or no longer reads \
                `audioSession.sampleRate` back afterwards. Without the read-back the file asks \
                for a buffer duration computed at a rate the hardware may have refused, and \
                nothing in the app or in an exported log can tell that it did (#961).
                """)
            return
        }
        XCTAssertTrue(activate.upperBound < readBack.lowerBound, """
            The granted rate is read BEFORE `setActive`. There it is whatever rate the session \
            happened to be at, not the one this configure will get — the read compiles, reports \
            a plausible number and answers a different question (#961).
            """)
    }

    // MARK: - 2. The re-ask divides by the GRANTED rate

    func testTheReAskUsesTheGrantedRateAndNotTheAspiration() throws {
        let body = try configureBody(try source())
        XCTAssertEqual(occurrences(of: "ioBufferDuration(for: grantedRate)", in: body), 1, """
            `configureAudioSession` no longer converts the buffer at the GRANTED rate. \
            `setPreferredIOBufferDuration` takes seconds and iOS converts them back to frames \
            at the rate it runs: dividing 512 frames by an asked 48000 on hardware granted \
            44100 delivers 470 frames to a player who chose 512 (#961).
            """)
        XCTAssertEqual(occurrences(of: "setPreferredIOBufferDuration(regranted)", in: body), 1, """
            The re-computed duration is no longer handed to the session. Computing the right \
            number and not asking for it is the same as not computing it.
            """)
    }

    // MARK: - 3. The re-ask is conditional, not unconditional

    func testTheReAskOnlyFiresWhenTheGrantDisagrees() throws {
        let body = try configureBody(try source())
        XCTAssertTrue(body.contains("abs(grantedRate - preferredSampleRate) > 1"), """
            The buffer re-ask is no longer gated on a real disagreement. Unconditional, it \
            issues a second session call on every launch of every device — including the \
            overwhelmingly common one where the ask was granted exactly and the two durations \
            are the same number. The tolerance is what makes this a repair and not churn (#961).
            """)
        XCTAssertTrue(body.contains("grantedRate > 0"), """
            The re-ask no longer guards against a non-positive granted rate. \
            `ioBufferDuration(for:)` has its own floor, but handing it a zero here would mean \
            asking the session for a duration derived from a rate the session just denied \
            having — a guard at the boundary, not a rescue downstream (`engineering.md` §3).
            """)
    }

    // MARK: - 4. COUNTERWEIGHT — the pre-activation ask stays

    /// ⭐ THIS CLAIM IS GREEN ON BOTH TREES ON PURPOSE, and splitting it out is a #367 repair.
    /// It was first written as one method with the shape checks below it, and that method went
    /// RED on the parent tree — but for the wrong reason: because the new lines did not exist
    /// yet, not because the pre-activation ask had been removed. A counterweight that fails on
    /// the tree it is protecting proves nothing about the thing it names.
    func testThePreActivationAskStays() throws {
        let body = try configureBody(try source())
        // The ask at the aspiration is CORRECT and stays. It is how the session learns the
        // latency the app wants before it negotiates. #364: this guard forbids nothing.
        XCTAssertEqual(occurrences(of: "ioBufferDuration(for: preferredSampleRate)", in: body), 1, """
            The pre-activation buffer ask is gone. #961 ADDS a read-back; it does not replace \
            the ask. Removing the ask means the session negotiates with no latency preference \
            at all and the re-ask below only ever corrects a number nobody asked for.
            """)
    }

    // MARK: - 5. The new diag line is DETAIL, not a fifth rung

    /// A fifth numbered step renumbers a four-step ladder that a neighbouring guard pins by
    /// equality, and `diag-ladder`'s terminator census reads any ALL-CAPS word after a ladder
    /// prefix as a line that ENDS the ladder. #954: making a rung "more useful" is exactly how
    /// a HEALTHY run started reading as a death, and it was caught only by driving the tool.
    func testTheNewDiagLineIsNotARung() throws {
        let body = try configureBody(try source())
        // #1022 added a THIRD unnumbered detail line in this same function (the `.playback`
        // option-set fallback). It is listed here rather than left uncovered: the rule this
        // claim states is about EVERY non-rung line in the window, and a list that names two
        // of three teaches the next author that the third is exempt.
        let newLines = ["session: rate asked ", "session: the buffer re-ask was refused (",
                        "session: the .playback option set was refused ("]
        for line in newLines {
            XCTAssertEqual(occurrences(of: line, in: body), 1,
                           "`\(line)` left `configureAudioSession` — re-anchor (§4).")
            guard let r = body.range(of: line) else { continue }
            let printed = String(body[r.lowerBound...].prefix(60))
            XCTAssertFalse(printed.contains("/4"), """
                The new diag line has been numbered into the 1/4…4/4 ladder. It is DETAIL after \
                the last rung, not a fifth step: numbering it reddens the equality pins on the \
                four rungs and puts a step into a log that the ladder does not have (#954/#961).
                """)
            XCTAssertNil(printed.range(of: "[A-Z]{3,}", options: .regularExpression), """
                The new diag line now carries an all-caps word. `diag-ladder`'s terminator \
                census matches `<ladder prefix> …<ALL-CAPS WORD>`, so this line would start \
                reading as a line that ENDS the `session: configure` ladder — a complete \
                launch reported as a death (#961).
                """)
        }
    }

    // MARK: - 6. A refused re-ask is visible, not swallowed

    func testARefusedReAskIsReported() throws {
        let body = try configureBody(try source())
        // ⛔ #1022 — THIS ANCHOR WAS `body.range(of: "catch {")`, i.e. the FIRST `catch` in the
        // function, and it silently changed subject the moment #1022 added an earlier one (the
        // `.playback` option-set fallback). It would have stayed GREEN while inspecting a
        // different `catch` entirely — the #408 shape: an anchor that still matches is not the
        // same as an anchor that still means what it named. The re-ask's own call is the stable
        // anchor; the `catch` must follow IT.
        guard let reAsk = body.range(of: "setPreferredIOBufferDuration(regranted)"),
              let c = body.range(of: "catch {", range: reAsk.upperBound..<body.endIndex) else {
            XCTFail("""
                The buffer re-ask no longer has a `catch` of its own. It must not `throw` out of \
                `configureAudioSession`: the session is already configured and usable, and an \
                unusable-latency preference is not a reason to fail a launch (#961).
                """)
            return
        }
        let after = String(body[c.upperBound...].prefix(400))
        XCTAssertTrue(after.contains("EchoelCrashLog.breadcrumb("), """
            The re-ask's failure is swallowed. `os_log` does not reach the exported \
            `echoel_diag.log` (#859), so a device whose session refuses the corrected duration \
            would look identical to one where the correction was never needed — the exact \
            silence the lifecycle ladder exists to remove.
            """)
    }

    // MARK: - 7. EXECUTED — the helper really is rate-sensitive

    /// The whole slice rests on `ioBufferDuration(for:)` producing a DIFFERENT duration for a
    /// different rate. If it ever stopped doing that, all five source claims above would stay
    /// green over code that had become a no-op. Asserted as a RATIO on purpose:
    /// `currentBufferSize` is a `nonisolated(unsafe) static var` that other tests in this
    /// bundle may have moved, so an absolute millisecond figure here would be order-dependent
    /// (the trap `TheBufferPolicyHasADoorTests` records in its own header).
    func testTheHelperConvertsFramesAtTheRateItIsGiven() throws {
        let at48 = AudioConfiguration.ioBufferDuration(for: 48_000)
        let at44 = AudioConfiguration.ioBufferDuration(for: 44_100)
        XCTAssertGreaterThan(at48, 0, "the helper returned a non-positive duration for 48 kHz")
        XCTAssertEqual(at44 / at48, 48_000.0 / 44_100.0, accuracy: 1e-9, """
            `ioBufferDuration(for:)` no longer scales inversely with the rate it is given. \
            Every source claim in this file would remain green while the re-ask asked for the \
            same duration it was correcting (#961).
            """)
        // Non-finite and non-positive inputs must not produce a non-finite duration — this is
        // the boundary the `grantedRate > 0` gate in claim 3 relies on NOT having to catch.
        for bad in [0.0, -48_000.0, Double.nan, Double.infinity] {
            let d = AudioConfiguration.ioBufferDuration(for: bad)
            XCTAssertTrue(d.isFinite && d > 0, """
                `ioBufferDuration(for: \(bad))` returned \(d). A non-finite or non-positive \
                duration reaches `AVAudioSession` as a preference. `+infinity` is the one that \
                slips a bare `> 0` test, and the granted-rate read-back is the first caller \
                whose argument is not a compile-time constant (#961).
                """)
        }
    }
}
