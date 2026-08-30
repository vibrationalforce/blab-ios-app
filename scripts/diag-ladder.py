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
import os
import re
import subprocess
import sys
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


def terminators_in_source(root: str,
                          ladders: dict[tuple[str, int], dict]) -> list[tuple[str, str, str]]:
    """Every `<ladder prefix> …<ALL-CAPS WORD>` written in `Sources/`, as (where, prefix, word).

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

    ⚠️ IT CANNOT SEE A 1/1 LADDER'S TERMINATOR (#908 review, LOW-6): `ladders_in_source`
    drops `total < 2`, so `session: lower` is not in `names` and its two `SKIPPED` lines do
    not appear here. Harmless — a 1/1 ladder is not tracked in log mode either, so its
    terminator could not change a verdict — and self-correcting the day `lower` grows a
    second step. But "the vocabulary is complete" is a claim about the ladders it can see.
    """
    names = sorted({p for (p, _t) in ladders}, key=len, reverse=True)
    if not names:
        return []
    pat = re.compile(r"(?:^|[^A-Za-z:])(" + "|".join(re.escape(n) for n in names)
                     + r")\s+(?:\d{1,2}/\d{1,2}\s+)?([A-Z]{3,})\b")
    out: list[tuple[str, str, str]] = []
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
                out.append((f"{rel}:{lineno}", m.group(1), m.group(2)))
    return sorted(set(out))


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
    print("\n  terminator lines (end a ladder without advancing it, #908):")
    if terms:
        unknown = 0
        for where, prefix, word in terms:
            known_word = "" if word in TERMINAL_WORDS else "   ⚠️ NOT IN TERMINAL_WORDS"
            unknown += 1 if known_word else 0
            print(f"    · {where}  {prefix} … {word}{known_word}")
        print("    A ladder whose last rung is short of `total` reads as ENDED, not DEAD,")
        print("    when one of these follows it in the log — UNNUMBERED only, see the ⛔ in")
        print("    `ladder_verdicts`. A word flagged above is NOT in the tool's vocabulary,")
        print("    so its ladder still reads as a death — add it.")
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
TERMINAL_WORDS = ("SKIPPED", "REFUSED", "FAILED")
BENIGN_TERMINALS = ("SKIPPED", "REFUSED")


def ladder_verdicts(lines: list[str],
                    known: set[tuple[str, int]]) -> dict[tuple[str, int], dict]:
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

    out: dict[tuple[str, int], dict] = {}
    for key in set(progress) | set(terminal):
        step, idx, line = progress.get(key, (0, -1, ""))
        term = terminal.get(key)
        if step >= key[1]:
            verdict = "done"
        elif term is not None and term[0] >= idx:
            verdict = "ended" if term[2] in BENIGN_TERMINALS else "failed"
            line = term[1]
            idx = term[0]
        else:
            verdict = "died"
        out[key] = {"step": step, "idx": idx, "line": line, "verdict": verdict}
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

    print(f"{path} — {len(lines)} non-empty lines\n")
    for head in lines[:2]:
        print(f"  header │ {head[:110]}")
    print(f"  last   │ {lines[-1][:110]}\n")

    verdicts = ladder_verdicts(lines, known)

    if not any(v["step"] > 0 for v in verdicts.values()):
        print("  No ladder rung appears in this log.")
        print("  That is a FINDING about the log, not about the code: either it predates the")
        print("  ladder, or the breadcrumb sink never opened (`EchoelCrashLog.begin()`).")
        return 1

    findings = 0
    ended = 0
    failed = 0
    print("  Ladder                      last step    where")
    for (prefix, total) in sorted(verdicts):
        v = verdicts[(prefix, total)]
        step, idx = v["step"], v["idx"]
        tail = " ← LAST LINE OF LOG" if idx == len(lines) - 1 else ""
        flag = {"done": "  ✅", "ended": "  ⏹", "failed": "  ⚠️", "died": "  ❌"}[v["verdict"]]
        findings += 1 if v["verdict"] in ("died", "failed") else 0
        ended += 1 if v["verdict"] == "ended" else 0
        failed += 1 if v["verdict"] == "failed" else 0
        print(f"  {flag} {prefix!r:<26} {step}/{total}      line {idx + 1}{tail}")
    print()
    if ended:
        print(f"⏹ {ended} ladder(s) ended DELIBERATELY short and said why (#908).")
        print("   That is not a death: the code took a documented exit and named it. READ THAT")
        print("   LINE — it is the diagnosis, e.g. `mic: start REFUSED — input format not ready`")
        print("   or a second owner meeting a route that was already raised.")
    if failed:
        print(f"⚠️ {failed} ladder(s) ended on a FAILED line — a finding, not a tidy exit.")
        print("   The line names the error the code caught. The steps after it did not run.")
    if findings:
        print(f"❌ {findings} ladder(s) did not reach their last step.")
        print("   Since #882 every numbered step emits even when skipped, so a gap in a ladder")
        print("   written after that is a DEATH AT THAT STEP — the rung stands before its call.")
        print("   ⚠️ Check the ladder is one of the post-#882 ones before concluding that;")
        print("   `--source` lists which ladders are complete in today's tree.")
    elif not ended:
        print("✅ Every ladder that appears reached its last step.")
    print("\n⚠️ A completed ladder does not mean the run was healthy — it means no rung was")
    print("   the last thing written. The crash may be anywhere the ladder does not reach.")
    return 1 if findings else 0


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
    used = {w for (_where, _p, w) in terminators_in_source(root, ladders)}
    check(f"every terminal word in Sources/ is known: {sorted(used)}",
          used.issubset(set(TERMINAL_WORDS)))

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
