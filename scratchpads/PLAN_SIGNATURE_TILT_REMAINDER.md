# PLAN — #403 Slice 2 remainder: register and density

**Status:** PLAN, second version. No code yet. Written 2026-08-05, **rewritten the same day
after a verification pass refuted most of the first version's evidence.**
**Epic:** #403 — *"Wenn verschiedene User das selbe preset auswählen und nichts verändern
sondern einfach rendern, soll er individuell nach der Person klingen."* (Founder, 2026-08-05.)

---

## ⛔ READ THIS BEFORE THE REST: how the first version failed

The first version of this plan built its whole argument on `ambientMelody`, `dubMelody` and
`trapMelody` — **three functions with no callers.** `BioComposer.swift:691-695` and `:715-722`
say so in the source, `RoleRhythm.swift:107-112` repeats it, and
`Tests/CISmoke/LeadRoleAbsenceTests.swift:11` pins it in the blocking bundle. I grepped for
the words "density" and "octave", found real code, quoted line numbers, and never asked
whether anything calls it.

Three of the conclusions inverted once the live paths were read. That is why this file now
marks every claim with the function it lives in and whether that function runs.

**The rule this cost:** in a composer with dormant genre builders, `git grep` for a CONCEPT
finds the dead implementation first — it is usually the more literal one. Establish the caller
chain before quoting a line as the behaviour.

---

## 0. The one law this slice hangs on (unchanged, and verified)

`EchoelStudioView.swift:7723-7726`, at the shipped Slice 2 call site:

> Both genre-tempo call sites in this method get the tilt and the LOCKED branch above
> deliberately does not: **a number the user typed is theirs, and a fingerprint quietly moving
> it would be a lying control.**

**Tilt the BODY-DERIVED term. Never tilt the USER-OWNED term.** Slice 2 obeys it by
construction: `:7704` and `:7728` are tilted, the `lockedBPM` branch at `:7698` is not.

---

## 1. The live picture (verified 2026-08-05)

### 1a. `MoodProfile.liveliness` has THREE user writers — and **zero live readers**

Writers in `EchoelStudioView.swift`: `moodKnob("Liveliness", $mood.liveliness)` at `:4962`,
the mood-pad drag `mood.liveliness = Float(y)` at `:1521`, and — missed by the first version —
`mood = preset.profile` at `:5215`, the **mood-preset loader**, which writes all eight
dimensions at once. Those three are the only writes of `mood` in the file; `mood` is
`@State private var mood = MoodProfile()` (`:291`), not persisted. `WeatherMood.blend` mutates
a copy (`var moodForInput = mood`, `:7534`) — `MoodProfile` is a struct, so that is a real
copy and the user's value is untouched.

**But all four reads of `liveliness` in the engine (`BioComposer.swift:1251`, `:2279`, `:2365`,
`:2376`) are in dormant code.** `:1251` is in `ambientMelody` (no caller); the others are
inside `if profile.leadDensity > 0` (`:2277-2399`), and all 33 `HarmonicProfile`s in
`MusicStyle.swift` pass `leadDensity: 0.0`.

So the first version's sentence *"the user's knob keeps its full authority as a multiplier on
top"* was **false** — the knob has no authority over anything today. Density for the roles
that sound is owned by `RoleRhythm`, which by its own precedence note (`RoleRhythm.swift:22`)
outranks `MoodProfile.liveliness`.

*(Naming correction: there is no `BioComposer.Input.liveliness`. The field is
`MoodProfile.liveliness` (`BioComposer.swift:79`); `Input` carries `mood: MoodProfile` (`:266`).)*

### 1b. `busy` is genuinely body-derived — and is consumed through THRESHOLDS

`BioComposer.swift:438`: `let busy = clamp01((0.6 * arousal + 0.4 * (1 - calm)) * settle)`,
inside `musicalState(coherence:hrvNormalized:heartRateBPM:)` (`:431`), bound once in `compose`
at `:655`. Inputs are bio only; no control writes it. ✔ body-derived.

Its **live** consumers:

