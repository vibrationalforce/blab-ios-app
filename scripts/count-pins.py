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

On the repaired tree the same run is clean. #977 added a SECOND known positive for the
shape it introduced — the tree that carried #975 (test file at `1e81876`, source at
`ad409d2`) reports exactly `pinned 5, actual 6` and exits 1:

    git show 1e81876:Tests/CISmoke/MonitoringCannotStrandTheEngineStoppedTests.swift > …
    git show ad409d2:Sources/Echoelmusic/Audio/AudioEngine.swift                     > …

It also found TWO further reds on its first
pass over the live tree — `TheFailedRestartHandsOverToDegradedTests`, in OPPOSITE
directions (a fifth helper call nobody counted, a pause site #823 had turned into a
stop) — both hand-verified with a plain `grep` before being believed.

HONEST LIMITS — read them before obeying a finding (#665: a checker with false alarms
is a checker nobody reads, so its blind spots are part of its output):

 1. It reads THREE syntactic shapes and nothing else:
        XCTAssertEqual([code]occurrences(of: "<literal>", in: <var>), <N>
        XCTAssertEqual(<var>.components(separatedBy: "<literal>").count - 1, <N>
        XCTAssertEqual(<var>.filter { $0.contains("<literal>") }.count, <N>
    ⛔ #977: the third was invisible until it had cost the SAME pin three reds (#631,
    #958b, #975 — `restoreEngineIfStranded(` in `MonitoringCannotStrandTheEngineStopped\
    Tests`, red each time the source grew a call site). On #975 this tool printed
    "0 RED" while that guard was failing, which is the one output a checker must never
    produce. It differed in three ways at once, not one: syntax, COUNTING MODE (it counts
    LINES holding the needle, not occurrences of it — see `mode` in `pins`), and BINDING
    (an array of lines from a zero-argument helper). Reach went 139 → 157 checked of
    178 → 221 seen, with no new red.
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
 3. The stripper is chosen per TEST FILE by a heuristic, EXCEPT for a pin bound through
    a zero-argument helper — there the helper's own body decides (#977), because this
    bundle mixes both kinds inside one file. The heuristic is `SourceText.codeOnly` if the
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
    a false RED. The two-state description was simply wrong.
    ⛔ #1050 — IT FIRED, and the direction was the opposite of the one predicted here.
    `AStillIsOneFrameNotASecondPathTests` was a SECOND raw reader (its `source(_:)` returns the
    file unstripped), it pinned `.sheet(` at 14, this tool stripped and measured 9, and the
    paragraph above had already taught the next reader to call that a false alarm — which the
    session log and a deep-audit note both then did. It was not: the guard's 14 was 9 real call
    sites plus 5 mentions inside comments, so it moved on PROSE edits and stood still when a
    `.fullScreenCover` was added. The pin is retracted; the claim's proper home
    (`ResetSoundClearsWhatTheLaunchLineReportsTests`) strips before counting and was green
    throughout. LESSON for this tool's next reader: a raw-reading guard is not a reason to
    distrust a RED here — it is the first thing to check ABOUT the guard, because "counts its own
    documentation" is a defect a stripping tool sees and an unstripped guard cannot.
    ⛔ #977 MEASURED a live wrongness this limit only described in the abstract:
    `ChromeDynamicTypeTests.swift` mentions `SourceText.codeOnly` ONCE, in PROSE, and
    every helper in it strips by deleting `//` lines — so the file-wide guess is already
    the wrong one there. Its pins happen to be unresolved for other reasons, so nothing
    is wrong TODAY; the fix for any pin the helper rule reaches is above, and a
    `codeLines(_:)`-bound pin would still take the guess.
 4. It resolves `let <var> = <fn>("<path>")`, `let <var> = <fn>(Self.<const>)` and
    (#977) `let <var> = try <helper>()` where `<helper>` is a zero-argument
    `throws -> [String]` whose body names exactly ONE `appendingPathComponent("…swift")`,
    taking the LAST binding before the assertion. Still unresolved, by name so the next
    reader does not have to rediscover them: a WINDOW (`span(lines, …)`,
    `Array(lines[s...e])`, `monitorOnSpan(…)`) — a slice is not the file and counting the
    whole file against it would be a false verdict, not a gap; a bare-identifier constant
    (`codeLines(row)` where `private let row = "…swift"`, 4 pins); and a helper returning
    `String` rather than `[String]`. 64 of 221 pins stay unresolved for these reasons.
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
# #977: the THIRD shape, and it is the one that bit three times (#631, #958b, #975 — the
# same pin in `MonitoringCannotStrandTheEngineStoppedTests`, red again each time the source
# grew a call site). It was invisible here for three separate reasons at once, which is why
# adding it is a slice and not a one-line regex:
#   · a different SYNTAX          `<var>.filter { $0.contains("<lit>") }.count`
#   · a different COUNTING MODE   it counts LINES that contain the needle, not occurrences
#                                 of it — two hits on one line are ONE here and TWO for
#                                 shapes A/B. Counting it the old way is a false RED.
#   · a different BINDING FORM    `<var>` is an ARRAY of lines, usually from a zero-argument
#                                 helper (`try engineLines()`), not from `<fn>("<path>")`.
# 43 equality pins across 16 files were unreadable here; 18 of them resolve today.
# ⛔ DELIBERATELY NOT MATCHED, each for a reason, not an oversight:
#   · `XCTAssertGreaterThanOrEqual(… .count, N)` (1 site) is NOT a pin — drift upward is
#     legal there, so treating it as one manufactures a false RED, the failure mode this
#     file's docstring is written against (#665).
#   · a COMPOUND predicate (`$0.contains("a") || $0.contains("b")`, 1 site) counts lines
#     matching EITHER needle; reading one needle would under-count.
#   · a non-literal predicate (`$0.contains(guardLine)`, `$0.trimming… == declaration`) is
#     a variable — the same exclusion as an interpolated needle (LIMIT 2).
# The regex demands the closing `") }.count,` immediately, so a compound or variable
# predicate cannot match its prefix and be silently half-read.
SHAPE_C = re.compile(
    r'XCTAssertEqual\(\s*(\w+)\.filter \{ \$0\.contains\("((?:[^"\\]|\\.)*)"\) \}'
    r'\.count,\s*\n?\s*(\d+)')
# #977: `let <var> = try <helper>()`. The bundle's line-array helpers take no argument and
# hide the path inside their own body — `engineLines()`, `studioLines()`, `viewLines()`.
# Without this the #975 pin stays unresolved and the known positive in the docstring cannot
# fire. The helper's body also decides its own STRIPPER, which the per-file heuristic in
# LIMIT 3 gets wrong for exactly this bundle: the `codeLines(_:)` helpers strip by DELETING
# `//` lines while `engineLines()` uses `SourceText.codeOnly`, and a file can hold both.
BIND_HELPER = re.compile(r'let\s+(\w+)\s*=\s*try\s+(\w+)\(\s*\)')
HELPER_DEF = re.compile(
    r'(?:private\s+)?func\s+(\w+)\(\s*\)\s*throws\s*->\s*\[String\]\s*\{')
APPEND = re.compile(r'appendingPathComponent\(\s*\n?\s*"([^"]+\.swift)"\s*\)')
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


def line_helpers(text):
    """#977: zero-argument `-> [String]` helpers → (source path, does it use codeOnly).

    Brace-matched from the opening `{`, not regex-delimited: these bodies contain `{ }`
    (a `guard … else { throw XCTSkip }`), so a lazy `.*?\\}` would stop at the first one
    and miss the `appendingPathComponent` below it. A helper with no path literal, or with
    more than one, is simply absent from the map — unresolved, never guessed.
    """
    out = {}
    for m in HELPER_DEF.finditer(text):
        depth, i, start = 1, m.end(), m.end()
        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        body = text[start:i]
        paths = APPEND.findall(body)
        if len(paths) == 1:
            out[m.group(1)] = (paths[0], "SourceText.codeOnly" in body)
    return out


def pins(root):
    """Yield (test, line, needle, pinned, source_path, blank_stripper, why, mode).

    `mode` is "occurrences" for shapes A/B and "lines" for shape C — see the SHAPE_C
    comment: counting a line-filter pin by occurrences is a false RED, not a near miss.
    """
    for test in sorted(glob.glob(os.path.join(root, "Tests/CISmoke/*.swift"))):
        text = open(test, encoding="utf-8").read()
        consts = dict(CONST.findall(text))
        helpers = line_helpers(text)
        binds = {}
        for m in BIND_LITERAL.finditer(text):
            binds.setdefault(m.group(1), []).append((m.start(), m.group(2), None))
        for m in BIND_CONST.finditer(text):
            if m.group(2) in consts:
                binds.setdefault(m.group(1), []).append((m.start(), consts[m.group(2)], None))
        for m in BIND_HELPER.finditer(text):
            hit = helpers.get(m.group(2))
            if hit is not None:
                binds.setdefault(m.group(1), []).append((m.start(), hit[0], hit[1]))
        blanks = "SourceText.codeOnly" in text
        for rx, shape in ((SHAPE_A, "A"), (SHAPE_B, "B"), (SHAPE_C, "C")):
            for m in rx.finditer(text):
                if shape == "A":
                    needle, var, pinned = m.group(1), m.group(2), int(m.group(3))
                else:
                    var, needle, pinned = m.group(1), m.group(2), int(m.group(3))
                mode = "lines" if shape == "C" else "occurrences"
                line = text[:m.start()].count("\n") + 1
                if "\\(" in needle:                       # LIMIT 2
                    yield (test, line, needle, pinned, None, blanks,
                           "interpolated needle", mode)
                    continue
                # #905: bounded at the enclosing `func`. Unbounded, a `let code = …` in an
                # EARLIER test could supply the path for a same-named slice variable here —
                # a false verdict with no marker. `window-margins.py` hit this first (#899);
                # no cross-function case exists in the bundle today, which is exactly when
                # a latent trap is cheap to close.
                starts = [f.start() for f in FUNC.finditer(text) if f.start() < m.start()]
                floor = starts[-1] if starts else 0
                earlier = [(p, s) for pos, p, s in binds.get(var, [])
                           if floor <= pos < m.start()]
                if not earlier:
                    yield (test, line, needle, pinned, None, blanks,
                           f"`{var}` not bound to a path inside this test", mode)
                    continue
                path, own_strip = earlier[-1]
                # #977: a HELPER states its own stripper; only fall back to the per-file
                # heuristic (LIMIT 3) when the binding does not know. This bundle mixes both
                # inside one file, so the file-wide guess is wrong there by construction.
                yield (test, line, needle, pinned, resolve_path(path),
                       blanks if own_strip is None else own_strip, None, mode)


def run(root, show_all):
    cache = {}
    findings, unresolved, checked = [], [], 0
    for test, line, needle, pinned, path, blanks, why, mode in pins(root):
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
        body = pair[0 if blanks else 1]
        # #977: the guard's OWN arithmetic, not a uniform one. Shape C filters an
        # array of lines, so two hits on one line are ONE there and TWO here.
        if mode == "lines":
            actual = sum(1 for l in body.split("\n") if resolved_needle in l)
        else:
            actual = body.count(resolved_needle)
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
    print("  ⚠️ `seen` is not the bundle's universe of count pins: this reads three syntactic "
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
              any(w and "inside this test" in w for *_, w, _ in pins(tmp)))
        # The comment copy must not be counted: the test file has no `SourceText.codeOnly`,
        # so the line-deleting stripper applies and `// needleA()` disappears.
        # `run` prints; the selftest owns its own output, so swallow it.
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            rc = run(tmp, False)
        check("a commented-out copy is not counted", rc == 0)

    # ---- #977: the THIRD shape, its counting mode, and its binding form ----------------
    m = SHAPE_C.search(
        'XCTAssertEqual(lines.filter { $0.contains("abc(") }.count, 4, """')
    check("shape C, plain", bool(m) and m.groups() == ("lines", "abc(", "4"))
    m = SHAPE_C.search(
        'XCTAssertEqual(lines.filter { $0.contains("abc(") }.count,\n            4, """')
    check("shape C, count on the next line", bool(m) and m.group(3) == "4")
    check("shape C REFUSES a compound predicate",
          SHAPE_C.search('XCTAssertEqual(l.filter { $0.contains("a") || $0.contains("b") }'
                         '.count, 3') is None)
    check("shape C REFUSES a >= assertion",
          SHAPE_C.search('XCTAssertGreaterThanOrEqual(l.filter { $0.contains("a") }'
                         '.count, 1') is None)
    check("shape C REFUSES a variable predicate",
          SHAPE_C.search('XCTAssertEqual(l.filter { $0.contains(needle) }.count, 1') is None)

    body = ('    private func engineLines() throws -> [String] {\n'
            '        let here = URL(fileURLWithPath: #filePath)\n'
            '        let path = here.appendingPathComponent(\n'
            '            "Sources/Echoelmusic/Audio/X.swift")\n'
            '        guard FileManager.default.fileExists(atPath: path.path) else {\n'
            '            throw XCTSkip("no tree")\n'
            '        }\n'
            '        return SourceText.codeOnly(try String(contentsOf: path)).split(\n'
            '            separator: "\\n").map(String.init)\n'
            '    }\n')
    h = line_helpers(body)
    # The brace-matching half: a lazy `.*?}` would stop at the `guard … else { … }` and,
    # depending on where the path sits, either miss it or miss the stripper below it.
    check("helper resolves its path past an inner brace block",
          h.get("engineLines", (None, None))[0] == "Sources/Echoelmusic/Audio/X.swift")
    check("helper reports its OWN stripper", h.get("engineLines", (None, None))[1] is True)
    check("a helper with no path literal is absent, not guessed",
          line_helpers('    private func x() throws -> [String] {\n        return []\n    }\n')
          == {})

    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "Tests/CISmoke"))
        os.makedirs(os.path.join(tmp, "Sources/Echoelmusic/Audio"))
        # TWO hits on ONE line: a line-filter pin counts 1, an occurrence pin counts 2.
        # This is the whole point of `mode` — the old arithmetic would call this pin RED.
        with open(os.path.join(tmp, "Sources/Echoelmusic/Audio/X.swift"), "w") as f:
            f.write('hit() ; hit()\nhit()\n')
        with open(os.path.join(tmp, "Tests/CISmoke/T.swift"), "w") as f:
            f.write('    private func engineLines() throws -> [String] {\n'
                    '        let path = root.appendingPathComponent(\n'
                    '            "Sources/Echoelmusic/Audio/X.swift")\n'
                    '        return SourceText.codeOnly(try String(contentsOf: path))\n'
                    '            .split(separator: "\\n").map(String.init)\n'
                    '    }\n'
                    'func testLines() {\n'
                    '    let lines = try engineLines()\n'
                    '    XCTAssertEqual(lines.filter { $0.contains("hit()") }.count, 2, "")\n'
                    '}\n')
        got = [r for r in pins(tmp) if r[6] is None]
        check("a zero-argument helper binds the pin to its file", len(got) == 1)
        check("a shape C pin is counted in line mode",
              bool(got) and got[0][7] == "lines")
        with contextlib.redirect_stdout(io.StringIO()):
            rc = run(tmp, False)
        # 3 occurrences, 2 lines. Green ONLY if the line mode is really used.
        check("two hits on one line are ONE line, not two occurrences", rc == 0)

    with tempfile.TemporaryDirectory() as tmp:
        # #977 — THE STRIPPER OVERRIDE, and it needed its own tree: the fixture above says
        # nothing about it, because there the helper's stripper and the file heuristic agree.
        # Here they DIVERGE, which is not hypothetical — `ChromeDynamicTypeTests.swift`
        # mentions `SourceText.codeOnly` only in PROSE while every helper in it strips by
        # deleting `//` lines, so the file-wide guess is already wrong there today.
        os.makedirs(os.path.join(tmp, "Tests/CISmoke"))
        os.makedirs(os.path.join(tmp, "Sources/Echoelmusic/Audio"))
        with open(os.path.join(tmp, "Sources/Echoelmusic/Audio/Y.swift"), "w") as f:
            # A TRAILING comment: `codeOnly` blanks it, the line-deleting stripper keeps it.
            f.write("keep()\nother()   // keep()\n")
        with open(os.path.join(tmp, "Tests/CISmoke/T.swift"), "w") as f:
            f.write('// This file only MENTIONS SourceText.codeOnly in prose.\n'
                    '    private func plainLines() throws -> [String] {\n'
                    '        let path = root.appendingPathComponent(\n'
                    '            "Sources/Echoelmusic/Audio/Y.swift")\n'
                    '        return try String(contentsOf: path)\n'
                    '            .split(separator: "\\n").map(String.init)\n'
                    '            .filter { !$0.hasPrefix("//") }\n'
                    '    }\n'
                    'func testDiverges() {\n'
                    '    let lines = try plainLines()\n'
                    '    XCTAssertEqual(lines.filter { $0.contains("keep()") }.count, 2, "")\n'
                    '}\n')
        got = [r for r in pins(tmp) if r[6] is None]
        check("the file heuristic and the helper disagree in this fixture",
              "SourceText.codeOnly" in open(os.path.join(tmp, "Tests/CISmoke/T.swift")).read()
              and bool(got) and got[0][5] is False)
        with contextlib.redirect_stdout(io.StringIO()):
            rc = run(tmp, False)
        # 2 lines hold `keep()` unstripped; `codeOnly` would blank the trailing one → 1.
        check("the HELPER's stripper wins over the file-wide guess", rc == 0)

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
