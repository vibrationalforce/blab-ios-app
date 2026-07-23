# Engineering Rules — apply to all code changes

These are general engineering-hygiene rules (founder 2026-07-23). They sit ALONGSIDE
the hard rules in `CLAUDE.md` and `.claude/rules/swift-audio.md` (audio-thread sanctity,
protected Rausch triad, no esoteric terms, branch discipline, Uncodixfy UI, `EchoelValueField`
for params) — where those are more specific, they win. This file adds the cross-cutting
"how we work" bar, not audio/Swift specifics.

## 1. Context & Architecture First
- Respect existing project patterns, caching mechanisms, and architecture. Reuse what
  exists (`EngineBus` is the one coupling spine) before adding.
- Do NOT refactor unrelated parts of the codebase, or introduce a new framework/library,
  without an explicit request. (Echoel ships ZERO external deps today — see CLAUDE.md.)
- Match current code style, conventions, and design paradigms — read the surrounding file
  first and write code that looks like it belongs.

## 2. Granular & Clean Code (No Slop)
- Keep diffs small, focused, and atomic — ONE Ralph-Wiggum slice per commit (this is
  already the loop). No multi-thousand-line monolithic outputs.
- Remove all debugging logs and dead code before committing. (`os_log` only where a log
  genuinely belongs; never `print`; nothing on the audio thread — see swift-audio.md.)
- Conventional Commits, one logical change per commit.

## 3. Edge Cases & Quality
- Never ship code that only handles the happy path.
- Explicitly handle: nil/optionals (guard-let, no force-unwrap), error boundaries,
  async timeouts/cancellation, division-by-zero and array-bounds guards, and the
  performance edge cases (thermal/battery/FPS — `AdaptiveQuality`/`ResourceGovernor`).
- Non-finite inputs (NaN/inf) at any DSP/bio boundary are an edge case, not an
  impossibility — sanitize at the boundary (the render-side `applyBioReactive` pattern).
- Prefer explicit, readable code over clever one-liners.

## 4. Architectural Justification
- Briefly explain *WHY* an architectural decision was taken — in the commit body, the PR
  description, and (for a significant/hard-to-reverse call) `decisions.csv` + `memory/`.
- For significant or hard-to-reverse moves, convene `the-council` first (it exists to
  catch the mistake before the commit); log the material decision so it is not
  re-litigated.

## Verification honesty
- State plainly whether a change is compile-verified (CI: Xcode Compile Check + CI/CD
  Pipeline) vs. device-verified. An audio-route / bio / UI-render change is NOT proven
  until a device run — say so rather than implying it is done.
