# PLAN — Visual rework (founder 2026-07-02)

Founder: "radikal reduzieren auf qualitative Biofeedback Musik. Visuals schön
überarbeiten und als kleines Fenster flexibel groß ein- und ausblendbar machen.
Tendenziell die Visuals interessanter gestalten aber weniger komplex von den
Einstellungen."

Reading: music is the core; the visual becomes a **floating, resizable, show/hide
window** — nicer to look at, FEWER settings.

Current state (audited):
- Visual shows ONLY fullscreen (`EchoelStudioView.$showVisual` cover + a WorkspaceView
  `expandedMonitor` cover), both mounting the real `MetalBioView`.
- MANY settings: intensity/detail/motion/spread/hue/saturation/style/styleB/blend +
  9 `VisualPreset`s (with a DUPLICATE name "Halo": ids `aura` and `halo`).
- `MetalBioView` reads bio itself in `draw(in:)` (render-safe); simple init exists
  (`MetalBioView(intensity:ringDensity:motion:spread:)`), needs EngineBus +
  ResourceGovernor + VisualRecorder from the env (all app-root injected).
- GPU RULE (HeaderMonitors note): only ONE `MetalBioView`/MTKView may render at a
  time — two starve the GPU (black for seconds). So the floating window must be the
  single Metal path at WorkspaceView level.

## Cycle 1 (this) — floating, resizable, show/hide visual window
New `Studio/FloatingVisualWindow.swift` (leaf; MetalBioView reads bio itself → no
10 Hz read in any ancestor body, freeze rule safe). A draggable card with:
- 3 snap sizes (S/M/L) cycled by one button ("flexibel groß"); draggable to reposition.
- Close (X) → hides ("ein-/ausblendbar"). NO sliders (fewer settings).
- Nice, calm chrome (rounded 12, 1px border, ≤8px shadow — Uncodixfy).
Wire into `WorkspaceView`: `@AppStorage visible` + `.overlay`; the header immersive
mini button TOGGLES the floating window (replaces the `expandedMonitor` fullscreen
cover — remove that path so only ONE Metal path remains at the root).

## Cycle 2 — simplify the settings + curate looks
- Cut the front visual controls to a SMALL set (a curated Look cycle + maybe one
  Intensity). Move the deep VJ sliders (hue/sat/style/blend) to Studio-advanced only.
- Trim `VisualPreset.factory` to ~4–5 distinct, beautiful looks; FIX the duplicate
  "Halo". Add a look-cycle button to the floating window.

## Cycle 3 — "interessanter" (nicer rendering)
- MetalBioView shader polish (default look more alive) — device-gated, its own cycle.

## Cycle 4 — the loop-render + short-video pillars (separate from visuals)
- `VisualRecorder` already captures the Metal visual to mp4 → foundation for
  social short videos; surface a clean "record short" from the floating window later.

## Verify
- CI compile-check (no local toolchain).
- Render safety: window body reads only low-freq @State; MetalBioView pulls bio in
  draw(in:). No new .sheet on EchoelStudioView. Only one MTKView at root.
- Device: toggle window, drag it, cycle S/M/L, close; audio + menus unaffected while bio runs.
