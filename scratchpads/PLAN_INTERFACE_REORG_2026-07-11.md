# PLAN — Comprehensive Interface Reorganization + Functioning Timeline (2026-07-11)

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

## PHASING (ordered; each = one safe, gate-verified, render-audited Ralph cycle)
> Concrete steps filled after the architecture survey (agent a817… running). Skeleton:

- [ ] **P0. Ground-truth map** (survey) — surfaces/models/stores state, every `.sheet`, adaptive gaps.
- [ ] **P1. Channel Rack = the Hackbrett.** Put per-track level + mute/solo + FX on each channel
      strip (Bass·Pad·Lead·Drums + 8 drum pads). Reuse MixerStore + TrackFXStore + BeatPlayer.
      Make the Rack a reachable surface (render-safe host). Mix panel becomes the Rack (or forwards to it).
- [ ] **P2. Unified Track model** (if not already) — one Track type bridging clip-tracks, drum pads,
      and the bass/pad/lead voices, so timeline + rack + mixer speak the same language.
- [ ] **P3. Functioning Timeline** — tracks that hold/play/edit clips against the transport clock;
      track headers carry the co-located controls; ArrangementPlayer actually schedules to audio.
- [ ] **P4. Adaptive H/V** — landscape/portrait layouts across the shell + timeline + rack.
- [ ] **P5. Polish + reorg sweep** — move every remaining orphan control to its object; docs/tests.
- [ ] (folded in) Weather multi-parameter panel — lands in the reorganized "where it happens" home.

## Autonomous loop discipline
Each cycle: build → tests → push → poll both CI gates (python-parse the actions_list overflow file)
→ deploy on green → session-log entry → next cycle via send_later chaining. Keep the founder's
inbox quiet except deploy notes; NO questions (he has the reins). Stop only when he returns.
