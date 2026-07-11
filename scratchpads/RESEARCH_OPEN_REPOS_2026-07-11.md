# Open-Repo-Research 2026-07-11 — Vollständiger Folge-Pass (4 verifizierte Panels)

**Founder-Auftrag:** „Such nach allen open repos, die uns jetzt weiterhelfen, nachdem
du die gesamte Geschichte + Vision von Echoel fürs Apple-Ökosystem durchdrungen hast."

**Methode:** 4 parallele Research-Agenten (DSP/Synthese · Apple-App-Layer · Visual/Video/
Licht · Bio/AI), jede Lizenz aus der ECHTEN LICENSE-Datei verifiziert (nicht Hörensagen),
Weights getrennt von Code geprüft (die klassische Falle). Ergänzt/schließt den
07-10-Pass (dort blieben WORLD/aubio/Spatial/On-Device-AI/Social offen — jetzt geklärt).

**Lizenz-Gesetz:** Closed-Source-App-Store-App = frei nutzbar heißt MIT/BSD/Apache-2.0.
GPL/AGPL/CC-BY-NC = VERBOTEN (Code UND Weights). Swift-first, Zero-Deps bleibt Default;
jede Dependency braucht Founder-OK. „REFERENCE-ONLY" = Algorithmus lesen, in Swift
NEU schreiben — kein Code-Copy.

## Die EINE große Erkenntnis

**Kein einziger neuer In-App-Dependency ist für die gesamte U1→K3-Bau-Reihenfolge nötig.**
Jeder Produkt-tier-Fund ist entweder first-party (CoreImage/AVFoundation/GroupActivities/
CoreMIDI/CoreML) ODER eine Reimplement-aus-Referenz. Alle echten ADOPTs sind PIPELINE
(CI/Content/Tooling — fassen `Sources/` nie an). **Und:** es gibt KEINE offene
Adaptive-Music-Engine und KEINE offene SwiftUI-DAW-Timeline zum Abkupfern — BioComposer
+ ArrangeTimelineView sind bestätigtes Neuland (Moat).

## ADOPT-PIPELINE (kein In-App-Code — CI / Content / Test-Oracle; Founder-OK je Nutzung)

| Repo | Lizenz | Wofür (Echoel-Nutzen) |
|---|---|---|
| **NeuroKit2** | MIT ✅ | CI-Beweis-Oracle für unsere HRV/Kohärenz-Mathematik: RMSSD/SDNN/pNN50 + welch/lomb-PSD + gebündelte Datensätze = Golden Test Vectors. Untermauert „science-first". |
| **PhysioNet-Datensätze** | CC0/PDDL/CC-BY ✅ (NUR diese — CC-BY-SA/ODbL MEIDEN) | Referenz-RR/PPG mit Ground Truth → unsere Coherence/RMSSD in CI gegen bekannte Wahrheit prüfen. |
| **colour-science/colour** | BSD-3 ✅ | Offline: Bio-Grade-LUTs erzeugen/validieren + SpectralColor-Tabellen + CIE-Daten gegenprüfen. |
| **ADM-OSC (`adm_osc`)** | MIT ✅ | Fertiger Konformitäts-Tester für unseren ADMOSCSender (`/adm/obj/n/*`). |
| **sACNKit (dsmurfin)** | MIT ✅ (2026-aktiv, voll E1.31-2018) | Konformitäts-Oracle für EchoelLux-sACN (heute unicast; deckt multicast/sync/priority ab). |
| **Pangolin BEYOND `/beyond/*` OSC** | offene Doku | Ziel-Namespace für den Laser-OSC-Relay (PLAN_PRO_LEVEL §4). |
| **librosa** | ISC ✅ | Python-Validierung unserer Swift-DSP (nur Pipeline). |
| Apple DrawTogether/GroupSessionMessenger | Apple sample ✅ | Muster (nicht Lib) für v1.1 Echoel-Live Puls+Partitur-Sync (Codable-Messages, first-party). |
| LUT-Konverter (muukii/ColorCube, YuAo) | MIT ✅ | Pipeline: LUT-Bild ↔ .cube. |

## ADOPT-PRODUCT-CANDIDATE (selten — Founder + Council-Gate; frühestens nach A1/A2)

| Repo | Lizenz | Wofür | Slot |
|---|---|---|---|
| **Spotify basic-pitch** | Apache-2.0 ✅ (CoreML-Modell IM Repo → Weights gedeckt) | Audio→MIDI: „summen/singen → MIDI-Clip auf einer Spur" — reine Instrument-DNA. Runtime = first-party CoreML (0 externe Deps); Kosten = ein Zyklus Swift-Vor/Nachverarbeitung (CQT-Stacking + Note-Decoding). | nach A1/A2 (braucht Multi-Roll + Record-Arm) |
| **CoreImage CIColorCube(WithColorSpace)** | first-party ✅ | Default-Engine der Bio-Grade-Farbpipeline (Video-Block C) + in-house ~100-Zeilen-.cube-Parser (Muster: SwiftCube MIT). | Video-Block C |
| **Apple AVCam + MV-HEVC-Samples** | Apple sample ✅ | Referenz-Skelett für Video-Block C (Capture/Trim/Export); Spatial-Video-Capture bestätigt machbar (dual-wide + cinematic stabilization, WWDC24 10166). | Video-Block C |

