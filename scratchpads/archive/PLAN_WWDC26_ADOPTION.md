# Plan: WWDC26 Framework Adoption (Progressive Enhancement on iOS 18 floor)

Date: 2026-06-16
Branch: claude/echoelmusic-app-feasibility-3rtwL (cut a dedicated `feat/wwdc26-*` branch per item)

## Context

Echoelmusic ships with an iOS 18 deployment floor (`project.yml`, `Package.swift`,
`Resources/iOS/Info.plist`). WWDC26 introduced four frameworks/feature sets that map
directly onto Echoel's identity as a **bio-reactive performance instrument**:
on-device LLM orchestration, on-device music analysis, deeper Siri/App Intents, and
richer SwiftUI GPU visuals.

CI builds with **Xcode 26.2 (iOS 26 SDK)**, so `@available(iOS 26, *)` code compiles
and links in CI today. The strategy is **strictly additive progressive enhancement**:
the iOS 18 floor stays; iOS 26 features light up behind `@available` / runtime
`if #available(iOS 26, *)` checks and `SystemLanguageModel`/session availability
probes. No floor bump. No new dependency (Foundation Models, MusicUnderstanding,
App Intents, SwiftUI shaders are all first-party SDK frameworks — TECH STACK
"one dependency only" rule is preserved).

### PRIVACY RED LINE (binding on every item below)
- Echoel's promise: **"biometrics stay on your device."**
- Foundation Models MUST run **on-device only**. Bio frames (`BioSampleFrame`),
  audio buffers, and derived bio-state MUST NOT be routed to Private Cloud Compute
  or any third-party model provider.
- Enforcement: only ever construct sessions against `SystemLanguageModel.default`
  (the on-device model). Never set a Private Cloud Compute / `useCase` server option
  or a third-party `LanguageModel` provider for any prompt that contains biometric
  or audio-derived content. Gate the entire feature off if the on-device model is
  unavailable rather than silently falling back to cloud.

### BRAND RED LINE
- Instrument framing only. No medical/clinical/diagnostic claims in any LLM prompt,
  system instructions, Siri phrase, or generated copy. Bio-state drives *musical*
  parameters (genre/key/mood/FX), never health advice.

---

## Verified API facts (from developer.apple.com, June 2026)

| Area | Framework | Confirmed entry points | On-device | Avail |
|---|---|---|---|---|
| LLM orchestration | `FoundationModels` | `SystemLanguageModel` (`.default`), `LanguageModelSession`, `@Generable`, `@Guide`, session `isAvailable` / model availability probe | Yes (`.default` = on-device Neural Engine model) | iOS 26 |
| Music analysis | `MusicUnderstanding` | `MusicUnderstandingSession(asset:)` and `(audioProvider:)`, `SessionResult` container, `KeyResult`/`RhythmResult`/`StructureResult`/`PaceResult`/`InstrumentActivityResult`/`LoudnessResult`, `KeySignature`(`tonic`/`mode`), `Tonic`, `Instrument`, `TimedValue<Value>`, `RangedValue<Value>`; loudness streamable via AsyncSequence | Yes (on-device, offline) | iOS 26 (assumed; needs confirm) |
| Siri / actions | `AppIntents` (base) + App Schemas | base: `AppIntent`, `AppShortcutsProvider` (iOS 16+); schemas: `@AppEntity(schema:)`, schema domains (e.g. `.messages.message`), `IndexedEntity` | n/a | base iOS 16+; schemas iOS 26 |
| SwiftUI visuals | SwiftUI (WWDC26 session 322) | `layerEffect()`, `colorEffect()`, `distortionEffect()`, `ShaderLibrary`, `Shader` (`.float`/`.float2`/`.image`), `TimelineView(.animation)`, `alignmentGuide()` | GPU | layer/color/distortion shaders iOS 17+; "advanced" patterns demoed at WWDC26 |

Confidence on exact symbol names: HIGH for FoundationModels and MusicUnderstanding;
HIGH for App Intents base; MEDIUM for the precise iOS-version gate on MusicUnderstanding
and on any net-new SwiftUI iOS-26 graphics symbol (see "Verification gaps" at end).

---

## Sequenced rollout (lowest-risk / highest-ROI first)

### ITEM 1 — App Intents / App Shortcuts / Siri  (NO iOS 26 required)
Highest ROI, lowest risk: base App Intents is **iOS 16+**, below our floor, so it ships
to 100% of users with no `@available` gymnastics. Pure additive surface over existing
EngineBus actions.

What it is: declarative actions the system (Siri, Spotlight, Shortcuts, Action Button)
can invoke. App Schemas (the iOS 26 piece) additionally make entities/actions
semantically understood by the rebuilt Siri.

