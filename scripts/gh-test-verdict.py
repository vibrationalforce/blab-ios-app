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
finds one line and every per-line filter silently returns nothing. Both halves of
that mistake are closed here so no future session has to rediscover either.

Usage: python3 scripts/gh-test-verdict.py <overflow-file.json>
Exit 0 = no test failure found, 1 = failures listed, 2 = could not read.
"""
import json
import re
import sys


def load(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    try:
        blob = json.loads(raw)
    except json.JSONDecodeError:
        return raw          # already plain text
    if isinstance(blob, dict) and "logs" in blob:
        return "\n".join(j.get("logs_content", "") for j in blob["logs"])
    return raw


def main():
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
    failures = [ln.split("Test case ", 1)[1].strip()
                for ln in text.split("\n")
                if "Test case " in ln and " failed on " in ln]
    ran = len(re.findall(r"Test case .* passed on ", text))

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
