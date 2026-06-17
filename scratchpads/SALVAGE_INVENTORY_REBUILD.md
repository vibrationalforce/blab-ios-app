# SALVAGE → REBUILD INVENTORY (full history laser-scan)

_Date: 2026-06-17 · Repo: Echoelmusic (formerly "blab" — renamed, history preserved
from the restart commit `2c85bb4`; the big cleanup `cf21ff3` removed ~2000 LOC of
deprecated modules). Founder directive: **go through the history, but rebuild everything
NEW, stable, future-fit** — mine the IDEAS, don't restore old code verbatim._

**Honest correction:** "VideoWeaver" / "VisualForge" were concept NAMES in docs/marketing
at the restart — never real Swift files. The deep pre-restart implementation did NOT
survive into git. What IS recoverable is the code below.

---

## TIER A — ADOPT (rebuild new on the stable EngineBus foundation; on-vision)

| Idea (history source) | What to rebuild (new) | Dimension | Effort | Notes |
|---|---|---|---|---|
| **Bio-reactive visual engine** — `Video/Shaders/VisualRendererKernels.metal` (5 GPU kernels: **Cymatics/Chladni**, Mandala, …, coherence/HR-driven, <2 ms/frame) + deleted `BioVisualRenderer.swift` | A clean Metal renderer wired to EngineBus snapshot, FlashGuard-clamped (≤3 Hz), Reduce-Motion, as immersive Visual depth on top of the live MetalBioView | Light/Visual | M | Science-visual (Cymatics = sound made visible), NOT esoteric. The honest realization of the "VisualForge" intent |
| **SequencerAccessibility** (`Studio/SequencerAccessibility.swift` + test) — pure VoiceOver label builders | Restore as pure strings + tests; wire when the clips/arrange UI lands | Data/A11y | S | Accessibility-first = core brand |
| **Settings surface** (`Views/SettingsView.swift`, deleted) | A clean Settings sheet: SkillLevel, Kammerton, safety toggles, sources — pairs with the SkillLevel pull-through | UX | S | Future-fit home for the role/level dial |

## TIER B — WATCH (rebuild when that dimension's cycle comes)

| Idea (history source) | Rebuild trigger | Dimension |
|---|---|---|
| **CloudKit personal sync** — `Core/CloudSync.swift` (Phase-0 foundation, tested, dormant, unwired) | When cross-device project sync is wanted; needs iCloud entitlement. Personal sync only — NOT the parked "accounts/community" pivot | Data |
| **One-view Clips / Arrangement UI** — models already salvaged; `ClipView/ArrangementView/ClipsTab` deleted (old multi-tab) | Producer tier of SkillLevel; rebuild as ONE-view surface (never new tabs) hosting LaunchQuantizer/ArrangementPlayer | Sound |
| **Sessions/Works UI** — `SessionRecorder` salvaged; `SessionGridView/SessionHistoryView` deleted | Pro tier; clean bio-session list/history surface | Body |
| **Short-form video render** — `Video/ShortContentRenderer.swift` (deleted, 416 LOC) | Video stays ROADMAP per vision-gate; rebuild new, bio-reactive, when the video cycle is greenlit | Visual |

## TIER C — REJECT (deprecated / off-vision; do NOT rebuild)

`SoundscapeEngine` (547 LOC, wellness soundscape — off-brand) · `OuraRingClient` (690 LOC —
Oura has no realtime third-party BLE; data comes via HealthKit) · `WeatherProvider` ·
`CircadianClock` · `MotionActivityProvider` · `BioSourceManager` (superseded by the
publisher-per-source model) · `MasterView` (1079 LOC old monolith) · `MomentCapture(View)` ·
`CameraMeasurementView` (old rPPG UI; replaced) · `StudioRoot/StudioNavigator/BeatTab/
WorksView/ModulationView/SoundscapeView` (old multi-tab paradigm — superseded by the single
`EchoelStudioView`).

---

## Rebuild order (Ralph cycles, stable-first, one per cycle)
1. **Bio-reactive visual engine** (Cymatics/Mandala kernels → clean renderer on EngineBus, flash-safe) — the top on-vision gem.
2. **SkillLevel pull-through** + **Settings** surface (founder-chosen; the "simple AND flexible" dial).
3. **SequencerAccessibility** (when clips UI starts).
4. **One-view Clips/Arrangement** (Producer tier).
5. WATCH items (CloudKit sync, sessions UI, video) as their dimension is greenlit.

_Principle: rebuild from the idea, clean and tested, on the stable bus — never paste old code._