Steps:
1. [ ] Create `Sources/Echoelmusic/Intents/EchoelAppIntents.swift`
   - Define `AppIntent` types backed by EngineBus / store calls:
     - `StartBioSessionIntent` → triggers the same path as WorksView session record
     - `KeepLastLoopIntent` → calls `LoopExporter` / `RetroCapture` keep-last action
     - `GenerateInGenreIntent` (param: genre string) → invokes Item-2 generator
       (guard: if iOS < 26 or model unavailable, perform a deterministic
       `SoundPrompt`-based fallback so the intent still does something on iOS 18)
   - Files touched: new file only; read-only reference to `Core/EngineBus.swift`,
     `Audio/LoopExporter.swift`, `Audio/RetroCapture.swift`, `DSP/SoundPrompt.swift`.
2. [ ] Create `Sources/Echoelmusic/Intents/EchoelShortcutsProvider.swift`
   - `AppShortcutsProvider` exposing the three intents with natural phrases
     ("start a bio session", "keep the last loop", "generate in <genre>").
3. [ ] (iOS 26 enhancement, separate commit) Adopt App Schemas where a media domain
   fits the loop/patch entity. Gate any schema-specific type with `@available(iOS 26, *)`.
   Keep base intents un-gated. ONLY adopt a schema if a real media/audio domain exists
   (verify domain names — `.messages` is confirmed; a media/music domain is NOT yet
   confirmed — see Verification gaps).
- @available: base intents NONE. Schema additions `@available(iOS 26, *)` only.
- Privacy: intents carry no biometric payload off-device; they call local engine actions.
- Risk: LOW. Effort: S (intents) + S (schemas, conditional).

### ITEM 2 — Foundation Models on-device bio-state orchestration  (iOS 26)
Highest differentiation; the "bio drives the brain of the instrument" story.

What it is: on-device LLM that, given a compact bio-state summary, proposes a musical
configuration (genre / key / mood / FX intensities). Output is consumed by the
existing modulation + patch layer — the model **suggests**, the engine **applies**.

Real API entry points: `SystemLanguageModel.default` (on-device), `LanguageModelSession`,
guided generation via `@Generable` struct with `@Guide` constraints so output is
type-safe (no free-text parsing).

Where it plugs in (exact paths):
- New `Sources/Echoelmusic/AI/BioMusicDirector.swift`
  - `@available(iOS 26, *)` `@MainActor` `@Observable` orchestrator.
  - Reads `EngineBus.latestBio` (HR/HRV/coherence/breath) → builds a *text-only,
    non-biometric-leaking* compact prompt (e.g. "calm, low arousal, steady" derived
    locally — never raw RR intervals or identifiers).
  - Defines `@Generable struct MusicDirection { @Guide(...) genre; key; mood; reverb; drive; ... }`.
  - Constructs `LanguageModelSession(model: .default)` ONLY. Hard-asserts on-device.
  - Calls into existing `Core/ModulationEngine.swift` / `Core/ModulationMatrix.swift`
    and `DSP/PatchLibrary.swift` / `DSP/SynthPatch.swift` to apply the suggestion.
- New `Sources/Echoelmusic/AI/OnDeviceModelGate.swift`
  - Single chokepoint: `static var isOnDeviceLLMAvailable: Bool` using
    `if #available(iOS 26, *)` + `SystemLanguageModel.default` availability probe.
    Every AI feature funnels through this so the privacy rule is enforced in one place.
- Wire-up: a button/route in `Studio/ComposeView.swift` (existing compose surface) that
  is only shown when `OnDeviceModelGate.isOnDeviceLLMAvailable`.
- Fallback (iOS 18 / model unavailable): route to deterministic `DSP/SoundPrompt.swift`
  so the feature degrades to today's on-device prompt mapping — no cloud.

- @available: `@available(iOS 26, *)` on the whole `AI/` directory's new types; call
  sites guarded by `OnDeviceModelGate`.
- Privacy: NEVER pass `BioSampleFrame` fields or audio buffers verbatim; pass only a
  locally-computed coarse adjective summary. Session bound to `.default` (on-device).
  No PCC, no third-party provider, ever. Off entirely if on-device model absent.
- Audio thread: orchestration is `@MainActor` control-plane only; it writes parameter
  *snapshots* that the audio thread reads — NO LLM call, alloc, or async on render path.
- Risk: MED (new framework, availability variance across devices). Effort: M.

### ITEM 3 — MusicUnderstanding analysis of imported audio  (iOS 26)
Strong instrument feature: analyze an imported loop/sample to extract key, tempo/beat
grid, structure, loudness — then align Echoel's sequencer/FX to it.

