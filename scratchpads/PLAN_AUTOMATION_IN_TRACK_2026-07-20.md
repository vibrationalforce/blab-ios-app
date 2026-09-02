# PLAN — Automation in der Spur (Founder REIHENFOLGE #1) — precision editor edits the RIGHT store

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Founder #1: "Automation in der Spur (im Clip UND clip-übergreifend, alle Parameter via
EchoelParameterRegistry)." Mandate: **ERST PLAN + Council, dann Zyklen.**

## Befund (investigiert 2026-07-20 — was WIRKLICH gebaut ist)

Most of #1 already ships:
- **"im Clip"** → `ClipAutomationView` (`.clipAutomation(region)`, L1/#70), draws clip-relative into the clip. ✓
- **"clip-übergreifend" (song-wide)** → `TimelineAutomationRow` (T1/#37), draws song-absolute into
  `document.automation`, persisted, played via `TimelineRegionPlayer` → `AutomationPlayer` timeline layer. ✓
- **"alle Parameter via Registry"** → both offer registry descriptors; per-track targets
  `track.<laneID>.<base>` (L2/L4/#72). ✓

**THE ONE REAL FUNCTIONAL BUG (convergence audit #1, now root-caused):** the *precision editor*
sheet `AutomationView` (opened from the row's "open editor" button `ArrangeTimelineView:917` AND the
lane door `:1065`, both via `activeModal = .automation`) edits a **different store**:
- `AutomationView` mutates `AutomationPlayer.lanes` — the **loop layer**: ONE bar, beat-indexed,
  defaults to `masterLevel`, NOT per-track, separate from `document.automation`.
- The `.automation` modal case carries **no parameter/track context** → the sheet always opens on
  `masterLevel` + the loop lanes, ignoring what the row was showing.

User flow that breaks: draw a per-track filter curve across the song in the inline row → tap
"open precision editor" → land in a blank 1-bar master-level loop editor. Typed value / curve /
segment-bend edits go to a layer disconnected from what plays with the song.

## Decision: Option C — repoint the precision editor to `document.automation` (keep the surface, fix the store)

Rejected **Option D** (delete the precision door, fold typed/curve/bend into the row): loses the
dedicated precision surface AND needs new row UI = MORE work than repointing. Rejected **Option A/B**
(rip out AutomationPlayer.lanes): the loop layer is also the runtime dispatch target fed FROM
document.automation — don't touch the playback spine.

De-risked finding: `TimelineStore` ALREADY has the song-absolute point ops the sheet needs
(`addAutomationPoint`/`moveAutomationPoint`/`removeAutomationPoint`/`automationLane(forParameter:)`),
used by the working row. Only small parity additions + the UI bind remain.

## Slices (one per Ralph cycle)

- **S1 — store parity (PURE, Linux-CI-testable, ZERO device risk) [NEXT BUILD]**
  Add to `TimelineStore`, mirroring `AutomationPlayer`'s point ops but on song-absolute ticks:
  `setAutomationValue(parameter:,id:,normalized:)` · `setAutomationCurve(parameter:,id:,_:)` ·
  `setAutomationCurvature(parameter:,id:,_:)` · `clearAutomation(parameter:)`. (add/move/remove/lane
  already exist.) Each commits once (structural persist, HARNESS_LEDGER relocate-storm law — same as
  the row). Unit tests: add→setValue→setCurve→remove→clear round-trips + alias identity
  (`masterLevel` ≡ `master.amp.level` never splits). No UI, no sheet, no device.

- **S2 — repoint the sheet (UI, DEVICE-GATED)**
  Give the EXISTING modal case a payload — `.automation(parameter: String, laneID: TimelineLane.ID?)`
  (REUSE the case; NO new `.sheet` — sheet-chain law). `AutomationView` reads
  `timeline.automationLane(forParameter:)` and writes via the S1 API (song-absolute), seeded on the
  passed parameter (not `masterLevel`). Canvas x-axis basis moves from `AutomationPlayer.beatsPerBar`
  (1 bar) to the row's song-absolute `pxPerTick`/span (`TimelineAutomationRowMath`). `:917` passes the
  head cell's `selectedParameter` + `perTrackLaneID`; `:1065` passes the lane's default automatable.
  Freeze law: no playhead/bio read in the sheet body (it already reads none). **Device-verify:** draw
  in row → open precision → SAME curve appears → typed edit persists + plays with the song.

- **S3 — loop-layer cleanup (device-gated, AFTER S2 verified)**
  With editing unified on `document.automation`, decide `AutomationPlayer.lanes`' editing path: keep
  it ONLY as the runtime dispatch target (fed from document.automation), retire its separate *editor*
  binding. Council re-checks whether any surface still authors the loop layer before removing.

## Council — precision editor edits the wrong automation store

· **Architect:** Option C reuses the working song-absolute store + playback spine; couples the sheet
  to `TimelineStore` (already the row's dependency). No new coupling. — concern: two coordinate bases
  (loop-beat vs song-tick) must not both linger in the sheet; S2 must fully switch, not straddle.
· **DSP Purist:** no audio-thread surface here (automation dispatch already runs on the transport
  tick via applyStep; unchanged). — nothing to flag.
· **Skeptic:** the real risk is S2's canvas retarget (loop-bar → song-absolute) — unverifiable
  without a device. Mitigation: land S1 (pure, tested) first; keep S2 a separate, revertible cycle;
  golden rule — the inline ROW path and the loop DISPATCH stay byte-unchanged. — cheapest way to be
  wrong = straddling both stores, so switch atomically in S2.
· **Shipper:** S1 is a tight, tested, green-gate slice with zero device risk — ship it next. S2/S3
  are device-gated, one cycle each. One thing per cycle. — proceed.
· **User-Advocate:** this is founder #1 and the only real functional bug; fixing it makes "draw in
  the track, refine precisely" behave as one coherent thing. — proceed.

→ **Recommendation:** Option C, staged S1→S2→S3. **Build S1 next** (pure store parity + tests).
**Gate: proceed.** S2/S3 gated on S1 green + a device draw/play verify. Golden invariants: inline row
store + loop dispatch unchanged; no new sheet; no playhead/bio read in the sheet.
