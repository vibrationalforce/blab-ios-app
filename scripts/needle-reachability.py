#!/usr/bin/env python3
"""Can this needle ever match? — the write-time check for a RUNTIME `.contains` needle.

WHY THIS EXISTS (#808). `TheBioPanelRowsSayWhoseBodyTests` asserted
`autoModeHint(...).contains("your body")` against a sentence that reads "toward your
measured **body state**". The needle never matched. It shipped in the same commit as the
sentence it was written for (`7e906cd`, #648), stayed red for two months, and was invisible
because the CI job log carries only `tail -200 test.log` (#807).

A SCAN needle (`code.contains(...)`) is self-verifying: whoever writes it greps for the
string. A RUNTIME needle (`SomeType.f(x).contains("lit")`) is not — this repo has no local
Swift toolchain, so nothing checks it until CI runs, and CI only shows a 200-line tail.
This script closes that gap without a compiler, by asking one question:

    does the literal occur in the source of the function the needle calls?

TWO BLIND SPOTS ARE HANDLED, AND THEY ARE NOT HYPOTHETICAL — the first version of this
script reported exactly two findings and BOTH were these:

  1. CONCATENATION SEAM. `autoModeCaption` spells "... when your " + "body is clearly
     settled", so "your body" exists only after the `+` runs. Adjacent literals are joined
     before searching.
  2. HELPER HOP. `breathVoiceHint` builds its sentence through `subject(synthetic:)`, whose
     real-body branch IS the literal. Called functions are resolved ONE level deep.

BOTH ERROR DIRECTIONS EXIST, and the first draft of this docstring claimed only one.
It said "every miss it cannot see is a FALSE GREEN, never a false alarm" — which sounds
like the safe direction and is simply wrong, as this file's own selftest then proved. The
mechanism is the opposite of what that sentence assumed:

  · INCOMPLETE resolution produces FALSE ALARMS. Two hops, interpolation (`"\\(x) body"`),
    a string assembled from an array — the literal is missing from what this script can
    reach, so it reports a needle that works perfectly. Case 5 of the selftest pins exactly
    this and is EXPECTED to report.
  · OVER-BROAD resolution produces FALSE GREENS. A literal that sits in a comment, in a
    branch the needle's state never takes, in a dead helper, or in a same-named function
    somewhere else (every candidate body is searched on a name collision).

So a green run is not a proof that a needle is right, and a finding is not a proof that it
is wrong. Read the finding, do not obey it. Hop depth is 1 on purpose: raising it trades
false alarms for false greens, and today it changes nothing — the live scan reports zero at
depth 1, so it reports zero at any depth.

USAGE
    python3 scripts/needle-reachability.py            # scan Tests/CISmoke against Sources
    python3 scripts/needle-reachability.py --selftest # drive the two blind spots + a real miss
Exit 1 when a needle cannot match (or a selftest case fails), else 0.
"""
import pathlib
import re
import sys

SOURCES = "Sources"
BUNDLE = "Tests/CISmoke"

# `XCTAssertTrue( Type.method(args) [newline] .contains("LITERAL") )`
# Only POSITIVE needles: an XCTAssertFalse that can never match is a weak assertion, not a
# red gate, and reporting it here would bury the class this script exists for.
NEEDLE = re.compile(
    r'XCTAssertTrue\(\s*([A-Z]\w*)\.(\w+)\((?:[^()]|\([^()]*\))*\)\s*'
    r'(?:\n\s*)?\.contains\("([^"\\]{4,})"\)')

# `"abc" + "def"` and its line-wrapped form — the concatenation seam.
SEAM = re.compile(r'"\s*\+\s*"')

CALL = re.compile(r'\b([a-z]\w*)\s*\(')


def _brace_body(text, start):
    """Text of the {...} block that opens at or after `start`, or None."""
    i = text.find("{", start)
    if i < 0:
        return None
    depth, j = 0, i
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j]
        j += 1
    return None


def index_functions(root):
    """name -> [body, ...] for every `func name(` under `root`."""
    out = {}
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r'\bfunc\s+(\w+)\s*[(<]', text):
            body = _brace_body(text, m.end())
            if body is not None:
                out.setdefault(m.group(1), []).append(body)
    return out


def reachable_text(name, funcs):
    """Every literal the function could produce: its own body, seams joined, one hop deep."""
    parts = list(funcs.get(name, []))
    for body in list(parts):
        for callee in set(CALL.findall(body)):
            if callee != name and callee in funcs:
                parts.extend(funcs[callee])
    return SEAM.sub("", "\n".join(parts))


def scan(bundle, funcs):
    findings = []
    for path in sorted(pathlib.Path(bundle).glob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in NEEDLE.finditer(text):
            _type, method, literal = m.groups()
            if method not in funcs:
                continue  # a test-local helper: out of scope, not a finding
            if literal not in reachable_text(method, funcs):
                findings.append(
                    (path.name, text[:m.start()].count("\n") + 1, method, literal))
    return findings


def selftest():
    """Drive the real miss and both blind spots. Fixtures are text, never files on disk."""
    def index(src):
        out = {}
        for m in re.finditer(r'\bfunc\s+(\w+)\s*[(<]', src):
            body = _brace_body(src, m.end())
            if body is not None:
                out.setdefault(m.group(1), []).append(body)
        return out

    cases = [
        ("#808 itself — a needle that can never match",
         'func hint() -> String { return "toward your measured body state" }',
         "hint", "your body", True),
        ("direct hit — the literal is right there",
         'func hint() -> String { return "toward your body" }',
         "hint", "your body", False),
        ("BLIND SPOT 1 — concatenation seam",
         'func cap() -> String { return "when your " + "body is settled" }',
         "cap", "your body", False),
        ("BLIND SPOT 2 — one helper hop",
         'func subject() -> String { return "your body" }\n'
         'func hint() -> String { return "follows " + subject() }',
         "hint", "your body", False),
        # EXPECTED TO REPORT. Two hops is beyond depth 1, so the script raises a needle
        # that works — a FALSE ALARM. It is pinned rather than fixed because the first
        # draft of this file asserted the opposite direction ("never a false alarm") and
        # this case is what disproved it. If depth is ever raised, this expectation flips
        # and the docstring paragraph above must move with it.
        ("two hops — a FALSE ALARM, pinned so the limit is not forgotten",
         'func leaf() -> String { return "your body" }\n'
         'func mid() -> String { return leaf() }\n'
         'func hint() -> String { return mid() }',
         "hint", "your body", True),
    ]
    bad = 0
    for label, src, method, literal, want_finding in cases:
        got = literal not in reachable_text(method, index(src))
        ok = got == want_finding
        bad += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'}  reports={got!s:<5} want={want_finding!s:<5}  {label}")
    print(f"selftest: {len(cases) - bad}/{len(cases)} cases correct")
    return 1 if bad else 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    funcs = index_functions(SOURCES)
    findings = scan(BUNDLE, funcs)
    if not findings:
        print(f"NEEDLE REACHABILITY: no unmatchable positive runtime needle "
              f"({len(funcs)} function names indexed under {SOURCES}/).")
        print("Not a proof that every needle is right — see the blind spots in this "
              "file's docstring. It proves only that none is provably unmatchable.")
        return 0
    print(f"NEEDLE REACHABILITY: {len(findings)} needle(s) cannot match.")
    for name, line, method, literal in findings:
        print(f"  {name}:{line}  {method}(...) can never produce {literal!r}")
    print("\nFix the NEEDLE unless the sentence is genuinely wrong — #808: the copy was "
          "pinned as intended by another claim in the same file.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
