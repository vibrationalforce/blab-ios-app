# PLAN — DMMW Production Shell (founder 2026-07-12)

**Founder (verbatim):** "Diese Art der Bedienung wird nicht in den DMMW Kontext passen.
Die Bedienung ist zwar bisher gut gewesen zum Test aber wenn wir produzieren wollen
brauchen wir mehr das feeling, wie in einer richtigen DAW/VideoEditing/Visual/light/Laser
Software. Die Button werden kleiner und verteilen sich sinnvoll auf den Spuren der
Timeline und oben im Menü. Alles bleibt im Hauptfenster es gehen nur dropdown Menüs
auf für die Einstellungen."

Three screenshots circle the ENTIRE stacked panel pile below the bio strip
(Composition · Session · Transpose · Sound & texture · Mix · Effects · Master · Mood ·
Export · Live Colabo · EchoelSynth · Learn & News) → all of it leaves the scroll flow.

## Target

Main window = chrome (header · transport · **menu bar**) + **timeline** (dominant) +
bio strip. Settings NEVER navigate away: a small menu button opens ONE anchored
dropdown panel over the main window; tap-outside closes.

## Architecture (render-safety first)

- **Menu bar**: one horizontal row of SMALL buttons (Uncodixfy chip style, 12-13pt)
  at the top of the studio zone: `Comp · Session · Sound · Mix · FX · Master · Mood ·
  Export · Live · Synth · Learn`. Horizontal scroll if narrow. Low-freq @State only.
- **ONE dropdown host** (the critical metadata trick): `@State var activeMenu: StudioMenu?`
  (enum). ZStack overlay above the (now nearly empty) scroll area: scrim (tap = close) +
  ONE panel card whose content switches on the enum — the EXISTING panel builders are
  REUSED as content. NO new `.sheet`/`.fullScreenCover` (the ~18-modal chain is at the
  SIGSEGV ceiling — this is exactly the "consolidate into a single slot" pattern the law
  prescribes). Removing ~11 AnyView rows from the flow SHRINKS the body's metadata type;
  the overlay adds ONE AnyView branch. Net: safer than today.
- **Why not system `Menu`**: SwiftUI Menu supports only Button/Toggle/Picker rows —
  `EchoelValueField` (the app-wide parameter control, drag + keypad) cannot live inside
  it. The custom anchored dropdown keeps the ONE-control rule intact.
- **Panel content in dropdown**: panels currently render via `panel(title, subtitle,
  isExpanded:)` disclosure cards. In the dropdown they render ALWAYS-EXPANDED (a
  `forceOpen` environment flag read by the panel helper — one change, all panels).
- **Direct actions** (no dropdown needed): Live Colabo / Learn / EchoelSynth menu
  buttons trigger their existing sheet/floating-window actions directly.
- **Lane distribution (D2)**: per-lane small controls on the timeline tracks (the
  founder's "verteilen sich sinnvoll auf den Spuren") — merge with the V3 design
  cleanup (label column, region blocks, ruler). ArrangeTimelineView owns its own
  single `.sheet(item:)` — lane dropdowns become anchored popover-style panels or
  reuse that one sheet slot.

## Phases

- [ ] **D1 — menu bar + single dropdown host in EchoelStudioView** (one cycle):
      stacked cards leave the flow; timeline gains the freed space. ui-state-review
      MANDATORY (metadata + freeze law), gates, deploy. NEEDS-FOUNDER-VERIFY (feel).
- [ ] **D2 — timeline lane distribution + design cleanup** (V3 merged): lane-head
      dropdown, per-lane small buttons, region block polish, ruler/label design,
      BioStrip "HRV 15.." truncation fix.
- [ ] **D3 — chrome polish**: if the founder wants the menu bar physically above the
      timeline (true top menu), relocate state or lift bindings then.

## Interlocks

- V2 groove anchor (offbeat fix) stays queued as its own musical cycle — test-first.
- V1 visual diagnosis: v174's `visual:` diag lines land the answer from the next
  device log; fix follows wherever it points (governor tier vs empty MusicalFrames).
- EchoelAI = later command layer (decisions.md 2026-07-12) — the menu bar leaves the
  top-right slot free for it.
