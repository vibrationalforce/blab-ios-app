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
    if REFUSED:
        print("\n  not read as rungs (numeric shape, no `:` / ` —` / ` SKIPPED` separator):")
        for line in REFUSED:
            print(f"    · {line}")
        print("    If one of these IS a rung, the separator rule above needs widening —")
        print("    they are printed precisely so the rule cannot drop a rung in silence.")
    print()
    if findings:
        print(f"❌ {findings} incomplete ladder(s).")
    else:
        print("✅ Every announced step has an emitter.")
    print("\n⚠️ This checks that a step CAN speak, never that it does at run time.")
    return 1 if findings else 0


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

    # Walk the log, tracking the newest step seen per ladder and where it sat.
    progress: dict[tuple[str, int], tuple[int, int, str]] = {}
    for idx, line in enumerate(lines):
        for (prefix, total) in known:
            m = re.search(rf"\b{re.escape(prefix)}\s+(\d{{1,2}})/{total}\b", line)
            if m:
                progress[(prefix, total)] = (int(m.group(1)), idx, line)

    if not progress:
        print("  No ladder rung appears in this log.")
        print("  That is a FINDING about the log, not about the code: either it predates the")
        print("  ladder, or the breadcrumb sink never opened (`EchoelCrashLog.begin()`).")
        return 1

    findings = 0
    print("  Ladder                      last step    where")
    for (prefix, total) in sorted(progress):
        step, idx, line = progress[(prefix, total)]
        tail = " ← LAST LINE OF LOG" if idx == len(lines) - 1 else ""
        flag = "  ❌" if step < total else "  ✅"
        findings += 1 if step < total else 0
        print(f"  {flag} {prefix!r:<26} {step}/{total}      line {idx + 1}{tail}")
    print()
    if findings:
        print(f"❌ {findings} ladder(s) stopped before their last step.")
        print("   Since #882 every numbered step emits even when skipped, so a gap in a ladder")
        print("   written after that is a DEATH AT THAT STEP — the rung stands before its call.")
        print("   ⚠️ Check the ladder is one of the post-#882 ones before concluding that;")
        print("   `--source` lists which ladders are complete in today's tree.")
    else:
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
