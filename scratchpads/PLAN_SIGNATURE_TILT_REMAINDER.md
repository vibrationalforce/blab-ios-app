# PLAN — #403 Slice 2 remainder: register tilt and density tilt

**Status:** PLAN. No code in this commit. Written 2026-08-05 after Slice 2 (pace tilt) shipped.
**Epic:** #403 — *"Wenn verschiedene User das selbe preset auswählen und nichts verändern
sondern einfach rendern, soll er individuell nach der Person klingen."* (Founder, 2026-08-05.)
**Why a plan and not a cycle:** the epic's own entry says ERST PLAN + Council. Both remaining
dimensions turned out to route through values a USER owns, and shipping either naively would
have built a lying control. That is the finding this document exists to record.

---

## 0. The one law this whole slice hangs on

`StudioCalculator.tilted`'s shipped call sites already state it, and it is the rule the two
remaining dimensions must obey:

> Both genre-tempo call sites in this method get the tilt and the LOCKED branch deliberately
> does not: **a number the user typed is theirs, and a fingerprint quietly moving it would be
> a lying control.**

Restated as the design rule for everything below:

**Tilt the BODY-DERIVED term. Never tilt the USER-OWNED term.**

Slice 2 obeyed it by construction: it tilts the genre-folded *body* tempo and leaves
`lockedBPM` untouched. Both remaining dimensions have a user-owned surface, so neither can
copy Slice 2's call site — they need a different insertion point, and finding it is most of
the work.

---

## 1. What was checked, and what it killed

Everything here is a source reading from 2026-08-05, not a recollection. Each line names the
symbol so the next session can re-check it rather than trust this file.

### 1a. Density — `mood.liveliness` is USER-OWNED. Do not tilt it.

`BioComposer.Input.liveliness` is documented `// 0 sparse/still … 1 busy/active (density)`.
It has **two** user-facing writers in `EchoelStudioView`:

- `moodKnob("Liveliness", $mood.liveliness)` — a direct control in the mood panel;
- the mood **pad**, which writes `mood.liveliness = Float(y)` from a drag.

Plus a third, non-user writer: `WeatherMood.blend` nudges a *copy* (`moodForInput.liveliness`)
before it reaches the composer, deliberately leaving `mood` itself alone.

So `liveliness` is a control the user sets and can see. Tilting it fails §0.

**But the density the composer actually uses is a PRODUCT, and the other factor is the body:**

```
let density = clamp01(busy * (0.6 + 0.8 * clamp01(mood.liveliness)))
let noteCount = 2 + Int((density * 6).rounded())          // 2…8
```

`busy` is body-derived — the file says so where it is computed: *"`busy` (density) then rises
with arousal"*, alongside the textbook stress signature (↑HR, ↓HRV). **`busy` is the term to
tilt.** It is the body's contribution, it has no control anywhere, and the user's knob keeps
its full authority as a multiplier on top.

**Consequence worth stating before anyone builds it:** because the two multiply, a user who
has set Liveliness to 0 gets density 0 whatever their fingerprint says — the tilt cannot
override the knob, only shade it. That is the correct hierarchy and it is also the reason the
audible effect will be modest on the sparsest genres. Do not "fix" that by moving the tilt
outside the product.

### 1b. Register — `mood.darkness` is USER-OWNED **and is not a continuum**. Two independent kills.

