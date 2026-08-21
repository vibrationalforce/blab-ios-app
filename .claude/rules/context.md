# Context Rules — apply to every session

**This file is deliberately small, because it is always loaded.** It sits alongside
`engineering.md` and `swift-audio.md` (2.6 KB + 3.2 KB). Anything that only matters while
working in one directory belongs in that directory's `CLAUDE.md`, not here.

## 1. What a session already pays

Three sources arrive before the first line of work: `CLAUDE.md`, the SessionStart hook's
stdout, and `.claude/rules/*.md`.

⛔ **THE BYTE TABLE THAT STOOD HERE IS DELETED, NOT REFRESHED, and that is the whole lesson.**
It asserted a total, a per-file breakdown and two law-share percentages, and a 2026-08-19
re-measurement found **seven** of those figures wrong — `CLAUDE.md` alone had grown +13,734 B
past the number printed two paragraphs above the rule "measure; do not recite". The same block
also carried its own contradiction: it said the executable law is "~11 %" of the surface and
then "2.7 %" of it, six lines apart. **Refreshing the numbers would have rebuilt the trap**;
a table of bytes in an always-loaded file is a date, not a fact, and nothing re-derives it.

**The live figure is `python3 scripts/doctor.py --section D`** — it prints the surface total,
the per-file split, and WARNs when **`CLAUDE.md` alone** passes 150,000 B. ⚠️ The threshold is
on that ONE file, not on the total, and the earlier wording here attached it to the total —
so on 2026-08-21 the section printed "Under the ceiling" at a surface of 155,062 B
(`CLAUDE.md` 142,688). A stated threshold that does not test the quantity it names is the
same defect class as a needle that cannot match. The ceiling is on the one file on purpose:
#538's repair — moving provenance to `memory/LEDGER_COUNTS.md` — only shrinks `CLAUDE.md`.

That ledger holds the count-provenance chains verbatim — **three** since #702 added §C
(`Tests/EchoelmusicTests/`) beside #538's §A and §B; it is NOT in the hook's `cat` list and must
never be added to it. ⛔ This sentence said "the two" until #702 and was a stale COUNT in the
file whose own §2 says *measure; do not recite* — re-derive with
`grep -c '^## [A-Z] — ' memory/LEDGER_COUNTS.md` rather than trusting the word here.

⚠️ **The ceiling now has teeth, and a red is not an order to delete your paragraph.**
`Tests/CISmoke/TheLawFileStaysUnderItsCeilingTests.swift` (#702) asserts the same 150,000 B on
the same one file, in the BLOCKING bundle, because a doctor WARN is advisory and nothing reads
it on a push. Its claim-2 message carries the repair: move PROVENANCE to the ledger, keep LAW
here. #701 added a genuine register entry with 628 B of headroom and was right to — the guard
exists to make the trade conscious, not to make the law file stop growing.

`.claude/settings.json` sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "50"`, so compaction fires at
half budget, and the executable law (audio-thread bans, force-unwrap ban, `EchoelValueField`,
the 3 Hz flash ceiling, the OSC address set) is the small share that gets summarised away
first. **Do not grow the always-loaded set.** Adding a line to an accreting ledger is cheap
for you and charged to every future session.

**Two caps hold this line. Do not remove either.** `sed -n '1,80p'` on `SESSION_LOG.md` keeps
778,917 B off the bill. `cat memory/*.md` was uncapped at 191,875 B (`decisions.md` alone
112,829, `inspiration_intake.md` 44,665) and is now sliced: five small files whole,
`decisions.md` tail-400, `inspiration_intake.md` head-60 (the funnel + the gate) plus
tail-120. Each slice prints what it withheld and the command to read the whole file.

⚠️ The `decisions.md` slice is a **heuristic, not a guarantee**, and the banner says so:
that file is **not** in date order. The tail wins only because the newest entry happens to sit
near it — re-derive with `grep -nE '^### 20[0-9]{2}-' memory/decisions.md | tail -3` against
`wc -l`, and note that a plain newest-date scan is WRONG here: it lands on a `review_date`
inside an older entry, not on the newest entry. If entries ever get appended elsewhere, the cap
silently shows the wrong ones. The real repair is ordering the file, not widening the slice.

## 2. Measure; do not recite, estimate, or remember

- **`wc -c` and `awk length()` count BYTES**, not characters — this repo's prose carries 726
  multi-byte marker glyphs (`⛔ ⚠️ ⭐`) plus German. A character claim needs Python
  (`len(open(p, encoding='utf-8').read())`). I published "573,478 chars / 79.1 %" for the
  ledger on 2026-08-12; both halves were wrong — it was 562,848 chars / 80.2 %, and the ratio
  had also been mis-divided. **Retracted here so the wrong pair is not re-quoted.** (Both
  numbers describe the file BEFORE #538 moved the chain out; neither says anything about today.)
- **A token count is not a char count / 3.5.** If no tokenizer ran, say UNMEASURED.
- **When a hand survey and an executable check disagree, the check is the measurement** and the
  survey is a memory of one (#453 → #477: a survey said eleven, a guard in the same commit
  selected a twelfth).
- Write the **command** next to any number you record, so the next reader can re-derive it
  instead of trusting it.

## 3. Reading CI

`Xcode Compile Check` builds `Sources/` **only**. CI/CD reports `failure` on **every** push
because of #396, so the conclusion alone says nothing — read the **job steps**. The full
discriminator (`Build for Testing` / `TEST EXECUTE FAILED` / `TEST BUILD FAILED`, and #445 on
what a missing test name does and does not prove) lives in **`Tests/CISmoke/CLAUDE.md` §5**;
it is not repeated here (#416).

**`.github/workflows/**`, `project.yml` and `Resources/iOS/Info.plist` are founder-gated:
report, do not edit.**

## 4. Handling large tool output

`mcp__github__actions_list` and `get_job_logs` routinely exceed the token cap and are written
to a file instead. Do not read such a file whole.

- Runs → `python3 scripts/gh-run-status.py <file>` (one line per run). Extend this script
  rather than writing a second parser.
- Logs → count needles in Python (`t.count(...)`) and print only the matching lines.
- Never paste a raw log or a large file into the transcript to "have it".

## 5. Subagents

⚠️ **A previous subagent destroyed uncommitted work in this repo.** Every subagent prompt must
carry, verbatim: *read-only inspection only — `git diff`, `git show`, `git log`, `git grep`,
Read/Grep/Glob; never `git checkout`, `stash`, `restore`, `reset`, `clean`, `add`, `commit`,
`push`; never edit, create or delete a file; report findings as text.*

Scratch files go **only** under the session scratchpad directory named in the system prompt,
with a unique prefix — never `/tmp`, never the repo.

Fan-out shape and the ≤4-workers-per-lead rule: `.claude/skills/ultracode-teams`.

## 6. Before escalating to the founder

**Measure first.** #451 asked the founder about GitHub Actions billing on the strength of a
missing-runs observation; the repository is public, standard runners are free, all workflows
were active, and the runs were merely queued. The answer that came back — *"Es sollen keine
Kosten entstehen"* — was spent on a non-question.

A question to the founder is more expensive than any measurement. Escalate only for genuine
ambiguity (`AskUserQuestion`), and only after the cheap check that would settle it.
