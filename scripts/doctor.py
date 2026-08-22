#!/usr/bin/env python3
"""Echoel doctor — checks whether the instruments that measure this repo are telling the truth.

This is NOT another content audit. `/scan`, `/review` and `/deep-dive` already look for stubs,
TODOs and audio-thread violations INSIDE the code. The doctor looks at the layer above: the
gates, the tool definitions, the doors and the numbers in the docs — the things that report on
the code and can therefore report FALSELY.

It exists because on 2026-07-28 the 305-file test suite failed to build for ~14 hours while its
workflow reported "success" (`continue-on-error` sits on the BUILD step, so the conclusion is
green while `steps.build.outcome` is `failure`). Nothing was red. Every check below is one that
would have caught a real, already-paid-for failure in this repo.

Design rules, taken from the flutter/brew/npm doctor family and from what actually went wrong here:
  · Deterministic only. No judgement, no LLM. Judgement lives in `.claude/skills/doctor/SKILL.md`.
  · Every finding prints its EVIDENCE (file:line and the matching text), never a bare verdict —
    a finding you cannot check by hand in ten seconds is not usable.
  · Read-only. It opens files and runs `git ls-files`. It never writes, never network.
  · No dependencies, no build. There is NO local Swift toolchain in this environment, which is
    precisely why a grep-and-parse instrument is the right shape here. Periphery would be the
    real tool for the reachability checks (C), but it needs SourceKit and a full build.
  · Honest about its own blind spots — see `--help` and the LIMITS block at the end of a run.

Usage:  python3 scripts/doctor.py [--section A|B|C|D] [--quiet]
Exit:   0 = no CRITICAL findings, 1 = at least one CRITICAL.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CRITICAL, WARN, INFO = "CRITICAL", "WARN", "INFO"
MARK = {CRITICAL: "❌", WARN: "⚠️ ", INFO: "ℹ️ "}


@dataclass
class Finding:
    level: str
    title: str
    evidence: list[str] = field(default_factory=list)
    fix: str = ""


@dataclass
class Section:
    key: str
    title: str
    findings: list[Finding] = field(default_factory=list)
    clean_note: str = ""


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _interpolation_end(line: str, at: int) -> int:
    """Index just past the `)` that closes an interpolation whose `(` is at `at`.

    Returns `len(line)` when the span does not close on this line — the span is then treated
    as running to end of line, which keeps the walk in literal state instead of guessing.
    ⚠️ In `blank_strings=True` that ERASES the remainder of the line, which is the FALSE-ALARM
    direction; 0 genuinely unclosed spans exist across the tracked tree today.

    ⛔ WHY THIS EXISTS: without it, `\(` was consumed as a plain escape and the next `"` — the
    OPENING quote of a nested literal inside the interpolation — read as the CLOSING quote of
    the outer one. Phase inverted for the rest of the interpolation, so its text was emitted
    as CODE. Measured on `XCTFail("no \(a["func ghostX("]) here")`: the needle survived the
    haystack blanking and found ITSELF, i.e. the #708 self-match again, one literal-shape over
    from the one #718 closed. The shape sits on 146 LINES in `Tests/CISmoke` and 45 in
    `Sources/` (`grep -c '\\([^)]*"'` — a line count, not an occurrence count: occurrences are
    148/50 and the spans this walk actually enters are 161/52; three defensible numbers, so the
    operation belongs beside the figure) — latent then, not any more.

    Nested literals are skipped with their own escape handling, so a `)` inside a string
    (`\(a[")"])`) does not close the span early.
    """
    depth, i, n = 0, at, len(line)
    while i < n:
        ch = line[i]
        if ch == '"':
            i += 1
            while i < n:
                if line[i] == "\\":
                    # ⛔ THE SKIP LOOP TREATED EVERY `\` AS A PLAIN ESCAPE, so an interpolation
                    # INSIDE the nested literal was not spanned: its opening `"` read as the
                    # nested literal's CLOSING quote, the span ended at the wrong `)`, and phase
                    # inverted for the rest of the line. The self-match was therefore still
                    # constructible ONE NESTING LEVEL DEEPER — the third repetition of this class,
                    # each time in the shape the previous fix did not reach. Recursing here is the
                    # whole repair, and it changed output on 0 of 711 files × 2 modes.
                    if i + 1 < n and line[i + 1] == "(":
                        i = _interpolation_end(line, i + 1)
                        continue
                    i += 2
                    continue
                if line[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def _code_only(text: str, blank_strings: bool = False) -> str:
    """Swift source with comments blanked, line count preserved.

    The Python twin of `SourceText.codeOnly` in `Tests/CISmoke`. It exists because a needle
    scan that reads RAW text also matches the prose ABOUT the guard — that is #711, where a
    token appeared in two explanatory comments and deleting the real call still passed green.

    `blank_strings=True` additionally blanks the INTERIOR of every literal, keeping the
    delimiters. That is what a haystack needs: a real declaration survives, a needle cannot
    find itself (#708). ⛔ Both passes come from THIS ONE WALK on purpose. The first version
    did the second pass with `re.sub(r'"[^"]*"', '""', line)`, a second and weaker idea of
    where a literal ends — it mis-pairs on a backslash-escaped quote, so the needle text could
    emerge unblanked and find itself. Two definitions of "where a string starts" is the #416
    shape; there is now one. ⚠️ THAT ONE WAS LATENT, NOT LIVE: measured over the real guard
    bundle, ZERO needles survived the old blanking. The repro needs an escaped quote BEFORE
    the needle on the same line (`contains("a \" b"), "func phantomX("`). The commit that
    made this repair asserted an occurrence and had none — the same standard the boundary
    check below applies to itself ("a latent false green, not a live one") had not been
    applied to it.

    ⚠️ HONEST LIMITS — a stripper that silently mis-parses is worse than none, and the
    failure direction is NOT one-sided: this walk ERASES text, and erased text feeds both the
    needle scan (a miss) and the haystack (a false alarm).
      · It understands `"` strings with backslash escapes, Swift triple-quoted literals, raw
        strings (`#"…"#`, any number of hashes, including `#\"\"\"…\"\"\"#`), `//` to end of
        line and `/* */` across lines.
      · Interpolation (`\\(expr)`, `\\#(expr)` in a raw string) is spanned by
        `_interpolation_end` and emitted as LITERAL text. ⚠️ READ WHICH PASS THAT AFFECTS: with
        `blank_strings=False` nothing is erased, so the NEEDLE SCAN still sees a declaration
        mentioned inside an interpolation and will report it; only the HAYSTACK blanks it, and
        haystack erasure is the FALSE-ALARM direction. It is benign here only because a real
        declaration never lives inside a literal. (The first version of this bullet said
        "invisible — a MISS, the safe direction", naming the wrong pass AND the opposite of this
        docstring's own framing — the very defect #719 was written to repair, one pass over.)
        ⛔ Until that helper existed the
        opposite happened: the walk desynchronised and emitted the interpolation as CODE, so
        a needle inside one found ITSELF. The docstring stated the safe direction while the
        code did the unsafe one, which is worse than either — a reader who trusts the line
        does not look. Now the line is true.
      · A backslash-escaped `\\"\"\"` inside a triple-quoted body no longer closes it. It used
        to, and the real terminator then RE-OPENED the literal, erasing every declaration to
        end of file (a FALSE ALARM, the expensive direction).
      · It does NOT understand NESTED block comments, which Swift permits: in
        `/* a /* b */ func real() {}` the outer `*/` leaks and `func real` survives. Same
        behaviour as the Swift twin, which documents it.
      · It is a character scan, not a lexer. Anything above is a shape it was TAUGHT, not a
        grammar it derives — the next unknown shape fails silently, in either direction.

    ⛔ THE `\"\"\"` CASE IS WHY THIS IS NOT OPTIONAL. Before it was handled, a `/*` inside a
    triple-quoted failure message — and this repo routinely writes globs like `Sources/**` in
    one — opened a phantom block comment that swallowed every line to the next `*/`. Measured
    on the real tree at the time: 621 non-comment lines blanked across 6 guard files,
    including 37 real declarations, and a phantom needle injected into the swallowed region
    was NOT caught. `Tests/CISmoke/SourceText.swift` had already written that exact analysis
    ("a negative scan goes GREEN ON NOTHING") for the `///` case; this reproduced it one
    literal-shape over. The recipe below is a REGRESSION CHECK and must print 0 — reproducing
    the 621 needs `git show b618883:scripts/doctor.py`, because the defect is in that walk:
        python3 -c "import sys;sys.path.insert(0,'scripts');import doctor as d;\\
    print(sum(1 for f in d.tracked('Tests/CISmoke/*.swift') \\
    for r,o in zip(d.read(f).split(chr(10)), d._code_only(d.read(f)).split(chr(10))) \\
    if r.strip() and not o.strip() and not r.strip().startswith('//')))"

    ⛔ THE TWINS NOW DIVERGE ON `\"\"\"`, DELIBERATELY, AND THAT IS A DECISION THE REPO HAS
    ALREADY GUARDED. `Tests/CISmoke/SourceText.swift` says of its own `\"\"\"` blindness "IT IS
    DELIBERATELY NOT FIXED, and the measurement is the reason rather than the effort": teaching
    the SWIFT scanner about `\"\"\"` would start handing Metal shader PROSE to
    `GlitterCannotBecomeAFlashTests`, the WCAG 3 Hz guard, and
    `TheStripperDoesNotKnowATripleQuoteTests` exists to go red the day a second file joins the
    disagreeing set. That reason does NOT transfer here: this walk feeds a needle scan and a
    declaration haystack, no safety guard reads it, and `\"\"\"` bodies are prose to it. Making
    THIS twin `\"\"\"`-aware is therefore right and the Swift one staying blind is also right —
    but they are no longer the same algorithm, and nothing checks that. ⚠️ The commit that
    introduced the divergence cited SourceText's `///` analysis as supporting precedent and
    omitted its `\"\"\"` conclusion from the same file, which is the citation failure this repo
    names most often.

    ⚠️ NOT covered by `OneDefinitionOfCodeNotProseTests` — that census anchors on the literal
    `func codeOnly` and scans Swift only, so this twin is invisible to it. Drift between the
    two is unguarded; if you change one, read the other.
    """
    out: list[str] = []
    in_block = False
    in_multi = False       # inside a Swift triple-quoted literal
    multi_hashes = 0       # raw-string hashes that must follow its closing delimiter
    for line in text.split("\n"):
        buf: list[str] = []
        i, n = 0, len(line)
        in_str = False     # inside a single-line literal
        str_hashes = 0
        esc = False

        def emit(s: str, literal: bool) -> None:
            buf.append(" " * len(s) if (literal and blank_strings) else s)

        while i < n:
            ch = line[i]

            if in_block:
                if line.startswith("*/", i):
                    in_block = False
                    buf.append("  ")
                    i += 2
                    continue
                buf.append(" ")
                i += 1
                continue

            if in_multi:
                closing = '"""' + "#" * multi_hashes
                interp = "\\" + "#" * multi_hashes + "("
                # ⛔ A BACKSLASH-ESCAPED `\"""` INSIDE THE BODY CLOSED IT EARLY, and the real
                # terminator then RE-OPENED the literal — blinding every declaration to the end
                # of the file (a false alarm, the expensive direction). 7,504 lines currently
                # sit inside a `"""` body carrying a backslash; one `\"""` was all it took.
                if multi_hashes == 0 and ch == "\\" and not line.startswith(interp, i):
                    emit(line[i:i + 2], True)
                    i += 2
                    continue
                if line.startswith(interp, i):
                    end = _interpolation_end(line, i + len(interp) - 1)
                    emit(line[i:end], True)
                    i = end
                    continue
                if line.startswith(closing, i):
                    in_multi = False
                    buf.append(closing)
                    i += len(closing)
                    continue
                emit(ch, True)
                i += 1
                continue

            if in_str:
                closing = '"' + "#" * str_hashes
                interp = "\\" + "#" * str_hashes + "("
                if not esc and line.startswith(interp, i):
                    end = _interpolation_end(line, i + len(interp) - 1)
                    emit(line[i:end], True)
                    i = end
                    continue
                if esc:
                    esc = False
                    emit(ch, True)
                    i += 1
                    continue
                if str_hashes == 0 and ch == "\\":
                    esc = True
                    emit(ch, True)
                    i += 1
                    continue
                if line.startswith(closing, i):
                    in_str = False
                    buf.append(closing)
                    i += len(closing)
                    continue
                emit(ch, True)
                i += 1
                continue

            # a raw-string opener is `#`*k + `"` (or `"""`); count the hashes first
            hashes = 0
            while i + hashes < n and line[i + hashes] == "#":
                hashes += 1
            if hashes and line.startswith('"', i + hashes):
                opener_is_multi = line.startswith('"""', i + hashes)
                opener = "#" * hashes + ('"""' if opener_is_multi else '"')
                buf.append(opener)
                i += len(opener)
                if opener_is_multi:
                    in_multi, multi_hashes = True, hashes
                else:
                    in_str, str_hashes = True, hashes
                continue

            if line.startswith('"""', i):
                in_multi, multi_hashes = True, 0
                buf.append('"""')
                i += 3
                continue

            if ch == '"':
                in_str, str_hashes = True, 0
                buf.append('"')
                i += 1
                continue

            if line.startswith("//", i):
                buf.append(" " * (n - i))
                break

            if line.startswith("/*", i):
                in_block = True
                buf.append("  ")
                i += 2
                continue

            buf.append(ch)
            i += 1

        out.append("".join(buf))
    return "\n".join(out)


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


class InstrumentUnavailable(RuntimeError):
    """The doctor cannot see. Raised instead of returning an empty list — see `tracked`."""


def tracked(pattern: str) -> list[Path]:
    """Git-tracked files matching a pathspec. Tracked-only keeps build junk out of the counts.

    ⛔ THIS FUNCTION USED TO SWALLOW FAILURE, and that made the doctor carry the exact disease it
    was written to diagnose. It caught `OSError`/`SubprocessError` and never looked at
    `returncode`, so any git failure — `fatal: detected dubious ownership` (the standard
    container case), git missing from PATH, a 30 s timeout — returned `[]`. Every git-backed
    check then found nothing, printed its green clean-note, and the run exited 0. A reviewer
    reproduced it with a git shim exiting 128: both CRITICAL findings vanished and the exit code
    flipped to success. A diagnostic must fail LOUD when blind; silence is the failure mode.
    """
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "ls-files", pattern],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        raise InstrumentUnavailable(f"git ls-files {pattern!r} could not run: {exc}") from exc
    if out.returncode != 0:
        raise InstrumentUnavailable(
            f"git ls-files {pattern!r} exited {out.returncode}: {out.stderr.strip()[:200]}")
    return [ROOT / line for line in out.stdout.splitlines() if line]


# ---------------------------------------------------------------- A. do the gates tell the truth

# Deliberately NARROW. The first version of this matched a bare `\bbuild\b` anywhere in a
# 12-line window and flagged "Check for TODO/FIXME" and "Purge Cloudflare Cache" — a doctor
# that cries wolf gets muted, which is worse than no doctor. This matches only an actual
# compiler invocation, and only inside the step's own body.
#
# `xcodebuild test` COMPILES before it runs, so masking it hides a build failure just as
# completely as masking `build-for-testing`. Leaving it out was a real blind spot: three such
# steps in ci.yml were invisible.
BUILD_CMD = re.compile(r"xcodebuild\b[^\n]*\b(?:build|build-for-testing|test|archive)\b"
                       r"|^\s*swift\s+(?:build|test)\b", re.M)
# Any key may open a step — `.github/workflows/testflight.yml` has one starting with `- if:`.
# Anchoring on name/uses/run/id merged that step into its predecessor's block.
STEP_START = re.compile(r"^(\s*)-\s+\w[\w-]*:")
JOB_START = re.compile(r"^  ([\w-]+):\s*$")


def _steps(lines: list[str]) -> list[tuple[int, int, str]]:
    """Split a workflow into (start, end, name) step blocks, so a check can be scoped to ONE step.

    ⛔ A step block must END AT ITS JOB'S BOUNDARY. Running it to the next step start anywhere in
    the file makes the last step of job N swallow job N+1's header — including a JOB-level
    `continue-on-error`, which then looks like it belongs to a step and is skipped as
    already-accounted-for. That is how `ci.yml`'s entirely non-blocking performance job stayed
    invisible: it masks strictly MORE than any step-level flag.
    """
    job_bounds = [i for i, line in enumerate(lines) if JOB_START.match(line)] + [len(lines)]
    starts = [i for i, line in enumerate(lines) if STEP_START.match(line)]
    out = []
    for n, s in enumerate(starts):
        e = starts[n + 1] if n + 1 < len(starts) else len(lines)
        e = min(e, next((b for b in job_bounds if b > s), len(lines)))
        name = ""
        for j in range(s, e):
            m = re.match(r"\s*-?\s*name:\s*(.+)", lines[j])
            if m:
                name = m.group(1).strip().strip("\"'")
                break
        out.append((s, e, name))
    return out


def _command_span(block: list[str], at: int) -> range:
    """The full extent of a shell command starting at `at`, following `\\` continuations.

    A build is routinely written across five lines and only the LAST one carries the pipe:
        xcodebuild build \\
          -scheme X \\
          2>&1 | tail -5
    Looking for the pipe on the same line as `xcodebuild` finds nothing — which is exactly how
    `benchmark.yml`'s unguarded pipe survived the first version of this check.
    """
    end = at
    while end < len(block) - 1 and block[end].rstrip().endswith("\\"):
        end += 1
    return range(at, end + 1)


def section_a() -> Section:
    sec = Section("A", "GATES — does a green check mean the work actually ran?")

    # A1. A build step whose failure cannot turn anything red. On a TEST step a mask is a
    # legitimate reveal mode; on a BUILD step it turns "did not compile" into "success", and
    # then nothing ran at all. Three distinct mechanisms produce that, and checking only the
    # first missed live cases in this very repo:
    #   (a) step-level `continue-on-error: true`
    #   (b) JOB-level `continue-on-error: true` — masks strictly more, and sits at an
    #       indentation the step splitter never looked at (ci.yml's performance job)
    #   (c) the exit status never reaching the runner at all: `|| true`, or a pipe without
    #       pipefail so the pipeline reports the LAST command's status (`| tail -5` → always 0).
    # ci.yml's own comment block documents (c) as the mask "written in a form that did not look
    # like one" — the lesson was in the repo before this check was, and the first version of
    # this check still missed it.
    masked: list[str] = []
    for wf in sorted(tracked(".github/workflows/*.yml")):
        lines = read(wf).splitlines()
        steps = _steps(lines)
        step_spans = [(s, e) for s, e, _ in steps]

        # (b) job level: a continue-on-error that belongs to no step.
        job_at = {}
        current = None
        for i, line in enumerate(lines):
            m = JOB_START.match(line)
            if m:
                current = m.group(1)
            job_at[i] = current
        for i, line in enumerate(lines):
            if "continue-on-error:" not in line or "true" not in line or line.lstrip().startswith("#"):
                continue
            if any(s <= i < e for s, e in step_spans):
                continue
            job = job_at.get(i)
            if not job:
                continue
            j_start = next(k for k in range(i, -1, -1) if JOB_START.match(lines[k]))
            j_end = next((k for k in range(i + 1, len(lines)) if JOB_START.match(lines[k])), len(lines))
            if BUILD_CMD.search("\n".join(lines[j_start:j_end])):
                masked.append(f"{rel(wf)}:{i + 1}  JOB {job!r} is entirely non-blocking, and it builds")

        for start, end, name in steps:
            block = lines[start:end]
            text = "\n".join(block)
            if not BUILD_CMD.search(text):
                continue
            # GitHub's default `run` shell is `bash -e {0}` — NO pipefail. Only an explicit
            # `shell: bash` (which is `bash --noprofile --norc -eo pipefail {0}`) or a literal
            # `set -o pipefail` restores it.
            #
            # `${PIPESTATUS[0]}` is the OTHER correct answer, and a stricter one than pipefail —
            # `xcode-compile-check.yml` and `testflight.yml` both capture the build's status that
            # way on purpose. Without this clause the doctor accuses the repo's own most careful
            # workflows, including the blocking compile gate, of the exact defect they guard
            # against. That is the cry-wolf failure in its most damaging form: the finding is
            # loudest where the engineering was best.
            pipefail = ("set -o pipefail" in text
                        or "PIPESTATUS" in text
                        or re.search(r"^\s*shell:\s*bash\s*$", text, re.M))
            for k, ln in enumerate(block):
                if "continue-on-error:" in ln and "true" in ln and not ln.lstrip().startswith("#"):
                    masked.append(f"{rel(wf)}:{start + k + 1}  step {name!r} tolerates a BUILD failure")
                if "|| true" in ln and BUILD_CMD.search(ln + "\n" + "\n".join(block[max(0, k - 6):k])):
                    masked.append(f"{rel(wf)}:{start + k + 1}  step {name!r} ends its build in `|| true` "
                                  f"— the failure never reaches the runner")
            if not pipefail:
                for k, ln in enumerate(block):
                    if not BUILD_CMD.search(ln):
                        continue
                    for j in _command_span(block, k):
                        if "|" in block[j].split("#")[0].replace("||", ""):
                            masked.append(f"{rel(wf)}:{start + j + 1}  step {name!r} pipes its build without "
                                          f"`set -o pipefail` — the pipeline reports the LAST command's status")
                            break
    if masked:
        sec.findings.append(Finding(
            CRITICAL,
            "A build failure here cannot turn anything red",
            sorted(set(masked)),
            "A test failure may be tolerable in a reveal-only run; a build failure never is. "
            "The repair DEPENDS ON WHICH LINE: a `|| true` or a missing `set -o pipefail` must "
            "be removed first — a guard step added on top of either reads success forever. Only "
            "once the step's own exit status is honest can a final step gate on "
            "`steps.<id>.outcome` (NOT `.conclusion`, which continue-on-error forces to "
            "success), and that requires the step to HAVE an `id:`. Changing CI config is "
            "founder-gated in this repo — report, do not edit."))

    # A2. Does the BLOCKING test bundle actually contain the test files people write?
    proj = read(ROOT / "project.yml")
    bundles = re.findall(r"\n  (\w+):\n    type: bundle\.unit-test\n(?:.*\n)*?    sources:\n"
                         r"((?:      - path: \S+\n)+)", proj)
    test_dirs = {d.name for d in (ROOT / "Tests").iterdir() if d.is_dir()} if (ROOT / "Tests").is_dir() else set()
    biggest = max(((d, len(list((ROOT / "Tests" / d).rglob("*.swift")))) for d in test_dirs),
                  key=lambda kv: kv[1], default=(None, 0))
    for name, srcs in bundles:
        paths = re.findall(r"- path: (\S+)", srcs)
        covered = any(biggest[0] and biggest[0] in p for p in paths)
        if not covered and biggest[0]:
            counts = ", ".join(f"{p} ({len(list((ROOT / p).rglob('*.swift'))) if (ROOT / p).is_dir() else 0} files)"
                               for p in paths)
            sec.findings.append(Finding(
                WARN,
                f"Test bundle {name!r} does not build the directory where the tests live",
                [f"project.yml: {name}.sources = {counts}",
                 f"largest suite on disk = Tests/{biggest[0]} ({biggest[1]} files)"],
                f"Whether this is wrong depends on which bundle the BLOCKING gate runs. If the "
                f"blocking gate runs {name!r}, then {biggest[1]} test files only ever run in a "
                f"non-blocking workflow. Founder-gated (project.yml)."))

    # A3. A `-only-testing:` filter naming a suite that does not exist tests nothing, silently.
    suites = set()
    for f in tracked("Tests/*/*.swift"):
        suites.update(re.findall(r"^(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", read(f), re.M))
    phantom: list[str] = []
    for wf in sorted(tracked(".github/workflows/*.yml")):
        for i, line in enumerate(read(wf).splitlines()):
            for m in re.finditer(r"-(?:only|skip)-testing:(\S+)", line):
                parts = m.group(1).split("/")
                if len(parts) >= 2 and parts[1] not in suites:
                    phantom.append(f"{rel(wf)}:{i + 1}  names suite {parts[1]!r} — no such XCTestCase class")
    if phantom:
        sec.findings.append(Finding(
            CRITICAL,
            "A test filter names a suite that does not exist — that step tests nothing",
            phantom,
            "A run with zero matched tests is understood to report success rather than fail — "
            "UNVERIFIED here, there is no Xcode in this environment, so treat it as the "
            "assumption this finding rests on. Before renaming: check whether the step is ALSO "
            "masked (see the finding above). If it is, fixing the name restores nothing "
            "observable — the mask is the bigger defect and has to go first."))

    if not sec.findings:
        sec.clean_note = "No masked build step, no phantom test filter."
    return sec


# ------------------------------------------------------- B. do our own tools describe a real repo

def section_b() -> Section:
    sec = Section("B", "TOOLING — do the commands and skills still describe THIS repo?")

    # ⛔ THIS GLOB READ TWO SURFACES AND REPORTED CLEAN FOR FOUR, UNTIL 2026-08-12. It was
    # `.claude/commands/*.md` + `.claude/skills/*/SKILL.md` only. The 11 files under
    # `.claude/agents/` and the 6 under `.claude/routines/` were never opened — and five
    # backticked paths in two agents had been dead for weeks, including the ONLY named path in
    # `bio-safety-reviewer.md`, the agent that gates medical-claim and 3 Hz-flash compliance.
    # `path_like` below already matched them verbatim; nothing was wrong with the check, only
    # with what it was pointed at. This is the exact "clean for work nobody looked at" failure
    # section B exists to prevent, committed by section B.
    # ⚠️ AND WIDENING IT DOES NOT CLOSE THE CLASS. A path scan catches path drift. It cannot
    # see `e2e-test-agent.md`, which is entirely about an AUv3 target removed 2026-07-24, or
    # `ui-state-reviewer.md`, whose subject `StudioRoot` has 0 hits in `Sources/` — neither
    # names a path. Concept drift in an agent's PROSE has no automated check here; say so
    # rather than let a green section B imply otherwise.
    docs = sorted(
        tracked(".claude/commands/*.md")
        + tracked(".claude/skills/*/SKILL.md")
        + tracked(".claude/agents/*.md")
        + tracked(".claude/routines/*.md")
    )
    path_like = re.compile(r"`(Sources/[\w/.*-]+|Tests/[\w/.*-]+|scripts/[\w/.-]+)`")
    # A document that EXPLAINS a deletion has to name the deleted path. Flagging that is the
    # cry-wolf failure in its most circular form: the doctor accusing the correction it asked
    # for. So an obituary on the line exempts the paths ON THAT LINE.
    #
    # ⛔ The first version widened this to a ±2-line neighbourhood, and that was measurably
    # worse than useless: it exempted 3 LIVE paths and caught no additional stale one. Among
    # the three was `Sources/Echoelmusic/Tools/` — the path the very same commit ADDED as the
    # replacement for the deleted AUv3 scan paths — because the sentence explaining the old
    # paths sat two lines below it. Rename or empty `Tools/` and the doctor would have said
    # clean forever. Same line is also the only form that PROVES the note is about that path;
    # a nearby sentence can be about anything.
    obituary = re.compile(r"deleted|removed|no longer|never existed|does not exist|gone with", re.I)
    stale: list[str] = []
    for doc in docs:
        lines = read(doc).splitlines()
        for i, line in enumerate(lines):
            if obituary.search(line):
                continue
            for m in path_like.finditer(line):
                raw = m.group(1)
                base = raw.split("*")[0].rstrip("/")
                if not base or "." not in Path(base).name and not base.count("/"):
                    continue
                if not (ROOT / base).exists():
                    stale.append(f"{rel(doc)}:{i + 1}  references {raw} — not in the repo")
    if stale:
        sec.findings.append(Finding(
            WARN,
            "A command or skill points at paths that no longer exist",
            sorted(set(stale))[:25],
            "A command that scans deleted directories reports 'clean' for work it never looked "
            "at. Update or delete the reference."))

    # A command that tells the agent to run a toolchain this environment does not have will
    # either be skipped or produce a confusing error — either way its check does not happen.
    has_swift = shutil.which("swift") is not None
    if not has_swift:
        # ⛔ Report only a step with NO fallback. Most of these commands are already
        # platform-aware — `/scan`, `/debug`, `/ship`, `/testflight-deploy` each give the
        # macOS command AND the CI route beside it, and flagging those was the cry-wolf
        # failure again: 17 lines reported where 5 were real. The defect is a step that
        # cannot run here and offers nothing instead.
        #
        # ⛔ Scope the search to the ENCLOSING `###` section, not a fixed line window. The
        # first version used i-10:i+12 and let a real offender through: `/test` section 4
        # ("Full Suite Fallback") offers no CI route at all, but inherited the exemption from
        # the `**Linux/web:**` line in section 3 ten lines above. A fallback in a DIFFERENT
        # step is not a fallback for this one.
        fallback = re.compile(r"linux|web.session|no xcode|CI will|platform-aware|gh-run-status"
                              r"|check .*CI|GitHub API", re.I)
        offenders: list[str] = []
        for doc in sorted(tracked(".claude/commands/*.md")):
            lines = read(doc).splitlines()
            heads = [k for k, ln in enumerate(lines) if ln.startswith("###")]
            for i, line in enumerate(lines):
                if not re.search(r"^\s*swift\s+(build|test)\b", line):
                    continue
                start = max([k for k in heads if k <= i], default=0)
                end = min([k for k in heads if k > i], default=len(lines))
                if fallback.search("\n".join(lines[start:end])):
                    continue
                offenders.append(f"{rel(doc)}:{i + 1}  {line.strip()} — and no CI route beside it")
        if offenders:
            sec.findings.append(Finding(
                WARN,
                "Commands instruct `swift build` / `swift test`, but there is no local toolchain",
                offenders[:20] + ([f"... and {len(offenders) - 20} more"] if len(offenders) > 20 else []),
                "In this environment CI is the only compiler AND the only test runner. A command "
                "whose first step cannot run tends to be abandoned mid-way. Either guard the step "
                "explicitly ('on Linux: check CI instead') or drop it."))

    # ------------------------------------------------------------------ phantom guard needles
    #
    # ⭐ ADDED BECAUSE IT HAPPENED THREE TIMES IN ONE SESSION, not because it sounded useful.
    # A guard in `Tests/CISmoke` that scans SOURCE TEXT is only as good as its needle, and a
    # needle that matches nothing passes green forever while the defect it names ships:
    #   · #705 — a "Bio chip" needle blind to the quoted spelling that produced the miss
    #            (normalised by #706)
    #   · #711 — a token that also matched the two prose comments ABOUT the guard, so the
    #            direction the file names first could not fire
    #   · #716 — `func pulseClock(` and `func sendClock(`, neither of which has ever existed
    #            (shipped by #715, found by #716); the real per-pulse handler is `emitPulse()`,
    #            so the ONE path that guard was written to protect was the one it could not see
    # `Tests/CISmoke/CLAUDE.md` states the rule (#367/#408) and it was still missed three
    # times, so the repair is mechanical, not more prose.
    #
    # ⚠️ SCOPE IS DELIBERATELY NARROW: only string literals shaped like a Swift DECLARATION
    # (`"func x("`, `"struct X"`, …). Those are mechanically checkable. An arbitrary needle
    # ("Bio chip", `.disabled(!midiOutMPE)`) is not, and pretending otherwise would produce a
    # finding nobody can act on.
    #
    # ⛔ SO SAY THE PLAIN THING, because a three-item list reads as three-item coverage: OF THE
    # THREE FAILURES ABOVE, THIS CHECK WOULD HAVE CAUGHT ONE. #716's needles are
    # declaration-shaped and are caught. #705's ("Bio chip") and #711's (a bare call token,
    # `normaliseDoorlessLeadMix()`) are not, and remain uncatchable by construction. The list
    # is the REASON this exists, not a claim about its reach.
    #
    # ⚠️ AND THE REACH IS NARROWER THAN THE SHAPE ALLOWS: 41 needles match this regex, against a
    # larger pool of declaration-ish literals in the bundle. Re-derived and stable: 41 matched,
    # and the empty-parens bucket (`"func X()"`) is 5, the `var`/`let`/`case`/`init`/`extension`/
    # `typealias` bucket 21. ⚠️ NOT re-derivable as first written: "~640" lands anywhere between
    # 558 and 683 depending on what counts as declaration-ish, "61" (leading modifier) re-derives
    # to 57 and "3" (arguments inside the literal) to 14 — no definition was recorded beside them,
    # which is the whole failure this repo names as "measure; do not recite". Treat the three as
    # OWED a definition, not as counts.
    #
    # ⭐ THE ORDERING CONSTRAINT IS DISCHARGED. Widening had to wait for the glob repair — with
    # `Sources/Echoelmusic/**` the empty-parens shape false-alarmed on `func openAppSettings()`
    # immediately. That landed in #718/#719, and re-measuring the same widening against the
    # shipped haystack now yields 0. A deferred item still marked blocked by a blocker that no
    # longer exists is the "doorless note that outlived its reason" shape. Forecast for whoever
    # does it: the `var`/`let`/`case` bucket produces prose fragments, not needles (`'init param'`,
    # `'var peerBio'`, `'let breathAddress'`, `'case wetDry'`), so that bucket needs a tighter
    # shape or it is cry-wolf.
    #
    # ⛔ THE FIRST VERSION MATCHED ITSELF AND CAUGHT NOTHING — the #708 failure, reproduced in
    # the check written to stop that family. It searched a haystack that INCLUDED
    # `Tests/CISmoke`, so `"func pulseClock("` found itself in the very line under test and
    # reported clean. The haystack is therefore built with string literals BLANKED: a real
    # declaration survives, a needle does not. Measured both ways — 0 findings on the correct
    # tree, and both #716 phantoms caught when re-injected.
    #
    # ⛔ AND THE SECOND VERSION BLANKED THEM WITH A DIFFERENT, WEAKER IDEA OF WHERE A LITERAL
    # ENDS (`re.sub(r'"[^"]*"', …)`), which mis-pairs on a backslash-escaped quote — 304 guard
    # lines carry one, and on those the needle found itself again. Blanking now comes from the
    # same walk as comment-stripping (`_code_only(..., blank_strings=True)`); see its docstring
    # for the `"""`-swallows-the-file case found in the same review.
    needle_shape = re.compile(r'"((?:func|struct|enum|class|protocol) [A-Za-z_][A-Za-z0-9_]*\(?)"')
    # A needle used in an ABSENCE assertion names something that must NOT exist. Flagging it is
    # the cry-wolf failure in its purest form. Same-line only, for the reason the path check
    # above learned the hard way: a neighbourhood exemption exempts live things by accident.
    absence = re.compile(r"XCTAssertFalse|XCTAssertNil|\.isEmpty|deleted|no longer|must be ABSENT")

    # ⛔ THE GLOB WAS `Sources/Echoelmusic/**/*.swift` AND DROPPED FOUR LIVE FILES — including
    # `EchoelmusicApp.swift`, the `@main` entry point. Git's `**/` requires at least one
    # intervening directory, so the two loose top-level files CLAUDE.md names explicitly
    # ("plus the two loose top-level files") were invisible, as were the Watch and Widget
    # targets. Consequence measured: a needle for `func openAppSettings()` — declared only in
    # `MicrophoneManager.swift` — reported as a phantom. That is the cry-wolf failure this
    # block's own comment warns against, inside the check that warns about it. `Sources/**`
    # alone returns all 369 — but so does `Sources/*.swift`, because git's `*` in an ls-files
    # pathspec crosses `/`, and that is the form the two other Sources-globs in this file use
    # — the form the file's two other Sources-glob sites reach for (`section_c`'s
    # `swift = tracked(...)`, `section_d`'s `src_count = len(set(...))`), both of which UNION the
    # two globs. `**/*.swift` would STILL miss a file placed directly in `Sources/`, so this line
    # now uses a form that cannot, rather than one that happens to agree today.
    #
    # ⛔ THE FIRST VERSION CITED THOSE TWO SITES BY LINE NUMBER (`:726`, `:816`) AND BOTH WERE
    # WRONG WHEN WRITTEN — the same commit shifted the file by ~90 lines; the sites are ~:746 and
    # ~:836, and by the time you read this they have moved again. It also said they "already knew
    # to widen", which reads as "they use this form"; they use the UNION. A quoted phrase survives
    # an insertion, a line number does not — this file's own subject matter, made in this file.
    def _declarations_only(paths: list[Path]) -> str:
        return "\n".join(_code_only(read(f), blank_strings=True) for f in paths)

    guards = sorted(tracked("Tests/CISmoke/*.swift"))
    if guards:
        haystack = _declarations_only(sorted(tracked("Sources/*.swift")) + guards)
        phantoms = []
        for f in guards:
            for i, line in enumerate(_code_only(read(f)).split("\n")):
                if absence.search(line):
                    continue
                for m in needle_shape.finditer(line):
                    # A bare needle (`"struct Bio"`) must not resolve by PREFIX against
                    # `struct BioStripView` — 28 of the 38 needles that are actually SCANNED
                    # carry no `(` (31 of the 41 matched; all 3 absence-exempt ones are
                    # paren-less, so the two denominators differ). All 28 resolve exactly
                    # today, so this closes a latent false green, not a live one.
                    #
                    # ⛔ THE BOUNDARY MUST NOT BE APPLIED TO A NEEDLE THAT ENDS IN `(`. The
                    # first version appended it unconditionally and produced EIGHT false
                    # alarms in one run — `func send(` is followed by `_` in
                    # `func send(_ bytes:)`, and `_` is a word character, so every real
                    # declaration with an unnamed first argument read as missing. Caught by
                    # running it; it is exactly the cry-wolf this block warns about.
                    needle = m.group(1)
                    pattern = re.escape(needle)
                    if needle[-1].isalnum() or needle[-1] == "_":
                        pattern += r"(?![A-Za-z0-9_])"
                    if not re.search(pattern, haystack):
                        phantoms.append(f"{rel(f)}:{i + 1}  {m.group(1)!r} — declared nowhere")
        if phantoms:
            sec.findings.append(Finding(
                WARN,
                "A guard needle names a declaration that does not exist",
                phantoms[:20] + ([f"... and {len(phantoms) - 20} more"] if len(phantoms) > 20 else []),
                "The guard cannot fail for its named reason (#367): the scan looks for something "
                "that is not there, so it is green whatever the code does. Re-derive the needle "
                "from the real declaration and ANCHOR it — assert the needle itself is present "
                "before asserting anything about it. If the name is meant to be absent, put the "
                "absence assertion on the SAME line, which exempts it here."))

    if not sec.findings:
        sec.clean_note = "Commands and skills reference only paths that exist."
    return sec


# ------------------------------------------------- C. do the surfaces exist where the UI claims

VIEW_DECL = re.compile(r"^(?:public\s+|private\s+|internal\s+)?struct\s+(\w+)\s*:\s*(?:[\w., ]*\b)?View\b", re.M)


def section_c() -> Section:
    sec = Section("C", "SURFACES — is there a door to what the code builds?")

    swift = tracked("Sources/*.swift") + tracked("Sources/**/*.swift")
    bodies = {f: read(f) for f in swift}

    # C1. A View struct that NOTHING anywhere constructs is a surface the user cannot reach —
    # the "doorless view" class CLAUDE.md keeps re-discovering by hand (PatchEditorView,
    # SpectralDonutView, the Tools grid).
    #
    # ⛔ The first version of this asked for zero construction sites OUTSIDE the declaring file
    # and returned 41 entries, almost all of them private leaves that their own file's reachable
    # parent constructs — `PulseTrace`, `RecordingBadge`, `MiniTransportView`. That is normal
    # SwiftUI composition, and burying five real findings under thirty-six non-findings is how a
    # check gets ignored. The question is not "is it used elsewhere" but "is it built AT ALL".
    doorless: list[str] = []
    for f, src in bodies.items():
        for m in VIEW_DECL.finditer(src):
            name = m.group(1)
            if name.endswith("_Previews") or name.endswith("Preview"):
                continue
            # ⛔ `\b{name}\s*\(` alone MISSES a view constructed with trailing-closure syntax
            # and no parentheses — `SafeModeView { ... }` at EchoelmusicApp.swift:288. That made
            # the doctor report the app's black-screen recovery screen as unreachable, and its
            # own advice then invites documenting-as-parked or deleting it. Accept `(` or `{`.
            # Two shapes are NOT construction and must not count as one: the declaration itself
            # and `extension Name { … }`. Subtracting a count afterwards (my first attempt) is
            # not equivalent — it over-corrects and accused `EchoelStudioView`, the app's own
            # root surface, of being unreachable. Exclude them at the match instead.
            uses = sum(len(re.findall(rf"(?<!struct )(?<!extension )\b{name}\s*[\(\{{]", other))
                       for other in bodies.values())
            if uses == 0:
                line = src[:m.start()].count("\n") + 1
                doorless.append(f"{rel(f)}:{line}  struct {name}: View — never constructed anywhere in Sources/")
    if doorless:
        sec.findings.append(Finding(
            WARN,
            "View types that nothing in Sources/ ever constructs",
            sorted(doorless),
            "Being constructed nowhere is proof of unreachability; being constructed somewhere is "
            "NOT proof of reachability — the caller may itself be dead (that is how the Tools-grid "
            "views stayed 'wired' for weeks). Some of these are parked on purpose "
            "(ImmersiveStageView, BroadcastView while RTMP is unlinked); the test per entry is "
            "whether that parking is WRITTEN DOWN in CLAUDE.md. Undocumented + unreachable is the "
            "defect, not unreachable by itself."))

    # C2. A modal flag with no setter is a slot that can never open — and in this repo those
    # slots still cost their share of the SwiftUI metadata budget that causes the black screen.
    #
    # ⛔ The obvious spelling of "assigned something other than false" is
    # `rf"\b{name}\s*=\s*(?!false\b)"` and it is WRONG — it matches the declaration itself.
    # `\s*` backtracks to zero width, which slides the lookahead in front of the space, where
    # the text reads " false" and the negative lookahead for "false" therefore succeeds. The
    # check silently found nothing at all. Capture the right-hand token and compare it in code.
    flag_decl = re.compile(r"@State\s+(?:private\s+)?var\s+(show\w+|\w+Presented)\s*(?::|=)")
    setterless: list[str] = []
    for f, src in bodies.items():
        for m in flag_decl.finditer(src):
            name = m.group(1)
            rhs = re.findall(rf"\b{name}\s*=\s*([A-Za-z_$][\w.$]*)", src)
            sets = sum(1 for r in rhs if r != "false") + len(re.findall(rf"\b{name}\.toggle\(\)", src))
            # A `$name` binding handed to a child view or a helper CAN set it, so the flag is
            # not provably dead. `isPresented: $name` is the exception: a presentation modifier
            # only ever writes `false` back on dismiss, so it opens nothing. Without this
            # distinction the check accuses the four live chip panels (`isExpanded: $showMood`).
            bindings = re.findall(rf"(\w+)\s*:\s*\${name}\b", src)
            if any(label != "isPresented" for label in bindings):
                continue
            if sets == 0:
                line = src[:m.start()].count("\n") + 1
                setterless.append(f"{rel(f)}:{line}  @State {name} — never assigned anything but its default")
    if setterless:
        sec.findings.append(Finding(
            WARN,
            "Modal flags that nothing can ever set to true",
            sorted(setterless)[:20],
            "The modifier bound to such a flag is unreachable UI that still counts against the "
            "presentation-modifier budget (the 10.76.34 black-screen law). These are the FIRST "
            "place to look for a slot when a new modal is needed."))

    if not sec.findings:
        sec.clean_note = "Every View has a construction site; every modal flag has a setter."
    return sec


# ------------------------------------------------------------- D. do the docs match the codebase

def section_d() -> Section:
    sec = Section("D", "DOCS — do the numbers in CLAUDE.md still hold?")

    # ⛔ THE REASON THAT STOOD HERE WAS FALSE, and the correction is ~90 lines above in this same
    # file: `Sources/**/*.swift` MISSES a file placed directly in `Sources/`, because git's `**/`
    # needs an intervening directory. The two globs agree today only because no `.swift` sits
    # there — exactly the "happens to agree" trap the phantom-needle block names. The union stays
    # (it is harmless and makes the dedup explicit); only its justification was wrong.
    # Historic wording, kept so the claim is not re-derived:
    # `git ls-files 'Sources/**/*.swift'` already matches top-level files, so unioning it with
    # 'Sources/*.swift' by ADDING the lengths double-counts everything — the first run of this
    # reported 656 for a 328-file tree. Deduplicate on the path.
    src_count = len(set(tracked("Sources/**/*.swift")) | set(tracked("Sources/*.swift")))
    test_count = len(tracked("Tests/EchoelmusicTests/*.swift"))

    studio = ROOT / "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    modifiers = 0
    if studio.exists():
        for line in read(studio).splitlines():
            if re.match(r"\s*\.(sheet|fullScreenCover|alert|fileImporter)\s*\(", line):
                modifiers += 1

    claude = read(ROOT / "CLAUDE.md")
    quoted: list[str] = []
    for i, line in enumerate(claude.splitlines()):
        if re.search(r"\d+\s+Swift under|\d+ test files|presentation.modifier", line, re.I):
            quoted.append(f"CLAUDE.md:{i + 1}  {line.strip()[:150]}")

    sec.findings.append(Finding(
        INFO,
        "Counted now — compare against what CLAUDE.md claims",
        [f"Sources/**/*.swift (git-tracked)      = {src_count}",
         f"Tests/EchoelmusicTests/*.swift        = {test_count}",
         f"EchoelStudioView presentation modifiers (file-wide, line-initial) = {modifiers}"]
        + (["--- the lines that make a claim ---"] + quoted if quoted else []),
        "The modifier count is FILE-WIDE, not body-chain-only — a modifier nested inside another "
        "modifier's content closure is counted here but does not sit on the body's generic type. "
        "Read the quoted CLAUDE.md lines against these numbers before trusting either."))

    # --- what a session PAYS before its first line of work -------------------------------------
    #
    # #538 moved 589 616 B of count-chain provenance out of CLAUDE.md into memory/LEDGER_COUNTS.md.
    # The defect it repaired is not "the file was long" — it is that the executable law (audio-thread
    # bans, force-unwrap ban, EchoelValueField, the 3 Hz ceiling, the OSC address set) was ~2.7 % of
    # an always-loaded surface and is therefore the first thing a compaction summarises away.
    #
    # ⚠️ The ceiling is a WARN at 150 000 B and NOT the 45 000 B that the plan aspired to. Pinning
    # the aspiration would make this section red on a correct tree today, and a check that reds
    # correct work gets muted or deleted — with the law it carries (#364). Raise the ceiling only
    # together with a reason; lowering it is free.
    always = [ROOT / "CLAUDE.md"] + sorted((ROOT / ".claude/rules").glob("*.md"))
    sizes = [(rel(f), f.stat().st_size) for f in always if f.exists()]
    root_bytes = next((b for n, b in sizes if n == "CLAUDE.md"), 0)
    total = sum(b for _, b in sizes)
    ceiling = 150_000
    sec.findings.append(Finding(
        WARN if root_bytes > ceiling else INFO,
        f"Always-loaded surface = {total:,} B ({len(sizes)} files); CLAUDE.md = {root_bytes:,} B",
        [f"{b:>9,} B  {n}" for n, b in sorted(sizes, key=lambda x: -x[1])],
        f"CLAUDE.md is over the {ceiling:,} B ceiling — an accreting ledger has grown back into it. "
        "Move the PROVENANCE (count chains, superseded stands, retraction blocks that no longer "
        "guide a decision) to memory/LEDGER_COUNTS.md and leave a routing line. Delete nothing."
        if root_bytes > ceiling else
        "Under the ceiling. This number only moves in the wrong direction by accretion, so it is "
        "worth re-reading whenever a cycle adds a paragraph to CLAUDE.md rather than to a ledger."))

    # --- a routing line that does not resolve is worse than no routing line ---------------------
    #
    # CLAUDE.md deliberately narrates DELETED source files ("`PianoRollView.swift` IST GELÖSCHT"),
    # so a naive "every backticked path must exist" sweep would be a permanent flood — the failure
    # mode this whole skill warns about. Restricted to the four trees where a mention is always a
    # live pointer and never an obituary.
    routable = re.compile(r"`((?:memory|scripts|\.claude|docs)/[^`\s]+|[A-Za-z][\w/]*/CLAUDE\.md)`")
    missing: dict[str, list[int]] = {}
    for i, line in enumerate(claude.splitlines()):
        for hit in routable.findall(line):
            target = hit.rstrip(".,;:)")
            if "*" in target or "…" in target:
                continue
            if not (ROOT / target).exists():
                missing.setdefault(target, []).append(i + 1)
    # ⛔ THE FIRST VERSION REPORTED `.claude/settings.local.json` THREE TIMES, and that file is
    # SUPPOSED to be absent here: it is gitignored (it holds the GitHub token) and CLAUDE.md's own
    # text says "If token missing: ask the user to create it". Flagging a deliberately-absent file
    # is the cry-wolf failure this script's other comments already warn about, so an ignored path
    # is not a broken pointer. `git check-ignore` answers it for every case, not just that one.
    if missing:
        try:
            out = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--", *missing],
                                 capture_output=True, text=True, timeout=30)
            for ignored in out.stdout.splitlines():
                missing.pop(ignored.strip(), None)
        except (OSError, subprocess.SubprocessError) as exc:
            raise InstrumentUnavailable(f"git check-ignore could not run: {exc}") from exc
    broken = [f"CLAUDE.md:{n}  {t}" for t, ns in sorted(missing.items()) for n in ns]
    if broken:
        sec.findings.append(Finding(
            WARN, f"{len(broken)} routing target(s) in CLAUDE.md do not exist",
            broken[:20],
            "A pointer into memory/ scripts/ .claude/ docs/ or a directory CLAUDE.md is always a "
            "live instruction, never an obituary — a session follows it and finds nothing, then "
            "concludes the rule behind it was withdrawn (#472). Fix the path or move the prose."))

    return sec


