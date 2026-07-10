# PLAN — Cymatics-Visual („Wasserklangbilder") für die immersive Visual-Dimension

**Founder-Ask (2026-07-10):** „Sowas mit Wasserklangbildern in Kombination mit dem
Visualisierungskonzept über Biofeedback." (Kontext: Martin Schönes Brain-Avatar —
Biosignal als kontinuierlicher Modulator einer Klang+Bild-Matrix; Günther Haffelders
messtechnisch validierte, anti-esoterische Linie.)

**Vision-Fit:** ADOPT-PRODUCT. Physikalisch ehrlich (Chladni-/Wasserklang-Muster sind
stehende Wellen — Physik, keine Esoterik), kontemplativ („wow"), science-first: die
Muster entstehen aus den REALEN Frequenzen der gerade klingenden Noten, nicht aus
Deko-Zufall. Genau das Produkt-Bar-Ziel: „das VISUAL muss Teil des Erlebnisses sein."

## Warum Echoel dafür schon fast alles hat

- `PianoRollModel` publiziert pro Tick eine **`MusicalFrame`** auf dem Bus:
  `notes: [MusicalNote(frequencyHz, amplitude)]` + rootPitchClass + beatPhase +
  masterLevel. → Die exakten Hz der klingenden Töne liegen bereits als Datenstrom vor.
- Bio-Snapshot (`usableBio()`): coherence / hrvNormalized / breathPhase → die
  „Wasser-Ruhe" (Dämpfung) und Feinbewegung.
- `MetalBioView` kompiliert seinen Shader zur Laufzeit → neuer Modus = Shader-Zweig
  + kleiner Uniform-Struct, kein neues Metal-File nötig. VJ-Overlay (Palette/Hue)
  existiert; ein „Cymatics"-Preset fügt sich dort ein.
- Flash-Safety-Gesetz (≤3 Hz) bleibt eingehalten: stehende Wellen ändern sich
  kontinuierlich, keine Blitze; BioVisualParams-Klammer wiederverwenden.

## Die Mathematik (physikalisch ehrlich, shader-billig)

Chladni-Platte (quadratisch, gelenkig gelagert), Modenform:
```
C(x, y, n, m) = cos(nπx)·cos(mπy) − cos(mπx)·cos(nπy)      x,y ∈ [−1, 1]
```
Muster = Nulllinien |Σ| ≈ 0. Pro klingender Note i:
- Hz → Modenpaar: `k = log2(f_i / f_root)` (Oktavlage), `n_i = 1 + round(3·frac(k·φ))`,
  `m_i = 1 + round(3·frac(k·φ²))` — deterministisch, gleiche Note ⇒ gleiches Muster
  (Wiedererkennbarkeit = Instrument-Gefühl), benachbarte Noten ⇒ benachbarte Moden.
- Amplitude a_i gewichtet den Summanden: `S(x,y) = Σ a_i · C(x,y,n_i,m_i)`.
- Render: `intensity = smoothstep(ε, 0, |S|)` → helle „Sand-Linien" auf dunklem
  Grund (Uncodixfy: keine Neon-Glows; Palette aus dem bestehenden VJ-Hue).

Bio-Mapping (kontinuierlich, kein Trigger-Gestückel — Schöne-Prinzip):
- **Kohärenz → ε (Linienschärfe):** hohe Kohärenz = gestochene, ruhige Muster;
  niedrige = weiche, „unruhiges Wasser"-Kanten.
- **Atemphase → sanfte Radial-Modulation** von x,y (das „Wasser atmet", ≤0.2 Hz).
- **HRV → Mikro-Drift** der Modenphase (lebendig, nie blitzend).
- **beatPhase → Dämpfungs-Puls ≤ masterLevel** (im Takt „angeregt", physikalisch
  wie ein Anschlag auf die Platte) — Rate = Musiktempo, aber Amplituden-, nie
  Luminanz-Sprung >3 Hz-Regel-relevant.

Max ~6 Noten × 2 cos-Paare = trivial für jede iPhone-GPU bei 120 fps.

## Umsetzung (1 Zyklus, ≤3 Dateien)

1. `Views/MetalBioView.swift`: Uniforms um `noteFreqs[8] / noteAmps[8] / rootHz /
   mode` erweitern; Shader-Zweig `cymatics` (obige Formel); Modus in die bestehende
   VJ-Preset-Auswahl („Cymatics") einhängen.
2. Feed: bestehende `MusicalFrame`-Subscription der Visual-Schicht (liegt am Bus an)
   → Uniform-Update im vorhandenen Frame-Tick (KEIN neuer 10-Hz-Observer in einem
   Ancestor-Body — render-safety-Regel; MetalBioView ist bereits ein Leaf).
3. Kein neues File, keine neue Dependency, AUv3 unberührt.

**Gate:** Founder-Ohr/-Auge — Ästhetik ist das Produkt. Deshalb NICHT blind in der
Nacht geshippt: der erste Wurf muss auf dem Gerät beurteilt werden (Screenshot-Loop).
Implementierung startet auf Founder-Go als nächster Visual-Zyklus.

## Abgrenzung (Anti-Esoterik-Wache)

Copy nennt es „standing-wave patterns of the notes you play" / „Wasserklangbild
deiner Musik" — Physik. KEINE Heil-/Frequenz-Wirkversprechen, kein 432-Hz-Mystik-
Framing (Kammerton bleibt frei wählbar, neutral). Haffelder-Nugget übernehmen wir
als ANSPRUCH (nur messbare Aussagen), nicht als Marketing-Vokabular.
