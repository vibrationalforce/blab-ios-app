#!/usr/bin/env python3
"""Read an `mcp__github__get_job_logs` overflow file and print the TEST verdict.

⛔ WHY THIS EXISTS (#679). Three separate needle sets were used to call a CI gate
"clean" in this session, and two of them could not match the format the log actually
uses:

  · `error:`   — xcbeautify renders a compile error as `❌` (fixed in #667).
  · `failed (` — an xcodebuild test failure line reads
        Test case 'Suite.testName()' failed on 'Clone 1 of iPhone 17 …' (0.003 seconds)
    so the literal `failed (` NEVER occurs. On `34be877` this reported "0 failures"
    while FOUR named tests had failed, and the commit was called green.

The log is ALSO a single JSON blob with escaped newlines, so a plain `split("\n")`
finds one line and every per-line filter silently returns nothing.

⛔ AND THAT SECOND HALF CAME BACK IN A NEW SHAPE (#738). `get_job_logs` writes TWO
different envelopes and this script only decoded one of them:

  · `run_id=… failed_only=true` → {"logs": [{"logs_content": "…"}], "run_id": …}
  · `job_id=…`                  → {"job_id": …, "logs_content": "…"}   ← NOT handled

On the single-job shape `json.loads` SUCCEEDED, `"logs" not in blob` was true, and the
loader fell through to `return raw` — handing every filter the un-decoded string with
2 999 literal backslash-n sequences and zero real newlines. Measured on `7644011`:
`tests observed passing: 1` where **136** passed. Worse, on a run that really fails, the
one giant line contains both needles at once, so the failure list printed **1** entry
where **2** tests had failed — and the text it printed began with the name of a test that
had PASSED. Not silent (exit stayed 1), but an instrument that undercounts failures and
labels a passing test as the failing one is the class this file exists to kill.

The lesson is narrower than "handle both shapes": **a JSON parse that succeeds is not a
decode that worked.** The fall-through returned raw text on a well-formed document whose
only sin was a different key. Every branch of `load()` now asserts it is returning text
that actually came out of the envelope, and `--selftest` drives both shapes.

Usage: python3 scripts/gh-test-verdict.py <overflow-file.json>
       python3 scripts/gh-test-verdict.py --selftest
Exit 0 = no test failure found, 1 = failures listed, 2 = could not read.
"""
import json
import re
import sys


def decode(raw):
    """Text of a `get_job_logs` overflow file, whichever envelope it uses (#738).

    Returns real newlines or nothing useful — never a half-decoded string. The
    `unescape` tail is the belt: if a shape ever arrives that this function does not
    know, it is better to split a string that was never JSON than to hand every
    per-line filter one 250 kB line and print confident numbers off it.
    """
    try:
        blob = json.loads(raw)
    except json.JSONDecodeError:
        return unescape(raw)                      # already plain text
    if isinstance(blob, dict) and isinstance(blob.get("logs"), list):
        return "\n".join(j.get("logs_content", "") for j in blob["logs"])
    if isinstance(blob, dict) and isinstance(blob.get("logs_content"), str):
        return blob["logs_content"]               # single-job shape (#738)
    return unescape(raw)


def unescape(text):
    """Turn literal backslash-n into newlines when a document is mostly escaped.

    ⛔ THE FIRST VERSION GUARDED ON `"\n" not in text` AND ONE REAL NEWLINE DEFEATED IT
    (#739). A file read off disk normally ends in a newline, so an otherwise fully escaped
    document scored `realNewlines == 1` and was left alone — after which every per-line
    filter saw one 250 kB line again, which is the whole #738 defect wearing a trailing `\n`.
    The honest test is the RATIO, not the presence: a document with more escaped sequences
    than real newlines is an escaped document. A genuine multi-line log that happens to quote
    a few `\\n` has far more real newlines and is left alone.
    """
    if text.count("\\n") > text.count("\n"):
        return text.replace("\\n", "\n")
    return text


