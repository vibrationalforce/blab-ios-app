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
// ⭐ GRADING FOR #763 (this tree, parent `99155dc`) — EPOCH 6. Claims 1-4 are COUNTERWEIGHTS
// (green on the parent too). Claim 5 is MIXED, and the split is not the usual one: its four
// LEDGER witnesses are counterweights, its fifth witness (`RUN_DESTINATION_DEVICE_NAME`,
// pointing at `Tests/CISmoke/CLAUDE.md` §5b) is a REGRESSION CATCH — both of its assertions
// are RED on the parent, measured (`git show HEAD:` on both files): the needle was absent from
// §5b and PRESENT in `CLAUDE.md`, which is precisely the state this commit repairs.
// ⛔ I first wrote "FORWARD — unfalsifiable on the parent" here, copying the §E/§F wording from
// EPOCH 4 without measuring. That is the MODEST direction of #464 rather than the flattering
// one, and it is still wrong: a forward guard CANNOT go red on the parent, this one does, and
// calling a real regression catch unfalsifiable understates what the file proves. The claim's SHAPE also
// changed: the destination is now per-witness, because #763's block is not count provenance
// and forcing it into the counts ledger would have made a FOURTH copy of the decision the move
// exists to de-duplicate. Statements still 13 (1+1+7+2+2, counted in Python over lines whose
// first token is XCTAssert); the checks claim 5 RUNS went 8 → 10. Same lesson as EPOCH 4: the
// statement count tracks neither coverage nor strength.
// ⚠️ Claim 2's margin is the reason this commit exists. The parent stood at 148,802 B — 1,198 B
// under the ceiling, i.e. the next register entry would have turned this guard RED. #763 moved
// the 10,019 B gate-discriminator block out and `CLAUDE.md` is 139,890 B, so the headroom is
// 10,110 B. That is claim 2's own prescribed repair executed, not a relaxation — and unusually,
// the moved block was a DUPLICATE rather than provenance: `.claude/rules/context.md` §3 had
// already named `Tests/CISmoke/CLAUDE.md` §5 as its one home and said it "is not repeated here".
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
            adaptivity paragraph in CLAUDE.md POINTS here and keeps only what a session \
            needs while MEASURING: the number, the `grep -c` that yields its denominator, \
            that command's TWO known deviations, the note that the neighbouring block runs a \
            DIFFERENT command yielding 11, and the two rules for using it (a \
            grid can live in a `private var` that is not a panel — follow the CALLER; \
            `spacing` is an ARGUMENT because a one-column grid REPLACES its host's spacing).
            ⛔ THIS MESSAGE DESCRIBED AN END STATE THE FILE DID NOT HAVE, FROM #746 UNTIL \
            #912: the pointer was written and the ~1.8 kB door history stayed in the \
            always-loaded file. NOTHING here could see that — claim 3 only asks whether the \
            DESTINATION exists. Claim 5's `wortgrenzen-genau zwei Schreiber` witness is the \
            half that was missing. ⚠️ #912's own first draft then repeated the defect one \
            size smaller: it cut the `grep -c` OUT of the paragraph while this message still \
            promised commands, leaving a pointer to a NEIGHBOURING block whose different \
            command yields 11 where the prose says 10. The law is therefore two-sided — a \
            move is only a move when the SOURCE got shorter (measure both sides, put the \
            figures in the commit), and every description of what SURVIVED has to be \
            re-read against the shortened text, not against the intention.
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
    /// count (#746 → §E), a sentence naming the panel that never had a grid (#746 → §F), and a
    /// simulator log key that appears exactly once in the tree (#763 → `Tests/CISmoke` §5b).
    ///
    /// ⚠️ A witness is NOT a summary of its block — it is a tripwire. Its absence from the
    /// destination means a paid-for lesson was DELETED rather than moved; its presence in
    /// `CLAUDE.md` means the block is re-accreting in the always-loaded file, which is how
    /// the surface refilled in the nine days after #538.
    ///
    /// ⭐ THE DESTINATION IS PER-WITNESS SINCE #763, and that generalisation is the point
    /// rather than tidiness. Four blocks went to `memory/LEDGER_COUNTS.md` because they are
    /// COUNT provenance and that ledger is where count chains live. The fifth is not a count:
    /// it is the CI-gate discriminator, whose one home `.claude/rules/context.md` §3 already
    /// named as `Tests/CISmoke/CLAUDE.md` §5 — so sending it to the counts ledger to satisfy
    /// a hard-coded path would have created a FOURTH copy of the very decision it was moved
    /// to de-duplicate. A guard that forces the wrong destination is worse than no guard.
    func testTheMovedProvenanceIsInItsLedgerAndNotInTheLawFile() throws {
        let law: String = try rawFile("CLAUDE.md")
        let witnesses: [(needle: String, home: String, section: String, what: String)] = [
            ("MIDIFileExporterDrumTests", "memory/LEDGER_COUNTS.md", "§C",
             "the #474 retraction — a cited test file that NEVER existed"),
            ("988 Zeilen", "memory/LEDGER_COUNTS.md", "§E",
             "the struck `PianoRollView` line count (#475 wrote 988; it was 987)"),
            ("Der Träger sitzt in `weatherRow`", "memory/LEDGER_COUNTS.md", "§F",
             "the sentence naming the panel that never had a grid"),
            ("statt einen 17. anzuhängen", "memory/LEDGER_COUNTS.md", "§G",
             "the ambiguous slot-budget phrase from the donut-pill block"),
            ("eine Zahl, die eine UNGETRACKTE Datei mitzählt", "memory/LEDGER_COUNTS.md", "§B",
             "the #818 move — the source-file COUNT and its whole chain (983 B) left the law "
             + "file; the literal was deleted rather than nursed, because #813 added one file "
             + "and made the number wrong with nothing going red"),
            ("wortgrenzen-genau zwei Schreiber", "memory/LEDGER_COUNTS.md", "§F.4",
             "the `visualVJOverlay` door history (#505 doorless -> #747 doored) — the ~1.8 kB "
             + "that #746 pointed away from and then LEFT IN PLACE; #912 measured both sides "
             + "and finished the move. ⛔ THE FIRST NEEDLE HERE WAS `tote Zweitkopie` AND IT "
             + "WAS TWO DEFECTS AT ONCE. (a) #364: CLAUDE.md line 24 carries `TOTE "
             + "Zweitkopie` in caps, so ordinary de-shouting of an UNRELATED sentence would "
             + "have reddened this row with the message 'the block is re-accreting'. Swift "
             + "`contains` is case-sensitive, so it was green — one keystroke from a false "
             + "red. (b) It anchored the block's most incidental clause, a sentence ABOUT "
             + "wording; a re-accretion that dropped that one clause would have passed "
             + "silently. This needle names the MEASUREMENT instead (`showVisual` had two "
             + "writers, both `false`), which paraphrase does not survive"),
            ("RUN_DESTINATION_DEVICE_NAME", "Tests/CISmoke/CLAUDE.md", "§5b",
             "the Clone-2 evidence from the #763 gate-discriminator move — the log line that "
             + "settled which simulator clone dies under #396")
        ]
        for w in witnesses {
            let home: String = try rawFile(w.home)
            XCTAssertTrue(home.contains(w.needle), """
                \(w.what) is missing from `\(w.home)` \(w.section).
                Every move out of CLAUDE.md was made on that file's promise to keep every \
                line. If this needle is in NEITHER file, the lesson was deleted, not moved.
                """)
            XCTAssertFalse(law.contains(w.needle), """
                \(w.what) is back in CLAUDE.md. That is the re-accretion this guard exists \
                to stop. Point at `\(w.home)` \(w.section) instead of re-quoting the \
                provenance in the always-loaded file.
                """)
        }
    }

    /// #818 — the source-file count was DELETED from the law file, not refreshed. A guard on
    /// the literal would go red on every new source file and force an edit to the file that
    /// sits ~2.5 kB under its ceiling; the repair is the one #810 and #803 already made, twice:
    /// **replace an unmaintainable number with its command.** So this claim is POSITIVE — it
    /// pins that the routing is there. A negative scan for "no digits on this line" would hit
    /// the retraction's own byte figure and is exactly the #491 self-hit.
    func testTheFileCountLineRoutesInsteadOfAssertingANumber() throws {
        let law: String = try rawFile("CLAUDE.md")
        let candidates = law.components(separatedBy: "\n").filter { $0.hasPrefix("- **Files:**") }
        XCTAssertEqual(candidates.count, 1, """
            Expected exactly one `- **Files:**` line in CLAUDE.md, found \(candidates.count).
            This scan anchors on that prefix; re-anchor it rather than letting it match nothing.
            """)
        let line = candidates.first ?? ""
        let command = "git ls-files 'Sources/**/*.swift' | wc -l"
        XCTAssertTrue(line.contains(command), """
            The Files line no longer carries the counting command. Whoever removed it has to
            put a literal back in its place, and that literal is what #818 deleted — it went
            stale silently four times, most recently on #813.
            """)
        XCTAssertTrue(line.contains("memory/LEDGER_COUNTS.md` §B"), """
            The Files line must point at the ledger section that holds the counting chain, or
            the provenance moved there becomes unreachable from the file a session reads first.
            """)
        XCTAssertTrue(line.contains("MESSEN, nicht zitieren"), """
            The Files line must carry the instruction, not just the command — the command
            without it reads as an optional extra rather than the rule.
            """)
        let ledger: String = try rawFile("memory/LEDGER_COUNTS.md")
        XCTAssertTrue(ledger.contains(command), """
            LEDGER_COUNTS.md §B must name the SAME command, so the two homes cannot teach two
            different recipes for one number (#416).
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

    /// #881 — THE SAME REPAIR, ONE SUITE OVER, and the number it removed was DATED. The
    /// law file carried `(2026-08-21: 314)` beside the counting command for
    /// `Tests/EchoelmusicTests/`, and the measured value on 2026-08-29 was 313.
    ///
    /// ⭐ The date is what protected it: a figure that presents itself as a snapshot LOOKS
    /// like bookkeeping, so nobody re-measures it — and it was wrong anyway, because a file
    /// disappeared after that date. A date beside a number does not make it honest, it makes
    /// it unassailable. So the number is DELETED, like #818's, not refreshed.
    ///
    /// ⚠️ The second home was the more dangerous one even though it carried no date: the
    /// `## KEY TESTS` HEADING. Same lesson as the H1 at the top of the law file — a heading
    /// is part of the claim, and a `grep` for the struck literal belongs to the striking.
    ///
    /// POSITIVE on the command (the #818 shape, so this cannot become a #491 self-hit), and
    /// on the heading it asserts only that no "N files" count came back — a bounded scan of
    /// ONE line, not of the whole file.
    func testTheTestCountLineRoutesInsteadOfAssertingANumber() throws {
        let law: String = try rawFile("CLAUDE.md")
        let command = "git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l"
        XCTAssertTrue(law.contains(command), """
            The law file no longer carries the counting command for the non-blocking suite. \
            Whoever removed it has to put a literal in its place, and that literal is what \
            #881 deleted — it was stale while wearing a date that made it look maintained.
            """)

        let headings = law.components(separatedBy: "\n").filter { $0.hasPrefix("## KEY TESTS") }
        XCTAssertEqual(headings.count, 1, """
            Expected exactly one `## KEY TESTS` heading, found \(headings.count) — re-anchor \
            this claim rather than letting it match nothing (§4).
            """)
        let heading = headings.first ?? ""
        XCTAssertFalse(heading.contains(" files"), """
            The KEY TESTS heading asserts a file count again: \(heading)
            A heading is part of the claim. Point at the `git ls-files` command in REPO \
            STRUCTURE instead; the counting chain lives in `memory/LEDGER_COUNTS.md` §C.
            """)
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
