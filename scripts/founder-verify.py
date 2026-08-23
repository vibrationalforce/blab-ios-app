#!/usr/bin/env python3
"""Collect every NEEDS-FOUNDER-VERIFY marker into one device-session checklist.

WHY THIS EXISTS. The two ship-gate checks that are still open — 1 Klang and
5 Stabilität — are BOTH sensory (see CLAUDE.md's SHIP GATE paragraph). No cycle can
close them by building; they need a device session. And the asks for that session were
scattered through the tree as free-text comments. Nothing collected them, nothing
ordered them, and the founder had no way to see the queue. The scarcest resource in
this project is device time, and it had an invisible backlog.

⚠️ TWO NUMBERS, BOTH CORRECT — name the OPERATION and the SCOPE or they read as a
contradiction. **108** counts every OCCURRENCE of the marker over four roots (Sources,
Tests, CLAUDE.md, scratchpads). **50** counts ASK LINES over the three roots this tool
walks, after the reference lines below are set aside. A line can carry the marker twice;
scratchpads are session prose, not asks. Neither number is wrong; the first version of
this docstring printed 108 next to a header that said 53 and explained neither.

⛔ AND THE INSTRUMENT COUNTED ITS OWN DESCRIPTION (#753). Registering this tool in
CLAUDE.md added a line reading "es sammelt jeden `NEEDS-FOUNDER-VERIFY`-Vermerk" — and
the next run reported 54 asks instead of 53. The 54th was the sentence describing the
tool. Four such lines exist: two in CLAUDE.md, two in guard headers that talk ABOUT the
backlog. They are not asks; nobody can perform them. See is_reference().

WHAT IT IS NOT. It does not decide anything and it cannot tell an ANSWERED ask from an
open one — see LIMITS. It turns scattered prose into a list you can walk with a phone
in your hand.

    python3 scripts/founder-verify.py             # counts per area + one line each
    python3 scripts/founder-verify.py --all       # the full instruction for every ask
    python3 scripts/founder-verify.py --area bio  # one area, full instructions

Read-only, no dependencies, no network, no build — the doctor.py house rules.
"""
import os
import re
import sys

MARKER = "NEEDS-FOUNDER-VERIFY"
ROOTS = ["Sources", "Tests", "CLAUDE.md"]

# Area comes from the FILE NAME, never from the words in the comment: a keyword
# classifier on prose this dense mislabels constantly (half these comments mention
# "bio" while being about layout).
#
# ⛔ THE FIRST VERSION MATCHED ONLY DIRECTORY SEGMENTS (`/Bio/`, `/Audio/`, …) and put
# 32 of 53 asks in "other". Every guard in `Tests/CISmoke` lives at one flat path, so a
# directory rule cannot see what it is about — and the CISmoke half is where the richest
# device instructions are. The basename carries the topic; that is what is matched now.
# A bucket that swallows 60 % of the queue is not a classification, it is a list.
# ⚠️ ORDER IS THE TIE-BREAK, and the selftest is why it is written down. `MetalBioView`
# carries BOTH "Metal" and "Bio"; with `bio` first it landed in the wrong bucket, and the
# selftest caught that before this file was ever committed. The rule: the MORE SPECIFIC
# needle wins, so `visual` is matched first. "Field" is deliberately NOT a visual needle
# even though the Field panel is the visual one — `BodyTempoField` would have been swept
# in, and a tempo control is not a picture.
AREAS = [
    ("visual", ("/Video/", "/Views/", "Visual", "Metal", "Look", "Recording", "Clip",
                "Donut")),
    ("bio", ("/Bio/", "Bio", "Pulse", "Coherence", "Breath", "Heart", "Camera", "RPPG",
             "Confidence", "Lock")),
    ("audio", ("/Audio/", "/DSP/", "/Tools/", "FX", "Grain", "Chain", "Tempo", "Genre",
               "Sound", "Patch", "Voice", "Autotune", "Reverb", "Mix", "Take", "Loop",
               "Monitor", "Tune", "Detune", "Instrument")),
    ("sync", ("/Sync/", "/Stream/", "OSC", "MIDI", "Peer", "Wire", "ArtNet", "Lux")),
    ("ui", ("/Studio/", "Text", "Label", "Chip", "Scroll", "Tap", "Sheet", "Panel",
            "Row", "Size", "Undo", "Menu", "Door", "Header", "Control", "Button",
            "Project", "Preset")),
]


