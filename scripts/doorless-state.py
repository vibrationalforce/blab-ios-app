#!/usr/bin/env python3
"""Settable state on a CLASS that nothing in `Sources/` ever writes.

WHY THIS EXISTS. Four cycles in a row (#724 `breathPlayEnabled`, #727 `isAutomatic`,
#730 `ArtNetSender.resolution`, and the recorded `inputMonitoringEnabled`) found the same
shape by hand: a non-private `var` with a default, read on a live path, and no writer
anywhere — a setting with no setter. Each hand survey cost a cycle and each one was found
by accident. This turns the survey into one command.

    python3 scripts/doorless-state.py

WHAT IT IS NOT. **A hit is a QUESTION, not a defect.** Plenty of no-writer properties are
correct: a DSP tuning constant a developer edits in place (`EchoelDDSP.pitchDriftCents`), a
type with no production path at all (`EchoelCellular`, `EchoelModalBank` — both test-only,
recorded in CLAUDE.md), a debug knob. What the list is good for is the OTHER kind: a knob a
user is described as being able to turn, that no shipped path can turn. Read the doc comment
next to each hit; if it names a person or a use case, that is the defect.

⛔ CLASSES AND ACTORS ONLY, AND THAT LIMIT IS MEASURED, NOT CAUTION. Run over `struct`s as
well and the top of the list fills with SwiftUI `View` members — `MetalBioView.autoAttuned`,
`entrainmentPulseHz`, `EchoelValueField.boxWidth`. Those are memberwise-INIT PARAMETERS,
written at every call site as `autoAttuned: autoMode`, which is not an assignment and never
will be. 91 hits over all type kinds, 35 over classes, and the difference was almost entirely
that one false-positive family. Per #665's rule — a checker with false alarms is a checker
nobody reads — the narrow version is the shipped one.

KNOWN-POSITIVE CONTROL (this repo's own law: a detector that has never found its own known
positive is not a measurement). Two properties are recorded IN THE SOURCE as doorless:
`ResourceGovernor.isAutomatic` (#727, with a guard) and `AudioEngine.inputMonitoringEnabled`
(recorded at `VoiceCaptureController.swift`). If either stops appearing, this script is
broken OR someone built the door — either way it is not a silent pass: exit code 2.

OTHER LIMITS, stated so nobody reads more into a green list than is there:
  · writes through a KeyPath, reflection or an unsafe pointer are invisible;
  · a property written only from `Tests/` is reported as doorless — correct for "no product
    path can set it", and #728 is the cycle that paid for confusing the two, so the scope is
    printed with the result;
  · multi-declaration lines (`var a: Float = 0; var b: Float = 0`) parse as one property.
"""
import re
import subprocess
import sys
import collections
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import doctor  # noqa: E402  — one definition of "code, not prose" (#416)

TYPE_OPENER = re.compile(r"\b(class|actor)\b")
DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public |internal |)var ([a-z]\w*)"
    r"\s*(?::\s*([\w\.<>\[\], ?]+?))?\s*=\s*(\S.*?)\s*(?:\{\s*)?$")

ASSIGN = re.compile(r"(?<![=!<>])\b([a-z]\w*)\s*=(?!=)")
BINDING = re.compile(r"\$[A-Za-z_]\w*\.([a-z]\w*)\b")
TOGGLE = re.compile(r"\.([a-z]\w*)\s*\.toggle\(\)")
INOUT = re.compile(r"&[A-Za-z_]\w*\.([a-z]\w*)\b")
WORD = re.compile(r"\b([a-z]\w*)\b")

CONTROL = ("isAutomatic", "inputMonitoringEnabled")


def class_members(text):
    """Stored `var`s whose innermost enclosing brace was opened by a class or actor."""
    stack = []
    out = []
    for line in text.split("\n"):
        if stack and stack[-1]:
            m = DECL.match(line)
            if (m and "private" not in line and "fileprivate" not in line
                    and not m.group(1).startswith("_")):
                out.append((m.group(1), (m.group(2) or "").strip(),
                            m.group(3), line.strip()))
        opener = bool(TYPE_OPENER.search(line)) and "func " not in line
        for _ in range(line.count("{")):
            stack.append(opener)
        for _ in range(line.count("}")):
            if stack:
                stack.pop()
    return out


def main():
    files = [f for f in subprocess.run(
        ["git", "ls-files", "Sources/*.swift"], capture_output=True, text=True,
        check=False).stdout.split() if f.endswith(".swift")]
    if not files:
        print("doorless-state: INSTRUMENT UNAVAILABLE — git listed no Swift sources")
        return 2
    codes = {f: doctor._code_only(pathlib.Path(f).read_text(encoding="utf-8"))
             for f in files}

    candidates = {}
    decl_lines = set()
    for f, code in codes.items():
        for name, typ, default, raw in class_members(code):
            candidates.setdefault(name, []).append((f, typ, default))
            decl_lines.add(raw)

    written = collections.Counter()
    mentions = collections.Counter()
    for code in codes.values():
        for line in code.split("\n"):
            if line.strip() not in decl_lines:
                for m in ASSIGN.finditer(line):
                    written[m.group(1)] += 1
            for pattern in (BINDING, TOGGLE, INOUT):
                for m in pattern.finditer(line):
                    written[m.group(1)] += 1
            for m in WORD.finditer(line):
                mentions[m.group(1)] += 1

    hits = [(name, homes[0][0], homes[0][1], homes[0][2], mentions[name])
            for name, homes in candidates.items()
            if written[name] == 0 and len(homes) == 1]
    hits.sort(key=lambda h: (-h[4], h[0]))

    print("doorless-state — settable class state with no writer under Sources/")
    print(f"  scope: {len(files)} Swift files under Sources/ ONLY "
          f"(a write from Tests/ does not count as a door)")
    print(f"  {len(candidates)} class properties examined · {len(hits)} without a writer\n")
    for name, f, typ, default, seen in hits:
        shown = f"{typ}" if typ else "(inferred)"
        print(f"  {name:26s} {shown[:22]:22s} = {default[:18]:18s} "
              f"mentions={seen:3d}  {f}")

    found = {h[0] for h in hits}
    missing = [c for c in CONTROL if c not in found]
    print()
    if missing:
        print(f"  ⛔ KNOWN-POSITIVE CONTROL FAILED: {', '.join(missing)} not reported.")
        print("     Either this detector broke, or a door was built for it. Both need a")
        print("     human: if a door exists, move the prose that calls it doorless (#456)")
        print("     and drop the name from CONTROL here.")
        return 2
    print(f"  ✅ known-positive control passed ({', '.join(CONTROL)} both reported).")
    print("     Reminder: a hit is a QUESTION. A tuning constant with no writer is fine;")
    print("     a knob whose doc names a user who cannot turn it is the defect.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        # `… | head` closes the pipe; a traceback there reads like a broken tool.
        sys.stderr.close()
        sys.exit(0)
