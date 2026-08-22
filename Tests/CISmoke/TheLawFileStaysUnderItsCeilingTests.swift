// TheLawFileStaysUnderItsCeilingTests.swift
// Echoel — #702, extended by #707 (§D) and corrected by #708. Blocking bundle: the other
// suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. `CLAUDE.md` is loaded before the first line of work in EVERY session,
// and `.claude/settings.json` sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "50"`, so compaction
// fires at half budget and the EXECUTABLE law — the audio-thread bans, the force-unwrap ban,
// `EchoelValueField`, the 3 Hz flash ceiling, the OSC address set — is the small share that
// gets summarised away FIRST. `scripts/doctor.py --section D` already WARNs past 150,000 B on
// that one file. A WARN is advisory and nothing reads it on a push; this is the same number
// with teeth.
//
// ⭐ WHY IT NEEDED TEETH, measured rather than assumed. #538 moved two count-provenance chains
// out of `CLAUDE.md` into `memory/LEDGER_COUNTS.md` for exactly this reason. Nine days later
// the `Tests/EchoelmusicTests/` block had re-filled: it SAID, in its own text, that the chain
// had been moved to the ledger — and carried three fresh ⛔ retractions underneath. #702 moved
// those to §C. The accretion was not carelessness; every one of those retractions was correct
// and worth keeping. That is the whole problem: adding a line to an accreting ledger is cheap
// for the session that writes it and charged to every session after.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364), AND CLAIM 2's MESSAGE IS THE POINT OF THE FILE. A red
// here does NOT mean "delete the paragraph you just wrote" and must never be read that way —
// #701 is the counter-example: it had a genuine register entry to add with 628 B of headroom,
// and skipping it would have been the wrong call. The repair is the one #538 and #702 both
// took: move PROVENANCE (how a number reached its value; which claim was retracted) to
// `memory/LEDGER_COUNTS.md`, and keep LAW (what a session must do) in `CLAUDE.md`. The ledger
// deletes nothing, so nothing is lost by moving.
//
// ⚠️ WHY IT READS BYTES AND NOT CHARACTERS. `.claude/rules/context.md` §2 records that this
// repo's prose carries hundreds of multi-byte marker glyphs (⛔ ⚠️ ⭐) plus German, and that a
// char claim needs Python. The doctor's threshold is on BYTES, and this guard has to test the
// same quantity the doctor prints or the two instruments disagree — the exact defect §D of
// that file already paid for, where a stated threshold did not test the quantity it named.
//
// ⚠️ HONEST LIMITS. 5 tests, 10 assertion statements (1+1+4+2+2; counted in Python over lines
// whose first token is XCTAssert). It measures SIZE, never quality: a file stuffed with 149 KB
// of nonsense passes. And it cannot see the rest of the always-loaded surface — the three
// `.claude/rules/*.md` files add ~13.7 KB that no assertion here bounds, deliberately, because
// the ceiling belongs on the ONE file that grows.
// ⛔ THAT FIGURE WAS WRITTEN "~12.8 KB" AND WENT STALE INSIDE ITS OWN COMMIT: the same commit
// then added 859 B to `context.md` (the #456 pull-along), so the number was wrong before it was
// ever pushed. Left visible rather than silently corrected, because it is this repo's most
// repeated defect in its smallest possible form — a measured number quoted one edit later.
// Re-derive: `for f in CLAUDE.md .claude/rules/*.md; do wc -c "$f"; done`.
//
// ⭐ GRADING (§3), restated for #708's parent because #707 edited this file and left #702's
// grading describing #702's parent — the block is required to describe THE parent of the commit
// that ships it, and a stale one is worse than none. Against `68625c1`: claims 1, 2, 4 and 5 are
// COUNTERWEIGHTS (green there too — `CLAUDE.md` was 146,984 B, under the ceiling; the hook never
// named the ledger; the witness was already split). Claim 3's four assertions are counterweights
// as well, §D included, because #707 created it one commit earlier. ZERO regressions and ZERO
// forwards this time; booking a counterweight as a forward is the flattering direction (#464).
// (For the record, #702's own grading was: 1/2/4 counterweights, 3 and 5 forward — §C and the
// moved text were created by THAT commit. #707's was: 3 counterweights + §D forward.)

import Foundation
import XCTest
@testable import Echoelmusic

final class TheLawFileStaysUnderItsCeilingTests: XCTestCase {

    /// The same number `scripts/doctor.py --section D` prints its WARN against.
    private static let ceilingBytes = 150_000

    // MARK: - 1: the anchor

    /// Without this, claim 2 passes trivially on a missing or truncated file (#454).
    func testTheLawFileIsPresentAndSubstantial() throws {
        let bytes = try byteCount("CLAUDE.md")
        XCTAssertGreaterThan(bytes, 50_000, """
            CLAUDE.md is \(bytes) B — far smaller than any state this repo has been in. \
            Either the file was truncated or this scan is reading the wrong path; a ceiling \
            test over a missing file is vacuous, so re-anchor rather than celebrating.
            """)
    }

    // MARK: - 2: THE CEILING

