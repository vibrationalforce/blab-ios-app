#!/usr/bin/env python3
"""Find COUNT PINS in Tests/CISmoke that no longer match the source they pin.

WHY THIS EXISTS, and it is one paid-for defect, not a hypothesis. #903 found a pin
that had been RED ON A CORRECT TREE for thirteen commits: a guard asserted eight
`EchoelCrashLog.breadcrumb(` sites in `AudioConfiguration.swift`, #888 added three and
did not come back to it. Nothing caught it because the CI/CD pipeline reports `failure`
on EVERY push (#396), so a genuinely red guard is indistinguishable from the host dying,
and §5 of `Tests/CISmoke/CLAUDE.md` says a test name's ABSENCE from the job log proves
nothing. A count pin is exactly the shape that rots silently: the code changes
CORRECTLY, and the number beside it does not follow.

    python3 scripts/count-pins.py            # 0 = every resolved pin matches
    python3 scripts/count-pins.py --all      # also list the pins it could NOT resolve
    python3 scripts/count-pins.py --selftest # after touching this file

VALIDATED AGAINST ITS OWN KNOWN POSITIVE — §4: a detector that has never found the
defect it was written for is not a measurement. Extract the two files of the tree that
CARRIED the #903 defect into a scratch dir mirroring the repo layout and point `--root`
at it; it reports exactly one RED, `pinned 8, actual 11`, and nothing else:

    git show 38b411e:Tests/CISmoke/TheEngineLifecycleSpeaksInTheDiagLogTests.swift > …
    git show 38b411e:Sources/Echoelmusic/Audio/AudioConfiguration.swift          > …
    python3 scripts/count-pins.py --root <that dir>

On the repaired tree the same run is clean. It also found TWO further reds on its first
pass over the live tree — `TheFailedRestartHandsOverToDegradedTests`, in OPPOSITE
directions (a fifth helper call nobody counted, a pause site #823 had turned into a
stop) — both hand-verified with a plain `grep` before being believed.

HONEST LIMITS — read them before obeying a finding (#665: a checker with false alarms
is a checker nobody reads, so its blind spots are part of its output):

 1. It reads TWO syntactic shapes and nothing else:
        XCTAssertEqual(occurrences(of: "<literal>", in: <var>), <N>
        XCTAssertEqual(<var>.components(separatedBy: "<literal>").count - 1, <N>
    A pin written any other way is invisible to it. It does not claim completeness.
 2. An INTERPOLATED needle (`"\\"\\(step)"`) is reported as unresolved, never as a
    finding. The first draft counted the literal text `\\(step)` and reported a pin as
    red that is green — a false alarm on the very first run, which is why this is a
    hard exclusion and not a best effort.
 3. The stripper is chosen per TEST FILE by a heuristic: `SourceText.codeOnly` if the
    file mentions it, otherwise the line-DELETING shape the private helpers use. Those
    two disagree only when a needle spans a blanked line, which no shape here does —
    but a file that does something a third way will be mis-stripped. The `codeOnly`
    port is imported from `window-margins.py`, not copied (#416).
 4. It resolves `let <var> = <fn>("<path>")` and `let <var> = <fn>(Self.<const>)`,
    taking the LAST binding before the assertion. A variable bound in a helper, or by
    a computed property, is unresolved.
 5. A MATCH is not a proof the guard is meaningful — only that its arithmetic holds.
    It says nothing about whether the pin is anchored on the right token (#367/#408).
"""

import argparse
import glob
import importlib.util
import os
import pathlib
import re
import sys

_spec = importlib.util.spec_from_file_location(
    "_wm", pathlib.Path(__file__).with_name("window-margins.py"))
_wm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_wm)

SHAPE_A = re.compile(
    r'XCTAssertEqual\(\s*occurrences\(of:\s*"((?:[^"\\]|\\.)*)",\s*in:\s*(\w+)\s*\),\s*(\d+)')
SHAPE_B = re.compile(
    r'XCTAssertEqual\(\s*(\w+)\.components\(\s*separatedBy:\s*"((?:[^"\\]|\\.)*)"\s*\)'
    r'\.count\s*-\s*1,\s*(\d+)')
BIND_LITERAL = re.compile(r'let\s+(\w+)\s*=\s*(?:try\s+)?\w+\(\s*"([^"]+\.swift)"\s*\)')
BIND_CONST = re.compile(r'let\s+(\w+)\s*=\s*(?:try\s+)?\w+\(\s*Self\.(\w+)\s*\)')
CONST = re.compile(r'static let (\w+)\s*=\s*"([^"]+\.swift)"')