Real API: `MusicUnderstandingSession(asset: AVAsset)` for imported files (or
`(audioProvider:)` for live), `SessionResult` with optional `KeyResult` /
`RhythmResult` / `StructureResult` / `PaceResult` / `InstrumentActivityResult` /
`LoudnessResult`; `KeySignature.tonic`/`.mode`, `Tonic`, `Instrument`,
`TimedValue`/`RangedValue`; loudness available as an AsyncSequence stream.

Where it plugs in (exact paths):
- New `Sources/Echoelmusic/Audio/MusicAnalyzer.swift`
  - `@available(iOS 26, *)` async wrapper around `MusicUnderstandingSession(asset:)`.
  - Maps `KeyResult` → existing `DSP/TuningReference.swift` / patch key; `RhythmResult`
    (tempo) → `Core/ModulationEngine` tempo + `Sequencer` clock; `LoudnessResult` →
    cross-check against `DSP/EchoelLoudnessMeter.swift`.
- UI entry: extend `Studio/SampleBrowserView.swift` (per-pad sample import already
  exists) with an "Analyze" affordance shown only `if #available(iOS 26, *)`; on import,
  offer "match tempo/key to this sample".
- Sequencer alignment: feed detected beat grid into the existing pattern/clock
  (`Sources/Echoelmusic/Sequencer/`).
- Fallback (iOS 18): import works as today; analyze affordance simply hidden.

- @available: `@available(iOS 26, *)` on `MusicAnalyzer` + the SampleBrowser affordance.
- Privacy: on-device/offline per Apple; imported audio stays local. Still route through
  `OnDeviceModelGate`-style availability check (own probe, since it is a different
  framework). No network.
- Audio thread: analysis is async/off-thread; only the resulting scalar tempo/key
  snapshots reach the engine — never call the analyzer from the render path.
- Risk: MED (iOS-version gate for MusicUnderstanding needs confirmation; large-file
  analysis time → must be async with progress + cancel). Effort: M.

### ITEM 4 — SwiftUI advanced graphics effects for bio visuals  (mostly iOS 17+, enhance on iOS 26)
Polish/ROI item; visuals are the "multidimensional" surface.

What it is: GPU shader effects (`layerEffect`/`colorEffect`/`distortionEffect` + Metal
`ShaderLibrary`) driven by `TimelineView(.animation)` and bio snapshots, replacing/
augmenting the current pure-`Canvas` renderer.

Where it plugs in (exact paths):
- `Sources/Echoelmusic/Studio/BioVisualView.swift` — currently pure Canvas+TimelineView
  reading `bus.latestBio`. Add an optional shader path: coherence→hue colorEffect,
  breath→domain-warp `layerEffect`, heart pulse→distortion, all driven by the same
  flash-safe ≤2 Hz timing it already enforces.
- New shader source `Sources/Echoelmusic/Studio/Shaders/BioVisualEffects.metal`
  (stitchable functions referenced via `ShaderLibrary`). Note existing Metal lives under
  `Video/Shaders/`; keep new visual shaders beside the view or under Studio — confirm
  `project.yml` resource globbing picks up the new `.metal` (no Info.plist/CI change
  without approval; if a build-config change is needed, STOP and ask).
- Gate the richest WWDC26-only patterns with `if #available(iOS 26, *)`; baseline
  shader effects (iOS 17+) ship under the floor; pure-Canvas remains the ultimate
  fallback so the view never renders blank.

- @available: baseline shaders un-gated (≥ floor); WWDC26-specific patterns
  `@available(iOS 26, *)`. Always keep the Canvas fallback.
- SAFETY: preserve the existing FlashGuard / ≤3 Hz WCAG limit and Reduce Motion
  handling already in `BioVisualView` + `Studio/FlashGuard.swift`. Shaders must obey
  the same clamps. (Run bio-safety-reviewer.)
- Privacy: visuals read local snapshots only.
- Risk: LOW–MED (visual regressions, flash-safety). Effort: M.

---

## Risks
- On-device model availability varies by device/region/Apple Intelligence toggle →
  Mitigation: single `OnDeviceModelGate` chokepoint; feature hidden + deterministic
  fallback when absent. Never cloud-fallback.
- Accidental PCC / third-party routing of bio data → Mitigation: bind every session to
  `SystemLanguageModel.default`; add a unit test asserting no non-default provider is
  constructed in `AI/`; code-review gate.
- MusicUnderstanding iOS-version / analysis-latency assumptions unconfirmed →
  Mitigation: verify version in SDK headers; run analysis async with cancel.
- Flash-safety regression from shaders → Mitigation: bio-safety-reviewer + keep
  FlashGuard clamps; Canvas fallback.
- Resource/build-config drift (new `.metal`, new dirs) → Mitigation: `Intents/`, `AI/`,
  `Studio/Shaders/` are net-new; CLAUDE.md only pre-approves `Sequencer/`/`Stream/`/
  `Studio/`. STOP and request approval before adding `Intents/` and `AI/` top-level
  dirs (or nest under an approved dir). Do not edit `project.yml`/Info.plist/CI
  without explicit approval.

