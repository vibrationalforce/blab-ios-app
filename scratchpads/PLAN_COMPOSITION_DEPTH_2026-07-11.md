# PLAN — Composition Depth (Founder 2026-07-11)

**Founder brief (verbatim core):** "Die Kompositionen müssen nicht statisch im Takt
sein aber sie sollten Sinn ergeben und kreativ sein zugleich. Interessante am
Herzschlag orientierte Rhythmen, punktierte und Synkopen etc. Und vor allem starke
Interpolierung. … Rockakkorde, Kirchentonarten und vieles mehr. Die Genres sind
auch noch ausbaufähig."

## Doctrine resolution (Council 2026-07-11)

The 2026-07-09 "Melodie komplett raus / Flächen still" order was about the **exposed
harsh wave-LEAD timbre + loud melody**, NOT about movement. The new law, which is the
founder's own "je nach Biofeedback immer individuell":

> **Calm body = still Fläche (the liked default). Active body = alive** — rhythm and
> movement return, but in the **pad/harmony timbre**, never a naked lead.

Everything below keeps this: at rest, bit-identical to today; only body energy adds life.

## "Skills & Datenbanken" answer

Founder asked to "search all skills and databases OR create all possibilities myself."
Per zero-deps + MIT/BSD-only law: **build in-house, reference public-domain theory.**
We already own the theory core:
- `MusicalKey.swift` — **42 scales incl. all 7 church modes** (Ionian…Locrian) + harmonic/
  melodic minor modes, maqam/raga/pentatonic families. Church modes = DONE.
- `MusicTheoryPrimer.swift`, `BioComposer` — progressions, voice-leading, cadences,
  turnarounds, moods (syncopation/humanize/romance/tension/weird), motif contour.
No external music DB needed; chord/rhythm vocabularies are small tables we author.

## Cycles (Ralph — one per TestFlight, TDD, bio-scaled, non-regressing)

- **Cycle 1 — Heartbeat onsets (dotted/tresillo) — SHIPPED this session.**
  Pure `BioComposer.heartbeatOnsets(secStart:secLen:energy:syncopation:)`: calm → one
  held onset (unchanged); active → dotted (`[6,4]`) then tresillo (`[3,3,2]`, the lub-dub
  grouping) re-articulations of the SAME chord voicing. Wired into the sustained pad path;
  driven by the composer's `busy` signal (still <0.5). Contiguous, bar-tight, in-key, no
  lead. Reconciled the two "still even when aroused" tests to the new law. 6 pure tests.

- **Cycle 2 — Rock chords + chord-quality vocabulary.**
  Extend `HarmonicProfile.chordTones` beyond triad/7th to named qualities: **power (root+5+oct)**,
  sus2, sus4, add9, 9/11/13. A `ChordQuality` enum → interval sets (pure, tested, in-key via
  `MusicalKey.degree`). Add 1–2 energetic genres that use power/sus voicings (still bio-scaled).
  Keeps the moving-bass + voice-leading. Files: `MusicStyle.swift`, `BioComposer.swift`, tests.

- **Cycle 3 — Strong interpolation ("starke Interpolierung").**
  Two readings, both in scope:
  (a) **Voicing morph** — when the chord changes (progression step / phase advance), glide the
      pad voices from the previous voicing to the next over N steps (crossfade onset velocities +
      shared-tone holds), instead of a hard swap. Voice-leading already picks nearest register;
      add the *temporal* glide.
  (b) **Bio-state morph** — interpolate composition params (density, syncopation tier, brightness)
      smoothly across the ~30 s re-seed boundary so takes evolve continuously, not in jumps.
  Pure, tested; no audio-thread work (composition is off-thread).

- **Cycle 4 — Modal/church-mode-forward genres + genre expansion.**
  Surface the 42 scales as *genre character* (Dorian groove, Phrygian dark, Lydian bright,
  Mixolydian rock) — new curated entries or a scale-forward "modal" family. Vibe-gate the roster
  with the founder (taste selection) before enlarging the offered Picker.

- **Cycle 5 — True per-beat orientation.**
  Thread the actual detected RR-interval / beat positions (from `BioEventGraph` heartbeat onsets)
  into `heartbeatOnsets` so accents land on the *measured* heartbeat, not just the HR-derived
  tempo grid. Deepens "am Herzschlag orientiert" from tempo-grid to literal beat placement.

## Guardrails carried through every cycle
- Calm default stays bit-identical (bio-scaled, threshold-gated).
- No exposed wave-lead in curated genres (movement = pad timbre).
- Always in-key (all pitches via `MusicalKey.degree`), always bar-tight (loop stays clean).
- Pure/seeded/Linux-testable; determinism preserved; no audio-thread changes.
- Enlarging the offered genre roster = **founder Vibe-gate**, not a unilateral add.