Same two writers (`moodKnob("Darkness", $mood.darkness)` and the pad's `mood.darkness =
Float(1 - x)`), so §0 already rules it out. The second kill is the more interesting one and is
already written down in `EchoelStudioView` around the mood-wiring note:

> `MoodProfile.darkness`, whose ONLY two readers in the whole engine are
> `mood.darkness > 0.6 ? -1 : 0`

`darkness` is consumed as a **threshold**, not as a magnitude. `BioComposer` reads it as
`let octave = 4 + (mood.darkness > 0.6 ? -1 : 0)`. A "tilt" of a threshold input is not a
tilt — it is either nothing at all or a whole-octave jump when it happens to cross 0.6. Two
performers whose fingerprints differ by any amount short of the crossing are bit-identical;
two who straddle it differ by twelve semitones. That is the worst possible distribution for
an individuality feature: invisible for most, jarring for a few.

**So register cannot ride `darkness`.** It needs a register offset the composer owns.

### 1c. Where register is actually decided — and why a global transpose is wrong

Register is **per-genre and per-role**, as hardcoded octave constants inside each genre
builder in `BioComposer`. Sampled:

| Site | Octave | Role |
|---|---|---|
| dub triads | 4 | harmony |
| dub sustained root | 2 | bass |
| trap 808 root line | 2 | bass |
| trap bell lead | 5 (`leadOctave`) | lead |
| ambient line | `4 + (darkness > 0.6 ? -1 : 0)` | lead |

A single global transpose would move bass and lead together and destroy the separation these
constants exist to create — and `foldLeadPitch` (the "piercing top octaves" fold) would then
fight it from the other side. **The register tilt must be a HARMONY/LEAD-only offset with the
bass excluded**, or it is not a register tilt but a key change.

### 1d. Honest scope of the audible effect

On `.selfObservation` — the genre a fresh install opens on, and the one the 2026-08-05 device
log was recorded from — a take is three chords, four sustained chord tones, no lead, five
notes total. Slice 1's own header already says the skeleton has very little room to differ
there. **Register on a five-note sustained take is the dimension that DOES read** (the same
five notes an octave apart is plainly a different piece), while density on the same take is
nearly inert (the count is already at the floor). On busier genres the ranking inverts.

Neither dimension will make `.selfObservation` sound like a different composition. Say so to
the founder rather than letting the epic's headline carry the claim.

---

## 2. The slices, in the order they should ship

### Slice 3 — density tilt (do this first: cheapest, and its insertion point is proven)

1. `PerformerSignature.densityTilt: Double` in −1…1, driven by habitual **`hrvNormalized`**.
   Rationale, stated as a musical handwriting and explicitly NOT as a statement about the
   body (the file's own §2 law): variability of the body → variability of the part. Unlearned
   (`hrvCount == 0`) ⇒ **exactly 0**, so a never-measured user renders bit-identically —
   the same safety story `SignatureIsThePersonNotTheMomentTests` pins for `seedSalt`.
2. New `BioComposer.Input.densityTilt: Double = 0` — a defaulted field, so every existing
   construction site compiles untouched and behaves identically.
3. Apply with the SHIPPED `StudioCalculator.tilted` at the `busy` term only, `within: 0...1`.
   Reuse, do not re-derive: the "fraction of the remaining headroom" shape is what makes the
   bound structural rather than clamped, and it already carries its own doc and guard.
4. Wire it in `makeComposerInput` — one folded line, no new surface (the shape Slice 1 used).
5. Guard in `Tests/CISmoke`: (a) an unlearned signature leaves the note count unchanged for a
   sweep of inputs; (b) two learned signatures at opposite HRV extremes produce different
   counts on a busy genre; (c) the density never leaves 0…1 for ANY tilt — swept, not
   sampled, for the same reason `ThePaceIsTiltedInsideTheGenre` sweeps: an "offset then
   clamp" refactor passes every hand-written case and then saturates a whole population.

### Slice 4 — register tilt (needs one decision first)

Blocked on a choice this plan deliberately does not make alone, because it is a musical call
and the cheap options are all slightly wrong:

- **(a) A composer-owned `registerTilt` that shifts harmony/lead octaves by at most ±1, bass
  never.** Honest, but ±1 octave is a big step and the in-between is empty — the same
  "threshold not continuum" defect that killed `darkness`, just with a better-chosen edge.
- **(b) Shift the harmonic skeleton's degree window instead of the octave** — a few scale
  degrees up or down, continuous, always in key. Musically subtler, more code, and it
  interacts with `voiceLeading` and the chord-tone imaging in ways that need reading first.
- **(c) Drop register; spend the slice on a third dimension instead** (ornament density,
  articulation, or the harmonic-profile choice), if register cannot be made continuous
  cheaply.

**Driver, if it goes ahead:** habitual **`breathRate`**. Breath and tessitura have a real
musical correspondence (wind and voice) that can be stated without going near a health claim.
Unlearned ⇒ 0, as always.

---

## 3. Council

- **Vision-Keeper** — on-vision: this is the body playing the instrument, which is the product
  sentence. The risk is the copy, not the code: "sounds like you" is not earned by either
  slice and must not appear in `ContentPipeline/CLAIMS.md` or the store text.
- **Skeptic** — the failure mode is #81 in reverse ("erst individuell, dann klingt alles
  gleich"): a tilt that can cross a genre boundary makes every genre sound like its
  neighbours. `tilted`'s headroom shape is what prevents it; any new dimension must use that
  function rather than its own arithmetic. Also: neither slice is verifiable without a device
  listen, so ship them one at a time.
- **User-Advocate** — §0 is the whole review. A knob the user set must keep its meaning; the
  fingerprint may shade what the BODY contributes and nothing else.
- **Shipper** — Slice 3 is one defaulted field plus one line plus a guard. Slice 4 is a
  decision, not a cycle. Take Slice 3 next and leave Slice 4 named.

**Gate: proceed with Slice 3. Slice 4 holds for the (a)/(b)/(c) call.**

---

## 4. What this plan is NOT

It does not touch the crackle line (#404/#405/#406/#407), and it does not claim that
individuality is a fix for anything the founder reported about sound quality. Those are
separate reports with separate evidence.