## Dependencies
- Xcode 26.2 / iOS 26 SDK in CI (already present per testflight.yml) — confirmed.
- Approval needed for new top-level source dirs `Intents/` and `AI/` (not in the
  CLAUDE.md allow-list). Item 4's `.metal` resource globbing must be verified.
- Item 1's `GenerateInGenreIntent` depends on Item 2 for the iOS 26 path (has iOS 18
  deterministic fallback, so Item 1 can ship first independently).

## Test Strategy (per item)
- Item 1 (Intents): unit-test intent `perform()` against a mock EngineBus (action
  fired, correct loop kept, genre routed). Manual: Shortcuts app + Siri phrase smoke
  test on device. No new CI target.
- Item 2 (Foundation Models): unit-test `OnDeviceModelGate` returns false on iOS < 26;
  unit-test the bio→adjective summarizer is deterministic and leaks no raw biometric
  fields; unit-test `@Generable` decode of a canned `MusicDirection`; **privacy test:
  assert sessions are only built with `.default`**. Device test on Apple-Intelligence
  capable hardware. Add to existing test suite (BusinessTests/IntegrationTests style).
- Item 3 (MusicUnderstanding): unit-test `MusicAnalyzer` mapping (KeyResult→TuningReference,
  RhythmResult tempo→clock) with a fixture `SessionResult`; integration-test import→analyze
  →apply on a short bundled AVAsset; assert async/cancel path. Cross-check loudness vs
  `EchoelLoudnessMeter`.
- Item 4 (Shaders): snapshot/visual test BioVisualView renders on iOS 18 (Canvas) and
  iOS 26 (shader) paths; bio-safety-reviewer for ≤3 Hz + Reduce Motion; assert Canvas
  fallback when shader compile unavailable.
- All items: `swift build` must pass with `-warnings-as-errors`; run audio-thread-reviewer
  on Items 2/3 (confirm zero render-path involvement); concurrency-reviewer on the new
  `@MainActor @Observable` types.

## Rollback
- Each item is a separate `feat/wwdc26-*` branch + isolated new files; revert the commit.
- All iOS 26 paths are behind `@available` / runtime gates + fallbacks, so reverting an
  item leaves iOS 18 behavior intact. No floor change to undo. No dependency to remove.

---

## Verification status (docs vs. needs-session-video)

Verified from developer.apple.com docs/sessions:
- FoundationModels: `SystemLanguageModel(.default)`, `LanguageModelSession`, `@Generable`,
  `@Guide`, on-device-only via `.default`; iOS 26. (apple-intelligence guide + dev docs)
- MusicUnderstanding: framework name, `MusicUnderstandingSession(asset:)`/`(audioProvider:)`,
  `SessionResult` + the six `*Result` types, `KeySignature`/`Tonic`/`Instrument`,
  `TimedValue`/`RangedValue`, on-device/offline, imported + live. (WWDC26 session 253)
- App Intents base (`AppIntent`, `AppShortcutsProvider`) iOS 16+; App Schemas exist with
  domains, `@AppEntity(schema:)`, `IndexedEntity`. (WWDC26 sessions 240/343/344)
- SwiftUI graphics: `layerEffect`/`colorEffect`/`distortionEffect`, `ShaderLibrary`,
  `Shader` (`.float`/`.float2`/`.image`), `TimelineView(.animation)`, `alignmentGuide`.
  (WWDC26 session 322)

Needs a session video / SDK header to confirm before coding:
- Exact iOS-version availability annotation for `MusicUnderstanding` symbols (assumed iOS 26).
- Whether an App Schema **media/music domain** exists (only `.messages` confirmed); if
  none fits loops/patches, Item 1 stays base-intents-only.
- Precise mechanism (if any) to *assert/force* on-device and forbid PCC at the session
  level vs. relying on `.default` being on-device (confirm in "Adding server-side
  intelligence with Private Cloud Compute" doc + session "What's new in Foundation Models").
- Any net-new iOS-26-only SwiftUI graphics symbol beyond the iOS 17 shader trio
  (session 322 transcript showed no new symbol names).

Sources:
- https://developer.apple.com/videos/play/wwdc2026/253/ (Music Understanding)
- https://developer.apple.com/wwdc26/guides/apple-intelligence/ (Foundation Models)
- https://developer.apple.com/videos/play/wwdc2026/240/ (App Schemas)
- https://developer.apple.com/videos/play/wwdc2026/343/ , /344/ (advanced App Intents)
- https://developer.apple.com/videos/play/wwdc2026/322/ (SwiftUI advanced graphics)
- https://developer.apple.com/documentation/FoundationModels/