def load(path):
    return decode(open(path, encoding="utf-8", errors="replace").read())


# ── The two renderings xcodebuild can emit, and why BOTH are here (#739) ────────────────
#
# xcbeautify (what CI uses today):
#     Test case 'Suite.testName()' failed on 'Clone 1 of iPhone 17 …' (0.039 seconds)
# plain xcodebuild (no formatter — a local run, or a workflow that drops the pipe):
#     Test Case '-[SuiteTests testName]' failed (0.001 seconds).
#
# ⛔ #738 ANCHORED ONLY ON THE FIRST AND ITS GUARD THEN FORBADE THE SECOND OUTRIGHT. Measured:
# on a plain-xcodebuild log the tool printed `TEST FAILURES: 0` and EXITED 0 — a silent green,
# strictly worse than the loud-but-wrong reading #679 paid four failing tests to find. Latent
# rather than live (today's pipeline only emits the first form), and recorded because that is
# exactly how #679 started: a discriminator that was right about the format it had seen.
#
# The `failed (` needle is BANNED ALONE and REQUIRED IN THE ALTERNATION. #679's mistake was
# searching for it INSTEAD of `" failed on "`; the repair is both, never either.
PASS_LINE = re.compile(r"Test [Cc]ase '([^']+)' passed", re.MULTILINE)
FAIL_LINE = re.compile(r"Test [Cc]ase '([^']+)' (?:failed on |failed \()", re.MULTILINE)
FAILED_OR_PASSED_PASS = PASS_LINE

# ⛔ #806 — THE TOOL REPORTED PASSES AND FAILURES AND WAS SILENT ABOUT SKIPS, while 268 of the
# 358 files in `Tests/CISmoke` can throw `XCTSkip`. A skipped guard is not a passing guard: it
# asserted nothing. The tool never MIS-read one (the verb differs, so a skip was never counted
# as a pass) — it simply did not mention them, and `Tests/CISmoke/CLAUDE.md` §5 tells every
# session to read this script's verdict instead of hand-rolling needles. "TEST FAILURES: 0" was
# therefore readable as "the bundle is fine" while an anchor-miss quietly skipped a guard. That
# is the 2026-07-28 shape that this whole directory exists to prevent: 14 hours of "success"
# over a build that was not building.
#
# ⚠️ THIS NEEDLE IS DERIVED, NOT OBSERVED — stated plainly because `.claude/rules/context.md` §4
# bans hand-rolled needles, and #679/#738/#778 are three separate incidents of a session
# inventing a spelling that could not match. What is PROVEN here is the LINE SHAPE:
# `Test [Cc]ase '<name>' <verb>…` holds for two verbs across both envelopes, and `PASS_LINE`
# takes exactly this form with no suffix, which is why it covers xcbeautify and plain
# xcodebuild alike. Only the third verb is assumed, and it is Apple's documented wording for
# `XCTSkip`. No log in this repo's reach contains a skip line — measured on the #805 run
# (`67eef12`): 4 occurrences of "skipped", all of them GitHub Actions step outcomes, zero test
# results. So the selftest below drives a shape this session CONSTRUCTED, not one it saw; if a
# real skip ever prints differently, fix it here and say so, do not add a fourth needle set.
SKIP_LINE = re.compile(r"Test [Cc]ase '([^']+)' skipped", re.MULTILINE)

