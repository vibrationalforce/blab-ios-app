# Open-Repo-Research 2026-07-10 — App-Store-sichere freie Bausteine (Founder-Auftrag)

Founder: „Research mit allen aktuellen Open Repos wo wir uns bedienen können ohne extra
draufzahlen zu müssen … EchoelAI und die anderen Tools noch ausbauen? … socialmedia
Management / contenterstellung und plattformübergreifendes posting?"

Harter Filter: Lizenz muss für eine CLOSED-SOURCE App-Store-App kostenlos sein
(MIT/BSD/Apache-2.0 ok; GPL/AGPL = verboten). **Adversarial verifiziert (3-Voter-Panel);
4 von 9 Feldern kamen durch, der Rest brach an Session-Limits ab — unten ehrlich markiert.**

## ADOPT-NOW-Tabelle (verifiziert, HIGH confidence — Founder-Ok vor JEDER Dep nötig)

| Lib | Lizenz | Schließt | Kosten | Beleg |
|---|---|---|---|---|
| **Signalsmith Stretch** | MIT (+ MIT-FFT-Dep „Linear", `SIGNALSMITH_USE_ACCELERATE`) | Stage-P Audio-Stretch/Pitch (polyphon, 0.75–1.5× am besten) | S/M — header-only C++11 hinter ObjC++/Swift-Shim; fällt exakt unter die „freie, gut gekapselte C++"-Ausnahme | github.com/Signalsmith-Audio/signalsmith-stretch; Qt shipped es unter MIT-Attribution |
| **HaishinKit** | BSD-3 (Voter bestätigt, formales License-Vote-Ticket brach ab — vor Add nochmal LICENSE lesen) | P4 Broadcast: RTMP + SRT (WHEP/WHIP alpha) | M — SPM, v2.x modular (`RTMPHaishinKit`); Release 2.2.5 (2026-03-28), 10 Jahre aktiv | github.com/HaishinKit/HaishinKit.swift — bestätigt den bestehenden Plan |
| **LinkKit (offizielle Binaries)** | „Ableton Link SDK License v2.0" — kostenlos + royalty-frei für kommerzielle App-Store-Apps; KEIN OSS | Tempo-Sync mit Ableton/allen Link-Apps | M — C++-SDK hinter Wrapper + Ableton-UI-Guidelines einhalten | github.com/Ableton/LinkKit. **NIE aus dem Link-Quell-Repo bauen (GPLv2 = App-Store-inkompatibel; README: „iOS developers should not use this repo")** |
| **ni-midi2** (nur falls UMP/MIDI-CI-Parsing über CoreMIDI hinaus nötig) | MIT | MIDI 2.0 UMP 1.1 + MIDI-CI 1.2 Message-Level | M — C++17 hinter Swift-Wrapper; v1.11.0 (2026-01-31) | midi2.dev / github.com/midi2-dev/ni-midi2. Empfehlung bleibt: CoreMIDI first-party zuerst |

## DO-NOT-USE (verifiziert)

- **Rubber Band** — GPL + kommerzielle Dual-Lizenz; Vendor wörtlich: App-Store-Vertrieb ohne
  bezahlte Lizenz ILLEGAL. Aktiv gepflegt — reiner Lizenz-Block, kein Qualitätsproblem.
- **Ableton Link Quell-Repo** (github.com/Ableton/link) — GPLv2+; nur offizielle
  LinkKit-Binaries verwenden.
- **AM_MIDI2.0Lib** — MIT, aber selbsterklärter Prototyp („CURRENTLY UNDER DEVELOPMENT");
  „voller MIDI-2.0-Stack"-Claim wurde 0-3 REFUTED (nur Bytestream↔UMP/CI-Konverter).
- **MIDI2Kit** — MIT, aber 0 Stars, pseudonym, shipped Binaries → Qualitätsrisiko.

## OFFEN — Verifikation abgebrochen (Session-Limit), Folge-Pass nötig vor Verdikt

- **WORLD-Vocoder** (plausibel modified-BSD, patentfrei, Release Feb 2026) — UNVERIFIZIERT.
- **aubio** (plausibel GPL-3 = Falle; BSD/MIT-Alternativen + Apple SoundAnalysis prüfen) — UNVERIFIZIERT.
- **Spatial** (libspatialaudio-Lizenz, PHASE-Patterns), **Video/Metal-Shader-Sammlungen,
  MV-HEVC-Beispiele, LUTs**, **On-Device-AI** (MLX, whisper.cpp, Musik-Gen-Modelle mit
  Non-Commercial-Fallen), **Social-Posting** (YouTube Data / Meta Graph / TikTok Content
  Posting API; Postiz/Mixpost self-host) — KEINE überlebenden Claims in diesem Lauf.
  → Für Social gilt bis dahin der ehrliche Ist-Stand: iOS-Share-Sheet ist der einzige
  server-lose, kostenlose, richtlinien-sichere Weg; alles Direkte braucht App-Review je
  Plattform und meist Server. Kein Verdikt als Fakt verkaufen, bevor der Folge-Pass lief.

## Vision-Gate-Einordnung

- Signalsmith → **ADOPT→PRODUCT (pending Founder-Ok, Stage P)** — Sound-Dimension, iOS-nativ machbar, realtime-sicher (Offline/Control-Plane-Stretch zuerst).
- HaishinKit → bestätigt **ROADMAP P4** (war schon geplant; Research bestätigt Lizenz/Pflege).
- LinkKit → **ROADMAP** (Sync-Dimension; nach Timeline-Kern).
- ni-midi2 → **WATCH** (CoreMIDI reicht heute).
- RubberBand/Link-Source → **REJECT** (Lizenz).
- Rest → **WATCH bis Folge-Pass.**