## REFERENCE-ONLY (Algorithmus lesen → Swift neu; KEIN Dependency)

- **Granular:** Mutable Instruments **Clouds** (STM32F-Code = MIT ✅) — kanonische Granular-
  Referenz. (Der Swift-Shortcut **GrainSwift ist GPL-3 → REJECT**, nicht mal pattern-copy.)
  Slot: neue NoteVoice hinter dem bestehenden Router, NACH A1.
- **Physical Modeling:** **STK** (MIT-permissiv ✅) — bowed/blown/reed als Bio-Exciter-Mappings.
- **Chladni/Cymatics:** **addiebarron/chladni** (MIT ✅, Particle-Settle) + **kai5z FEM**
  (physikalisch ehrlich, read-only) für den „Resonance"-Modus. Public-Domain-Mathematik.
- **Metal-Shader:** **twostraws/Inferno** (MIT ✅), **MetalPetal** (MIT, dormant) —
  `.colorEffect`/`.layerEffect`- + LUT-Filter-Muster für MetalBioView.
- **AWB („intelligenter Weißabgleich"):** in-house Gray-World (wenige vDSP-Zeilen) +
  first-party `AVCaptureDevice.temperatureAndTintValues`/locked WB — heute on-device;
  OpenCV xphoto (Apache-2.0) als Algo-Referenz.
- **Waveform/Timeline:** DSWaveformImage (MIT), **AudioKit/Waveform** (MIT, Metal — bester
  K3-Read), NextLevel (MIT) für Segment/Trim.
- **MIDI/OSC:** MIDIKit (MIT; hat WENIGER MPE als unser CoreMIDI — nur MIDI-File/UMP-Read),
  OSCKit/F53OSC (MIT; OSCKit v3 zieht SwiftNIO = Dep-Verstoß → nur lesen).
- **WORLD-Vocoder** (modified-BSD ✅, v1.0.1 Feb 2026): Harvest-F0 + CheapTrick als Referenz,
  VocoderCore existiert in-house. **DDSP** (Apache-2.0) = Design-Ahne von EchoelDDSP.
- **AUv3:** Apple AUv3Filter/Instrument-Samples + AudioKit Cookbook (MIT). Kein offenes
  App-Group-Bio→Extension-Template existiert — DAS pionieren wir selbst.

## REJECT (Lizenz oder Qualität — verifiziert)

- **Code non-commercial/copyleft:** aubio (GPL-3), Essentia (AGPL), **RAVE** (CC-BY-NC —
  Code selbst!), Splash (GPLv3), omnidome (AGPL-3), NINJAM/JamTaba (GPL — nur Prinzip zitieren),
  hrv-analysis/Aura (GPL-3), pyVHR (GPL-3).
- **Weights non-commercial (Code-vs-Weights-Falle):** **MusicGen/AudioCraft** (Weights CC-BY-NC
  → Output nicht monetarisierbar), **open-unmix** umxl (CC-BY-NC-SA), **madmom** Modelle
  (CC-BY-NC-SA trotz BSD-Code), **Afifi**-AWB-Repos (research-only/NC).
- **Lizenz-Fallen trotz MIT-Label:** **SoundpipeAudioKit** (dokumentierter LGPL-Streit,
  Csound-portierte Module) → nie Code-Port; **Shadertoy**-Shader (Default CC-BY-NC-SA).
- **Stem-Separation:** demucs Code MIT, aber **Weights NIE separat lizenziert** (auf 800
  internen Songs trainiert) → für Produkt flaggen. On-Device via CoreML/MLX-Ports MACHBAR
  (alle MIT), bleibt aber WATCH(Produkt)/PIPELINE(Content) — nicht im Charter (wir
  EXPORTIEREN Stems, separieren nicht). Spleeter/RubberBand → REJECT.

## WATCH (später neu bewerten)

- **mlx-swift** (MIT, iOS-nativ) = glaubwürdigstes On-Device-Inferenz-Substrat, falls je ein
  kleines Modell eingebettet wird — heute kein Modell dafür.
- **YuE** (Apache-2.0 inkl. Weights — Lizenz SAUBER, korrigiert alte NC-Annahme) + **Stable
  Audio Open** (bedingt kommerziell, frei <1 Mio $ Org-Umsatz) = Offline-Content-Pipeline,
  nicht iPhone-on-device (7B).
- **MNE-LSL** (BSD, 2026-aktiv) = sauberere EEG-Realtime-Referenz als muse-lsl, falls EEG
  je hochgestuft wird. BrainFlow bleibt WATCH (C++, EEG=Roadmap — kein Re-Tiering).
- **CREPE** (MIT inkl. Weights) = neuronaler Mono-Pitch, nur falls in-house-YIN nicht reicht.

## Empfohlener nächster Schritt (Founder-Entscheid)

Nichts hiervon verzögert v1.0. Die zwei mit dem höchsten Hebel + null Risiko:
1. **NeuroKit2 + PhysioNet als CI-Oracle** (PIPELINE) — macht unsere Bio-Claims beweisbar.
2. **basic-pitch als Produkt-Kandidat vormerken** (Founder+Council) für nach A1/A2 —
   „summen → MIDI" ist reine Echoel-DNA.
Beide brauchen ein explizites Founder-Go, bevor irgendetwas gezogen wird.
