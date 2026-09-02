#!/usr/bin/env python3
"""Read the crash ladder — from the SOURCE, and then from a device log.

WHY THIS EXISTS. #859–#882 built a ladder into the audio paths: every intervention
writes a numbered rung into the exported `echoel_diag.log`, and the law is that a
rung stands BEFORE its call, so **silence between two rungs is a finding**. That law
is only usable if two things hold, and both were violated before this script existed:

  1. Every announced step must have an emitter in the source. #882 found three that
     did not — `on 4/5`, `on 5/5` and a wholly absent `off 5/5` — so a healthy run
     logged 1/5, 2/5, 3/5 and stopped, which reads as a death at step 3. That was
     found BY HAND, months after the rungs were written.
  2. A human must be able to read a 500-line log and say which step died. Today that
     is done by eye, per log, under time pressure, by whoever the founder pasted it to.

⭐ THE DESIGN DECISION THAT MATTERS: the ladder vocabulary is **derived from
`Sources/` at run time**, never hardcoded here. A hardcoded table is the
self-confirming-enumeration failure this repo keeps paying for — a census whose
search pattern comes from the entries already known confirms itself and goes stale
in silence. Derived, this tool cannot drift from the code.

⛔ AND THE FIRST VERSION OF THIS PARAGRAPH OVER-CLAIMED, so the retraction stays: it
said `--source` "would have caught #882 on the day those rungs were written". Measured
against the pre-#882 tree, it reports `MISSING [5] 'off' 1..5` — and calls `'on' 1..5`
COMPLETE, because the two ON rungs did exist, they were merely CONDITIONAL. So it would
have caught ONE of #882's three defects, not all three. The tool sees whether a step has
an emitter; it cannot see whether that emitter is reachable on every path. Finding the
other two still took reading the braces.

USAGE
    python3 scripts/diag-ladder.py --source            # audit the ladders in Sources/
    python3 scripts/diag-ladder.py path/to/echoel_diag.log
    python3 scripts/diag-ladder.py --selftest

EXIT CODES
    0  nothing to report
    1  a finding (an incomplete ladder in the source, or a truncated run in a log)
    2  INSTRUMENT UNAVAILABLE — could not read what it needed. Deliberately NOT 0:
       a diagnostic tool that returns green when it could not look is the same lie
       as a masked CI gate (the `doctor.py` rule).

WHAT THIS CANNOT SAY — stated because a diagnosis without limits is itself a lie:
  · IT CANNOT SEE A CONDITIONAL EMITTER. A rung inside `if x { … }` counts here exactly
    like an unconditional one, so a ladder can read COMPLETE and still fall silent at run
    time — that was two of #882's three defects. Only the brace nesting settles it.
  · #882 made every numbered step emit either way, so a gap SHOULD now mean a death — but
    only for ladders written after it. An older ladder can still skip silently.
  · It never proves a crash. A log ending mid-ladder can also be a log that was
    exported mid-session, or a device that ran out of disk.
  · It reads only what the breadcrumb sink wrote. `os_log` lines are invisible in
    the exported file by construction, so their absence means nothing.
  · LAST WINS, PER LADDER. Only the newest rung and the newest terminator of each ladder
    are kept, so a log with TWO attempts hides the first one's outcome behind the second's:
    attempt 1 dies at 2/3, attempt 2 completes → `done`. That predates #908 (the original
    loop overwrote the same way); #908 adds a second such path, since a later terminator
    rescues an earlier death. A per-attempt reading needs a run marker in the log, which
    does not exist. Read the raw lines when a log shows more than one attempt.
  · A NUMBERED skip is ambiguous and is NOT a terminator — see `ladder_verdicts`.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict

# A rung literal looks like "<prefix> <step>/<total><separator><prose>".
# Anchored at the start of the string literal so a number inside prose cannot match.
# ⛔ THE FIRST VERSION HAD NO SEPARATOR RULE AND ITS OWN SELFTEST CAUGHT IT: the negative
# sample `"latency 12/48 ms measured"` matched, which would have minted a phantom ladder
# `latency 1..48` with 47 "missing" steps — a loud false alarm, i.e. the #665 failure where
# a checker with false alarms becomes a checker nobody reads. The rule below is DERIVED from
# the corpus, not invented: every real rung in `Sources/` is followed by `:`, ` —` or
# ` SKIPPED`. ⚠️ And that cuts in the dangerous direction — a future rung with a new
# separator would be MISSED, silently. So nothing is dropped silently: `--source` prints
# every near-miss under "not read as rungs" so a human sees what the rule refused.
RUNG = re.compile(
    r"^(?P<prefix>[A-Za-z][A-Za-z /:+-]{0,28}?)\s(?P<step>\d{1,2})/(?P<total>\d{1,2})"
    r"(?P<sep>:| —| -| SKIPPED)")
# The same shape WITHOUT the separator — used only to report what was refused.
RUNG_SHAPE = re.compile(
    r"^(?P<prefix>[A-Za-z][A-Za-z /:+-]{0,28}?)\s(?P<step>\d{1,2})/(?P<total>\d{1,2})\b")

# The three sinks that reach the exported file. `log.audio`/`os_log` deliberately absent:
# they do NOT appear in echoel_diag.log, which is the whole reason the ladder exists.
SINKS = ("EchoelCrashLog.breadcrumb(", "logEngineLifecycle(", "logMonitorOutcome(")

STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def repo_root() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(here)


def tracked_swift(root: str) -> list[str]:
    out = subprocess.run(["git", "-C", root, "ls-files", "Sources/*.swift"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "git ls-files failed")
    return [os.path.join(root, p) for p in out.stdout.split("\n") if p.strip()]


REFUSED: list[str] = []


def ladders_in_source(root: str) -> dict[tuple[str, int], dict[int, list[str]]]:
    """(prefix, total) -> {step: [file:line, ...]}.

    ⚠️ Scans EVERY string literal in a file that contains at least one sink call —
    not only the literal syntactically inside the call. Two of the rungs written in
    #877/#878 are WRAPPED, so their literal sits on its own line and an
    argument-scoped parser silently misses exactly the newest ones. Over-collecting
    is the safe direction here: a false rung shows up as a stray prefix a human sees
    at once, while a missed rung is an invisible gap in the thing being audited.
    """
    found: dict[tuple[str, int], dict[int, list[str]]] = defaultdict(lambda: defaultdict(list))
    REFUSED.clear()
    for path in tracked_swift(root):
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        if not any(s in text for s in SINKS):
            continue
        rel = os.path.relpath(path, root)
        for lineno, line in enumerate(text.split("\n"), 1):
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            for literal in STRING_LITERAL.findall(line):
                m = RUNG.match(literal)
                if not m:
                    shape = RUNG_SHAPE.match(literal)
                    if shape and int(shape.group("total")) >= 2:
                        REFUSED.append(f"{rel}:{lineno}  {literal[:70]}")
                    continue
                total = int(m.group("total"))
                step = int(m.group("step"))
                if total < 2 or step < 1 or step > total:
                    continue
                prefix = m.group("prefix").strip()
                found[(prefix, total)][step].append(f"{rel}:{lineno}")
    return found


def census_pattern(names: list[str]) -> "re.Pattern[str]":
    """The census matcher, lifted out so the selftest can drive REAL literals through it
    (#914 review, MEDIUM-4). Longest prefix first, so `mic: start` wins over `start`.

    Group 1 = ladder prefix · group 2 = the rung number, present or None · group 3 = the word.
    ⚠️ Group 2 only says a number is TEXTUALLY there. It does not check the number is a rung
    of the matched ladder — `on 2/3 SKIPPED` (wrong total) matches with group 2 set, while
    `ladder_verdicts` sees neither a rung nor a terminator on that line. That is why
    `census_effect` says "does NOT rescue" for a numbered line rather than "walks on": the
    weaker claim is the one this pattern can actually support.
    """
    short = [w for w in TERMINAL_WORDS if len(w) < 3]
    word = "|".join(["[A-Z]{3,}"] + [re.escape(w) for w in short])
    return re.compile(r"(?:^|[^A-Za-z:])(" + "|".join(re.escape(n) for n in names)
                      + r")\s+(\d{1,2}/\d{1,2}\s+)?(" + word + r")\b")


def terminators_in_source(root: str,
                          ladders: dict[tuple[str, int], dict]
                          ) -> list[tuple[str, str, str, bool]]:
    """Every `<ladder prefix> …<ALL-CAPS WORD>` in `Sources/`, as (where, prefix, word, numbered).

    ⭐ #914 — `numbered` IS THE POINT OF THE FOURTH FIELD. This census deliberately
    over-collects (see below), so it also picks up NUMBERED skips like `on 4/5 SKIPPED`,
    which do NOT end their ladder: they walk on to `on 5/5`. Until #914 the printed section
    was headed "terminator lines (end a ladder without advancing it, #908):" and listed them
    side by side with the real terminators, with the distinction demoted to the footnote below
    the list. A tool written to remove exactly that ambiguity must not reproduce it in its own
    output, so each line now says for itself whether it rescues a short ladder — see
    `census_effect`, whose docstring carries the three ways the first draft got that wrong.

    ⭐ IT SCANS FOR *ANY* ALL-CAPS TOKEN, NOT FOR `TERMINAL_WORDS`. Searching for the words
    already known would be the self-confirming enumeration this file's own header warns
    about: the census would agree with the list by construction and a fourth word added in
    `Sources/` would never show up — it would just silently go back to reading as a death.
    Scanning the shape instead means the selftest can assert `found ⊆ TERMINAL_WORDS` and
    actually fail. ⛔ A LITERAL CENSUS STOOD HERE ("SKIPPED (3), REFUSED (1), FAILED (1)")
    and went stale TWICE unnoticed — REFUSED at #910, SKIPPED at #913 — in the docstring of
    the very function whose job is to distrust a hard-coded vocabulary. Deleted, not
    refreshed: `python3 scripts/diag-ladder.py --source` prints the live census, and the
    selftest asserts the property that actually matters (`found ⊆ TERMINAL_WORDS`).

    ⚠️ THIS SCANS RAW LINES, NOT `STRING_LITERAL` MATCHES, and that is deliberate: the one
    terminator that matters most — `mic: start REFUSED — input format not ready` — lives
    inside a `\"\"\"` block, where a quote-pair scanner finds nothing. Under-reporting a
    census that exists to prove the vocabulary is complete would defeat its purpose, so it
    over-collects in the safe direction, exactly as `ladders_in_source` does.

    ⭐ #957 — THE FIFTH FIELD IS THE RUNG TEXT, and it exists because the fourth was not
    enough. `census_effect` knew a line was NUMBERED but not WHICH number, so it printed
    "still reads as ❌ died" for every numbered skip — including one at the LAST rung, where
    the ladder is COMPLETE and this same tool prints `✅ done` in log mode. A tool that tells a
    triager the opposite of what it itself does is the #937 defect inside the instrument.

    ⚠️ IT CANNOT SEE A 1/1 LADDER'S TERMINATOR (#908 review, LOW-6): `ladders_in_source`
    drops `total < 2`, so `session: lower` is not in `names` and its two `SKIPPED` lines do
    not appear here. Harmless — a 1/1 ladder is not tracked in log mode either, so its
    terminator could not change a verdict — and self-correcting the day `lower` grows a
    second step. But "the vocabulary is complete" is a claim about the ladders it can see.
    """
    names = sorted({p for (p, _t) in ladders}, key=len, reverse=True)
    if not names:
        return []
    # The ladder's OWN total, per prefix — `None` when a prefix carries two, which is
    # ambiguous and must fall back to the conservative wording rather than guess.
    totals: dict[str, "int | None"] = {}
    for (pfx, tot) in ladders:
        totals[pfx] = None if (pfx in totals and totals[pfx] != tot) else tot
    pat = census_pattern(names)
    out: list[tuple[str, str, str, bool]] = []
    for path in tracked_swift(root):
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        if not any(s in text for s in SINKS):
            continue
        rel = os.path.relpath(path, root)
        for lineno, line in enumerate(text.split("\n"), 1):
            if line.lstrip().startswith("//"):
                continue
            for m in pat.finditer(line):
                out.append((f"{rel}:{lineno}", m.group(1), m.group(3),
                            m.group(2) is not None,
                            completes_ladder(m.group(2), totals.get(m.group(1)))))
    return sorted(set(out))


def completes_ladder(rung_text: "str | None", total: "int | None") -> bool:
    """Does this numbered census line sit on the ladder's LAST rung? (#957)

    Conservative by construction: `False` unless the text parses as `n/t`, `t` equals the
    ladder's own total, and `n == t`. `census_pattern`'s group 2 only proves a number is
    TEXTUALLY present — `on 2/3 SKIPPED` under a 1..5 ladder matches with the group set — so
    anything that does not line up returns `False` and the caller keeps the cautious wording.
    """
    if not rung_text or total is None:
        return False
    m = re.fullmatch(r"(\d{1,2})/(\d{1,2})\s*", rung_text)
    if not m:
        return False
    n, t = int(m.group(1)), int(m.group(2))
    return t == total and n == t


def census_effect(word: str, numbered: bool, completes: bool = False) -> str:
    """What a census line does to a LOG verdict. Pure, so the selftest drives THIS and not a
    re-implementation of it (#416), and so an inverted flag cannot pass unnoticed (#914
    review, MEDIUM-4: the first check was `any(numbered) and any(not numbered)` over the real
    tree, which survived a full label inversion).

    ⛔ #914's FIRST DRAFT HAD THREE DEFECTS HERE, all in the reassuring direction, and all of
    them the very ambiguity this section was rewritten to remove:

    · An UNKNOWN word printed "ENDS the ladder". `ladder_verdicts` builds its needle from
      `TERMINAL_WORDS`, so a word outside that tuple ends NOTHING — its ladder still reads as
      a death. The per-line label said the opposite of the footer four lines below it, in the
      ONE case the over-collecting census exists for: a word nobody has taught the tool yet.
    · A numbered line printed "walks on", which is a claim about SWIFT CONTROL FLOW that a
      line scanner cannot make. A numbered skip that RETURNS is writable — guard (c3) exists
      because of it — and the label would then point the reader away from a real death, which
      is #908's first draft all over again. The tool-truth is narrower and checkable: it does
      not RESCUE.
    · "ENDS the ladder" was unconditional, but `ladder_verdicts` rescues only when the
      terminator FOLLOWS the last rung AND the ladder is short. `["mic: start REFUSED",
      "mic: start 1/3", "mic: start 2/3"]` is a DEATH, and a BENIGN terminator after a
      COMPLETE ladder leaves `done`. Both measured.
      ⛔ #969 — THAT LAST CLAUSE SAID "a terminator", FULL STOP, AND #967 HAD ALREADY MADE IT
      FALSE: a NON-benign terminator after a complete ladder is the `failed` verdict #967
      exists for. #967 corrected two prose homes and missed this one, four lines below the
      return value that states the new rule correctly. A rule needs correcting in EVERY home
      (#456), and the home nobody re-reads is the docstring of the function that got it right.
    """
    if word not in TERMINAL_WORDS:
        return "ends NOTHING (word unknown to the tool) — its ladder still reads as ❌ died"
    if numbered:
        # ⛔ #957 — THIS PRINTED "still reads as ❌ died" FOR EVERY NUMBERED LINE, and for one
        # at the ladder's LAST rung that is the opposite of what this same tool prints in log
        # mode: a ladder whose last rung is `N/N` is COMPLETE, so the verdict is `✅ done`.
        # A triager holding a crash log was being told to look for a death that the tool
        # itself does not see — the #937 defect one layer in, inside the instrument. The
        # claim stays as weak as the scanner allows everywhere else (`completes` is False
        # unless the number parses AND matches the ladder's own total AND is its last rung).
        if completes:
            return ("does NOT rescue — but this rung COMPLETES the ladder, "
                    "so a log ending here reads ✅ done")
        return "does NOT rescue — a ladder ending here still reads as ❌ died"
    if word in BENIGN_TERMINALS:
        return "rescues a SHORT ladder it FOLLOWS  → ⏹ ended"
    # #967: NOT "a SHORT ladder" any more. A non-benign terminator that FOLLOWS the last rung
    # is a finding whether the ladder is short or complete — the label said "SHORT" while the
    # verdict silently blessed the complete case as `done`.
    return "a finding wherever it FOLLOWS the rungs  → ⚠️ failed (short or complete)"


def audit_source(root: str) -> int:
    ladders = ladders_in_source(root)
    if not ladders:
        print("INSTRUMENT UNAVAILABLE: no ladder literals found under Sources/.")
        return 2
    findings = 0
    print(f"Ladders derived from Sources/ ({len(ladders)} found)\n")
    for (prefix, total) in sorted(ladders):
        steps = ladders[(prefix, total)]
        missing = [n for n in range(1, total + 1) if n not in steps]
        mark = "❌" if missing else "✅"
        emitters = sum(len(v) for v in steps.values())
        print(f"  {mark} {prefix!r} 1..{total}  — {len(steps)}/{total} steps, {emitters} emitters")
        if missing:
            findings += 1
            print(f"       MISSING STEP(S): {missing}")
            print( "       A step with no emitter makes a HEALTHY run look like a death there,")
            print( "       because the ladder's law reads silence as a finding (#882). Either give")
            print( "       the step an emitter — a SKIPPED line counts — or stop announcing it.")
            for n in sorted(steps):
                print(f"         {n}/{total}: {', '.join(steps[n])}")
    terms = terminators_in_source(root, ladders)
    unknown = 0
    print("\n  ALL-CAPS outcome words after a ladder prefix (#908/#914):")
    if terms:
        unknown = 0
        for where, prefix, word, numbered, completes in terms:
            known_word = "" if word in TERMINAL_WORDS else "   ⚠️ NOT IN TERMINAL_WORDS"
            unknown += 1 if known_word else 0
            print(f"    · {where}  {prefix} … {word}{known_word}")
            print(f"        {census_effect(word, numbered, completes)}")
        print("    ⭐ The list is a census of WORDS, not of rescues — it over-collects on")
        print("    purpose so a NEW word shows up instead of silently reading as a death.")
        print("    RESCUE IS CONDITIONAL and the line above says only what the WORD allows:")
        print("    `ladder_verdicts` rescues a ladder only when the terminator FOLLOWS its")
        print("    last rung and that rung is short of `total`. A terminator before the rungs")
        print("    leaves a death; one after a COMPLETE ladder leaves `done`.")
        print("    A numbered skip is not RESCUED at all: once a number is present, the form")
        print("    that walks on and the form that returns are the SAME STRING in a log.")
        print("    #957: not rescued is not the same as read as a death. A skip on the LAST")
        print("    rung leaves a COMPLETE ladder, so its log reads done — the line above says")
        print("    which of the two it is, because saying died there contradicted this very")
        print("    tool's own log-mode verdict.")
    else:
        print("    · none — every short ladder in a log will read as a DEATH.")

    if REFUSED:
        print("\n  not read as rungs (numeric shape, no `:` / ` —` / ` SKIPPED` separator):")
        for line in REFUSED:
            print(f"    · {line}")
        print("    If one of these IS a rung, the separator rule above needs widening —")
        print("    they are printed precisely so the rule cannot drop a rung in silence.")
    print()
    # ⚠️ TWO COUNTERS, NOT ONE (#908 review, MEDIUM-4): folding an unknown terminal word into
    # `findings` printed "❌ 1 incomplete ladder(s)" while every ladder was ✅ — a summary
    # naming a repair (find the missing rung) that did not exist.
    if findings:
        print(f"❌ {findings} incomplete ladder(s).")
    elif unknown:
        print(f"⚠️ {unknown} terminal word(s) in Sources/ are unknown to this tool.")
        print("   Every ladder is complete; add the word(s) to TERMINAL_WORDS or their")
        print("   ladders will keep reading as deaths in a log.")
    else:
        print("✅ Every announced step has an emitter.")
    print("\n⚠️ This checks that a step CAN speak, never that it does at run time.")
    return 1 if findings else 0


# ⭐ #908 — THE CONCEPT THE TOOL LACKED: A LINE THAT *ENDS* A LADDER WITHOUT *ADVANCING* IT.
# Before this, `read_log` knew only rungs, so ANY ladder whose last rung was < total read as
# "stopped before its last step … a DEATH AT THAT STEP". That is wrong for every path where
# the code took a documented exit and SAID SO. Two measured cases, both in today's tree:
#   · `session: raise SKIPPED` on a second owner — a healthy two-owner run reported as a death
#     (#906 wrote it NUMBERED, which made it worse; #907 unnumbered it, which only hid it).
#   · `mic: start REFUSED — input format not ready` (`MicrophoneManager`) sits between `2/3`
#     and `3/3`: driven on a synthetic log it prints `❌ 'mic: start' 2/3`, a FALSE DEATH that
#     has been possible since #890 and that NO wording could fix — measured, `2/3 SKIPPED`
#     reads the same and `3/3 SKIPPED` reads ✅ for a step that never ran.
# So the repair belongs here, not in a third rule about how to word a breadcrumb (#907 named
# this as the next slice for exactly that reason).
#
# ⚠️ VOCABULARY IS MEASURED FROM `Sources/`, NOT INVENTED — and the counts that stood here
# were WRONG on all three words while a second census a hundred lines below printed the right
# ones (#908 review). Deleted rather than refreshed: `--source` prints the live census with
# file:line, so no number belongs in a comment (`.claude/rules/context.md` §2). A fourth word
# added in source and not here would silently go back to reading as a death, which is why
# `--selftest` asserts the list against an INDEPENDENT scan.
#
# ⚠️ FAILED IS NOT LIKE THE OTHER TWO. A skip or a refusal is a deliberate exit; a FAILURE is
# the thing the reader is hunting. It ends the ladder just as truly, so it belongs here — but
# it gets its own outcome and stays a FINDING, or a real failure would print as a tidy end.
TERMINAL_WORDS = ("SKIPPED", "REFUSED", "FAILED", "OK")
BENIGN_TERMINALS = ("SKIPPED", "REFUSED", "OK")
# ⭐ #973 — A SUCCESS WORD IS A PROMISE, and that is what makes the next verdict derivable.
# `SKIPPED`/`REFUSED` say "we are not doing this"; `OK` says "we DID it, and it worked". A
# ladder that bothers to announce success explicitly therefore announces it EVERY time it
# succeeds — so on such a ladder, silence after the last rung is not completeness, it is a
# process that died inside the call the last rung stands before.
SUCCESS_TERMINALS = ("OK",)

# ⛔ #969 — `OK` WAS MISSING AND THAT MADE THE TOOL CRY WOLF ON EVERY HEALTHY LAUNCH. The happy
# path of `AudioEngine.start()` emits `start 1/2` and then `start OK — audio output active`;
# `start 2/2` is written ONLY on the retry. So a perfectly good launch reached 1 of 2 rungs with
# no terminator the tool knew, and printed `❌ … did not reach their last step`, exit 1. That is
# the mirror of the false green #967 fixed, and the worse half: an instrument that flags every
# healthy run teaches its reader to ignore the flag. Measured, not reasoned — driven on a
# two-line log.
#
# ⚠️ AND `OK` IS TWO LETTERS, WHICH THE DISCOVERY CENSUS CANNOT SEE. `terminator_pattern` scans
# for the SHAPE `[A-Z]{3,}` on purpose, so that a word nobody has taught the tool still shows up
# instead of silently reading as a death. Loosening that to `{2,}` was measured and rejected: it
# adds 18 hits of which 15 are prose ("unit-tested on CI", "off IS the level", "the hands-on VJ
# panel"), a 5:1 noise ratio in the one listing that exists to be read. Known short words are
# therefore added to the pattern BY NAME, and that half is self-confirming — see the ⚠️ in
# `terminator_pattern`.


def ladder_verdicts(lines: list[str],
                    known: set[tuple[str, int]],
                    announced: "set[str] | None" = None) -> dict[tuple[str, int], dict]:
    """Walk a log ONCE and decide each ladder's outcome. Pure, so the selftest can drive
    the real thing rather than a re-implementation of it (#416: one definition per rule).

    Three outcomes, and the middle one is what #908 adds:
      · `done`  — the last rung reached `total`.
      · `ended` — the last rung is short of `total` AND a terminator for that ladder stands
                  at or after it. The code stopped ON PURPOSE and named the reason; the line
                  itself is the diagnosis. NOT a finding.
      · `died`  — short, with no terminator after it. Silence between two rungs, i.e. the
                  original finding this tool exists for.

    ⛔ A NUMBERED SKIP IS **NOT** A TERMINATOR, AND THE FIRST VERSION OF #908 GOT THIS WRONG
    IN THE EXPENSIVE DIRECTION. It recorded `on 4/5 SKIPPED` as a terminator too, so a log
    whose LAST line is that rung printed `⏹ ended`, exit 0 — while in `AudioEngine` control
    falls straight out of that `else` into `on 5/5: installing input tap`, i.e. that log is a
    DEATH INSIDE `installTap`, the exact `isInputConnToConverter` region the ladder exists
    for. The tool told the reader not to look there. Driven and reproduced before the fix.

    ⭐ THE REASON IT CANNOT BE RESCUED BY A CLEVERER RULE: in the LOG, `on 4/5 SKIPPED` (walks
    on) and `raise 1/2 SKIPPED` (returns) are the SAME SHAPE. Nothing in the line says which.
    So a numbered skip is AMBIGUOUS by construction and must keep reading as a death, and the
    Swift-side ban on numbering a skip that RETURNS (guard claim (c3)) is load-bearing after
    all — #908's first draft retired it and that was the mistake. An UNNUMBERED terminator is
    unambiguous: it claims no step, so it can only mean "this ladder stops here".
    """
    progress: dict[tuple[str, int], tuple[int, int, str]] = {}
    terminal: dict[tuple[str, int], tuple[int, str, str]] = {}
    # ⛔ #971 — `terminal` KEEPS ONLY THE LAST HIT, AND THAT HID FAILURES OUTRIGHT. Both dicts
    # are unconditional overwrites, so `on 1..5` → `on FAILED` → `on 1..5` again reported
    # `✅ 'on' 5/5` and `✅ Every ladder that appears reached its last step`, exit 0 — the
    # FAILED line was not even PRINTED. Monitoring is toggled repeatedly in one session and
    # `on`/`off` are real ladders, so this is the ordinary shape, not a corner. Driven.
    hostile_seen: dict[tuple[str, int], list[tuple[int, str]]] = {}
    words = "|".join(TERMINAL_WORDS)
    for idx, line in enumerate(lines):
        rungs: dict[tuple[str, int], tuple[int, int, int]] = {}    # key -> (step, lo, hi)
        terms: dict[tuple[str, int], tuple[str, int, int]] = {}    # key -> (word, lo, hi)
        for (prefix, total) in known:
            pat = re.escape(prefix)
            m = re.search(rf"\b{pat}\s+(\d{{1,2}})/{total}\b", line)
            if m:
                rungs[(prefix, total)] = (int(m.group(1)), m.start(), m.end())
            # UNNUMBERED only — see the ⛔ above. A numbered skip stays a rung and nothing else.
            tm = re.search(rf"\b{pat}\s+({words})\b", line)
            if tm:
                terms[(prefix, total)] = (tm.group(1), tm.start(), tm.end())

        # ⛔ #908 — LONGEST PREFIX WINS, AND THIS IS NOT THEORETICAL: the FIRST version of
        # the terminator scan minted a phantom `⏹ 'start' 0/2` out of the line
        # `mic: start REFUSED — …`, because `\bstart` matches happily after `mic: `. Caught by
        # driving the tool, not by reading it. The rung scan had the SAME latent collision and
        # was safe only by accident — `start` is 1..2 and `mic: start` is 1..3, so the totals
        # never agreed. A future ladder with matching totals would have made it real, so the
        # filter covers both scans.
        spans: list[tuple[str, int, int]] = (
            [(k[0], lo, hi) for k, (_s, lo, hi) in rungs.items()]
            + [(k[0], lo, hi) for k, (_w, lo, hi) in terms.items()])

        def shadowed(prefix: str, lo: int) -> bool:
            """True when a LONGER prefix matched a span CONTAINING this one.

            ⚠️ The span test is not decoration (#908 review, LOW-1): a whole-line rule drops a
            genuine `start 1/2` rung from a line that also carries `mic: start REFUSED`, and
            the first repair still did, because it searched the line for the bare prefix and
            found the copy inside the longer one. Only a containing MATCH is a collision; two
            ladders mentioned on one line are two ladders.
            """
            return any(other != prefix and other.endswith(prefix)
                       and o_lo <= lo < o_hi for other, o_lo, o_hi in spans)

        for key, (step, lo, _hi) in rungs.items():
            if not shadowed(key[0], lo):
                progress[key] = (step, idx, line)
        for key, (word, lo, _hi) in terms.items():
            if not shadowed(key[0], lo):
                terminal[key] = (idx, line, word)
                if word not in BENIGN_TERMINALS:
                    hostile_seen.setdefault(key, []).append((idx, line))

    out: dict[tuple[str, int], dict] = {}
    for key in set(progress) | set(terminal):
        step, idx, line = progress.get(key, (0, -1, ""))
        term = terminal.get(key)
        # ⛔ #967 — `step >= total` USED TO SHORT-CIRCUIT TO `done` BEFORE THE TERMINATOR WAS
        # EVEN LOOKED AT, so a ladder that ran to its last rung and THEN reported a failure
        # printed `✅ done` and, with no other finding in the log, `✅ Every ladder that appears
        # reached its last step`. That is not a corner: it is the shape #964 had just shipped —
        # `start 1/2` → `start 2/2` → `start FAILED — the retry threw` — i.e. a start that
        # failed reading as a healthy one, in the instrument a triager opens FIRST. The #937
        # defect inside the tool, exactly the class this file keeps finding elsewhere.
        # A FAILED that FOLLOWS the last rung now wins; a BENIGN one still does not (a
        # `SKIPPED` after a complete ladder is a documented tidy exit, #907).
        if (term is not None and term[0] >= idx
                and term[2] not in BENIGN_TERMINALS):
            verdict = "failed"
            line = term[1]
            idx = term[0]
        elif step >= key[1]:
            # ⛔ #973 — `done` USED TO BE THE END OF IT, AND FOR AN ANNOUNCING LADDER THAT WAS A
            # FALSE GREEN ON THE EXACT CRASH THE LADDER EXISTS FOR. `start 2/2` stands BEFORE
            # `try masterEngine.start()`; a run that recovered writes `start OK after session
            # reconfigure` next, and a run that failed writes `start FAILED`. Neither present
            # means the process died INSIDE the retry — the `isInputConnToConverter` region.
            # Driven: that log printed `✅ 'start' 2/2` and `✅ Every ladder … reached its last
            # step`, exit 0 — while the SAME crash one attempt earlier correctly read `❌ 1/2`.
            # Backwards: the strictly worse run read greener.
            # ⚠️ `announced` is DERIVED, never a hardcoded ladder name: it is the set of
            # prefixes whose `Sources/` census carries a SUCCESS terminator. On today's tree
            # that is exactly `start`; `on`/`off`/`mic:*`/`session:*` complete without one and
            # are untouched. The day another ladder starts announcing success, it joins.
            # ⚠️ NOT `term is None`: a terminator that stands BEFORE the rungs belongs to an
            # EARLIER run of this ladder, so it announces nothing about this one. The test is
            # the same "at or after the last rung" the two branches around it use.
            if (announced and key[0] in announced
                    and not (term is not None and term[0] >= idx)):
                verdict = "unterminated"
            else:
                verdict = "done"
        elif term is not None and term[0] >= idx:
            verdict = "ended"
            line = term[1]
            idx = term[0]
        else:
            verdict = "died"
        # #971: every non-benign terminator for this ladder EXCEPT the one that decided the
        # verdict. On a `done`/`ended` ladder that list is the masked failure; on a `failed`
        # one it is the earlier attempts, which are also real and were also never printed.
        masked = [(i, ln) for (i, ln) in hostile_seen.get(key, []) if i != idx]
        out[key] = {"step": step, "idx": idx, "line": line,
                    "verdict": verdict, "masked": masked}
    return out


def unowned_failures(lines: list[str],
                     known: set[tuple[str, int]]) -> list[tuple[int, str]]:
    """Log lines that report a FAILURE which belongs to NO ladder, as (index, line).

    ⛔ #970 — WITHOUT THIS, THE THREE MOST EXPENSIVE LINES #968 ADDED HAVE NO VERDICT AT ALL.
    `ladder_verdicts` builds its terminator needle from the eight ladder PREFIXES, so a failure
    line whose prefix is not one of them is invisible to it: `session: interruption FAILED`,
    `session: media reset FAILED`, `engine: restart after <ctx> FAILED`. Driven — a log holding
    a complete `session: configure` ladder plus all three printed
    `✅ Every ladder that appears reached its last step`, exit 0. That is the same false green
    #967 was written to remove, on lines shipped one commit later.

    ⛔ AND #968's OWN GUARD HEADER CLAIMED THE OPPOSITE, naming all four ALL-CAPS sites as read
    by this tool when only `mic: stop FAILED` was. The source comment at
    `AudioConfiguration.swift:1008` said the honest thing the whole time. The header is
    corrected in the same commit as this function (#456), because the two are one decision:
    either the tool reads them or the prose must not say it does.

    ⚠️ BENIGN WORDS ARE NOT COLLECTED. An unowned `SKIPPED` is a tidy exit nobody is waiting
    on; only a non-benign word is a finding by itself. And a line already attributed to a
    ladder is excluded, so a `mic: stop FAILED` is reported once, by the ladder that owns it.

    ⛔ #974 — THE PRINTED BLOCK USED TO ENUMERATE THREE SITES AND SAY "ON THOSE THREE AUDIO IS
    DEAD", AND BOTH HALVES WERE WRONG. Measured on this tree, an unowned `FAILED` has SIX
    shapes, not three — and `input: select FAILED` / `input: system default FAILED`
    (`AudioInputManager`) leave audio playing on the previous input, so the claim was false for
    a third of what the block collects. Worse, the SAME COMMIT that wrote it (#970) had just
    retracted "audio dead" as a false discriminator in the guard header one directory over. A
    retraction only counts in every home (#456). The enumeration is deleted rather than
    corrected to six: a count of call sites in a printed paragraph is a date, not a fact
    (#818), and "the ladder model has no verdict for these — read them" was always the whole
    honest content.

    ⚠️ THE PREFIX IS NOT PARSED. This deliberately does not try to name which subsystem failed
    — it says "here is a failure line the ladder model has no verdict for, read it". Guessing
    a prefix would be the `census_effect` mistake: a claim about control flow that a line
    scanner cannot make.
    """
    hostile = [w for w in TERMINAL_WORDS if w not in BENIGN_TERMINALS]
    if not hostile:
        return []
    word_pat = re.compile(r"(?:^|[^A-Za-z])(" + "|".join(re.escape(w) for w in hostile) + r")\b")
    owned_pat = [re.compile(rf"\b{re.escape(prefix)}\s+(" + "|".join(TERMINAL_WORDS) + r")\b")
                 for (prefix, _total) in known]
    out: list[tuple[int, str]] = []
    for idx, line in enumerate(lines):
        if not word_pat.search(line):
            continue
        if any(pat.search(line) for pat in owned_pat):
            continue
        out.append((idx, line))
    return out


def read_log(path: str, root: str) -> int:
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        print(f"INSTRUMENT UNAVAILABLE: cannot read {path}: {exc}")
        return 2
    lines = [ln.rstrip("\n") for ln in text.split("\n") if ln.strip()]
    if not lines:
        print(f"INSTRUMENT UNAVAILABLE: {path} is empty.")
        return 2

    ladders = ladders_in_source(root)
    known = {(p, t) for (p, t) in ladders}
    # #973: prefixes whose Sources/ census carries a SUCCESS terminator — derived, never named.
    announced = {prefix for (_where, prefix, word, numbered, _c)
                 in terminators_in_source(root, ladders)
                 if word in SUCCESS_TERMINALS and not numbered}

    print(f"{path} — {len(lines)} non-empty lines\n")
    segments = split_segments(lines)
    if len(segments) > 1:
        print(f"  ⚠️ This export holds {len(segments)} RUNS, not one (#972). "
              "`EchoelCrashLog.diagnosticsExport`")
        print("     appends an EARLIER run that ended badly AFTER the current one, so the file")
        print("     is not chronological. Each run is read on its own below; reading them as")
        print("     one made the older, crashed run win every `last wins, per ladder` verdict.")
        print()
    worst = 0
    for label, offset, chunk in segments:
        if len(segments) > 1:
            print(f"  ═══ {label} — lines {offset + 1}..{offset + len(chunk)}")
        worst = max(worst, report_segment(chunk, known, offset, announced))
        if len(segments) > 1:
            print()
    # #972: ONCE, after every segment. Printing it inside `report_segment` repeated the
    # caveat per run, and a caveat that repeats is a caveat that stops being read.
    print("⚠️ A completed ladder does not mean the run was healthy — it means no rung was")
    print("   the last thing written. The crash may be anywhere the ladder does not reach.")
    return worst


def split_segments(lines: list[str]) -> list[tuple[str, int, list[str]]]:
    """Split a pasted export into its RUNS, as (label, offset in `lines`, that run's lines).

    ⛔ #972 — THE TOOL HAD NO IDEA THIS FILE COULD HOLD TWO PROCESSES, and the consequence was
    not a missing feature but an INVERTED verdict. `EchoelCrashLog.diagnosticsExport` builds the
    pasted artifact as `current + "\n\n" + retainedCrashHeader + "\n" + retainedCrash` — the
    CURRENT run first, an EARLIER run that ended badly appended after it. So the file is not
    chronological, and `ladder_verdicts`' "last wins, per ladder" handed every verdict to the
    older, crashed process. Driven: a current run with a genuine `mic: stop FAILED` plus an
    appended crash holding a complete `mic: stop 1..3` printed `✅ 'mic: stop' 3/3` and demoted
    the real failure into #971's MASKED block — which then narrated "the run failed, was
    retried, and the retry succeeded" about a run that ended in SIGABRT BEFORE it.

    ⚠️ THE MARKER IS NOT SPELLED HERE TWICE. `EchoelCrashLog.retainedCrashHeader` is the one
    definition (#416); this matches its stable, human-readable core rather than the whole line,
    because the parenthetical after it is prose that may be reworded. If the header is renamed
    outright, this returns one segment and the tool is back to its pre-#972 behaviour — which is
    why the split is REPORTED in the output rather than done silently.
    """
    cut = None
    for idx, line in enumerate(lines):
        if "RETAINED CRASH" in line:
            cut = idx
            break
    if cut is None:
        return [("the run", 0, lines)]
    current = lines[:cut]
    retained = lines[cut + 1:]
    out: list[tuple[str, int, list[str]]] = []
    if current:
        out.append(("THE CURRENT RUN (the one you just exported)", 0, current))
    if retained:
        out.append(("AN EARLIER RUN THAT ENDED BADLY (appended, not later in time)",
                    cut + 1, retained))
    return out or [("the run", 0, lines)]


def report_segment(lines: list[str], known: set[tuple[str, int]], offset: int,
                   announced: "set[str] | None" = None) -> int:
    """Everything `read_log` used to do inline, for ONE run. `offset` keeps every printed line
    number pointing at the ORIGINAL file, so a triager can still find the line by eye."""
    for head in lines[:2]:
        print(f"  header │ {head[:110]}")
    print(f"  last   │ {lines[-1][:110]}\n")

    verdicts = ladder_verdicts(lines, known, announced)
    orphans = unowned_failures(lines, known)

    if not any(v["step"] > 0 for v in verdicts.values()):
        print("  No ladder rung appears in this log.")
        print("  That is a FINDING about the log, not about the code: either it predates the")
        print("  ladder, or the breadcrumb sink never opened (`EchoelCrashLog.begin()`).")
        # #970: this branch returns before the report below, so an orphan failure in a
        # rung-less log would be swallowed by the one exit that already knows it is a finding.
        for idx, line in orphans:
            print(f"  ⚠️ line {idx + 1 + offset}: {line[:110]}")
        return 1

    findings = 0
    ended = 0
    failed = 0
    incomplete = 0
    unterminated = 0
    masked: list[tuple[int, str, str]] = []
    print("  Ladder                      last step    where")
    for (prefix, total) in sorted(verdicts):
        v = verdicts[(prefix, total)]
        step, idx = v["step"], v["idx"]
        # #972: "OF THIS RUN", not "OF LOG" — an export can hold two runs, and the last line
        # of the first one is not the last line of the file.
        tail = " ← LAST LINE OF THIS RUN" if idx == len(lines) - 1 else ""
        flag = {"done": "  ✅", "ended": "  ⏹", "failed": "  ⚠️", "died": "  ❌",
                "unterminated": "  ❌"}[v["verdict"]]
        findings += 1 if v["verdict"] in ("died", "failed", "unterminated") else 0
        unterminated += 1 if v["verdict"] == "unterminated" else 0
        ended += 1 if v["verdict"] == "ended" else 0
        failed += 1 if v["verdict"] == "failed" else 0
        # #967: COMPLETENESS is its own question. A ladder can reach its last rung AND report a
        # failure after it; saying "did not reach their last step" about that one is false, and
        # printing nothing about it was how the failure went invisible in the first place.
        # ⛔ #969 — AND THE FIRST FORM OF THIS LINE (`step < total`) COUNTED THE `ended` CASE
        # TOO, so a documented tidy exit printed BOTH `⏹ … ended DELIBERATELY short … That is
        # not a death` AND `❌ … a DEATH AT THAT STEP`, four lines apart, in the instrument a
        # triager opens first. Before #967 the ❌ block was gated on `findings`, which excludes
        # `ended`; widening it to a pure completeness test lost that. The rule is the union of
        # both intents: short AND not a deliberate exit.
        incomplete += 1 if step < total and v["verdict"] != "ended" else 0
        for i, ln in v["masked"]:
            masked.append((i, prefix, ln))
        print(f"  {flag} {prefix!r:<26} {step}/{total}      line {idx + 1 + offset}{tail}")
    print()
    if ended:
        print(f"⏹ {ended} ladder(s) stopped before their last rung AND SAID WHY (#908).")
        print("   Not a death: the code left by a named exit. READ THAT LINE — it is the")
        print("   diagnosis, and it is one of TWO kinds (#969). Either the run stopped early")
        print("   on purpose (`mic: start REFUSED — input format not ready`, a second owner")
        print("   meeting a route already raised), or it SUCCEEDED before an optional rung")
        print("   (`start OK — audio output active`: `start 2/2` is the RETRY, so a healthy")
        print("   launch is a one-rung ladder). The word tells you which.")
    if failed:
        print(f"⚠️ {failed} ladder(s) ended on a FAILED line — a finding, not a tidy exit.")
        print("   READ THAT LINE: it names the error the code caught. On a SHORT ladder the")
        print("   steps after it did not run; on a COMPLETE one the run reached its last step")
        print("   and failed anyway — #967, which is the shape a retry-then-degrade writes.")
    if unterminated:
        print(f"❌ {unterminated} ladder(s) reached the last rung and NEVER SAID HOW IT WENT"
              " (#973).")
        print("   These ladders announce their own outcome — a success word, not just a rung.")
        print("   The last rung stands BEFORE the call it describes, so a rung with no outcome")
        print("   after it means the process died INSIDE that call. Completeness is not the")
        print("   success signal here; the outcome line is, and it is missing.")
    if masked:
        print(f"⚠️ {len(masked)} FAILED line(s) are MASKED BY A LATER RUN of the same ladder"
              " (#971).")
        print("   The verdict above describes the LAST run only, because a ladder's progress")
        print("   and its terminator are both overwritten each time it starts again. These")
        print("   lines happened and are NOT that verdict — read them. What came after each")
        print("   one is whatever the verdict says: it may have been retried and worked, or")
        print("   the ladder may have died or failed anyway. This block does not know which.")
        for idx, prefix, line in sorted(masked):
            print(f"     line {idx + 1 + offset} ({prefix}): {line[:92]}")
    if orphans:
        print(f"⚠️ {len(orphans)} line(s) report a FAILURE that belongs to NO ladder (#970).")
        print("   The ladder model has no verdict for these — read them. Before #970 a log")
        print("   holding nothing but these still printed the green line and exited 0.")
        for idx, line in orphans:
            print(f"     line {idx + 1 + offset}: {line[:104]}")
    if incomplete:
        print(f"❌ {incomplete} ladder(s) did not reach their last step.")
        print("   Since #882 every numbered step emits even when skipped, so a gap in a ladder")
        print("   written after that is a DEATH AT THAT STEP — the rung stands before its call.")
        print("   ⚠️ Check the ladder is one of the post-#882 ones before concluding that;")
        print("   `--source` lists which ladders are complete in today's tree.")
    elif not ended and not failed and not orphans and not masked and not unterminated:
        print("✅ Every ladder that appears reached its last step.")
    return 1 if findings or orphans or masked else 0


def selftest(root: str) -> int:
    ok = True

    def check(name: str, cond: bool) -> None:
        nonlocal ok
        print(("  PASS " if cond else "  FAIL ") + name)
        ok &= cond

    print("selftest — the needle must match what it is pointed at\n")
    samples = [
        ("on 1/5: stopping engine + claiming record route", "on", 1, 5),
        ("on 4/5 SKIPPED: engine was not running", "on", 4, 5),
        ("off 5/5: restoring engine if stranded (wasRunning: true)", "off", 5, 5),
        ("mic: stop 2/3 — removing input tap", "mic: stop", 2, 3),
        ("session: configure 4/4 — setActive", "session: configure", 4, 4),
        ("startup 3/4: audio engine started OK", "startup", 3, 4),
    ]
    for literal, prefix, step, total in samples:
        m = RUNG.match(literal)
        check(f"{literal[:44]!r} → {prefix!r} {step}/{total}",
              bool(m) and m.group("prefix").strip() == prefix
              and int(m.group("step")) == step and int(m.group("total")) == total)

    # Negatives: prose that must NOT be read as a rung.
    for literal in ["latency 12/48 ms measured", "", "trigger#1 step=3 notes=4"]:
        m = RUNG.match(literal)
        matched = bool(m) and int(m.group("total")) >= 2 and int(m.group("step")) >= 1
        # "latency 12/48" is a legal shape; it is excluded by step<=total, not by the regex.
        if literal.startswith("latency"):
            matched = matched and int(m.group("step")) <= int(m.group("total"))
        check(f"not a rung: {literal[:40]!r}", not matched)

    # ⭐ The end-to-end claim: derived-from-source must see the ladders #882 completed.
    try:
        ladders = ladders_in_source(root)
    except RuntimeError as exc:
        print(f"  FAIL could not read Sources/: {exc}")
        return 2
    for prefix, total in (("on", 5), ("off", 5), ("mic: stop", 3), ("session: configure", 4)):
        steps = ladders.get((prefix, total), {})
        check(f"source ladder {prefix!r} 1..{total} is complete",
              all(n in steps for n in range(1, total + 1)))

    # ⭐ #908 — THE VERDICT LOGIC, DRIVEN END TO END rather than reasoned about. Each case
    # below is a log this repo actually produced or would produce; the first two are the
    # measured defects that motivated the change. Driving `ladder_verdicts` itself (not a
    # copy of its rules) is the point — #416.
    mic = ["mic: start 1/3 — claiming record route", "mic: start 2/3 — tapping input"]
    raise2 = ["session: raise 1/2 — setCategory(.playAndRecord)",
              "session: raise 2/2 — setActive"]
    for name, lines, key, want in [
        ("a mid-ladder REFUSED is an END, not a death (#890 path)",
         mic + ["mic: start REFUSED — input format not ready"], ("mic: start", 3), "ended"),
        # #906's wording stays a DEATH on purpose: in a log it cannot be told apart from a
        # skip that walks on. The repair for it is the guard-side ban (c3), not this tool.
        ("#906's numbered wording is ambiguous and stays a DEATH",
         ["session: raise 1/2 SKIPPED: category already .playAndRecord"],
         ("session: raise", 2), "died"),
        ("an unnumbered skip after a complete run is still DONE (#907 wording)",
         raise2 + ["session: raise SKIPPED — category already .playAndRecord"],
         ("session: raise", 2), "done"),
        ("silence after a rung is still a DEATH — the finding this tool exists for",
         mic, ("mic: start", 3), "died"),
        # ⛔ THE ONE #908's FIRST DRAFT GOT BACKWARDS, and its own selftest blessed it (#367).
        # `on 4/5 SKIPPED` WALKS ON — `on 5/5: installing input tap` follows it in
        # `AudioEngine` — so a log ending there is a death INSIDE `installTap`, the
        # `isInputConnToConverter` region this ladder exists for. In the LOG that line is
        # indistinguishable from a numbered skip that RETURNS, so it must stay a death.
        ("a NUMBERED skip is ambiguous in a log and stays a DEATH",
         ["on 1/5: a", "on 4/5 SKIPPED: engine was not running"], ("on", 5), "died"),
        ("a FAILED terminator is its own outcome, never a tidy end",
         ["mic: start 1/3 — a", "mic: start FAILED (route lost)"], ("mic: start", 3), "failed"),
        # ⛔ #967 — THE CASE THAT READ GREEN. `step >= total` short-circuited to `done` before
        # the terminator was looked at, so a ladder that reached its last rung and THEN failed
        # printed `✅ done` and the summary said every ladder reached its last step. This is
        # the exact log #964's retry-then-degrade path writes.
        ("a FAILED after the LAST rung is still a failure, not a tidy done",
         ["session: raise 1/2 — a", "session: raise 2/2 — b",
          "session: raise FAILED (the retry threw)"], ("session: raise", 2), "failed"),
        # …and the counterweight, so the repair does not swallow the #907 rule with it:
        # a BENIGN terminator after a complete ladder is still a documented tidy exit.
        ("a SKIPPED after the LAST rung stays done (#907 is not undone by #967)",
         raise2 + ["session: raise SKIPPED — category already .playAndRecord"],
         ("session: raise", 2), "done"),
    ]:
        got = ladder_verdicts(lines, {key}).get(key, {}).get("verdict")
        check(f"{name} → {want}", got == want)

    # ⛔ THE PHANTOM LADDER THIS CAUGHT ON ITS FIRST RUN: `\bstart` matches inside
    # `mic: start REFUSED`, so the first version minted `⏹ 'start' 0/2` out of thin air.
    # Longest prefix wins now; this pins it, because the rung scan had the same latent
    # collision and was safe only because the two totals happened to differ.
    both = {("mic: start", 3), ("start", 2)}
    check("a longer prefix shadows a shorter one on the same SPAN",
          ("start", 2) not in ladder_verdicts(
              ["mic: start REFUSED — input format not ready"], both))
    # …and does NOT shadow a genuine hit elsewhere on the line (#908 review, LOW-1).
    mixed = ladder_verdicts(
        ["mic: start REFUSED — retrying; start 1/2: starting master engine"], both)
    check("a second ladder on the same line survives the shadow filter",
          mixed.get(("start", 2), {}).get("step") == 1)

    # The vocabulary is asserted against an INDEPENDENT scan (any ALL-CAPS token after a
    # ladder prefix), never against the word list itself — see terminators_in_source.
    census = terminators_in_source(root, ladders)
    used = {w for (_where, _p, w, _n, _c) in census}
    check(f"every terminal word in Sources/ is known: {sorted(used)}",
          used.issubset(set(TERMINAL_WORDS)))

    # ⛔ #969 — THE SHORT-WORD ARM OF THE CENSUS PATTERN SURVIVED ITS OWN MUTATION. Deleting it
    # (`word = "[A-Z]{3,}"`) left the whole selftest GREEN, because the check above is a SUBSET
    # assertion: finding fewer words still satisfies it. So the census would silently stop
    # listing every `start OK` site while `ladder_verdicts` kept acting on them — a listing that
    # is read as complete and is not. Driven on a LITERAL, not on the tree, so it does not go
    # red the day that one call site is reworded (#914's lesson about pinning `Sources/`).
    short_words = [w for w in TERMINAL_WORDS if len(w) < 3]
    short_pat = census_pattern(["start"])
    check(f"a known SHORT terminal word is still discoverable by the census {short_words}",
          all(short_pat.search(f"engine: start {w} — audio output active") is not None
              for w in short_words) and bool(short_words))

    # #914 — drive the REAL matcher and the REAL labeller on LITERALS.
    # ⛔ The first version of this check was `any(numbered) and any(not numbered)` over the
    # tree. It survived a full inversion of the flag (every unnumbered terminator would have
    # printed "does not rescue" and vice versa) and went RED for a legitimate future tree with
    # no numbered skip left — i.e. it pinned `Sources/`, not the code under review.
    cpat = census_pattern(["mic: start", "on"])

    def numbered_of(line: str):
        m = cpat.search(line)
        return None if m is None else (m.group(1), m.group(3), m.group(2) is not None)

    # #957 — the LAST-RUNG case, driven through the two pure functions rather than through a
    # re-implementation. ⛔ Before this, `census_effect` printed "still reads as ❌ died" for a
    # numbered skip at `N/N`, while `ladder_verdicts` on the same log prints `done` — the tool
    # contradicting itself, which is exactly what a triager acts on.
    check("a skip on the LAST rung is labelled as completing, not as a death",
          "✅ done" in census_effect("SKIPPED", True, completes_ladder("5/5 ", 5))
          and "❌ died" not in census_effect("SKIPPED", True, completes_ladder("5/5 ", 5)))
    check("a skip on a MIDDLE rung keeps the cautious wording",
          "❌ died" in census_effect("SKIPPED", True, completes_ladder("4/5 ", 5)))
    check("a rung whose total disagrees with the ladder cannot claim completion",
          completes_ladder("3/3 ", 5) is False)
    check("an unparsable or absent rung cannot claim completion",
          completes_ladder(None, 5) is False and completes_ladder("x/y ", 5) is False)
    # And the verdict this label now agrees with, measured rather than asserted from memory.
    check("a log ending on a LAST-rung skip really does read as done",
          ladder_verdicts(["on 1/5: a", "on 2/5: b", "on 3/5: c", "on 4/5: d",
                           "on 5/5 SKIPPED: tap already installed"],
                          {("on", 5)}).get(("on", 5), {}).get("verdict") == "done")

    check("a numbered skip is read as numbered",
          numbered_of("monitor: on 4/5 SKIPPED: engine was not running")
          == ("on", "SKIPPED", True))
    check("an unnumbered skip is read as unnumbered",
          numbered_of("monitor: on SKIPPED — monitoring already engaged")
          == ("on", "SKIPPED", False))
    check("the longer ladder prefix wins in the census too",
          (numbered_of("mic: start REFUSED — input format not ready") or (None,))[0]
          == "mic: start")
    # The labels themselves, including the two the first draft got backwards.
    check("an unknown word is NOT sold as ending a ladder",
          "ends NOTHING" in census_effect("ABORTED", False)
          and "died" in census_effect("ABORTED", False))
    check("a numbered terminator does not claim a rescue",
          "does NOT rescue" in census_effect("SKIPPED", True))
    check("an unnumbered benign terminator rescues, and says it must FOLLOW the rung",
          "ended" in census_effect("SKIPPED", False)
          and "FOLLOWS" in census_effect("SKIPPED", False))
    check("FAILED keeps its own outcome and stays a finding",
          "failed" in census_effect("FAILED", False)
          and "finding" in census_effect("FAILED", False))
    # #967: the label used to say "rescues a SHORT ladder", which described only half of what
    # the verdict now does — and the half it left out was the one that printed a false green.
    check("the FAILED label no longer restricts itself to a SHORT ladder",
          "SHORT" not in census_effect("FAILED", False)
          and "complete" in census_effect("FAILED", False))
    check("the BENIGN label still says it must FOLLOW and still ends tidily",
          "FOLLOWS" in census_effect("SKIPPED", False)
          and "ended" in census_effect("SKIPPED", False))

    # ⛔ AND THE CHECKS ABOVE ARE STILL NOT ENOUGH ON THEIR OWN — measured, not reasoned.
    # They drive `census_pattern` and `census_effect` directly, so inverting the flag WHERE THE
    # TUPLE IS BUILT (`m.group(2) is not None` in `terminators_in_source`) left the selftest
    # green. That is the #914 review's MEDIUM-4 defect moved one step, not fixed: the composed
    # path had no witness. This closes it WITHOUT pinning which shapes the tree happens to
    # contain — every census entry must agree with what the matcher says about its own source
    # line, so an inversion disagrees on the first numbered entry and a legitimate tree change
    # cannot redden it.
    mismatched = []
    for where, prefix, word, numbered, _completes in census:
        rel, _, lineno = where.rpartition(":")
        try:
            line = open(os.path.join(root, rel), encoding="utf-8").read().split("\n")[int(lineno) - 1]
        except (OSError, ValueError, IndexError):
            continue
        for m in census_pattern(sorted({p for (p, _t) in ladders}, key=len, reverse=True)) \
                .finditer(line):
            if m.group(1) == prefix and m.group(3) == word:
                if (m.group(2) is not None) != numbered:
                    mismatched.append(where)
                break
    check(f"every census entry agrees with its own source line about the number "
          f"({len(census)} entries)", not mismatched and bool(census))

    # ⭐ #967 — THE PRINTER, DRIVEN END TO END THROUGH `read_log`. Every check above drives the
    # two PURE functions; the false green was PRINTED, and mutating the printer (making
    # `incomplete` count verdicts again, or restoring the unconditional `elif not ended:`) left
    # this selftest GREEN. Same composition gap as #962/#963/#965 — what bites is the
    # composition, not the part — and here it is the part a triager actually reads.
    with tempfile.TemporaryDirectory(prefix="diag-ladder-selftest-") as tmp:
        def verdict_text(name: str, body: str) -> tuple[int, str]:
            path = os.path.join(tmp, name)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(body)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = read_log(path, root)
            return rc, buf.getvalue()

        GREEN = "Every ladder that appears reached its last step"
        # #972: the marker as `EchoelCrashLog.retainedCrashHeader` writes it. Spelled here so a
        # rename of that Swift constant shows up as a RED fixture rather than as a silent
        # return to reading two processes as one.
        EchoelRetainedHeader = "=== RETAINED CRASH (an earlier run that ended badly) ==="
        # A complete, NON-announcing ladder: `on` has no success terminator in Sources/, so it
        # is the counterweight to every claim about the announcing kind (#973).
        good_on = "".join(f"on {n}/5: step {n}\n" for n in range(1, 6))
        SHORT = "did not reach their last step"
        rc, out = verdict_text("complete_then_failed.log",
                               "engine: start 1/2: starting master engine\n"
                               "engine: start 2/2: retry after session reconfigure\n"
                               "engine: start FAILED — the retry threw (err)\n")
        check("a COMPLETE ladder that then FAILED is not printed as a green run",
              GREEN not in out and "ended on a FAILED line" in out and rc == 1)
        check("...and it is not accused of stopping short either, because it did not",
              SHORT not in out)
        rc, out = verdict_text("short_and_failed.log",
                               "engine: start 1/2: starting master engine\n"
                               "engine: start FAILED — the session reconfigure threw (err)\n")
        check("a SHORT ladder that FAILED is both a failure AND incomplete",
              "ended on a FAILED line" in out and SHORT in out and rc == 1)
        # ⛔ #969 RENAMED THIS FIXTURE FROM `healthy.log` AND STILL GOT IT WRONG. #969 was
        # right that `start 2/2` is the RETRY rung, and then called the two-rung log
        # "recovered" — but a run that recovers writes `start OK after session reconfigure`
        # NEXT. Two rungs and nothing after them is a death INSIDE the retry `start()`. So the
        # fixture pinned a false green on the very crash class the ladder exists for, one
        # commit after renaming its predecessor for the identical mistake. Both halves are
        # here now: the death, and a genuinely recovered run.
        rc, out = verdict_text("died_inside_the_retry.log",
                               "engine: start 1/2: starting master engine\n"
                               "engine: start 2/2: retry after session reconfigure\n")
        check("a complete ANNOUNCING ladder with no outcome line is a death, not a green run",
              GREEN not in out and "NEVER SAID HOW IT WENT" in out and rc == 1)
        rc, out = verdict_text("recovered_after_retry.log",
                               "engine: start 1/2: starting master engine\n"
                               "engine: start 2/2: retry after session reconfigure\n"
                               "engine: start OK after session reconfigure\n")
        check("a genuinely recovered run still prints the green line and exits 0",
              GREEN in out and "ended on a FAILED line" not in out and rc == 0)
        rc, out = verdict_text("non_announcing_ladder_completes.log", good_on)
        check("a ladder that does NOT announce success is untouched by the new verdict",
              GREEN in out and "NEVER SAID HOW IT WENT" not in out and rc == 0)
        # ⛔ #973 — WITHOUT THIS FIXTURE THE MUTATION `term is None` SURVIVED. An engine can
        # start, stop and start again in one session, so an earlier `start OK` sits ABOVE the
        # rungs of the later run — and it announces nothing about THAT run. The test has to be
        # "at or after the last rung", the same one the two neighbouring branches use, and no
        # other fixture reached that difference.
        rc, out = verdict_text("outcome_belongs_to_an_earlier_run.log",
                               "engine: start OK — audio output active\n"
                               "engine: start 1/2: starting master engine\n"
                               "engine: start 2/2: retry after session reconfigure\n")
        check("an outcome line ABOVE the rungs does not vouch for the run below it",
              GREEN not in out and "NEVER SAID HOW IT WENT" in out and rc == 1)
        # ⭐ #969 — THE TWO FIXTURES THE PRINTER WAS MISSING, and both were live defects.
        rc, out = verdict_text("healthy_first_attempt.log",
                               "engine: start 1/2: starting master engine\n"
                               "engine: start OK — audio output active\n")
        check("the REAL happy path (one rung, then OK) is not accused of dying",
              SHORT not in out and "SAID WHY" in out and rc == 0)
        rc, out = verdict_text("deliberate_short_exit.log",
                               "mic: start 1/3 — configuring the capture engine\n"
                               "mic: start REFUSED — input format not ready\n")
        check("a documented tidy exit is NOT also accused of stopping short",
              SHORT not in out and "SAID WHY" in out and rc == 0)

        # ⭐ #970 — THE THREE CASES OF `unowned_failures`, DRIVEN THROUGH THE PRINTER. The
        # middle one is the regression guard: a failure its ladder already owns must be
        # reported ONCE, by that ladder, and never appear in the orphan block as well.
        ORPHAN = "belongs to NO ladder"
        rc, out = verdict_text("orphan_failures.log",
                               "engine: session: configure 1/4: a\n"
                               "engine: session: configure 2/4: b\n"
                               "engine: session: configure 3/4: c\n"
                               "engine: session: configure 4/4: d\n"
                               "session: interruption FAILED — could not reactivate (e)\n"
                               "engine: restart after interruption FAILED — e\n")
        check("a FAILURE belonging to no ladder is a finding, not a green run",
              ORPHAN in out and GREEN not in out and rc == 1)
        rc, out = verdict_text("owned_failure.log",
                               "mic: stop 1/3 — a\nmic: stop 2/3 — b\nmic: stop 3/3 — c\n"
                               "mic: stop FAILED — the record route was not released (e)\n")
        check("a failure its ladder OWNS is not double-reported as an orphan",
              ORPHAN not in out and "ended on a FAILED line" in out and rc == 1)
        rc, out = verdict_text("orphan_benign.log",
                               "engine: session: configure 1/4: a\n"
                               "engine: session: configure 2/4: b\n"
                               "engine: session: configure 3/4: c\n"
                               "engine: session: configure 4/4: d\n"
                               "route: release SKIPPED — nobody held it\n")
        check("an unowned BENIGN word is not dragged in as a failure",
              ORPHAN not in out and GREEN in out and rc == 0)

        # ⭐ #971 — THE MASKING CASE AND ITS TWO REGRESSION GUARDS. `on`/`off` are toggled
        # repeatedly in one session, so "failed, retried, retry worked" is the ORDINARY shape.
        MASKED = "MASKED BY A LATER RUN"
        # ⛔ #972 — THIS FIXTURE HELD ONE FAILURE AND #971'S WHOLE MECHANISM IS "COLLECT EVERY,
        # NOT ONLY THE LAST". Replacing `hostile_seen.setdefault(key, []).append(...)` with
        # `hostile_seen[key] = [(idx, line)]` — i.e. the pre-#971 semantics — left the selftest
        # GREEN. With one failure the two are indistinguishable, so the check could not grade
        # the line named in its own commit title. TWO failures, and both line numbers asserted.
        # Same class as the numbered-skip fixture #971 already had to repair: a fixture must
        # REACH the branch it names.
        rc, out = verdict_text("failure_masked_by_retry.log",
                               good_on + "on FAILED — the first one died\n" + good_on
                               + "on FAILED — and so did the second\n" + good_on)
        check("EVERY hidden FAILURE is printed, not just the last one",
              MASKED in out and GREEN not in out
              and "line 6" in out and "line 12" in out and rc == 1)
        rc, out = verdict_text("single_failure_not_masked.log",
                               "mic: stop 1/3 — a\nmic: stop 2/3 — b\nmic: stop 3/3 — c\n"
                               "mic: stop FAILED — the record route was not released (e)\n")
        check("the failure that DECIDED the verdict is not also listed as masked",
              MASKED not in out and "ended on a FAILED line" in out and rc == 1)
        # ⛔ #971 — THIS FIXTURE'S FIRST DRAFT USED `on 4/5 SKIPPED`, A NUMBERED SKIP, AND THE
        # MUTATION "collect benign words too" SURVIVED IT. A numbered line is never a
        # terminator (the c3 rule), so the fixture could not exercise the benign filter at all
        # — it graded nothing while looking like it graded the case in its own name. The
        # terminator has to be UNNUMBERED to be one.
        rc, out = verdict_text("benign_before_a_good_run.log",
                               "on REFUSED — the route was already raised\n" + good_on)
        check("a BENIGN terminator earlier in the log is not reported as a masked failure",
              MASKED not in out and rc == 0)

        # ⭐ #972 — THE TWO-RUN EXPORT. `EchoelCrashLog.diagnosticsExport` appends an EARLIER
        # crashed run AFTER the current one, so the file is not chronological. Read as one, the
        # older run won every `last wins` verdict and #971 then narrated "the retry succeeded"
        # about a process that had already died.
        TWO = "holds 2 RUNS"
        rc, out = verdict_text("export_with_retained_crash.log",
                               "mic: stop 1/3 — a\n"
                               "mic: stop FAILED — the record route was not released (e)\n"
                               "\n" + EchoelRetainedHeader + "\n"
                               "mic: stop 1/3 — a\nmic: stop 2/3 — b\nmic: stop 3/3 — c\n")
        check("a two-run export is split, and the CURRENT run's failure is not demoted",
              TWO in out and "ended on a FAILED line" in out and MASKED not in out and rc == 1)
        check("...and the appended run's line numbers still point at the whole file",
              "line 6" in out)
        rc, out = verdict_text("ordinary_single_run.log", good_on)
        check("an ordinary one-run log is NOT announced as multi-run",
              TWO not in out and GREEN in out and rc == 0)

    print("\n" + ("selftest OK" if ok else "selftest FAILED"))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Read the Echoel crash ladder.")
    ap.add_argument("log", nargs="?", help="path to an echoel_diag.log")
    ap.add_argument("--source", action="store_true", help="audit the ladders in Sources/")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    root = repo_root()
    try:
        if args.selftest:
            return selftest(root)
        if args.source or not args.log:
            return audit_source(root)
        return read_log(args.log, root)
    except RuntimeError as exc:
        print(f"INSTRUMENT UNAVAILABLE: {exc}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
