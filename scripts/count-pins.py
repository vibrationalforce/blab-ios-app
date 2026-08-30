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
        XCTAssertEqual([code]occurrences(of: "<literal>", in: <var>), <N>
        XCTAssertEqual(<var>.components(separatedBy: "<literal>").count - 1, <N>
    A pin written any other way is invisible — notably a TWO-STATEMENT pin
    (`let hits = …count - 1` … `XCTAssertEqual(hits, N)`). It does not claim
    completeness, and the summary line says so rather than implying a census.
    ⛔ #905: the first draft demanded the bare name `occurrences`, so it never saw the
    `codeOccurrences` spelling — which is the LARGER half (73 vs 51 at writing) and the
    one `dead-needles.py` already parses. Reach went 55 → 136 checked for two regex
    characters, with no new red. A tool that silently reads the smaller half while
    printing a total is worse than one that reads nothing.
 2. An INTERPOLATED needle (`"\\"\\(step)"`) is reported as unresolved, never as a
    finding. The first draft counted the literal text `\\(step)` and reported a pin as
    red that is green — a false alarm on the very first run, which is why this is a
    hard exclusion and not a best effort.
 3. The stripper is chosen per TEST FILE by a heuristic: `SourceText.codeOnly` if the
    file mentions it, otherwise the line-DELETING shape the private helpers use. The
    `codeOnly` port is imported from `window-margins.py`, not copied (#416).
    ⛔ #905: this said the two "disagree only when a needle spans a blanked line", and
    that is the RAREST of three divergence classes, not the only one. The two common
    ones run the other way — a needle sitting in a TRAILING `// …` comment, or inside
    `/* … */`, survives the line-deleting stripper and is blanked by `codeOnly`
    (`blank=1, lines=2`). This repo's own style (`foo()   // #611: …`) produces exactly
    that. Measured across all 54 distinct needles today: zero disagreements — but a
    reader who trusts the old sentence would not know where to look.
    ⚠️ There is a THIRD state the heuristic cannot express: `TheMonitorSurgeryQuiets\
    TheEngineTests` reads RAW, unstripped text. If one of its pins ever resolves, this
    tool would strip where the guard does not, and a needle inside a comment would give
    a false RED. Nothing fires today; the two-state description was simply wrong.
 4. It resolves `let <var> = <fn>("<path>")` and `let <var> = <fn>(Self.<const>)`,
    taking the LAST binding before the assertion. A variable bound in a helper, or by
    a computed property, is unresolved.
 5. A MATCH is not a proof the guard is meaningful — only that its arithmetic holds.
    It says nothing about whether the pin is anchored on the right token (#367/#408).
    The #904 fixes are the worked example: a plain `grep` settles the COUNT, and only
    reading the declaration settles whether the count is the RIGHT one (there,
    `private func restartOrDegrade(after context: String)` cannot match the needle
    `restartOrDegrade(after:`, which is why five and not four is correct).
"""

import argparse
import glob
import importlib.util
import os
import pathlib
import re
import signal
import sys

# #905: a tool that traces back when piped into `head` looks broken and stops being
# trusted — `window-margins.py` learned this first and this file did not carry it over.
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):          # not POSIX, or not the main thread
    pass

# #905: guarded. Unguarded, a rename or a new import-time side effect in the sibling makes
# even `--help` and `--selftest` traceback, which is the worst way to learn about it.
_SIBLING = pathlib.Path(__file__).with_name("window-margins.py")
try:
    _spec = importlib.util.spec_from_file_location("_wm", _SIBLING)
    if _spec is None or _spec.loader is None:
        raise ImportError(f"cannot load {_SIBLING}")
    _wm = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_wm)
except Exception as exc:                       # pragma: no cover - environment failure
    sys.exit(f"count-pins: cannot import the shared stripper from {_SIBLING.name} ({exc}).\n"
             "  It holds the one `SourceText.codeOnly` port (#416). Fix that file, or say\n"
             "  plainly that this check did not run — never treat this as a clean result.")

# #905: `(?:code)?occurrences` — the bundle spells it BOTH ways and the second spelling is
# the LARGER half (73 vs 51 at writing). The first draft demanded the bare name, so the
# summary line read like a census while silently seeing the smaller half. `dead-needles.py`
# already parses `codeOccurrences`; there was no reason for this file to be narrower.
SHAPE_A = re.compile(
    r'XCTAssertEqual\(\s*(?:code)?[Oo]ccurrences\(of:\s*"((?:[^"\\]|\\.)*)",'
    r'\s*in:\s*(\w+)\s*\),\s*(\d+)')
SHAPE_B = re.compile(
    r'XCTAssertEqual\(\s*(\w+)\.components\(\s*separatedBy:\s*"((?:[^"\\]|\\.)*)"\s*\)'
    r'\.count\s*-\s*1,\s*(\d+)')
# #905: `(?:\w+:\s*)?` — a LABELLED argument (`try code(at: Self.view)`) is still a binding
# to a path. Without it ten of the twenty-five unresolved pins were reported as "not bound
# to a path" while being bound to one, one regex group away.
BIND_LITERAL = re.compile(
    r'let\s+(\w+)\s*=\s*(?:try\s+)?\w+\(\s*(?:\w+:\s*)?"([^"]+\.swift)"\s*\)')
BIND_CONST = re.compile(
    r'let\s+(\w+)\s*=\s*(?:try\s+)?\w+\(\s*(?:\w+:\s*)?Self\.(\w+)\s*\)')
FUNC = re.compile(r'^\s*(?:private\s+|internal\s+|public\s+)?func\s', re.M)
CONST = re.compile(r'static let (\w+)\s*=\s*"([^"]+\.swift)"')


# #905: the table was `n t " \\` and everything else fell through AS ITSELF — so a needle
# containing `\\u{2014}` kept that literal text while the guard searches for `—`, giving
# count 0 against a pinned N: a FALSE RED, the one failure mode this tool's docstring is
# written against (#665). Unknown escapes are now a hard exclusion, like interpolation.
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


def unescape(literal):
    """Swift source escapes → the bytes the needle matches, or None if unsupported."""
    out, i, n = [], 0, len(literal)
    while i < n:
        c = literal[i]
        if c == "\\" and i + 1 < n:
            nxt = literal[i + 1]
            if nxt not in _ESCAPES:
                return None
            out.append(_ESCAPES[nxt])
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
                # #905: bounded at the enclosing `func`. Unbounded, a `let code = …` in an
                # EARLIER test could supply the path for a same-named slice variable here —
                # a false verdict with no marker. `window-margins.py` hit this first (#899);
                # no cross-function case exists in the bundle today, which is exactly when
                # a latent trap is cheap to close.
                starts = [f.start() for f in FUNC.finditer(text) if f.start() < m.start()]
                floor = starts[-1] if starts else 0
                earlier = [p for pos, p in binds.get(var, [])
                           if floor <= pos < m.start()]
                if not earlier:
                    yield (test, line, needle, pinned, None, blanks,
                           f"`{var}` not bound to a path inside this test")
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
        resolved_needle = unescape(needle)
        if resolved_needle is None:
            unresolved.append((test, line, needle, "escape this tool does not model"))
            continue
        actual = pair[0 if blanks else 1].count(resolved_needle)
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
    seen = checked + len(unresolved)
    print(f"\ncount-pins: {checked} of {seen} pin(s) it can SEE were checked, "
          f"{len(findings)} RED, {len(unresolved)} unresolved.")
    print("  'unresolved' means THIS TOOL could not read the pin — never that the guard "
          "is wrong. Run with --all to list them.")
    print("  ⚠️ `seen` is not the bundle's universe of count pins: this reads two syntactic "
          "shapes (LIMIT 1). A clean run is never a census.")
    if not findings:
        print("  A clean run means the arithmetic holds, not that the pins are anchored "
              "well (LIMIT 5).")
    if seen == 0:
        print("  ⛔ NOTHING WAS SEEN. That is not a pass — the root holds no "
              "`Tests/CISmoke/*.swift`. Check --root.")
        return 2
    return 1 if findings else 0


def selftest():
    """#905: the count is COUNTED, and the RESOLVER is exercised.

    The first version printed a literal "8 checks" beside a list it did not read — the
    exact defect `window-margins.py` records one file over ("`len(cases)`, not a literal")
    and this repo's most-repeated one in miniature. It also tested only the regexes and
    `unescape`, never `pins()` — i.e. never the resolver, which is where every gap #905
    closed actually lived.
    """
    failures, total = [], []

    def check(name, ok):
        # #905b: `total` is APPENDED to on every call, so the printed denominator is
        # COUNTED. My own first draft of this rewrite printed a literal `{13}` while
        # fixing a literal `8` — the defect reproduces itself if the number is typed.
        total.append(name)
        if not ok:
            failures.append(name)

    m = SHAPE_A.search('XCTAssertEqual(occurrences(of: "abc", in: code), 3')
    check("shape A, plain", bool(m) and m.groups() == ("abc", "code", "3"))
    m = SHAPE_A.search('XCTAssertEqual(codeOccurrences(of: "abc", in: src), 9')
    check("shape A, codeOccurrences spelling", bool(m) and m.groups() == ("abc", "src", "9"))
    m = SHAPE_A.search('XCTAssertEqual(occurrences(of: "say \\"hi\\"", in: code), 1')
    check("shape A, escaped quote in the needle", bool(m) and m.group(1) == 'say \\"hi\\"')
    m = SHAPE_B.search('XCTAssertEqual(file.components(separatedBy: "x(").count - 1, 5')
    check("shape B", bool(m) and m.groups() == ("file", "x(", "5"))

    check("unescape, escaped quote", unescape('a\\"b') == 'a"b')
    check("unescape, newline", unescape("a\\nb") == "a\nb")
    check("unescape, unsupported escape is EXCLUDED", unescape("a\\u{2014}") is None)
    check("unescape, interpolation marker survives", unescape("a\\(b") is None)

    check("stripper keeps a // inside a string literal",
          _wm.code_only('let s = "http://x"') == 'let s = "http://x"')
    check("stripper drops a trailing comment",
          _wm.code_only("code() // tail").rstrip() == "code()")

    # THE RESOLVER, end to end, in a throwaway tree — this is the half the first
    # selftest did not touch.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "Tests/CISmoke"))
        os.makedirs(os.path.join(tmp, "Sources/Echoelmusic/Audio"))
        with open(os.path.join(tmp, "Sources/Echoelmusic/Audio/X.swift"), "w") as f:
            f.write('needleA()\nneedleA()\n// needleA()\nneedleB()   // trailing\n')
        with open(os.path.join(tmp, "Tests/CISmoke/T.swift"), "w") as f:
            f.write('func testOne() {\n'
                    '    let code = try source("Sources/Echoelmusic/Audio/X.swift")\n'
                    '    XCTAssertEqual(occurrences(of: "needleA()", in: code), 2, "")\n'
                    '}\n'
                    'func testTwo() {\n'
                    '    XCTAssertEqual(occurrences(of: "needleA()", in: code), 2, "")\n'
                    '}\n')
        resolved = [r for r in pins(tmp) if r[6] is None]
        check("resolver binds a path inside its own test", len(resolved) == 1)
        check("resolver refuses a binding from ANOTHER test",
              any(w and "inside this test" in w for _, _, _, _, _, _, w in pins(tmp)))
        # The comment copy must not be counted: the test file has no `SourceText.codeOnly`,
        # so the line-deleting stripper applies and `// needleA()` disappears.
        # `run` prints; the selftest owns its own output, so swallow it.
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            rc = run(tmp, False)
        check("a commented-out copy is not counted", rc == 0)

    print(f"selftest: {'OK' if not failures else 'FAILED'}, {len(failures)} failure(s) "
          f"of {len(total)} checks")
    for name in failures:
        print(f"  FAILED: {name}")
    return 0 if not failures else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="also list unresolved pins")
    ap.add_argument("--selftest", action="store_true")
    # #905: anchored to the script, not to `.`. With `default="."` a run from any other
    # directory printed "0 pin(s) checked, 0 RED" and EXITED 0 — a silent green, the #738
    # shape. The sibling script already defaulted this way.
    ap.add_argument("--root",
                    default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = ap.parse_args()
    sys.exit(selftest() if args.selftest else run(args.root, args.all))
