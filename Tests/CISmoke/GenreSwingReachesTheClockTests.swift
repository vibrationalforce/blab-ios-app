// GenreSwingReachesTheClockTests.swift
// Echoel — #327. `MusicStyle.swing` was authored in GROOVE CYCLE 2 with per-genre values,
// and the ONE production caller of `PatternEngine.setSwing` passed a hardwired `0`. Every
// genre ran dead on the grid; the numbers existed, were tested, and reached nothing.
//
// ⭐ WHY A GUARD AND NOT JUST THE FIX. This defect is invisible from both ends. From the
// data side everything looks healthy — `MusicStyleSwingTests` asserts the values are sane
// and that jazz is the maximum, and it passes whether or not anyone reads them. From the
// call side the literal `0` carried a justification that sounded right ("no beat → nothing
// to swing"), so it read as a deliberate choice rather than a dropped wire. Nothing in
// between could fail. That gap is what this file closes.
//
// It fires on the two halves that must BOTH hold:
//   1. the generate path resolves swing from the style instead of a literal, and
//   2. the resolved value actually changes the clock — `swingGap` must not equal `base`
//      for a swung genre, and must equal it for a straight one.
//
// ⛔ HONEST LIMITS.
//   · Half 1 is a SOURCE SCAN. The call sits inside a SwiftUI view body, which no pure
//     assertion can reach and no simulator here can drive (house pattern —
//     `SoundPromptHasADoorTests`, `SoundPanelPresetBarTests`). It proves the argument is
//     written, not that the take audibly swings.
//   · It does NOT check the ordering of the genres' feel against each other, and it does
//     not know whether 0.16 is the right amount of shuffle for deep house. Whether the six
//     changed genres now sound better is the founder's ear (#254/#314), not a test's.
//   · Half 2 exercises `PatternEngine.swingGap`, the pure static both the per-tick re-arm
//     and the `setTempo` re-arm call. It is the real law, but it is not the audio.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreSwingReachesTheClockTests: XCTestCase {

    private static let generateSite = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - Half 1: the wire is connected

    /// Deliberately matches "not a literal" rather than one exact spelling, so a later
    /// refactor (a resolver function, a local `let`) stays green as long as the value still
    /// comes from the style — and a re-hardwired constant goes red however it is written.
    func testGenerateDoesNotHardwireTheSwingAmount() throws {
        let calls = try codeLines(Self.generateSite).filter { $0.contains("setSwing(") }

        XCTAssertFalse(calls.isEmpty, """
        no `setSwing(` call found in \(Self.generateSite). Either generate stopped setting \
        swing at all — in which case the engine keeps whatever the previous take left, which \
        is its own bug — or this scan's anchor rotted. Both need a human; a silent green here \
        would mean the guard scanned nothing.
        """)

        let hardwired = calls.filter { line in
            guard let open = line.range(of: "setSwing(") else { return false }
            let rest = line[open.upperBound...]
            guard let close = rest.firstIndex(of: ")") else { return false }
            let argument = rest[rest.startIndex..<close].trimmingCharacters(in: .whitespaces)
            // A numeric literal (0, 0.0, .25) is a hardwire. Anything naming something —
            // `style.swing`, a resolver call, a local — is not.
            return argument.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
                && !argument.isEmpty
        }

        XCTAssertTrue(hardwired.isEmpty, """
        `setSwing` is called with a numeric literal in \(Self.generateSite):
        \(hardwired.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        That is exactly #327: `MusicStyle.swing` carries per-genre values, they are unit-tested, \
        and a hardwired argument means none of them ever reaches the clock. The melody rides \
        this tick — "there are no drums to swing" is not a reason, because a note's onset is \
        decided by when the tick fires, not by what else is playing. Pass the style's value; \
        the ten straight genres already return 0 on their own.
        """)
    }

    // MARK: - Half 2: the value actually bends the clock

    /// The pure law, at the exact call the engine makes. A swung genre must lengthen the gap
    /// after an even step and shorten the one after an odd step — and the pair must still sum
    /// to `2 × base`, or swing would drift the tempo.
    func testASwungGenreBendsTheGridAndKeepsTheTempo() {
        let base = 0.125   // one 16th at 120 BPM
        let swung = MusicStyle.offered.filter { $0.swing > 0 }

        XCTAssertFalse(swung.isEmpty, """
        no offered genre has a non-zero swing. If the curation legitimately went all-straight, \
        delete this test with a note; until then this means the swing table lost its values, \
        and the fix in #327 protects nothing.
        """)

        for style in swung {
            let long = PatternEngine.swingGap(afterStep: 0, base: base, swing: style.swing)
            let short = PatternEngine.swingGap(afterStep: 1, base: base, swing: style.swing)

            XCTAssertGreaterThan(long, base, "\(style) should delay the off-beat 16th")
            XCTAssertLessThan(short, base, "\(style) should shorten the step after the off-beat")
            XCTAssertEqual(long + short, 2 * base, accuracy: 1e-12, """
            \(style)'s swung pair does not sum to 2× base — swing would then change the TEMPO, \
            not the feel, and every bar would drift against a slaved clock.
            """)
        }
    }

    /// The other half of the contract, and the one the old hardwire was pretending to protect:
    /// the meditative and ambient genres must stay dead straight on their own, without anyone
    /// forcing them to.
    func testTheContemplativeGenresStayStraightWithoutBeingForced() {
        let base = 0.125
        let straight = MusicStyle.offered.filter { $0.swing == 0 }

        XCTAssertGreaterThan(straight.count, 5, """
        only \(straight.count) offered genres are straight. The point of #327 is that the ten \
        calm genres never needed the hardwired 0 — if that majority disappears, the decision \
        to let the data speak deserves a fresh look.
        """)

        for style in straight {
            XCTAssertEqual(PatternEngine.swingGap(afterStep: 0, base: base, swing: style.swing),
                           base, accuracy: 1e-12,
                           "\(style) must run straight — a swung Fläche reads as a genre shuffle")
            XCTAssertEqual(PatternEngine.swingGap(afterStep: 1, base: base, swing: style.swing),
                           base, accuracy: 1e-12, "\(style) must run straight")
        }
    }

    // MARK: - Files

    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.stripComment(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Comment stripping is load-bearing: the block above the call site now DISCUSSES
    /// `setSwing(0)` at length, and without stripping the tombstone explaining the fix would
    /// itself fail the test it documents.
    private static func stripComment(_ line: String) -> String {
        var quotes = 0
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" { quotes += 1 }
            if ch == "/", previous == "/", quotes % 2 == 0 {
                return String(line[line.startIndex..<line.index(before: index)])
            }
            previous = ch
            index = line.index(after: index)
        }
        return line
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — the scanning half of this file reads \
            source text, so it SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }
}
