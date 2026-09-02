# PLAN — Comprehensive Interface Reorganization + Functioning Timeline (2026-07-11)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


## Founder directive (verbatim intent, 2026-07-11, full autonomy 12h, NO questions)
> "Mix Level sollten auf dem Hackbrett landen und alles so reorganisieren, dass alles
> möglichst an Ort und Stelle ist wo es auch wirklich stattfindet. Arbeite die nächsten 12
> Stunden ohne Rückfragen … an der Timeline und der Herstellung, funktionierend Spuren aller
> Funktionen etc. Sowie passendes adaptives Design für horizontal und Vertikal. Du hast volle
> Kontrolle und erarbeitest alles auf noch besserem Niveau … zukunftsfähig und stabil."

Decoded:
1. **Mix levels → the "Hackbrett" (Channel Rack):** each track's level + FX live ON that
   track's strip, not in a separate Mix panel. The dulcimer/board metaphor = the grid of channels.
2. **Reorganize so every control sits where the thing actually happens** (DAW co-location).
3. **Timeline that WORKS:** functioning tracks for all functions (hold/play/edit clips, per-track
   controls on the track header).
4. **Adaptive design for horizontal + vertical** (landscape timeline-wide, portrait stacked).
5. Highest level, future-proof, stable.

## HARD GUARDRAILS (never violated, even under full autonomy)
- **Never regress the launching instrument.** swiftui-render-safety laws:
  - Do NOT grow `EchoelStudioView`'s `.sheet`/`.fullScreenCover` chain (metadata black-screen).
    A NEW surface must reuse a slot, or the chain must be consolidated to ONE `.sheet(item:)` enum FIRST.
  - No ~10 Hz `@Observable` read (bio/playhead) in ANY ancestor of a menu host — confine live
    reads to leaf views.
