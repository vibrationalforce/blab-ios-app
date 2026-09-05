import XCTest
@testable import Echoelmusic

/// #1001 — `Category` sorts the genres; `offered` is the roster.
///
/// WHY IT EXISTS. The doc block over `MusicStyle.Category` said "Every genre is now offered".
/// Measured on the day it was struck: **36 cases, 19 offered** — rock 0 of 5 (the family and its
/// header vanish from the picker), acoustic 1 of 6. A session that trusts the sentence adds a
/// case to the enum, watches it land in a category branch, and ships a genre no picker can reach.
/// That is a whole cycle spent on a door that was never opened.
///
/// ⚠️ THE CURATION IS NOT THE DEFECT. Seventeen finished, patched, distinct genres are dark on
/// purpose — a founder ear-call. This guard does NOT push toward widening the roster (#364); it
/// only refuses to let the FILE claim a roster it does not have.
///
/// ⚠️ THE NEEDLE CANNOT BE THE BARE PHRASE, and that is the whole design of claim 1. The struck
/// clause is quoted in its own retraction, so a plain "this phrase is absent" scan would fail on
/// a correct file — the #491 trap, in a source file this time. So the claim allows the phrase
/// only on a line that also marks it as struck.
///
/// ⚠️ HONEST GRADING. Three claims, transcribed against both trees. 1 and 2 are load-bearing
/// (red on `HEAD`, where the clause still stands as a claim and nothing names `offered` as the
/// roster). 3 is a COUNTERWEIGHT, green on both trees: it pins the arithmetic the prose rests on,
/// so the day somebody genuinely offers every genre it goes red and names the comment to rewrite
/// in that same commit — which is the outcome this guard wants, not one it forbids.
final class TheOfferedRosterIsTheRosterTests: XCTestCase {

    private static let file = "Sources/Echoelmusic/Sequencer/MusicStyle.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — LOAD-BEARING: the struck clause may be quoted, never asserted.
    func testTheEveryGenreClaimSurvivesOnlyAsARetraction() throws {
        let text = try source(Self.file)
        let phrase = "Every genre is now offered"
        for line in text.components(separatedBy: "\n") where line.contains(phrase) {
            XCTAssertTrue(line.contains("STRUCK"), """
                "\(phrase)" appears in \(Self.file) as a CLAIM rather than as a retraction:

                \(line.trimmingCharacters(in: .whitespaces))

                Measured when it was struck: 36 cases, 19 offered — rock 0 of 5, acoustic 1 of \
                6. A session that believes this sentence adds an enum case, sees it sorted into \
                a category, and ships a genre the picker cannot reach.

                If the roster really has been widened, that is welcome — say so in words that \
                are true, and move claim 3's arithmetic with it in the same commit.
                """)
        }
    }

    // 2 — LOAD-BEARING: the reader is pointed at the array that actually decides.
    func testTheDocNamesTheRealRoster() throws {
        let text = try source(Self.file)
        XCTAssertTrue(text.contains("the\n    /// ROSTER is `offered`") || text.contains("ROSTER is `offered`"), """
            The `Category` doc block no longer tells the reader that `offered` is the roster \
            and `Category` is only the sorting. Without that sentence the file states the \
            grouping loudly and the gate not at all, which is how the struck clause survived \
            for months: nothing contradicted it in the place a reader looks.
            """)
    }

    // 3 — COUNTERWEIGHT: the arithmetic the prose rests on, pinned.
    func testTheRosterIsStillNarrowerThanTheEnum() {
        let offered = Set(MusicStyle.offered)
        let all = Set(MusicStyle.allCases)
        XCTAssertLessThan(offered.count, all.count, """
            `MusicStyle.offered` now covers every case. That is a legitimate founder decision \
            and this guard does not forbid it (#364) — but the prose above `Category` describes \
            a NARROWED roster with per-family counts, and it becomes false the moment this \
            passes. Rewrite that doc block in the same commit, then relax this claim.
            """)
        XCTAssertTrue(offered.isSubset(of: all), """
            `offered` names a genre the enum does not — impossible by construction today, and \
            worth failing loudly if it ever becomes possible.
            """)
    }
}
