#!/usr/bin/env python3
"""Find guards that are BROKEN on a correct tree — two different ways.

  A. a needle asserted PRESENT in Sources/ that is not there  (shapes 1-3, #656/#665)
  B. a `\(Self.member)` reference the file cannot compile     (shape 4, #776)
  B2. a plain `Self.member` reference, same fatality           (shape 5, #781)

Both are "the guard is wrong, not the code", and both are invisible to a reading of the diff.

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

SHAPE 4 (#776) — A GUARD THAT CANNOT COMPILE. `TheMPEDimensionsReachNoVoiceTests` dropped
`private static let architecture` when its claim became a directory sweep, and one reference
survived inside a failure message's string INTERPOLATION. The push answered `TEST BUILD FAILED`
and cost a cycle. `Xcode Compile Check` cannot see this — it builds `Sources/` alone — so the
only reader is the pipeline whose conclusion is `failure` on every push anyway (#396).

The shape is narrow on purpose and the narrowness is measured, not asserted. A naive
`\bSelf\.(\w+)` audit over the bundle reports TWENTY files, every one false: `Self.x` also sits
inside NEEDLE STRINGS, which are prose to the compiler. What IS code inside a literal is the
INTERPOLATION `\(Self.x)`, and an ESCAPED one (`\\(Self.x)` — a needle searching production
text for that spelling) is not. Comments are stripped first for the #753 reason: this very
paragraph names `Self.x`, and a scan that read its own documentation would report itself.

VALIDATED against the commit that broke and the commit that repaired: `342f3df` → exactly one
hit, the real one; `7145854` and `d7c1083` → none. Comment-stripping is LOAD-BEARING, measured:
without it the repaired tree reports one false hit, produced by the prose above.

HONEST LIMITS, because a checker that overstates its reach is the thing it is guarding
against:
  · It does NOT cover negative assertions (`XCTAssertFalse(... .contains(X))`), where absence
    is the point. Distinguishing those needs the assertion's polarity, which these two shapes
    give and a bare `.contains` does not.
  · It does NOT cover needles built by interpolation or held in a `let`.
  · Shape 3's receiver set is per FUNCTION and split on `func ` (#666). A closure inside a
    function that re-binds a source-text name to something else would still fool it. Coarse,
    and coarse in the safe direction: an unknown name is skipped, never flagged.
  · A needle present in a DIFFERENT file than the guard intends still counts as present. This
    finds dead needles, not misaimed ones. Worked example from #664: `route: "macOS HAL"` was
    asserted on `latencyBreadcrumb`'s body, had MOVED to `currentSessionLatency`, and is not
    flagged — it is alive in `Sources/`, just not where the guard looks. Its sibling
    `route: routeName` had left `Sources/` entirely and IS flagged.
  · It proves nothing about whether a guard RUNS. See #445.
  · Shape 4 assumes a `Self.` member is declared in the SAME file. A guard that reached a
    static declared in an extension elsewhere would be reported falsely; measured today, no
    file in the bundle does that (0 hits on a correct tree). If one ever does, widen the
    declaration set rather than deleting the check.
  · Shape 5 (#781) covers the plain `Self.gone` that shape 4 cannot see. ⛔ THE BULLET THAT
    STOOD HERE SAID IT COULD NOT BE DONE "without a parser" — one measurement short, and the
    gap cost a near-miss repeat of #776 at #780. `strip_comments` already tracks string state;
    it just kept what it tracked. `strip_strings` blanks it instead, and the two shapes read
    opposite inputs: interpolations live inside strings (shape 4 keeps them), a plain reference
    is code (shape 5 blanks them). The 20-false-alarm figure was true of a naive
    `\bSelf\.(\w+)` (#777), not of the checker's own machinery.
  · Shape 5 OPENED WITH 17 FALSE ALARMS ON A CORRECT TREE, and both causes are worth keeping
    because they are the reason it is safe now — a checker with false alarms is a checker
    nobody reads (#665). (a) A line that OPENS a multi-line literal kept everything before the
    opener unblanked, so an ordinary `code.contains("Self.maxRate ...")` sitting on the same line as
    a triple-quote opener leaked a needle into the scan. (b) The declaration set came from
    `strip_comments(src)`, which is line-based and does not know a Swift multi-line literal, so
    a `/*` inside a failure message swallowed real code,
    measured at `TheLawFileNeverReachesMainByItselfTests.swift:216`, whose
    `private static func pathFilter` line came back EMPTY. The set is read from RAW text now:
    a name that appears only in prose counts as declared, so the checker stays quiet when it is
    unsure. That direction is deliberate — a missed finding costs a cycle, a false one costs
    the checker.
  · The Swift twin of cause (b) is measured and deliberately PINNED, not fixed, in
    `TheStripperDoesNotKnowATripleQuoteTests` — for `Sources/` the current behaviour is the one
    a scanner wants, because the only differing file holds a Metal shader whose `//` are real
    comments. That decision is about `Sources/`; this one is about GUARD files, where the same
    blindness swallows declarations instead of shader comments. Different corpus, opposite
    consequence — do not "unify" them.

VALIDATED, not assumed, once per shape. Shapes 1-2: run against e5956b9 it reports exactly
one hit — the known one — and against the commit that repaired it, zero. Shape 3: run against
5c9f386 it reports exactly one — `TheMeasuredLatencyReachesTheDiagLogTests.swift:308`,
`route: routeName`, the assertion #664 found red on a correct tree — and zero against the
commit that repaired it. A detector that has never found its own known positive is not a
measurement.

Shape 5: driven against the #780 near-miss — `Self.readme` used by one step of a script while
the step that would have declared it crashed before writing the file — it reports exactly that
one reference and nothing else; zero on the repaired tree. Shape 4 was RE-driven after the
declaration set moved to raw text: renaming `ALaneSurvivesAFieldItDoesNotKnowTests`'
`static let timeline` reports its interpolation (line 241) and, via shape 5, its two plain
references (138, 239).
⛔ AND THE FIRST ATTEMPT AT THAT SHAPE-4 RE-DRIVE WAS A NO-OP THAT READ AS A PASS. It renamed
`private static let architecture` in the MPE guard — a declaration #776 had already deleted, so
the only occurrences left were in comments. The mutation changed nothing and the checker
correctly said nothing, which looks identical to "the shape is broken". **A mutation is not
evidence until you have confirmed it LANDED** — grep the mutated file before trusting either
outcome. The same slip, in the same session, also produced a heading-anchor mutation that only
renamed a suffix (`range(of:)` matches a prefix).

Usage:  python3 scripts/dead-needles.py [repo-root]
Exit:   0 = no dead needles · 1 = at least one · 2 = could not look (no Tests/CISmoke)
"""
import glob
import os
import re
import sys

