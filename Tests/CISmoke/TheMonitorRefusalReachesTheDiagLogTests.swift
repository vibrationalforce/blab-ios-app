// TheMonitorRefusalReachesTheDiagLogTests.swift
// Echoel — #650: five slices of instrumentation wrote to a sink the founder cannot export.
//
// WHAT THIS GUARDS. When "Monitoring could not start" appears, the ONE artefact a founder can
// send is `echoel_diag.log`. That file is written by `EchoelCrashLog.breadcrumb` and by nothing
// else — it is where `launch`, `init a:`, `rPPG:` and `trust:` come from. Every "Input
// monitoring: …" line added by #613, #625, #628 and #631 to settle this exact failure went to
// `log.audio`, i.e. `os_log` plus an in-memory ring that `ProfessionalLogger`'s own doc calls
// "write-only today". `AudioEngine` carried exactly TWO breadcrumbs before this slice, both in
// the audio-timing tally, neither on the monitoring path.
//
// ⭐ MEASURED, NOT INFERRED, and the measurement is what turns this from a hunch into a hole.
// Build 2531, 2026-08-20: the founder's screen recording shows the refusal banner at 13:43:49
// and his diag log covers 13:43:23 → 13:44:09. The failure sits INSIDE the logged window and
// the log names none of the exits. Correlating the recording's wall clock with the log's epoch
// stamps is the whole argument — without it, "the log says nothing" is equally well explained
// by "he did not upload the right window", and four cycles of hypotheses would have continued.
//
// ⚠️ THIS SLICE FIXES NO BUG. Monitoring may still refuse on the next build; what changes is
// that the refusal will NAME ITSELF in the file the founder already knows how to send. Saying
// so plainly matters, because the previous four slices each shipped a hypothesis as if it were
// a repair, and the reason none could be confirmed or killed is the sink, not the reasoning.
//
// KIND (§1): SOURCE-TEXT SCAN. `AudioEngine` is `@MainActor` and its monitoring path needs a
// live `AVAudioEngine`, a session and a microphone; nothing in this bundle can drive it. What
// IS checkable is that no exit writes to only one sink. **DEVICE PROBE, open:** that the next
// diag log actually carries a `monitor:` line is the founder's next take, not ours.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (8d65671), both trees, raw and
// stripped:
//   · **1 REGRESSION — claim 1.** The parent has ZERO `EchoelCrashLog.breadcrumb` calls inside
//     `setInputMonitoring` / `engageInputMonitoring` / `rearmInputMonitoring`; this tree routes
//     all of them through one helper that writes both sinks.
//   · **1 REGRESSION — claim 2.** The parent spells `log.audio("Input monitoring` at **EIGHT**
//     sites; here exactly ONE remains, inside the helper. 8 → 1, driven. (⛔ This said six,
//     counted off the exits I had edited rather than off the file — the ON, OFF and re-arm
//     lines were monitoring lines too and I had not counted them as such until the driver did.)
//   · **1 REGRESSION — claim 3.** `engageInputMonitoring`'s `@unknown default` returned false
//     with NO line in ANY sink on the parent — the only exit that was silent even in `os_log`.
//   · **1 COUNTERWEIGHT — claim 4**, green on both trees, and the point of the file: the
//     breadcrumb writer must stay the diag file's writer. If `EchoelCrashLog.breadcrumb` ever
//     stops being what produces `echoel_diag.log`, every line this slice adds goes back to
//     being invisible and nothing else would say so.
//   · **1 COUNTERWEIGHT — claim 5**, green on both trees: no breadcrumb inside a render block.
//     `breadcrumb` does `Date()` plus `write(2)`, which is file I/O and banned on the audio
//     thread. This slice put ten new calls into a file that also contains render code, so the
//     ban is worth pinning at the moment the count went up.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH** — 0 of the
// 8 scan verdicts flip, on either tree.
// ⛔ I PREDICTED "TRAGEND, 1 of 8" AND WROTE THE MECHANISM OUT IN FULL — the helper's doc
// quotes both sinks while explaining the split, so surely an unstripped claim 2 counts the
// prose. It does not, and #649's header says why in as many words: **a well-built needle
// carries its call context and is therefore NARROWER than the prose that quotes the bare
// phrase.** The needle is `log.audio("Input monitoring` — it includes the opening quote of the
// string literal, and no comment spells that. FOURTH consecutive slice where I asserted
// load-bearing from the shape of a diff and measured otherwise. The rule is not "predict
// better"; it is that this line is not writable before the driver runs.
//
// ⚠️ #364: a DIFFERENT dual sink is not forbidden. Teaching `ProfessionalLogger` to mirror
// `.error` into the crash log would satisfy this law better than a helper does, and would turn
// claims 1–2 red — that is the moment to rewrite this file, not to delete it. What is
// forbidden silently is a monitoring exit that a founder's export cannot see.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMonitorRefusalReachesTheDiagLogTests: XCTestCase {

    private static let engine = "Echoelmusic/Audio/AudioEngine.swift"
    private static let crashLog = "Echoelmusic/Core/EchoelCrashLog.swift"

    /// 1 — REGRESSION. Every monitoring outcome reaches the breadcrumb sink.
    func testEveryMonitoringOutcomeIsBreadcrumbed() throws {
        let code = try Self.codeText(Self.engine)
        let helper = try Self.body(of: "private func logMonitorOutcome", in: code)
        XCTAssertTrue(helper.contains("EchoelCrashLog.breadcrumb"), """
            `logMonitorOutcome` no longer writes the breadcrumb sink. That sink is the ONLY \
            writer of `echoel_diag.log`; without it every monitoring refusal is invisible to \
            the one artefact a founder can send, which is the #650 hole verbatim.
            """)
        XCTAssertTrue(helper.contains("log.audio"), """
            `logMonitorOutcome` no longer writes `os_log`. Console is where a wired device is \
            read live; dropping it trades one blind spot for another.
            """)
        let calls = Self.occurrences(of: "logMonitorOutcome(", in: code) - 1   // minus the decl
        XCTAssertGreaterThanOrEqual(calls, 9, """
            Only \(calls) monitoring outcomes route through the dual sink. #650 routed ten: \
            three permission exits, three failure exits inside `setInputMonitoring`, ON, OFF, \
            the session-downgrade warning and the re-arm. A path that stops using the helper is \
            a path whose evidence stops reaching the founder — and it will look fine in Console.
            """)
    }

    /// 2 — REGRESSION. No monitoring line may go to `os_log` ALONE.
    ///
    /// ⚠️ Anchored on the message stem, not on `log.audio` in general: `AudioEngine` logs plenty
    /// that has nothing to do with monitoring, and banning the whole call would be the #364
    /// failure (a guard that forbids ordinary work gets deleted, and the law goes with it).
    func testNoMonitoringLineGoesToOneSinkOnly() throws {
        let code = try Self.codeText(Self.engine)
        let single = Self.occurrences(of: "log.audio(\"Input monitoring", in: code)
        XCTAssertEqual(single, 1, """
            \(single) monitoring lines write `os_log` directly. Exactly one may: the line INSIDE \
            `logMonitorOutcome`, which is the helper doing its job. Any other is a refusal or a \
            state change that the founder's diag export cannot see — six of them existed before \
            #650 and four cycles of hypotheses were spent for want of the evidence they held.
            """)
    }

    /// 3 — REGRESSION. The permission switch has no silent arm left.
    func testTheUnknownPermissionCaseIsNotSilent() throws {
        let code = try Self.codeText(Self.engine)
        let door = try Self.body(of: "func engageInputMonitoring", in: code)
        guard let unknown = door.range(of: "@unknown default:") else {
            return XCTFail("`engageInputMonitoring` no longer switches on the permission — re-anchor (#454).")
        }
        // ⛔ THIS TOOK `.prefix(400)` AND WAS RED ON ITS OWN CORRECT TREE — the arm carries a
        // five-line comment explaining why the exit matters, which pushed the call past 400
        // characters. A fixed window in a repo that writes 30-line comment blocks is unsound BY
        // CONSTRUCTION (#408), and I wrote this one into the guard whose whole subject is
        // instrumentation. Bounded by the arm's own `return` instead, so the prose can grow.
        guard let end = door.range(of: "return false", range: unknown.upperBound..<door.endIndex) else {
            return XCTFail("the `@unknown default` arm no longer returns — re-anchor (#454).")
        }
        let arm = String(door[unknown.upperBound..<end.lowerBound])
        XCTAssertTrue(arm.contains("logMonitorOutcome"), """
            The `@unknown default` arm returns false without writing any sink. It is unreachable \
            today, which is exactly why it would be the hardest exit to diagnose if a future \
            `AVAudioApplication` case ever landed there: the door would render "try again" and \
            no log anywhere would say why.
            """)
    }

    /// 4 — COUNTERWEIGHT, green on both trees. The premise the whole slice rests on.
    func testTheBreadcrumbIsStillTheDiagFilesWriter() throws {
        let crash = try Self.codeText(Self.crashLog)
        let writer = try Self.body(of: "static func breadcrumb", in: crash)
        XCTAssertTrue(writer.contains("write(fd"), """
            `EchoelCrashLog.breadcrumb` no longer writes the file descriptor. #650's entire \
            argument is that this function IS `echoel_diag.log`; if the file gains another \
            writer, or this one stops writing, re-derive which sink a founder's export actually \
            carries before trusting any monitoring line to reach it. ⚠️ #916 changed what \
            the EXPORT carries — the Diagnostics row now appends a retained crash from an \
            earlier run — WITHOUT adding a writer to this file, so this claim stays true; \
            "the export" and "this file" are no longer the same set of bytes.
            """)
        let rppg = try Self.codeText("Echoelmusic/Bio/CameraRPPGBioPublisher.swift")
        XCTAssertTrue(rppg.contains("EchoelCrashLog.breadcrumb"), """
            The rPPG path stopped breadcrumbing. It is the reference case — the reason the \
            founder's log carries `rPPG:` lines at all — and if IT moved to another sink, this \
            file is reasoning from a sibling that no longer exists.
            """)
    }

    /// 5 — COUNTERWEIGHT, green on both trees. File I/O stays off the audio thread.
    ///
    /// ⚠️ A TEXT SCAN CANNOT PROVE THREAD SAFETY and does not claim to. What it pins is the one
    /// mechanical tell available here: a breadcrumb inside a render-block closure. The real
    /// guarantee is that every call site added by #650 is graph configuration on the main actor,
    /// which a human read and this file cannot.
    func testNoBreadcrumbSitsInsideARenderBlock() throws {
        let code = try Self.codeText(Self.engine)
        // ⛔ #655 — THIS NEEDLE WENT ONE INDIRECTION BLIND AND NOTHING SAID SO. #653 added
        // `AudioConfiguration.latencyBreadcrumb`, which performs the SAME `write(2)` behind a
        // name `EchoelCrashLog.breadcrumb` cannot match. Both names are banned now. A THIRD
        // wrapper would need adding here too — the honest limit of a text scan.
        //
        // ⛔ #658 — AND #655's OTHER HALF WAS VACUOUS EXACTLY WHERE IT MATTERED. It kept the
        // `prefix(1200)` window and `range(of: marker)`, which takes the FIRST match:
        // `installTap` occurs THREE times in this file, and the first is a metering tap ~1000
        // lines from the monitor tap the slice was about. The two markers that actually name
        // render blocks — `renderBlock`, `AURenderPullInputBlock` — appear ZERO times here, so
        // their `continue` was a silent no-op. The whole law rested on one window around a
        // meter tap.
        //
        // ⚠️ AND THE OBVIOUS REPAIR WOULD HAVE REDDENED A CORRECT TREE, which is the #655
        // failure mode reproduced by #655. Simply looping all occurrences with the SAME
        // character window finds `AudioConfiguration.latencyBreadcrumb` inside the monitor
        // tap's 1200-character window — the `"monitor on"` call, which sits AFTER the closure
        // closes, on the main actor, and is safe. A fixed character window is unsound by
        // construction (#408); this file says so itself twenty lines up about a different one,
        // and #650's `.prefix(400)` already paid for it once.
        //
        // So: every occurrence, and bounded by the closure's own BRACES. Measured on this
        // tree — 3 `installTap` regions of 5841 / 831 / 230 characters, none containing a
        // banned name — where the character window would have flagged the third.
        var examined = 0
        for marker in ["installTap", "renderBlock", "AURenderPullInputBlock"] {
            var searchFrom = code.startIndex
            while let hit = code.range(of: marker, range: searchFrom..<code.endIndex) {
                searchFrom = hit.upperBound
                guard let closure = try? Self.closureBody(after: hit.upperBound, in: code) else {
                    continue
                }
                examined += 1
                for banned in ["EchoelCrashLog.breadcrumb", "AudioConfiguration.latencyBreadcrumb"] {
                    XCTAssertFalse(closure.contains(banned), """
                        `\(banned)` appears INSIDE the closure attached to `\(marker)`. It \
                        ends in `Date()` plus `write(2)` — file I/O, which \
                        `.claude/rules/swift-audio.md` bans outright on the audio thread. \
                        #650 added ten breadcrumb calls to this file and #653 added three \
                        more behind a wrapper; this is the assertion that keeps the next one \
                        out of a render path.
                        """)
                }
            }
        }
        // #454: a scan that examined nothing passes for the wrong reason. Two of the three
        // markers match nothing in this file TODAY and are kept only so a render block added
        // later is covered the day it is written — which is exactly why the count matters.
        XCTAssertGreaterThanOrEqual(examined, 1, """
            No tap or render closure was found in `AudioEngine.swift` at all, so every \
            assertion above was skipped and this test passed without looking at anything. \
            Re-anchor the marker list (#454) — do not accept a green from an empty loop.
            """)
    }

    // MARK: - helpers

    /// The brace-matched closure body that opens after `index`.
    ///
    /// #658. A tap call is `installTap(onBus:bufferSize:format:) { buffer, time in … }`, so the
    /// first `{` after the call name opens the closure. Brace-matching it gives the region that
    /// actually runs on the audio thread — which is the question — instead of a character count
    /// that also sweeps up whatever happens to be written nearby.
    private static func closureBody(after index: String.Index, in text: String) throws -> String {
        guard let open = text[index...].firstIndex(of: "{") else {
            throw MonitorAnchorMissing(reason: "no closure brace after a tap/render marker")
        }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw MonitorAnchorMissing(reason: "unbalanced braces after a tap/render marker")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// Brace-matched body after `key` (#408 — never a fixed line window).
    private static func body(of key: String, in text: String) throws -> String {
        let hits = occurrences(of: key, in: text)
        guard hits == 1 else {
            throw MonitorAnchorMissing(reason: """
                `\(key)` occurs \(hits)× — this scan needs exactly one so it cannot read a \
                different declaration (#408).
                """)
        }
        guard let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw MonitorAnchorMissing(reason: "no opening brace after `\(key)`")
        }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw MonitorAnchorMissing(reason: "unbalanced braces after `\(key)`")
    }

    private struct MonitorAnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    private static func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent("Sources").appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MonitorAnchorMissing(reason: """
                Sources/\(relative) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
