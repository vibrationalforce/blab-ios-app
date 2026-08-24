// TheLawFileCitesGuardsThatExistTests.swift
// Echoel — #800/#802. The always-loaded files name guard files by the dozen. Nothing
// checked that they exist.
//
// ⛔ THE COUNT LIVES IN ONE PLACE IN THIS FILE, AND #803 IS WHY. #802 widened the corpus
// from one file to four, which moved the count from 32 to 35 — and the number was written
// out FOUR times here. Three were updated and the fourth, in the grading block, still said
// "All 32 resolve" when it shipped. That is #416 applied to a count: two spellings of one
// fact is the defect whether or not they agree today, and this file argues against exactly
// that. Below, `citationsWhenWritten` is the only place a number appears; every sentence
// that needs it says so in words or interpolates the constant.
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
// WHAT IT READS. The ALWAYS-LOADED set — `CLAUDE.md` plus the three `.claude/rules/*.md`
// files — in two citation forms, because those are the two those files actually use:
//   · an explicit path  `Tests/CISmoke/<Name>.swift`  — must exist at exactly that path,
//     since the sentence around it tells a reader where to look;
//   · a backticked identifier  `` `<Name>Tests` ``   — must exist as `<Name>Tests.swift`
//     under EITHER bundle, because the KEY TESTS block cites the non-blocking suite
//     (`Tests/EchoelmusicTests/`) in exactly this form.
// Counted when written: see `citationsWhenWritten`. All of them resolved, on this tree and
// on the parent.
//
// ⛔ #800 READ `CLAUDE.md` ALONE, AND THAT WAS THE #787 GAP ONE LEVEL UP: the law file is
// not the only thing a session is charged for before its first line of work. #802 added
// the three rules files — `context.md` cites one guard by path, `swift-audio.md` two by
// backtick. All three resolved, so nothing was broken; what was missing was the check.
//
// ⛔ AND EXTENDING THE CORPUS EXPOSED A FALSE POSITIVE THAT #800 PASSED BY LUCK. Measuring
// the directory-scoped `Tests/CISmoke/CLAUDE.md` reported `EchoelmusicTests` unresolvable
// — correctly, because it is a build TARGET in `project.yml`, cited in exactly the
// backticks a test class uses. The rule "backticked, ends in Tests" cannot tell a suite
// from a bundle; it passed on the law file only because that file happens never to name
// one. Bundle names are now READ from `project.yml` and excluded. Directory-scoped
// `CLAUDE.md`s stay out of the corpus on principle — they load only inside their own
// tree, which is a different question, not a way around the false positive.
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
// ⚠️ GRADED HONESTLY (#464): PREVENTIVE. Every citation resolves on this tree AND on the
// parent — this catches nothing today and is booked as catching nothing. It is worth its bytes
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

    /// How many distinct citations the corpus carried when this guard was last measured.
    /// ⚠️ It is DOCUMENTATION, never an assertion: adding or removing a citation is
    /// ordinary work and must not turn this red (#364) — that is what `citationFloor`
    /// is for. It exists so the failure message can say what "normal" looked like
    /// without a second sentence repeating the number (#416).
    private static let citationsWhenWritten = 35

    /// The files every session is charged for before its first line of work: the law file
    /// plus the three always-loaded rule files. Directory-scoped `CLAUDE.md`s are NOT in
    /// here — they load only while working in their own tree, and one of them cites a build
    /// TARGET in the same backticks a test class uses, which is a different question.
    private static let alwaysLoaded = [
        "CLAUDE.md",
        ".claude/rules/context.md",
        ".claude/rules/engineering.md",
        ".claude/rules/swift-audio.md",
    ]

    /// Unit-test TARGET names, read from `project.yml` rather than listed here.
    static func unitTestTargets(in project: String) -> Set<String> {
        var found: Set<String> = []
        let lines = project.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            guard line.contains("type: bundle.unit-test"), index > 0 else { continue }
            let head = lines[index - 1].trimmingCharacters(in: .whitespaces)
            if head.hasSuffix(":") { found.insert(String(head.dropLast())) }
        }
        return found
    }

    func testEveryGuardTheAlwaysLoadedFilesNameResolvesToAFile() throws {
        let root = try repoRoot()
        var pathForm: [String] = []
        var tickForm: [String] = []
        var readFiles: [String] = []
        for rel in Self.alwaysLoaded {
            let url = root.appendingPathComponent(rel)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            readFiles.append(rel)
            scan(text, pattern: "Tests/CISmoke/", suffix: ".swift", into: &pathForm)
            scanBackticked(text, into: &tickForm)
        }
        XCTAssertEqual(readFiles.count, Self.alwaysLoaded.count, """
            Only \(readFiles.count) of \(Self.alwaysLoaded.count) always-loaded files were \
            readable: \(readFiles.joined(separator: ", ")).

            The set this guards is exactly the one every session pays for before its first \
            line of work (#454). If a rules file moved or was renamed, re-point this list in \
            the same commit — a shrinking corpus makes the assertions below pass on less.
            """)

        // Bundle names are read, never assumed: `EchoelmusicTests` is a TARGET in
        // project.yml, and `Tests/CISmoke/CLAUDE.md` cites it in backticks exactly as it
        // cites test classes. Measuring that file was what exposed the ambiguity — the rule
        // "backticked, ends in Tests" cannot tell a suite from a bundle, and it passed on
        // CLAUDE.md only because that file happens not to name a bundle. Passing by luck is
        // not passing.
        let targets = Self.unitTestTargets(in:
            (try? String(contentsOf: root.appendingPathComponent("project.yml"),
                         encoding: .utf8)) ?? "")
        tickForm.removeAll { targets.contains($0) }

        let all = Set(pathForm).union(tickForm)
        XCTAssertGreaterThanOrEqual(all.count, Self.citationFloor, """
            The always-loaded files cite only \(all.count) guard file(s) — the scan \
            expected at least \(Self.citationFloor) and found \(Self.citationsWhenWritten) \
            when it was written.

            A collapse like this means the corpus moved, not that the law file got tidy \
            (#454). Either a file moved out of the always-loaded set, or citations stopped \
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
