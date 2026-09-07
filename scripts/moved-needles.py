#!/usr/bin/env python3
"""Which guards anchor on a line this change REMOVES from Sources/? — the diff-time check.

WHY THIS EXISTS (#1092). #1027 lifted the transport row's `HStack(spacing: 8) { … }` out of
`startControlRow` into its own member `transportLine1`, and struck the prose "line 1 is
bit-for-bit what it was" in BOTH of its Sources homes. `TheTransportBarIsDissolvedTests`
anchors on exactly that stack inside exactly that declaration; nobody grepped the bundle, the
guard went RED, and four TestFlight builds (454–458) shipped over it. The CI/CD job log is
`tail -200 test.log` (#807), and the test's line fell outside that window on every run until
#1091's, three days later.

WHY `dead-needles.py` COULD NOT SEE IT, which is the whole reason for a second tool: it asks
"is this needle absent from Sources/?" — and `HStack(spacing: 8) {` was still present in
dozens of places. The guard was red because the needle had left the DECLARATION its scan is
scoped to, not because it had left the tree. Presence in the tree is the wrong question at
diff time. The right one is cheaper and earlier:

    for every line this diff REMOVES from Sources/, which guard files contain that text?

Every hit is a guard to OPEN before committing — a question, not a verdict. The tool cannot
know whether the guard's scan still reaches the text at its new address (that is what the
#1092 repair had to decide by hand); it can only stop the case where nobody looked.

USAGE
    python3 scripts/moved-needles.py                 # working tree + index vs HEAD
    python3 scripts/moved-needles.py HEAD            # HEAD~1..HEAD (the commit just made)
    python3 scripts/moved-needles.py A..B            # any range; guards are read AT B
    python3 scripts/moved-needles.py --selftest      # after touching it

Exit 0 = no removed line is a needle anywhere in the blocking bundle. Exit 1 = at least one
hit — read it, do not obey it. Exit 2 = INSTRUMENT UNAVAILABLE (git failed, or the selftest's
commits are not in this clone): deliberately not a green, per `doctor.py`'s convention.

WHAT IT CLASSIFIES, so the reader knows how alarmed to be:
    gone from Sources   the removed text occurs NOWHERE in Sources/ at the new state — the
                        guard is red (a positive needle) or vacuous (a negative one) unless it
                        was repaired in the same change. The `dead-needles.py` case, seen early.
    still in Sources    the text survives elsewhere. The guard MAY still be green, and that is
                        the dangerous half: it is green only if its scan happens to reach the
                        new address. #1027's three hits were all of this kind.

LIMITS — a checker that overstates its reach is the thing it guards against.
  · Substring only. A guard that assembles its needle (`"HStack(spacing: " + "8) {"`) or
    reads it from a `Self.` constant is invisible here; `dead-needles.py` shape 4/5 owns the
    constant case after the fact.
  · A removed line is matched as a WHOLE, whitespace-trimmed. A guard whose needle is a
    fragment of the line (`"spacing: 8"`) is not found. Widening to fragments was measured
    on #1027: every `.frame(`/`.font(` line lights up half the bundle. Not shipped.
  · Lines shorter than 12 characters, comment-only lines and pure punctuation are skipped —
    a `}` is a needle in every guard and a hit in none.
  · A needle found in more than MAX_GENERIC guard files is reported as ONE line with its
    count and no file list: `#if canImport(AVFoundation)` sits in 18 guards and is nobody's
    anchor. The number is printed, never hidden.
  · Only `Tests/CISmoke/` (the blocking bundle). The non-blocking suite has the same shape
    and is out of scope on purpose — its reds cost nothing today (#208).
  · This does NOT run in CI (`scripts/*.py` is executed by no workflow, pinned by
    `TheLawFileNeverReachesMainByItselfTests`). It is a pre-commit habit, which is exactly
    the moment #1027 lacked.

KNOWN POSITIVE (§4 of Tests/CISmoke/CLAUDE.md): the selftest drives the real code path over
`fcd3d4b8~1..fcd3d4b8` (#1027) and requires `TheTransportBarIsDissolvedTests.swift` among the
hits, with the guards read AT `fcd3d4b8` — the bundle as it stood when the slip happened, not
today's repaired one. Known negative: `99b4b966~1..99b4b966` (#1089, a one-line string change)
must report nothing.
"""
from __future__ import annotations

import re
import subprocess
import sys

MAX_GENERIC = 8
MIN_LEN = 12
BUNDLE = "Tests/CISmoke"
KNOWN_POSITIVE = "fcd3d4b8~1..fcd3d4b8"
KNOWN_POSITIVE_GUARD = "TheTransportBarIsDissolvedTests.swift"
KNOWN_NEGATIVE = "99b4b966~1..99b4b966"


class Unavailable(Exception):
    """git could not answer — the instrument has no reading, not a clean one."""


def git(*args: str) -> str:
    try:
        return subprocess.run(["git", *args], check=True, capture_output=True,
                              text=True, errors="replace").stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise Unavailable(f"git {' '.join(args)}: {exc}") from exc


def interesting(line: str) -> bool:
    if len(line) < MIN_LEN:
        return False
    if line.startswith(("//", "/*", "*")):
        return False
    return not re.fullmatch(r"[{}()\[\]\s;,:]*", line)


