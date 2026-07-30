# PLAN — #253 A5, the LEAD's rhythm character (BUILT, REVERTED, NOT RECOVERABLE)

**Status: BLOCKED on the founder decision in #255. Do not build this until #255 answers (a).**

## Why this file exists

A5 was built in full on 2026-07-30 and reverted in the same cycle (`2a28f28`), because there is no
lead melody in this product: all 25 curated genres set `HarmonicProfile.leadDensity == 0`, so
`BioComposer.composeHarmonic`'s melody block never runs and no `.lead`-role note is ever composed. A
Mood-panel "Lead rhythm" Picker would have done nothing on every genre — the #135/#164/#227
lying-control defect.

**The code is GONE.** `2a28f28` reverted it with `git checkout --`, so it is not in that commit, not
in any other commit, not in a stash, and not in a dangling object (a reviewer checked all four,
including `git fsck --lost-found`). `2a28f28`'s body said "the diff is in this commit's body", which
was false; this file replaces that pointer. Re-implementation is ~60 lines and the design below is
the whole of it — nothing about it was hard, and the two non-obvious traps are recorded so they are
not re-discovered.

## The design, as it was built and would be built again

All of it inside `BioComposer.composeHarmonic`'s `if profile.leadDensity > 0` block, plus the usual
four wiring points (`Input` field → `composeHarmonic` param → both call sites → `StudioDefaultKeys`
+ a Mood-panel `Picker` → the `Input` builder in `EchoelStudioView`).

1. **Density needs no inference.** Unlike `padRhythm` (which had to COUNT the path it replaces to
   find an equivalent rate), the lead already computes its own `count`, so the density handed to
   `RoleRhythm` is literally `Float(count) / Float(stepCount)`. Reuse `roleRhythmOnsets(secStart: 0,
   secLen: stepCount, sectionIndex: 0, …)` — the whole bar is one "section" for the melody.
2. **`count` must follow the onsets.** `let count` becomes `var count`, and after a non-empty
   `roleRhythmOnsets` result, `count = leadBeats.count` — BEFORE `motifDeltas(count:)` is built.
   A motif of 5 deltas walked over 3 onsets silently truncates the contour's answer phrase.
3. **Golden law:** the `rng.next()` seed draw sits INSIDE `if let character = leadRhythm`, so the
   `nil` take stays byte-identical.
4. **`nextOnset` guard.** `leadBeats.isEmpty ? stepCount : (i+1 < count ? leadBeats[i+1].start :
   stepCount)`. Needed in two places, because a character's cells can sit a single 16th apart while
   the even spread's never do: the note LENGTH clamps to it, and the grace-note condition uses it
   instead of `stepCount` (an ornament pushes the main note to `startStep+1`, which would otherwise
   land on top of the following onset). On the default path it equals `stepCount`, so both uses
   reduce to the pre-A5 expression exactly.
5. **Skip the mood syncopation nudge under an override** — it exists to push an on-beat note off the
   grid, and a character that chose its own cells would then be pushed off ITS grid.
6. **Velocity scales, it does not replace.** `if !leadBeats.isEmpty { velocity = clamp01(velocity *
   leadBeats[i].level) }` as a SEPARATE statement after the existing expression, so the phrase arc,
   the metric accent and the humanize spread all survive and the nil path is untouched.
7. **The body's floor of 3 is deliberately NOT re-imposed.** That floor guards the EVEN spread (two
   evenly-spread notes are two strong beats = the bare chord-tone leap removed on 2026-07-11).
   `sparse` meaning sparse is the point of an explicit override. `roleRhythmOnsets` always sounds
   the section downbeat, so the line can never vanish and always opens on step 0.

## What A5 must NOT claim

`push` is still unread on every `RoleRhythm` consumer (`Note.startStep` is a whole 16th) — that is
A2b. No UI copy may promise swing or a laid-back feel.

## What wakes WITH A5 if #255 goes to (a)

Five dormant paths, all listed in `Tests/CISmoke/LeadRoleAbsenceTests.swift`'s failure message:
the Mixer's Lead fader, `IntroAttenuation.leadFactor`, `tameLeadPitch`, `leadVoice` (a live
`PolySynthVoice(maxVoices: 3)` attached to the engine and polling at 100 ms while receiving zero
notes), and A5 itself.
