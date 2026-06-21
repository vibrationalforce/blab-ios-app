# PLAN — Interface Optimization (compact, accessible, pro-tool clear)

Founder direction (2026-06-21): the whole interface must be optimized toward the
clarity of leading multidimensional/multimedia software (Ableton, FL Studio; and the
domains: video AI/editing, content production, mapping, light, laser, streaming,
spatial sound control, 360°, spatial visuals). Make the menu COMPACT, put tools on
the FRONT, fix that tools feel inaccessible / "don't work right", and bring EFX into
the Echoel CI.

## Decisions (locked with founder)
1. **IA = persistent workspace bar.** Remove the "Tools" dropdown + modal sheets.
   Tools become first-class, always-visible panels reached from a flat, compact
   tab/segment bar (FL/Ableton feel), opening in-place — not pop-ups.
2. **EFX → Echoel CI.** EchoelFXView must match the app's bespoke dark panel design,
   not the stock iOS Form/list chrome.
3. **Structure for all domains, show only what ships.** The IA must host video/light/
   laser/streaming/spatial/360 later, but surface ONLY working tools now — no dead
   buttons (brand: claim only what ships).

## Root causes (audited)
- Deep editors (Piano Roll, Clips, Arrangement, Sound Editor, Drum Samples, Visual,
  Breath, Audio Input, MIDI, Health) are hidden behind ONE `Tools` Menu and open as
  modal `.sheet`/`.fullScreenCover` → the "inaccessible" feeling.
- `EchoelFXView` is a stock SwiftUI `Form`/`Section` grouped list (grey insets, system
  headers/toggles) — the lone CI outlier. Its `field()` already uses `EchoelValueField`.
- Many target categories are roadmap (RTMP/video/streaming not built; light partial).

## Shared vocabulary (build once, reuse everywhere)
- `EchoelValueField` — the one numeric parameter control. ✅ exists.
- Panel look — currently a private `panel(title,subtitle,isExpanded:)` in
  EchoelStudioView. **Extract a shared `EchoelPanel`** so the FX view + the new
  workspace use the identical card. (Next cycle.)

## Staged cycles
- **UI-1 (done, low-risk):** EFX CI restyle — drop the stock grey Form background,
  Echoel black bg, themed nav bar, accent tint, dark scheme. Functionality untouched
  (preset list keeps its swipe/context actions). Ships so the founder can react on
  device before the deeper panel conversion.
- **UI-2:** Extract shared `EchoelPanel`; rebuild EFX body on ScrollView + EchoelPanel
  (full bespoke-panel parity; preset actions move swipe→per-row menu + inline ★).
- **UI-3 (the big one):** Persistent workspace bar. Replace the Tools dropdown + modal
  sheets with a flat compact segment/tab nav; tools become in-place panels. Resize for
  iPhone first. Keep the always-on BioStrip on top.
- **UI-4:** Dead-button pass — only show working tools; gate roadmap domains until live.
- **UI-5 (later):** Category scaffolding for video/light/laser/streaming/spatial/360 as
  each becomes functional. Compose with the audiovisual engine (E/F/G) + EchoelLux.

## Guardrails
- Uncodixfy CI rules (CLAUDE.md): radii ≤16, no glassmorphism/glow, ≤8px shadows,
  opacity/colour transitions ≤200ms, EchoelValueField for every parameter.
- iPhone-first; no dead controls; every screen does something.