# ⛔ #807 — THE JOB LOG IS NOT THE TEST RUN. IT IS `tail -200 test.log`, AND EVERY VERDICT THIS
# SCRIPT HAS EVER PRINTED WAS COMPUTED OVER THAT WINDOW ALONE.
#
# Measured on `aec6cea`, `67eef12` and `92ddb00`, from COMPLETE job logs (`original_length`
# matched the decoded line count, so these are not tails of my own making):
#   · `ci.yml` runs `xcodebuild test-without-building … 2>&1 | tee test.log | xcpretty`, and
#     xcpretty printed NOTHING for a twelve-minute run — the live window is 16 lines: the
#     command echo, the env block, and `##[error]Process completed with exit code 65`.
#   · The next step is `Print test log on failure` → `tail -200 test.log`. That 210-line block
#     (200 tail lines plus the step scaffolding) is where ALL 134 result lines and the
#     `** TEST EXECUTE FAILED **` marker live, in every run measured.
#
# CONSEQUENCE, and it is the reason this block exists rather than a comment somewhere: a test
# that FAILS outside the last 200 raw lines produces no line in the job log at all, so this
# script prints `TEST FAILURES: 0` over a run that really failed. That is a silent green, the
# same shape as #738 and strictly worse, because it is structural rather than a needle bug.
# It also explains #686 exactly — the test that could not pass showed no result line because it
# was not in the window, not because a clone swallowed it.
#
# ⚠️ IT ALSO RETIRES THE "FLUSH LOTTERY" MODEL. `Tests/CISmoke/CLAUDE.md` §5 said the log
# carries the non-deterministic subset a surviving clone managed to flush. Measured across four
# consecutive runs, 133 of 135 result lines are IDENTICAL — a fixed tail, not a lottery.
# `test.log` itself is complete; only the job log is cut.
#
# The window is READ from the log rather than assumed, so if the workflow ever prints more (or
# uploads `TestResults`, which it already produces via `-resultBundlePath`), this reports the
# new reality instead of a remembered one.
TAIL_STEP = re.compile(r"tail -(\d+) (\S*test\.log)")


def find_failures(text):
    return FAIL_LINE.findall(text)


def find_skips(text):
    return SKIP_LINE.findall(text)


SELFTEST_BODY = (
    "2026-01-01T00:00:00Z Test build Succeeded\n"
    "2026-01-01T00:00:01Z Test case 'A.testOne()' passed on 'Clone 1 of iPhone 17' (0.1 seconds)\n"
    "2026-01-01T00:00:02Z Test case 'A.testTwo()' failed on 'Clone 1 of iPhone 17' (0.2 seconds)\n"
    "2026-01-01T00:00:03Z Test case 'B.testThree()' passed on 'Clone 1 of iPhone 17' (0.3 seconds)\n"
    "2026-01-01T00:00:04Z Test case 'B.testFour()' failed on 'Clone 1 of iPhone 17' (0.4 seconds)\n"
    "2026-01-01T00:00:05Z Test case 'C.testFive()' passed on 'Clone 1 of iPhone 17' (0.5 seconds)\n"
    "2026-01-01T00:00:06Z Test case 'C.testSix()' skipped on 'Clone 1 of iPhone 17' (0.0 seconds)\n"
    "2026-01-01T00:00:07Z Test Case '-[DTests testSeven]' skipped (0.0 seconds).\n"
    "2026-01-01T00:00:08Z /src/Foo.swift:12:3: error: cannot find 'Bar' in scope\n"
    "2026-01-01T00:00:09Z ** TEST EXECUTE FAILED **\n"
)
SELFTEST_LINES = SELFTEST_BODY.count("\n")