UNWRAP = re.compile(r'XCTUnwrap\([^)]*?range\(of:\s*"((?:[^"\\]|\\.)+)"')

# ⭐ #937 — SHAPE 1 WANTED AN INLINE LITERAL, AND THE SECOND INSTANCE OF THE VERY DEFECT THIS
# SCRIPT WAS WRITTEN FOR HID BEHIND THAT. #650 renamed a logged string; #655/#656 found ONE
# guard broken by it, re-anchored that guard, wrote the lesson into `Tests/CISmoke/CLAUDE.md`
# and built this file. The SAME rename had broken a SECOND guard,
# `TheFailedRestartHandsOverToDegradedTests`, which spelled its needle as
#     let anchor = "Input monitoring: engine restart failed"
#     let start = try XCTUnwrap(code.range(of: anchor), …)
# One `let` of indirection, and this scan saw nothing. It stayed red on a correct tree for
# ELEVEN DAYS, invisible because #396 makes CI/CD report `failure` on every push.
#
# ⚠️ RESOLUTION IS PER FUNCTION, NOT PER FILE — the #666 lesson, which this file already paid
# for once in shape 3: file scope let one binding vouch for a same-named binding in a sibling
# test and produced seven false alarms on the next commit.
#
# ⚠️ AN UNRESOLVABLE NAME IS SKIPPED, NOT REPORTED. `let anchor = someHelper()` is ordinary and
# not a defect, and a checker with false alarms is a checker nobody reads (#665's own argument).
# So this closes the literal-behind-a-`let` hole and nothing wider; a needle assembled by
# interpolation or returned by a call is still invisible here, deliberately.
UNWRAP_VAR = re.compile(r'XCTUnwrap\([^)]*?range\(of:\s*([A-Za-z_]\w*)\s*[,)]')
LOCAL_BIND = re.compile(r'\blet\s+(\w+)\s*=\s*"((?:[^"\\]|\\.)+)"\s*$', re.MULTILINE)
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


