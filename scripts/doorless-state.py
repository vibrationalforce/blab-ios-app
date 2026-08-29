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

⛔ CLASSES AND ACTORS ONLY — AND THE FIRST VERSION'S REASON FOR THAT WAS OVERSTATED BY A
FACTOR OF FIVE (#735). It said the 91-vs-35 difference was "almost entirely" SwiftUI `View`
memberwise-init parameters. Measured, the 56 extras are: **11** `View` members (real false
positives — `MetalBioView.autoAttuned` is passed at every call site as `autoAttuned: autoMode`,
which is not an assignment), **22** `MetalBioView.BioUniforms` fields written by TUPLE
DESTRUCTURING (`(uniforms.cc0r, uniforms.cc0g, uniforms.cc0b) = (…)`, a third false-positive
mechanism the write matcher cannot see), **1** enum, and **~22 non-`View` structs that are
arguably real hits** — `CrashSafeStatePersistence.artNetEnabled`, `TapTempo.minBPM`,
`VoiceAnalyzer.floorDB`. So the narrow scope is a signal-to-noise CHOICE (per #665: a checker
with false alarms is a checker nobody reads), not the "it is all one false family" the first
version claimed. Widening it is a real option for a later slice, and it needs the tuple-write
matcher first.

KNOWN-POSITIVE CONTROL (this repo's own law: a detector that has never found its own known
positive is not a measurement). TWO properties are recorded IN THE SOURCE as doorless:
`ResourceGovernor.isAutomatic` (#727, with a guard) and `EchoelDDSP.useConvolutionReverb`
(#735/#546). If either stops appearing, this script is broken OR someone built the door —
either way it is not a silent pass: exit code 2.

⛔ `AudioEngine.inputMonitoringEnabled` WAS THE THIRD AND IS GONE (#866) — cause 1 of the
three the failure message lists, in its rarest form: not "someone built the door" but
"someone removed the property". It was deleted precisely BECAUSE this detector kept finding
it, which is the outcome a known-positive control is supposed to produce; a control that can
never retire has stopped describing the repo. Note the count above said "Two" while the tuple
already held three — the #735 addition never updated the sentence, so this correction is two
facts, not one.

THREE SECTIONS, BECAUSE THE FIRST VERSION DROPPED TWO KINDS OF HIT IN SILENCE (#735):
  · the main list — one declaration of the name, no writer;
  · **AMBIGUOUS** — no writer, but the name is declared on more than one type, so the untyped
    writer test cannot attribute it. The old `len(homes) == 1` filter discarded 39 names over
    100 declarations before the writer test ever ran, and `loopEnabled` (declared identically
    in `ArrangementPlayer` and `TimelineRegionPlayer`, read on both, written nowhere) was in
    there — squarely the target shape, silently gone;
  · **MASKED** — written somewhere, but never in the file that declares it. `written` is keyed
    on the identifier alone, so any same-named binding anywhere hides a real hit. The case
    this section was BUILT for was `AutoMixChain.preset`: a documented four-way tonal choice
    with `didSet { applyPreset() }` on a node `AudioEngine` constructs, invisible because
    `BioSignalDeconvolver` and `BioSpaceMap` each write `self.preset = preset`. ⛔ PAST TENSE
    SINCE #736 — that slice gave it a Picker, so `applyPersistedPreset()` now writes `preset`
    inside its own file and the name has left this section for good. Kept as the worked
    EXAMPLE, because it is the only positive this section has ever been proven to find; do
    not read it as a live finding, and do not go looking for it in the output. Typed
    attribution is NOT the fix — #665 measured that last-type-before-the-member mis-attributes
    nested types and lost every real positive. Listing suspects is honest; deciding them is a
    human's job. Capped at 12; `DOORLESS_ALL=1` shows all.

OTHER LIMITS, stated so nobody reads more into a green list than is there:
  · writes through a KeyPath, reflection, an unsafe pointer or TUPLE DESTRUCTURING are
    invisible (the last one is measured above, in `BioUniforms`);
  · a property written only from `Tests/` is reported as doorless — correct for "no product
    path can set it", and #728 is the cycle that paid for confusing the two, so the scope is
    printed with the result;
  · multi-declaration lines (`var a: Float = 0; var b: Float = 0`) parse as one property;
  · `#if os(...)` / `#else` duplicated stored properties land in AMBIGUOUS, not the main list —
    there is no preprocessor awareness here (`EchoelBioEngine.smoothBreathDepth` and its
    platform-stub twin are the measured example);
  · the `mentions` column is a GLOBAL word frequency, not mentions of that property. Sort by
    it; never conclude from it.
"""
import os
import re
import subprocess
import sys
import collections
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import doctor  # noqa: E402  — one definition of "code, not prose" (#416)

TYPE_OPENER = re.compile(r"\b(class|actor)\b")
# ⛔ THE MODIFIER LIST IS THE PART THAT WAS WRONG (#735). The first version accepted only
# `public `/`internal `, which rejected `nonisolated(unsafe) static var useConvolutionReverb`
# — the flag this repo documents in FIVE places as the canonical doorless one. The detector
# shipped a known-positive control that passed while its best-documented positive was
# invisible. Measured families the old list refused: 7 `other-prefix` (incl.
# `public internal(set)`), 6 `lazy`, 1 `nonisolated`.
MODIFIER = (r"(?:@\w+(?:\([^)]*\))?\s+|public\s+|internal\s+|nonisolated(?:\(unsafe\))?\s+"
            r"|static\s+|final\s+|lazy\s+|weak\s+|unowned\s+|class\s+"
            r"|public\s*\((?:set|get)\)\s+|(?:public|internal)\s+(?:internal|private)\(set\)\s+)*")
DECL = re.compile(
    r"^\s*" + MODIFIER + r"var ([a-z]\w*)"
    r"\s*(?::\s*([\w\.<>\[\], ?]+?))?\s*=\s*(\S.*?)\s*(?:\{\s*)?$")

ASSIGN = re.compile(r"(?<![=!<>])\b([a-z]\w*)\s*(?:\+|-|\*|/)?=(?!=)")
BINDING = re.compile(r"\$[A-Za-z_]\w*\.([a-z]\w*)\b")
TOGGLE = re.compile(r"\.([a-z]\w*)\s*\.toggle\(\)")
INOUT = re.compile(r"&[A-Za-z_]\w*\.([a-z]\w*)\b")
# ⛔ A COLLECTION IS WRITTEN WITHOUT EVER BEING ASSIGNED (#735). `fronts` was the one false
# positive in the first version's 35: `fronts[i].radius = …`, `fronts.append(…)`,
# `fronts.removeAll { … }`, `fronts.removeFirst(…)` — the `=` belongs to `radius`, and a
# mutating method has no `=` at all.
MUTATE = re.compile(r"\b([a-z]\w*)\s*(?:\[|\.(?:append|insert|remove\w*|popLast|sort\w*"
                    r"|reverse|swapAt|replaceSubrange|updateValue|formUnion|subtract\w*"
                    r"|toggle)\s*\()")
WORD = re.compile(r"\b([a-z]\w*)\b")

# The control is what makes this a measurement rather than a guess. `useConvolutionReverb` is
# added by #735 precisely BECAUSE the first version could not see it (see MODIFIER above).
CONTROL = ("isAutomatic", "useConvolutionReverb")


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
    declarations = 0
    for f, code in codes.items():
        for name, typ, default, raw in class_members(code):
            candidates.setdefault(name, []).append((f, typ, default))
            decl_lines.add(raw)
            declarations += 1

    written = collections.Counter()
    mentions = collections.Counter()
    write_files = {}
    for path, code in codes.items():
        for line in code.split("\n"):
            if line.strip() not in decl_lines:
                for m in ASSIGN.finditer(line):
                    written[m.group(1)] += 1
                    write_files.setdefault(m.group(1), set()).add(path)
            for pattern in (BINDING, TOGGLE, INOUT, MUTATE):
                for m in pattern.finditer(line):
                    written[m.group(1)] += 1
                    write_files.setdefault(m.group(1), set()).add(path)
            for m in WORD.finditer(line):
                mentions[m.group(1)] += 1

    hits = [(name, homes[0][0], homes[0][1], homes[0][2], mentions[name])
            for name, homes in candidates.items()
            if written[name] == 0 and len(homes) == 1]
    hits.sort(key=lambda h: (-h[4], h[0]))

    # ⛔ NOTHING IS SILENTLY DROPPED ANY MORE (#735). The first version required
    # `len(homes) == 1` and said nothing about the rest: 39 names over 100 declarations were
    # discarded before the writer test, and four of them had no writer at all — including
    # `loopEnabled`, declared identically in `ArrangementPlayer` and `TimelineRegionPlayer`,
    # which is squarely the shape this tool exists to find. They cannot be reported in the
    # main list because the untyped writer test cannot tell two same-named properties apart,
    # so they get their own section rather than a shrug.
    ambiguous = sorted((name, [h[0] for h in homes])
                       for name, homes in candidates.items()
                       if written[name] == 0 and len(homes) > 1)

    # ⛔ AND THE BLIND SPOT GETS A SECTION TOO, because naming it in prose was not enough.
    # `written` is keyed on the identifier alone, with no receiver type, so ANY same-named
    # binding anywhere masks a real hit. Measured worst case WHEN THIS SECTION WAS WRITTEN:
    # `AutoMixChain.preset` — a documented four-way tonal choice with `didSet { applyPreset() }`
    # on a node the audio engine constructs — WAS invisible because `BioSignalDeconvolver` and
    # `BioSpaceMap` each write `self.preset = preset`. #736 doored it, so it is no longer in
    # this list; the blind spot it demonstrated is unchanged. Typed attribution is NOT the fix:
    # #665 measured that
    # last-type-before-the-member mis-attributes nested types and lost every real positive.
    # Listing the suspects is honest and cheap; deciding them is a human's job.
    suspect = sorted(
        (name, homes[0][0]) for name, homes in candidates.items()
        if len(homes) == 1 and written[name] > 0
        and write_files.get(name) and homes[0][0] not in write_files[name])

    found = {h[0] for h in hits}
    missing = [c for c in CONTROL if c not in found]
    status = 2 if missing else 0

    print("doorless-state — settable class state with no writer under Sources/")
    print(f"  scope: {len(files)} Swift files under Sources/ ONLY "
          f"(a write from Tests/ does not count as a door)")
    print(f"  {declarations} declarations / {len(candidates)} distinct names examined "
          f"· {len(hits)} without a writer")
    # The verdict prints BEFORE the listing on purpose: the first version printed it last,
    # so `… | head` showed a clean banner and the BrokenPipeError handler returned 0 even
    # when the control had FAILED — the opposite of the "not a silent pass" promise (#735).
    if missing:
        print(f"\n  ⛔ KNOWN-POSITIVE CONTROL FAILED: {', '.join(missing)} not reported.")
        print("     THREE possible causes, in the order worth checking:")
        print("       1. someone built the door — then move the prose that calls it doorless")
        print("          (#456) and drop the name from CONTROL below;")
        print("       2. a second property of the same name appeared, so it fell into the")
        print("          AMBIGUOUS section instead of the main list;")
        print("       3. this detector broke — a modifier or write shape it cannot parse.")
    else:
        print(f"\n  ✅ known-positive control passed "
              f"({', '.join(CONTROL)} all reported).")
    print("     A hit is a QUESTION. A tuning constant with no writer is fine; a knob whose")
    print("     doc names a user who cannot turn it is the defect.")
    print("     `mentions` is a GLOBAL word frequency, not mentions of this property — a")
    print("     common name inflates it. Use it to sort, never to conclude.\n")

    for name, f, typ, default, seen in hits:
        shown = typ if typ else "(inferred)"
        print(f"  {name:26s} {shown[:22]:22s} = {default[:18]:18s} "
              f"mentions={seen:3d}  {f}")

    if ambiguous:
        print(f"\n  AMBIGUOUS — no writer, but the name is declared on more than one type,")
        print(f"  so the untyped writer test cannot attribute it ({len(ambiguous)}):")
        for name, homes in ambiguous:
            print(f"    {name:26s} {' · '.join(h.split('/')[-1] for h in homes)}")

    if suspect:
        # Capped by default: a suspect list in the high dozens would drown the ~35 hits, and
        # a tool whose output nobody reads is the failure mode the doctor skill already names.
        # What is withheld is stated, with the command that shows it — this repo's own slicing
        # rule. ⛔ THIS COMMENT SAID "96 suspects" AND "35 hits" AS FACTS; #736 doored one
        # suspect and the 96 became 95 in the same commit that wrote it. Both live numbers are
        # PRINTED four lines below and in the header — a count written down beside a count the
        # program computes is a date, not a fact (`.claude/rules/context.md` §2).
        show = suspect if os.environ.get("DOORLESS_ALL") else suspect[:12]
        print(f"\n  MASKED — written somewhere, but never in the file that declares it")
        print(f"  ({len(suspect)}). A same-named binding elsewhere may be hiding a real hit;")
        print(f"  most are ordinary cross-file setters. Decide them by hand; the section")
        print(f"  lists candidates, it does not accuse. (The case it was built for,")
        print(f"  `AutoMixChain.preset`, was doored by #736 and is no longer in this list.)")
        for name, f in show:
            print(f"    {name:26s} {f}")
        if len(show) < len(suspect):
            print(f"    … {len(suspect) - len(show)} more — "
                  f"DOORLESS_ALL=1 python3 scripts/doorless-state.py")

    return status


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        # `… | head` closes the pipe; a traceback there reads like a broken tool. The
        # control verdict prints BEFORE the listing, so it has already been seen — but the
        # exit code must not be laundered to 0 by a closed pipe (#735).
        sys.stderr.close()
        sys.exit(2)