| Site | Shape |
|---|---|
| `:1607` `heartbeatActive` | `energy >= 0.5` — a gate; below it a sustained section emits ONE held onset |
| `:1621`/`:1623` | stride buckets at `0.68` / `0.82` — three discrete states |
| `:1678` `.stab` / `:1682` `.comp` | `>= 0.6` / `>= 0.62` |
| `:1674` `.skank` | does not read the body at all |
| `:2094` arp step | `busy > 0.6 ? 2 : 4` |
| `:2224` pulse gap | `busy > 0.7 ? 2 : 4` |
| `:1378` `appendBass` | `motion > 0.32`, where `motion = clamp01(busy*0.7 + (1-calm)*0.4)` (`:1375`) |
| `:2356` note length | **continuous** |

**This is the finding that kills the first version's Slice 3.** A tilt on `busy` is, for almost
every consumer, either nothing at all or a whole-texture jump at 0.5 / 0.6 / 0.62 / 0.68 /
0.7 / 0.82 — *verbatim the "invisible for most, jarring for a few" argument the first version
used to rule out `darkness`.* The objection does not distinguish the two dimensions; it
applies to both.

Second hazard: `busy` is one local fanning out to ~10 consumers, so tilting it at `:655` also
moves note length, bass presence, arp subdivision and pulse density. "Tilt the `busy` term" is
not a small change.

### 1c. `darkness` — the threshold kill stands, and is stronger than claimed

Two reads exist in `Sources/`: `BioComposer.swift:1254` (dead `ambientMelody`) and `:1968`
`let octShift = mood.darkness > 0.6 ? -1 : 0` in `composeHarmonic` — **the one live reader.**
No reader anywhere uses `darkness` as a magnitude. Default is `0.5` (`:88`), so `octShift == 0`
on a fresh install. Writers are the same three as `liveliness`.

### 1d. Register has ONE live mechanism, not N genre builders — and this makes it CHEAPER

The first version's octave table (dub 4 / dub root 2 / trap 808 2 / trap lead 5 / ambient
`4 + …`) is real text in dead functions. The live register is entirely in `composeHarmonic`,
driven by two `HarmonicProfile` fields (`MusicStyle.swift:36` `padOctave`, `:38` `leadOctave`)
plus the single `octShift`:

- pad `:2020` — `octave: profile.padOctave + octShift`
- bass `:2006` — `let bassOct = max(0, profile.padOctave - 1 + octShift)`
- lead `:2342`, `:2381` — `profile.leadOctave + octShift` (inside the dormant `leadDensity > 0` block)

**Two of the first version's claims invert here:**

1. *"a global transpose would move bass and lead together and destroy the separation"* — the
   shipped `octShift` **is** a global transpose, and bass is defined *relative to* the pad
   (`padOctave - 1`). Separation survives **because** they move together. The dangerous option
   is the one the first version preferred: a harmony-only offset would break that relation.
2. *"`foldLeadPitch` would fight it from the other side"* — **there is no `foldLeadPitch`.**
   The function is `tameLeadPitch` (`BioComposer.swift:1818`) and it serves the dormant lead
   path (`LeadRoleAbsenceTests.swift:63` lists it among five dormant paths). It cannot fight
   anything.

### 1e. What a default take actually is

`.selfObservation` is the shipped default (`StudioDefaultKeys.swift:47`). Its profile
(`MusicStyle.swift:1449-1451`) is `progression: [0, 5, 3]`, `chordTones: [0, 2, 4, 6]`,
`padOctave: 3`, `leadOctave: 5`, `leadDensity: 0.0`, `sustained: true`.

`BioComposer.swift:1916` reduces a sustained profile with more than two chords to **ONE chord
section per take**. So a take is **one** held chord — not "three chords", as the first version
wrote — giving 4 pad tones + 1 sustained bass root = the 5 notes the device log shows.

---

## 2. What this leaves, honestly

Neither dimension is the clean continuous tilt the first version promised:

- **Density via `busy`** — body-derived (good), but threshold-consumed (the disqualifying
  defect), and it fans out far beyond density.
- **Register via `octShift`** — one insertion point (good, and much cheaper than believed),
  but octaves are integers, so any fingerprint-driven register move is a ±1 **placement**, not
  a tilt. That is defensible *as a placement* — a stable per-person choice of low or high
  register is a legitimate handwriting and does not pretend to be continuous — but it must be
  named that way, not sold as a tilt.

