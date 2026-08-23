#!/usr/bin/env python3
"""Collect every NEEDS-FOUNDER-VERIFY marker into one device-session checklist.

WHY THIS EXISTS. The two ship-gate checks that are still open — 1 Klang and
5 Stabilität — are BOTH sensory (see CLAUDE.md's SHIP GATE paragraph). No cycle can
close them by building; they need a device session. And the asks for that session were
scattered across 60+ files as free-text comments: measured 2026-08-23, **108 markers**.
Nothing collected them, nothing ordered them, and the founder had no way to see the
queue. The scarcest resource in this project is device time, and it had an invisible
backlog.

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
    found = []
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
                if MARKER in line:
                    found.append((area_of(p), p, i + 1, comment_body(lines, i)))
    return found


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

    found = collect()
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

    print("── LIMITS (read before treating this as a work queue)")
    print("   It CANNOT tell an answered ask from an open one. There is no 'verified' "
          "convention in\n     the tree, so an ask stays listed after the founder has "
          "done it. The repair is a\n     convention (e.g. VERIFIED-<date> on the same "
          "line), not a smarter parser.")
    print("   The AREA is derived from the file path, never from the words. A layout ask "
          "living in a\n     bio file lands under 'bio'. Order the walk yourself; this "
          "only makes the queue visible.")
    print("   It reads RAW text on purpose — every marker is a comment.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
