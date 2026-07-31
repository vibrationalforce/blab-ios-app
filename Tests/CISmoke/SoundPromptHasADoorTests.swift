// SoundPromptHasADoorTests.swift
// Echoel — #320. `SoundPrompt` is a finished, tested "word → sound" mapper. For a month it
// had ZERO production callers, and its own file header said "the editor calls `apply` and
// offers `suggestions`" in the present tense.
//
// ⭐ WHY THAT SENTENCE IS THE DEFECT AND NOT JUST A STALE COMMENT. A door that ROTS leaves a
// grep trail: the caller is in the history, the removal is in a commit. This one was never
// written — the obvious suspect, `PatchEditorView`, contains zero occurrences of "prompt" at
// its last revision (`git show 8d31c21^:Sources/Echoelmusic/Studio/PatchEditorView.swift`).
// So every session that opened `SoundPrompt.swift` read a wired capability and moved on. That
// is how a finished feature stays invisible for a month with nothing failing anywhere.
//
// This file makes the header's claim CHECKABLE: the door must exist, and the file must name
// the file that holds it.
//
// ⛔ HONEST LIMITS. Two of these three tests are SOURCE SCANS — they prove the call is written,
// not that the row renders or that a tap reaches it. (`promptRow` is `private` inside a `body`;
// `@testable import` grants `internal`, and there is no simulator here. House pattern —
// `SoundPanelPresetBarTests`, `SoundPanelReflowsTests`, `FieldSurvivesAHiddenPictureTests`.)
// The third one is real behaviour and needs no scan. None of them can say whether "very warm
// lush pad" SOUNDS warm — that ear is the founder's.

import Foundation
import XCTest
@testable import Echoelmusic

final class SoundPromptHasADoorTests: XCTestCase {

    private static let core = "Sources/Echoelmusic/DSP/SoundPrompt.swift"

    /// The call every door must make. Anything that merely mentions the type in prose is
    /// stripped before matching, so a comment can never stand in for a caller — which is the
    /// exact substitution that produced #320.
    private static let callMarker = "SoundPrompt."

    // MARK: - The door exists

    /// ⭐ THE HEADLINE, and deliberately NOT anchored to a file name: any production file may
    /// own the door. A future move of the row into its own view must keep this green on its
    /// own, and it is the NEXT test that then forces the header to follow.
    func testSoundPromptHasAProductionCaller() throws {
        let callers = try callerFiles()
        XCTAssertFalse(callers.isEmpty, """
        nothing in Sources/ calls `SoundPrompt` any more (outside its own file).

        That is the #320 state exactly: a complete, unit-tested word→sound mapper that no \
        player can reach, sitting behind a header that describes a caller. If the door was \
        removed on purpose, delete this test and rewrite `SoundPrompt.swift`'s header to say \
        the capability is parked — do not leave the header claiming an editor that calls it.
        """)
    }

    /// The header must name the file that actually holds the door. Derived from the header
    /// itself rather than hard-coded, so moving the row and updating the doc stays green while
    /// moving the row alone goes red — which is the only failure worth having here.
    func testTheHeaderNamesTheFileThatReallyCallsIt() throws {
        let (type, member) = try doorClaim()
        let callers = try callerFiles()
        let named = callers.first { $0.hasSuffix("/\(type).swift") }
        XCTAssertNotNil(named, """
        `SoundPrompt.swift`'s header claims the door lives in `\(type).\(member)`, but \
        `\(type).swift` is not among the files that call it:
        \(callers.joined(separator: "\n"))

        One of the two is wrong. If the row moved, move the ⭐ THE DOOR line with it in the \
        same commit — a header naming a caller that does not call is the whole reason this \
        file exists.
        """)

        guard let file = named else { return }
        let lines = try codeLines(file)
        XCTAssertTrue(lines.contains { $0.contains("var \(member)") }, """
        `\(file)` calls `SoundPrompt` but declares no `\(member)`, which the header names as \
        the door.

        Either the row was renamed (update the header) or the call moved somewhere else in the \
        file (name that instead). The point of the claim is that a reader can find the door \
        from the core file in one hop.
        """)
        // "Placed" here means the name stands ALONE on a line, which in this codebase is how a
        // `some View` member enters a parent `ViewBuilder` (`presetRow`, `randomizeButton`, and
        // now `promptRow`). Deliberately narrower than "appears anywhere": the declaration line
        // contains the name too, so a looser match would pass on a declared-but-unused row.
        XCTAssertTrue(lines.contains { $0.trimmingCharacters(in: .whitespaces) == member }, """
        `\(member)` is declared in \(file) but never placed into a parent view — the name \
        appears on no line of its own.

        A declared-but-unplaced row is precisely a doorless capability with extra steps: the \
        call to `SoundPrompt` compiles, the guard above passes, and no player ever sees it. If \
        the row is composed differently now (inside a container expression), widen this check \
        rather than deleting it.
        """)
    }

