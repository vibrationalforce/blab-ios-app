// TheMeasuredLatencyReachesTheDiagLogTests.swift
// Echoel — #653: the app measured its own round-trip latency and showed it to nobody.
//
// WHAT THIS GUARDS. `AudioConfiguration.latencyStats()` builds a tidy report — sample rate,
// IO buffer, input latency, output latency, total, a target and a ✅/⚠️/❌ verdict. Measured
// before this slice: it had exactly ONE caller (`AudioEngine.prepareGraph`), and that caller
// wrote it to `log.audio`, which is `os_log` plus a write-only in-memory ring. Neither sink
// reaches `echoel_diag.log`, the file the founder exports. No view rendered the number either.
// `git grep -n 'breadcrumb(.*[lL]atency' -- Sources` returned NOTHING.
//
// ⭐ THIS IS THE #650 HOLE ONE LAYER UP, AND NAMING THAT IS THE POINT. #650 found the input
// monitoring path fully instrumented into the unexportable sink and moved it to the breadcrumb
// file; the founder's monitoring failure was never a missing diagnosis, it was a diagnosis
// written where he could not read it. The latency report is the same shape: five slices of
// careful measurement, addressed to a console nobody attaches. The founder's literal ask is
// "Alle Latenzen und Kombinationen optimiert für Sessions" — and neither he nor this session
// could name ONE measured latency figure from his hardware.
//
// ⚠️ THE ROUTE IS PART OF THE MEASUREMENT. The same phone reports a different round-trip on
// the built-in mic, a wired interface and a Bluetooth headset (~150-250 ms on A2DP), and
// "Kombinationen" is the founder's word for exactly that. A latency number without its route
// cannot be compared against another line in the same log, which is why `route` is a required
// parameter and not an optional embellishment. The founder's device signal names an HI-X25BT —
// a Bluetooth headphone — so this is not hypothetical for the very next take.
//
// KIND (§1): MIXED, and claim 1 is the BEHAVIOURAL half — it calls `latencyLine` and asserts
// on the string it returns, so the formatting law is executed, not described. Claims 2-5 are
// source-text scans over the wiring, which needs a live `AVAudioSession`, a route and hardware
// that nothing here can provide. **DEVICE PROBE, open:** what the numbers actually ARE on the
// founder's phone, wired and over Bluetooth. That is the whole reason the line exists.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (4b1a52d), both trees, raw and
// stripped. Numbers written after the run.
// **Scan half — 6 verdicts: 4 REGRESSIONS, 2 COUNTERWEIGHTS.**
//   · REGRESSION — claim 2: zero `latencyBreadcrumb` call sites on the parent.
//   · REGRESSION — claims 3a and 3b: `latencyBreadcrumb` does not exist there, so nothing
//     writes a latency figure to the exportable sink and nothing carries a route.
//   · REGRESSION — claim 5: on the parent its two anchors do not both exist, so it takes the
//     re-anchor `XCTFail` path. ⚠️ Stated plainly because it is the weaker kind of red: it
//     fails there for "the pair is not present", which is literally true (the latency half was
//     never written) but is not the *ordering* failure the claim is built to catch. The
//     ordering can only be tested once both halves exist.
//   · COUNTERWEIGHTS — claims 4a and 4b: `latencyStats()` and its `log.audio` call survive on
//     both trees. They are the guard against "fixing" this by MOVING the report instead of
//     adding a second reader.
//
// ⚠️ CLAIM 1 (BEHAVIOURAL) CANNOT BE GRADED AGAINST THE PARENT AT ALL, and that is the
// honest statement rather than a flattering one: `AudioConfiguration.latencyLine` does not
// exist on 4b1a52d, so the test file does not compile there. Its verdicts were driven against
// a Python transcription of the function (both PASS: the wired set formats
// `total=9.0ms` from 5.0 + 1.5 + 2.5, and a NaN/negative set yields `?` per field with the
// total taken over the readable parts only). A behavioural claim over a brand-new pure
// function is always in this position; saying so is the §3 requirement, not a defect.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH — 0 of 12
// scan verdicts flip** (6 claims × 2 trees). Every needle here carries call syntax
// (`latencyBreadcrumb(reason:`, `log.audio(AudioConfiguration.latencyStats())`) or a
// declaration prefix, which is narrower than any prose that quotes the bare name — the same
// measurement as #652, and the reason the prediction is written after the run and not before.
//
// ⚠️ #364: emitting the line from MORE places (a take starting, an export, an interface
// swap) is expected and must never redden claim 2, which is why it is a floor. What is
// forbidden silently is routing this measurement back into a sink the founder cannot export,
// or dropping the route from the line.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMeasuredLatencyReachesTheDiagLogTests: XCTestCase {

    private static let engine = "Echoelmusic/Audio/AudioEngine.swift"
    private static let config = "Echoelmusic/Audio/AudioConfiguration.swift"

    // MARK: - 1: behavioural — the formatting law, executed

    /// 1a — a plausible wired set: the parts are reported and the total is their sum.
    func testTheLineReportsThePartsAndTheirSum() {
        let line = AudioConfiguration.latencyLine(
            reason: "monitor on",
            sampleRate: 48_000,
            ioBufferSeconds: 0.005,      // 5.0 ms
            inputSeconds: 0.001_5,       // 1.5 ms
            outputSeconds: 0.002_5,      // 2.5 ms
            route: "Built-In Microphone→Speaker")
        XCTAssertTrue(line.hasPrefix("latency: monitor on "), """
            The line no longer opens with `latency: <reason> `. The prefix is what makes the \
            measurement greppable in a founder log that also carries `monitor:`, `rPPG:` and \
            `launch` lines — a reader pulls one class of line with one search.
            Got: \(line)
            """)
        XCTAssertTrue(line.contains("sr=48000"), "sample rate missing or reshaped: \(line)")
        XCTAssertTrue(line.contains("buf=5.0"), "IO buffer missing or mis-scaled: \(line)")
        XCTAssertTrue(line.contains("in=1.5"), "input latency missing or mis-scaled: \(line)")
        XCTAssertTrue(line.contains("out=2.5"), "output latency missing or mis-scaled: \(line)")
        // 5.0 + 1.5 + 2.5 = 9.0. The TOTAL is the number a founder reads first, and it is the
        // one that decides whether monitoring is usable — a wrong sum is a wrong verdict.
        XCTAssertTrue(line.contains("total=9.0ms"), """
            The total is not the sum of the three parts. This is the figure that decides \
            whether a take is monitorable at all; the parts exist to explain it.
            Got: \(line)
            """)
        XCTAssertTrue(line.contains("route=Built-In Microphone→Speaker"), """
            The route is gone from the line. A latency figure without the combination it was \
            measured on cannot be compared against another line in the same log, and \
            "Kombinationen" is exactly what the founder asked to have optimised.
            Got: \(line)
            """)
    }

    /// 1b — a session queried mid-teardown answers with anything. It must not print `nanms`.
    ///
    /// ⚠️ This is an edge case, not an impossibility (`engineering.md` §3): `AVAudioSession`
    /// can report 0, a negative, or a non-finite value while the route is being rebuilt — and
    /// a route rebuild is precisely when this line fires. A line reading `total=nanms` looks
    /// like a parse bug in the log rather than a session that had no answer, which sends the
    /// next reader after the wrong thing.
    func testANonFiniteMeasurementDoesNotPoisonTheLine() {
        let line = AudioConfiguration.latencyLine(
            reason: "route change",
            sampleRate: .nan,
            ioBufferSeconds: .nan,
            inputSeconds: -1,
            outputSeconds: 0.010,
            route: "none→none")
        XCTAssertFalse(line.lowercased().contains("nan"), "non-finite leaked into the line: \(line)")
        XCTAssertFalse(line.contains("-"), "a negative measurement leaked into the line: \(line)")
        XCTAssertTrue(line.contains("sr=?"), "an unusable sample rate must read `?`: \(line)")
        XCTAssertTrue(line.contains("buf=?"), "an unusable buffer must read `?`: \(line)")
        XCTAssertTrue(line.contains("in=?"), "a negative input latency must read `?`: \(line)")
        // The one usable part still counts, and the total is over the usable parts only —
        // reporting 0.0 because one field was unreadable would hide a real 10 ms output path.
        XCTAssertTrue(line.contains("out=10.0"), "the usable part was dropped: \(line)")
        XCTAssertTrue(line.contains("total=10.0ms"), """
            The total must sum the parts that ARE readable. Zeroing the whole line because one \
            field was unavailable throws away the measurement this slice exists to capture.
            Got: \(line)
            """)
    }

    // MARK: - 2-5: the wiring

    /// 2 — a FLOOR (#364). Emitting from more places is expected; emitting from none is the bug.
    func testTheLineIsEmittedFromTheEngine() throws {
        let code = try Self.codeText(Self.engine)
        let sites = Self.count(of: "AudioConfiguration.latencyBreadcrumb(reason:", in: code)
        XCTAssertGreaterThanOrEqual(sites, 3, """
            Only \(sites) `latencyBreadcrumb` call sites in `AudioEngine`; #653 wired THREE, \
            and each answers a different question: `start` (what does this device cost at \
            rest), `route change` (a Bluetooth headset connecting is the only event that \
            changes the round-trip with no user action), and `monitor on` (the moment that \
            decides whether monitoring is usable at all). Removing one is a real decision — \
            say which question stopped mattering.
            """)
    }

    /// 3 — the whole point: it must reach the sink the founder can EXPORT.
    func testTheEmitterWritesToTheExportableSink() throws {
        let code = try Self.codeText(Self.config)
        guard let body = Self.body(of: "static func latencyBreadcrumb", in: code) else {
            return XCTFail("`latencyBreadcrumb` is no longer uniquely declared — re-anchor (#454).")
        }
        XCTAssertTrue(body.contains("EchoelCrashLog.breadcrumb"), """
            `latencyBreadcrumb` no longer writes to `EchoelCrashLog`. That is the ENTIRE \
            slice: `log.audio` is `os_log` plus a write-only in-memory ring, and neither \
            reaches `echoel_diag.log`. A latency measurement the founder cannot export is the \
            state this file was written to end — and it is the same hole #650 closed for the \
            monitoring path one slice earlier.
            """)
        XCTAssertTrue(body.contains("route:"), """
            `latencyBreadcrumb` stopped passing a route. The number alone cannot be compared \
            between two lines of the same log; see the header.
            """)
    }

    /// 4 — COUNTERWEIGHT. The console report was ADDED TO, not replaced.
    func testTheConsoleReportSurvives() throws {
        let config = try Self.codeText(Self.config)
        XCTAssertTrue(config.contains("static func latencyStats()"), """
            `latencyStats()` is gone. #653 deliberately kept BOTH: the report carries the \
            target and the ✅/⚠️/❌ verdict for someone with a console attached, the \
            breadcrumb carries the comparable one-liner for a shared log. Replacing one with \
            the other trades a working diagnostic for a different working diagnostic and gains \
            nothing.
            """)
        let engine = try Self.codeText(Self.engine)
        XCTAssertTrue(engine.contains("log.audio(AudioConfiguration.latencyStats())"), """
            The console report is no longer logged at graph preparation. See above — the two \
            sinks serve two different readers.
            """)
    }

    /// 5 — the #650 pairing: the monitor-ON fact and its measurement must stay together.
    func testTheMonitorOnFactAndItsLatencySitTogether() throws {
        let code = try Self.codeText(Self.engine)
        guard let onSite = code.range(of: "logMonitorOutcome(\"ON (gain "),
              let latency = code.range(of: "AudioConfiguration.latencyBreadcrumb(reason: \"monitor on\")"),
              onSite.upperBound < latency.lowerBound else {
            return XCTFail("""
                The monitor-ON breadcrumb and its latency line are no longer both present with \
                the fact first — re-anchor claim 5 (#454). An extraction that finds nothing \
                would make the assertion below vacuously green.
                """)
        }
        // ⚠️ NOT A CHARACTER WINDOW. #652 measured the previous guard in this family at TEN
        // characters from a false red because it bounded a region with `suffix(600)`. The
        // question here is "does anything RETURN between the fact and its measurement", and
        // a `return` is the exact token that would separate them — so the region between the
        // two anchors is read for one, rather than its length being guessed at.
        let between = String(code[onSite.upperBound..<latency.lowerBound])
        XCTAssertFalse(between.contains("return"), """
            A `return` now sits between the "monitor ON" breadcrumb and its latency line, so \
            every successful start logs the fact and never its cost. The pair is the \
            deliverable: "monitoring started" and "on THIS combination it costs N ms" are one \
            statement, and a founder log carrying only the first cannot answer whether the \
            take was monitorable.
            """)
    }

    // MARK: - helpers

    private static func count(of needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    private static func body(of key: String, in text: String) -> String? {
        guard text.components(separatedBy: key).count - 1 == 1,
              let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
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
        return nil
    }

    private static func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent("Sources").appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            struct Missing: Error, CustomStringConvertible {
                let p: String
                var description: String { "Sources/\(p) is missing — re-anchor this scan (#454)." }
            }
            throw Missing(p: relative)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