# ⛔ THE MARKER IS ALSO AN ORDINARY NOUN, and that is how a tool ends up counting its
# own description (#753). "es sammelt jeden `NEEDS-FOUNDER-VERIFY`-Vermerk" is prose
# ABOUT the backlog; "NEEDS-FOUNDER-VERIFY: tap the thing" is a job for a human with a
# phone. Both contain the marker.
#
# ⛔ THE OBVIOUS RULE WAS MEASURED AND KILLED FIRST. Punctuation after the marker does
# NOT separate them: across the 54 hits the marker is followed by 30 distinct 3-character
# tails, and 15 of the non-colon ones are REAL asks ("NEEDS-FOUNDER-VERIFY on device…",
# "NEEDS-FOUNDER-VERIFY, and the honest failure mode…"). A colon rule would have hidden
# fifteen jobs from the founder to remove four sentences.
#
# What DOES separate them is the word BEFORE. An ask is never preceded by a determiner;
# a noun-use always is ("the backlog", "jeden Vermerk", "aus dem der …-Rückstand").
# Markup between the two is stripped, so `**the** `MARKER`` still reads as a noun-use.
#
# ⭐ THE DIRECTION IS DELIBERATE AND IS THE SAFETY PROPERTY. This rule can only move a
# line OUT of the ask list, and only when a determiner sits in front of it. A reference
# phrased WITHOUT one stays counted as an ask — over-counting, which costs the founder a
# glance. Hiding a real ask would cost a device session, so the rule fails toward noise.
DETERMINERS = {"the", "a", "this", "der", "dem", "den", "die", "das",
               "jeden", "jede", "jedes", "einen", "eine", "einem"}


def is_reference(line: str, at: int):
    """The determiner in front of the marker, or None when this line is an ask.

    `at` is the index the marker starts at. Markup characters immediately before it
    (backtick, asterisk, underscore) are not words and are stripped.
    """
    words = line[:at].replace("`", " ").replace("*", " ").replace("_", " ").split()
    if not words:
        return None
    last = words[-1].lower()
    return last if last in DETERMINERS else None


def area_of(path: str) -> str:
    base = os.path.basename(path)
    for name, needles in AREAS:
        if any(n in path if n.startswith("/") else n in base for n in needles):
            return name
    return "other"


