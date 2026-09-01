#!/usr/bin/env python3
"""Find guards that are BROKEN on a correct tree — two different ways.

  A. a needle asserted PRESENT in Sources/ that is not there  (shapes 1-3, #656/#665)
  B. a `\(Self.member)` reference the file cannot compile     (shape 4, #776)
  B2. a plain `Self.member` reference, same fatality           (shape 5, #781)
  A2. the same fatality written as a `guard`, not `XCTUnwrap`  (shape 6, #960)

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

WHAT IT CHECKS. Four assertion shapes whose needle must exist in production code:
    XCTUnwrap(<x>.range(of: "NEEDLE") ...)
    guard let <x> = <recv>.range(of: "NEEDLE") else { ... XCTFail ... }   — #960, and only
        in a guard file that names at least one path and ONLY `Sources/` ones. The `XCTFail`
        is what makes the miss FATAL; `else { return }` is a legitimate skip and is not
        reported. The needle may be inline or bound to a `let`, per-function first and then
        class-level — the repaired form of its own known positive uses the class-level one.
    XCTAssertEqual/GreaterThan[OrEqual](codeOccurrences(of: "NEEDLE" ...), N)   with N >= 1
    XCTAssertTrue(<recv>.contains("NEEDLE"))          — #665, and only where <recv> is
        PROVABLY source text, by EITHER route (#944): the `Self.`-qualified bind
        (`Self.codeText/read/body/rawSource/source`) in a file that names ONLY `Sources/`
        paths, OR the plain bind through a helper of those names that this same file defines
        and that provably returns `SourceText.codeOnly(…)`, whose ARGUMENT resolves to a
        `Sources/` path. Either way the needle must carry no surviving escape. ⛔ THAT LAST CLAUSE SAID "no interpolation"
        until #941/#941b: the live rule is broader — shape 3 shares `decode_needle`
        now, so ANY needle with an undecodable backslash escape (newline, tab, unicode) is
        skipped, not just an interpolation (a unicode escape included — spelling one
        out here would break this very docstring, which is not raw). Quieter, never
        louder.
Comments in Sources/ are stripped first, so a needle that survives only inside prose about
itself does NOT count as present — that is the `EchoelModalBank` trap in executable form.

⛔ WHY THE THIRD SHAPE IS SO NARROW, because a checker that overstates its reach is the thing
it guards against. #664 was a guard red on a correct tree for exactly this shape, and #663's
commit body cited THIS SCRIPT as independent confirmation while it extracted zero needles
from the file in question. The obvious widening — every `XCTAssertTrue(x.contains("N"))` —
was measured before it was written: 785 such needles in the bundle, 86 flagged on a CORRECT
tree. The receiver of a `.contains` may be source text, a produced string, a doc file, or a
file under `Tests/`; polarity alone does not say which. The provenance test cut 785 to 26 —
3 % reach, stated rather than hidden, because the alternative was 86 false alarms, which is
how a checker gets ignored (the mechanism that made `continue-on-error` invisible).
⭐ #944 RAISED THAT REACH BY ANSWERING THE PROVENANCE QUESTION BETTER, NOT BY RELAXING IT:
**248 of 1 071 needles today, 23 %**, with 0 findings on two correct trees and exactly 1 on the
tree carrying the known defect. Widening the REGEX would have bought reach at the cost of false
alarms; widening the PROOF buys it at no cost, and the two new gates (`stripping_helpers`,
`names_a_source`) are what does the proving. Both numbers here are dates — re-derive rather
than quote (`Tests/CISmoke/CLAUDE.md` §0).

SHAPE 4 (#776) — A GUARD THAT CANNOT COMPILE. `TheMPEInputHasNoZonesTests` dropped
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
import contextlib
import glob
import io
import os
import re
import sys
import tempfile

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
#
# ⛔ #941 — THE OBVIOUS WIDENING WAS PROTOTYPED, MEASURED, AND DELIBERATELY NOT SHIPPED, and
# the measurement is written down so nobody re-derives it. `SOURCE_BIND` recognises only the
# `Self.`-qualified spellings; the bundle binds source text **377 times across 99 files** in the
# plain instance form (`let code = try source("Sources/…")`) against 60 in the recognised form,
# so ~86 % of the binding sites are invisible to this shape. ⛔ THOSE TWO NUMBERS READ 392/103
# FOR ONE COMMIT AND WERE NOT REPRODUCIBLE (#941b) — a looser hand-grep over several spellings,
# summed wrong. The derived share survived (86.3 % vs 86.7 %), which is exactly why a share is
# safer to quote than a count. Re-derive rather than trust:
#
#     python3 - <<'EOF'
#     import re, glob
#     P = re.compile(r'\b(?:let|var)\s+[A-Za-z_]\w*\s*=\s*(?:try\s+)?(?:XCTUnwrap\()?\s*'
#                    r'(?:codeText|read|body|rawSource|source)\(')
#     n = sum(len(P.findall(open(f, encoding="utf-8").read()))
#             for f in glob.glob("Tests/CISmoke/*.swift"))
#     print(n)
#     EOF
#
# Widening the regex to accept the plain form is one line, and it surfaced ELEVEN candidates
# BEFORE the escape repair below and NINE after it — a reader re-running the widening on the
# shipped tree gets 9, and a recipe that answers 9 where the prose promises 11 reads as a
# contradiction (the `EchoelModalBank` shape the root law file warns about). Every inspected one
# is a FALSE ALARM, in four distinct kinds:
#
#   · RAW vs STRIPPED. `AGrainCannotClickOrRunAwayTests` binds `chainRaw` from `rawSource` and
#     asserts a needle
#     that lives in a COMMENT in `EchoelFXChain.swift`. This script's corpus is comment-blanked,
#     so it cannot see it. Same for `EveryReachableRowStatesItsGridTests`, whose own `source()`
#     helper does not strip at all — the guard asserts on a comment ON PURPOSE.
#   · THE RECEIVER IS NOT A `Sources/` FILE. `BioApplyRateIsTheDedupedRateTests` binds
#     `CLAUDE.md`; `OneDefinitionOfCodeNotProseTests` reads files under `Tests/`. The FILE gate
#     above passes them because their string literals name only `Sources/` paths.
#   · TRANSFORMED TEXT. `UnmeasuredPulseIsNotZeroTests` binds `squashed` — source with all
#     whitespace removed — and asserts `"guardletv,v.isFiniteelse{returnd}"`.
#   · ESCAPES. The `\n` needles that exposed the decoder gap repaired above.
#
# The common cause, and it is why no regex fixes this: **a receiver NAME does not say what the
# text IS.** Raw or stripped, whole file or squashed, `Sources/` or a Markdown ledger — the
# script would have to resolve the helper, and the helpers differ per file by design. Per #665's
# own rule (a checker with false alarms is a checker nobody reads), the honest output is this
# paragraph rather than a widening that is wrong eleven ways on a correct tree.
SOURCE_PATH = re.compile(
    r'"((?:Sources|Tests|docs|scripts|fastlane|memory|scratchpads|ContentPipeline)/[^"]*)"')
SOURCE_BIND = re.compile(
    r'\blet\s+([A-Za-z_]\w*)\s*=\s*(?:try\s+)?(?:XCTUnwrap\()?\s*'
    r'Self\.(?:codeText|read|body|rawSource|source)\b')
POSITIVE_CONTAINS = re.compile(
    r'XCTAssertTrue\(\s*(?:try )?([A-Za-z_]\w*)\.contains\(\s*"((?:[^"\\]|\\.)+)"\s*\)')

# ⭐ #944 — THE WIDENING #941 MEASURED AND DECLINED, SHIPPED, BECAUSE THE EVIDENCE CHANGED AND
# THE GATE CHANGED WITH IT. #941's argument stands as written: widening `SOURCE_BIND` to the
# plain instance form is one line, surfaced nine candidates on a correct tree, and every one was
# a false alarm. What it did NOT have was a true positive, so the trade was all cost.
# #943 supplied one. `TheMPEInputHasNoZonesTests` asserted the literal
# `private var heldByController = false` while the same slice deleted that declaration —
# `grep -c` on `BioReactiveSynthVoice.swift` gives 1 at `febecdb`, 0 at `25d34dc`, so the guard
# was certainly red on the tree that shipped — and the CI/CD run for it reported 0 failures
# (`Tests/CISmoke/CLAUDE.md` §5, the second known-bad control). This shape is exactly the shape
# that missed it: the bind is `let code = try source(Self.voice)`, plain, not `Self.source`.
#
# ⚠️ WHAT MAKES IT SAFE IS NOT THE WIDER REGEX BUT THE TWO GATES BESIDE IT, each aimed at one
# of #941's measured false-alarm kinds:
#   · `stripping_helpers` — accept a helper NAME only when that helper, defined in this same
#     guard file, provably returns `SourceText.codeOnly(…)`. Kind 1 (raw vs stripped: a needle
#     that lives in a COMMENT, asserted through `rawSource`) and kind 3 (transformed text: a
#     `squashed` receiver with whitespace removed) cannot enter, by construction.
#   · `names_a_source` — the bind's ARGUMENT must provably name a `Sources/` path: a literal, or
#     a `static let` in this file that is one. Kind 2 (the receiver is a `Tests/` file or
#     `CLAUDE.md`) cannot enter. A loop variable resolves to nothing and is SKIPPED, never
#     guessed (#665: quiet when unsure).
#
# ⛔ AND THE FIRST DRAFT HAD ONLY THE FIRST GATE, WHICH MEASURED GREEN FOR A REASON THAT WAS
# LUCK. `OneDefinitionOfCodeNotProseTests` binds `let code = try read(name)` over `Tests/`
# files and asserts `code.contains("SourceText.codeOnly")`; that literal happens to occur ONCE
# in `Sources/`, in `Video/CameraAnalyzer.swift`, so the corpus check passed by accident. Delete
# that one incidental line and the tool reports a perfectly correct guard as dead. A green whose
# cause you have not read is not a measurement.
#
# MEASURED BY RUNNING THIS SCRIPT — not by a transcription of it — over three checked-out trees:
# **0** findings on the worktree, **0** on `febecdb`, and **exactly 1** on `25d34dc`, at
# `TheMPEInputHasNoZonesTests.swift:578`, the line the reviewer named. A detector that has never
# found its own known positive is not a measurement; one validated only against its known
# NEGATIVES is not either.
# ⛔ The transcription said the same thing one gate too early and was wrong: see the third gate,
# `allow_legacy`, in `source_receivers` — the file-level `SOURCE_PATH` proxy was still SKIPPING
# the whole guard, so the shipped tool said OK on the tree the probe called red.
# The union with `SOURCE_BIND` is deliberate: for a file that passes the legacy proxy this is
# strictly ADDITIVE, so no finding the old form produced can disappear behind the new gates.
HELPER_DEF = re.compile(
    r'(?:private |public |internal )?func\s+(codeText|read|body|rawSource|source)\s*\(')
PATH_CONST = re.compile(r'static\s+let\s+(\w+)\s*=\s*"([^"]*)"')


def stripping_helpers(code):
    """Names of source-reading helpers in THIS file whose body calls `SourceText.codeOnly(`.

    Brace-matched rather than line-windowed (`Tests/CISmoke/CLAUDE.md` §2, #408): this repo
    writes 30-40-line doc blocks, so any fixed window is unsound by construction.
    """
    found = set()
    for match in HELPER_DEF.finditer(code):
        opening = code.find("{", match.end())
        if opening < 0:
            continue
        depth, i = 0, opening
        while i < len(code):
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if "SourceText.codeOnly(" in code[opening:i]:
            found.add(match.group(1))
    return found


def source_receivers(chunk, helpers, consts, allow_legacy):
    """Local names in `chunk` that hold comment-stripped text of a `Sources/` file.

    The union of the `Self.`-qualified form recognised since #665 and the #944 plain form.

    `allow_legacy` is the FILE gate, and it applies only to the `Self.`-qualified half. That
    half never looks at its argument, so #665 approximated the question "is this receiver a
    `Sources/` file?" with the file-wide one "does this guard name ONLY `Sources/` paths?".
    The #944 half answers the real question per receiver, so it does not need the proxy — and
    must not be subject to it.

    ⛔ THAT PROXY IS WHY THE FIRST #944 DRAFT STILL MISSED ITS OWN KNOWN POSITIVE, and only
    running the real tool showed it. `TheMPEInputHasNoZonesTests` reads `docs/*.html` for the
    website claims, so `SOURCE_PATH` sees a non-`Sources/` path and `main()` skipped the WHOLE
    file — including the `Sources/`-bound receiver carrying the dead needle. My probe had
    reimplemented shape 3 without that gate and reported "1 finding on `25d34dc`"; the shipped
    tool on the same tree said OK. **A transcription that omits a gate is not a measurement of
    the tool** — the same defect class as grading a guard against a tree you did not build.
    """
    names = {m.group(1) for m in SOURCE_BIND.finditer(chunk)} if allow_legacy else set()
    if not helpers:
        return names
    binder = re.compile(
        r'\blet\s+([A-Za-z_]\w*)\s*=\s*(?:try\s+)?(?:XCTUnwrap\()?\s*'
        r'(?:Self\.)?(?:%s)\(\s*(?:Self\.)?([A-Za-z_"][^),]*)' % "|".join(sorted(helpers)))
    for match in binder.finditer(chunk):
        argument = match.group(2).strip()
        if argument.startswith('"'):
            resolved = argument[1:]
        else:
            resolved = consts.get(argument, "")
        if resolved.startswith("Sources/"):
            names.add(match.group(1))
    return names

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


# ⛔ #941b — THE SPLIT WAS SPELLED THREE TIMES, byte-identical today and silently divergent
# tomorrow (#416). Worse, the selftest performed its OWN split, so the mutation it claimed to
# pin — `main()` reverting shape 3 to FILE scope, the #666 defect — left it GREEN. One helper,
# three call sites, and the selftest now hands it the UNSPLIT text so the composition is what
# gets driven (#914, the same lesson this slice applied to case 1 and missed in case 2).
FUNC_SPLIT = re.compile(r"\n    (?=(?:private |public |internal )?(?:static )?func )")


def function_chunks(code):
    """The guard file's text, split at each top-level `func`. Coarse on purpose (#666): a
    nested closure re-binding a name still confuses it, and it is coarse in the SAFE
    direction, because a name unknown to the enclosing function is simply skipped."""
    return FUNC_SPLIT.split(code)


def shape3_findings(chunk, corpus, helpers, consts, allow_legacy):
    """Shape 3 for ONE function chunk: yield `(match, needle)` for each needle asserted
    present that the corpus does not contain.

    `helpers` / `consts` are the file's #944 widening context and are REQUIRED, not defaulted:
    a defaulted argument that no call site writes appears in no diff (#431/#440/#443), and both
    call sites here — `main()` and `selftest()` — must state which one they are driving. Pass
    `set()`/`{}` for the pre-#944 behaviour exactly.

    ⭐ #941 EXTRACTED THIS SO THE SELFTEST CAN DRIVE THE COMPOSITION, not the parts. The first
    draft of that selftest checked `decode_needle` on literals — which was already correct — and
    would therefore have stayed GREEN through the exact mutation it was written for (shape 3
    decoding escapes inline instead of calling it). That is the #914 lesson one file over: what
    bites is the composition, and a checker that cannot fail on its own mutation is not a
    checker.
    """
    receivers = source_receivers(chunk, helpers, consts, allow_legacy)
    if not receivers:
        return
    for match in POSITIVE_CONTAINS.finditer(chunk):
        if match.group(1) not in receivers:
            continue
        # ⛔ #941 — THIS DECODED ESCAPES INLINE INSTEAD OF CALLING `decode_needle`, which is the
        # #937 pattern the decoder was written to end: one form repaired, its twin left broken.
        # `decode_needle`'s own docstring says "Shape 1 shares this decode on purpose" and shape
        # 3 did not — a claim of coverage the code did not have, in the tool this repo reaches
        # for when a guard rots.
        #
        # It was LATENT, not live: shape 3 finds nothing on today's tree. The demonstration came
        # from the binder-widening experiment recorded above —
        # `TheAutotuneCharacterIsDerivedNotStoredTests` asserts
        # `engine.contains("var voiceTuneStrength: Float = 1\n")`, whose `\n` the old
        # two-`replace` decode left as two characters. That can never be in `Sources/`, so the
        # moment a RECOGNISED binding met such a needle the tool would have reported a correct
        # guard as dead — the #665 false alarm this file argues against in its own comments.
        needle = decode_needle(match.group(2))
        # ⛔ `or "\\(" in needle` STOOD HERE AND IS DEAD (#941b): `decode_needle` already
        # returns None for anything with a surviving backslash, and `\\(` is one. Removed
        # rather than kept as documentation — a live-looking condition that can never fire is
        # the kind of line a later reader trusts.
        if needle is None or len(needle) < MIN_NEEDLE:
            continue
        if needle not in corpus:
            yield match, needle


# ⭐ #960 — SHAPE 6: `guard let x = <recv>.range(of: "NEEDLE") else { XCTFail(…); return }`.
#
# THE KNOWN POSITIVE THIS WAS BUILT AGAINST, and it is this script's own blind spot rather
# than a hypothetical. `TheMonitorSurgeryQuietsTheEngineTests` anchored THREE claims on
# `guard isInputMonitoring else { return true }`. #913 (`860e400`) removed that literal when it
# gave the OFF exit its own `off SKIPPED` breadcrumb. Bisected: present at HEAD~100, absent
# from HEAD~99 on. All three claims then hit their `XCTFail` and returned, on a CORRECT tree,
# in the BLOCKING bundle, for 99 commits — invisible because #396 makes CI/CD report `failure`
# on every push, so a genuinely red guard looks exactly like the host dying.
#
# Shapes 1 and 2 could not see it: they read `XCTUnwrap(… .range(of: …))`. This is the same
# fatality written as a `guard`. That is the #937 pattern for the THIRD time in this file — a
# rename breaks one guard, the fix lands, and a sibling in a different SPELLING stays red.
#
# ⚠️ TWO GATES, AND THE MEASUREMENT FOR EACH, because a checker that overstates its reach is
# the thing this file guards against:
#   · **`XCTFail` inside the else block** — the FATALITY argument. `guard let … else { return }`
#     without it is a legitimate skip, not a failure, and reporting it would be a false alarm.
#     Measured on today's tree: PROPHYLACTIC, not load-bearing — 116 sites without the gate vs
#     76 with it, and the verdicts are identical (3 dead on `1ae5c5f`, 0 on the repair). It is
#     kept because it is the ARGUMENT, not because it changes today's answer. Said plainly
#     rather than implied, per this file's own rule about measuring a gate before claiming it.
#   · **the file names ONLY `Sources/` paths, and names at least one** — `allow_legacy`,
#     reused, not re-spelled (#416). ⛔ THE NON-EMPTY HALF IS NOT DECORATION AND THE PROTOTYPE
#     PROVED IT: `TheDecisionLogIsMachineReadableTests` reads `review.sh` and its needle
#     `SKIP_STATUS = {` is absent from `Sources/` — a false alarm. That file yields an EMPTY
#     `SOURCE_PATH` set, so a bare `all(...)` would be VACUOUSLY TRUE and let it through
#     (#926, the same trap in a different file). With both halves: 1 false alarm becomes 0.
#
# ⚠️ TWO REACH GAPS OF SHAPE 6, MEASURED (#962 review) AND NAMED HERE RATHER THAN LEFT TO BE
# REDISCOVERED. Both are misses, never false alarms, and widening either adds ZERO findings on
# today's tree — pure reach at no cost, which is why they are registered and not rushed:
#   · COMPOUND GUARDS, 2nd clause onward — 45 needles across 25 files. Both regexes anchor at
#     `\bguard`, so one statement yields at most one needle; `guard let a = …, let b = …` hides
#     everything after the first (live: `TheWayOutSurvivesRotationTests`,
#     `ASwiftUIBodyStaysUnderTheBuilderOverloadsTests`, `AutoModeStartsOffAndOwnsNoTempoTests`).
#   · FATAL-BY-`throw` — 58 sites. `guard_else_fails` requires `XCTFail`, but in a `throws` test
#     `throw AnchorMissing` is just as fatal (live: `ALaneSurvivesAFieldItDoesNotKnowTests`,
#     `RMSSDReadsOnlyAdjacentBeatsTests`). The gate's stated purpose — "exclude a legitimate
#     skip" — does not describe those: a `throw` is not a `return`.
#
# ⭐ #963 — THE BRACE-IN-STRING DEFECT #962 REGISTERED IS FIXED. `guard_else_fails` used to
# brace-match over a chunk with COMMENTS stripped but STRINGS intact, so a brace inside a
# failure message miscounted in both directions (see its own docstring). It now walks
# `code_positions`, which skips string literals in place.
#
# ⛔ AND THE REPAIR #962 WROTE DOWN HERE — "match over `strip_strings(chunk)` while reporting
# offsets on the original" — WOULD HAVE BEEN A SILENT MIS-INDEX. `guard_else_fails` receives
# `after` as an offset into the ORIGINAL chunk, and `strip_strings` is NOT length-preserving:
# measured across 418 files, 21 change length (`SourceText.swift` 16518 → 16364,
# `AudioEngine.swift` 253654 → 253630), because its triple-quote head case rewrites the line.
# It would have pointed the walk at the wrong character in exactly the files that carry the
# triple-quoted messages this shape must read — and nothing would have gone red, because the
# tree's verdicts do not change. A named repair in a registered defect deserves the same
# measurement as the defect: I wrote that sentence from the shape of the function, not from
# running it.
#
# ⚠️ THE VAR-BOUND FORM IS COVERED TOO, AND NOT COVERING IT WOULD HAVE LOST THE KNOWN POSITIVE
# THE MOMENT IT WAS REPAIRED: #959b's fix hoists the anchor to a type-level
# `private let offAnchor = "…"`, so the repaired file uses `range(of: offAnchor)`. A shape that
# only read inline literals would go quiet on exactly the file it was written for — passing
# forever for the wrong reason (§2, the #367 mirror case). The fallback dict is therefore
# consulted after the per-function ones, per-function winning (#666).
#
# ⛔ #962 — IT IS A FILE-SCOPE FALLBACK, NOT A CLASS-LEVEL ONE, and #960 wrote "class-level" in
# two places. `LOCAL_BIND` matches `let name = "literal"` at ANY indent, so `main`'s dict holds
# every function-local binding in the file as well, last write winning — the exact scope defect
# that cost seven false alarms at #666, one level up. It does not bite today (all five live
# fallback resolutions are the genuine type-level `private let offAnchor`/`offTerminator` in
# `TheMonitorSurgeryQuietsTheEngineTests`), but the collision material is there: eleven names in
# the bundle are bound to more than one distinct literal inside a single file — `anchor` has
# four values in `TapTargetFloorTests`, `message` twenty-five in
# `SignatureIsThePersonNotTheMomentTests`. A `guard let r = code.range(of: anchor)` in a
# function of such a file that does not bind `anchor` locally resolves against an arbitrary
# sibling. Restricting the fallback to type-level declarations is the repair; until then the
# comment says what the code does.
GUARD_LIT = re.compile(
    r'\bguard\s+let\s+\w+\s*=\s*[A-Za-z_][\w.]*\.range\(of:\s*"((?:[^"\\]|\\.)+)"')
GUARD_VAR = re.compile(
    r'\bguard\s+let\s+\w+\s*=\s*[A-Za-z_][\w.]*\.range\(of:\s*([A-Za-z_]\w*)\s*[,)]')


def code_positions(chunk, start=0):
    """Yield every index from `start` that is OUTSIDE a Swift string literal.

    ⭐ #963 — WHY THIS EXISTS INSTEAD OF `strip_strings(chunk)`, which is the obvious repair and
    which SILENTLY MIS-INDEXES. `guard_else_fails` receives `after` as an offset into the
    ORIGINAL chunk (`match.end()`), so any blanking pass it walks over must preserve length
    exactly. `strip_strings` does not: measured across 418 files, **21 change length** (e.g.
    `SourceText.swift` 16518 → 16364, `AudioEngine.swift` 253654 → 253630), because its
    triple-quote head case rewrites `raw[:index] + '\"\"\"'`. Handing it a caller's offset
    would point the brace walk at the wrong character in exactly the files that contain the
    triple-quoted messages this shape has to read. Skipping in place needs no offset map.

    ⚠️ Comments are already gone by the time shape 6 runs (`main` calls `strip_comments` before
    `function_chunks`), so strings are the only remaining hazard here.
    """
    i, n = start, len(chunk)
    in_str = in_ml = False
    while i < n:
        if in_ml:
            if chunk.startswith('\"\"\"', i):
                in_ml = False
                i += 3
            else:
                i += 1
            continue
        if in_str:
            if chunk[i] == "\\" and i + 1 < n:
                i += 2
                continue
            if chunk[i] == '"':
                in_str = False
            i += 1
            continue
        if chunk.startswith('\"\"\"', i):
            in_ml = True
            i += 3
            continue
        if chunk[i] == '"':
            in_str = True
            i += 1
            continue
        yield i
        i += 1


def guard_else_fails(chunk, after):
    """True when the `guard`'s else block, brace-matched from `after`, contains `XCTFail`.

    Brace-matched rather than line-windowed (§2, #408): this repo writes 30-40-line doc blocks
    and the else body of these guards routinely carries a multi-line failure message.

    ⛔ #963 — IT COUNTED BRACES INSIDE STRING LITERALS, BOTH ERROR DIRECTIONS DEMONSTRATED.
    An unbalanced `{` in a NON-fatal else ran the window to the end of the function and picked
    up an unrelated `XCTFail` later in it — a legitimate `else { return }` skip reported as a
    dead needle, the false-alarm class #665 says kills a checker. An unbalanced `}` in a FATAL
    else closed the window early and lost the finding. Not hypothetical:
    `ASwiftUIBodyStaysUnderTheBuilderOverloadsTests` quotes `struct EchoelFXView: View {` and
    `var body: some View {` in ONE message — two unbalanced `{` — and the verdict there was
    right BY ACCIDENT, because that else really is fatal. Guards in this repo quote Swift at
    each other constantly, so this was going to bite.

    ⚠️ A genuinely unbalanced brace in CODE (a truncated chunk) still runs to the end of the
    chunk. That is the honest remainder: this function knows strings, not syntax errors.
    """
    opening = -1
    for i in code_positions(chunk, after):
        if chunk.startswith("else {", i):
            opening = i
            break
    if opening < 0:
        return False
    depth, end = 0, len(chunk)
    for i in code_positions(chunk, opening + len("else ")):
        if chunk[i] == "{":
            depth += 1
        elif chunk[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    # `XCTFail` is read on CODE positions too: a failure message that quotes the word
    # `XCTFail` at another guard is prose, and reading it would make a skip look fatal.
    body = "".join(chunk[i] for i in code_positions(chunk, opening) if i < end)
    return "XCTFail" in body


def shape6_findings(chunk, corpus, class_binds):
    """(match, needle) for every fatal `guard let … range(of: …) else { XCTFail }` gone dead.

    Pure, and driven by the selftest as a COMPOSITION rather than piecewise — the #914/#941
    lesson this file has now paid for twice: a selftest that exercises the regexes and the
    decoder separately passes while the code that JOINS them is the broken part.
    """
    binds = {m.group(1): m.group(2) for m in LOCAL_BIND.finditer(chunk)}
    out = []
    for match in GUARD_LIT.finditer(chunk):
        if not guard_else_fails(chunk, match.end()):
            continue
        needle = decode_needle(match.group(1))
        if needle is None or len(needle) < MIN_NEEDLE:
            continue
        if needle not in corpus:
            out.append((match, needle))
    for match in GUARD_VAR.finditer(chunk):
        if not guard_else_fails(chunk, match.end()):
            continue
        raw = binds.get(match.group(1))
        if raw is None:
            raw = class_binds.get(match.group(1))
        if raw is None:
            continue                      # computed or out of scope — skipped, not reported
        needle = decode_needle(raw)
        if needle is None or len(needle) < MIN_NEEDLE:
            continue
        if needle not in corpus:
            out.append((match, needle))
    return out


def legacy_allowed(paths):
    """Whether a guard file's argument-blind halves may speak, from the paths it NAMES.

    #944: this gate no longer SKIPS the file — it decides whether the `Self.`-qualified half of
    shape 3 (which cannot prove its receiver) is allowed to report. Shape 6 (#960) shares it.

    ⭐ BOTH HALVES MATTER. Without `bool(paths)` the `all(...)` is vacuously TRUE for a guard
    that names no path at all (#926), which is exactly how the one measured false alarm
    (`TheDecisionLogIsMachineReadableTests`, which names `review.sh` with no directory prefix,
    so `SOURCE_PATH` yields nothing) would have got in.

    ⛔ #962 — THIS FUNCTION EXISTS BECAUSE THE SELFTEST TRANSCRIBED THE EXPRESSION INSTEAD OF
    CALLING IT, and #960's commit body then claimed a mutation of it "drives red" when it does
    not. Spelled twice, the vacuous-gate mutation lands in `main` and leaves the selftest GREEN
    — the #941b defect this file already documents about its own split helper, reproduced one
    shape later by the commit that widened it. One definition, both callers (#416).

    ⚠️ IT FAILS OPEN for any path spelling `SOURCE_PATH` does not recognise (`CLAUDE.md`,
    `project.yml`, `Package.swift`, `.github/workflows/*`): those yield no match, so a file that
    reads ONLY such a path looks like "names no path" and is denied — but a file that reads a
    `Sources/` path AND one of those looks like "Sources only" and is allowed. Shape 3 stopped
    relying on this at #944 by proving its own receiver; shape 6 has no such proof yet. Two
    files are live today where shape 6 speaks and the file also reads non-`Sources/` text
    (`BioApplyRateIsTheDedupedRateTests` reads `CLAUDE.md`, `TheWayOutSurvivesRotationTests`
    reads `Info.plist`); both happen to hand Swift source to their guarded receivers, so there
    is no false alarm today. The next one that does not gets one.
    """
    return bool(paths) and all(p.startswith("Sources/") for p in paths)


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
        for chunk in function_chunks(strip_comments(src)):
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
        allow_legacy = legacy_allowed(paths)
        if allow_legacy:
            class_binds = {m.group(1): m.group(2) for m in LOCAL_BIND.finditer(guard_code)}
            for chunk in function_chunks(guard_code):
                for match, needle in shape6_findings(chunk, corpus, class_binds):
                    offset = guard_code.find(chunk)
                    line = guard_code[:offset + match.start()].count("\n") + 1
                    dead.append((os.path.relpath(guard, root), line, needle))
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
        helpers = stripping_helpers(src)          # RAW: a helper is a declaration, not prose
        consts = {m.group(1): m.group(2) for m in PATH_CONST.finditer(guard_code)}
        for chunk in function_chunks(guard_code):
            for match, needle in shape3_findings(chunk, corpus, helpers, consts,
                                                 allow_legacy):
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


def selftest():
    """Drive the two decisions this script gets wrong quietly — on literals, not on the tree.

    ⛔ #941 — THERE WAS NO SELFTEST, in a script whose own comments argue twice that a checker
    must be driven against a known positive rather than reasoned about. Both cases below go RED
    under the mutation they were written for and green after; a fixture over the real tree could
    not have shown either, because shape 3 finds nothing there in both directions.
    """
    ok = True
    ESC = chr(92) + "n"           # the two characters a Swift `\n` is before decoding

    # 0. SHAPE 6 (#960), driven as a COMPOSITION. Four cases in one fixture, because the three
    #    things this shape can get wrong quietly are all decisions ABOUT a match rather than
    #    the match itself: whether the else block is fatal, whether a class-level binding is
    #    consulted, and whether a present needle stays silent. A selftest that drove
    #    `GUARD_LIT` and `decode_needle` separately would pass through every one of them —
    #    the lesson #941/#941b paid for twice in this same file.
    ALIVE = "let liveThing = 42"
    GONE = "let deletedThing = 7"
    GONE2 = "let alsoDeletedThing = 9"
    s6_class = 'private let anchorName = "' + GONE2 + '"\n'
    s6_chunk = (
        '    func a() {\n'
        '        let code = engineCode()\n'
        '        guard let x = code.range(of: "' + GONE + '") else {\n'
        '            XCTFail("gone")\n'
        '            return\n'
        '        }\n'
        '        guard let y = code.range(of: "' + GONE + ' NOFAIL") else {\n'
        '            return\n'
        '        }\n'
        '        guard let z = code.range(of: anchorName) else {\n'
        '            XCTFail("gone too")\n'
        '            return\n'
        '        }\n'
        '        guard let w = code.range(of: "' + ALIVE + '") else {\n'
        '            XCTFail("present")\n'
        '            return\n'
        '        }\n'
        '    }\n')
    s6_binds = {m.group(1): m.group(2) for m in LOCAL_BIND.finditer(s6_class)}
    found6 = {n for _, n in shape6_findings(s6_chunk, ALIVE, s6_binds)}
    if GONE not in found6:
        print("selftest: shape 6 missed a dead inline needle in a fatal guard — the shape "
              "does not see the form it was written for.", file=sys.stderr)
        ok = False
    if GONE2 not in found6:
        print("selftest: shape 6 missed a dead CLASS-BOUND needle. #959b hoisted exactly such "
              "an anchor to a `private let`, so dropping this loses the known positive.",
              file=sys.stderr)
        ok = False
    if any(n.endswith("NOFAIL") for n in found6):
        print("selftest: shape 6 reported a `guard let … else { return }` with no XCTFail — "
              "that is a legitimate skip, not a failure, and reporting it is a false alarm.",
              file=sys.stderr)
        ok = False
    if ALIVE in found6:
        print("selftest: shape 6 reported a needle that IS in the corpus — the membership "
              "test is inverted or the corpus is not being read.", file=sys.stderr)
        ok = False

    # ⛔ #963 — BRACES INSIDE STRING LITERALS, BOTH ERROR DIRECTIONS. Guards in this repo quote
    # Swift at each other constantly, so an unbalanced brace in a failure message is ordinary,
    # not exotic (`ASwiftUIBodyStaysUnderTheBuilderOverloadsTests` has two `{` in one message).
    GONE3 = "let braceOpenerThing = 3"
    GONE4 = "let braceCloserThing = 4"
    s6_braces = (
        '    func b() {\n'
        '        let code = engineCode()\n'
        # (a) NON-fatal skip whose message quotes an OPENING brace. Counting it ran the window
        #     past the end of this else and swallowed the NEXT guard's XCTFail — a legitimate
        #     `else { return }` reported as a dead needle.
        '        guard let a = code.range(of: "' + GONE3 + '") else {\n'
        '            print("this quotes struct X: View {")\n'
        '            return\n'
        '        }\n'
        # (b) FATAL else whose message quotes a CLOSING brace BEFORE the XCTFail. Counting it
        #     closed the window early, so the XCTFail fell outside and the finding was lost.
        '        guard let b = code.range(of: "' + GONE4 + '") else {\n'
        '            let hint = "closing brace } in prose"\n'
        '            XCTFail("gone: \\(hint)")\n'
        '            return\n'
        '        }\n'
        '    }\n')
    found_braces = {n for _, n in shape6_findings(s6_braces, ALIVE, {})}
    if GONE3 in found_braces:
        print("selftest: shape 6 reported a non-fatal `else { return }` whose message merely "
              "QUOTES an opening brace. The brace walk is counting inside string literals "
              "again, so the window ran on and borrowed a neighbour's XCTFail (#963).",
              file=sys.stderr)
        ok = False
    if GONE4 not in found_braces:
        print("selftest: shape 6 MISSED a fatal guard whose failure message quotes a closing "
              "brace before the XCTFail. The brace walk closed the window inside a string "
              "literal, so the XCTFail fell outside it (#963).", file=sys.stderr)
        ok = False

    # ⛔ AND TWO MORE, FOUND BY MUTATING MY OWN FIX — the #962 lesson arriving one cycle later.
    # The two cases above pin the brace COUNTING but not the two other places the same walk
    # reads raw text: reverting only the OPENER lookup, or only the `XCTFail` membership test,
    # both left the selftest GREEN. What bites is the composition, not the part (#914/#941b).
    GONE5 = "let compoundThing = 5"
    GONE6 = "let politeSkipThing = 6"
    s6_raw = (
        '    func c() {\n'
        '        let code = engineCode()\n'
        # (c) A COMPOUND guard whose second clause QUOTES `else {`. A raw `find("else {")` from
        #     the needle latches onto that string and starts the brace walk inside a literal.
        '        guard let c = code.range(of: "' + GONE5 + '"),\n'
        '              code.contains("} else { fallthrough }") else {\n'
        '            XCTFail("gone")\n'
        '            return\n'
        '        }\n'
        # (d) A NON-fatal skip whose message merely NAMES `XCTFail`. Read on raw text, the word
        #     inside the string makes a polite skip look fatal and the needle gets reported.
        '        guard let d = code.range(of: "' + GONE6 + '") else {\n'
        '            print("re-anchor this rather than XCTFail here")\n'
        '            return\n'
        '        }\n'
        '    }\n')
    found_raw = {n for _, n in shape6_findings(s6_raw, ALIVE, {})}
    if GONE5 not in found_raw:
        print("selftest: shape 6 MISSED a fatal compound guard whose second clause quotes "
              "`else {`. The opener lookup is reading raw text again, so the brace walk "
              "started inside a string literal (#963).", file=sys.stderr)
        ok = False
    if GONE6 in found_raw:
        print("selftest: shape 6 reported a polite `else { return }` whose message merely "
              "NAMES `XCTFail`. The fatality test is reading raw text, so prose about another "
              "guard makes a skip look fatal (#963).", file=sys.stderr)
        ok = False

    # The VACUOUS-GATE mutation (#926), driven through `legacy_allowed` — the function `main`
    # actually calls. ⛔ #962: this loop used to re-spell the expression, so mutating the real
    # gate left the selftest GREEN and #960's commit body claimed otherwise. A selftest that
    # transcribes what it pins pins its own transcription.
    for label, paths, expected in (("no path at all", set(), False),
                                   ("Sources only", {"Sources/A.swift"}, True),
                                   ("mixed", {"Sources/A.swift", "scripts/x.py"}, False)):
        got = legacy_allowed(paths)
        if got is not expected:
            print(f"selftest: the Sources-only gate said {got} for '{label}' — a vacuous "
                  "TRUE here lets a guard about a non-Swift file be judged against Sources/.",
                  file=sys.stderr)
            ok = False

    # 1. THE COMPOSITION, not the parts (#914). A needle carrying an undecodable escape must be
    #    SKIPPED by shape 3, never compared: decoded naively it becomes characters that can never
    #    be in `Sources/`, so the tool would report a correct guard as dead (#665/#937). Driving
    #    `decode_needle` alone here would stay green through exactly that mutation — it is the
    #    CALL SITE that was wrong, not the decoder.
    chunk = ('    func a() throws {\n'
             '        let code = Self.source(of: "Sources/X.swift")\n'
             '        XCTAssertTrue(code.contains("var voiceTuneStrength: Float = 1' + ESC + '"))\n'
             '        XCTAssertTrue(code.contains("var voiceTuneStrength: Float = 1"))\n'
             '    }\n')
    corpus = "var voiceTuneStrength: Float = 1\n"
    reported = [needle for _, needle in shape3_findings(chunk, corpus, set(), {}, True)]
    if reported:
        print(f"selftest: shape 3 reported {reported} — an escaped needle must be skipped, "
              "and the unescaped one is present in the corpus")
        ok = False
    # …and it must still FIND a genuinely absent needle, or the skip above proves nothing.
    absent = [needle for _, needle in
              shape3_findings(chunk, "something else entirely", set(), {}, True)]
    if absent != ["var voiceTuneStrength: Float = 1"]:
        print(f"selftest: shape 3 found {absent} — it must report the one plain needle that is "
              "absent from the corpus, or the test above is vacuous")
        ok = False

    # 2. The receiver scope, which #666 had to narrow from per-FILE to per-FUNCTION after seven
    #    false positives. A name bound to source text in one function must not vouch for the
    #    same name in the next.
    #
    # ⛔ #941b — THIS CASE DID ITS OWN `re.split` AND THEREFORE DID NOT BITE. The per-function
    # split lives in `main()`, not in `shape3_findings`; a selftest that splits the fixture
    # itself stays GREEN through the exact #666 mutation it names (measured by the mandatory
    # review: revert `main()` to file scope → still green). It is the #914 defect a second time
    # in one file — case 1 was fixed for it and case 2 shipped with it. The fixture is now
    # handed UNSPLIT to the shared `function_chunks`, so the composition is what runs.
    two = ('    func a() throws {\n'
           '        let line = Self.body(of: "x", in: "Sources/Y.swift")\n'
           '        XCTAssertTrue(line.contains("a needle that is source text"))\n'
           '    }\n'
           '    func b() throws {\n'
           '        let line = AudioConfiguration.latencyLine(sampleRate: 48000)\n'
           '        XCTAssertTrue(line.contains("a needle that is a produced string"))\n'
           '    }\n')
    scoped = [n for c in function_chunks(two) for _, n in shape3_findings(c, "", set(), {}, True)]
    # ⛔ THE MESSAGE SAID "leaked across functions" UNCONDITIONALLY (#941b) — it also printed
    # when NOTHING was found, i.e. it named a leak while reporting a vacuum. Two questions, two
    # sentences (#367: an assertion must fail for the reason it states).
    if "a needle that is source text" not in scoped:
        print("selftest: the source-text needle was not found at all — the anchor is gone, so "
              f"the leak check below proves nothing (checked {scoped})")
        ok = False
    elif scoped != ["a needle that is source text"]:
        print(f"selftest: receiver scope leaked across functions — checked {scoped}")
        ok = False

    # 3. #944 — THE PLAIN BIND, driven as a COMPOSITION through the two gates and the real
    #    `function_chunks`. This fixture IS the shape that missed the #943 defect: the helper
    #    call is unqualified (`source(Self.voice)`), while the pre-#944 `SOURCE_BIND` only ever
    #    recognised `Self.source(...)`. It goes RED under the mutation it exists for — revert
    #    `source_receivers` to `SOURCE_BIND` alone and the needle stops being reported.
    #
    #    ⚠️ Re-derive the numbers in the block comment above rather than trusting them; the
    #    probe is this selftest with `Tests/CISmoke/*.swift` in place of the fixture.
    guard_file = (
        "    private func source(_ p: String) throws -> String {" + chr(10) +
        "        return SourceText.codeOnly(try String(contentsOf: url))" + chr(10) +
        "    }" + chr(10) +
        "    func a() throws {" + chr(10) +
        "        let code = try source(Self.voice)" + chr(10) +
        "        XCTAssertTrue(code.contains(" + chr(34) + "private var heldByController = false" + chr(34) + "))" + chr(10) +
        "    }" + chr(10))
    helpers = stripping_helpers(guard_file)
    consts = {"voice": "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"}
    widened = [n for c in function_chunks(guard_file)
               for _, n in shape3_findings(c, "a corpus without it", helpers, consts, False)]
    if widened != ["private var heldByController = false"]:
        print("selftest: the #944 plain bind was not recognised — shape 3 reported "
              f"{widened}. This is the exact shape that missed #943; without it the widening "
              "buys nothing.")
        ok = False

    # 4. …and each gate must REFUSE for its own reason, or case 3 is just a wider regex with
    #    #941's nine false alarms behind it. Two mutations, two refusals:
    #    (a) the helper does not strip — #941 kind 1/3 (a needle that lives in a comment, or
    #        text transformed before the assert). (b) the argument names no `Sources/` path —
    #        #941 kind 2, the one whose first draft measured green Ochr(10)Y by coincidence.
    unstripped = guard_file.replace("SourceText.codeOnly(try String(contentsOf: url))",
                                    "try String(contentsOf: url)")
    leaked = [n for c in function_chunks(unstripped)
              for _, n in shape3_findings(c, "a corpus without it",
                                          stripping_helpers(unstripped), consts, False)]
    if leaked:
        print(f"selftest: gate 1 leaked — a helper that does NOT call SourceText.codeOnly "
              f"still vouched for {leaked}. Raw text may hold the needle in a comment.")
        ok = False
    off_tree = [n for c in function_chunks(guard_file)
                for _, n in shape3_findings(c, "a corpus without it", helpers,
                                            {"voice": "Tests/CISmoke/Whatever.swift"}, False)]
    if off_tree:
        print(f"selftest: gate 2 leaked — a receiver bound from a non-Sources path was still "
              f"checked against the Sources corpus, reporting {off_tree}.")
        ok = False

    # 5. #944 — THE FILE GATE MUST GATE ONLY THE LEGACY HALF, in both directions. Cases 3 and
    #    4 already run with `allow_legacy=False` and still find the needle, which pins that the
    #    argument-proving half is NOT suppressed by the proxy. This is the other half: an
    #    argument-BLIND `Self.` receiver must fall silent when the proxy says no. Without it,
    #    "relaxed the gate" could quietly mean "removed it".
    legacy_chunk = (
        "    func a() throws {" + chr(10) +
        "        let code = Self.source(of: " + chr(34) + "Sources/X.swift" + chr(34) + ")" + chr(10) +
        "        XCTAssertTrue(code.contains(" + chr(34) + "a needle that is absent here" + chr(34) + "))" + chr(10) +
        "    }" + chr(10))
    allowed = [n for c in function_chunks(legacy_chunk)
               for _, n in shape3_findings(c, "", set(), {}, True)]
    refused = [n for c in function_chunks(legacy_chunk)
               for _, n in shape3_findings(c, "", set(), {}, False)]
    if allowed != ["a needle that is absent here"]:
        print(f"selftest: the legacy `Self.` bind stopped being recognised at all — {allowed}. "
              "The refusal check below would then prove nothing (#367).")
        ok = False
    elif refused:
        print(f"selftest: the file gate no longer restrains the argument-blind legacy half — "
              f"it still reported {refused}. #665 chose that proxy because that half never "
              "looks at its argument; #944 relaxed it for the gated half only.")
        ok = False

    # ⭐ #962 — THE COMPOSITION, DRIVEN THROUGH `main()` ITSELF. Every check above hands
    # `shape6_findings` a chunk and a dict it built by hand, so it pins the PART. The reviewer
    # of #960 deleted the ENTIRE shape-6 call site from `main` and this selftest still printed
    # OK: `function_chunks`, `strip_comments`, the `class_binds` construction, the line
    # arithmetic and the call site itself were never executed by it. That matters more here
    # than in a CI-gated tool — `dead-needles.py` is a manual pre-push playbook, so this
    # selftest is the only automated thing that could notice the shape going silent (#914/#941b:
    # what bites is the composition, not the parts).
    with tempfile.TemporaryDirectory(prefix="dead-needles-selftest-") as tmp:
        os.makedirs(os.path.join(tmp, "Sources"))
        os.makedirs(os.path.join(tmp, "Tests/CISmoke"))
        with open(os.path.join(tmp, "Sources", "A.swift"), "w", encoding="utf-8") as h:
            h.write("func a() {\n    // " + ALIVE + "\n    let s = \"" + ALIVE + "\"\n}\n")
        # The fixture NAMES a Sources path so `legacy_allowed` opens the gate — the same
        # condition the real corpus satisfies. Without it this would prove only that a denied
        # file stays quiet.
        with open(os.path.join(tmp, "Tests/CISmoke", "FixtureTests.swift"), "w",
                  encoding="utf-8") as h:
            h.write('final class FixtureTests: XCTestCase {\n'
                    # A CLASS-BOUND anchor too: `main` builds the fallback dict, and without
                    # this the fixture cannot tell a working fallback from `class_binds = {}`.
                    '    private let anchorName = "' + GONE2 + '"\n'
                    '    func testA() throws {\n'
                    '        let code = try text("Sources/A.swift")\n'
                    '        guard let x = code.range(of: "' + GONE + '") else {\n'
                    '            XCTFail("gone")\n'
                    '            return\n'
                    '        }\n'
                    '        guard let z = code.range(of: anchorName) else {\n'
                    '            XCTFail("gone via the class binding")\n'
                    '            return\n'
                    '        }\n'
                    '        guard let y = code.range(of: "' + ALIVE + '") else {\n'
                    '            XCTFail("present")\n'
                    '            return\n'
                    '        }\n'
                    '    }\n'
                    '}\n')
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            rc = main(tmp)
        out = buf.getvalue()
        # The LINE, not just the name: `line = 1` for every finding leaves every other check
        # here green while a triager is sent to the top of the file. Driven — the fixture's
        # first fatal guard is on line 5 (class · private let · func · let code · guard).
        if "Tests/CISmoke/FixtureTests.swift:5" not in out:
            print("selftest: the end-to-end run did not anchor the fixture's dead needle at "
                  f"line 5. Got:\n{out}", file=sys.stderr)
            ok = False
        if GONE2 not in out:
            print("selftest: the end-to-end run missed the CLASS-BOUND dead needle. `main` "
                  "builds that fallback dict itself, so emptying it there leaves every "
                  "hand-built check above green — the dict they use is passed in (#962).",
                  file=sys.stderr)
            ok = False
        if GONE not in out:
            print("selftest: the END-TO-END run through `main()` did not report the fixture's "
                  "dead needle. Shape 6 is wired out of the scan, or the corpus/gate/line "
                  "arithmetic around it broke — every hand-built check above can still pass "
                  "while the tool reports nothing on a real tree (#962).", file=sys.stderr)
            ok = False
        if ALIVE in out:
            print("selftest: the end-to-end run reported a needle that IS in the fixture's "
                  "Sources/ — the corpus is not reaching the comparison.", file=sys.stderr)
            ok = False
        if rc != 1:
            print(f"selftest: `main()` returned {rc} on a tree with one dead needle; 1 is the "
                  "exit code a caller checks. A finding printed under a 0 is a silent green.",
                  file=sys.stderr)
            ok = False

    print("dead-needles --selftest: OK" if ok else "dead-needles --selftest: FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    # #941b — anywhere in argv, not just position 1: `dead-needles.py . --selftest` used to
    # run the normal scan silently, which is the worst kind of no-op (it prints a green).
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    roots = [a for a in sys.argv[1:] if not a.startswith("-")]
    sys.exit(main(roots[0] if roots else "."))