def decode_needle(literal):
    """The Swift literal's VALUE, or None when it carries an escape this scan cannot decode.

    ⛔ #937 — WRITTEN AFTER MY OWN NEW SHAPE PRODUCED A FALSE ALARM ON ITS FIRST RUN.
    `CopyNamesTheLiveControlTests` binds `let door = "\n            quickDoorRow\n"`; the old
    two-`replace` decode left the backslash-n as two characters, which of course is not in
    `Sources/`, and the tool reported a correct guard as dead. That is the exact failure #665
    argued against — a checker with false alarms is a checker nobody reads.

    Returning None (skip) rather than decoding `\n` is deliberate and coarse in the SAFE
    direction, the #666 rule this file already follows: a needle with real newlines would have
    to match the source's exact indentation, so a decoded comparison is as likely to be wrong as
    right, and being silently wrong is worse than being silently absent.

    Shape 1 shares this decode on purpose. It had the identical latent hazard and had simply
    never met such a needle; leaving one path fixed and its twin broken is how #937 happened in
    the first place (#456 — the repair goes in EVERY home).
    """
    value = literal.replace('\\"', '"').replace("\\\\", "\\")
    return None if "\\" in value else value

# Shape 4 (#776). The capture keeps the backslash run so an ESCAPED interpolation — a needle
# searching production text for the literal `\(Self.x)` — can be told from a real one.
SELF_INTERPOLATION = re.compile(r"(\\*)\(Self\.(\w+)")
STATIC_MEMBER = re.compile(r"static\s+(?:let|var|func)\s+(\w+)")
# Shape 5 (#781). The PLAIN reference — `rawFile(Self.readme)` — on text whose string literals
# have been blanked, so the same spelling inside a needle cannot reach it.
SELF_PLAIN = re.compile(r"(?<![\w.])Self\.(\w+)")


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


