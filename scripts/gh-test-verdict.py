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
    """Turn literal backslash-n into newlines when a document has none of its own.

    Guarded on `"\n" not in text` so a genuinely multi-line log that happens to contain
    an escaped sequence is left alone.
    """
    if "\n" not in text and "\\n" in text:
        return text.replace("\\n", "\n")
    return text


def load(path):
    return decode(open(path, encoding="utf-8", errors="replace").read())


SELFTEST_BODY = (
    "2026-01-01T00:00:00Z Test build Succeeded\n"
    "2026-01-01T00:00:01Z Test case 'A.testOne()' passed on 'Clone 1 of iPhone 17' (0.1 seconds)\n"
    "2026-01-01T00:00:02Z Test case 'A.testTwo()' failed on 'Clone 1 of iPhone 17' (0.2 seconds)\n"
    "2026-01-01T00:00:03Z Test case 'B.testThree()' failed on 'Clone 1 of iPhone 17' (0.3 seconds)\n"
    "2026-01-01T00:00:04Z ** TEST EXECUTE FAILED **\n"
)


def selftest():
    """Drive BOTH envelopes and assert the same verdict comes out of each (#738).

    The defect this replaces was not a wrong needle — every needle was right. It was a
    loader that returned an un-decoded string for a well-formed document, so the needles
    ran over one 250 kB line. A shape-level check is therefore the only kind that could
    have caught it; a fixture of one shape would have passed forever.
    """
    shapes = {
        "single-job  {job_id, logs_content}":
            json.dumps({"job_id": 1, "logs_content": SELFTEST_BODY}),
        "failed_only {logs: [{logs_content}]}":
            json.dumps({"logs": [{"logs_content": SELFTEST_BODY}], "run_id": 2}),
        "plain text (no envelope)": SELFTEST_BODY,
        "plain text, newlines already escaped": SELFTEST_BODY.replace("\n", "\\n"),
    }
    bad = 0
    for name, raw in shapes.items():
        text = decode(raw)
        passed = len(re.findall(r"Test case '[^']+' passed on ", text))
        failed = re.findall(r"Test case '([^']+)' failed on ", text)
        ok = (passed == 1 and failed == ["A.testTwo()", "B.testThree()"]
              and "Test build Succeeded" in text)
        bad += 0 if ok else 1
        print(f"  {'ok ' if ok else 'BAD'}  {name:38}  passed={passed}  failed={failed}")
    print("selftest: OK" if not bad else f"selftest: {bad} shape(s) MISREAD")
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
    compile_errors = [ln.strip() for ln in text.split("\n")
                      if (" error:" in ln or "❌" in ln)]
    # Anchored, non-greedy, and NOT dependent on line splitting (#738): on a document
    # that arrived as one line, the old line filter matched once and printed the whole
    # remainder of the log as if it were the name of a single failing test.
    failures = re.findall(r"Test case '([^']+)' failed on ", text)
    ran = len(re.findall(r"Test case '[^']+' passed on ", text))

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
    if not failures and not compile_errors:
        print("\nVERDICT: no failure in the FLUSHED log. #445 — a test name's ABSENCE "
              "proves nothing; only its presence proves it ran.")
    return 1 if (failures or compile_errors or build_failed) else 0


if __name__ == "__main__":
    sys.exit(main())
