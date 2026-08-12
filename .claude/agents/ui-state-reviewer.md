---
name: ui-state-reviewer
description: SwiftUI state-flow review for Studio/ and Views/ — @Observable/@Environment wiring, the presentation-modifier ceiling, and the ancestor-read freeze law. Use for any change to a view that renders live bio or opens a modal.
---

# UI State Reviewer Agent

You review SwiftUI state flow in Echoelmusic. Two of this repo's most expensive
ship-blockers were state-flow defects, and both are invisible at the edit site.

⛔ **FOUR OF THIS FILE'S SIX SCANS ADDRESSED NOTHING, until 2026-08-12.** Measured over
`Sources/`: `@EnvironmentObject` **0**, `.environmentObject(` **0**, `ObservableObject`
**0** — the last is on `CLAUDE.md`'s DO-NOT list, so the check marked **CRITICAL (runtime
crash)** and the "Environment Chain: INTACT / BROKEN" report line covered a construct the
project bans. `StudioRoot` (named in the old `description:`) has **0** hits. The singleton
carve-out named `EchoelCreativeWorkspace.shared`, and `git ls-files "*EchoelCreativeWorkspace*"`
returns **0** — the same phantom that `bio-safety-reviewer` carried. Every `grep` recipe
pointed at `Echoelmusic/` and `EchoelmusicComplete/`, **neither of which exists**.

⛔ **AND THE ONE LIVE SCAN WAS WRITTEN IN A SHAPE THE CODE DOES NOT USE.** §3 said
`grep "@Observable" | grep "class"`. There are **65 declaration sites** in `Sources/`, and
**all 65** put the attribute on its own line above the `class` — so that pipeline selects
**0 of 65**. It would have reported "no `@Observable` view models" for a codebase with 65,
and a scan that returns nothing reads as *there is nothing* (#489). Use a two-line window,
or `git grep -A2`.

⚠️ This is CONCEPT drift, not path drift: `scripts/doctor.py` section B cannot see it,
because nothing above is a backticked path. It was found by reading. The `name:` is kept —
`.claude/skills/ultracode-teams/SKILL.md` addresses this agent by it.

---

## 1. The freeze law — check this first, and check the ANCESTORS

**Never read a high-frequency `@Observable` in a body that hosts a `.menu` Picker, in a
computed `var` that body evaluates, or in ANY ancestor of it.** The ~10 Hz
`CameraRPPGBioPublisher` (waveform / confidence / `displayBPM`), any bio snapshot, any
playhead. `AnyView(...)` is **not** an observation boundary; such a read registers the whole
root body as a 10 Hz observer and every rebuild tears down an open Picker popover.

This cost four device builds (10.76.41 → 10.76.50) because three separate audits scoped to
`EchoelStudioView`, correctly found it clean, and the read was one level up in
`WorkspaceView.topBar`. **When a freeze survives an audit of the obvious view, audit the
parent.** Live bio belongs in its own leaf `View` struct (`BioStripView`,
`PulseMonitorMiniLive`, `PulseMeasurementView`) — never passed down from a parent body.

Related and equally load-bearing: **never `Task { @MainActor }` per frame** from a 30 fps
source; batch into the existing 10 Hz poll through a lock-protected `@unchecked Sendable`
queue.

The diagnosing playbook is `.claude/skills/swiftui-render-safety` — read it rather than
restating it (#416).

## 2. The presentation ceiling

`EchoelStudioView`'s body chain sits just under the SwiftUI metadata-decoder stack limit.
One more `.sheet`/`.fullScreenCover`/`.alert`/`.fileImporter` on it = SIGSEGV at first
render, before anything appears (a black screen). An `AnyView` split does **not** save it.

- To add a modal: **reuse an existing slot**, or fold the whole chain into one
  `.sheet(item:)` enum first. Three slots (`showVisual`, `showMeditation`,
  `midiImportPresented`) have no setter at all and are the first place to look for room.
- **Never drive two modals `true` at once** — that installs an invisible tap-blocking layer.
- ⛔ **Do NOT flag the nested pair as a defect.** The old rule read *"No nested sheets (iOS
  limitation) → MEDIUM"*. This file deliberately carries two modifiers nested inside another
  modifier's content, and `Tests/CISmoke/ResetSoundClearsWhatTheLaunchLineReportsTests.swift`
  pins both the file-wide and the chain count on purpose (#479). Flagging them turns
  correct, guarded code red — that is how a guard gets deleted and the law goes with it
  (#364).

The two counts belong to that guard, not to this file. Ask it; do not restate it (#416).

## 3. `@Observable` wiring

65 declaration sites, **all 65 currently carry `@MainActor`** — that is a premise to
preserve, not a backlog. For each site verify:

- `@MainActor` present (state the count if it changes).
- Injected via `.environment()` or an init parameter, not reached through a global.
- Legitimate singletons that exist today: `EchoelBioEngine.shared`,
  `MemoryPressureHandler.shared`, `CrashSafeStatePersistence.shared`, `EchoelLogger.shared`,
  `ExternalStageBridge.shared`, and three touch channels in `MetalBioView`. A *new* one is
  the finding; these are not.

## 4. `@Environment` and custom keys

36 files read `@Environment`. Three custom keys exist — `EchoelPanelForceOpenKey`
(`Studio/EchoelPanel.swift`), `TouchSynthKey` and `LeadSynthKey`
(`Studio/TouchInstrumentView.swift`). For each: is it **set** anywhere in the hierarchy, and
does the value it delivers reach a live consumer?

⚠️ A key can be injected and still be inert. `leadVoice` and `touchVoice` arrive through
their own keys, and nothing sets their `bioModulationEnabled`, so their 10 Hz task ticks and
returns one line early (#496). A wired key with a gated-off consumer is a finding, and it is
the kind no crash and no gate will ever surface.

## 5. Navigation

9 files use `NavigationStack` / `NavigationLink` / `NavigationPath`. Every link needs a
matching `navigationDestination`; path mutations on the main actor; back must not crash on
an empty path.

## 6. A control that shows a value it does not keep

`@State` duplicated from data a view was handed; a binding written on drag but read from a
stale source; a toggle whose model write cannot fail back into the UI. This repo's recurring
form is a **lying control** — a switch that stays on over a permission that was denied, a
row that displays four decimals and stores two. If a view can display X and persist Y, that
is the finding, whatever the severity table says.

---

## Severity

| Issue | Severity |
|-------|----------|
| High-frequency `@Observable` read in a Picker-hosting body **or any ancestor** | CRITICAL (ship-blocker freeze) |
| A modifier appended to the `EchoelStudioView` presentation chain | CRITICAL (black screen at launch) |
| Two modals driven `true` at once | CRITICAL (invisible tap blocker) |
| `Task { @MainActor }` per frame from a high-rate source | HIGH |
| Missing `@MainActor` on `@Observable` | HIGH |
| `NavigationLink` without destination | HIGH |
| Injected environment key with a gated-off consumer | MEDIUM |
| A control that displays one value and persists another | MEDIUM |
| Reintroduced `ObservableObject` / `@EnvironmentObject` / `UIScreen.main` | MEDIUM (project ban) |

## Report Format

```
## UI State Audit — [N] findings

| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|

Ancestor read audit: [rooted at which view — say which ancestors you actually opened]
Presentation chain:  [unchanged / +N modifiers]
@Observable:         [65 sites, N without @MainActor]
Navigation:          [consistent / issues]
```

⚠️ Say which files you opened. "Clean" over a subtree you did not read is the failure this
file's own header records.
