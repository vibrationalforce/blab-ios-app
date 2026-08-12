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
