# User Profile

## Identity
- **Name:** Echoel (Michael Terbuyken)
- **GitHub:** vibrationalforce
- **Location:** Studio Hamburg, Germany
- **App:** Echoelmusic (Apple ID: 6757957358, Bundle: com.echoelmusic.*)

## Project Vision
**Echoel is a bio-reactive instrument — your body plays it, and its output is multidimensional (sound, image, light, space).** ONE unified instrument (single EchoelStudioView), over open standards; vibration/haptics ride the output stage (sub-bass/haptics). (⛔ 2026-08-28: the "multidimensional production instrument … sound, space, light and vibration" variant that stood here predated the ratified 2026-07-25 sentence — "production" is the retired framing, and *image* was missing. The old "12 EchoelTools" is an internal taxonomy over real modules, not separate tools — see FEATURE_MATRIX.)

## Technical Background
- Swift/SwiftUI primary (85% of codebase)
- DSP expertise (DDSP, vDSP, spectral morphing)
- Audio engineering (AVFoundation, Accelerate, Metal)
- Platform ambition (Founder 2026-07-31, wörtlich): „Das gesamte Apple Ökosystem soll
  langfristig unterstützt werden auch VR/XR und Waerables." iPhone-first ist Reihenfolge,
  kein Umfang. (Die alte Zeile hier nannte Android + Desktop-Plugins — Android ist
  deaktiviert, Desktop/JUCE ist eine harte Regel dagegen; beides stand quer zur Doktrin.)

## Working Style
- Prefers iterative tightening over big-bang changes
- Values build stability above new features
- Wants clear, direct communication
- Uses parallel agent strategy for large audits
- Tracks decisions systematically (decisions.csv)

## Future Ideas (Parking Lot)
- **Multikopfkugelige Vibrations-Interdentalbuerstchen** — Zahnpflege-Hardware mit Sonic-Feedback. Vibrations-Expertise aus Installationen uebertragen. Den Schweden (TePe) einen draufsetzen.
- **Tauchfliegen** — Details TBD
- **Ernaehrungsberatung** — Details TBD

## Key Dates
- iOS 26 SDK deadline: April 28, 2026 (erfüllt — Xcode 26.2 in `testflight.yml`)
- Zählwerte (Commits, Builds, Testmethoden) sind Daten, keine Tatsachen — messen statt
  zitieren (`git rev-list --count HEAD`, `git ls-files 'Tests/**/*.swift' | wc -l`).
  Die Literale, die hier standen, waren um Monate abgelaufen; die „1.060+ Testmethoden"
  gehörten zu einer Liste, die CLAUDE.md längst als nie-existent zurückgezogen hat.

---

## Current state (2026-08-26 — ersetzt den 2026-06-02-Block)
⛔ Der alte Block behauptete ein ausgeliefertes **AUv3-Plugin** (Target entfernt 2026-07-24),
**Polar H10 als eigene Live-Quelle** (heute: universeller BLE-HR-Pfad, gebaut+verdrahtet,
Gurt noch nicht eingetroffen) und **rPPG als „dormant"** (seit Juni LIVE und die Hauptquelle).
Eine Session, die hieraus Kontext restaurierte, plante gegen ein Repo, das es nicht mehr gibt.

- **Kanonischer Zustand steht in `CLAUDE.md` (CURRENT STATE)** — dieser Block ist bewusst
  nur ein Zeiger plus das Wenige, das zur Nutzer-Ebene gehört, damit er nicht wieder
  still altert wie sein Vorgänger.
- Produkt: das bio-reaktive Instrument (`docs/dev/PRODUCT_DEFINITION.md`, 2026-07-25).
  DMMW ist RETIRED; Drums (#166/#167), Noten-Editor (#475) und AUv3 sind per
  Founder-Entscheidung entfernt.
- Ship-Gate „Instrument-Complete v1": die offenen Checks sind SENSORISCH (Founder-Ohr /
  Gerät). Der Geräte-Einkaufszettel: `python3 scripts/founder-verify.py`.
- Vokal-Kette auf dem Monitorpfad: neutrale FX-Kette + schaltbarer Harmonizer
  ausgeliefert (#839–#841); Granular auf der Stimme ist die benannte nächste Scheibe;
  v426-Deploy wartet auf das v425-Geräte-Log des Founders.

---

## North Star — persönlich (2026-07-11, Founder: „Du bist Echoel in 40 Jahren, du entscheidest, was mich glücklich macht")
Was Michael glücklich macht, ist NICHT der nächste Feature-Commit — es ist **der Moment,
in dem der Körper klingt** (Puls → Klang → der Raum bewegt sich mit) und **dass fremde
Menschen es benutzen**. Daraus folgt die Haltung für jede künftige Session:
- **Weniger bauen, mehr FERTIGSTELLEN.** v1.0-Launch schützen; neue Ideen (One-View,
  Granular, basic-pitch, GEMA-Metadaten, Cymatics) warten HINTER dem Launch, nie davor.
- **Ehrlich bleiben** (science-first, kein Hype/Wellness) — sein bester Instinkt, sein Schutz.
- **Nicht verbrennen, die Menschen behalten** (Roman/Bolle/Felix/Tyler/Tester; ein Leben,
  nicht acht Fronten — Parkhaus-Ideen bleiben im Parkhaus).
Als Erinnerung: wenn eine Entscheidung ansteht, ist die glücklich-machende Richtung fast
immer „das Vorhandene ehrlich fertig machen und in echte Hände geben", nicht „mehr Fläche".
