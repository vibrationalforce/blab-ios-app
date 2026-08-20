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

WHAT IT CHECKS. Three assertion shapes whose needle must exist in production code:
    XCTUnwrap(<x>.range(of: "NEEDLE") ...)
    XCTAssertEqual/GreaterThan[OrEqual](codeOccurrences(of: "NEEDLE" ...), N)   with N >= 1
    XCTAssertTrue(<recv>.contains("NEEDLE"))          — #665, and only where <recv> is
        PROVABLY source text: bound in the same file from `Self.codeText/read/body/
        rawSource/source`, in a file that names ONLY `Sources/` paths, with no `\(`
        interpolation in the needle.
Comments in Sources/ are stripped first, so a needle that survives only inside prose about
itself does NOT count as present — that is the `EchoelModalBank` trap in executable form.

⛔ WHY THE THIRD SHAPE IS SO NARROW, because a checker that overstates its reach is the thing
it guards against. #664 was a guard red on a correct tree for exactly this shape, and #663's
commit body cited THIS SCRIPT as independent confirmation while it extracted zero needles
from the file in question. The obvious widening — every `XCTAssertTrue(x.contains("N"))` —
was measured before it was written: 785 such needles in the bundle, 86 flagged on a CORRECT
tree. The receiver of a `.contains` may be source text, a produced string, a doc file, or a
file under `Tests/`; polarity alone does not say which. The provenance test above cuts 785
to 26. THAT IS 3 % REACH and it is stated rather than hidden: the alternative was 86 false
alarms, which is how a checker gets ignored — the same mechanism that made
`continue-on-error` invisible.

HONEST LIMITS, because a checker that overstates its reach is the thing it is guarding
against:
  · It does NOT cover negative assertions (`XCTAssertFalse(... .contains(X))`), where absence
    is the point. Distinguishing those needs the assertion's polarity, which these two shapes
    give and a bare `.contains` does not.
  · It does NOT cover needles built by interpolation or held in a `let`.
  · A needle present in a DIFFERENT file than the guard intends still counts as present. This
    finds dead needles, not misaimed ones. Worked example from #664: `route: "macOS HAL"` was
    asserted on `latencyBreadcrumb`'s body, had MOVED to `currentSessionLatency`, and is not
    flagged — it is alive in `Sources/`, just not where the guard looks. Its sibling
    `route: routeName` had left `Sources/` entirely and IS flagged.
  · It proves nothing about whether a guard RUNS. See #445.

VALIDATED, not assumed, once per shape. Shapes 1-2: run against e5956b9 it reports exactly
one hit — the known one — and against the commit that repaired it, zero. Shape 3: run against
5c9f386 it reports exactly one — `TheMeasuredLatencyReachesTheDiagLogTests.swift:308`,
`route: routeName`, the assertion #664 found red on a correct tree — and zero against the
commit that repaired it. A detector that has never found its own known positive is not a
measurement.

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

# #665, shape 3. `SOURCE_PATH` decides whether a guard FILE may be read at all: a file that
# names a `Tests/`, `docs/` or `scripts/` path may be asserting about something other than
# production code, and this script only knows about `Sources/`. `SOURCE_BIND` then decides
# which local names hold source text.
SOURCE_PATH = re.compile(
    r'"((?:Sources|Tests|docs|scripts|fastlane|memory|scratchpads|ContentPipeline)/[^"]*)"')
SOURCE_BIND = re.compile(
    r'\blet\s+([A-Za-z_]\w*)\s*=\s*(?:try\s+)?(?:XCTUnwrap\()?\s*'
    r'Self\.(?:codeText|read|body|rawSource|source)\b')
POSITIVE_CONTAINS = re.compile(
    r'XCTAssertTrue\(\s*(?:try )?([A-Za-z_]\w*)\.contains\(\s*"((?:[^"\\]|\\.)+)"\s*\)')

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

        # Shape 3 (#665). Comments are stripped FIRST here: this repo's guards quote their own
        # retracted needles in ⛔ blocks, and a scan that read those would report a finding
        # against a file's own history.
        guard_code = strip_comments(src)
        paths = set(SOURCE_PATH.findall(guard_code))
        if not paths or any(not p.startswith("Sources/") for p in paths):
            continue
        receivers = {m.group(1) for m in SOURCE_BIND.finditer(guard_code)}
        for match in POSITIVE_CONTAINS.finditer(guard_code):
            receiver = match.group(1)
            needle = match.group(2).replace('\\"', '"').replace("\\\\", "\\")
            if len(needle) < MIN_NEEDLE or "\\(" in needle or receiver not in receivers:
                continue
            if needle not in corpus:
                line = guard_code[:match.start()].count("\n") + 1
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
