# CLAUDE.md — `Tests/CISmoke/` (the blocking bundle)

Scope: this directory only. The root `CLAUDE.md` owns product, brand and state; this file
owns **how a guard is written, graded and reported**. Every law below is one this repo has
already paid for; none is invented.

Measured 2026-08-14 (run the command, never quote the number — the 08-12 row set had
aged by 46 files in two days, which is exactly why the commands are the fact):

| Fact | Command |
|---|---|
| **284** files | `git ls-files 'Tests/CISmoke/*.swift' \| wc -l` |
| **1 927** `func test…` | `git grep -ho 'func test[A-Za-z0-9_]*' -- 'Tests/CISmoke/*.swift' \| wc -l` |
| **119** delegate to `SourceText.codeOnly` | `git grep -l 'SourceText.codeOnly' -- 'Tests/CISmoke/*.swift' \| wc -l` |
| **69** still declare a private stripper | `git grep -lE 'func (codeLines\|stripComment\|sourceLines)' -- 'Tests/CISmoke/*.swift' \| wc -l` |

---

## 0. There is no compiler here

No local Swift toolchain, no simulator. **CI is the only compiler.** A guard you cannot run
is graded by *transcription*: reimplement its logic in Python and drive it against **both**
trees — `git show <parent>:<path>` and the worktree. Anything you have not driven that way,
you have not graded. Say so.

---

## 1. State the limit before the claim

Three different things get called "green" here, and conflating them is the defect this
bundle exists to prevent. Every guard's file header names which one it is:

- **SOURCE-TEXT SCAN** — proves where text sits. It does not prove the app does anything.
  Most `Studio/` assertions are this, because the members are `private` on a `View` no test
  bundle can instantiate.
- **END-TO-END BEHAVIOUR** — drives shipped, `public`, Foundation-only value types. This is
  the strong kind; say so when you have it.
- **DEVICE PROBE** — renders, sounds, reads well, VoiceOver speaks it. **Impossible here.**
  Name it as open rather than implying the guard covers it.

A guard that mixes the three in one file must label them per assertion.

---

## 2. Writing a guard

**#367 — it must be able to fail for its NAMED reason.** Not just "able to fail". The
prototype: an ordering scan anchored on a token whose first occurrence was the *declaration*,
so it compared 1228 < 1169 and was red on correct code. The mirror case is worse — an
assertion that is green for a reason other than the one its message states (a `min()` over a
whole track whose first sample is 0 by cold-start construction pinned the minimum forever,
while the message claimed a full retraction was proven).

**#364 — it must not forbid correct work.** A guard that turns an ordinary, legitimate edit
red gets deleted, and then the law goes with it. Never pin a value a designer may reasonably
change (the three corner radii are pinned as *names*, never as 4/8/12). Never ban a file from
naming what it forbids.

**#408 — anchor on a token that occurs ONLY at the intended site.** Checking that uniqueness
is part of *writing* the scan, not of review. Prefer brace-matched extraction of a member's
body over a fixed line window: this repo writes 30–40-line comment blocks, `SourceText.codeOnly`
preserves line count, so any fixed window or bounded blank-line lookahead is unsound **by
construction** and gets worse as the prose grows.

**#343 — the counterweights are the content.** A guard that only asserts the new line stays
green on a tree that kept the LINE and lost the FACT. Pin the premises that make the new
assertion mean anything: the producer still writes the field, the door is still mounted, the
sibling path still refuses. Expect most assertions in a file to be green on both trees. That
is correct, not padding.

**#425 — a slice must not contain a claim and its own refutation.** If the doc block seven
lines up explains why the general statement cannot hold, the general statement is wrong.

**#416 — one definition per decision.** Ask the existing constant instead of restating it
(`BioSource.freshnessWindow`, `BioEgressPolicy`, `SynthPatch.Bounds`, `RespirationEstimator
.reportableRange`). Two spellings of one threshold is the defect, whether or not they agree today.

⚠️ **#926 — AND THERE IS ALREADY A LIVE ONE IN THIS DIRECTORY: `slice(…, from:, to:)`.** Ten
files declare it privately, in **two families that mean different things**. Four return the text
AFTER the `from` marker (`text[start.upperBound...]`); six return it STARTING WITH the marker
(`String(code[start.lowerBound..<end.lowerBound])`). Both stop before `to`, so they differ by
exactly the opening marker: **a needle counting anything that occurs in that marker — a function
name, `private func`, a label — reads one higher in the second family.** Both also return `""` on
a missed anchor, so `XCTAssertEqual(count, 0)` over a mis-anchored slice is a vacuous green;
anchor-check before expecting zero. **When you copy a `slice` from a neighbour, read its body,
not its name** — that choice is made while AUTHORING, which is why it is written here and not
only in the guard (`TheSliceHelperHasTwoSemanticsTests`, which can only fire at CI time and only
on a THIRD spelling). No live case today; the migration to one shared helper is deliberately
still open, because folding them changes the meaning of four files.

**#453 / #460 / #477 — one stripper.** `SourceText.codeOnly` is the definition of "code, not
prose": it blanks comments, is string-literal aware, and **preserves line count** (several
guards assert on `lines[i - 1]` relations). Do not declare a private one.
`OneDefinitionOfCodeNotProseTests` enforces this by NAME, so 69 differently-named private
copies remain — widening that anchor reds ~70 files at once and is a *migration*, not a guard
change. When you use the stripper, **measure whether it is load-bearing**: count each needle
raw vs. stripped on both trees and say `TRAGEND (n of m verdicts flip)` or `PROPHYLAKTISCH
(0 of m)`. Three slices in a row claimed load-bearing without measuring and had to retract.

**#486 — one absence reported N times is ONE finding.** When a new type does not exist on the
parent, every assertion naming it goes red together. That is one finding, not six. Counting
them as six is the flattering direction of the same defect #433 names.