    // MARK: - What the door offers must do something

    /// ⭐ REAL BEHAVIOUR, NOT A SCAN — and the one lying-control risk this row actually carries.
    /// The chips are `SoundPrompt.suggestions` verbatim, and `apply` silently ignores every word
    /// outside its vocabulary. Four of the eight shipped phrases already contain such a word
    /// ("pluck", "lead", "bell", "cinematic") — harmless while the rest of the phrase still
    /// shapes the patch, and exactly why the row prints what it RECOGNISED. A phrase where
    /// NOTHING resolves would be a chip that does nothing at all when tapped, with no error and
    /// no visible change: the failure mode this repo files as a lying control.
    func testEverySuggestionChipShapesTheSound() {
        XCTAssertFalse(SoundPrompt.suggestions.isEmpty, """
        `SoundPrompt.suggestions` is empty, so the row renders no chips and this test proves \
        nothing. If the chips moved to another source, point this test at it.
        """)
        for phrase in SoundPrompt.suggestions {
            let terms = SoundPrompt.recognizedTerms(in: phrase)
            XCTAssertFalse(terms.isEmpty, """
            the suggestion chip "\(phrase)" contains no word `SoundPrompt` understands, so \
            tapping it applies nothing at all — a control that visibly does nothing.

            Either add the word to `vocabulary` and give it a `shape(...)` case, or reword the \
            chip. Words are dropped silently by design (an unknown word must never garble a \
            patch), which is what makes a fully-unknown phrase invisible without this test.
            """)
        }
    }

    // MARK: - Source access

    /// Files under `Sources/` that call `SoundPrompt`, excluding its own file. Comments are
    /// stripped first: a prose mention is what #320 mistook for a caller.
    private func callerFiles() throws -> [String] {
        var out: [String] = []
        for path in try swiftSourcePaths() where path != Self.core {
            if try codeLines(path).contains(where: { $0.contains(Self.callMarker) }) { out.append(path) }
        }
        return out.sorted()
    }

    /// The `Type.member` the header's ⭐ THE DOOR line claims, read out of the RAW text (the
    /// claim is a comment, so `codeLines` would strip exactly what is being checked).
    private func doorClaim() throws -> (type: String, member: String) {
        let header = try rawLines(Self.core)
        guard let line = header.first(where: { $0.contains("THE DOOR") }) else {
            XCTFail("""
            `SoundPrompt.swift` no longer carries a "⭐ THE DOOR" line naming its caller.

            That line is the checkable half of the header. Without it the file is back to \
            describing a door in prose that nothing verifies — the #320 state.
            """)
            throw XCTSkip("no door claim")
        }
        // The first backtick-quoted `Type.member` after the marker.
        let after = line[(line.range(of: "THE DOOR")?.upperBound ?? line.startIndex)...]
        guard let open = after.firstIndex(of: "`"),
              let close = after[after.index(after: open)...].firstIndex(of: "`") else {
            XCTFail("the \"THE DOOR\" line names no `Type.member` in backticks: \(line)")
            throw XCTSkip("unparseable door claim")
        }
        let parts = after[after.index(after: open)..<close].split(separator: ".")
        guard parts.count == 2 else {
            XCTFail("expected `Type.member` in the door claim, found: \(after[after.index(after: open)..<close])")
            throw XCTSkip("unparseable door claim")
        }
        return (String(parts[0]), String(parts[1]))
    }

    /// Every Swift file under `Sources/`, repo-relative.
    private func swiftSourcePaths() throws -> [String] {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("cannot enumerate \(sources.path)")
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var out: [String] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            out.append(url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path)
        }
        XCTAssertFalse(out.isEmpty, "no Swift source found — a green here would be meaningless")
        return out.sorted()
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
            source tree not present at \(sources.path) — the scanning half of this file reads \
            source text, so it SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }

    private func rawLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Every non-empty line of `path` with comments removed — whole-line AND trailing. The
    /// quote-parity check approximates "is this `//` inside a string literal"; a wrong cut can
    /// only ever REMOVE text, i.e. cost a match, never invent one.
    private func codeLines(_ path: String) throws -> [String] {
        try rawLines(path)
            .map { Self.stripComment($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

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
}
