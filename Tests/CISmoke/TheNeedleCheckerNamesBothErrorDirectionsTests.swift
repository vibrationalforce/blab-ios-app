// TheNeedleCheckerNamesBothErrorDirectionsTests.swift
// Echoel — #809: the write-time check for a RUNTIME `.contains` needle, and the claim it
// made about itself that its own selftest disproved.
//
// WHY THE TOOL EXISTS. #808 found a needle that had never matched: the test asserted
// `autoModeHint(...).contains("your body")` against a sentence reading "toward your measured
// **body state**". It shipped in the same commit as the sentence (`7e906cd`, #648) and stayed
// red for two months, invisible because the CI job log carries only `tail -200 test.log`
// (#807). A SCAN needle is self-verifying — whoever writes it greps. A RUNTIME needle is not,
// because this repo has no local Swift toolchain. `scripts/needle-reachability.py` closes that
// gap without a compiler by asking whether the literal occurs in the source of the function
// the needle calls.
//
// ⛔ WHAT THIS FILE ACTUALLY GUARDS IS A RETRACTION. The tool's first docstring said "every
// miss it cannot see is a FALSE GREEN, never a false alarm" — the reassuring direction, and
// backwards. The mechanism runs the other way: **incomplete resolution reports a needle that
// works** (two hops, interpolation, a string built from an array), because the literal is
// simply missing from what the script can reach. False GREENS come from the opposite failure,
// over-broad resolution — a literal in a comment, in a branch the needle's state never takes,
// or in a same-named function elsewhere. Selftest case 5 is what disproved the sentence, one
// minute after it was written. **A tool that describes its own error direction wrongly is
// worse than one that says nothing**: a session reads a finding as proof, or dismisses one as
// "the known safe direction". Both readings are wrong in opposite ways.
//
// ⚠️ #665 IS THE REASON THE CLAIM MATTERS, not a reason to hide it. A checker with false
// alarms is a checker nobody reads — so the false-alarm direction has to be documented at the
// tool, where the person staring at a finding is standing. Today it reports **zero** findings
// across the whole bundle; the direction is theory until the day it is not.
//
// KIND (§1): **PREVENTIVE, source-text scans.** No claim here drives Python. They pin that the
// tool carries its origin, both error directions, and the pinned false-alarm case, and that
// the directory law points a session at it. Grading is honest about that: none of these would
// have caught #808 — the TOOL would have, and these keep the tool honest about itself.
//
// ⛔ ONE CLAIM WAS CUT DURING THE DRIVE, and it is the finding worth carrying. A sixth
// assertion banned the retracted sentence itself (`XCTAssertFalse(src.contains("never a false
// alarm"))`). The checker's docstring QUOTES that sentence in order to withdraw it, so the
// needle matched its own retraction and the CONTROL tree came back red — #491, in a file
// written by someone who had just read #491. Driving found it in one run; re-reading would
// not have. The note sits at claim 2 where a reader stands.
//
// ⚠️ #364 — THIS FORBIDS NO FUTURE WORK. Raising the hop depth is a legitimate change; it
// trades false alarms for false greens. Claim 3 goes red when case 5's expectation flips, and
// its message names the docstring paragraph that has to move in the same commit.

import XCTest

final class TheNeedleCheckerNamesBothErrorDirectionsTests: XCTestCase {

    private static let checker = "scripts/needle-reachability.py"
    private static let dirLaw = "Tests/CISmoke/CLAUDE.md"

    private func root() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relative) not in this tree — nothing to grade (#454: missing TREE skips).")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 0 · the tool exists at all

    /// A guard whose every claim degrades to a skip has no failure mode (#739). `text(_:)`
    /// skips on a partial checkout, which is right; one claim must treat absence as absence.
    func testTheNeedleCheckerIsStillInTheRepository() {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root().appendingPathComponent(Self.checker).path), """
            `\(Self.checker)` is gone. It is the only thing in this repo that can tell a
            session, BEFORE a push, that a runtime `.contains` needle can never match — the
            #808 class, which cost two months of a red gate nobody could see. If it was
            replaced, point this claim and the directory law at the replacement in the same
            commit; if it was deleted on purpose, this test goes with it and #808's lesson
            needs a new home.
            """)
    }

    // MARK: - 1 · it carries its origin and the two blind spots it HANDLES

    func testTheCheckerRecordsWhyItExistsAndWhatItResolves() throws {
        let src = try text(Self.checker)
        XCTAssertTrue(src.contains("#808"), """
            The checker lost its origin. Without "#808" a reader cannot find the failure that
            justifies the tool, and a tool without a paid-for failure behind it is the kind
            this repo deletes.
            """)
        for handled in ["CONCATENATION SEAM", "HELPER HOP"] {
            XCTAssertTrue(src.contains(handled), """
                The checker stopped naming the blind spot "\(handled)", which it HANDLES. Both
                were found the only way that counts: the first version reported exactly two
                findings and both were these. A reader who does not know they are handled will
                re-discover them as bugs.
                """)
        }
    }

    // MARK: - 2 · the retraction: BOTH error directions, named

    func testTheCheckerNamesBothErrorDirections() throws {
        let src = try text(Self.checker)
        for direction in ["FALSE ALARMS", "FALSE GREENS"] {
            XCTAssertTrue(src.contains(direction), """
                The checker names only one error direction again. Its first docstring claimed
                "never a false alarm" and its own selftest disproved that within the minute:
                incomplete resolution REPORTS a working needle. A tool that states its error
                direction wrongly makes a session either obey a false alarm or dismiss a real
                finding. Both directions, or the sentence is not honest.
                """)
        }
        // ⛔ A SECOND ASSERTION STOOD HERE FOR ONE DRIVE AND WAS THE #491 TRAP EXACTLY.
        // It was `XCTAssertFalse(src.contains("never a false alarm"))` — banning the retracted
        // sentence. The checker's docstring QUOTES that sentence in order to retract it, so the
        // needle matched its own retraction and the CONTROL tree came back red. Driving the
        // claim is what found it; reading it back would not have. **A negative scan over prose
        // that deliberately cites what it withdraws cannot distinguish the claim from its
        // retraction.** The positive assertions above carry the law on their own: if either
        // direction disappears, this claim goes red.
    }

    // MARK: - 3 · the pinned false-alarm case

    func testTheTwoHopFalseAlarmStaysPinned() throws {
        let src = try text(Self.checker)
        XCTAssertTrue(src.contains("two hops"), """
            Selftest case 5 is gone. It is the case that disproved the docstring, and it is
            pinned rather than fixed so the depth-1 limit cannot be forgotten. If the hop depth
            was raised, this expectation flips from reporting to not reporting — update this
            claim AND the "Hop depth is 1 on purpose" paragraph in the checker's docstring in
            the SAME commit (#456). Raising the depth is allowed; losing the record is not.
            """)
    }

    // MARK: - 4 · a session is pointed at it

    func testTheDirectoryLawPointsAtTheChecker() throws {
        let law = try text(Self.dirLaw)
        XCTAssertTrue(law.contains("needle-reachability"), """
            The directory law stopped naming the checker. A tool nobody is told to run is the
            #665 failure in its quiet form — not a checker with false alarms, a checker with no
            readers. §4 of `.claude/rules/context.md` bans hand-rolled needles precisely
            because the tooling is supposed to be named where a session looks.
            """)
    }
}