- **Audio-thread rules** on every render-path change; audio-thread-reviewer before commit.
- **Protected Rausch triad** READ-ONLY.
- **CI is ground truth** — Quick Test + Xcode Compile Check green before EVERY deploy (no local
  Swift toolchain; the sandbox can't hear audio or see the render).
- **Safe defaults / no functional regression** — reorg must keep every currently-working control
  working; move, don't break. Behaviour-identical where possible; new surfaces reachable but the
  instrument HOME stays the launch view.
- **EchoelValueField** for every parameter; **Uncodixfy** (solid fills, ≤12px radii, 1px borders,
  ≤8px shadow, opacity/colour transitions, no glassmorphism/neon, ≤3 Hz flash).
- **Build on what's solid; extend, don't rewrite** ("zukunftsfähig und stabil"). No new deps /
  targets / top-level dirs.
- One coherent change per cycle; commit → both gates green → deploy → next. Small blast radius.

## DESIGN PRINCIPLES for the reorg
- **Co-location:** a track's volume, mute/solo, and inserts live on its strip; a clip's controls
  on the clip; transport on the transport bar. No orphan "Mix panel" when the mixer IS the rack.
- **One Track abstraction** the whole app shares (build on the existing model if sound).
- **Adaptive:** `horizontalSizeClass` + `GeometryReader`; landscape = wide timeline / rack rows;
  portrait = stacked. One layout code path, two arrangements — no duplicated view trees.
- **Render-safe surface host:** if bringing back multiple surfaces, do it via ONE consolidated
  `.sheet(item:)`/host, not N appended modifiers. Live bio reads stay in leaves.

## GROUND-TRUTH (survey 2026-07-11 — the facts that shape everything)
- **Root = `WorkspaceView` → `SurfaceHost`** (the real main view; WIRED-FUNCTIONAL, render-safe).
  `SurfaceHost` (SurfaceSwitcher.swift:114) is the ONLY orientation-aware code: `GeometryReader`,
  `landscape = width>height`, timeline-height ratio. When `timelineExpanded` it stacks
  `ArrangeTimelineView` over `EchoelStudioView` (both `AnyView`-erased — deliberate launch-crash fix).
- **`EchoelStudioView` is AT the ~18-modal metadata-SIGSEGV ceiling** (15 `.sheet` + 2
  `.fullScreenCover` + `.fileImporter` + 3 `.alert`). **NO new modal here, ever.** New surfaces go
  through `SurfaceHost` or INLINE panels (behind `AnyView(soundControls)`, line 430 — that boundary
  keeps inline additions out of body's metadata type).
- **`ArrangeTimelineView` = the live timeline (WIRED-PARTIAL):** renders `TimelineStore` lanes+regions,
  pinch-zoom, waveforms, `laneMixStrip` (mute/solo/level → store), its OWN single `.sheet(item:)`.
  **BUT no region plays** — only `rollSlotGain → pianoRoll.mixGain` reaches audio; playhead is visual-only.
- **No engine plays `TimelineRegion`s** — THE core gap. Clock infra exists: `Transport` (pure, no timer)
  driven by `PatternEngine` relay; `PianoRollModel.start` wires `onTick → arrangement.transportStep →
  automation.applyStep → trigger`. `ArrangementPlayer` plays legacy SECTIONS (tested) but is unreachable
  and knows nothing of regions.
- **Track model fragmented:** `TimelineLane` (arrange) vs 8 index-based drum pads (BeatPlayer) vs
  bass/pad/lead `NoteRole`s (MixerStore→voices). Only `rollSlotGain` bridges lane→audio.
- **Adaptive essentially unbuilt** except SurfaceHost's height ratio. `EchoelTheme.layout(h:v:)` exists,
  used only in BioStrip — a ready hook to extend.
- **Reusable, tested:** `ChannelRackView` (strip UI), `MixerStore`/`TrackFXStore`, `ClipView`
  capture/launch, `ArrangementPlayer` (section playback + tests), `TimelineStore` mute/solo math.

## PHASING (ordered; each = one safe, gate-verified, render-audited Ralph cycle)
- [x] **P0. Ground-truth map** (survey done).
- [x] **P1. Hackbrett — Channel Rack inline in the Mix panel.** DONE (ce039fa): `ChannelRackView`
      embedded (scroll-less) at the bottom of `mixerPanel` — the 8 drum channels' level/mute/solo/FX
      now reachable in the mix, no new modal. ui-state-reviewer: 0 risks. → v168.
- [ ] **P1b. Master voices onto the same rack** (optional polish) — render Bass/Pad/Lead/Drums-master
      as strips in the rack format (MixerStore + TrackFXStore), so ALL levels read as one Hackbrett.
      Defer behind the timeline (higher value); fold into the adaptive pass.
- [ ] **P2. TimelineRegionScheduler — PURE engine, TEST-FIRST.** A pure type: (document, transport
      position) → active regions per lane + resolved gain (mute/solo). No audio wiring yet. Fully
      unit-tested. The safe foundation for playback. Extends the ArrangementPlayer pattern, doesn't rewrite.
- [ ] **P3. Wire the scheduler to Transport + engine** (ADDITIVE, opt-in "timeline play"; existing
      pattern/roll playback unchanged so nothing regresses). MIDI regions → roll/pattern; audio regions
      → AudioClipPlayer at offset; per-lane level/mute/solo → engine. `NEEDS-FOUNDER-VERIFY` (audio).
- [ ] **P4. Adaptive H/V** — extend `EchoelTheme.layout(h:v:)` + size-class into the mixer/timeline/panels;
      landscape = wide rack rows / timeline; portrait = stacked. Layout-only → render-safe.
- [~] **P5. Reorg sweep + weather multi-parameter panel** — IN PROGRESS. Weather panel BUILT
      (v172 pending): `WeatherMood.Contribution` extended with continuous per-parameter targets
      split SOUND (darkness/liveliness/tension) + VISUAL (hue/saturation/glow/motion); a `Param`
      enum (domain · label · explanation · mixKey · defaultIntensity · currentIntensity reader) +
      pure `blend()` crossfade; the Session panel's weather row is now an explained, grouped
      Klang/Bild mixer list of `WeatherMixRow` leaves (each = EchoelValueField 0..1 + one-line
      explanation, own @AppStorage → render-safe, NO new modal). Wired: sound → `moodForInput`
      darkness/liveliness/tension blend before Input; structure salt gated by its mixer; visual →
      FloatingVisualWindow crossfades hue/saturation/intensity/motion toward the sky. Off / mixer 0
      = bit-identical. Tests: ranges, distinctness (warm<cold, storm=most-tense, wind→motion,
      fog=dimmest), blend endpoints, Param metadata, currentIntensity unset=default. NEEDS-FOUNDER-VERIFY
      (feel). Remaining: reorg sweep of any orphan controls; docs.

## Autonomous loop discipline
Each cycle: build → tests → push → poll both CI gates (python-parse the actions_list overflow file)
→ deploy on green → session-log entry → next cycle via send_later chaining. Keep the founder's
inbox quiet except deploy notes; NO questions (he has the reins). Stop only when he returns.
