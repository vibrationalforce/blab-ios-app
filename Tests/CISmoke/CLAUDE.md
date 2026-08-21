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

It checks the two shapes whose needle MUST exist — `XCTUnwrap(… .range(of: "…"))` and
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
  ⚠️ **AND THE LOG IS ONE JSON BLOB WITH ESCAPED NEWLINES.** `get_job_logs` writes
  `{"logs":[{"logs_content":"…\n…"}]}` to the overflow file, so a plain `split("\n")` yields
  ONE line and every per-line filter silently returns nothing while `count()` on the raw text
  still works. That is why the first reading showed "0 failure lines" next to correct counts:
  two different bugs agreeing on a wrong answer. `json.loads` first, then split.
  **Both halves are closed in `scripts/gh-test-verdict.py`** — point it at the overflow file:
      python3 scripts/gh-test-verdict.py <file>
  It prints build-for-testing, the two banners, the count of tests OBSERVED PASSING, every
  compile-error line and every failing test by name; exit 1 if anything failed. Extend that
  script rather than writing a fourth ad-hoc needle set.
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
