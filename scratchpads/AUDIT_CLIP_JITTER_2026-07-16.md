# AUDIT — Clip-Zittern (task #56), static code audit 2026-07-16

Founder (device build 2373): "Die Clips sind immer noch sehr rudimentär in der Handhabung
und zittern." Screen recording pending — this is the code-derived shortlist of causes,
ranked. All line numbers as of branch `claude/piano-roll-clip-view-wozlie` @ 345cb6f.

Files: `Sources/Echoelmusic/Studio/ArrangeTimelineView.swift` (view + RegionBlockView leaf),
`Sources/Echoelmusic/Core/TimelineStore.swift`, `Sources/Echoelmusic/Sequencer/Timeline.swift`,
`Sources/Echoelmusic/Core/MediaLibrary.swift`, `Sources/Echoelmusic/Studio/WaveformView.swift`.

---

## What task #44 already fixed (and therefore is NOT the cause)

- 89a5872 `refactor: extract RegionBlockView leaf` — root-@State churn: every trim frame
  used to rebuild ALL lanes + ruler + playhead. Fixed: `resizeDelta`/`frontDelta`/`moveDelta`
  are leaf-local `@State`; verified still true (ArrangeTimelineView.swift:1053-1066).
- 29c5fa0 smooth playhead — the ~8 Hz Transport read lives in the `TimelinePlayhead` leaf
  (`TimelineView(.animation)`, :1440-1575); the grid body reads no transport. Verified: no
  regression — `@Environment(Transport.self)` in RegionBlockView (:1050) is read ONLY inside
  contextMenu action closures, never in body. Freeze-law intact.
