# Deep-Research-Report: Licht/Laser + iOS-Musik-Ökosystem (Juli 2026)

(Deep-Research-Agent, 2026-07-12, Founder-Auftrag "licht, Laser … alles iOS
Apps aus unseren Bereichen … abklappern aber gründlich". Search-Snippets,
403-Lücken am Ende.)

## FELD 1 — LICHT + LASER

- **grandMA3 v2.4 (Mai 2026):** Phaser-Recipes (generative Show-Elemente),
  universelle Presets, Cue-Preview, onPC gratis. **Phaser-Modell = mehrstufige
  Attribut-Modulation (Steps × Phase × Speed) pro Fixture. Konsequenz: nicht
  MA3 nachbauen — aber Herzphase/Atemphase als Phaser-Phase-Input ist
  EchoelLux' natives Alleinstellungsmerkmal (Bio-Phaser statt Step-Chases).**
- **ChamSys MagicQ (1.9.7.x):** stark verbesserter GDTF- + MVR-Import;
  60.000+ Personalities. **GDTF ist 2025/26 endgültig der offene Fixture-
  Standard (XML in ZIP) → GDTF-Subset-Parser = Zero-Deps-Weg zur Fixture-
  Library für EchoelLux.**
- **Lightkey 5.7 (Mac):** 7.000+ Profile, 70+ Effekt-Templates, Sync via MIDI
  Clock + **Ableton Link** — UX-Referenz "Lichtpult ohne Pult-Denke";
  Link als Licht-Sync ist etabliert (LinkKit frei, Council-fähig).
- **ENTTEC:** ODE Mk3, S-Play, Pixelator, ELM — EchoelLux' Art-Net/sACN-Out
  trifft die Hardware direkt. Fehlend für Pixel: Multi-Universe + 2D-Mapping
  (**HilbertSensorMapper ist dafür schon im Haus**).
- **iOS-DMX-Apps:** Photon 2 (Art-Net/sACN, Fixture-Creator, BeatTracker +
  Link; one-time 128 ch, Abo 512), Luminair 4 (1–4 Universen, sACN-Priority,
  KiNET, RDM). **iOS-Lichtpulte sind reif — Echoel gewinnt über die
  Bio-Quelle, nicht Konsolen-Parität.**
- **LASER:** Pangolin BEYOND/QS 5.5, FB4 "Turbo Mode"; MoboLaser (iOS) = NUR
  Companion-Remote — **Slot "standalone iOS→Netzwerk-DAC" unbesetzt.**
  IDN (ILDA Digital Network) = offener UDP-Stream-Standard (~12 Mbit/s pro
  Projektor @100 kHz); Helios-DAC open source. Zero-Deps-technisch analog zu
  ADMOSCSender machbar; Punkt-Optimierung (Blanking, Dwell, Scanner-Limits)
  = eigenes Handwerk. **Safety hart: IEC 60825-1, MPE-Grenzen, Audience-
  Scanning nur mit Zonen/E-Stop/Operator; DE: OStrV/TROS + Laserschutz-
  beauftragter (Vorwissen, unverifiziert). Echoel übernimmt NIE Exposure-
  Verantwortung — wenn, dann Content-Quelle an DACs mit eigener Safety-Kette,
  Operator-Arm-Gate, permanenter Blackout, kein Autostart. → WATCH/Phase 2.**

### EchoelLux → "kleines Lichtpult": Prioritätenliste

1. Grand Master / Master-Dimmer + Blackout (jede Referenz-App; Safety).
2. Gruppen (Fixtures → benannte Modulationsziele).
3. **Bio-Phaser statt Chases** (Phase-Offset pro Fixture über die Gruppe;
   Herz/Atem als Phase) + 2–3 klassische Chase-Presets.
4. Fixture-Library via GDTF-Subset-Import.
5. sACN-Multicast + Priority, >1 Universum (Photon/Luminair-Parität).
6. Später: Pixel-Mapping (Hilbert!), Art-Net-Discovery, RDM.

## FELD 2 — iOS-MUSIK-ÖKOSYSTEM

- **AUM 1.4.8:** nur inkrementell; bleibt Standard-Host → andocken
  (MIDI/AUv3-Out), nicht konkurrieren.
- **Drambo 2.48/2.49:** Code-Modul (User bauen Module). Modular-Tiefe ist
  Drambos Land; Echoels Tiefe = Bio-DSP.
- **Loopy Pro 2.0:** MIDI-Clips, polyphones Clip-Playback, Bus-zu-Bus.
  **Pricing-Vorbild: Free + 7-Tage-Trial + $30 one-time (MASTERPLAN §2).**
- **Koala:** AUv3-Instrumente/FX als Quelle — jede App wird Mini-Host;
  "billig + tief" funktioniert.
- **Cubasis 3.8:** Audio-I/O-Auswahl, Portrait + ext. Display — klassisches
  Feature-Rennen, nicht unseres.
- **Logic Pro iPad 3/12.3:** Flashback Capture, Chord ID, AI Session Players,
  "Music Understanding". **Apple besetzt "AI versteht deine Musik" — Echoel
  kontert mit "Körper als Musiker" (physiologisch, nicht statistisch).**
- **GarageBand:** TrueDepth-Face-Control existiert als Gimmick — validiert
  die Idee "Körper steuert Sound", niemand macht es ernsthaft (HRV/Kohärenz,
  wissenschaftsbasiert). Genau Echoels Claim.
- **Endlesss: TOT** (Server 05/2024 abgeschaltet) — server-abhängige
  Kollab-Modelle sterben mit der Firma; Echoels lokale, standard-offene
  Architektur (OSC/ADM-OSC/MIDI, SharePlay-Puls-Modell) ist die robuste Wette.
- **Fugue Machine/Aphelian/Riffler/Piano Motifs:** generative Nische lebt,
  aber regel-/zufallsbasiert. **Kein Player koppelt Generativität an
  Physiologie → unbesetzte Position bestätigt.**

**Plattform-Realität:** iOS-Audio-Render bleibt faktisch EIN Realtime-Thread;
Multicore hilft begrenzt. Echoels Budget (<10 ms, CPU <30 %) richtig gesetzt —
Single-Core-Disziplin im DSP bleibt Gesetz.

**Gewinnende Muster 2025/26:** Free+Trial+One-time (Loopy 2) · günstige Basis
+ IAPs (Koala/Drambo) · AUv3-Interop Pflicht · Ableton Link überall (auch
Licht!) · anpassbare Performance-Canvases statt DAW-Layouts.

## Lücken

Daslight/Sunlite-Changelogs; QuickQ-Details; Lightkey-5.7-Notes einzeln;
Riffler/Piano-Motifs-Stände; A18/A19-Audio-Benchmarks; IEC-60825-Neuausgabe +
deutsche Laser-Pflichten juristisch prüfen; Nischen-iOS-IDN-Apps nicht
ausschließbar; alles Snippet-basiert (403).
