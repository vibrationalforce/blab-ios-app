#!/usr/bin/env python3
"""Collect every NEEDS-FOUNDER-VERIFY marker into one device-session checklist.

WHY THIS EXISTS. The two ship-gate checks that are still open — 1 Klang and
5 Stabilität — are BOTH sensory (see CLAUDE.md's SHIP GATE paragraph). No cycle can
close them by building; they need a device session. And the asks for that session were
scattered through the tree as free-text comments. Nothing collected them, nothing
ordered them, and the founder had no way to see the queue. The scarcest resource in
this project is device time, and it had an invisible backlog.

⚠️ TWO NUMBERS, BOTH CORRECT — name the OPERATION and the SCOPE or they read as a
contradiction. One counts every OCCURRENCE of the marker over four roots (Sources, Tests,
CLAUDE.md, scratchpads); the other counts ASK LINES over the three roots this tool walks,
after the reference lines below are set aside. A line can carry the marker twice;
scratchpads are session prose, not asks. Neither is wrong; the first version of this
docstring printed one of them next to a header showing the other and explained neither.

⛔ THE TWO LITERALS ARE DELETED, NOT REFRESHED (#1053, #818). They were 108 and 50, both
long expired — the second by roughly a factor of two — in a file whose whole job is to
print the current count two lines lower. **The header IS the measurement; the docstring
only names the two OPERATIONS.** Re-derive the wide one with
`git grep -c NEEDS-FOUNDER-VERIFY -- Sources Tests CLAUDE.md scratchpads`, and the narrow
one by running this tool.

⛔ AND THE INSTRUMENT COUNTED ITS OWN DESCRIPTION (#753). Registering this tool in
CLAUDE.md added a line reading "es sammelt jeden `NEEDS-FOUNDER-VERIFY`-Vermerk" — and
the next run reported 54 asks instead of 53. The 54th was the sentence describing the
tool. Four such lines exist: two in CLAUDE.md, two in guard headers that talk ABOUT the
backlog. They are not asks; nobody can perform them. See is_reference().

WHAT IT IS NOT. It does not decide anything. It turns scattered prose into a list you
can walk with a phone in your hand.

⭐ ANSWERED ASKS (#773). Until now the queue could only GROW: nothing in the tree said
"the founder did this one", so a settled ask stayed listed forever and every device
session started by re-reading jobs that were already done. The tool named its own repair
in its LIMITS — "a convention, not a smarter parser" — and this is that convention:

    // NEEDS-FOUNDER-VERIFY VERIFIED-2026-08-23: lock while stopped, listen to the ease.

The mark goes on the SAME LINE as the marker, because that is the line this tool already
keys on; a mark one line below would be ambiguous the moment two asks sit adjacent. A
marked ask leaves the open queue and is counted under ANSWERED — never deleted, because
deleting it also deletes the DATE, and "when was this last confirmed" is the question a
regression makes you ask.

⛔ IT MUST MATCH A REAL DATE, NOT THE WORD, and that is the #753 trap seen coming instead
of paid for. `VERIFIED-<date>` is how one WRITES ABOUT the convention — it appears twice
in this very file and once in the LIMITS text the tool prints. A parser keying on the
bare prefix would read its own documentation as an answer and silently retire an ask
nobody performed. The needle is therefore `VERIFIED-` followed by `\d{4}-\d{2}-\d{2}`.

⭐ AND IT FAILS TOWARD NOISE, exactly like the determiner rule below. A malformed or
half-typed mark leaves the ask OPEN. Showing a settled ask costs the founder a glance;
hiding an open one costs a device session, and those are not the same mistake.

⚠️ ZERO ASKS CARRY THE MARK TODAY, and that is honest rather than disappointing: I cannot
know which ones the founder has already done, and guessing would retire real jobs. The
feature ships with ANSWERED at 0 and fills up as he walks the list.

⭐ BLOCKED ASKS (#1053). A third state, and the one that made this list partly a wall:
an ask whose DOOR no longer exists. #1024 removed all three microphone doors on a founder
command, and ten asks went on instructing him to tap "Mix chip -> Choose input...". Same
same-line convention, digits required for the #753 reason:

    // NEEDS-FOUNDER-VERIFY BLOCKED-BY-#NNNN: <the original instruction>

They are held out of the open count and printed in their own section with the slice that
took the door — never deleted, because the engine behind them is untouched and these are
the probes that must run on the day it is re-doored. ANSWERED wins over BLOCKED: a date is
a fact about the past that a later removal cannot undo.

    python3 scripts/founder-verify.py             # counts per area + one line each
    python3 scripts/founder-verify.py --all       # the full instruction for every ask
    python3 scripts/founder-verify.py --area bio  # one area, full instructions
    python3 scripts/founder-verify.py --setup     # grouped by the EQUIPMENT a session needs

Read-only, no dependencies, no network, no build — the doctor.py house rules.
"""
import os
import re
import subprocess
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
#
# ⭐ #1149 WIDENED THE TABLE BECAUSE "other" HAD GROWN BACK TO 43 OF 110 — 39 %, which is
# the same "not a classification, it is a list" the paragraph above measured at 60 %. The
# cause is not a regression in the rule; it is that the visual/flash/colour work of the
# last weeks minted a whole vocabulary the table predates (Aurora, Caustics, Dish,
# Wavefront, Shader, Hue, Flash, Blend, Still).
#
# ⭐ WHY WIDENING IS SAFE IN A WAY THE OTHER RULES IN THIS FILE ARE NOT. An area label can
# only move an ask from "other" into a named bucket. It can never HIDE one — that is what
# `is_reference` does, and why that rule is measured so much harder. The only real hazard
# is the ORDER tie-break above: a needle added to an EARLIER area can steal an ask that a
# LATER one classifies correctly today.
#
# ⛔ TWO CANDIDATES WERE MEASURED AND KILLED FOR EXACTLY THAT. "Input" for audio would
# have stolen `TheMPEInputHasNoZonesTests` from `sync` (audio is matched first) — the
# needle is `InputEdge`. "Key" for the musical key would have stolen
# `TheKeypadCannotTypeWhatItCannotKeepTests` from `ui` — the needle is `Flat`. Both were
# found by diffing every ask's bucket before and after, not by reading the list.
#
# ⛔ A THIRD WAS KILLED BY THAT DIFF AFTER IT WAS ALREADY WRITTEN, which is the whole
# argument for running it. "Still" (for the still-image asks) matched inside
# `TheMonoVoiceKeepsTheKeyStillDownTests` and moved it AUDIO → VISUAL — a needle that is a
# whole word in one name and a syllable in another. The obvious repairs were both worse:
# a file-specific needle (`StillIsOne`) is brittle by construction, and "Frame" would have
# stolen `TheLockNeedsFramesTests` from `bio`. So the needle is simply GONE and its two
# asks stay in "other". A bucket that is honestly empty of a topic beats one that is
# quietly wrong about a neighbour.
AREAS = [
    ("visual", ("/Video/", "/Views/", "Visual", "Metal", "Look", "Recording", "Clip",
                "Donut", "Colour", "Shader", "Aurora", "Rings", "Caustic", "Dish",
                "Wavefront", "Hue", "Flash", "Blend", "Filmic")),
    ("bio", ("/Bio/", "Bio", "Pulse", "Coherence", "Breath", "Heart", "Camera", "RPPG",
             "Confidence", "Lock", "Stall")),
    ("audio", ("/Audio/", "/DSP/", "/Tools/", "/Sequencer/", "FX", "Grain", "Chain",
               "Tempo", "Genre", "Sound", "Patch", "Voice", "Autotune", "Reverb", "Mix",
               "Take", "Loop", "Monitor", "Tune", "Detune", "Instrument", "Howl",
               "Harmoni", "Mute", "Buffer", "InputEdge", "Silent", "Microphone",
               "Lifecycle", "PlugIn", "Retry", "Bar", "Flat")),
    ("sync", ("/Sync/", "/Stream/", "OSC", "MIDI", "MPE", "Peer", "Wire", "ArtNet",
              "Lux")),
    ("ui", ("/Studio/", "Text", "Label", "Chip", "Scroll", "Tap", "Sheet", "Panel",
            "Row", "Size", "Undo", "Menu", "Door", "Header", "Control", "Button",
            "Project", "Preset", "Keypad", "Rotation", "Chrome")),
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

# The reason token for the string-literal shape (see is_reference). It is a sentinel, not a
# word, so the renderer can tell the two kinds of non-ask apart without re-deriving them.
BARE_LITERAL = "<bare string literal>"

# See the ANSWERED paragraph in the module docstring. The date is REQUIRED: the bare
# prefix is how the convention is written ABOUT, including three times in this file, so a
# prefix-only needle would retire asks by reading documentation (#753, one layer over).
VERIFIED = re.compile(r"VERIFIED-(\d{4}-\d{2}-\d{2})")

# ⭐ BLOCKED ASKS (#1053). A third state the two above cannot express: an ask that is
# neither open nor answered, because the DOOR it instructs the founder to open is gone.
# #1024 removed all three microphone doors on a founder command, and ten asks kept telling
# him to tap "Mix chip -> Choose input...". A checklist that hands out jobs nobody can do
# is the same defect class as a masked gate — it looks like a queue and part of it is a
# wall. The engine behind those asks is untouched, so the asks are NOT deleted: re-dooring
# is three call sites, and the day it happens these are the tests that must run.
#
# ⛔ THE NEEDLE REQUIRES DIGITS, for the #753 reason `VERIFIED-` learned the hard way: the
# bare prefix is how one WRITES ABOUT the convention (it appears in this comment, in the
# module docstring and in the LIMITS text this tool prints), so a prefix-only needle would
# retire asks by reading its own documentation. Write the shape as BLOCKED-BY-#NNNN when
# describing it; only a real slice number marks a real ask.
#
# ⭐ AND IT FAILS TOWARD NOISE, the same direction as everything else here: a malformed
# mark leaves the ask OPEN. Showing a blocked ask costs a glance; hiding a live one costs
# a device session.
BLOCKED = re.compile(r"BLOCKED-BY-#(\d+)\b")


# ── SETUP buckets: what you must physically HAVE IN HAND, not what the ask is about.
#
# ⭐ WHY THIS EXISTS ALONGSIDE `AREAS`. A device session is bounded by SETUP, not by topic.
# The founder plugs in headphones once and can then answer every headphone ask in one pass;
# grouped by area those same asks sit in three different buckets and read as three trips.
# `--area` answers "what is this about", `--setup` answers "what do I need to have with me".
#
# ⛔ THIS DELIBERATELY BREAKS THE RULE STATED ABOVE FOR `AREAS`, and the exception has to be
# argued rather than assumed. That rule says: classify from the FILE NAME, because a keyword
# classifier on prose this dense mislabels constantly. It is right — about TOPIC, which the
# basename genuinely carries. It cannot apply here: no filename can say "you need a
# Bluetooth headset". The setup exists ONLY in the prose, so prose is the only place to read
# it, and the mitigation is not accuracy but SHAPE — see the next paragraph.
#
# ⚠️ IT FAILS TOWARD NOISE, which is this file's standing principle: an ask matching nothing
# lands in "none named" rather than a guessed bucket, and an ask may appear in SEVERAL
# buckets (headphones AND monitoring is a real combination). So the bucket totals add up to
# MORE than the number of asks, and the header prints both numbers for that reason. A
# duplicate costs a glance; a wrong bucket costs a trip with the wrong equipment.
#
# ⚠️ ORDER DOES NOT MATTER HERE — unlike `AREAS`, which returns one bucket and needs a
# tie-break. This returns a set.
#
# ⛔ BARE "lock" IS DELIBERATELY ABSENT from `background`, and the selftest pins it. This
# repo says "pulse lock" and "locks on device" constantly about rPPG; a `lock` needle would
# sweep half the bio queue into "lock the screen". The needles are lock SCREEN, sperren,
# Anruf, call, Hintergrund, background — the physical act, never the shared word.
SETUP = [
    ("headphones", ("Kopfhörer", "headphone", "Bluetooth", "A2DP", "in-ear")),
    ("speaker", ("Lautsprecher", "speaker", "Megaphon", "megaphone", "Howl", "howl",
                 "Rückkopplung", "feedback")),
    ("monitoring", ("Monitoring", "monitoring", "Choose input", "Mikrofon", "microphone",
                    "mic ", "Autotune", "autotune", "Tune to key")),
    ("strap", ("Gurt", "strap", "Polar", "H10", "BLE", "0x180D")),
    ("camera", ("Finger", "finger", "Kamera", "camera", "rPPG", "Linse", "lens", "Torch",
                "torch")),
    ("network", ("OSC", "Art-Net", "ArtNet", "sACN", "DMX", "Pult", "console", "LAN")),
    ("background", ("lock screen", "sperren", "Anruf", "phone call", "Hintergrund",
                    "background", "Interruption", "interruption")),
    # ⭐ ADDED #873 AFTER READING THE "no setup named" PILE, which is what that pile is FOR.
    # Six asks in the first screenful were Dynamic-Type probes — the same iOS Settings change
    # answers all of them in one pass — and the first version of this table had no needle for
    # any of them, so they read as "no equipment" when they need the most deliberate setup on
    # the list. A bucket nobody thought of looks exactly like an ask that needs nothing.
    ("larger-text", ("Larger Text", "Text Size", "accessibility step", "AX3", "AX5",
                     "Dynamic Type", "dynamicType")),
    ("rotation", ("rotate", "Rotate", "landscape", "Landscape", "Querformat", "Hochformat",
                  "portrait", "Portrait")),
]


def setups_of(body: str) -> list:
    """Every setup bucket this ask's own words call for. Empty means none named."""
    return [name for name, needles in SETUP if any(k in body for k in needles)]


def verified_on(line: str):
    """The ISO date a founder confirmed this ask, or None while it is open.

    Malformed marks return None on purpose — an unreadable mark leaves the ask in the
    queue, which is the direction that costs a glance instead of a device session.
    """
    m = VERIFIED.search(line)
    return m.group(1) if m else None


def blocked_by(line: str):
    """The slice number that removed this ask's door, or None while it is performable.

    Malformed marks return None on purpose — see the BLOCKED comment above.
    """
    m = BLOCKED.search(line)
    return m.group(1) if m else None


def state_of(line: str):
    """`("answered", date)` | `("blocked", slice)` | `("open", None)` for one marker line.

    ⛔ IT IS A FUNCTION AND NOT TWO `if`s INSIDE `collect()` BECAUSE OF ONE MUTANT (#1053).
    The precedence — a date WINS over a block — could not be driven while it lived inline:
    zero asks carry a date today, so the tree-walking check that was supposed to pin it ran
    over an empty list and stayed green with the precedence inverted. A claim that cannot
    fail is not a claim (#454). Pulled out here, it takes one synthetic line to prove.

    The precedence itself: ANSWERED wins. A date is a fact about the past, and a door
    removed afterwards cannot undo a thing the founder already heard on a device — while
    losing that date is exactly what a regression makes you want back.
    """
    when = verified_on(line)
    if when:
        return ("answered", when)
    slice_no = blocked_by(line)
    if slice_no:
        return ("blocked", slice_no)
    return ("open", None)


def is_reference(line: str, at: int):
    """The determiner in front of the marker, or None when this line is an ask.

    `at` is the index the marker starts at. Markup characters immediately before it
    (backtick, asterisk, underscore) are not words and are stripped.
    """
    # ⛔ A SECOND SHAPE THE DETERMINER RULE CANNOT SEE (#887, measured 2026-08-30). The
    # marker can sit inside a Swift STRING LITERAL, where the word in front of it is a
    # quote and a paren — no determiner, so the rule above lets it through and the founder
    # is handed a job that is really a guard asserting the convention still exists:
    #     XCTAssertTrue(doc.contains("NEEDS-FOUNDER-VERIFY"), …)
    # That is #753 one layer further out: the tool counted the test that polices its own
    # checklist. The needle is deliberately the NARROWEST one that separates them — the
    # marker must be the ENTIRE content of the literal. An ask needs words, so a bare
    # literal can never be one, and this cannot hide a real ask no matter how it is
    # phrased. Measured across Sources/ + Tests/: exactly ONE line matches, and it is the
    # offending one. A looser rule ("marker anywhere inside a string") was rejected — real
    # asks do live in assertion messages, and hiding one costs a device session while
    # over-counting costs a glance (this file's standing direction).
    before = line[:at].rstrip()
    after = line[at + len(MARKER):].lstrip()
    if before.endswith('"') and after.startswith('"'):
        return BARE_LITERAL

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
    found, refs, done, walled = [], [], [], []
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
                    continue
                kind, mark = state_of(line)
                if kind == "answered":
                    done.append((area_of(p), p, i + 1, mark))
                elif kind == "blocked":
                    walled.append((area_of(p), p, i + 1, mark,
                                   comment_body(lines, i)))
                else:
                    found.append((area_of(p), p, i + 1, comment_body(lines, i)))
    return found, refs, done, walled



# ── --since: which asks the build in the founder's hand made newly answerable ──────────
#
# ⭐ WHY THIS EXISTS (#931). The list is grouped by AREA, which is the right shape for
# "walk the whole backlog" and the wrong one for the question the founder actually has
# after a TestFlight build lands: *what did THIS build change that I can test right now?*
# Sixty-odd asks are a project; the handful a new build touched are an evening. His device
# time is the scarcest resource in this repo — every check that reads "you already answered
# that" or "that is not wired yet" is spent for nothing.
#
# ⚠️ IT COMPARES THE REF TO THE **WORKING TREE**, not to `HEAD`, and that is not a detail.
# `collect()` reads the working tree, so a `<ref>..HEAD` diff would hand back line numbers
# from a different text the moment anything is uncommitted — the asks would be filtered by
# positions that no longer mean what they meant. `git diff <ref>` (no second endpoint) is
# exactly the comparison whose post-image IS the text being walked.
#
# ⚠️ AN ASK THAT MERELY MOVED IS CORRECTLY NOT "NEW". Editing lines above a marker shifts
# its number without touching it; git reports no addition, and the ask stays out of the
# filtered view. That is the intent: the founder is asking what CHANGED, not what slid.
def added_lines_since(ref: str):
    """Post-image line numbers added or reworded since `ref`, per path. None = cannot tell."""
    try:
        out = subprocess.run(
            ["git", "diff", "-M", "--unified=0", ref, "--"] + list(ROOTS),
            capture_output=True, text=True, cwd=os.path.dirname(os.path.dirname(
                os.path.abspath(__file__))) or ".")
    except OSError:
        return None
    if out.returncode != 0:
        return None
    added, path = {}, None
    for line in out.stdout.split("\n"):
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@") and path:
            # `@@ -a,b +c,d @@` — `d` may be absent (means 1) or 0 (a pure deletion).
            try:
                plus = line.split("+", 1)[1].split(" ", 1)[0]
            except IndexError:
                continue
            start, _, count = plus.partition(",")
            try:
                start_no, span = int(start), int(count) if count else 1
            except ValueError:
                continue
            for n in range(start_no, start_no + span):
                added.setdefault(path, set()).add(n)
    return added


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

    # 3b. `setups_of` must read the PROSE for physical equipment, and must NOT sweep the
    #     shared vocabulary. The pulse-lock case is the one that matters: this repo says
    #     "lock" about rPPG constantly, so a bare `lock` needle would file half the bio queue
    #     under "lock the screen". Driven with a known-wrong expectation first, per the rule
    #     at the top of this function.
    for body, want, forbid in [
        ("plug in Bluetooth-Kopfhörer, play, monitoring on", {"headphones", "monitoring"}, set()),
        ("hold a finger on the lens until the pulse locks on device", {"camera"}, {"background"}),
        ("send to a DMX console over Art-Net and watch the fixture", {"network"}, set()),
        ("tap the tempo field and listen to the ease", set(), set()),
        # #873: the two buckets the first table forgot. The rotation case ALSO checks that a
        # landscape probe is not swept into `larger-text` merely for saying "text".
        ("iOS Settings → Display → Text Size at an accessibility step, Bio panel open",
         {"larger-text"}, {"rotation"}),
        ("open the visual fullscreen, rotate to landscape, check the text still fits",
         {"rotation"}, set()),
    ]:
        got = set(setups_of(body))
        if not want <= got:
            bad.append(f"setups_of missed {want - got} in {body!r} (got {sorted(got)})")
        if got & forbid:
            bad.append(f"setups_of wrongly bucketed {sorted(got & forbid)} for {body!r}")

    # 3. The classifier must not put a named topic in `other` — the defect the first
    #    version shipped, where a directory rule left 32 of 53 unclassified.
    #    ⭐ THE SECOND HALF OF THIS LIST IS THE #1149 ORDER-HAZARD, and it is here because
    #    a widened table cannot be checked by reading it. `AREAS` is scanned in order, so a
    #    needle added to an EARLIER area silently steals an ask a LATER one gets right. All
    #    four names below were measured, not imagined: `TheMonoVoiceKeepsTheKeyStillDown`
    #    actually moved audio → visual on a "Still" needle before the diff caught it, and
    #    the other three are the shapes that would break next. A needle whose word is a
    #    whole word in one name and a SYLLABLE in another is the failure mode; these pin it.
    for path, want in [("Tests/CISmoke/TheHarmonizerMixTests.swift", "audio"),
                       ("Tests/CISmoke/PulseLockTests.swift", "bio"),
                       ("Sources/Echoelmusic/Views/MetalBioView.swift", "visual"),
                       ("Sources/Echoelmusic/Sync/OSCSender.swift", "sync"),
                       # "Still" as a syllable — the needle that was written and removed.
                       ("Tests/CISmoke/TheMonoVoiceKeepsTheKeyStillDownTests.swift", "audio"),
                       # ⛔ THIS EXPECTATION WAS WRONG WHEN IT WAS WRITTEN AND THE SELFTEST
                       # SAID SO. The comment claimed "Input" would steal this file FROM
                       # sync; measured, it was in `other` all along — "MPE" is not "MIDI",
                       # and nothing in the sync row matched it. #1149 added the `MPE`
                       # needle, so the expectation is TRUE now for a different reason than
                       # the one first given, and the hazard it pins is real from here on:
                       # a bare `Input` in audio would take it back out.
                       ("Tests/CISmoke/TheMPEInputHasNoZonesTests.swift", "sync"),
                       # "Key" would have pulled this out of ui; the needle is Flat.
                       ("Tests/CISmoke/TheKeypadCannotTypeWhatItCannotKeepTests.swift", "ui"),
                       # "Frame(s)" for visual would have pulled this out of bio.
                       ("Tests/CISmoke/TheLockNeedsFramesTests.swift", "bio")]:
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

    # 5b. THE STRING-LITERAL SHAPE (#887). The first line is transcribed verbatim from
    #     `TheDeviceChecklistOnlyAsksWhatExistsTests.swift` — the guard that polices the
    #     founder checklist, which this tool was counting as a 62nd job for the founder.
    #     The three lines under it are the ones the rule must NOT touch: a real ask that
    #     merely CONTAINS a quoted phrase, a real ask inside an assertion message, and a
    #     literal that carries words beside the marker. Driven with the known-wrong
    #     expectation first (all four as references) — that version "passed" the first line
    #     and hid two real asks, which is exactly the direction this file forbids.
    for line, want in [
        ('        XCTAssertTrue(doc.contains("NEEDS-FOUNDER-VERIFY"),', BARE_LITERAL),
        ('// NEEDS-FOUNDER-VERIFY: the row must read "Non-standard tuning"', None),
        ('            "NEEDS-FOUNDER-VERIFY: play a take and listen for the ease")', None),
        ('        XCTAssertTrue(doc.contains("NEEDS-FOUNDER-VERIFY: tap it"),', None),
    ]:
        got = is_reference(line, line.index(MARKER))
        if got != want:
            bad.append(f"the literal rule answered {got!r}, expected {want!r}: {line[:52]!r}")

    # 6. THE WIRING, not just the rule. Checks 4–5 exercise is_reference() directly and
    #    stay green even if collect() ignores it entirely — a mutant that drops the split
    #    passed all five while the header went back to counting 54. This walks the real
    #    tree and asserts the PROPERTY instead of a number: nothing in the ask list may
    #    have a determiner in front of it. It survives the tree changing; a count would not.
    asks, references, _answered, _walled = collect()
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

    # 7. THE ANSWERED RULE (#773). A real date retires an ask; the way the convention is
    #    WRITTEN ABOUT must not. The third string is transcribed from this file's own
    #    LIMITS output — the exact sentence that would have retired asks by documentation.
    for line, want in [
        ("// NEEDS-FOUNDER-VERIFY VERIFIED-2026-08-23: lock while stopped", "2026-08-23"),
        ("// NEEDS-FOUNDER-VERIFY: tap the thing", None),
        ("a convention (e.g. VERIFIED-<date> on the same line), not a smarter parser", None),
        ("// NEEDS-FOUNDER-VERIFY VERIFIED-2026: half-typed, stays open", None),
        ("// NEEDS-FOUNDER-VERIFY VERIFIED: no date at all, stays open", None),
    ]:
        got = verified_on(line)
        if got != want:
            bad.append(f"verified_on({line[:44]!r}) = {got!r}, expected {want!r}")

    # 8. THE WIRING for it, the check 6 lesson repeated deliberately (#739): rule 7 passes
    #    even if collect() never calls verified_on. Assert the PROPERTY over the real tree —
    #    no line in the OPEN queue may carry a date, and no line in ANSWERED may lack one.
    #    A count would go stale the first time the founder marks something; this does not.
    open_asks, _, answered, _walled2 = collect()
    for _, path, line_no, _ in open_asks:
        try:
            raw = open(path, encoding="utf-8").read().split("\n")[line_no - 1]
        except OSError:
            continue
        if verified_on(raw):
            bad.append(f"an answered ask stayed in the open queue: {path}:{line_no}")
    for _, path, line_no, when in answered:
        if not when:
            bad.append(f"an ask reached ANSWERED with no date: {path}:{line_no}")

    # 8b. THE BLOCKED RULE (#1053), same two halves as 7+8 and for the same paid reason.
    #     The third string below is transcribed from THIS FILE's own docstring — the exact
    #     sentence that would have retired ten asks by reading its own documentation if the
    #     needle took the bare prefix (#753, third time). Digits are what separates a mark
    #     from a description of the convention.
    for line, want in [
        ("// NEEDS-FOUNDER-VERIFY BLOCKED-BY-#1024: monitoring on, sing", "1024"),
        ("// NEEDS-FOUNDER-VERIFY: tap the thing", None),
        ("    // NEEDS-FOUNDER-VERIFY BLOCKED-BY-#NNNN: <the original instruction>", None),
        ("// NEEDS-FOUNDER-VERIFY BLOCKED-BY-: no slice at all, stays open", None),
        ("// NEEDS-FOUNDER-VERIFY BLOCKED-BY#1024: mistyped, stays open", None),
    ]:
        got = blocked_by(line)
        if got != want:
            bad.append(f"blocked_by({line[:44]!r}) = {got!r}, expected {want!r}")

    # 8c. THE WIRING for it — check 6's lesson a third time (#739). Rule 8b passes even if
    #     collect() never calls blocked_by. Assert the PROPERTY over the real tree: no line
    #     in the OPEN queue may carry a mark, every BLOCKED line must carry one, and an
    #     ANSWERED date must WIN over a mark on the same line (a date is a fact about the
    #     past that a later door removal cannot undo).
    open3, _, answered3, walled3 = collect()
    for _, path, line_no, _ in open3:
        try:
            raw = open(path, encoding="utf-8").read().split("\n")[line_no - 1]
        except OSError:
            continue
        if blocked_by(raw) and not verified_on(raw):
            bad.append(f"a blocked ask stayed in the open queue: {path}:{line_no}")
    for _, path, line_no, slice_no, _ in walled3:
        if not slice_no:
            bad.append(f"an ask reached BLOCKED with no slice: {path}:{line_no}")
    for _, path, line_no, _ in answered3:
        try:
            raw = open(path, encoding="utf-8").read().split("\n")[line_no - 1]
        except OSError:
            continue
        if not verified_on(raw):
            bad.append(f"an ANSWERED entry has no date at its line: {path}:{line_no}")

    # 8d. THE PRECEDENCE, on SYNTHETIC lines — and this check exists because the tree could
    #     not carry it. Zero asks are answered today, so 8c's answered loop runs over an
    #     empty list: a mutant that inverted the precedence passed the whole selftest. That
    #     is the #454 defect inside the anti-#454 machinery. `state_of` was extracted so
    #     one line can prove it.
    for line, want in [
        ("// NEEDS-FOUNDER-VERIFY VERIFIED-2026-08-23 BLOCKED-BY-#1024: both marks",
         ("answered", "2026-08-23")),
        ("// NEEDS-FOUNDER-VERIFY BLOCKED-BY-#1024 VERIFIED-2026-08-23: order swapped",
         ("answered", "2026-08-23")),
        ("// NEEDS-FOUNDER-VERIFY BLOCKED-BY-#1024: door gone", ("blocked", "1024")),
        ("// NEEDS-FOUNDER-VERIFY: tap the thing", ("open", None)),
    ]:
        got = state_of(line)
        if got != want:
            bad.append(f"state_of({line[:46]!r}) = {got!r}, expected {want!r}")

    # 9. `--since` HUNK PARSING (#931). Driven over the three shapes git actually emits.
    #    `+c` with no count means ONE line; `+c,0` is a pure deletion and adds nothing. A
    #    parser that reads the missing count as 0 loses every single-line change — i.e. most
    #    of them — and one that reads `,0` as 1 invents an ask at a deleted position.
    class _Fake:
        returncode = 0
        stdout = "\n".join([
            "diff --git a/Sources/A.swift b/Sources/A.swift",
            "+++ b/Sources/A.swift",
            "@@ -10 +10 @@",
            "@@ -20,0 +21,2 @@",
            "@@ -30,2 +33,0 @@",
            "+++ b/Tests/B.swift",
            "@@ -1,0 +2 @@",
        ])
    real_run = subprocess.run
    try:
        subprocess.run = lambda *a, **k: _Fake()
        got = added_lines_since("whatever")
    finally:
        subprocess.run = real_run
    want = {"Sources/A.swift": {10, 21, 22}, "Tests/B.swift": {2}}
    if got != want:
        bad.append(f"--since hunk parsing: got {got}, want {want}")

    # 10. THE FAILURE MODE THAT MATTERS MORE THAN THE PARSING. An unresolvable ref must come
    #     back as None, never as an empty dict: `{}` filters every ask away and prints
    #     "nothing changed since <ref>", which is a confident WRONG answer that sends the
    #     founder to bed. `None` is what makes `main` exit 2 and say it could not look.
    class _Failed:
        returncode = 128
        stdout = ""
    try:
        subprocess.run = lambda *a, **k: _Failed()
        got_bad = added_lines_since("no-such-ref")
    finally:
        subprocess.run = real_run
    if got_bad is not None:
        bad.append(f"an unresolvable ref returned {got_bad!r} instead of None — "
                   "that prints 'nothing changed' for a question nobody answered")

    for line in bad:
        print("FAIL:", line)
    print(f"selftest: {'FAILED' if bad else 'ok'} ({len(bad)} problem(s))")
    return 1 if bad else 0


def main() -> int:
    args = sys.argv[1:]
    if "--selftest" in args:
        return selftest()
    show_all = "--all" in args
    show_setup = "--setup" in args
    since = None
    if "--since" in args:
        try:
            since = args[args.index("--since") + 1]
        except IndexError:
            print("--since needs a git ref (e.g. the previous deploy's bump commit)")
            return 2
    only = None
    if "--area" in args:
        try:
            only = args[args.index("--area") + 1]
        except IndexError:
            print("--area needs a name (bio audio visual sync ui other)")
            return 2

    found, refs, done, walled = collect()
    if not found:
        print("No NEEDS-FOUNDER-VERIFY markers found — that is either a clean backlog "
              "or a broken walk. Check that Sources/ and Tests/ are present.")
        return 2                      # INSTRUMENT UNAVAILABLE, never a silent green

    total_open = len(found)
    if since is not None:
        added = added_lines_since(since)
        # ⛔ NO SILENT FALLBACK TO THE FULL LIST. If git could not answer — no repo, a ref
        # that does not resolve, git missing — printing all 60-odd asks under a header that
        # says "since <ref>" would send the founder to re-test things this build never
        # touched, and look like a deliberate answer. Exit 2 is this file's own word for
        # "the instrument could not look", and `doctor` uses the same code for the same
        # reason. Never a silent green, and never a silent WRONG list either.
        if added is None:
            print(f"Cannot resolve `{since}` — no answer given rather than the whole list.\n"
                  f"   `git diff -M --unified=0 {since} -- {' '.join(ROOTS)}` is what this "
                  f"needs; run it by hand to see why it failed.")
            return 2
        found = [(a, p, n, b) for (a, p, n, b) in found if n in added.get(p, ())]

    by_area = {}
    for area, p, n, body in found:
        by_area.setdefault(area, []).append((p, n, body))

    answered_note = f", {len(done)} answered" if done else ", none answered yet"
    if since is None:
        print(f"Founder device-session checklist — {len(found)} OPEN asks in "
              f"{len({p for _, p, _, _ in found})} files{answered_note}\n")
    else:
        # ⚠️ THE FILTERED COUNT MUST NEVER READ AS THE BACKLOG. Printing "12 OPEN asks"
        # under a `--since` run would understate the queue by a factor of five and look
        # identical to a shrinking backlog. Both numbers, and the word NEW, every time.
        print(f"Founder device-session checklist — {len(found)} NEW or REWORDED since "
              f"`{since}`, of {total_open} open{answered_note}")
        print("   'New' means the marker LINE was added or changed. An ask that only moved "
              "(lines edited above it) is deliberately NOT here — it did not change.")
        print("   ⚠️ It sees TEXT, not capability: a REWORDED ask is an old ask whose sentence "
              "was polished, not one that became newly answerable. Read the sentence.")
        if not found:
            print(f"\n   Nothing changed since `{since}`. The full list is the same command "
                  f"without --since.")
            return 0
        print()
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

    if show_setup:
        by_setup, none_named = {}, []
        for _area, p, n, body in found:
            buckets = setups_of(body)
            if not buckets:
                none_named.append((p, n, body))
            for b in buckets:
                by_setup.setdefault(b, []).append((p, n, body))
        grouped = sum(len(v) for v in by_setup.values())
        print(f"── BY SETUP — {grouped} bucket entries across {len(found)} asks "
              f"(an ask needing two things is listed twice, on purpose)\n")
        for name in sorted(by_setup, key=lambda b: -len(by_setup[b])):
            items = by_setup[name]
            print(f"── {name.upper()}  ({len(items)}) — one setup, {len(items)} asks answered")
            for p, n, body in items:
                short = p.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
                print(f"   {short}:{n}")
                print(f"      {body[:150]}{'…' if len(body) > 150 else ''}")
            print()
        print(f"── NO SETUP NAMED ({len(none_named)}) — not \"needs nothing\": their own words "
              f"do not say.\n   Read them before planning a session; the tool refuses to guess.")
        for p, n, body in none_named:
            short = p.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
            print(f"   {short}:{n}   {body[:100]}{'…' if len(body) > 100 else ''}")
        print()
        return 0

    if refs:
        print(f"── NOT ASKS ({len(refs)}) — the marker used as a noun, nobody can perform these")
        for p_, n_, det in refs:
            short = p_.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
            if det == BARE_LITERAL:
                why = "the marker IS the whole string literal — a guard asserting the convention"
            else:
                why = f"\"{det}\" in front of it — prose about the backlog"
            print(f"   {short}:{n_}   ({why})")
        print()

    if done:
        print(f"── ANSWERED ({len(done)}) — confirmed on a device, kept for the date")
        for area, p_, n_, when in sorted(done, key=lambda r: r[3], reverse=True):
            short = p_.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
            print(f"   {when}  {area:7} {short}:{n_}")
        print()

    if walled:
        doors = sorted({s for _, _, _, s, _ in walled})
        print(f"── BLOCKED ({len(walled)}) — the door these instruct you to open was removed")
        print(f"   By slice #{', #'.join(doors)}. NOT open, NOT answered, NOT deleted: the")
        print("   engine behind them is untouched, so the day the door comes back these are")
        print("   exactly the probes that must run. They are held out of the count above so")
        print("   the queue is jobs you can actually do with a phone in your hand.")
        for area, p_, n_, slice_no, body in sorted(walled, key=lambda r: (r[0], r[1])):
            short = p_.replace("Sources/Echoelmusic/", "").replace("Tests/CISmoke/", "CISmoke/")
            print(f"   #{slice_no}  {area:7} {short}:{n_}")
            print(f"          {body[:110]}…")
        print()

    print("── HOW TO RETIRE AN ASK once you have done it on a device")
    print("   Put the date on the SAME line as the marker, then commit:")
    print("     // NEEDS-FOUNDER-VERIFY VERIFIED-YYYY-MM-DD: <the original instruction>")
    print("   Keep the instruction. The line stays as the record of WHAT was confirmed and")
    print("     WHEN — deleting it also deletes the date, which is the first thing you want")
    print("     back when the behaviour regresses.\n")

    print("── LIMITS (read before treating this as a work queue)")
    print("   ANSWERED depends on somebody writing the mark. An ask you did on a device but\n"
          "     never marked stays in the open list — the tool reads the tree, not your\n"
          "     memory. It fails toward noise on purpose: a half-typed mark leaves the ask\n"
          "     OPEN, because showing a settled ask costs a glance and hiding an open one\n"
          "     costs a device session.")
    print("   The AREA is derived from the file path, never from the words. A layout ask "
          "living in a\n     bio file lands under 'bio'. Order the walk yourself; this "
          "only makes the queue visible.")
    print("   It reads RAW text on purpose — every marker is a comment.")
    print("   The NOT-ASKS split keys on a determiner in front of the marker, and can only\n"
          "     REMOVE from the list above. A sentence about the backlog phrased without one\n"
          "     stays counted as an ask — noise, never a hidden job.")
    print("   BLOCKED is a HAND-WRITTEN mark, not a derivation. Nothing here can tell that a\n"
          "     door was removed; somebody has to notice and write BLOCKED-BY-#<slice> on the\n"
          "     marker line. So this list under-reports: an ask whose door died unnoticed is\n"
          "     still shown as open, which is the safe direction and not a clean bill.")
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
