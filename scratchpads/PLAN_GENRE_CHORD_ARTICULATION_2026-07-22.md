# PLAN — Genre-Rhythmus in die hörbare Akkord-Artikulation (2026-07-22)

## Warum (Root-Cause, nach 3 fehlgeschlagenen DSP-Zyklen)
Founder: „Das Genre Problem nicht behoben." Diagnose von Grund auf:
- Drums = stumm (`silentBeat()`), Auto-Leads = aus (`leadDensity 0`). Übrig: gehaltene Pad-Akkorde + Timbre + Harmonie.
- ALLE 13 rhythmischen Genres (ska/rocksteady/klezmer/rock/punk/rocknroll/heavyMetal/jazz/oriental/disco/futuristic/dubTechno/trap) sind `sustained:true` → laufen durch **denselben** `heartbeatOnsets`-Pfad. Dessen Onset-Rhythmus ist NUR von `energy`/`syncopation` getrieben — **genre-blind**.
- Frühere Genre-Distinktheit (Beat-Signatur, `hatRate`, Energy-Hats) lag alle in der **stummen Drum-Reihe** → unhörbar (DEAD-END im Ledger). Cutoff/Brightness (v333/334) tunten nur das Timbre der gehaltenen Fläche = schwacher Cue.
- Rhythmus & Artikulation = stärkster Genre-Cue, aktuell 100% genre-blind. DAS ist der Grund.

## Was (der Hebel)
Genre-spezifische Akkord-Artikulation im hörbaren Pad, abgeleitet aus dem VORHANDENEN `beatArchetype`:
- `.offbeat` (ska/rocksteady/klezmer) → **skank**: kurze Chops auf den Offbeat-8teln (Schritt %4==2).
- `.fourOnFloor` (disco/futuristic — die sustained-Vertreter) → **stab**: Akkord auf den Beats (%4==0), bei hoher Energie 8tel-Puls.
- `.backbeat` (rock/punk/rocknroll/heavyMetal/jazz/oriental) → **comp**: Betonung 2&4 (%8==4) + Synkope bei Energie.
- `.halfTime`/`.none`/`.signature` (doom/vaporwave/sciFi/classical/meditation/selfObs/dubTechno/trap) → **sustained**: delegiert an bestehenden `heartbeatOnsets` = BYTE-IDENTISCH (calm=still-Kern unangetastet).

Arpeggiated-Genres (eighties/synthwave/earlySynth/psytrance) bleiben Arp (eigener Zweig, unberührt).
Bio bleibt: `energy` skaliert Dichte/Intensität obendrauf; Genre-Signatur ist immer präsent (= „erst individuell").

## Wie (minimal, test-first, null Regression)
1. `MusicStyle.swift`: `enum ChordArticulation { skank, stab, comp, sustained }` + `var chordArticulation` (aus `beatArchetype`).
2. `BioComposer.swift`: neue reine `chordOnsets(secStart:secLen:energy:syncopation:articulation:)`; `.sustained` → `heartbeatOnsets(...)` (identisch). Im `profile.sustained`-Zweig (~1612) `heartbeatOnsets` → `chordOnsets(..., articulation:)`. `articulation`-Param an `composeHarmonic` (default `.sustained`), an beiden Call-Sites `input.style.chordArticulation` durchreichen.
3. Tests: skank→Offbeats, stab→Beats, comp→2&4, sustained→identisch zu heartbeatOnsets; Determinismus; drei Genres messbar verschiedene Onset-Sets bei gleichem Bio.

## Risiko/Mitigation
- „Zu busy / Drum-Feel": kurze Chops, warmes Pad-Timbre, bio-skaliert; meditativer Kern unberührt. Founder-Feintuning pro Genre = Follow-up, nicht falscher Hebel.
- Determinismus: reine Schritt-Modulo-Platzierung, kein RNG in der Platzierung (Velocity nutzt bestehenden `hVel`).

## Gate: proceed (Council). Danach Founder-Ohr entscheidet Feintuning.
