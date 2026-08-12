# Context Rules — apply to every session

**This file is deliberately small, because it is always loaded.** It sits alongside
`engineering.md` and `swift-audio.md` (2.6 KB + 3.2 KB). Anything that only matters while
working in one directory belongs in that directory's `CLAUDE.md`, not here.

## 1. What a session already pays

Measured 2026-08-12: **925,658 bytes / 909,101 chars** arrive before the first line of work.

| source | bytes | note |
|---|---|---|
| `CLAUDE.md` | 715,488 | of which **562,848 chars (80.2 %)** is one ledger, lines 310–5911 |
| SessionStart hook stdout | 199,983 | `cat memory/*.md` **uncapped** (191,875 B; `decisions.md` alone 112,829 B) |
| `.claude/rules/*.md` | 10,187 | **this file is 4,404 of them** — it was 5,783 before it existed |

`.claude/settings.json` sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "50"`, so compaction fires at
half budget. The ~25 KB of executable law (audio-thread bans, force-unwrap ban,
`EchoelValueField`, the 3 Hz flash ceiling, the OSC address set) is **2.7 %** of that surface
and is what gets summarised away first. **Do not grow the always-loaded set.** Adding a line to
an accreting ledger is cheap for you and charged to every future session.

The one working mitigation in the tree is the `sed -n '1,80p'` cap on `SESSION_LOG.md`, which
keeps 778,917 B off the bill. **Do not remove it.**

## 2. Measure; do not recite, estimate, or remember

- **`wc -c` and `awk length()` count BYTES**, not characters — this repo's prose carries 726
  multi-byte marker glyphs (`⛔ ⚠️ ⭐`) plus German. A character claim needs Python
  (`len(open(p, encoding='utf-8').read())`). I published "573,478 chars / 79.1 %" for the
  ledger on 2026-08-12; both halves were wrong — it is 562,848 chars / 80.2 %, and the ratio
  had also been mis-divided. **Retracted here so the wrong pair is not re-quoted.**
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
