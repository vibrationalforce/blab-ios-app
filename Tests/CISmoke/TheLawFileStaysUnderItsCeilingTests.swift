// TheLawFileStaysUnderItsCeilingTests.swift
// Echoel — #702, extended by #707 (§D), corrected by #708, widened by #746 (§E + §F).
// Blocking bundle: the other suite cannot fail a merge (#208).
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
// ⚠️ HONEST LIMITS. 5 tests, 13 assertion statements (1+1+7+2+2; counted in Python over lines
// whose first token is XCTAssert), and the count moved TWICE inside #746 while I wrote this
// line. ⛔ I first put "8 (1+1+4+2)" here from the SHAPE of the edit — claim 5's two literal
// assertions had become a loop, and I read that as "fewer". Measured, it was still 10: the
// same two statements now run over three witnesses, so the statements held while the checks
// went from two to six. Then extending claim 3 to §E and §F made it 12. Both retractions stay
// visible in the header whose neighbour says `measure; do not recite`, because this is that
// defect in its smallest form. The number that means something is what a claim PROVES; the
// statement count tracks neither coverage nor strength. It measures SIZE, never quality: a file stuffed with 149 KB
// of nonsense passes. And it cannot see the rest of the always-loaded surface — the three
// `.claude/rules/*.md` files add ~13.7 KB that no assertion here bounds, deliberately, because
// the ceiling belongs on the ONE file that grows.
// ⛔ THAT FIGURE WAS WRITTEN "~12.8 KB" AND WENT STALE INSIDE ITS OWN COMMIT: the same commit
// then added 859 B to `context.md` (the #456 pull-along), so the number was wrong before it was
// ever pushed. Left visible rather than silently corrected, because it is this repo's most
// repeated defect in its smallest possible form — a measured number quoted one edit later.
// Re-derive: `for f in CLAUDE.md .claude/rules/*.md; do wc -c "$f"; done`.
//
// ⭐ GRADING FOR #751 (this tree, parent `a5dd049`) — EPOCH 5. Claims 1, 2 and 4 are
// COUNTERWEIGHTS. Claims 3 and 5 are MIXED again, for the same structural reason as EPOCH 4:
// their §A–§F halves are counterweights, their §G halves FORWARD (that section is created by
// this commit). #751 moved the donut-pill provenance out and CORRECTED a stale number while
// doing it — `CLAUDE.md` 148,028 → 147,117 B. The move is smaller than #746's because two
// thirds of the block turned out to be live LAW, not provenance; that is the expected shape,
// not a shortfall.
//
// ⭐ EARLIER GRADING FOR #746 (parent `1d5b041`) — EPOCH 4. Claims 1, 2 and 4 are
// COUNTERWEIGHTS (green on the parent too). Claim 3 is MIXED: its §A–§D assertions are
// counterweights, its §E and §F assertions FORWARD (those sections did not exist on the
// parent). Claim 5 is MIXED for the same reason and must be labelled as such: its
// §C witness is a counterweight (it predates this commit), while the §E and §F witnesses are
// FORWARD — the sections they name were created by THIS commit, so those four assertions were
// unfalsifiable on the parent. Booking the whole claim as a counterweight would be the modest
// direction and booking it all forward the flattering one (#464); it is neither.
// ⚠️ And claim 2 came within 4,715 B of red rather than the 1,762 B it had before: #746 moved
// the `PianoRollView` line-count nachlese (§E) and the `AdaptiveCardGrid` panel-count chain
// (§F) out, taking `CLAUDE.md` from 148,238 B to 145,285 B. That is the repair claim 2's
// message prescribes, executed — not a relaxation of the ceiling.
//
// ⭐ EARLIER GRADING (§3), restated for #708's parent because #707 edited this file and left #702's
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
        // #746 moved two blocks for HEADROOM, the #707 shape: `CLAUDE.md` 148,238 → 145,285 B
        // (2,953 B recovered on the file this guard tests; the always-loaded SURFACE fell by
        // the same 2,953 B, because this commit spent nothing on `.claude/rules/*`). Both
        // quantities are named on purpose — §D's lesson is a threshold that did not test what
        // it named, and one number standing for two is how that happens.
        XCTAssertTrue(ledger.contains("## E — `PianoRollView` (#475)"), """
            §E (the `PianoRollView` line-count nachlese, moved by #746) is gone. CLAUDE.md's \
            register bullet POINTS at it and keeps only the law (state the size of the edit, \
            never a living file's line count) — a dangling pointer here means the law file \
            promises a nachlese that no longer exists.
            """)
        XCTAssertTrue(ledger.contains("## G — Die „Donuts\"-Pille und der tote Tools-Katalog"), """
            §G (the donut-pill retraction and the dead tools catalogue, moved by #751) is gone.
            CLAUDE.md's Absent-register bullet POINTS here and keeps only the law: unreachable is
            NOT the same as ineffective, this line deliberately gets no text-scan guard (#491),
            and the two lessons about reachability and persisted flags.
            """)
        XCTAssertTrue(ledger.contains("## F — `AdaptiveCardGrid` / reflowende Panels"), """
            §F (the four versions of the reflowing-panel count, moved by #746) is gone. The \
            adaptivity paragraph in CLAUDE.md POINTS here and keeps only the number, the \
            re-derivation commands and the one sentence needed to USE them (a grid can live \
            in a `private var` that is not a panel — follow the CALLER).
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

    // MARK: - 5: the moves actually happened, in both directions

    /// #472: grep AFTER moving. ONE witness stands for each moved block, chosen so it cannot
    /// be re-derived by accident: a filename that never existed (#702 → §C), a struck line
    /// count (#746 → §E), and a sentence naming the panel that never had a grid (#746 → §F).
    ///
    /// ⚠️ A witness is NOT a summary of its block — it is a tripwire. Its absence from the
    /// ledger means a paid-for lesson was DELETED rather than moved; its presence in
    /// `CLAUDE.md` means the block is re-accreting in the always-loaded file, which is how
    /// the surface refilled in the nine days after #538.
    func testTheMovedProvenanceIsInTheLedgerAndNotInTheLawFile() throws {
        let ledger: String = try rawFile("memory/LEDGER_COUNTS.md")
        let law: String = try rawFile("CLAUDE.md")
        let witnesses: [(needle: String, section: String, what: String)] = [
            ("MIDIFileExporterDrumTests", "§C", "the #474 retraction — a cited test file that NEVER existed"),
            ("988 Zeilen", "§E", "the struck `PianoRollView` line count (#475 wrote 988; it was 987)"),
            ("Der Träger sitzt in `weatherRow`", "§F", "the sentence naming the panel that never had a grid"),
            ("statt einen 17. anzuhängen", "§G", "the ambiguous slot-budget phrase from the donut-pill block")
        ]
        for w in witnesses {
            XCTAssertTrue(ledger.contains(w.needle), """
                \(w.what) is missing from `memory/LEDGER_COUNTS.md` \(w.section).
                Every move out of CLAUDE.md was made on the ledger's promise to keep every \
                line. If this needle is in NEITHER file, the lesson was deleted, not moved.
                """)
            XCTAssertFalse(law.contains(w.needle), """
                \(w.what) is back in CLAUDE.md. That is the re-accretion this guard exists \
                to stop. Point at `memory/LEDGER_COUNTS.md` \(w.section) instead of \
                re-quoting the provenance in the always-loaded file.
                """)
        }
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
