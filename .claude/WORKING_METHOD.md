# Working Method — How Sandbox-Claude + Owner (Mac/iPhone) Ship

**Single source of truth for the collaboration loop.** Short on purpose — if it grows past two screens, something is wrong. Project doctrine lives in `CLAUDE.md`; this file is only *how we work together*.

> Consolidated here from the former `.ai/WORKING_METHOD.md` (2026-07 cleanup). The sprint-specific parts (a past deadline, the never-built Beat/Record/Video/Share tabs, an old branch name, a since-deleted `PLAN_v10_TestFlight_Sprint.md`) were dropped as stale. The durable reality below still holds.

---

## Reality Check — no local toolchain

| Capability | Sandbox-Claude (this) | Owner (iPhone/Mac) | GitHub Actions (macOS runner) |
|---|---|---|---|
| Edit files | ✅ | ✅ | ✅ |
| `swift build` / `swift test` | ❌ no toolchain | ❌ (iPhone) | ✅ in CI |
| `xcodebuild archive` / `fastlane pilot` | ❌ | ❌ | ✅ (`testflight.yml`) |
| Trigger workflow | ✅ `bash scripts/check-testflight.sh dispatch` | ✅ GitHub web | n/a |
| Read PRs/issues/commits | ✅ `mcp__github__*` | ✅ web | ✅ |
| Real device test | ❌ | ✅ TestFlight | ❌ |

**Implication:** the build oracle is **CI + device**, not a local build. Every code change reaches truth by one path: push → CI verifies on macOS runner → TestFlight (or an error log the owner pastes back). This is stricter than a normal loop — it rewards small focused commits and punishes speculative refactors.

---

## The Loop (one cycle = one feature or fix)

1. **PICK** the next item (roadmap / audit / device log).
2. **WRITE** one feature OR one fix, minimal change (≤3 files where possible).
3. **COMMIT** conventional prefix, one logical change.
4. **PUSH** to the current dev branch (never `main`).
5. **VERIFY** — CI `build_only: true` first; only after green, `build_only: false` to ship to TestFlight.
6. **DEVICE TEST** — owner confirms on TestFlight (the only oracle for audio/Metal/rPPG).
7. **LOG** — update `scratchpads/SESSION_LOG.md` with commit + outcome.
8. **REPEAT.**

**Hard rules:** ONE feature/fix per cycle, no batching. Tests in the same commit as the feature. Red CI = drop everything until green.

---

## Source-of-Truth Map

| Concern | File |
|---|---|
| Project doctrine | `CLAUDE.md` (read FIRST every session) |
| Working method | `.claude/WORKING_METHOD.md` (this file) |
| Decisions | `memory/decisions.md` + `decisions.csv` |
| Session history | `scratchpads/SESSION_LOG.md` |
| Audio-thread rules | `.claude/rules/swift-audio.md` |
| User profile | `memory/user.md`, `people.md`, `preferences.md` |
| Public README | `README.md` |

Anything not in this map is either obsolete or should be merged into one of these files.

---

## Commit Conventions

```
<type>(<scope>): <imperative summary, ≤70 chars>

<optional body — what & why>
```

Types: `feat · fix · refactor · test · docs · chore · perf`. One change per commit; a second concern is a second commit.

---

## What to Never Do

- Touch `BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver` (PROTECTED)
- Modify `Info.plist`, `*.entitlements`, `.github/workflows/*.yml`, `Package.swift`, or `project.yml` target membership without naming it explicitly (and, for CI/Info.plist, asking first)
- `--no-verify`, `--amend` on a published commit, or force-push a shared branch
- Push directly to `main`
- Add a dependency without logging the decision in `memory/decisions.md`
- Create a new top-level dir under `Sources/Echoelmusic/` beyond the approved set
- Re-introduce bio-reactive auto-play in the main flow (launch silence is a rule)
