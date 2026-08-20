#!/usr/bin/env python3
"""Find guard needles that MUST be present in Sources/ but are not.

WHY THIS EXISTS (#656). `Tests/CISmoke/TheNotchIsSlewedAndMonitorOnlyTests` anchored on the
literal "Input monitoring: engine restart failed". #650 routed monitoring outcomes through a
helper that OWNS the "Input monitoring: " prefix, so the call site stopped containing that
literal. `XCTUnwrap` on nil is a failure — the guard was RED on a correct tree for five
commits, and three status deltas in between said "nothing red is mine".

It survived because of the fog, not because it was subtle: #396 makes the CI/CD pipeline
report `failure` on EVERY push, and #445 established that a test name missing from the job
log proves nothing about whether it ran. A guard that reddens inside that fog looks exactly
like the simulator host dying. No gate can tell the difference; this script can, for one
specific and recurring shape.

WHAT IT CHECKS. Two assertion shapes whose needle must exist in production code:
    XCTUnwrap(<x>.range(of: "NEEDLE") ...)
    XCTAssertEqual/GreaterThan[OrEqual](codeOccurrences(of: "NEEDLE" ...), N)   with N >= 1
Comments in Sources/ are stripped first, so a needle that survives only inside prose about
itself does NOT count as present — that is the `EchoelModalBank` trap in executable form.

HONEST LIMITS, because a checker that overstates its reach is the thing it is guarding
against:
  · It does NOT cover negative assertions (`XCTAssertFalse(... .contains(X))`), where absence
    is the point. Distinguishing those needs the assertion's polarity, which these two shapes
    give and a bare `.contains` does not.
  · It does NOT cover needles built by interpolation or held in a `let`.
  · A needle present in a DIFFERENT file than the guard intends still counts as present. This
    finds dead needles, not misaimed ones.
  · It proves nothing about whether a guard RUNS. See #445.

VALIDATED, not assumed: run against e5956b9 it reports exactly one hit — the known one — and
against the commit that repaired it, zero. A detector that has never found its own known
positive is not a measurement.

Usage:  python3 scripts/dead-needles.py [repo-root]
Exit:   0 = no dead needles · 1 = at least one · 2 = could not look (no Tests/CISmoke)
"""
import glob
import os
import re
import sys

UNWRAP = re.compile(r'XCTUnwrap\([^)]*?range\(of:\s*"((?:[^"\\]|\\.)+)"')
POSITIVE_COUNT = re.compile(
    r'XCTAssert(?:Equal|GreaterThanOrEqual|GreaterThan)\(\s*(?:Self\.)?'
    r'(?:codeOccurrences|count)\(of:\s*"((?:[^"\\]|\\.)+)"[^)]*\)[^,]*,\s*([1-9]\d*)')

MIN_NEEDLE = 8   # shorter literals are punctuation or fragments, not anchors


def strip_comments(text):
    """Blank // and /* */ comments; a marker inside a string literal is not a comment."""
    out, in_block = [], False
    for raw in text.split("\n"):
        line, i, n = [], 0, len(raw)
        in_string = False
        while i < n:
            c = raw[i]
            nxt = i + 1
            has = nxt < n
            if in_block:
                if has and c == "*" and raw[nxt] == "/":
                    in_block = False
                    i = nxt + 1
                else:
                    i = nxt
                continue
            if in_string:
                if c == "\\" and has:
                    line.append(c)
                    line.append(raw[nxt])
                    i = nxt + 1
                    continue
                if c == '"':
                    in_string = False
                line.append(c)
                i = nxt
                continue
            if has and c == "/" and raw[nxt] == "/":
                break
            if has and c == "/" and raw[nxt] == "*":
                in_block = True
                i = nxt + 1
                continue
            if c == '"':
                in_string = True
            line.append(c)
            i = nxt
        out.append("".join(line))
    return "\n".join(out)


def main(root="."):
    guards = sorted(glob.glob(os.path.join(root, "Tests/CISmoke/*.swift")))
    if not guards:
        print("dead-needles: no Tests/CISmoke/*.swift found — nothing to check", file=sys.stderr)
        return 2

    chunks = []
    for base, _, files in os.walk(os.path.join(root, "Sources")):
        for name in files:
            if name.endswith(".swift"):
                path = os.path.join(base, name)
                with open(path, encoding="utf-8") as handle:
                    chunks.append(strip_comments(handle.read()))
    corpus = "\n".join(chunks)
    if not corpus:
        print("dead-needles: Sources/ is empty or absent — nothing to check", file=sys.stderr)
        return 2

    dead = []
    for guard in guards:
        with open(guard, encoding="utf-8") as handle:
            src = handle.read()
        for match in list(UNWRAP.finditer(src)) + list(POSITIVE_COUNT.finditer(src)):
            needle = match.group(1).replace('\\"', '"').replace("\\\\", "\\")
            if len(needle) < MIN_NEEDLE:
                continue
            if needle not in corpus:
                line = src[:match.start()].count("\n") + 1
                dead.append((os.path.relpath(guard, root), line, needle))

    if not dead:
        print(f"dead-needles: OK — {len(guards)} guard file(s), no dead must-be-present needle")
        return 0
    print(f"dead-needles: {len(dead)} needle(s) asserted present but ABSENT from Sources/:")
    for path, line, needle in dead:
        print(f"  {path}:{line}  {needle!r}")
    print("\nEach is a guard that FAILS on a correct tree. Re-anchor it on a literal that")
    print("exists, and assert that literal's uniqueness while you are there (#408).")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
