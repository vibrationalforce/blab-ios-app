# Plan: Modularize monolith into SwiftPM targets (leaf-first, always shippable)
Date: 2026-06-20
Branch: claude/piano-roll-clip-view-wozlie (open dedicated branch per cycle)

## Context
The app is ONE SwiftPM target (`Echoelmusic`, ~133 Swift) + `EchoelmusicAUv3`
app-extension that compiles `Sources/Echoelmusic/DSP/` + 2 Core files directly
(no module). Goal: carve folders into modules with COMPILER-ENFORCED boundaries
(you cannot `import` what you don't depend on), leaf-first so each cycle ships.

## Measured import graph (grep over `import` + symbol refs, 2026-06-20)
| Folder | SwiftUI | UIKit | Other notable | Purity |
|---|---|---|---|---|
| DSP/ (24) | 0 | 0 | Foundation + Accelerate ONLY | PURE. EngineBus ref is a comment only. |
| Bio/ (15) | 0 | 0 | Foundation, AVFoundation, HealthKit, Combine, Observation | depends only on Core value types (BioFrame/BioEvent, clamped) |
| Core/ (28) | 0 | 1 | Foundation, Observation + impure outliers: StoreKit (EchoelStore), UIKit/AppKit (MemoryPressureHandler), WidgetKit (BioFeedbackPublisher), FoundationModels (OnDeviceModelGate), AVFoundation (NumericExtensions) | bus + value types PURE; outliers must move |
| Audio/ (11) | 0 | 0 | AVFoundation, Accelerate, CoreMIDI, AudioToolbox | domain |
| Sequencer/ (20) | 0 | 0 | Foundation, AVFoundation, FoundationModels | domain |
| Sync/ (5) | 0 | 0 | Foundation, Network, Observation | domain (OSC/ADM/MIDI net) |
| Tools/ (3) | 0 | 0 | Foundation, AVFoundation, Observation | domain |
| Stream/ (0) | — | — | empty (RTMP = roadmap) | n/a |
| Views/ (2) | 2 | 0 | SwiftUI, MetalKit, simd | UI |
| Studio/ (27) | 14 | 1 | SwiftUI, AVFoundation, AppIntents, CoreHaptics, UI types | UI (root) |

**Key facts:**
- DSP is genuinely pure → already proves the AUv3 split is viable.
- Protected triad (`BioEventGraph`, `HilbertSensorMapper`, `BioSignalDeconvolver`)
  imports Foundation only. `BioEventGraph` *emits* `BioEvent`, a value type defined
  in `Core/EngineBus.swift` → Bio must depend on Core (one-directional, fine).
- `Core/EngineBus.swift` (bus + `BioFrame`/`BioEvent` + `SPSCQueue.swift`) is pure
  Foundation+Observation → clean anchor for `EchoelCore`.
- No reverse violations found: Core does NOT import Bio/DSP; DSP does NOT import
  Studio. The only cross-layer noise is in COMMENTS, not code.
- AUv3 needs: all of DSP/, plus `Core/BioFeedbackManager.swift` + `Core/NumericExtensions.swift`.

## Target dependency graph (arrows = "depends on")
```
        EchoelmusicApp (executable/app target — Studio/ + Views/ + @main)
                 │
     ┌───────────┼───────────┬───────────┬──────────┐
     ▼           ▼           ▼           ▼          ▼
 EchoelUI    EchoelAudio  EchoelSeq   EchoelSync  EchoelVideo/Stream(later)
     │           │           │           │
     └─────┬─────┴─────┬─────┴─────┬─────┘
           ▼           ▼           ▼
       EchoelBio   EchoelDSP   (domains → Core)
           │           │
           └─────┬─────┘
                 ▼
            EchoelCore   ← bus, SPSCQueue, value types, logger, NumericExtensions, BioFeedbackManager
                 │
                 ▼  (depends on nothing but Foundation/Accelerate/Observation)

EchoelDSP  → depends on NOTHING (Foundation+Accelerate). Leaf.
EchoelBio  → depends on EchoelCore only (for BioFrame/BioEvent/clamped).
AUv3 target → depends on EchoelDSP + EchoelCore (was: raw file globs).
```
Rule enforced by SwiftPM: UI → domains → Core; DSP depends on nothing; Bio depends
only on Core. Any future `import EchoelUI` from DSP simply won't compile.

## Module roster (final shape)
1. **EchoelCore** — `Core/` PURE subset: EngineBus, SPSCQueue, NumericExtensions,
   ProfessionalLogger/EchoelLogger, BioFeedbackManager, value types (BioFrame/BioEvent),
   stores that are Foundation-only. Deps: none.
2. **EchoelDSP** — `DSP/` whole. Deps: none. (Accelerate+Foundation.)
3. **EchoelBio** — `Bio/` whole incl. protected triad. Deps: EchoelCore.
4. **EchoelSync** — `Sync/`. Deps: EchoelCore.
5. **EchoelAudio** — `Audio/`. Deps: EchoelCore, EchoelDSP.
6. **EchoelSequencer** — `Sequencer/` (+ Tools/ sample utils). Deps: EchoelCore, EchoelAudio.
7. **EchoelUI** — `Studio/` + `Views/` (design system + screens). Deps: all domains.
8. **EchoelmusicApp** — `@main` + thin glue. Deps: EchoelUI (transitively all).
9. (Roadmap) **EchoelStream/EchoelVideo** — empty/Stream now; carved when built.

## Cycles (one module per cycle, build→test→ship→loop; each ends CI-green)

### Cycle 0 — Prep (no extraction, must stay green)
- [ ] Confirm baseline: `swift build` + `swift test` green on branch.
- Test: existing 88 `@testable import Echoelmusic` tests pass.

### Cycle 1 — Extract **EchoelDSP** (lowest risk: zero deps, already AUv3-proven)
- Package.swift: add `.target(name:"EchoelDSP")` over a new `Sources/EchoelDSP/`
  (move `Sources/Echoelmusic/DSP/*`); main `Echoelmusic` target depends on it.
- project.yml: AUv3 stops globbing `Sources/Echoelmusic/DSP`; for SPM consumers it
  imports `EchoelDSP`. **AUv3 is an Xcode app-extension, not an SPM product** — keep
  it compiling the DSP *sources* via the SPM target's path OR add the moved files to
  the AUv3 `sources:` list (path `Sources/EchoelDSP`). Simplest: point AUv3
  `sources:` at the new `Sources/EchoelDSP` folder (same file-glob mechanism, new path).
- Add `import EchoelDSP` to the ~handful of app files that used DSP types.
- Files: move 24 files; edit Package.swift, project.yml (AUv3 path), DSP consumers.
- Test: `swift build`, `swift test`; run `EchoelmusicAUv3` compile_check scheme.
- Win: build-speed (DSP compiles once, parallel), hard boundary, AUv3 cleaner.

### Cycle 2 — Extract **EchoelCore**
- New `Sources/EchoelCore/` = PURE Core files (EngineBus, SPSCQueue, NumericExtensions,
  logger, BioFeedbackManager, BioFrame/BioEvent). **Leave impure outliers**
  (EchoelStore/StoreKit, MemoryPressureHandler/UIKit, BioFeedbackPublisher/WidgetKit,
  OnDeviceModelGate/FoundationModels) in the app target for now (Cycle 7 cleanup).
- main target + EchoelDSP-already-out + AUv3 depend on EchoelCore (AUv3 needs
  BioFeedbackManager + NumericExtensions → now from EchoelCore path/target).
- Add `import EchoelCore` across consumers (most of the app).
- Test: build + full test; AUv3 compile_check.

### Cycle 3 — Extract **EchoelBio** (incl. PROTECTED triad — move, do NOT edit)
- New `Sources/EchoelBio/` = `Bio/*`. Depends on EchoelCore.
- Triad files moved byte-identical; SKILL.md contracts unchanged. No logic edits.
- Add `import EchoelBio` to bio consumers (Studio Well, publishers wiring).
- Test: build + `swift test` (bio/triad tests), confirm triad untouched via `git diff --stat`.

### Cycle 4 — Extract **EchoelSync**
- `Sources/EchoelSync/` = `Sync/*`. Deps: EchoelCore.
- Test: OSC/ADM/MIDI net tests + build.

### Cycle 5 — Extract **EchoelAudio**
- `Sources/EchoelAudio/` = `Audio/*`. Deps: EchoelCore, EchoelDSP.
- Test: AudioEngineTests, MIDITests, RecordingTests + build.

### Cycle 6 — Extract **EchoelSequencer** (+ Tools)
- `Sources/EchoelSequencer/` = `Sequencer/*` (+ `Tools/*` sample utils). Deps: EchoelCore, EchoelAudio.
- Test: SequencerTests + build.

### Cycle 7 — Extract **EchoelUI** + relocate Core outliers; thin app
- `Sources/EchoelUI/` = `Studio/*` + `Views/*`. Deps: all domains.
- Move the impure Core outliers (StoreKit/UIKit/WidgetKit/FoundationModels) into
  EchoelUI or the app target where they belong (UI/lifecycle concerns).
- `Echoelmusic` target shrinks to `@main` + glue, depends on EchoelUI.
- Split test target: `EchoelmusicTests` → per-module test targets
  (`EchoelDSPTests`, `EchoelBioTests`, …) using `@testable import <Module>`.
  Keep an `IntegrationTests` target depending on the app.
- Test: full suite green; TestFlight full `build_only=false` run.

## Risks → Mitigation
- **Circular deps** (Bio needs BioEvent from Core; if Core ever needed Bio) →
  value types BioFrame/BioEvent stay in EchoelCore (they already do). Never move them to Bio.
- **`@MainActor` isolation across modules** → `@MainActor @Observable` types (EngineBus)
  must be `public` with `public` members; Swift 6 strict-concurrency is already on
  (`StrictConcurrency=targeted`). Mark cross-module APIs `public`/`Sendable` as moved;
  `nonisolated(unsafe)` audio mirrors must stay `public nonisolated(unsafe)`.
- **Access control churn** → moving a file makes `internal` symbols invisible cross-module;
  each cycle's main task is promoting the *used* surface to `public` (compiler lists them).
- **Resource bundles** → `Resources/` (Drums, Community, Assets) stays with the app/UI
  target via `.process("Resources")`; modules that load samples take paths/Data, not bundles
  (avoid `Bundle.module` proliferation). If a domain must own a resource, give it its own
  `resources:` and use `Bundle.module`.
- **AUv3 is Xcode-only (XcodeGen), not an SPM product** → it can't `import EchoelDSP` from
  SPM; keep feeding it the moved *source files* by path in project.yml `sources:`. Verify
  every cycle via the `EchoelmusicAUv3` compile_check scheme BEFORE merge.
- **project.yml app target sources** → still globs `Sources/Echoelmusic`; new
  `Sources/Echoel*` module folders must be added to the app target's `sources:` OR the
  app consumes them as SPM dependencies. Decide per cycle (SPM path preferred for the
  app scheme used by `swift build`; Xcode app uses XcodeGen groups).
- **-warnings-as-errors** → new module targets must carry the same swiftSettings
  (`-warnings-as-errors`, StrictConcurrency) so a quiet warning can't slip in.

## Dependencies / prerequisites
- Baseline green build+test (Cycle 0).
- HaishinKit stays the only external dep; lands in EchoelStream when built (not now).
- One dedicated git branch per cycle; merge to main only when CI + AUv3 compile_check green.

## Test strategy
- Per cycle: `swift build` (warnings-as-errors), `swift test` (relevant filter then full),
  `EchoelmusicAUv3` compile_check scheme. Cycles 1–3 also `git diff --stat` to prove the
  protected triad + moved files are byte-identical (move, not rewrite).
- Final cycle: split monolithic `EchoelmusicTests` into per-module test targets; full
  TestFlight `build_only=false` archive across platforms.

## Rollback
- Each cycle is one branch, one module, ≤ "move files + add target + add imports".
- Revert = drop the branch (files un-move, Package.swift/project.yml restore). Because
  the app stays a superset (depends on the new module), reverting any single cycle leaves
  the previous green state intact. No data/schema migration involved.
```

## Council gate
Significant, multi-file, hard-to-reverse → convene The Council before Cycle 1.
Default verdict expected: PROCEED leaf-first (DSP→Core→Bio), HOLD the protected-triad
move for explicit founder sign-off (Cycle 3) since it touches protected files even as a move.
