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

---

## 5. Did it actually run?

`mcp__github__actions_list` → `list_workflow_jobs`, `workflow_jobs_filter {"filter":"latest"}`.

- Step **"Build for Testing" = `success`** ⇒ this bundle **compiles**. That is the claim a
  compile-only gate can support; `Xcode Compile Check` builds `Sources/` **only** and proves
  nothing about a test file.
- `** TEST EXECUTE FAILED **` = **#396**, founder-gated, harmless — a simulator clone dies
  mid-suite. CI/CD reports `failure` on **every** push because of it, so the conclusion alone
  says nothing.
- `** TEST BUILD FAILED **` ⇒ read the log. **Does any `error:` line name a repo file?** If
  not, it is an infrastructure flake (stale module cache) — re-run, do not debug your slice.
- **#445:** a test name **in** the log proves it ran. Its **absence proves nothing** — the
  surviving clone flushes a non-deterministic subset. Honest wording for an unobserved guard:
  *"kompiliert nachweislich, Ausführung unbelegt."* Never "green", never "red".

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
- **A second copy of a threshold** that a shipped type already owns (§2, #416).
- **A guard over a fact nobody can observe.** If neither behaviour nor source text can carry
  it, it is a device probe — register it as open instead of writing a scan that cannot fail.
