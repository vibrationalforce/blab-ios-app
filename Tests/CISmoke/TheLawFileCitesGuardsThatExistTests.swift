// TheLawFileCitesGuardsThatExistTests.swift
// Echoel — #800. CLAUDE.md names 32 guard files. Nothing checked that they exist.
//
// ⭐ WHY THIS AND NOT ANOTHER STALE-NUMBER CHECK. This repo has paid for the pointer
// class twice already, and both times the pointer was prose while the target was code:
// #472 found `Core/PerTrackParameterKeyPath.swift` pointing at a line range that a
// previous slice had already invalidated, and #473 found five prose citations of a view
// the same commit deleted — one of them a guard that read the removed file through a
// `try` behind a directory-wide skip, which would have gone HARD RED on a correct tree.
// The lesson those wrote down is short: **a pointer is only as durable as its target.**
// `.claude/rules/context.md` §2 states the executable half ("write the command next to
// any number you record"), and #474 extended it from numbers to NAMES — "ein Name ist
// genauso ein `git ls-files` wert wie eine Zahl". Nothing enforced that extension.
//
// WHAT IT READS. `CLAUDE.md` only, in two citation forms, because those are the two the
// file actually uses:
//   · an explicit path  `Tests/CISmoke/<Name>.swift`  — 16 today, must exist at exactly
//     that path, since the sentence around it tells a reader where to look;
//   · a backticked identifier  `` `<Name>Tests` ``   — 17 today, must exist as
//     `<Name>Tests.swift` under EITHER bundle, because the KEY TESTS block cites the
//     non-blocking suite (`Tests/EchoelmusicTests/`) in exactly this form.
// The two overlap by one, so 32 distinct names. All 32 resolve on this tree.
//
// ⛔ WHY NOT A BROADER SCAN, measured before it was written rather than assumed. A bare
// `\b[A-Z][A-Za-z0-9_]*Tests\b` sweep is the obvious "stronger" version and it is WRONG
// here for the #491 reason: CLAUDE.md quotes retracted and superseded names ON PURPOSE,
// inside its ⛔ blocks, so a broad scan would demand that the repo keep every name the
// law file ever withdrew. Backticks and explicit paths are how the file marks a LIVE
// citation; the ⛔ prose around a withdrawn one does not use them. Narrow and honest
// beats broad and disarmed — the same trade `WebsitePagesAreFindableAndHonestTests`
// spells out for the word "streaming".
//
// ⚠️ GRADED HONESTLY (#464): PREVENTIVE. All 32 resolve on this tree AND on the parent —
// this catches nothing today and is booked as catching nothing. It is worth its bytes
// because the failure it prevents is silent: a renamed guard leaves the prose pointing
// at a file that no longer exists, and the next session follows the pointer, finds
// nothing, and cannot tell "renamed" from "deleted" from "never existed".
//
// ⚠️ IT DOES NOT FORBID RENAMING A GUARD (#364). Renaming is ordinary work; the law is
// #456 — the citation moves in the SAME commit. That is exactly what this turns from a
// habit into a check, and the failure message says so instead of leaving it to be
// rediscovered.
//
// ⚠️ WHAT IT CANNOT DO. It proves a NAME resolves to a file, never that the file still
// contains the claim the prose attributes to it. A guard gutted to `XCTAssertTrue(true)`
// under an unchanged name passes here. That deeper question has no cheap mechanical
// form, and pretending otherwise would be the decoration this file argues against.
import XCTest

final class TheLawFileCitesGuardsThatExistTests: XCTestCase {

    /// #454 — a citation count of zero means the scan lost its corpus, not that the file
    /// is clean. Anchored as a floor rather than an equality: adding a guard citation is
    /// ordinary work and must not turn this red, while a drop to zero can only mean the
    /// law file moved or the citation style changed wholesale.
    private static let citationFloor = 20

    func testEveryGuardCLAUDEmdNamesResolvesToAFile() throws {
        let root = try repoRoot()
        let law = try String(contentsOf: root.appendingPathComponent("CLAUDE.md"),
                             encoding: .utf8)

        var pathForm: [String] = []
        var tickForm: [String] = []
        scan(law, pattern: "Tests/CISmoke/", suffix: ".swift", into: &pathForm)
        scanBackticked(law, into: &tickForm)

        let all = Set(pathForm).union(tickForm)
        XCTAssertGreaterThanOrEqual(all.count, Self.citationFloor, """
            CLAUDE.md cites only \(all.count) guard file(s) — the scan expected at least \
            \(Self.citationFloor) and found 32 when it was written.

            A collapse like this means the corpus moved, not that the law file got tidy \
            (#454). Either the file is no longer at `CLAUDE.md`, or citations stopped \
            using the two forms this reads: an explicit `Tests/CISmoke/<Name>.swift` path, \
            or a backticked `<Name>Tests`. Re-point the scan in the same commit.
            """)

        var missing: [String] = []
        for name in pathForm.sorted()
        where !FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Tests/CISmoke/\(name).swift").path) {
            missing.append("Tests/CISmoke/\(name).swift")
        }
        for name in tickForm.sorted() where !resolves(name, under: root) {
            missing.append("`\(name)` (neither bundle)")
        }

        XCTAssertTrue(missing.isEmpty, """
            CLAUDE.md points at guard file(s) that do not exist: \
            \(missing.joined(separator: ", ")).

            This is NOT a ban on renaming or deleting a guard — both are ordinary work. \
            It is the #456 law made executable: the citation moves in the SAME commit as \
            the file. A dangling pointer is worse than no pointer, because the next \
            session cannot tell "renamed" from "deleted" from "never existed", and \
            CLAUDE.md is the one file every session reads before anything else.

            If the guard was deliberately removed, remove its sentence too — or rewrite \
            the sentence to say what replaced it, the way the register does elsewhere.
            """)
    }

    // MARK: - scanning

    /// Collects `<prefix><Name><suffix>` occurrences, returning just the `<Name>` part.
    private func scan(_ text: String, pattern prefix: String, suffix: String,
                      into out: inout [String]) {
        var search = text.startIndex..<text.endIndex
        while let hit = text.range(of: prefix, range: search) {
            let rest = text[hit.upperBound...]
            if let end = rest.range(of: suffix) {
                let name = String(rest[..<end.lowerBound])
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    out.append(name)
                }
            }
            search = hit.upperBound..<text.endIndex
        }
    }

    /// Collects backticked identifiers ending in `Tests`. The closing backtick has to
    /// follow immediately — a dotted method reference (`SomeTests.testFoo`) is a citation
    /// of a METHOD and is deliberately out of scope, since the file it lives in is
    /// already covered by whichever sentence names the file.
    private func scanBackticked(_ text: String, into out: inout [String]) {
        for chunk in text.components(separatedBy: "`").enumerated()
        where chunk.offset % 2 == 1 {
            let name = chunk.element
            guard name.hasSuffix("Tests"), name.count > 5,
                  let first = name.first, first.isUppercase,
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { continue }
            out.append(name)
        }
    }

    private func resolves(_ name: String, under root: URL) -> Bool {
        for bundle in ["Tests/CISmoke", "Tests/EchoelmusicTests"] {
            let p = root.appendingPathComponent("\(bundle)/\(name).swift").path
            if FileManager.default.fileExists(atPath: p) { return true }
        }
        return false
    }

    // MARK: - file access

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath:
                dir.appendingPathComponent("CLAUDE.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(domain: "TheLawFileCitesGuardsThatExist", code: 1, userInfo: [
            NSLocalizedDescriptionKey:
                "could not find the repo root from \(#filePath) — the guard read nothing"
        ])
    }
}
