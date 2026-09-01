---
name: swiftui-render-safety
description: Use BEFORE editing EchoelStudioView, WorkspaceView, or any always-on
  header/HUD/leaf that shows live bio. Prevents the two recurring ship-blockers —
  the SwiftUI metadata black-screen (.sheet-chain limit) and the 10 Hz @Observable
  menu-freeze. Load when adding a modal, reading a bio/playhead value in a view,
  or diagnosing a black screen / frozen Picker / "can't select while biofeedback runs".
---

# SwiftUI Render Safety (Echoel)

These are two hard-won, ship-blocking regression classes. Both cost multiple
device builds to diagnose because the crash/freeze happens FAR from the edit.
This skill exists so a fresh session gets the exact rule instead of re-breaking it.

## When you touch a view — check ALL of these

- [ ] **Adding a modal?** DO NOT append another `.sheet`/`.fullScreenCover` to
      `EchoelStudioView`'s body. The aggregate generic type is near the SwiftUI
      metadata-decoder stack limit; one more modifier = SIGSEGV at first render,
      before any view appears (presents as a black screen, or Safe-Mode/black
      alternating once the self-healing net catches every other launch).
      REUSE an existing slot, or consolidate the whole chain into ONE
      `.sheet(item:)` enum FIRST. An `AnyView` split does NOT save it
      (10.76.35 still crashed; only reverting the body count did).
- [ ] **Never drive two modals `true` at once** → installs an invisible
      tap-blocking layer (the "can't click anything" hang).
- [ ] **Reading a HIGH-FREQ `@Observable`?** (the ~10 Hz `CameraRPPGBioPublisher`
      finger/confidence/waveform, any bio snapshot, a playhead/BPM) — NEVER read it
      in a Picker/menu-hosting `body`, in a computed `var` that `body` evaluates,
      or in ANY ancestor body (`WorkspaceView`, any always-on header / PulseMonitor).
      `AnyView(...)` is NOT an observation boundary — such a read registers the
      WHOLE root body as a 10 Hz observer and every rebuild tears down an open
      `.menu` Picker popover (the freeze; worse while playing). Confine the read to
      its OWN small leaf `View` struct (`BioStripView`, `PulseMonitorMiniLive`,
      `PulseMeasurementView`) so only that leaf churns.
- [ ] **The camera is NOT the only hot producer — there are FOUR.** (1) `CameraRPPGBioPublisher`
      at ~10 Hz. (2) **`AudioEngine`'s 60 Hz meter poll timer** (`masterLevel`, `masterLevelR`,
      `masterPeakDb`, `masterLUFS`, the R128 readouts, `masterOutputLRA`) — SIX TIMES hotter, and
      it churns whenever AUDIO is running, not only when the camera is on. (3) **`masterVolume`**,
      rewritten by `AutomationPlayer.applyStep` on every transport step. The `masterVolume` case
      already happened once: read inline in `masterPanel`, it tore down the Tonart/Genre Picker,
      and `MasterVolumeField` exists as its own 8-line struct as the repair. (4) **`metronome.bpm`**,
      pushed by `Transport.onTempoChange(id: "metronome")` on every tempo change — up to ~20 Hz
      during a glide. Same law for all four: read them in a leaf, never in an ancestor body.

      ⛔ **THIS LIST SAID "THREE" FOR THREE WEEKS AFTER #928 MEASURED THE FOURTH, and the way it
      survived is the point.** #928 added `metronome.bpm` in `CLAUDE.md` and to the guard; this
      file — the one a session opens when `CLAUDE.md` says "Details in the skill" — kept teaching
      three, so following the pointer for detail got the SHORTER list. A repair moves in EVERY
      home (#456), and "three" is exactly the kind of number that nothing re-derives.

      ⚠️ **`metronome.bpm` is the most dangerous of the four**, because the host already reads
      four `metronome.` properties at TWO sites that `body` evaluates (`mixerPanel`'s click row
      and `metronomeRow`). Those are rightly COLD — a finger turns them — so the receiver and the
      habit are already in the body, and the hot spelling differs by one word.
      Guard: `Tests/CISmoke/TheMenuHostReadsNoHotStateTests.swift` (it DERIVES the hot sets, so a
      new readout joins them automatically) — it scans four ancestors: `EchoelmusicApp`,
      `WorkspaceView`, `SurfaceHost`, `EchoelStudioView`.
- [ ] **Never `Task { @MainActor }` per frame from a 30 fps source** → the flood of
      tiny main-actor task submissions starves the SwiftUI executor and freezes open
      menus while bio runs. Batch into the EXISTING low-rate (10 Hz) main-actor poll
      via a lock-protected `@unchecked Sendable` queue (see `CameraRPPGBioPublisher`
      `RGBSampleQueue`), ZERO actor hop in the background closure.

## Diagnosing (route to the fix)

- **Black screen / alternating Safe-Mode**, nothing renders → metadata limit →
  consolidate the `.sheet` chain (do NOT add more).
- **Picker/menu freezes while PLAYING but not while biofeedback runs** → it is the other
  producer: a 60 Hz meter readout or `masterVolume` read in an ancestor body, not the camera.
- **Picker/menu freezes ONLY while biofeedback runs** (not a crash) → a 10 Hz read
  leaked into an ancestor body → AUDIT THE PARENT/ROOT (`WorkspaceView`, any header
  reading live bio), not just the obvious view. Every prior audit that scoped only
  to `EchoelStudioView` found it clean while the real read was one level up.

## Rule of thumb

Header/monitor tiles that show live bio MUST read it in their own leaf, never via
values passed down from a parent body. When a freeze persists after the obvious
view is proven clean, the churn is in an ancestor.
