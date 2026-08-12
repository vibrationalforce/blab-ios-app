# Context Rules — apply to every session

**This file is deliberately small, because it is always loaded.** It sits alongside
`engineering.md` and `swift-audio.md` (2.6 KB + 3.2 KB). Anything that only matters while
working in one directory belongs in that directory's `CLAUDE.md`, not here.

## 1. What a session already pays

Measured 2026-08-12, **after #538**: **227,099 bytes** arrive before the first line of work.

| source | bytes | note |
|---|---|---|
| `CLAUDE.md` | 126,635 | was **715,488** — #538 moved the two count chains out (see below) |
| SessionStart hook stdout | 89,515 | was 199,983 until the two big memory files were capped |
| `.claude/rules/*.md` | 10,949 | **this file is 5,166 of them** — it was 5,783 before it existed |

⛔ **This table read `715,488 / 562,848 chars (80.2 %) / lines 310–5911` and every number in it
is now history.** #538 moved that chain — the `Tests/CISmoke` provenance (5,599 lines) and the
`Sources/**` provenance (17,511 chars inside one bullet) — **verbatim** to
`memory/LEDGER_COUNTS.md`, leaving a routing line at each site. Nothing was deleted; the file is
NOT in the SessionStart hook's `cat` list and must never be added to it. The always-loaded
surface fell **−588,853 B (−72.2 % of the total, −82.3 % of `CLAUDE.md`)**, so the ~25 KB of
executable law is now **~11 %** of the surface instead of 2.7 %. `scripts/doctor.py --section D`
prints this table live and WARNs above 150,000 B; **read it there, do not quote this row.**

`.claude/settings.json` sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "50"`, so compaction fires at
half budget. The ~25 KB of executable law (audio-thread bans, force-unwrap ban,
`EchoelValueField`, the 3 Hz flash ceiling, the OSC address set) is **2.7 %** of that surface
and is what gets summarised away first. **Do not grow the always-loaded set.** Adding a line to
an accreting ledger is cheap for you and charged to every future session.

**Two caps hold this line. Do not remove either.** `sed -n '1,80p'` on `SESSION_LOG.md` keeps
778,917 B off the bill. `cat memory/*.md` was uncapped at 191,875 B (`decisions.md` alone
112,829, `inspiration_intake.md` 44,665) and is now sliced: five small files whole,
`decisions.md` tail-400, `inspiration_intake.md` head-60 (the funnel + the gate) plus
tail-120. Each slice prints what it withheld and the command to read the whole file.

⚠️ The `decisions.md` slice is a **heuristic, not a guarantee**, and the banner says so:
that file is **not** in date order — its first 200 lines carry 07-21…07-23 and its last 200
carry 07-20…07-31. The tail wins only because the newest entry (07-31) sits at line 1242 of
1272. If entries ever get appended in a different place, the cap silently shows the wrong
ones. The real repair is ordering the file, not widening the slice.

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