def selftest():
    """Drive every envelope AND ASSERT THE DECODE, not just the verdict computed off it.

    ⛔ THE FIRST VERSION OF THIS SWEEP WAS A CONTROL ITS OWN KNOWN-POSITIVE PASSED (#739),
    which is #735's lesson arriving one commit later in the same session. Measured: run
    #738's four shape checks against #737's BROKEN loader and all four report `ok`. Every
    assertion it made — `re.findall` over the whole text, a substring test — is
    NEWLINE-INDEPENDENT, and JSON does not escape single quotes, so the needles sit in the
    un-decoded document verbatim. It asserted the ANSWER while the DEFECT was in the INPUT.

    Three things make this version discriminate, and each maps to a way #738 went wrong:
      · `newlines` — the decode itself. A one-line document fails here first, whatever any
        regex says about it.
      · `greedy` — the exact expression #737 shipped (`Test case .* passed on ` with a greedy
        `.*`). On correctly decoded text it counts 3; on one line it counts 1. This is the
        original symptom, kept as a live canary rather than a story in a comment.
      · `line_filter` — the exact predicate #738 removed. On one line it matches once for the
        whole log. Keeping it here means the bug can never be reintroduced unnoticed, even
        though production no longer uses it.
    The fixture carries THREE passes and TWO failures on purpose: with one of each, a count
    of 1 is correct by accident and every one of these canaries stays quiet.
    """
    shapes = {
        "single-job  {job_id, logs_content}":
            json.dumps({"job_id": 1, "logs_content": SELFTEST_BODY}),
        "failed_only {logs: [{logs_content}]}":
            json.dumps({"logs": [{"logs_content": SELFTEST_BODY}], "run_id": 2}),
        "plain text (no envelope)": SELFTEST_BODY,
        "plain text, newlines escaped": SELFTEST_BODY.replace("\n", "\\n"),
        "plain text, escaped + trailing real newline":
            SELFTEST_BODY.replace("\n", "\\n") + "\n",
    }
    bad = 0
    for name, raw in shapes.items():
        text = decode(raw)
        newlines = text.count("\n")
        greedy = len(re.findall(r"Test case .* passed on ", text))
        line_filter = len([ln for ln in text.split("\n")
                           if "Test case " in ln and " failed on " in ln])
        passed = len(PASS_LINE.findall(text))
        failed = find_failures(text)
        errors = len([ln for ln in text.split("\n") if " error:" in ln])
        # TWO skips, one per renderer, so a needle that only knows xcbeautify counts 1 and
        # is caught — the #738 lesson applied to the third verb before it can cost anything.
        skipped = find_skips(text)
        ok = (newlines >= SELFTEST_LINES
              and greedy == 3 and line_filter == 2 and errors == 1
              and passed == 3 and failed == ["A.testTwo()", "B.testFour()"]
              and skipped == ["C.testSix()", "-[DTests testSeven]"]
              and "Test build Succeeded" in text)
        bad += 0 if ok else 1
        print(f"  {'ok ' if ok else 'BAD'}  {name:44}  nl={newlines} greedy={greedy} "
              f"lines={line_filter} err={errors} pass={passed} fail={len(failed)} "
              f"skip={len(skipped)}")

    # A renderer sweep, separate because it is about the FORMAT and not the envelope.
    renders = {
        "xcbeautify":       "Test case 'S.testA()' failed on 'Clone 1' (0.1 seconds)",
        "plain xcodebuild": "Test Case '-[STests testA]' failed (0.1 seconds).",
    }
    for name, line in renders.items():
        hit = find_failures(line)
        good = len(hit) == 1
        bad += 0 if good else 1
        print(f"  {'ok ' if good else 'BAD'}  renderer {name:34}  -> {hit}")

    skips = {
        "xcbeautify":       "Test case 'S.testA()' skipped on 'Clone 1' (0.1 seconds)",
        "plain xcodebuild": "Test Case '-[STests testA]' skipped (0.1 seconds).",
    }
    for name, line in skips.items():
        hit = find_skips(line)
        # A skip must NOT be counted as a pass or a failure — that is the whole point.
        good = len(hit) == 1 and not PASS_LINE.findall(line) and not find_failures(line)
        bad += 0 if good else 1
        print(f"  {'ok ' if good else 'BAD'}  skip-renderer {name:29}  -> {hit}")

    # The WINDOW detector (#807). Read from the log, never assumed — so both answers must be
    # reachable: a log that carries the tail step, and one that does not.
    windows = {
        "tail step present": ("2026-01-01T00:00:00Z ##[group]Run tail -200 test.log\n", "200"),
        "tail step renamed": ("2026-01-01T00:00:00Z ##[group]Run tail -40 build/test.log\n", "40"),
        "no tail step":      ("2026-01-01T00:00:00Z ##[group]Run echo done\n", None),
    }
    for name, (line, expected) in windows.items():
        hit = TAIL_STEP.search(line)
        got = hit.group(1) if hit else None
        good = got == expected
        bad += 0 if good else 1
        print(f"  {'ok ' if good else 'BAD'}  window {name:33}  -> {got}")

    print("selftest: OK" if not bad else f"selftest: {bad} check(s) MISREAD")
    return 0 if not bad else 1


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        return selftest()
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    text = load(sys.argv[1])
    if not text.strip():
        print("INSTRUMENT UNAVAILABLE — empty log")
        return 2

    build = "Test build Succeeded" in text
    execute_failed = "TEST EXECUTE FAILED" in text
    build_failed = "TEST BUILD FAILED" in text
    # A repo-file `error:` or an xcbeautify `❌` means YOUR commit; an error naming
    # only an SDK/module-cache path is infrastructure (#478).
    # DELIBERATELY line-based, and it must stay that way: #478's discriminator is "does this
    # error line name a repo file or only an SDK path", which needs the WHOLE line. Its
    # correctness therefore rests entirely on `decode()`; that is why the selftest asserts the
    # decode itself (#739) and not just the verdict computed off it.
    compile_errors = [ln.strip() for ln in text.split("\n")
                      if (" error:" in ln or "❌" in ln)]
    # Anchored, non-greedy, and NOT dependent on line splitting (#738): on a document
    # that arrived as one line, the old line filter matched once and printed the whole
    # remainder of the log as if it were the name of a single failing test.
    failures = find_failures(text)
    skips = find_skips(text)
    window = TAIL_STEP.search(text)
    ran = len(FAILED_OR_PASSED_PASS.findall(text))

    if window:
        print(f"WINDOW            : job log carries only `tail -{window.group(1)} "
              f"{window.group(2)}` — a failure before that window does NOT appear here (#807)")
    else:
        print("WINDOW            : no `tail -N test.log` step seen — treating the log as whole")
    print(f"build-for-testing : {'Succeeded' if build else 'NOT SEEN'}")
    print(f"TEST BUILD FAILED : {build_failed}")
    print(f"TEST EXECUTE FAILED: {execute_failed}   (#396 — expected on every push)")
    print(f"tests observed passing: {ran}")
    print(f"compile-error lines   : {len(compile_errors)}")
    for line in compile_errors[:10]:
        print("   ", line[:200])
    print(f"TEST FAILURES         : {len(failures)}")
    for line in failures:
        print("   ", line[:200])
    print(f"TESTS SKIPPED         : {len(skips)}")
    for line in skips:
        print("   ", line[:200])
    if skips:
        # Non-zero exit on a skip is deliberate, and it is NOT the #665 false-alarm trap:
        # this bundle has no legitimately-skippable test — every `XCTSkip` here guards an
        # ANCHOR, and §4 says a missing anchor must FAIL rather than pass on less. A skipped
        # guard asserted nothing while looking exactly like one that did. If a genuinely
        # environment-dependent test ever belongs here, name it in this script rather than
        # loosening the check — printing alone is not enough, which is the one thing the
        # 2026-07-28 masked-gate incident settled.
        print("\nVERDICT: a guard SKIPPED. A skip is not a pass — it asserted nothing. "
              "Find its `XCTSkip` and re-anchor it (#454); do not read this run as clean.")
    elif not failures and not compile_errors:
        scope = (f"the last {window.group(1)} lines of {window.group(2)}"
                 if window else "the whole job log")
        print(f"\nVERDICT: no failure and no skip IN {scope.upper()}. That is NOT "
              "'the suite passed' (#807): the job log is a tail, so a failure earlier in the "
              "run leaves no trace here. #445 — a test name's ABSENCE proves nothing; only "
              "its presence proves it ran.")
    return 1 if (failures or compile_errors or build_failed or skips) else 0


if __name__ == "__main__":
    sys.exit(main())