def comment_body(lines, i):
    """The marker line plus the comment lines that continue it (max 4).

    Stops at the first line that is not a comment, so an ask never swallows code.
    """
    out = [lines[i].strip()]
    for j in range(i + 1, min(i + 5, len(lines))):
        s = lines[j].strip()
        if not (s.startswith("//") or s.startswith("///") or s.startswith("*")
                or s.startswith("· ") or s.startswith("- ")):
            break
        if MARKER in s:          # a second ask starts here — it gets its own entry
            break
        out.append(s)
    text = " ".join(out)
    text = re.sub(r"^\s*(///|//|\*)\s*", "", text)
    text = re.sub(r"\s*(///|//|\*)\s*", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def collect():
    found, refs = [], []
    for root in ROOTS:
        paths = [root] if os.path.isfile(root) else [
            os.path.join(d, f)
            for d, _, fs in os.walk(root)
            for f in fs if f.endswith((".swift", ".md"))
        ]
        for p in sorted(paths):
            try:
                lines = open(p, encoding="utf-8").read().split("\n")
            except OSError:
                continue
            for i, line in enumerate(lines):
                if MARKER not in line:
                    continue
                det = is_reference(line, line.index(MARKER))
                if det:
                    refs.append((p, i + 1, det))
                else:
                    found.append((area_of(p), p, i + 1, comment_body(lines, i)))
    return found, refs


def selftest() -> int:
    """Drive the two parsing rules over fixtures whose answers are known.

    ⛔ WRITTEN BECAUSE #738/#739 PAID FOR THE LESSON TWICE: a control its own
    known-positive passes is not a control. Both checks below are driven with a KNOWN
    WRONG expectation first (in review, not in code) — what ships is the pair that
    distinguishes a working parser from a broken one, not a pair that any parser passes.
    """
    bad = []

    # 1. `comment_body` must STOP at the first non-comment line, or an ask swallows code.
    lines = [
        "        // NEEDS-FOUNDER-VERIFY: tap the thing",
        "        // and listen for the ease.",
        "        let x = 1",
        "        // unrelated trailing comment",
    ]
    body = comment_body(lines, 0)
    if "unrelated" in body or "let x" in body:
        bad.append(f"comment_body ran past the code line: {body!r}")
    if "listen for the ease" not in body:
        bad.append(f"comment_body dropped the continuation: {body!r}")

    # 2. A SECOND marker starts its own entry — otherwise two asks read as one.
    lines = [
        "// NEEDS-FOUNDER-VERIFY: first ask",
        "// NEEDS-FOUNDER-VERIFY: second ask",
    ]
    if "second ask" in comment_body(lines, 0):
        bad.append("comment_body merged two separate asks into one entry")

    # 3. The classifier must not put a named topic in `other` — the defect the first
    #    version shipped, where a directory rule left 32 of 53 unclassified.
    for path, want in [("Tests/CISmoke/TheHarmonizerMixTests.swift", "audio"),
                       ("Tests/CISmoke/PulseLockTests.swift", "bio"),
                       ("Sources/Echoelmusic/Views/MetalBioView.swift", "visual"),
                       ("Sources/Echoelmusic/Sync/OSCSender.swift", "sync")]:
        got = area_of(path)
        if got != want:
            bad.append(f"area_of({path}) = {got!r}, expected {want!r}")

    # 4. The reference split must move exactly the noun-uses and nothing else. These
    #    four strings are transcribed from the tree; the first is the sentence that
    #    registered this very tool in CLAUDE.md and made the count read 54 (#753).
    for line, want in [
        ("**`python3 scripts/founder-verify.py`** (#752): es sammelt jeden "
         "`NEEDS-FOUNDER-VERIFY`-Vermerk aus `Sources/`", "jeden"),
        ("kann, in dem Register, aus dem der NEEDS-FOUNDER-VERIFY-Rückstand triagiert "
         "wird", "der"),
        ("// discover that, sitting in the register a session reads when triaging the "
         "NEEDS-FOUNDER-VERIFY", "the"),
        ("//  a listen, and it is on the NEEDS-FOUNDER-VERIFY list rather than asserted "
         "here.", "the"),
    ]:
        got = is_reference(line, line.index(MARKER))
        if got != want:
            bad.append(f"is_reference missed a noun-use ({want!r}): got {got!r}")

    # 5. …and must NOT touch a real ask. Both forms below are transcribed from the tree:
    #    a bare marker and one wrapped in markdown bold, which the stripper must see past
    #    WITHOUT finding a determiner that is not there.
    for line in [
        "        // NEEDS-FOUNDER-VERIFY: tap the thing and listen",
        "// **NEEDS-FOUNDER-VERIFY (#747), now genuinely performable:** open Field",
        "//  cap. NEEDS-FOUNDER-VERIFY on device: does the strip still read?",
    ]:
        got = is_reference(line, line.index(MARKER))
        if got is not None:
            bad.append(f"is_reference hid a real ask as {got!r}: {line[:50]!r}")

    # 6. THE WIRING, not just the rule. Checks 4–5 exercise is_reference() directly and
    #    stay green even if collect() ignores it entirely — a mutant that drops the split
    #    passed all five while the header went back to counting 54. This walks the real
    #    tree and asserts the PROPERTY instead of a number: nothing in the ask list may
    #    have a determiner in front of it. It survives the tree changing; a count would not.
    asks, references = collect()
    for _, path, line_no, _ in asks:
        try:
            raw = open(path, encoding="utf-8").read().split("\n")[line_no - 1]
        except OSError:
            continue
        det = is_reference(raw, raw.index(MARKER))
        if det:
            bad.append(f"a noun-use stayed in the ask list: {path}:{line_no} (after {det!r})")
    if not references:
        bad.append("no references found at all — the split is wired out or the tree moved")

    for line in bad:
        print("FAIL:", line)
    print(f"selftest: {'FAILED' if bad else 'ok'} ({len(bad)} problem(s))")
    return 1 if bad else 0


def main() -> int:
    args = sys.argv[1:]
    if "--selftest" in args:
        return selftest()
    show_all = "--all" in args
    only = None
    if "--area" in args:
        try:
            only = args[args.index("--area") + 1]
        except IndexError:
            print("--area needs a name (bio audio visual sync ui other)")
            return 2

    found, refs = collect()
    if not found:
        print("No NEEDS-FOUNDER-VERIFY markers found — that is either a clean backlog "
              "or a broken walk. Check that Sources/ and Tests/ are present.")
        return 2                      # INSTRUMENT UNAVAILABLE, never a silent green

    by_area = {}
    for area, p, n, body in found:
        by_area.setdefault(area, []).append((p, n, body))

    print(f"Founder device-session checklist — {len(found)} asks in "
          f"{len({p for _, p, _, _ in found})} files\n")
    for area in sorted(by_area, key=lambda a: -len(by_area[a])):
        items = by_area[area]
        if only and area != only:
            print(f"  {area:8} {len(items):3d}   (--area {area} to read them)")
            continue
        print(f"── {area.upper()}  ({len(items)})")
        width = 200 if (show_all or only) else 110
        for p, n, body in items:
            short = p.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
            print(f"   {short}:{n}")
            print(f"      {body[:width]}{'…' if len(body) > width else ''}")
        print()

    if refs:
        print(f"── NOT ASKS ({len(refs)}) — the marker used as a noun, nobody can perform these")
        for p_, n_, det in refs:
            short = p_.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
            print(f"   {short}:{n_}   (\"{det}\" in front of it — prose about the backlog)")
        print()

    print("── LIMITS (read before treating this as a work queue)")
    print("   It CANNOT tell an answered ask from an open one. There is no 'verified' "
          "convention in\n     the tree, so an ask stays listed after the founder has "
          "done it. The repair is a\n     convention (e.g. VERIFIED-<date> on the same "
          "line), not a smarter parser.")
    print("   The AREA is derived from the file path, never from the words. A layout ask "
          "living in a\n     bio file lands under 'bio'. Order the walk yourself; this "
          "only makes the queue visible.")
    print("   It reads RAW text on purpose — every marker is a comment.")
    print("   The NOT-ASKS split keys on a determiner in front of the marker, and can only\n"
          "     REMOVE from the list above. A sentence about the backlog phrased without one\n"
          "     stays counted as an ask — noise, never a hidden job.")
    return 0


if __name__ == "__main__":
    # `founder-verify.py | head` is the natural way to skim this, and without SIG_DFL
    # here Python turns the closed pipe into a BrokenPipeError traceback — a tool that
    # prints a stack trace when you skim it reads as broken. Windows has no SIGPIPE.
    try:
        import signal
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except (ImportError, AttributeError, ValueError):
        pass
    sys.exit(main())
