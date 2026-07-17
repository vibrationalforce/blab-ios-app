# PLAN — Harmony-Core (Voice-Leading + Bio-Suggest) · 2026-07-17

Quelle: ANALYSIS_SCALER3_2026-07-17.md Top-1/2/3. Founder-Ask "was können wir von
Scaler 3.3 einbeziehen"; Reihenfolge 1→2→3 vorgeschlagen, kein Widerspruch.

## Council
- Architect: pure value-Schicht in Sequencer/ (neben BioComposer-Inputs), von
  BioComposer konsumiert — koppelt nichts Neues; KEINE UI. Sorge: BioComposer ist
  der Klang-Kern — jede Änderung dort muss opt-in/bit-identisch-by-default sein.
- DSP Purist: kein Audio-Thread-Bezug (Compose-Zeit, MainActor); Rausch-Triade
  unberührt. Sorge: keine.
- Shipper: 3 Slices, jeder einzeln grün + hörbar erst nach explizitem Wiring-
  Schalter im Composer-Input (Flag-los, aber default-neutral). Sorge: nicht mit
  laufendem b)-Fix (ArrangeTimelineView) kollidieren — Harmony-Core berührt
  NUR neue Dateien + BioComposer(+Input) → disjunkt.
- Skeptic: "bit-identisch by default" MUSS getestet sein wie A-Slice; Gefahr:
  Voice-Leading verändert die Registerlage bestehender Takes → nur aktiv, wenn
  der neue Input-Schalter gesetzt ist; Golden-Tests auf unverändertem Input.
- User-Advocate: Founder-Bar = "organisch/professionell" — Hörbarkeit entsteht
  erst mit Schalter-ON per Default NACH Geräte-Verify (Modus-Lehre: Schalter,
  die der Founder nie erreichen kann, sind verboten → der Schalter ist ein
  COMPOSER-INPUT-Feld, das der nächste Deploy default-ON setzt, Rollback = 1 Zeile).
→ Verdikt: proceed. Reihenfolge H1→H2→H3.

## Slices
### H1 — VoiceLeader (pure, M)
`Sequencer/VoiceLeader.swift`: `resolve(from: [Int], to chord: ChordSpec,
strictness: Float, spread: Float) -> [Int]` — wählt die Inversion/Lage des
Zielakkords mit minimaler Summen-Bewegung (common tones halten, Distanz-
Minimierung über Kandidaten-Voicings), strictness ∈ 0…1 (1 = engste Führung),
spread = close/open-Neigung. Deterministisch, Foundation-only. Tests: Distanz-
Minimierung, common-tone-Erhalt, Grenzen (leer/1 Ton), Determinismus.
Wiring: BioComposer nutzt VoiceLeader für Harmony-Rollen-Akkorde, wenn
`input.voiceLeading != nil`; nil ⇒ HEUTIGER Pfad byte-identisch (Golden-Test).
Bio-Mapping (im Composer, nicht im Core): HRV-Trend→strictness, Atemtiefe→spread.

### H2 — ChordSuggest (pure, M)
`Sequencer/ChordSuggest.swift`: Kandidaten = diatonische Funktionen + kuratierte
Borrowings (eigene Theorie-Ableitung, KEINE Scaler-Sets); Ranking = Funktions-
Logik (T→S→D-Neigung) + VoiceLeader-Distanz; Auswahl durch Kohärenz-Selektor
(hoch→konsonant/erwartet, niedrig/steigend→Spannung), Seed-stabil (SeededRNG).
Ersetzt/erweitert die progressionPhase-Journey opt-in (`input.suggestJourney`).
Tests: Ranking-Gesetze, Determinismus pro Seed, Kohärenz-Monotonie.

### H3 — HRV-Humanize (pure, S)
Timing/Velocity-Mikro-Offsets aus der ECHTEN RMSSD/IBI-Streuung des Takes
(BioSampleFrame-HRV → Jitter-Skala, ±(few ms/vel-%)), deterministisch pro Seed
+ HRV-Wert. Opt-in `input.humanize`. Tests: 0-HRV ⇒ 0 Jitter, Skalen-Grenzen,
Determinismus. KEIN Zufalls-Humanize.

## Gesetze
Neue Dateien in Sequencer/ (nicht DSP/ — Core/Sequencer-Typen erlaubt),
bit-identisch ohne Input-Schalter (Golden-Tests Pflicht), keine UI, keine neuen
Türen, Scaler-Begriffe nirgends in Copy. Nach H1–H3: BodyVibe-Pattern-Generatoren
(B2/Motions-Analog) verwenden dieselben Cores.
