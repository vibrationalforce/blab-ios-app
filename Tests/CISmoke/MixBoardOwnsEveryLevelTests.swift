// MixBoardOwnsEveryLevelTests.swift
// Echoel — #330. The founder asked one question: "Alles Sound Ebenen übersichtlich zu
// mixen?" The honest answer was no — the generated take's roles were on the Mix board,
// while the Field (the layer you play with your HANDS) and the click sat two chips away,
// each with its own units and its own law. #330 puts every audible layer on one board.
//
// ⭐ WHAT THIS FILE ACTUALLY GUARDS, and it is NOT "the board is complete". Completeness
// is a judgement about the product; a test asserting "there are exactly four strips" would
// go red on the next honest addition and teach nothing. What it guards is the DEFECT that
// giving a value a second door reliably produces here:
//
//   A `@AppStorage` value whose engine fan-out lives in an `.onChange` has exactly ONE
//   working door. `.onChange` fires only in the view that declares it, so the moment a
//   second field binds the same storage, that field persists the number and leaves the
//   voice at its old gain. The number moves. The sound does not.
//
// This repo has shipped that bug twice — `subBass.mixLevel` (the Bass fader that did
// nothing) and the `resetToUnity` path that had to be taught to push the same two lines by
// hand. `mixerPanel`'s reset button still carries the warning. The fix is structural, not
// vigilance: the fan-out belongs INSIDE the binding's setter, where a new door cannot fail
// to inherit it.
//
// ⛔ HONEST LIMITS.
//   · This is a SOURCE SCAN. `touchSynth?.setGain` runs on a real voice inside a SwiftUI
//     view; no pure assertion here can reach it and there is no simulator in this lane
//     (house pattern — `SoundPromptHasADoorTests`, `NoDoorlessStudioViewsTests`).
//   · It proves the fan-out is WRITTEN into the one owner, not that the gain is audible.
//     Whether the Field now sits right against the take is the founder's ear.
//   · It says nothing about the Click strip: `MetronomeVoice` is an `@Observable` object,
//     so both doors mutate the same instance and the split this file guards cannot occur
//     there. Stated rather than silently omitted — a guard whose scope is guessed at is
//     the same defect as a green that was never earned.

import Foundation
import XCTest
@testable import Echoelmusic

final class MixBoardOwnsEveryLevelTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - The one owner exists and still fans out

    func testTheFieldLevelBindingWritesTheStoreAndTheVoice() throws {
        let body = try declarationBody(of: "fieldLevelBinding", in: try codeLines(Self.studio))

        XCTAssertFalse(body.isEmpty, """
        no `fieldLevelBinding` declaration found in \(Self.studio). Either it was renamed \
        (then rename it here in the same commit) or it was inlined back into the two views \
        — which is the regression this file exists for: two `.onChange`-carrying fields on \
        one `@AppStorage` key, only one of which reaches the voice.
        """)

        XCTAssertTrue(body.contains("touchLevel ="), """
        `fieldLevelBinding`'s setter no longer writes `touchLevel`. The field would then \
        move on screen and snap back on the next redraw, because nothing persisted it.
        """)

        XCTAssertTrue(body.contains("setGain"), """
        `fieldLevelBinding`'s setter no longer calls `setGain`. This is the exact failure \
        this binding was extracted to make impossible: the level persists, the Field keeps \
        playing at its old gain, and both doors look like they work. If the fan-out moved \
        somewhere else deliberately, move this assertion with it — do not delete it.
        """)
    }

    // MARK: - No door may bypass the owner

    /// The rule in one line: nothing binds `$touchLevel` directly any more. A bare
    /// `value: $touchLevel` is a door without the fan-out, whatever view it sits in.
    func testNoViewBindsTheRawTouchLevelStorage() throws {
        let offenders = try codeLines(Self.studio).filter { $0.contains("$touchLevel") }

        XCTAssertTrue(offenders.isEmpty, """
        \(Self.studio) binds `$touchLevel` directly:
        \(offenders.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        Use `fieldLevelBinding`. A raw binding writes the stored value without touching \
        `PolySynthVoice.setGain`, so the Field's level changes on screen and not in the \
        air — and because the OTHER door still works, the bug reads as "sometimes it \
        applies", which is the hardest kind to report.
        """)
    }

    // MARK: - Files

    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.stripComment(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The lines of a declaration, from its `var <name>` to the matching close brace.
    /// Brace-counted rather than line-counted so an added line inside cannot silently
    /// truncate the scan — a scanner that reads half a body reports a green it did not earn.
    private func declarationBody(of name: String, in code: [String]) throws -> String {
        guard let start = code.firstIndex(where: { $0.contains("var \(name)") }) else { return "" }
        var depth = 0
        var collected: [String] = []
        for line in code[start...] {
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0, collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    /// Comment stripping is load-bearing: the binding's own doc block discusses `$touchLevel`
    /// and `setGain` at length, so without it the explanation would satisfy the tests it
    /// documents — prose standing in for code, the substitution `NoDoorlessStudioViewsTests`
    /// was built to reject.
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
            source tree not present at \(sources.path) — this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }
}
