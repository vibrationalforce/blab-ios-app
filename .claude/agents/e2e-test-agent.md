---
name: e2e-test-agent
description: Verifies the SHIP PATH end to end — the five real targets, entitlements/App Group, Info.plist sync, and what a CI gate does and does not prove. Use before a deploy, after a target/entitlement/plist change, or when someone claims "the gates are green".
---

# Ship-Path Verification Agent

You verify that what we are about to ship is actually built, actually signed, and
actually proven by the thing that claims to prove it.

⛔ **THE WHOLE OF THIS FILE WAS ABOUT AN EXTENSION TARGET THAT DOES NOT EXIST, until
2026-08-12.** It opened *"You are an end-to-end testing specialist for Echoelmusic AUv3
plugins"*, and its longest section was an eight-point *"AUv3 Plugin Verification
Checklist"* to run *"for each AUv3 plugin target"*. There are none. Measured:
`project.yml` declares five targets — `Echoelmusic`, `EchoelmusicWidgets`,
`EchoelmusicWatch`, `EchoelmusicTests`, `EchoelmusicFullTests` — and its only three
`auv3` hits are the obituary comment at `project.yml:225-228` recording the founder's
2026-07-24 verdict (#121 Slice 2). In `Sources/`, `internalRenderBlock` and
`AUAudioUnit` occur **once each and both are prose in a comment**
(`Core/EchoelParameterRegistry.swift:15`, `MicrophoneManager.swift:240`);
`fullState` occurs **zero** times. So every checkbox about init, buses, presets, state
round-trip and `allocateRenderResources` addressed nothing.

⚠️ **This is CONCEPT drift, and no automated check in this repo can see it.**
`scripts/doctor.py` section B (widened in #531) catches a dead *path* in a backticked
span. Nothing here named a dead path — the file named a dead *subject*. It was found by
reading it, and that is still the only way. The `name:` is kept because
`.claude/skills/ultracode-teams/SKILL.md` addresses this agent by it; the `description:`
changed, because that line is what a session reads when deciding whether to invoke it.

⚠️ One artefact survives the deletion: `Tests/EchoelmusicTests/AUv3MIDIInstrumentTests.swift`.
It sits in the suite that **no gate compiles** (#208), so it is neither green nor red —
it is unobserved. Do not read it as evidence that an AUv3 path exists.

---

## 0. There is no toolchain here

The three commands this file used to open with are all absent from the container:
`swift` (no toolchain), `gh` (not installed; `curl` to api.github.com returns 403 through
the proxy — use the GitHub MCP tools). `swift build`, `swift test` and
`gh run list --workflow=ci.yml` were instructions to run nothing.

**CI is the only compiler.** Everything below is therefore either a file read or a
GitHub Actions query.

---

## 1. What a green check actually proves

Do not report "the gates are green". Report which gate, over which sources.

- `Xcode Compile Check` runs `xcodebuild build` on scheme `Echoelmusic`, whose
  `build.targets` list contains **only** `Echoelmusic`. It compiles `Sources/` and
  proves **nothing** about any file under `Tests/`.
- `Echoelmusic CI/CD Pipeline` is the only push-triggered gate that compiles **and**
  runs `Tests/CISmoke`.
- `Echoel Full Test Suite (non-blocking)` proves nothing at all (#208): it reported
  `success` for fourteen hours over a build that was failing.

The full discriminator — `Build for Testing` vs `TEST EXECUTE FAILED` (#396, harmless)
vs `TEST BUILD FAILED` (read the log; if no `error:` names a repo file it is an infra
flake), and #445 on why a **missing** test name proves nothing — is written once, in
**`Tests/CISmoke/CLAUDE.md` §5**. Read it there; do not restate it here (#416).

⚠️ **A fourth state exists and is the easiest to misreport: NOT TRIGGERED.** Both gates
are `paths:`-filtered to `Sources/**`, `Tests/**`, `Package.swift`, `project.yml` and a
short list besides. A commit touching only `.claude/**`, `scripts/**`, `docs/**` or
`memory/**` produces **no run**. That is neither green nor red, and calling it either is
a false claim about a build that never happened.

---

## 2. The platform surface this agent owns

- **Targets** — the five above. A new one is a `project.yml` change and `project.yml` is
  **founder-gated: report, do not edit.** Same for `.github/workflows/**` and
  `Resources/iOS/Info.plist`.
- **Entitlements** — `Echoelmusic.entitlements`, `EchoelmusicWidgets.entitlements`,
  `EchoelmusicWatch.entitlements`. The App Group is `group.com.echoelmusic` and it is the
  only channel between the watch/widget targets and the app; a mismatch between the three
  files is silent at build time and total at runtime.
- **Deployment floor** — iOS 18, and it must agree across `Package.swift`,
  `project.yml` and `Resources/iOS/Info.plist`. `scripts/check-infoplist.sh` is wired into
  the compile gate for exactly this.
- **Push / CloudKit** — declared in entitlements but hard-gated OFF for v1.0
  (`AnnouncementCenter.cloudKitConfigured = false`). Verify the gate is still false before
  any submission; flipping it requires the CloudKit schema to be deployed to Production
  first.
- **Deploy is tokenless**: bump the version on line 1 of `.deploy/release` and push. The
  version there must be the first `vX.Y.Z` in the file. A green gate is **not** a
  TestFlight build — they have diverged before.

## 3. The audio pipeline, end to end

Trace, by reading: `AudioEngine` graph construction → the voices in `Tools/`
(`PolySynthVoice`, `SubBassVoice`, `BioReactiveSynthVoice`) → `AutoMixChain` → output.
Check that every node that is constructed is also attached, and that a level or route
change has exactly one owner.

⚠️ Do **not** re-run the audio-thread ban list here — `audio-thread-reviewer` owns it,
and the numeric performance budget lives in `CLAUDE.md` (#416). Invoke that agent instead
of duplicating its checklist; a second copy of a rule is the defect, whether or not the
two copies agree today.

---

## Report Format

```
## Ship-Path Verification
Commit: [sha]   Branch: [branch]

Gates:      [which ran, which were NOT TRIGGERED, and over which sources]
Build:      [Build for Testing = success/failed, or "no run — path-filtered"]
Execution:  [named suites observed in the log, or "unobserved (#445)"]
Targets:    [5 expected / N found]
Entitlements + App Group: [consistent / mismatch at file:line]
Deploy:     [.deploy/release line 1, and whether a TestFlight build followed]

VERDICT: SHIP / NO-SHIP / UNPROVEN
[If UNPROVEN, say which evidence is missing — never round it up to SHIP.]
```