# --------------------------------------------------------------------------------------- report

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--section", choices=list("ABCD"), help="run only one section")
    ap.add_argument("--quiet", action="store_true", help="print findings only, no clean sections")
    args = ap.parse_args()

    runners = {"A": section_a, "B": section_b, "C": section_c, "D": section_d}
    keys = [args.section] if args.section else list("ABCD")

    criticals = 0
    print("Echoel doctor — are the instruments telling the truth?\n")
    for key in keys:
        try:
            sec = runners[key]()
        except InstrumentUnavailable as exc:
            # Exit 2, distinct from both 0 (healthy) and 1 (found something). A caller that
            # treats "not 0" as failure still stops; a caller reading the code learns that the
            # doctor never looked, rather than that the repo is clean.
            print(f"⛔ INSTRUMENT UNAVAILABLE — section {key} could not be examined.")
            print(f"   {exc}")
            print("   The doctor did NOT find the repo healthy; it could not see it at all.")
            return 2
        if not sec.findings and args.quiet:
            continue
        print(f"── {sec.key}. {sec.title}")
        if not sec.findings:
            print(f"   ✅ {sec.clean_note}\n")
            continue
        for f in sec.findings:
            criticals += f.level == CRITICAL
            print(f"   {MARK[f.level]} [{f.level}] {f.title}")
            for e in f.evidence:
                print(f"        {e}")
            if f.fix:
                for chunk in _wrap(f.fix, 92):
                    print(f"        → {chunk}")
            print()

    print("── LIMITS (what this run did NOT check)")
    for line in [
        "Reachability is grep-based: it proves a NAME is never constructed, not that a surface is",
        "  unreachable at runtime. The chain to a rendering parent still has to be read by hand.",
        "Nothing here compiles or runs anything. A green doctor says the instruments look honest,",
        "  never that the code works.",
        "Sound, feel and device behaviour are outside its reach entirely — those need a listen.",
    ]:
        print(f"   {line}")
    print(f"\n{'❌' if criticals else '✅'} {criticals} critical finding(s).")
    return 1 if criticals else 0


def _wrap(text: str, width: int) -> list[str]:
    words, lines, cur = text.split(), [], ""
    for w in words:
        if cur and len(cur) + len(w) + 1 > width:
            lines.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}".strip()
    if cur:
        lines.append(cur)
    return lines


if __name__ == "__main__":
    sys.exit(main())
