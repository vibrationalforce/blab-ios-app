# PLAN — #224 Slice 2c: the Field actually plays itself

> ⛔ **PARTLY SUPERSEDED 2026-07-31 (#311) — read this before quoting the Council entry below.**
> This plan was implemented (Option A), and its central trade-off has since been **overruled by
> the founder**: *"die arps soll immer hörbar sein und nicht nur, wenn das Visual Fenster auf
> ist."* The verdict below — *"the mount-lifetime limitation is accepted and must be written into
> the code, not discovered later"* — is history, not policy.
>
> **And the reason it was accepted turned out to be wrong.** Option B was costed here as "an
> app-level driver and a second note path", i.e. the #177 defect class, and that estimate was
> copied verbatim into `FieldAutoPlay.swift`'s header and `TouchInstrumentView.didMoveToWindow`.
> Three files then agreed with each other, which reads as corroboration. The actual fix needed
> **neither**: the lifetime bug was one level ABOVE the play surface — `WorkspaceView` mounted the
> whole `FloatingVisualWindow` behind an `if`, so hiding the PICTURE unmounted the SURFACE. It is
> now mounted unconditionally and merely made inert when hidden; the note path never moved.
>
> Option A vs B was therefore a false choice, and the Council did not see it because nobody
> re-derived the cost of B — including the file that already contained the correct pattern for
> exactly this failure (`FloatingVisualWindow.visualLayer`'s #206 doc: *"hiding the window takes
> the phone's PLAY SURFACE with it"*). **Keep this document as the record of how that happened.**
> Do not plan from its Option-B estimate.

**Status:** planned 2026-07-29; Option A implemented; mount-lifetime trade-off overruled
2026-07-31 (#311) — see the block above.
**Founder ask:** *"Es soll auch eine Möglichkeit geben wie der Synth selbst spielt ohne das
man Touch bedienen muss. Natürlich mit mehreren Parametern."*
**Already shipped:** `Sequencer/FieldAutoPlay.swift` — the pure generator (positions, not
notes), hardened `c632e9b`/`41303bd`, both gates green. It has **zero callers**. This plan is
how it gets one.

Written as a plan rather than a commit because the shape was genuinely undecided and the
wrong choice is expensive: the obvious implementation creates a SECOND note path, which is
the exact defect this repo paid for in #177 and which `FieldAutoPlay`'s own header exists to
prevent. Reading the dispatch first changed the design twice.

---

## What the code actually is (verified, not assumed)

| Fact | Where |
|---|---|
| The play surface is mounted in **exactly one place** | `FloatingVisualWindow.swift:510` |
| …so it exists only while the floating visual is up | that window's body |
| The note dispatch is `private func sound(pitch:velocity:cutoffScale:finger:index:)` | `TouchInstrumentView.swift:599` |
| It is keyed on a **finger** (`ObjectIdentifier` of a `UITouch`) for `pendingOn` bookkeeping | `:320` (decl), `:627`, `:638`, `:704` |
| Note-OFF comes from `release(_:)` on `touchesEnded/Cancelled` | `:686`–`:694` |
| A note whose finger lifted early already self-releases after `staccatoSeconds` (0.18 s) | `:638`–`:645` |
| Ultrasync decision core is public | `TouchQuantizer.plan(forTick:index:seed:)` |
| Life is public | `TouchPitchMap.microVariation(noteIndex:depth:)` |
| Level is a gain on the shared voice, inherited automatically | `EchoelmusicApp.swift:581` |
| The musical clock is available **pull-based only** | `musicalNow: (@MainActor () -> TouchMusicalTime?)?` |

**The two consequences that decide the design:**

1. **There is no note-off for a note nobody is holding.** Every release path in the view is
   finger-driven. A generated touch has no finger, so it needs a duration — and the view
   *already has that concept*: the lifted-while-pending path plays on the grid and releases
   itself after 0.18 s. A generated note is the same shape as a tap whose finger already left.
2. **There is no push clock.** `musicalNow` is called AT touch time. Self-play needs to be
   told when a cell begins.

---

## Council

- **Architect** — put the driver where the synth, the quantizer, the Life counter and the
  note lifecycle already live: inside `TouchInstrumentUIView`. Anything else re-implements
  the dispatch. *Concern:* that view only exists while the floating visual is mounted, so
  self-play stops when the window is closed.
- **Shipper** — Option A is ~3 files and reuses everything; Option B (an app-level driver)
  is correct-forever and duplicates the dispatch today. Ship A, state the limitation.
- **Skeptic** — a display link inside a UIView is a new always-on loop. It must exist ONLY
  while armed and die in `deinit`. And: what happens when a finger plays while the generator
  runs? If both drive the same pitch the note-offs will fight.
- **User-Advocate** — the founder's own metaphor decides it: *even with a finished soup people
  still want to feel they are cooking.* The hand must always win, instantly, with no mode
  switch to find.
- **DSP Purist** — nothing here touches the audio thread; `noteOn`/`noteOff` are main-actor
  calls into `PolySynthVoice`. Clean.

**Verdict — proceed with Option A**, with the three mitigations below. The mount-lifetime
limitation is accepted and must be written into the code, not discovered later.

---

## Design

### 1. Clock — a pure core, testable, no new concept
Add to `FieldAutoPlay`:

```swift
/// Which cell a musical tick falls in, and whether it is the FIRST tick of that cell.
static func cell(forTick tick: Int, ticksPerCell: Int) -> Int
```

The view keeps `lastFiredCell: Int?` and fires when the value changes. That makes the
"advance" decision a pure function with a test, and leaves the view holding one Int.

`ticksPerCell` comes from the existing grid vocabulary (`TouchQuantizer.Grid`), NOT a new
unit — a sixteenth is 1/4 of `TimelineTime.ticksPerQuarter`.

### 2. Drive — `CADisplayLink`, only while armed
`TouchInstrumentUIView` gains:

```swift
var autoPlay: FieldAutoPlay.Params?      // nil = off, and OFF IS THE DEFAULT
var autoPlaySeed: UInt64 = 0
```

`didSet` starts a `CADisplayLink` when it becomes non-nil and invalidates it when it becomes
nil; `deinit` invalidates unconditionally. Each callback reads `musicalNow()`, computes the
cell, and on a change asks `FieldAutoPlay.touches(atStep:params:seed:)`.

> Rejected: a `Timer` (coalesces badly under load) and a `Task` loop (needs its own
> cancellation story that `CADisplayLink.invalidate()` gives for free).

### 3. Sound it through the EXISTING path — one new private call, no new dispatch
Each generated `Touch` becomes `TouchPitchMap.pitch(normX:normY:key:)` exactly as a finger
does, then goes through `sound(...)`. Two adjustments, both small:

- `sound` is keyed on `finger id: ObjectIdentifier`. Generated notes get a **stable synthetic
  id per voice index** (a private sentinel object per voice, allocated once), so `pendingOn`
  bookkeeping keeps working unchanged and a re-fire of the same voice cancels its own pending
  note rather than a stranger's.
- The note releases itself after `staccatoSeconds`, reusing the existing lifted-while-pending
  behaviour. **No new release machinery.**

### 4. The hand wins — non-negotiable
While any real touch is down, the generator **does not emit**. Not "ducks" — does not emit.
One `guard held.isEmpty else { return }` in the display-link callback — `held: [ObjectIdentifier: Int]` (`TouchInstrumentView.swift:292`) is the live-finger map, and `release(_:)` clears it on both `touchesEnded` and `touchesCancelled`, so it is the honest "is a finger down" test. (An earlier draft of this plan invented a property called `activeTouches`; there is no such thing.) Cheapest
possible implementation of the founder's metaphor, and it means there is no mode to find:
put a finger down and it is yours; take it off and the field carries on.

Additionally: on the first real touch, any pending generated note is cancelled through the
same `pendingOn` path that already exists.

### 5. The control — ONE element, in the panel that already exists
`EchoelStudioView`'s `visualPanel` (`:2435`, rendering `panel("Field", isExpanded: $showVisualSettings)` at `:2441`), reached by the **Field** chip. Note `.sound` and `.field` are two SEPARATE chips — an earlier draft of this plan wrote "Sound/Field chip" and named a `fieldPanel` that does not exist. The surface's Level field already lives in this panel (`:2520`), so the new rows join controls that are already there. **No new sheet** — the
presentation chain stays at 14 (black-screen law). The element:

- a **mode row** — `Off · Rise · Fall · Pendulum · Drift · Hold`, which is where the ARP
  (#220) becomes a sixth mode later rather than a seventh surface;
- `EchoelValueField` rows for Density, Span, Centre, Band, Band-drift, Voices, Period —
  the app-wide parameter control, no raw `Slider`.

Persisted via `StudioDefaultKeys` (new `field.autoPlay.*` entries), NOT raw `@AppStorage`
literals at the use site — the #163/#170 rule, and the rename test already pins that file.

---

## Honest limitations, to be written into the code

1. **Self-play runs only while the play surface is mounted** — i.e. while the floating visual
   is on screen (default on). Closing the window stops it. This is a real limit, not a bug to
   discover; if the founder wants it to survive a closed window, that is Option B and a
   separate slice.
2. **Device-verify required.** Timing, whether the generated part sits musically under the
   generated take, and whether 0.18 s is the right generated-note length are all ear
   judgements. Nothing in CI can answer them.
3. `bandDrift` below ~0.34 will not change the octave (documented in the core). The default
   0.2 therefore starts as a visual-only wander — deliberate, but the panel copy must not
   promise otherwise.

## Slice order

- **2c-1** `FieldAutoPlay.cell(forTick:ticksPerCell:)` + tests (pure, blocking bundle).
- **2c-2** `TouchInstrumentUIView`: `autoPlay` + display link + hand-wins guard + generated
  note through `sound(...)`.
- **2c-3** the panel control + `StudioDefaultKeys` + wiring through `FloatingVisualWindow`.
- **2c-4** device-verify with the founder; then #220 folds the ARP in as a mode.