**#431 / #440 / #443 — a defaulted argument no call site writes appears in no diff.** Make it
required and let the compiler catch the forgetful call site — but remember the compiler only
reaches you where a gate builds the caller: `Tests/EchoelmusicTests` is compiled by **no** gate
(#208), so a required argument buys silence there, not safety.

**#448 — a measured number carries its sampling grid**, or it is not a measurement. A mean over
0…95 s at 0,5 s and a mean over 0…90 s are different numbers with the same name.

**#442 — write assertions from the algebra, not from the printed value.** `1000 + 3.2`
subtracted back is 3,2000000000000455; anchor at zero where the subtraction is exact.

**#808 — a RUNTIME needle is not self-verifying, so run the checker before you push it.**
A SCAN needle (`code.contains("…")`) is verified by the `grep` you did while writing it. A
needle that CALLS a shipped function — `SomeCopy.hint(for: x).contains("your body")` — is
verified by nothing until CI runs, and CI shows only `tail -200 test.log` (#807). That is how
`TheBioPanelRowsSayWhoseBodyTests` shipped a needle in the SAME commit as the sentence it was
written for and stayed red for two months: the sentence reads "your measured **body state**".

```
python3 scripts/needle-reachability.py            # scan the whole bundle against Sources/
python3 scripts/needle-reachability.py --selftest # after touching it
```

It asks one question — does the literal occur in the source of the function the needle calls
— joining concatenation seams (`"… your " + "body …"`) and resolving ONE helper hop, because
the first version reported exactly two findings and both were those. **Read a finding, do not
obey it.** Its error directions run BOTH ways and the tool's own docstring got this backwards
until its selftest disproved it: *incomplete* resolution (two hops, interpolation) reports a
needle that works — a false ALARM; *over-broad* resolution (a literal in a comment, in a
branch this state never takes, in a same-named function elsewhere) is a false GREEN. Zero
findings today across the bundle. Guard: `TheNeedleCheckerNamesBothErrorDirectionsTests`.

---

## 3. Honest grading (#433 / #464) — required in every guard header

State, for the parent tree:

- **How many assertions are REGRESSIONS** (red there for the reason their name gives).
- **How many are red only by ANCHOR ABSENCE** — the extraction found nothing. Report as one
  absence, N times (#486).
- **How many are FORWARD guards** — they drive a symbol this same commit creates and could
  never have been red. Booking these as regressions is the flattering-direction defect.
- **How many are COUNTERWEIGHTS** — green on both trees, and usually the point of the file.
- If the file **does not compile** against the parent (it names a new symbol), say exactly
  that: *no assertion has a verdict there*, and hand-transcribe instead. Do not let "not
  gradable against the parent" read as "green against its own tree" — #488 shipped a red gate
  for a cycle behind exactly that ambiguity.

Getting your own tests wrong in the *generous* direction is the same defect as in the harsh one.

⛔ **And delta grading is BLIND to a permanently-red assertion in a method the slice did not
touch.** It compares parent with worktree; an assertion red on both produces no delta and is
reported by nothing. #497 moved a value onto the frame and left two needles in
`TheAlwaysOnBioPathIsNamedTests` naming a local (`hrNormalized`) that stopped existing —
4 red assertions, 2 needles × 2 sites. #542 then rewrote 168 lines of that same file, graded
"ZERO REGRESSIONS" *honestly by this section's procedure*, and the red survived because it
predates the delta. #445 is why a run does not catch it either: the surviving clone flushes a
non-deterministic subset, so absence from the log means nothing. **The only thing that finds it
is transcribing the WHOLE file, not the diff — so when a slice rewrites a guard substantially,
drive every assertion in it, not only the ones it changed.** Cheap tell: a needle naming a
LOCAL VARIABLE rather than a member or a literal is the fragile kind — `git grep -c` it in
`Sources` before trusting it.

---

## 4. Before you change a surface

`git grep` the surface in **`Tests/CISmoke`**, not only in `Sources/` (#456). A commit that
removes a control must move the guards over it in the *same* commit. The failure mode is not
a red gate — it is a guard that stays **green for a reason that no longer exists** (a needle
searching for a string the new code can never contain again).

If you delete a view or a file, grep afterwards too (#472): the blocker you registered is
rarely the only one, and prose in other source files may cite what you removed.

**RENAMING a logged string is the same event and is easier to miss (#655/#656).** #650 routed
monitoring outcomes through a helper that OWNS the `"Input monitoring: "` prefix; a guard
anchored on the old full literal then matched nothing, `XCTUnwrap` on nil failed, and it was
**red on a correct tree for five commits** while three status deltas said "nothing red is
mine". Nothing caught it because §5 is true: the pipeline reports `failure` on every push, so
a genuinely red guard is indistinguishable from the host dying.

```
python3 scripts/dead-needles.py        # 0 = clean · 1 = a guard fails on a correct tree
```

```
python3 scripts/count-pins.py            # 0 = every COUNT PIN it can read still matches
python3 scripts/count-pins.py --all      # also list the pins it could not resolve
python3 scripts/count-pins.py --selftest # after touching it
```

**A count pin is the other shape that rots silently, and it rots the same way (#903/#904).**
`XCTAssertEqual(occurrences(of: "…", in: code), N)` goes stale when the CODE changes
CORRECTLY and the number does not follow. Three measured cases, none of them noticed by CI:
a breadcrumb pin red for thirteen commits (#903, #888 added three sites), a helper-call pin
red since `bae1672`/2026-08-19 (a fifth caller doing exactly what the pin's own message asked
for), and a pause pin red since `d0564d7`/#823 (a pause that became a stop). §5 is why none
of them surfaced: the pipeline reports `failure` on every push, so a genuinely red guard is
indistinguishable from the host dying. **Run it in the same breath as `dead-needles.py`.**
⚠️ Its output prints a denominator on purpose (`N of M pins it can SEE`) — M is NOT the
bundle's universe of count pins, and a clean run proves the ARITHMETIC only, never that a
pin is anchored on the right token (#367/#408). Five limits in its docstring; it is
validated against the tree that carried the #903 defect, per §4's known-positive rule.

```
python3 scripts/diag-ladder.py --source          # every announced rung has an emitter
python3 scripts/diag-ladder.py <echoel_diag.log> # where a ladder stopped in a real run
```

**DRIVE BOTH MODES, ALWAYS — #907 is the whole argument.** The two modes read DIFFERENT
things and disagree: `--source` walks the emitters in `Sources/`, the log mode walks the
lines a device actually wrote. #906 added a breadcrumb for a skipped step and wrote it
NUMBERED (`session: raise 1/2 SKIPPED: …`). `--source` stayed green — the emitter exists.
The LOG mode kept the LAST `n/N` per ladder and had no notion of a skip (it has one since
#908 — see below), so a perfectly
healthy TWO-OWNER run ended its ladder at `1/2` and the tool printed **"stopped before their
last step … a DEATH AT THAT STEP"** — on exactly the path the ladder exists to illuminate.
Reproduced on a synthetic log both ways before and after the repair.

⛔ **THE LAW #907 WROTE HERE LASTED ONE COMMIT, and that is the right outcome, not a
wobble.** It said: *a skipped step may be NUMBERED only when the ladder WALKS ON past it*,
pinned by claim (c3). Two things were wrong with it as a LAW — it is position-dependent
(unnumbered is correct only where the skip precedes every rung; mid-ladder no wording works
at all), and it obliged every future ladder author to remember which side of the first rung
their skip sits on, for a tool we own and can teach. It is kept here as history because the
next reader will otherwise re-derive it.

⭐ **#908 TAUGHT THE TOOL HALF OF IT — the half no wording could do.** `diag-ladder.py`
knows a **TERMINATOR**: an **UNNUMBERED** `SKIPPED` / `REFUSED` / `FAILED` line for a known
ladder. A ladder that stops short with one of those after it reads **`⏹ ended`**, not
`❌ died`. `FAILED` gets its own outcome and stays a finding — a failure is the thing the
reader is hunting, not a tidy exit. That fixes `mic: start REFUSED`, which sits between
`2/3` and `3/3` and printed a FALSE DEATH that no source wording could repair (measured:
`2/3 SKIPPED` printed the same, `3/3 SKIPPED` printed ✅ for a step that never ran).

⛔ **AND #908's FIRST DRAFT RETIRED (c3) ON THAT BASIS, WHICH WAS WRONG — the review
disproved it with a log.** `AudioEngine`'s `on 4/5 SKIPPED:` WALKS ON (`on 5/5: installing
input tap` follows), so a log ending on that line is a death **inside `installTap`**, the
`isInputConnToConverter` region the ladder exists for — and the draft printed `⏹ ended`,
exit 0, telling the reader not to look there. **In a log, a numbered skip that walks on and
one that returns are the same shape**, so the tool must read both as deaths and (c3) is what
keeps the returning kind out of `Sources/`. Tool and guard split the job; neither replaces
the other.

⭐ **#914 MADE THE `--source` CENSUS SAY IT PER LINE.** That section used to be headed
*"terminator lines (end a ladder without advancing it, #908):"* and listed the two NUMBERED
`on … SKIPPED` lines right next to the real terminators, with the distinction demoted to the
footnote below the list. The census over-collects **on purpose** (it scans for ANY ALL-CAPS
token after a ladder prefix, so a NEW word shows up instead of silently reading as a death),
so the fix is not to filter it: each entry now states its own effect through the pure
`census_effect`.

⛔ **AND THE FIRST DRAFT OF THAT LABEL WAS WRONG THREE TIMES, ALL IN THE REASSURING
DIRECTION** — the review measured every one. (a) An UNKNOWN word printed *"ENDS the ladder"*,
which is false — `ladder_verdicts` builds its needle from `TERMINAL_WORDS`, so an unknown word
ends nothing — and it contradicted the footer four lines below, **in the one case the
over-collecting census exists for**. (b) A numbered line printed *"walks on"*, a claim about
Swift control flow that a line scanner cannot make: a numbered skip that RETURNS is writable
(that is why guard (c3) exists), and the label would then point the reader away from a real
death — #908's first draft again. The checkable claim is narrower: it does not RESCUE. (c)
*"ENDS the ladder"* was unconditional, but rescue requires the terminator to FOLLOW the last
rung of a SHORT ladder; a terminator before the rungs leaves a death, one after a complete
ladder leaves `done`.

⛔ **THE SELFTEST BEHIND IT ALSO FAILED TWICE BEFORE IT BIT.** Draft 1 was
`any(numbered) and any(not numbered)` over the real tree: it survived a FULL inversion of the
flag, and went red for a legitimate future tree with no numbered skip left — it pinned
`Sources/`, not the code. Draft 2 drove `census_pattern` and `census_effect` on literals,
which is right but still let the inversion through **where the tuple is built**, one step
away. What bites is the composition: every census entry must agree with what the matcher says
about its OWN source line. Measured — that mutation is red, and a tree without numbered skips
stays green. **A checker that cannot fail on the mutation it was written for is not a
checker; drive it, do not reason about it.**

⭐ **(c4) was added ALONGSIDE, not instead:** every exit from the two session moves must
ANNOUNCE itself — the class behind #906 AND #907 both (the #907 review: *"nothing detects a
NEW silent return added to either function"*). No number to go stale, graded across three
trees. ⚠️ Its first draft false-reddened a WRAPPED breadcrumb — the form written in the very
file it scans — and stayed green on `if x { return }`, `else{return}`, a trailing-comment
`return` and a silent `throw`. Mutation-drive a scanner like this before believing it.

Back to `dead-needles.py` (its command block is well above now): it checks the two
shapes whose needle MUST exist — `XCTUnwrap(… .range(of: "…"))` and
`codeOccurrences(of: "…") >= N` — against comment-stripped `Sources/`. Its limits are in its
own header and are real: it does not read negative assertions, interpolated needles, or
whether a guard ran. It was validated against the commit that carried the known defect (finds
exactly one) and the commit that repaired it (finds none) — a detector that has never found
its own known positive is not a measurement.

---

## 5. Did it actually run?

`mcp__github__actions_list` → `list_workflow_jobs`, `workflow_jobs_filter {"filter":"latest"}`.

- Step **"Build for Testing" = `success`** ⇒ this bundle **compiles**. That is the claim a
  compile-only gate can support; `Xcode Compile Check` builds `Sources/` **only** and proves
  nothing about a test file.
- `** TEST EXECUTE FAILED **` = **#396**, founder-gated, harmless — a simulator clone dies
  mid-suite. CI/CD reports `failure` on **every** push because of it, so the conclusion alone
  says nothing.
- `** TEST BUILD FAILED **` ⇒ read the log. **Does any diagnostic name a repo file?** If not,
  it is an infrastructure flake (stale module cache) — re-run, do not debug your slice.
  ⛔ **#667: THIS RULE SAID "any `error:` line" AND THAT NEARLY MISDIAGNOSED A REAL RED.**
  `ci.yml` pipes `xcodebuild` through **xcbeautify**, which rewrites `…: error: …` as a line
  beginning **`❌`** and drops the word. Measured on run `32412687490`: `TEST BUILD FAILED` = 1,
  **`error:` = 0**, `❌` = 3 — and all three named
  `Tests/CISmoke/TheMeasuredLatencyReachesTheDiagLogTests.swift` with a real compile error.
  Following the old recipe literally gives "no `error:` line ⇒ flake ⇒ re-run", which would
  have re-run a genuinely broken commit until someone noticed. **Count BOTH markers:**
      t.count("error:")   # raw xcodebuild, and the SDK/module-cache flake prints these
      t.count("❌")        # xcbeautify's rendering of the same thing
  The flake case (#478) is still recognisable — its diagnostics name an SDK `module.modulemap`
  and a `DerivedData` `.pcm`, never a file under `Sources/` or `Tests/`. The DISCRIMINATOR is
  unchanged (does a diagnostic name a repo file?); only the search term was too narrow.
- ⚠️ **Before changing a signature in `Sources/`, grep THIS directory for its callers.** #666
  added one non-defaulted parameter to `AudioConfiguration.latencyLine`, updated the three
  PRODUCTION call sites, and missed **three behavioural call sites in the guard file it was
  editing at the time** — `TEST BUILD FAILED`, three errors, one cycle lost. Neither
  `dead-needles.py` nor a source-text driver can see this: both read text, and this is a
  type-check fact. The check that works is one command, and it is cheap enough to be reflexive:
      git grep -n "\.<functionName>(" -- Tests/CISmoke Sources
  ⛔ A SCRIPT FOR IT WAS PROTOTYPED AND DELIBERATELY NOT SHIPPED. Matching call arguments
  against declared labels by name alone gave **59 false positives** on a correct tree (one
  `apply` shadowing another); adding receiver-type attribution cut that to 7 but LOST all three
  real positives, because last-`enum|struct`-before-the-func mis-attributes a nested type.
  Per #665's own rule — a checker with false alarms is a checker nobody reads — the honest
  output is this paragraph rather than a script that is wrong in both directions.
- ⛔ **#679 — A THIRD NEEDLE WAS WRONG, AND THIS ONE CALLED A COMMIT WITH FOUR FAILING TESTS
  "clean". `TEST EXECUTE FAILED` is #396 AND a real assertion failure looks identical from
  outside.** Both print that banner; the difference is only in the per-test lines. I searched
  for `failed (` — measured on `34be877`: `failed (` = **0**, `error:` = 0, `❌` = 0, and FOUR
  named guards had failed. The line xcodebuild actually writes is
      Test case 'Suite.testName()' failed on 'Clone 1 of iPhone 17 …' (0.039 seconds)
  so the literal `failed (` can never occur — the word is followed by ` on `, not ` (`.
  **THE NEEDLE IS `" failed on "` ON A LINE CONTAINING `"Test case "`.** Same class as #667
  one layer down: the discriminator was right, the search term could not match the format.
  ⛔ **AND THAT SENTENCE PRESCRIBES A LINE PREDICATE THAT THE TOOL NO LONGER USES (#739), for
  a reason worth carrying: on a badly decoded log the whole file is ONE line, and
  `"Test case " in ln && " failed on " in ln` is then satisfied by the log as a whole. The
  live scan is an anchored regex on the quoted test name. ⛔ **The needle itself was also only
  HALF the format.** Plain `xcodebuild` with no formatter writes
      Test Case '-[SuiteTests testName]' failed (0.001 seconds).
  — capital `Case`, and `failed (`, the very spelling this paragraph bans. #738 matched only
  the xcbeautify form and on such a log printed `TEST FAILURES: 0` and **exited 0**, a SILENT
  green — worse than #679's loud-but-wrong reading. The rule is therefore: `failed (` is
  wrong ALONE and required IN THE ALTERNATION with `" failed on "`. Never either.
  ⚠️ **AND THE LOG IS ONE JSON BLOB WITH ESCAPED NEWLINES.** `get_job_logs` writes
  `{"logs":[{"logs_content":"…\n…"}]}` to the overflow file, so a plain `split("\n")` yields
  ONE line and every per-line filter silently returns nothing while `count()` on the raw text
  still works. That is why the first reading showed "0 failure lines" next to correct counts:
  two different bugs agreeing on a wrong answer. `json.loads` first, then split.
  **Both halves were closed in `scripts/gh-test-verdict.py`** — and the second half REOPENED
  on 2026-08-22, see the ⛔ block below; read "closed" as "closed as of #739", never as a
  standing property. Point it at the overflow file:
      python3 scripts/gh-test-verdict.py <file>
  It prints build-for-testing, the two banners, the count of tests OBSERVED PASSING, every
  compile-error line, every failing test by name, and — since #806 — every SKIPPED test by
  name; exit 1 if anything failed OR skipped. **A skip is not a pass:** it asserted nothing,
  and most of the files here can throw `XCTSkip`, each one guarding an ANCHOR — count with
  `grep -rln XCTSkip Tests/CISmoke/*.swift | wc -l` rather than trusting a number in prose
  (#803; it was 268 of 358 when this was written). The skip needle
  is DERIVED from the proven line shape rather than observed — no log in reach contains a
  test-result skip line — and the parser says so at its definition. Extend that
  script rather than writing a fourth ad-hoc needle set.
  ⛔ **AND THE ESCAPED-NEWLINE HALF CAME BACK ON 2026-08-22 (#738), so "closed" above means
  closed AS OF #738 — not closed forever.** `get_job_logs` writes TWO envelopes and the
  loader decoded one: `job_id=…` returns `{"job_id": …, "logs_content": "…"}` with no `logs`
  key, `json.loads` SUCCEEDED, the key test failed, and the loader fell through to the RAW
  string — one line, literal backslash-n, every per-line filter running over it. Measured on
  `7644011`: it printed **1** test passing where **136** ran; on `1118b46`, 1 where **172**
  ran. On a fixture that really fails it printed **1** failure where **2** had failed, and
  the text began with the name of a test that had PASSED. Not silent (exit stayed 1), but
  wrong in the direction that matters. **The narrow lesson: a JSON parse that SUCCEEDS is not
  a decode that WORKED** — the document was well-formed, its only sin was a different key.
  Repaired with a shape SELFTEST rather than another fixture, because a fixture of either
  single shape passes forever against a loader that mishandles the other:
      python3 scripts/gh-test-verdict.py --selftest
  Run that before trusting a verdict from a log shape you have not seen before. Shape pinned
  by `TheVerdictParserReadsBothLogShapesTests`.
- ⛔ **#807 — THE JOB LOG IS NOT THE TEST RUN. IT IS `tail -200 test.log`, AND THAT RETIRES THE
  "FLUSH LOTTERY" EXPLANATION THIS SECTION GAVE TWICE.** #445's CONCLUSION survives untouched;
  its REASON was wrong, and the wrong reason is what made re-running look like a way to buy
  evidence. Measured on three COMPLETE job logs (`original_length` matched the decoded line
  count, so these are not tails of my own making — `aec6cea`, `67eef12`, `92ddb00`):
  · `ci.yml` runs `xcodebuild test-without-building … 2>&1 | tee test.log | xcpretty`, and
    **xcpretty printed NOTHING** for a twelve-minute run. The live test window is **16 lines**:
    the command echo, the env block, and `##[error]Process completed with exit code 65`.
  · The next step, `Print test log on failure`, is **`tail -200 test.log`**. That 210-line block
    holds **ALL** result lines and the `** TEST EXECUTE FAILED **` marker, in every run measured.
  · Across FOUR consecutive runs the result sets are **133 of 135 identical**. That is a fixed
    tail, not a non-deterministic subset. `test.log` itself is complete; only the JOB log is cut.
  **Consequence, and it is the one that matters: a test that fails outside the last 200 raw lines
  leaves no trace in the job log**, so `gh-test-verdict.py` prints `TEST FAILURES: 0` over a run
  that really failed — a silent green, structural rather than a needle bug. It also explains #686
  exactly: the test that could not pass showed no result line because it was outside the window.
  ⚠️ The tool now prints a `WINDOW` line naming the tail it actually saw, READ from the log
  rather than assumed (pinned by `TheVerdictParserReadsBothLogShapesTests`). **Never write "the
  suite passed" from a green verdict; write what the window supports.**
  ⚠️ Repair is founder-gated (`.github/workflows/**` — report, do not edit) and already has a
  cheap shape: the run writes `-resultBundlePath TestResults` and uploads it as an artifact, so
  complete results EXIST and simply never reach the job log.
- **#445:** a test name **in** the log proves it ran. Its **absence proves nothing** — the
  surviving clone flushes a non-deterministic subset. Honest wording for an unobserved guard:
  *"kompiliert nachweislich, Ausführung unbelegt."* Never "green", never "red".
- **#686 — #445 WITH A KNOWN-BAD CONTROL, which this directory never had before.** Until now
  #445 was an inference: absence *ought* to prove nothing. On 2026-08-21 it was measured
  against a test that provably fails.
  `2e65ab7` shipped `AGrainCannotClickOrRunAwayTests.testZeroMixReturnsTheInputExactly…`
  asserting `activeGrainCount > 0` one call after the mix was raised. The stage cannot
  satisfy that — the spawn accumulator sits at 0.00091 after one call and the first grain
  launches on call ~1 098 — confirmed by re-implementing the algorithm in Python. The file
  was in the commit, it compiled (`build-for-testing: Succeeded`), and the gate reported
  **170 tests passing, 0 failures, and not one result line from that suite.**
  Whether it never ran or ran and was not flushed does not matter; the consequence is the
  same and it is worth saying without softening: **the blocking bundle did not block a test
  that was certain to fail.** 336 files in the directory, 170 results flushed on that run.
  Two things follow, and neither is "write fewer guards":
  · A new guard's numbers are only as good as the arithmetic you did BEFORE pushing. A CI
    round trip is not a check on them — it is a lottery ticket that mostly comes up blank.
    Derive the expectation (`#442`), or simulate the algorithm, or you have not tested it.
  · The mandatory reviewer is not ceremony. On this slice it caught the failing expectation
    that the gate then demonstrably did not.
  ⚠️ Do not read this as "#396 is worse than we thought" and go quiet about it — the fix is
  founder-gated and already recorded. Read it as: **the gate is a floor, not a verdict.**
- **#689 — COUNT THE ROOT CAUSES, NOT THE ERROR LINES, and this one nearly became a false
  law in the always-loaded file.** `6eb172b` produced four `error:` lines naming a repo file:
  three `cannot find 'source' in scope` and one `type 'Any' cannot conform to 'Equatable'`.
  The fourth reads as an independent defect in `map(\.0)` — a key path to a tuple element —
  and the review that found the slice flagged exactly that construct as suspect.
  It is a **cascade**. `chain` is bound by `try source(...)` on the failing line, so it has no
  type; the closure `{ !chain.contains($0.1) }` cannot resolve; `filter` returns something
  unresolved; `map(\.0)` degrades to `[Any]`; and `XCTAssertEqual` then reports the only
  thing it can see. One root cause, four lines.
  Measured proof that the construct is fine: `OneSpellingOfTheDemoSubjectTests.swift:243`
  does `strippedLines().map(\.2).joined(separator:)` on a `[(String, Int, String)]`, in THIS
  bundle, and it compiles on every green run. A `[Any]` there could not be `joined`.
  **The rule: when several errors name one file, fix the FIRST — the unresolved symbol — and
  re-measure before believing any of the others.** Had this not been re-measured, a row saying
  "`map(\.N)` on a tuple does not compile" would have gone into CLAUDE.md's build-error table,
  where it is prescriptive and always loaded, and the next session would have obeyed it.
  ⚠️ The cheap swap to `map { $0.0 }` was kept — both forms compile and churn is not free —
  but the REASON given for it at the time was wrong, and that is recorded rather than quietly
  dropped.

⛔ **A `.md` file in THIS directory triggers both gates.** Their `paths:` filters list
`Tests/**` — the filter matches a PATH, not a source extension — so editing this very file
starts a full `build-for-testing` on a macOS runner. #538's commit message claimed "neither
gate triggers" because the change was documentation; it touched `Tests/CISmoke/CLAUDE.md` and
both gates ran. The rule that IS true, and the one `docs/CLAUDE.md` states for its own tree:
a commit touching only `.claude/**`, `docs/**`, `scripts/**` or `memory/**` produces **no
run at all** — a fourth state that is neither green nor red. Read the filter, not the suffix.

Responses overflow the token cap; they are saved to a file. Parse runs with
`python3 scripts/gh-run-status.py <file>`.

### 5b. The workflow-level provenance (moved here from the root `CLAUDE.md`, #763)

⛔ **THIS BLOCK LIVED IN THE ALWAYS-LOADED `CLAUDE.md` AND WAS ITS THIRD COPY.**
`.claude/rules/context.md` §3 already declares §5 the one home of the gate discriminator and
says in as many words that it *"is not repeated here (#416)"* — while the root law file carried
10,019 B of the same decision, in a STALER form: it predates #667 (xcbeautify renders `error:`
as `❌`), #679, #738 and #739, so a session reading it followed a recipe §5 had already
corrected. **A duplicate is not merely redundant when the copies have different ages — the
always-loaded one wins by default and it was the wrong one.**

⚠️ **IT IS MOVED VERBATIM, NOT SUMMARISED**, because four facts live ONLY here and nowhere else
in the repo: the proof that `Xcode Compile Check` compiles `Sources/` alone (`project.yml`
`build.targets`), the `pr-check.yml`/#210 note that makes CI/CD's exclusivity a SIDE EFFECT
rather than the design, the #478 DerivedData cache-key defect, and the Clone-2 retraction.
Nothing above this line was rewritten; where it disagrees with §5, §5 is newer.

**⚠️ WELCHES GATE WAS BEWEIST — die Unterscheidung, die jede Session sonst neu falsch rät** (per Workflow-Lesung 2026-07-31; sie hat in dieser Woche zweimal einen Commit rot gemacht, den ein grüner Compile-Check schon abgesegnet hatte):

- **`Xcode Compile Check`** ist `xcodebuild build` auf Scheme `Echoelmusic` (`xcode-compile-check.yml:57`) — **NICHT** `build-for-testing`. Das kompiliert **nur `Sources/`**, und der Beleg steht im Schema selbst: `project.yml:379-382` gibt Scheme `Echoelmusic` unter `build.targets` **ausschließlich** `Echoelmusic`; `EchoelmusicTests` (Sources = `Tests/CISmoke`, `project.yml:304-310`) steht dort nur unter `test.targets`, und `xcodebuild build` baut die `build`-Targets. Ein grünes Compile-Check-Häkchen beweist über eine neue oder geänderte TESTDATEI also **nichts** — nicht einmal, dass sie kompiliert. (Der Schritt selbst ist ehrlich: er fängt `${PIPESTATUS[0]}` ab und gibt es weiter, trotz des `set +eo pipefail` davor. Sein Blindfleck ist die Reichweite, nicht die Maskierung.)
- **`Echoelmusic CI/CD Pipeline`** macht `build-for-testing` (`ci.yml:175`) **und** `test-without-building` (`ci.yml:190`), beide mit `set -o pipefail` und ohne `continue-on-error` (ein Kommentar bei `ci.yml:198-202` verbietet die frühere `|| cat`-Maske ausdrücklich). **Auf `push` ist es das EINZIGE Gate, das `Tests/CISmoke` kompiliert UND ausführt.** (⛔ Ohne das „auf `push`" war der Satz falsch: `pr-check.yml:106` baut dasselbe Scheme mit `build-for-testing` und `:129` würde es ausführen — auf PRs nach `main`/`develop`. Es kommt dort nie an, weil der Schritt dazwischen, `:118`, das nicht existierende Scheme `Echoelmusic-macOS` baut und den Job vorher tötet. Die Exklusivität ist also eine **Nebenwirkung von #210**, nicht der Entwurf; wer #210 repariert, muss diesen Satz mitziehen.)
- ⛔ **ZWEI ROTS, DIE GLEICH AUSSEHEN — und solange #396 lebt, ist das die einzige Unterscheidung, die zählt.** `Echoelmusic CI/CD Pipeline` meldet auf JEDEM Push `failure`, also sagt die Conclusion allein NICHTS. Im Job-Log stehen die beiden Fälle EINE Zeile auseinander und nirgendwo sonst: **`** TEST EXECUTE FAILED **` = #396** (kompiliert, Host stirbt beim Ausführen, harmlos) · **`** TEST BUILD FAILED **` = der BUILD ist gestorben** — ⛔ hier stand „= DEIN Commit", und das ist eine Fassung zu kurz, siehe den Punkt direkt darunter. Umgekehrt ist **`▸ Test build Succeeded`** der einzige Beleg, dass eine neue Testdatei überhaupt baut. Belegt am 2026-08-07 an `f489a6e`: `ASnappedValueIsLegalForItsRowTests.swift` fehlte `@testable import Echoelmusic`, neun „cannot find 'ScrubPrecision' in scope", Bundle tot — bei einer Conclusion, die von #396 nicht zu unterscheiden war. **Wer die Conclusion liest und aufhört, hat nichts geprüft.**
- ⛔ **UND DAS WAREN NICHT ZWEI ROTS, SONDERN DREI — der dritte sieht exakt aus wie der zweite und ist NICHT dein Commit.** `** TEST BUILD FAILED **` heißt „der Build ist gestorben", nicht „deine Datei kompiliert nicht". Belegt am 2026-08-07 an `998af71` (Lauf 31186349705, Job 92891930582, ganzer Job-Log 689 Zeilen): **4 `error:`-Zeilen, davon NULL mit einer Datei unter `Sources/` oder `Tests/`** — alle vier nennen `/Applications/Xcode_26.2.app/…/iPhoneSimulator26.2.sdk/…/_StoreKit_SwiftUI.framework/Modules/module.modulemap` gegen ein `.pcm` in `DerivedData/ModuleCache.noindex`: *„has been modified since the module file … was built: mtime changed"*. **Der Diskriminator ist deshalb EINE Frage: nennt IRGENDEINE `error:`-Zeile eine Datei aus dem Repo?** Null von vier → Infrastruktur. Die Antwort darauf ist ein erneuter Lauf, keine Code-Änderung — und wer stattdessen die eigene Scheibe debuggt, debuggt korrekten Code.
- ⭐ **Und es ist ein FLAKE, kein vergifteter Cache — gemessen, nicht vermutet, und die naheliegende Diagnose war meine erste.** Gegen den unmittelbar davor liegenden Commit derselben Reihe verglichen (`1118b55`, Lauf 31184026431, Job 92885354981): **gleiches Runner-Image `20260707.563`, gleicher Cache-Schlüssel `macOS-spm-<hash>-iPhone 17`, in BEIDEN Läufen „Cache restored from key" + „Cache restored successfully"** — und der eine druckt `▸ Test build Succeeded`, der andere zwei Minuten später `** TEST BUILD FAILED **`. Identische Eingaben, verschiedenes Ergebnis. **Und der Beweis kommt vom Commit DANACH:** `b06b8ca` (Lauf 31186573809) ist eine reine Prosa-Änderung ÜBER demselben Baum — dieselben drei `Tests/CISmoke`-Dateien, die `998af71` angelegt hatte — und sein „Build for Testing" ist `success`. Der Inhalt, den der rote Lauf angeblich nicht kompilieren konnte, kompiliert. **Ein `TEST BUILD FAILED` ist also erst dann eine Aussage über deinen Commit, wenn eine `error:`-Zeile eine Repo-Datei nennt** — sonst ist der billigste nächste Schritt ein leerer Folge-Commit, nicht eine Stunde Fehlersuche.
- ⚠️ **Der LATENTE Defekt daneben ist echt und founder-gated (#478):** `ci.yml:127` und `:349` cachen `~/Library/Developer/Xcode/DerivedData` — dort liegt `ModuleCache.noindex` — unter einem Schlüssel, der NUR `Package.swift`/`Package.resolved` hasht, also nichts über die Xcode- oder SDK-Version. Ein `.pcm`, das gegen ein älteres SDK gebaut wurde, wird damit auf einen Runner mit neuerem SDK zurückgespielt, und die Fehlanpassung ist STÄNDIG vorhanden: die zwei Zeitstempel derselben Meldung sind **`.pcm` 2026-07-20T05:58:14Z** gegen **modulemap 2026-07-28T05:57:08Z**, acht Tage auseinander — und BEIDE Läufe oben haben genau dieses `.pcm` zurückgespielt. Nur einer ist darüber gestolpert. Die Reparatur wäre eine Zeile (Xcode-/SDK-Version in den Cache-Schlüssel), liegt aber in `.github/workflows/**` → BERICHTEN, nicht editieren.
- ⛔ **Und meine eigene erste Lesung dieser Sache war falsch, in genau der Datei, die man dafür aufschlägt:** ich hatte notiert, `ci.yml` cache „nur `~/.swiftpm` und `.build`, DerivedData NICHT" — und daraus geschlossen, ein Cache könne über Läufe hinweg gar nicht vergiften. Zeile 127 sagt das Gegenteil, und sie stand die ganze Zeit da. Die SCHLUSSFOLGERUNG (nicht mein Commit) überlebt, die BEGRÜNDUNG nicht. **Lehre in der Familie dieses Absatzes: wer aus einer Konfigurationsdatei argumentiert, liest die Zeile, statt sich an sie zu erinnern** — dieselbe Klasse wie das abgelaufene `EchoelModalBank`-Rezept, nur in einer Datei, die ich für zu klein zum Nachschlagen hielt.
- ⭐ **UND #396 IST EIN TEILWEISER HOST-TOD, NICHT EIN TOTALER — das ändert, was ein Zyklus über einen neuen Wächter behaupten darf.** Der Log zeigt `NSMachErrorDomain Code=-308 "(ipc/mig) server died"` für EINEN Simulator-Clone, während **Clone 1 weiterläuft und einzelne `passed`-Zeilen druckt**. (⛔ **DIE RÜCKNAHME WAR SELBST FALSCH, und das ist die dritte Fassung dieses Satzes.** Sie lautete: „die erste Fassung schrieb ‚auf **Clone 2**' … nennt die Nummer des toten aber nirgends, die Ziffer war geraten". Sie steht sehr wohl im Log, nur nicht in der Fehlerzeile: der Umgebungs-Dump des gescheiterten Launches trägt `"RUN_DESTINATION_DEVICE_NAME" = "Clone 2 of iPhone 17"`, direkt über dem `Code=-308`. Nachgeschlagen an Lauf `31153418893` (`4787b8b`). **Clone 2 stirbt, Clone 1 läuft weiter** — die ERSTE Fassung war richtig, meine Korrektur hat eine belegte Ziffer zu einer geratenen erklärt, weil ich den Ausschnitt gelesen habe statt den Log. Lehre, verschieden von der Stale-Zahl-Lehre: **eine Rücknahme ist auch eine Behauptung und braucht dieselbe Messung wie das, was sie zurücknimmt** — „steht nirgends" ist eine Aussage über den GANZEN Log, nicht über die Zeilen, die man gerade vor sich hat.) Belegt am 2026-08-07 an `a5aafe2`: alle 10 Fälle von `OneDefinitionOfAParameterRangeTests` und alle 6 des Nachbarn stehen dort namentlich als `passed`, bei `** TEST EXECUTE FAILED **` als Gesamtverdikt. **Also ist „lief grün“ für einen neuen Wächter belegbar — man liest die Testnamen im Job-Log, nicht die Conclusion und nicht nur `▸ Test build Succeeded`.** Die schwächere Formulierung („kompiliert nachweislich, Ausführung durch #396 unbelegt“) war bis hierher richtig und ist ab jetzt zu schwach, wenn die Namen im Log stehen.
- ⛔ **UND DIE UMKEHRUNG DIESES GESETZES GILT NICHT — das fehlte in der ersten Fassung, und es ist die Hälfte, die eine Sitzung wirklich braucht.** Ein Testname IM Log beweist „gelaufen"; sein FEHLEN beweist gar nichts. Der Log trägt nur die Ausgabe, die der ÜBERLEBENDE Clone vor dem Tod des anderen noch geleert hat, und das ist ein Bruchteil des Bundles. Gemessen am selben Tag, `Tests/CISmoke` = **182 Dateien**: `5584ffd` (Job 92762010894, `original_length` 5263 Zeilen, also der GANZE Log, keine Kürzung) druckte **28 Suiten / 166 `passed`**, alle auf `Clone 1`; `4be555e` (Lauf 31144230149) druckte **19 Suiten** — DERSELBE Zweig, DIESELBE Scheibe, verschiedene Teilmengen. Der neue Wächter `AHeldFrameCannotResetTheHoldTests` steht in KEINEM der beiden, obwohl er in beiden nachweislich KOMPILIERT (`▸ Test build Succeeded`). **Die Zuteilung ist nicht deterministisch, also ist Neu-Laufen eine Lotterie und kein Beweisverfahren.** ⛔ **DIESER SATZ IST MIT #807 ÜBERHOLT, und zwar in der Begründung, nicht im Ergebnis:** die zwei verschiedenen Teilmengen sind zwei verschiedene `tail -200`, kein Zuteilungs-Würfel — über vier aufeinanderfolgende Läufe sind **133 von 135** Ergebniszeilen identisch. Neu-Laufen kauft trotzdem nichts, aber aus dem anderen Grund: das Fenster liegt immer am selben Ende des Logs. Siehe den #807-Block oben. Ehrliche Formulierung für einen Wächter ohne Treffer: „kompiliert nachweislich, Ausführung unbelegt" — nicht „grün", nicht „rot". ⚠️ Und der Erkennungs-Marker aus dem Absatz darüber ist NICHT immer da: `5584ffd` hat `** TEST EXECUTE FAILED **`, aber **null** `Code=-308` und **null** `server died` (`4be555e` hat beide). Der verlässliche Diskriminator bleibt `TEST EXECUTE FAILED` gegen `TEST BUILD FAILED`; die Mach-Zeile ist ein Bonus, kein Kriterium. Das ist die schärfste bisherige Fassung von #445.
- ⭐ **#396 HAT EINE ZWEITE FEHLERSIGNATUR, und wer nach der ersten greppt findet nichts und
  schliesst falsch** (gemessen 2026-08-24 an `bea1a83`, Job 97331641102). Der Absatz darüber
  nennt `NSMachErrorDomain Code=-308 "(ipc/mig) server died"`. Dieser Lauf hat **null** solche
  Zeile und ist trotzdem exakt dieselbe Lage: der Umgebungs-Dump trägt wieder
  `"RUN_DESTINATION_DEVICE_NAME" = "Clone 2 of iPhone 17"`, und die Fehlerzeile lautet
  `Simulator device failed to launch com.echoelmusic.app` → `FBSOpenApplicationServiceErrorDomain
  Code=1` → `FBProcessExit Code=64 "The process failed to launch."` → `RBSRequestErrorDomain
  Code=5 "Launch failed."`, „denied by service delegate (SBMainWorkspace)". Clone 1 lief
  weiter und druckte 27 `passed`-Zeilen von `FieldAutoPlayArpTests`; **null** fehlgeschlagene
  Zusicherungen im ganzen Log. Also: Clone 2 stirbt entweder BEIM LAUFEN (`-308`) oder BEIM
  START (`Code=64`) — zwei Signaturen, eine Lage, und `** TEST EXECUTE FAILED **` ist bei beiden
  da. **Der Diskriminator bleibt `TEST EXECUTE FAILED` gegen `TEST BUILD FAILED`**, genau wie
  der Absatz darüber sagt; neu ist nur, dass die Bonus-Zeile in ZWEI Formen kommt.
  ⚠️ **Die Lehre ist die von #778/#779, eine Ebene tiefer:** eine Nadel, die aus dem WORTLAUT
  des letzten Vorfalls gebaut ist, ist eine Nadel für den letzten Vorfall. Wer hier
  `grep "server died"` fährt, bekommt 0 Treffer bei einem Lauf, der die Lage perfekt zeigt.
  `scripts/gh-test-verdict.py` ist davon NICHT betroffen — es prüft die beiden
  `** TEST … FAILED **`-Marker, nicht die Mach-Zeile, und hat diesen Lauf korrekt als
  `TEST EXECUTE FAILED: True / TEST FAILURES: 0` gemeldet. Das ist der Grund, warum
  `.claude/rules/context.md` §4 „hand-roll keine Nadeln" sagt.
- Konsequenz für die Sprache in jedem Status-Delta: „beide echten Gates grün" ist als Kurzform für „das blockierende Bundle lief" nur deshalb richtig, **weil CI/CD dabei ist**. Für eine reine Testdatei ist CI/CD allein maßgeblich; Compile-Check-grün allein heißt nur `Sources/`-grün.

---

## 6. What does NOT belong in this directory

- **The count chain.** The history of how many files live here lives in
  `memory/LEDGER_COUNTS.md` §A. Do not start a second one in this file; keep the commands in §0
  and derive the number. ⛔ This line said "a root-`CLAUDE.md` ledger" and #538 moved it — the
  chain was 5,599 lines and 80.2 % of a file that is loaded before every session, while the
  executable law it crowded out was 2.7 %. Nothing was deleted. A stale pointer here would be
  the #472 defect on the very rule that forbids a second chain.
- **A private comment stripper** (§2, #453).
  ⚠️ ONE recorded exception, and it is recorded HERE because the enforcing guard cannot see it:
  `TheStripperDoesNotKnowATripleQuoteTests` declares `tripleQuoteAwareCodeOnly` on purpose (#659).
  It is not a copy of the decision — it is the CONTRAST against which the shipped scanner is
  measured, and the only thing it is ever asserted on is WHICH FILES the two shapes disagree
  about, never what a file says. **It escapes `testNoUnlistedFileDeclaresItsOwnStripper` by
  accident**: that guard anchors on the literal `func codeOnly`, and
  `func tripleQuoteAwareCodeOnly` does not contain that substring. An exemption granted by a name-anchor is not an exemption, so it
  is written down where the law lives. A SECOND such helper needs the same paragraph or it is
  simply the thing this line forbids.
- **A second copy of a threshold** that a shipped type already owns (§2, #416).
- **A guard over a fact nobody can observe.** If neither behaviour nor source text can carry
  it, it is a device probe — register it as open instead of writing a scan that cannot fail.
