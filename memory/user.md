# User Profile

## Identity
- **Name:** Echoel (Michael Terbuyken)
- **GitHub:** vibrationalforce
- **Location:** Studio Hamburg, Germany
- **App:** Echoelmusic (Apple ID: 6757957358, Bundle: com.echoelmusic.*)

## Project Vision
The multidimensional production instrument: ONE unified instrument (single EchoelStudioView — one button, then sliders) where the body plays sound, space (ADM-OSC), light (Art-Net/sACN) and vibration (sub-bass/haptics) in real time, over open standards. (The old "12 EchoelTools" is an internal taxonomy over real modules, not separate tools — see FEATURE_MATRIX.)

## Technical Background
- Swift/SwiftUI primary (85% of codebase)
- DSP expertise (DDSP, vDSP, spectral morphing)
- Audio engineering (AVFoundation, Accelerate, Metal)
- Cross-platform ambitions (iOS, Android, Desktop plugins)

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
- iOS 26 SDK deadline: April 28, 2026
- TestFlight build: 22572541274
- 1,560+ commits, 1,060+ test methods

---

## Current state (2026-06-02)
- **TestFlight build 1477 VALID** — app + EchoelmusicWidgets + AUv3 plugin + CX (bio→App Group glance) + Release auto-demo (lives without hardware) + brand-clean Info.plist.
- **Live bio sources:** HealthKit + Polar H10 + Demo (auto-starts in Release after 4 s grace). Camera rPPG exists but dormant (not bus-wired) — Planned.
- **3 Apple surfaces shipping.** Watch compile-verified but embed-blocked (needs local Xcode). macOS-Catalyst/visionOS/tvOS/Clip = roadmap.
- **Biggest open gap:** nothing is runtime-verified — needs build 1477 on a real iPhone (audio/launch/tabs + App Store screenshots).
- **"12 EchoelTools" reframed:** a taxonomy over real modules; 4 LIVE, 5 partial, 3 roadmap (see FEATURE_MATRIX). Not 12 separate Swift tools.

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