- 587740f front-trim, 1a9a425 drag-to-move, 61f5a75 undo (#48): undo snapshots happen ONLY in
  store commit methods (TimelineStore.swift:92-97 called from resize/move/trim), which the
  gestures call ONLY in `.onEnded` — **no per-.onChanged store writes, no undo thrash**
  (task-hunt items 2 & 4: verified absent).
- No snap round-trip per frame (hunt item 1 in its literal form): snapping happens once, at
  commit (:1230-1236, :1255-1283, :1300-1305). No `withAnimation`/`.animation` on regions,
  no Timer fighting the gesture (hunt item 7: absent).

What #44 attributed the 2026-07-15 trim jitter to (root churn) was real but — see C1 —
plausibly only HALF the story. The oscillation mechanism below survives leaf extraction.

---

## Ranked candidates

### C1 — HIGH · Trailing-trim drag measured in a coordinate space the trim itself moves
**Where:** ArrangeTimelineView.swift:1223-1239 (`resizeGesture`, default `.local` space),
handle overlay :1121-1134 (`.overlay(alignment: .trailing)`), width :1076 + `.frame(width: w)` :1135.

**Mechanism (concrete oscillation):** `w` includes the live `resizeDelta`, applied via
`.frame(width:)` — a **layout** change. The trailing-aligned handle's layout position
therefore shifts right by `resizeDelta` every frame. `DragGesture` without an explicit
`coordinateSpace` converts locations into the receiving view's CURRENT space per event, so
`translation.width` = fingerΔ − handleShift = fingerΔ − resizeDelta(prev). With
`resizeDelta(n) = translation(n)` you get `r(n+1) = d − r(n)` — the width alternates between
two values every frame: the clip's right edge **vibrates at display rate** while the finger
holds still mid-trim. This is the literal "zittern". (Front-trim and body-move are today
immune by accident: their live motion goes through `.offset` — a render transform that does
NOT move layout geometry — so their `.local` space stays put. Only the trailing handle rides
a *layout* change.)

**Minimal fix (1 file):** give all three region gestures an explicit STABLE coordinate space —
`DragGesture(minimumDistance: 3, coordinateSpace: .named(ArrangeTimelineView.playheadSpace))`
(widen `playheadSpace` :903 private→fileprivate, exactly like `laneHeight`). The grid space
already exists for the playhead drag and is scroll-invariant. Translation then measures pure
finger delta regardless of the clip's own re-layout.

### C2 — HIGH · Gesture deltas in `@State` never reset on gesture CANCELLATION (stuck ghost offsets)
**Where:** ArrangeTimelineView.swift:1053-1066 (`resizeDelta`/`isResizing`/`frontDelta`/
`isFrontResizing`/`moveDelta`/`isMoving` are `@State`, written in `.onChanged`, reset only in
`.onEnded`).

**Mechanism:** the region sits inside a horizontal ScrollView inside a vertical ScrollView
(:118-127). When the scroll gesture wins arbitration mid-drag (easy: move min-distance is 8 pt
≈ the scroll threshold), the DragGesture is **cancelled — `.onEnded` never fires** — and the
deltas stay non-zero: the clip renders displaced by up to the stolen distance with NOTHING
committed to the store. Next grab starts from a lie; the eventual commit snaps it back →
clips appear to twitch/jump around between grabs ("rudimentär in der Handhabung").
`@GestureState` exists precisely for this: it auto-resets on cancel.

**Minimal fix (same file):** convert the three deltas to `@GestureState` via `.updating`;
derive `isMoving`-style flags from `delta != .zero` (or a second `@GestureState`). Commit in
`.onEnded` keeps using `value.translation` (independent of the state), so behaviour on a
clean drag is identical. Verify on device that reset+commit land in one transaction (no
one-frame flash-back at release).

### C3 — MEDIUM · Nested ScrollViews race the body-move drag at grab time
**Where:** ArrangeTimelineView.swift:118-127 (scroll nesting), :1151 (`.gesture(moveGesture)`),
:1249 (`minimumDistance: 8`).

**Mechanism:** plain `.gesture` competes with both scroll axes. In the undecided window the
grid can pan while the clip also offsets (tug-of-war wobble at grab); when scroll wins → C2's
stuck state; vertical lane-moves fight the vertical scroll the same way. The trim handles won
this war via dedicated 22 pt zones + min-distance 3 (device-verified per :1122-1133 comments);
the body move never got the same treatment.

**Minimal fix (same file):** promote the clip body drag to `.highPriorityGesture(moveGesture)`
— GarageBand semantics: touch on a clip edits it, empty lane space / ruler / headers scroll.
Keep min-distance 8 so tap-audition and the long-press menu keep falling through.

### C4 — MEDIUM · Stepless live preview vs snapped+clamped commit → jump at every release
**Where:** ArrangeTimelineView.swift — preview :1075-1076 (raw deltas), commits :1229-1239
(trailing: snap + `max(ticksPerTransportStep,…)` floor), :1254-1286 (move: snap + edge magnet +
C5 overlap), :1299-1308 (front: snap + `trimmedStart` clamps, Timeline.swift:244-259).

**Mechanism:** during the drag the clip follows the finger stufenlos; at release the commit
snaps (default grid 1/16!), magnetizes to neighbour edges, floors the min length, and clamps
the front-trim at media start / end−1. Every release therefore JUMPS the clip, sometimes by
half a grid cell — and the front handle can be dragged visually past the clip's right edge
(w clamps at 6 pt but x keeps following the finger, :1075-1076) before snapping back. Feels
exactly like "zittern + rudimentär" even when each individual mechanism is correct. Hunt
item 6 (units): `trimmedStart` mixes the seconds↔ticks domains for the offset clamp
(Timeline.swift:245) — rounding is ≤1 tick and commit-time only, NOT a jitter source, but the
live preview knows none of these clamps.

**Minimal fix (3 files, test-first):** pure `TimelineDragMath` core in `Sequencer/`
(Linux-CI-testable): given raw delta-points, ppb, snap, region + neighbour edges → the
clamped, snapped LIVE delta (same maths as the commits). Wire into the three `.onChanged`s so
the preview lands where the commit will; release becomes a visual no-op; move the C4 haptic
to live snap-tick changes. Files: `Sequencer/TimelineDragMath.swift` + `Tests/...` +
`ArrangeTimelineView.swift`.

### C5 — LOW-MED · File-system probes in the leaf body — runs EVERY drag frame for audio clips
**Where:** ArrangeTimelineView.swift:1082 (`auditionURL`) and :1089 (waveform overlay) both
call `ArrangeTimelineView.mediaURL` → `MediaLibrary.resolveRef` (MediaLibrary.swift:80-99):
`FileManager.fileExists` ×1 on hit, up to ~5 probes + `directory(sub)` **directory creation
side effect** per MISS — synchronously, in body, twice per frame at 60-120 Hz while a drag's
delta churns the leaf. A clip whose media ref is vanished/re-rooted pays the full cascade
every frame → main-thread micro-hitches = stutter under the finger.

**Minimal fix (1-2 files):** resolve once per `clip.mediaRef` into leaf `@State` (`.task(id:
clip?.mediaRef)`) or a small memo cache on MediaLibrary; body reads the cached URL only.

### C6 — LOW · Synchronous persist on every commit compounds the release jump
**Where:** TimelineStore.swift:566-569 — `persist()` JSON-encodes the WHOLE document + writes
the file + runs `onDocumentChanged` (LaneAUInstrumentHost.syncAssignments dict-diff,
EchoelmusicApp.swift:597-605) on the main thread at every gesture end AND every undo/redo.
One-frame hitch exactly at the moment C4 jumps — additive perception of "zittern".
**Fix (later, careful):** debounce the file write (keep the in-memory mutation + observation
synchronous); do NOT reorder around undo.

### C7 — LOW · contextMenu long-press lift-preview vs slow drag start
**Where:** :1164 `.contextMenu` and :1151 drag on the same clip. Holding ~0.5 s while moving
<8 pt starts the system lift preview (clip pops up/scales), then movement cancels it — a
visible flash when grabbing hesitantly. Verify on the recording before touching (the menu is
a founder-requested feature; any change needs a Council look at gesture precedence).

---

## Verify on-device when the founder's recording arrives

1. **C1:** does the clip's RIGHT edge vibrate at high frequency while the finger rests
   mid-trailing-trim? (Front edge should NOT vibrate — offset-based.) → confirms C1.
2. **C2:** after an aborted grab (timeline scrolled instead), is a clip left slightly
   displaced until the next successful drag/commit? → confirms C2.
3. **C3:** does the grid pan WHILE a clip is also moving under the finger? → confirms C3.
4. **C4:** does the visible jump happen at finger-LIFT (not during motion), size ≈ half a
   1/16 cell or a neighbour-edge magnet pull? → confirms C4 (also check snap=Off behaviour).
5. **C5:** is jitter worse on audio clips (waveform) than MIDI clips, worse on clips whose
   audio vanished? → confirms C5.
6. Confirm transport playing vs stopped makes no difference (if it DOES, revisit the playhead
   leaf and ClipStore writes during generative play — currently ruled out statically).

## Slices (Ralph Wiggum, ≤3 files each; laws respected — no new sheets, leaf-only live state,
## no audio-thread involvement, pure cores tested on Linux CI)

- **Slice 1 (FIRST, 1 file — ArrangeTimelineView.swift):** C1 + C2 + C3 together: named stable
  coordinate space on all three region gestures (widen `playheadSpace` to fileprivate),
  `@GestureState` deltas, `.highPriorityGesture` for the body move. Smallest change that
  attacks the literal per-frame Zittern + the stuck-ghost handling complaints.
- **Slice 2 (3 files, TDD):** C4 — `TimelineDragMath` pure core + tests + wire live
  snap/clamp preview so release never jumps.
- **Slice 3 (1-2 files):** C5 — cache `resolveRef` per mediaRef out of the per-frame body;
  then reassess C6/C7 against the recording.