**So the next step is not a slice. It is an inventory.** Before choosing a dimension, list the
**live, continuous, body-driven** quantities in `composeHarmonic` and `RoleRhythm` — the only
places where a tilt can be a tilt. `BioComposer.swift:2356` (note length from `busy`) is the
one continuous consumer this pass found; there are probably a handful more in `RoleRhythm`,
whose precedence note says it owns density for the roles that sound.

Ranked candidates for the cycle after that inventory:

1. **Register placement (±1 octave) from habitual breath rate**, at `octShift`. One line, one
   insertion point, honest framing, and the mechanism already exists and is proven to preserve
   bass/pad separation. `octShift` is currently `-1` or `0`; a fingerprint could reach `+1`,
   which the shipped code never produces.
2. **A continuous quantity found by the inventory**, tilted with the shipped
   `StudioCalculator.tilted`.
3. Nothing in the composer — spend the epic's remaining budget on `TakeDistance`-guided seed
   diversity instead, which is already continuous by construction.

### Constraints any slice must carry

- **`StudioCalculator.tilted`'s in-range promise is about ACCEPTED inputs.** Read `:294-317`,
  not the summary: `tilt == 0`, a degenerate window, a non-finite bound or a non-finite
  headroom all return the input **unchanged** — `tilted(200, within: 44...66, by: 0)` is `200`.
  The source doc states this at `:285-289` and `ThePaceIsTiltedInsideTheGenreTests.swift:114`
  and `:174` pin it. The first version dropped the qualifier. Two clamps are load-bearing
  outside the documented domain (`anchor` at `:308`, `amount` at `:309`) — so "the shape alone
  guarantees it" is true only on the declared domain, and a NEW driver must respect it.
- **`hrvNormalized` has no published span.** `tempoTilt` maps onto `habitualSpan = 50...90`
  (`PerformerSignature.swift:351`); an HRV driver is already 0…1 and needs its own stated
  mapping rather than "copy the pattern".
- **The unlearned case must be exactly 0.** `tempoTilt` returns 0 when `heartRateCount == 0`
  (`:333`) and ramps in over `confidentAfter = 8` (`:363`). Any new tilt copies that, so a
  never-measured user renders bit-identically.
- **HRV is learned more slowly than heart rate.** `observing` treats `hrvNormalized == 0` as
  "not measured" (`:195-198`), and `FaceExpressionBioPublisher.swift:153` hardcodes `0`, so
  that source never teaches the channel. Camera rPPG, HealthKit and Polar do. A fresh user has
  a pace tilt before any HRV-driven one.
- **Two live composer-input paths.** `EchoelStudioView.swift:7549` and
  `LaneComposerInput.swift` (per-lane mood at `:35`, reached from `EchoelStudioView.swift:8032`).
  Any new `Input` field must decide whether lanes inherit it.
- **A guard cannot assume the effect is visible.** `.skank` ignores the body entirely; the
  other characters change only across a threshold. A behavioural test has to name a genre and
  a body state that straddles a specific edge — and needing to do that is itself evidence the
  quantity is not continuous.

---

## 3. Council

- **Skeptic** — the first version of this plan was refuted on its own evidence, so the gate is
  now the inventory, not a build. The #81 failure mode ("erst individuell, dann klingt alles
  gleich") is still the thing to avoid, and threshold-driven dimensions are the fastest route
  into it: they sort performers into two or three buckets, which is the opposite of individual.
- **Vision-Keeper** — on-vision, but "sounds like you" is not earned by anything here and must
  stay out of `ContentPipeline/CLAIMS.md` and the store text.
- **User-Advocate** — §0 still governs. And a ±1 register placement must be described to the
  founder as a placement, not as a continuous fingerprint.
- **Shipper** — one inventory pass, then one slice. Do not build from this document's first
  version, which is preserved only in git history.

**Gate: inventory the live continuous body-driven quantities. Then Slice 3.**

---

## 4. What this plan is NOT

It does not touch the crackle line (#404/#405/#406/#407/#409), and nothing here claims that
individuality addresses anything the founder reported about sound quality.