def removed_lines(diff_args: list[str]) -> list[str]:
    """Trimmed `-` lines of `git diff -U0 … -- Sources`, in order, deduplicated."""
    seen: set[str] = set()
    out: list[str] = []
    for raw in git("diff", "-U0", *diff_args, "--", "Sources").split("\n"):
        if raw.startswith("---") or raw.startswith("+++") or not raw.startswith("-"):
            continue
        line = raw[1:].strip()
        if line in seen or not interesting(line):
            continue
        seen.add(line)
        out.append(line)
    return out


def guard_texts(at: str | None) -> dict[str, str]:
    """Bundle file → text. At a revision when given, else the working tree."""
    if at is None:
        names = git("ls-files", "--", f"{BUNDLE}/*.swift").split()
        return {n: open(n, encoding="utf-8", errors="replace").read() for n in names}
    names = git("ls-tree", "-r", "--name-only", at, "--", BUNDLE).split()
    return {n: git("show", f"{at}:{n}") for n in names if n.endswith(".swift")}


def still_in_sources(needle: str, at: str | None) -> bool:
    args = ["grep", "-q", "-F", "-e", needle]
    if at is not None:
        args.append(at)
    args += ["--", "Sources"]
    try:
        subprocess.run(["git", *args], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError as exc:
        if exc.returncode == 1:
            return False
        raise Unavailable(f"git grep: {exc}") from exc


def scan(diff_args: list[str], at: str | None) -> list[tuple[str, list[str], bool]]:
    """(removed line, guard files containing it, still in Sources at the new state)."""
    guards = guard_texts(at)
    hits = []
    for line in removed_lines(diff_args):
        files = sorted(n.rsplit("/", 1)[-1] for n, t in guards.items() if line in t)
        if files:
            hits.append((line, files, still_in_sources(line, at)))
    return hits


def resolve(arg: str | None) -> tuple[list[str], str | None, str]:
    """→ (git diff args, revision the guards are read at or None for the tree, label)."""
    if arg is None:
        return ["HEAD"], None, "working tree + index vs HEAD"
    if ".." in arg:
        a, b = arg.split("..", 1)
        return [arg], b or "HEAD", arg
    return [f"{arg}~1..{arg}"], arg, f"{arg}~1..{arg}"


def report(hits, label: str) -> int:
    print(f"moved-needles: {label}")
    if not hits:
        print("  no removed Sources/ line is a needle in the blocking bundle.")
        return 0
    for line, files, present in hits:
        state = "still in Sources" if present else "GONE from Sources"
        shown = line if len(line) <= 72 else line[:69] + "…"
        if len(files) > MAX_GENERIC:
            print(f"  [{state}] {shown!r}  → generic: {len(files)} guards, not listed")
            continue
        print(f"  [{state}] {shown!r}  → {len(files)}: {', '.join(files)}")
    print(f"  {len(hits)} hit(s). Each is a guard to OPEN: does its scan still reach this text "
          "at the new address? A hit is a question, not a verdict; see the docstring.")
    return 1


def selftest() -> int:
    """Drive `scan()` itself, never a re-implementation (#962)."""
    try:
        for rev in ("fcd3d4b8", "99b4b966"):
            git("cat-file", "-e", f"{rev}^{{commit}}")
    except Unavailable as exc:
        print(f"selftest: INSTRUMENT UNAVAILABLE — known-positive commits not in this clone ({exc})")
        return 2
    ok = True
    pos = scan(*resolve(KNOWN_POSITIVE)[:2])
    named = [f for _, files, _ in pos for f in files]
    if KNOWN_POSITIVE_GUARD in named:
        print(f"selftest 1 OK — {KNOWN_POSITIVE} names {KNOWN_POSITIVE_GUARD} "
              f"({named.count(KNOWN_POSITIVE_GUARD)}× over {len(pos)} hits)")
    else:
        ok = False
        print(f"selftest 1 FAIL — {KNOWN_POSITIVE} did not name {KNOWN_POSITIVE_GUARD}; "
              f"hits: {[(l[:40], f) for l, f, _ in pos]}")
    # The positive must be of the dangerous kind: the text survived elsewhere. If this flips,
    # the classification is broken, not the tree.
    kinds = {present for _, files, present in pos if KNOWN_POSITIVE_GUARD in files}
    if kinds == {True}:
        print("selftest 2 OK — every hit on that guard is 'still in Sources' (the #1027 shape)")
    else:
        ok = False
        print(f"selftest 2 FAIL — expected only 'still in Sources', got {kinds}")
    neg = scan(*resolve(KNOWN_NEGATIVE)[:2])
    if not neg:
        print(f"selftest 3 OK — {KNOWN_NEGATIVE} reports nothing")
    else:
        ok = False
        print(f"selftest 3 FAIL — {KNOWN_NEGATIVE} reported {len(neg)} hit(s)")
    # `interesting` — the filters that keep `}` and comments out of the hit list.
    if (not interesting("}") and not interesting("// a comment that is long enough")
            and interesting("HStack(spacing: 8) {")):
        print("selftest 4 OK — punctuation and comment lines are skipped, code is kept")
    else:
        ok = False
        print("selftest 4 FAIL — `interesting` filter changed")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    arg = next((a for a in argv if not a.startswith("-")), None)
    diff_args, at, label = resolve(arg)
    return report(scan(diff_args, at), label)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Unavailable as exc:
        print(f"moved-needles: INSTRUMENT UNAVAILABLE — {exc}")
        sys.exit(2)