def strip_strings(text):
    """Blank the CONTENTS of Swift string literals, keeping line structure.

    Shape 5 (#781) needs the opposite input from shape 4. An interpolation lives INSIDE a
    string, so shape 4 must keep strings; a plain `Self.gone` reference is code, and the
    identical text inside a needle is prose. Telling them apart is exactly what this does.

    ⛔ THE HEADER USED TO SAY THIS COULD NOT BE DONE "without a parser", and that was one
    measurement short. `strip_comments` above ALREADY tracks `in_string` — it simply keeps
    what it tracks. The only genuinely missing piece was the multi-line triple-quote block,
    a handful of lines because it cannot nest. The claim was true about a naive
    `\bSelf\.(\w+)` (#777 measured 20 false alarms on a correct tree); it was not true about
    the checker's own machinery, and the gap cost a near-miss repeat of #776 at #780.

    ⚠️ Interpolations are blanked along with the rest of the literal. That is correct here and
    NOT a loss: shape 4 owns them, on the un-blanked text, and reports them separately.
    """
    out = []
    in_multiline = False
    for raw in text.split("\n"):
        if in_multiline:
            if '"""' in raw:
                in_multiline = False
                out.append(" " * len(raw))
            else:
                out.append(" " * len(raw))
            continue
        head = None
        if '"""' in raw and raw.count('"""') % 2 == 1:
            # ⛔ THE FIRST VERSION KEPT `raw[:index]` VERBATIM and that produced 2 of the 17
            # false alarms this shape opened with: `code.contains("Self.maxRate ..."), """`
            # has an ORDINARY literal before the opener, and leaving it unblanked is exactly
            # the confusion this function exists to remove. Blank the head, keep the opener.
            in_multiline = True
            raw, head = raw[:raw.index('"""')], '"""'
        line, i, n, in_string = [], 0, len(raw), False
        while i < n:
            c = raw[i]
            nxt = i + 1
            if in_string:
                if c == "\\" and nxt < n:
                    line.append("  ")
                    i = nxt + 1
                    continue
                if c == '"':
                    in_string = False
                    line.append(c)
                else:
                    line.append(" ")
                i = nxt
                continue
            if c == '"':
                in_string = True
            line.append(c)
            i = nxt
        out.append("".join(line) + (head or ""))
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
    uncompilable = []
    for guard in guards:
        with open(guard, encoding="utf-8") as handle:
            src = handle.read()
        for match in list(UNWRAP.finditer(src)) + list(POSITIVE_COUNT.finditer(src)):
            needle = decode_needle(match.group(1))
            if needle is None or len(needle) < MIN_NEEDLE:
                continue
            if needle not in corpus:
                line = src[:match.start()].count("\n") + 1
                dead.append((os.path.relpath(guard, root), line, needle))

        # Shape 4 (#776). Comments stripped first (#753 — this file's own header names the
        # spelling it looks for). Only a single-backslash interpolation is code.
        code_for_self = strip_comments(src)
        # ⛔ THE DECLARATION SET IS READ FROM THE RAW FILE, NOT FROM `strip_comments(src)`, and
        # that is the OTHER 15 of the 17 false alarms shape 5 opened with. `strip_comments` is
        # line-based and does not know a Swift `"""` block (the Swift twin of this blindness is
        # measured and deliberately PINNED in `TheStripperDoesNotKnowATripleQuoteTests`), so a
        # `/*` inside a failure message opens a block comment that swallows real code until the
        # next `*/` — including, measured, `private static func pathFilter` at
        # `TheLawFileNeverReachesMainByItselfTests.swift:216`, whose whole line came back empty.
        # A swallowed line costs shape 4 only a missed finding (safe); it costs shape 5 a FALSE
        # ONE (unsafe), because a missing declaration looks exactly like a deleted member.
        # Reading declarations from raw text errs the other way: a name that appears only in
        # prose counts as declared, so the checker stays quiet when it is unsure (#665).
        declared = set(STATIC_MEMBER.findall(src))
        for match in SELF_INTERPOLATION.finditer(code_for_self):
            if len(match.group(1)) != 1:
                continue                      # 0 = not an interpolation, 2 = escaped needle
            name = match.group(2)
            if name in declared:
                continue
            line = code_for_self[:match.start()].count("\n") + 1
            uncompilable.append((os.path.relpath(guard, root), line, name))

        # Shape 5 (#781). Same declaration set, opposite input: strings BLANKED, so a plain
        # `Self.gone` in ordinary code is visible and the identical text inside a needle is
        # not. This is the spelling that slipped past shape 4 at #780 — a static declared by a
        # script step that crashed before writing the file, and used by a later step.
        code_no_strings = strip_strings(code_for_self)
        for match in SELF_PLAIN.finditer(code_no_strings):
            name = match.group(1)
            if name in declared:
                continue
            line = code_no_strings[:match.start()].count("\n") + 1
            entry = (os.path.relpath(guard, root), line, name)
            if entry not in uncompilable:
                uncompilable.append(entry)

        # Shape 1b (#937): the needle is bound to a local `let` and handed to `range(of:)` by
        # name. Same per-function scope as shape 3, same comment-stripping — a ⛔ block quoting
        # a retracted needle must not be read as a live binding (#753).
        for chunk in re.split(r"\n    (?=(?:private |public |internal )?(?:static )?func )",
                              strip_comments(src)):
            bindings = {m.group(1): m.group(2) for m in LOCAL_BIND.finditer(chunk)}
            if not bindings:
                continue
            for match in UNWRAP_VAR.finditer(chunk):
                needle = bindings.get(match.group(1))
                if needle is None:
                    continue                      # computed or out of scope — see the note above
                needle = decode_needle(needle)
                if needle is None or len(needle) < MIN_NEEDLE:
                    continue
                if needle not in corpus:
                    offset = strip_comments(src).find(chunk)
                    line = strip_comments(src)[:offset + match.start()].count("\n") + 1
                    dead.append((os.path.relpath(guard, root), line, needle))

        # Shape 3 (#665). Comments are stripped FIRST here: this repo's guards quote their own
        # retracted needles in ⛔ blocks, and a scan that read those would report a finding
        # against a file's own history.
        guard_code = strip_comments(src)
        paths = set(SOURCE_PATH.findall(guard_code))
        if not paths or any(not p.startswith("Sources/") for p in paths):
            continue
        # ⛔ #666 — THE RECEIVER SET IS PER FUNCTION, NOT PER FILE, AND #665 GOT THAT WRONG.
        # Shipped with file scope, this produced SEVEN false positives on the very next
        # commit. The cause is ordinary Swift style: one test binds
        # `let line = Self.body(of: "static func latencyLine", in: config)` — source text —
        # while four sibling tests bind `let line = AudioConfiguration.latencyLine(...)` — a
        # PRODUCED string. File scope let the first `line` vouch for all the others, and every
        # needle asserted against the produced line ("floor=9.0ms", "sr=48000") was reported
        # as absent from Sources/, which is exactly what it is supposed to be.
        # ⭐ The finding matters more than the fix: #665's own argument was that a checker with
        # false alarms is a checker nobody reads, and it shipped with a scoping bug that makes
        # them. Splitting on `func ` is coarse — a nested closure re-binding the same name
        # would still confuse it — and coarse in the SAFE direction, because a name unknown to
        # the enclosing function is simply skipped.
        for chunk in re.split(r"\n    (?=(?:private |public |internal )?(?:static )?func )",
                              guard_code):
            receivers = {m.group(1) for m in SOURCE_BIND.finditer(chunk)}
            if not receivers:
                continue
            for match in POSITIVE_CONTAINS.finditer(chunk):
                receiver = match.group(1)
                needle = match.group(2).replace('\\"', '"').replace("\\\\", "\\")
                if len(needle) < MIN_NEEDLE or "\\(" in needle or receiver not in receivers:
                    continue
                if needle not in corpus:
                    offset = guard_code.find(chunk)
                    line = guard_code[:offset + match.start()].count("\n") + 1
                    dead.append((os.path.relpath(guard, root), line, needle))

    if not dead and not uncompilable:
        print(f"dead-needles: OK — {len(guards)} guard file(s), no dead needle, "
              "no unresolvable `Self.` reference")
        return 0
    if dead:
        print(f"dead-needles: {len(dead)} needle(s) asserted present but ABSENT from Sources/:")
        for path, line, needle in dead:
            print(f"  {path}:{line}  {needle!r}")
        print("\nEach is a guard that FAILS on a correct tree. Re-anchor it on a literal that")
        print("exists, and assert that literal's uniqueness while you are there (#408).")
    if uncompilable:
        print(f"dead-needles: {len(uncompilable)} `Self.x` reference(s) with no matching "
              "`static let/var/func` in the same file:")
        for path, line, name in uncompilable:
            print(f"  {path}:{line}  Self.{name}")
        print("\nEach is a guard that CANNOT COMPILE — `TEST BUILD FAILED`, and `Xcode Compile")
        print("Check` will still say success because it builds Sources/ alone. Usually a member")
        print("was deleted and a failure message kept naming it (#776): grep the USAGES, not")
        print("just the declaration, whenever you remove one.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
