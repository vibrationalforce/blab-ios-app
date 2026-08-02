// ReSeedIntervalIsMeasuredBeforeItIsResetTests.swift
// Echoel — the `sinceLast=` a device log prints must be the interval, not zero. BLOCKING. #390.
//
// WHY THIS EXISTS AT ALL, given that a breadcrumb is "only" diagnostics. `generate(…)` both
// READS `lastSeedAt` (to say how long ago the last re-seed was) and WRITES it (the anti-flood
// floor for the next automatic one). Those two lines are three lines apart and there is
// nothing in the language stopping a future edit from reordering them — a `lastSeedAt = Date()`
// hoisted to the top of the function for tidiness reads as harmless and is not.
//
// ⛔ AND THE FAILURE MODE IS THE BAD ONE. A dropped field prints nothing and I notice. A
// reordered one prints `sinceLast=0.0s` on every single generate — a plausible number, in a
// line I read as evidence, that says the founder re-seeded seven times in the same instant.
// This repo has already paid for exactly that shape once: #306, where I diagnosed a re-rolled
// bass mix from a breadcrumb whose LABEL was honest but whose meaning was not, and was wrong
// in public. A wrong number costs more than a missing one, so the ORDER is the invariant, not
// the string.
//
// ⚠️ WHY A SOURCE SCAN. `generate(…)` is `private` on a `@MainActor` SwiftUI `View` with the
// whole engine graph as its dependencies, and there is no local toolchain to stand one up.
// House pattern (`BioFXReachesEveryChainTests`, `ActiveTargetsIsAPerEditFactTests`,
// `SoundPanelReflowsTests`). It proves the order is WRITTEN; it cannot run the function.
//
// THE NEEDLE IS POSITIONAL, NOT A `contains`. The check is not "a read exists somewhere" —
// that passes with the write above it, which is the entire defect. It is: among every line in
// `generate(…)` that mentions `lastSeedAt`, the FIRST one must be the read. Nothing can be
// inserted above it, because anything inserted above it becomes the first.

import Foundation
import XCTest

final class ReSeedIntervalIsMeasuredBeforeItIsResetTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⭐ THE GUARD. The measurement must come before the reset.
    func testTheIntervalIsReadBeforeTheFloorIsOverwritten() throws {
        let body = try memberBody(startingWith: "private func generate(", in: Self.view)
        let mentions = body.filter { $0.contains("lastSeedAt") }
        XCTAssertGreaterThanOrEqual(mentions.count, 2, """
            `generate(…)` no longer both reads and writes `lastSeedAt` — found \
            \(mentions.count) mention(s):
            \(mentions.map { $0.trimmingCharacters(in: .whitespaces) })

            If the anti-flood floor moved somewhere else, move this guard with it. Do not \
            delete it: the breadcrumb's `sinceLast=` is only true while the read happens first.
            """)
        XCTAssertTrue(mentions[0].contains("== .distantPast"), """
            the FIRST thing `generate(…)` does with `lastSeedAt` is no longer to MEASURE \
            against it — this line is now first:
            \(mentions[0].trimmingCharacters(in: .whitespaces))

            If a write reached it first, `sinceLast=` prints 0.0s on every generate. That is \
            not a missing field, it is a plausible wrong number in a line read as evidence \
            (the #306 lesson). Put the `lastSeedAt == .distantPast` capture back on top.
            """)
    }

    /// The value has to survive the trip to the breadcrumb. A capture that nothing prints is
    /// dead code the compiler will warn about; a breadcrumb that prints something ELSE under
    /// the name `sinceLast` is the #306 shape again, so both ends are named here.
    func testTheCapturedIntervalIsWhatTheBreadcrumbPrints() throws {
        let body = try memberBody(startingWith: "private func generate(", in: Self.view)
        XCTAssertTrue(body.contains(where: { $0.contains("sinceLastSeed.map") }), """
            nothing in `generate(…)` formats `sinceLastSeed` any more — the interval is \
            measured and then dropped.
            """)
        guard let crumb = body.first(where: { $0.contains("EchoelCrashLog.breadcrumb") }) else {
            return XCTFail("`generate(…)` no longer emits a breadcrumb at all.")
        }
        XCTAssertTrue(crumb.contains("sinceLast=\\(sinceText)"), """
            the breadcrumb's `sinceLast=` no longer prints the value derived from \
            `sinceLastSeed`:
            \(crumb.trimmingCharacters(in: .whitespaces))
            """)
    }

    /// ⛔ THE THREE FIELDS THE FOUNDER REPORT NEEDED, named individually. "It sounds very
    /// unharmonic" (v10.79.366, log 2483) could not be answered because the log named no
    /// pitch, no scale and no tone system. `tuning=` is the load-bearing one: the #312 sub-bass
    /// retune is bit-identical under 12-TET, so a take that sounds wrong WITH `tuning=edo12`
    /// rules it out in one glance and a non-12-TET id makes it the first thing to test.
    func testTheBreadcrumbNamesTheHarmonicFrame() throws {
        let body = try memberBody(startingWith: "private func generate(", in: Self.view)
        guard let crumb = body.first(where: { $0.contains("EchoelCrashLog.breadcrumb") }) else {
            return XCTFail("`generate(…)` no longer emits a breadcrumb at all.")
        }
        for field in ["key=", "tuning=", "a4="] {
            XCTAssertTrue(crumb.contains(field), """
                the generate breadcrumb no longer prints `\(field)`:
                \(crumb.trimmingCharacters(in: .whitespaces))

                Removing one of these puts the next "it sounds wrong" report back where the \
                v10.79.366 one was: twenty-seven rPPG lines and not one naming a pitch.
                """)
        }
    }

    // MARK: - Source helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here: the ⭐ block above the
    /// breadcrumb explains `lastSeedAt` and `sinceLastSeed` in prose, and a scan that read it
    /// would find the "first mention" inside a comment instead of in the code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
