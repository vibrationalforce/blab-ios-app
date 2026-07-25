# Echoel — Product Definition (canonical)

**Status:** CANONICAL as of 2026-07-25. Supersedes `DMMW_ARCHITECTURE.md`
(the "Digital Multidimensional Multimedia Workstation" goal, 2026-06-21).
Founder delegated this call in full ("Du entscheidest… etwas das einfach zu
begreifen, zu vermarkten und zu pflegen ist"); decided via Grand Council
2026-07-25 and logged in `decisions.csv`.

---

## The one sentence

> **Echoel is a bio-reactive instrument. Your body plays it, and its output is
> multidimensional — sound, image, light, space.**

That is the whole product. There is no second product, no workstation, and no
acronym. If a description needs more than this sentence, it is off-target.

## Why "DMMW" is retired

"Digital Multidimensional Multimedia Workstation" failed all three founder
criteria at once:

- **Grasp:** a five-word acronym nobody can repeat after hearing it once.
- **Market:** "workstation" puts Echoel on FL Studio / Cubasis / Ableton turf,
  where a solo developer competes on feature parity forever and always loses.
- **Maintain:** a workstation is an infinite surface — every DAW feature a user
  expects becomes a support obligation.

It also cost real focus: the 2026-07-19 Grand Council already recorded
"Fokusverlust seit DMMW" (343 files, +62 % cruft). The term is retired
permanently. The *multidimensional output* it was reaching for is kept — as a
property of the instrument, not a product of its own.

## The boundary: Editor ≠ Workstation

This is the line that decides every future keep/cut question. Ask: **is this
about the sound the instrument is making right now, or about arranging material
over time?**

| KEEP — the instrument | CUT — the workstation |
|---|---|
| Generative bio engine (the home) | Arrangement / clips timeline |
| Flow + Loop modes | Multi-track recording & mixing desk |
| **Patch editor** — shape and save the sound | Audio-file import as timeline regions |
| **Piano roll** — fix/shape the notes of the current loop | Video capture, trim, edit |
| Curated genres | AUv3 hosting and the AUv3 plugin target |
| Output stage (below) | RTMP / broadcast |
| Export: audio · MIDI · visual recording | Subscription commerce |

**Craft tools are instrument controls, not DAW surfaces.** A synth you cannot
tune is not an instrument. This resolves task #131: the patch editor and the
piano roll **return as doors** in the instrument home.

There is also a hard technical reason the piano roll stays: `PianoRollView`
**publishes `MusicalFrame`** — it is the source that tells the visuals and the
light rig what is currently sounding (`Core/MusicalFrame.swift`,
`Core/EngineBus.swift`, consumed by `Views/MetalBioView.swift`,
`Sync/MusicMediaMapping.swift`, `Studio/SpectrumAnalysis.swift`). Cutting it
would sever the spine of the differentiator, not merely remove a convenience.

## The two layers

### Layer 1 — The Instrument (what is sold)
The generative bio-instrument is the home (`EchoelStudioView`). Body signals
(camera rPPG · BLE heart-rate strap · HealthKit) drive the composition live.
Flow mode is free and contemplative; Loop mode is tempo-locked and producible.
The player can shape the sound (patch editor), correct the notes (piano roll),
pick a curated genre, and export.

### Layer 2 — The Output Stage (what makes it unique)
Not a separate product and deliberately **not** given a brand name — it is the
instrument's output, the way a synth has audio out. One typed bus carries
`BioFrame` + `MusicalFrame`; each medium is a subscriber that maps those signals
into its own domain:

| Medium | Path | Standard |
|---|---|---|
| Sound | audio master | — |
| Image | `MetalBioView` · `SpectralColor` · visual recording | — |
| Light | `EchoelLux` Art-Net + sACN | open DMX-over-IP |
| Space | `ADMOSCSender` | ADM-OSC |
| Body | `HapticController` | CoreHaptics |
| Control | OSC · MIDI/MPE in & out | OSC, MIDI 2 |

Adding a medium means adding a subscriber — never a new surface. That is what
makes this maintainable by one person.

Open standards, no SDK lock-in, zero external dependencies. This is the moat:
the bio-reactive generative core plus standards-native multidimensional output
is a combination no DAW competitor has, and it is not something a feature
checklist can copy.

## Ship gate — "Instrument-Complete v1"

Replaces the dead criterion *"bis die gesamte DMMW auf Profi-Level ist"*, which
became permanently unreachable once the workstation half was dismantled (#121).

Five binary checks. All five true → lift the TestFlight freeze, ship, and let
the founder test on device:

1. **Klang** — curated genres sound professional and keep their identity (no
   convergence bug, #81/#82). Founder's ear is the judge.
2. **Kontrolle** — the player can shape the sound (patch editor) and correct the
   melody (piano roll). Both reachable. (#131)
3. **Modi** — Flow and Loop both work as specified (#128).
4. **Ausgabe** — the visual is live and contemplative on device ("wow"). Light
   and space are demonstrable but not required for v1.
5. **Stabilität** — clean launch, no black screen, no menu freeze, no known UI
   trap.

Deliberately finite and checkable. It does not move when the roadmap moves.

## The four quality axes (founder 2026-07-25)

Verbatim: *"Du entscheidest alles. Creative, Immersive, accessible, health (no
claims)."* This is not a feature list — it is the standing frame for **how quality
is judged**, and it sits one level below the Editor ≠ Workstation boundary. That
boundary decides *whether something belongs to the product*; these four decide
*whether what belongs is any good*, and therefore what gets a cycle next.

| Axis | What it means here | How it is checked |
|---|---|---|
| **Creative** | The player can make something and then *shape* it — generate, correct the notes, shape the timbre, keep it, export it. A capability the user cannot reach does not count. | Every capability has a reachable door. Doorless = broken. |
| **Immersive** | The output stage is the experience, not a readout: the visual is live and contemplative; light and space are real outputs, not demos. | On device: does it produce the "wow"? Founder's eye judges. |
| **Accessible** | Legible numbers, VoiceOver labels, Dynamic Type, ≥44 pt tap targets, reduce-motion honoured, flash ≤ 3 Hz. Accessibility is a first-class axis, **not** a polish pass at the end. | HIG/WCAG are hard numbers — check them, don't estimate. |
| **Health — no claims** | Physiology is a first-class, science-based *modulation source*. Cited research and self-observation are allowed; healing, therapy, diagnosis and wellness framing are never. | Any bio-adjacent copy passes the brand guardrails below. |

**Practical rule:** a slice that serves none of the four axes goes to the back of
the queue, however tidy it looks. (Applied immediately on 2026-07-25: the DAW-model
hygiene slice #132 lost its place at the front to an accessibility fix with a
measurable defect behind it.)

## Brand guardrails (unchanged, restated)

Biofeedback is a first-class, science-based modulation source — **not** wellness,
therapy, or healing. Never "healing frequencies", chakras, Solfeggio, BLAB, or
Vibrational Force. Claim only what ships. Data is for self-observation, never
medical diagnosis. Flash rate ≤ 3 Hz (WCAG).

## What this changes for the roadmap

- The pure-instrument epic (#121) continues unchanged — Slices 4–6 keep removing
  workstation surfaces and the DAW model.
- Task #131 is **decided**: re-door the patch editor and the piano roll (and the
  spatial stage, which belongs to the output stage). Re-dooring must NOT grow the
  `EchoelStudioView` sheet chain — reuse a slot or consolidate to one
  `.sheet(item:)` enum first (black-screen metadata law).
- `DMMW_ARCHITECTURE.md` is superseded; keep it only as history.
