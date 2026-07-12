# Deep-Research-Report: VJ/Mapping/Realtime-Visual/Animation 2025/2026

(Deep-Research-Agent, 2026-07-12, Founder-Auftrag "Mapping, licht, Laser,
animation, Visual … abklappern aber gründlich". Search-Snippets, 403-Lücken
am Ende.)

## VJ- & Media-Server-Tools

- **Resolume Arena/Avenue 7.22–7.27 + Wire:** De-facto-Standard Clip-VJing;
  Wire = Node-Editor, Patches als FX/Quellen kompilierbar. Audio-FFT auf jeden
  Parameter; MIDI/OSC/DMX-Mapping; NDI + Syphon/Spout. 7.24: 10-bit Output +
  LUTs (Farbmanagement im VJ-Mainstream). Mapping: Corner-Pin, Bezier-Warp,
  Edge-Blend, LED/DMX. **ISF nativ seit 7.8.**
- **TouchDesigner 2025: POPs** — Millionen Punkte/Partikel GPU-resident ohne
  Shader-Code; DMX-POPs (Fixture→Art-Net/sACN direkt aus Geometrie).
  Reaktivitäts-Referenzklasse (Audio-CHOPs, alles-I/O). Profiling-Kultur.
- **MadMapper 6 + miniMAD:** Mapping-Goldstandard — Timelines statt Cues,
  Space Scanner (Structured Light), LED-Scanner, DMX-Fixture-Editor, 4096
  Universen, ILDA-Export. miniMAD-Modell: Editor exportiert, Billig-Hardware
  spielt ab. ISF nativ.
- **Notch 2026.1 ("Gold", ISE 2026):** NURA (4 Renderer Realtime→Photoreal),
  Notch for AE (Beta). Harte 16,6-ms-Budget-Denke + GPU-Profiler. Notch
  Blocks = DAS Realtime-Content-Format der Branche. Jetzt Subscription.
- **VDMX6:** kompletter Metal-Rewrite; ISF-Heimat (~200 ISFs mit);
  **ISF-Metal-Framework open source** (Lizenz prüfen!). ~$99.
- **Smode:** "Echtzeit-After-Effects" — Layer/Modifier/Masken statt Nodes;
  Unreal-/Notch-Wrapper, Genlock; Theater/Show-Segment.
- **HeavyM:** Einsteiger-Mapping, eingebaute Sound-Analyse (Bänder→Effekte),
  Edge-Blend — Mapping-Basics sind massentauglich verpackbar.
- **Magic Music Visuals:** günstiger Audio-Visualizer, mehrkanalige
  Audio/MIDI/OSC-Inputs (pro Instrument eigene Reaktion).

## Animations-Frontier (kurz)

- After Effects 2025: MFR ausgereift, GPU-Preview-Rewrite, Notch-Brücke.
- **Rive: State Machines + Data Binding 2025 — .riv = winziges interaktives
  Vektor-Runtime-Format MIT iOS-RUNTIME; Logik lebt in der Datei. Bestes
  konzeptionelles Vorbild für "Bio-Wert → Animations-State".**
- Cavalry 2.7: prozedurale 2D-Motion, CSV/API-datengetrieben.
- Blender Grease Pencil 3: Rewrite, Geometry-Nodes für Strokes (offline).

## Echoel-Visual/Mapping: Profi-Kriterien

**Was macht ein Visual "professionell" statt Demo (Feld-Konsens):**
1. **Kompositions-Ebenen:** Layer+Blend+Maske statt Ein-Shader-Vollbild →
   MetalBioView von "ein Canvas" zu 2–4 kompositierten Passes heben
   (Basis-Feld + Bio-Layer + Grade-Pass).
2. **Farb-Management:** definierter Farbraum (Display P3), LUT-/Tone-Mapping-
   Pass, kein Banding; vorhandene Hue/Sat-Palette ist der richtige Keim.
3. **Übergänge/Zustands-Logik:** nie hart schneiden — Bio-Zustandswechsel
   (Kohärenz-Tier) braucht getimte Crossfades/Morphs (Rive-State-Machine-
   Denke), kein Parameter-Springen.
4. **Parameter-Glättung + Budget-Disziplin:** 16,6-ms-Denke + Profiler —
   Echoels AdaptiveQuality IST diese Profi-Praxis; ausbauen.

**Mapping-Minimalfunktion iPhone→Beamer (2025er iOS-Mapping-Welle: ProMapper,
Lazy Lighting, SurfaBeam, ProjectX — Kategorie entsteht GERADE):** externes
UIScreen/Scene via HDMI/AirPlay + **4-Punkt-Corner-Pin pro Fläche (eine 3×3-
Homographie im bestehenden Metal-Pass, quasi gratis)** + einfache Maske +
Blackout. Edge-Blend/Mesh-Warp = v2. Das iPhone als "miniMAD mit Gehirn" ist
eine real entstehende Kategorie.

**ISF-Import = sinnvoller Zero-Deps-Weg:** ISF = JSON-Header + GLSL-Fragment,
offene Spec, von Resolume/VDMX/MadMapper getragen; Vidvox' Metal-ISF-Pipeline
open source. Haken: GLSL→MSL. Pragmatisch: Subset (Single-Pass-Generatoren)
selbst transpilieren ODER ISFs offline nach MSL konvertieren und als
"Echoel-Shader-Pack" shippen. Bio-Werte mappen 1:1 auf ISF-INPUTS.

**Bio-Reaktivität im Feld — Alleinstellungs-Check BESTÄTIGT:** Kein einziges
kommerzielles VJ-/Mapping-Tool hat eingebauten Bio-Input (alle brauchen
Custom-OSC-Brücken). Was existiert = Kunst-Unikate: Techno-empathy 2.0 (2025,
TD + Muse-EEG + HR), Lisa Park (Eunoia/NUE), Marco Donnarumma (Biophysical
Music), BioFlockVR (Forschung). **Ein Produkt, das rPPG/BLE-HR out-of-the-box
in Visuals + ADM-OSC + Art-Net routet, gibt es nicht.** Zusätzlich billigster
Weg in Profi-Rigs: Echoel als Sensor-Hub FÜR Resolume/TD (OSC-Out — existiert).

## Lücken

- Smode-/HeavyM-/Magic-Versionsstände unbestätigt; AE-2025-Liste teils
  SEO-Blogs; Notch-Preise unverifiziert; ISF-Metal-Lizenz exakt prüfen;
  App-Store-Longtail "HR→Visuals"-Startups nicht ausschließbar (Restrisiko
  klein).
