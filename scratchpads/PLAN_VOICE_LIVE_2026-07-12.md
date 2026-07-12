# PLAN — Voice Live (Harmonizer · Autotune · Stimme→Synthese) — das Syng-Erbe

**Founder (2026-07-12, mit Syng-Pitch-PDF):** "Harmonizer und Autotune mit Voice
und Instrumente Synthese für Live Audio Input (ehem Syng Konzept)"

**Syng-Kern (aus dem Pitch):** Stimme → Farben (Oktavanalogie C=grün…),
Klangwolken, Biofeedback übers Smartphone, 3D-Sound+Visuals, gemeinsames
Musizieren. → Echoel IST die Realisierung (SpectralColor = Oktavanalogie,
rPPG = Kamera-Biofeedback, Spatial-Expansion = 3D, Echoel Live v1.1 = das
gemeinsame Musizieren). Fehlendes Stück: **die Stimme als Live-Instrument.**
(Brand-Wache: Syng-Pitch-Vokabular wie "Bioresonanz/Organresonanztherapie"
bleibt DRAUSSEN — unsere Sprache ist die Physik der Oktavanalogie, wie im
VocoderCore-Header schon kodifiziert.)

## Was SCHON existiert (Audit 2026-07-12)

| Baustein | Ort | Status |
|---|---|---|
| EchoelHarmonizer (2-stimmig, Delay-Line-Shifter, audio-thread-safe) | DSP/ | LIVE im FX-Chain (Synth-Pfad), feste Halbton-Intervalle |
| PitchTracker (YIN, cents-genau, pure, getestet) | DSP/ | LIVE für TuningDetector |
| VocoderCore (VoiceFrame→Klang+Bild+Licht-Mapping, FlashGuard-safe) | Studio/ | PURE, getestet, UNVERDRAHTET — "founder's flagship vision" |
| VoiceAnalyzer | Studio/ | vorhanden (Analyse-Seite) |
| MicrophoneManager + FeedbackGuard (Live-Monitoring-Schutz) | Audio/ | WIRED |
| Musiktheorie in-house (Tonart/Skala BEKANNT — keine Detection nötig) | Core/ | LIVE |
| TuningReference/Kammerton (432/440 als Korrektur-RASTER) | DSP/ | LIVE |
| SpectralColor (Ton→Farbe, CIE, CENTS-genau, kammerton-reaktiv) | Studio/ | LIVE |

**Der Echoel-Vorteil ggü. jedem Autotune am Markt:** wir müssen die Tonart
nicht raten — der Composer ERZEUGT sie. Korrektur + Harmonien sind
skalen-ehrlich und KAMMERTON-korrekt (ein 432-Hz-Autotune hat niemand).

## Stufen (je ≥1 Zyklus, Risiko aufsteigend)

- [ ] **VL1 — AutotuneCore (pure, autonom, TDD):** `Core/` oder `DSP/`
      VoicePitchCorrector: (detectedHz, Tonart, Skala, Kammerton,
      retuneSpeed 0…1, Stärke 0…1) → targetHz + ratio, mit One-Pole-Glide
      (retune "hart" = Cher-Effekt, "weich" = natürlich). Skalen-Snapping
      über die bestehende Theorie; NaN/unvoiced-Guards. Tests: Snapping in
      C-Dur/c-Moll, 432 vs 440-Raster, Glide-Konvergenz, Edge-Hz.
- [ ] **VL2 — Skalen-Harmonizer (pure, autonom, TDD):** EchoelHarmonizer
      erweitern ODER Mapping-Layer davor: diatonische Intervalle statt
      fixer Halbtöne (Terz/Quinte IN der Skala relativ zur erkannten Note;
      Voice-Leading-Optionen). Kernmethode pure/testbar; der bestehende
      Shifter bleibt unangetastet (nur interval1/2 werden pro Fenster
      skalen-korrekt gesetzt — control-plane, kein Audio-Thread-Umbau).
- [ ] **VL3 — Live-Mic-Pfad (DEVICE-GATED, audio-thread-review PFLICHT):**
      Mic-Tap → PitchTracker-Fenster (existiert für Tuning) → VL1-Ratio →
      Harmonizer-Instanz im MIC-Pfad (heute sitzt er im Synth-FX-Chain) +
      FeedbackGuard-Monitoring. Latenz-Budget beachten (<10ms Ziel;
      Delay-Line-Shifter ~50ms Fenster = hörbare Verzögerung → ehrlich als
      "Ensemble-Charakter" kommunizieren, Dattorro-Methode).
- [ ] **VL4 — Stimme→Instrument-Synthese (das Syng-Herz, DEVICE-GATED):**
      VoiceAnalyzer produziert VoiceFrames (pitch/energy/brightness) →
      treibt EchoelDDSP/PolySynth (Stimme SPIELT das Instrument) UND
      VocoderCore-Mapping → Bild (SpectralColor-Ton-Farbe!) + Licht
      (EchoelLux, FlashGuard). Damit ist die Syng-Vision geschlossen:
      eine Äußerung wird gehört, gesehen, gefühlt.
- [ ] **VL5 — AUv3-Fassung:** der Live-Voice-Prozessor als Teil von
      EchoelBioSynth (E4) oder eigenes Effekt-AUv3 — NACH E4-Grundlage.

## Interlocks

- VL1+VL2 sind pure Kerne → sofort autonom baubar, Release-neutral.
- VL3/VL4 brauchen Gerät (Ohr!) — NEEDS-FOUNDER-VERIFY, kein Blind-Claim.
- Kein neues Modal für die UI (bestehende Panels/Dropdowns nutzen).
- Spatial S3/S4 laufen parallel weiter (pure Kerne, kein Konflikt);
  langfristig ist die Stimme ein SpatialObject (ownerPeer = Performer).
- Markt-Referenzen aus der Deep-Research: VirSyn Harmony Eight (8 Stimmen
  räumlich platzierbar), MusiKraken Mic-Pitch→MIDI (nur Plumbing) — unsere
  Differenzierung: skalen-ehrlich + kammerton-korrekt + Bild/Licht-Kopplung.