    /// ⭐ Read the message, not just the number.
    func testTheLawFileStaysUnderTheDoctorsCeiling() throws {
        let bytes = try byteCount("CLAUDE.md")
        XCTAssertLessThan(bytes, Self.ceilingBytes, """
            CLAUDE.md is \(bytes) B, past the \(Self.ceilingBytes) B ceiling that \
            `scripts/doctor.py --section D` WARNs at. THIS IS NOT "delete what you just \
            wrote" — #701 added a genuine register entry with 628 B of headroom and was \
            right to. The repair is the one #538 and #702 both took: move PROVENANCE (how a \
            number reached its value, which claim was retracted, which cycle paid for it) \
            into `memory/LEDGER_COUNTS.md`, and keep LAW (what a session must DO) here. The \
            ledger deletes nothing, so the move costs no knowledge. Largest paragraphs, to \
            start from: `python3 -c "for i,l in enumerate(open('CLAUDE.md',encoding='utf-8')): \
            print(len(l.encode()),i+1)" | sort -rn | head`.
            """)
    }

    // MARK: - 3: the ledger the repair depends on

    /// "Moved, not deleted" is only true while the destination exists and holds every chain
    /// that left this file. If one were gone, claim 2's message would be advising a deletion.
    /// ⛔ RENAMED FROM `…AllThreeChains` (#708, the #374 precedent): a count in a TEST NAME is
    /// the same stale-number defect this very commit deleted from `.claude/rules/context.md`,
    /// and #707 added §D in the same breath that left "three" standing. The name now says what
    /// it checks instead of how many, so the next move cannot age it.
    func testTheLedgerExistsAndHoldsEveryMovedChain() throws {
        let ledger = try rawFile("memory/LEDGER_COUNTS.md")
        XCTAssertTrue(ledger.contains("## A — `Tests/CISmoke/`"), """
            §A (the blocking bundle's chain, moved by #538) is gone from the ledger. Claim \
            2 tells a session to move provenance THERE — if the destination lost a section, \
            fix that before trusting this file's advice.
            """)
        XCTAssertTrue(ledger.contains("## B — `Sources/**/*.swift`"),
                      "§B (the Sources chain, #538) is gone — see the message above.")
        XCTAssertTrue(ledger.contains("## C — `Tests/EchoelmusicTests/`"), """
            §C (the non-blocking suite's chain, moved by #702) is gone. That is the chain \
            CLAUDE.md now POINTS at instead of carrying — a dangling pointer here means the \
            law file promises provenance that no longer exists.
            """)
        // ⚠️ #707 is the first section moved for HEADROOM rather than to fix an accretion:
        // CLAUDE.md stood 942 B under this file's own ceiling, and claim 2's message names
        // exactly this trade. It recovered 2,074 B ON THE FILE THIS GUARD TESTS and lost no
        // law. ⛔ Not the same as the always-loaded SURFACE, which recovered 2,027 B — the
        // same commit spent 47 B on `.claude/rules/context.md`. Naming the wrong quantity is
        // this file's own §D lesson (a threshold that does not test what it names), so both
        // numbers are stated rather than one (#708).
        XCTAssertTrue(ledger.contains("## D — `EchoelStudioView` Präsentations-Modifier"), """
            §D (the presentation-modifier chain, moved by #707) is gone. CLAUDE.md's \
            Presentation and CRAFT-TOOL-DOORS bullets both POINT at it instead of carrying \
            the history — same dangling-pointer failure as §C above.
            """)
    }

    // MARK: - 4: THE INVARIANT that makes the move worth anything

    /// ⚠️ The ledger is ~600 KB. `.claude/rules/context.md` says outright that it is not in
    /// the hook's `cat` list and must never be added to it — adding it would charge every
    /// session more than the entire law it was moved to protect.
    func testTheSessionStartHookNeverReadsTheLedger() throws {
        let settings = try rawFile(".claude/settings.json")
        XCTAssertFalse(settings.contains("LEDGER_COUNTS"), """
            The SessionStart hook now names `LEDGER_COUNTS.md`. That file is ~600 KB of pure \
            provenance; reading it every session spends more budget than all of CLAUDE.md's \
            law, and it defeats the entire point of #538 and #702. If a session needs a \
            count's history it opens the ledger BY HAND. Remove it from the hook, and \
            correct `.claude/rules/context.md`, which states this as an invariant.
            """)
        XCTAssertTrue(settings.contains("memory/project_knowledge.md"), """
            The hook's named `cat` list changed shape — claim 4 is a NEGATIVE over that \
            command, so it goes quietly vacuous if the list is gone. Re-anchor it.
            """)
    }

    // MARK: - 5: the #702 move actually happened, in both directions

    /// #472: grep AFTER moving. One retraction stands witness for the whole block — it is a
    /// literal filename that never existed, so it cannot be re-derived by accident.
    func testTheMovedProvenanceIsInTheLedgerAndNotInTheLawFile() throws {
        let witness = "MIDIFileExporterDrumTests"
        XCTAssertTrue(try rawFile("memory/LEDGER_COUNTS.md").contains(witness), """
            The #474 retraction (a cited test file that NEVER existed) is missing from the \
            ledger. #702 moved it out of CLAUDE.md on the promise that the ledger keeps \
            every line — if it is gone from both, a paid-for lesson was deleted, not moved.
            """)
        XCTAssertFalse(try rawFile("CLAUDE.md").contains(witness), """
            The moved provenance is back in CLAUDE.md. That is the re-accretion #702 exists \
            to stop — it is how the block re-filled in the nine days after #538. Point at \
            `memory/LEDGER_COUNTS.md` §C instead of re-quoting it.
            """)
    }

    // MARK: - file access

    private struct DiagAnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    /// ⚠️ BYTES, not characters — see the header. `.utf8.count` on the decoded string is the
    /// same quantity `wc -c` and the doctor report, so the two instruments cannot drift.
    private func byteCount(_ relativePath: String) throws -> Int {
        try rawFile(relativePath).utf8.count
    }

    private func rawFile(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