def unescape(literal):
    """Swift source escapes → the bytes the needle actually matches."""
    out, i, n = [], 0, len(literal)
    while i < n:
        c = literal[i]
        if c == "\\" and i + 1 < n:
            nxt = literal[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, "\\" + nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def drop_comment_lines(text):
    return "\n".join(l for l in text.split("\n") if not l.strip().startswith("//"))


def resolve_path(raw):
    if raw.startswith("Sources/"):
        return raw
    return os.path.join("Sources/Echoelmusic", raw.lstrip("/"))


def pins(root):
    """Yield (test_file, needle, pinned, source_path, blank_stripper) or an unresolved note."""
    for test in sorted(glob.glob(os.path.join(root, "Tests/CISmoke/*.swift"))):
        text = open(test, encoding="utf-8").read()
        consts = dict(CONST.findall(text))
        binds = {}
        for m in BIND_LITERAL.finditer(text):
            binds.setdefault(m.group(1), []).append((m.start(), m.group(2)))
        for m in BIND_CONST.finditer(text):
            if m.group(2) in consts:
                binds.setdefault(m.group(1), []).append((m.start(), consts[m.group(2)]))
        blanks = "SourceText.codeOnly" in text
        for rx, shape in ((SHAPE_A, "A"), (SHAPE_B, "B")):
            for m in rx.finditer(text):
                if shape == "A":
                    needle, var, pinned = m.group(1), m.group(2), int(m.group(3))
                else:
                    var, needle, pinned = m.group(1), m.group(2), int(m.group(3))
                line = text[:m.start()].count("\n") + 1
                if "\\(" in needle:                       # LIMIT 2
                    yield (test, line, needle, pinned, None, blanks, "interpolated needle")
                    continue
                earlier = [p for pos, p in binds.get(var, []) if pos < m.start()]
                if not earlier:
                    yield (test, line, needle, pinned, None, blanks, f"`{var}` not bound to a path")
                    continue
                yield (test, line, needle, pinned, resolve_path(earlier[-1]), blanks, None)


def run(root, show_all):
    cache = {}
    findings, unresolved, checked = [], [], 0
    for test, line, needle, pinned, path, blanks, why in pins(root):
        if why is not None:
            unresolved.append((test, line, needle, why))
            continue
        full = os.path.join(root, path)
        if full not in cache:
            try:
                raw = open(full, encoding="utf-8").read()
            except OSError:
                cache[full] = None
            else:
                cache[full] = (_wm.code_only(raw), drop_comment_lines(raw))
        pair = cache[full]
        if pair is None:
            unresolved.append((test, line, needle, f"cannot read {path}"))
            continue
        actual = pair[0 if blanks else 1].count(unescape(needle))
        checked += 1
        if actual != pinned:
            findings.append((test, line, needle, pinned, actual, path))

    for test, line, needle, pinned, actual, path in findings:
        print(f"RED  {os.path.basename(test)}:{line}  pinned {pinned}, actual {actual}"
              f"  needle={needle[:56]!r}  in {os.path.basename(path)}")
    if show_all:
        for test, line, needle, why in unresolved:
            print(f"  unresolved {os.path.basename(test)}:{line}  ({why})"
                  f"  needle={needle[:40]!r}")
    print(f"\ncount-pins: {checked} pin(s) checked, {len(findings)} RED, "
          f"{len(unresolved)} unresolved.")
    print("  'unresolved' means THIS TOOL could not read the pin — never that the guard "
          "is wrong. Run with --all to list them.")
    if not findings:
        print("  A clean run means the arithmetic holds, not that the pins are anchored "
              "well (LIMIT 5).")
    return 1 if findings else 0


def selftest():
    cases = [
        ("plain", 'XCTAssertEqual(occurrences(of: "abc", in: code), 3', ("abc", "code", 3)),
        ("escaped quote",
         'XCTAssertEqual(occurrences(of: "say \\"hi\\"", in: code), 1', ('say \\"hi\\"', "code", 1)),
        ("shape B", None, None),
    ]
    ok = True
    m = SHAPE_A.search(cases[0][1])
    if not (m and m.group(1) == "abc" and m.group(2) == "code" and m.group(3) == "3"):
        print("selftest FAIL: plain shape A"); ok = False
    m = SHAPE_A.search(cases[1][1])
    if not (m and m.group(1) == 'say \\"hi\\"'):
        print("selftest FAIL: escaped quote inside the needle"); ok = False
    m = SHAPE_B.search('XCTAssertEqual(file.components(separatedBy: "x(").count - 1, 5')
    if not (m and m.group(1) == "file" and m.group(2) == "x(" and m.group(3) == "5"):
        print("selftest FAIL: shape B"); ok = False
    if unescape('a\\"b') != 'a"b':
        print("selftest FAIL: unescape of an escaped quote"); ok = False
    if unescape("a\\nb") != "a\nb":
        print("selftest FAIL: unescape of a newline"); ok = False
    if unescape("a\\(b") != "a\\(b":
        print("selftest FAIL: an interpolation marker must survive unescape unchanged"); ok = False
    # LIMIT 2: an interpolated needle must be reported unresolved, never counted.
    if "\\(" not in 'occurrences(of: "\\"\\(step)", in: code)':
        print("selftest FAIL: the interpolation guard cannot see its own case"); ok = False
    # The stripper must be the faithful one: a `//` inside a string literal is CODE.
    if _wm.code_only('let s = "http://x"') != 'let s = "http://x"':
        print("selftest FAIL: imported stripper cut inside a string literal"); ok = False
    if _wm.code_only("code() // tail").rstrip() != "code()":
        print("selftest FAIL: imported stripper kept a trailing comment"); ok = False
    print(f"selftest: {'OK, 8 checks' if ok else 'FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="also list unresolved pins")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default=".")
    args = ap.parse_args()
    sys.exit(selftest() if args.selftest else run(args.root, args.all))
