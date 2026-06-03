# User Profile

## Identity
- **Name:** Echoel (Michael Terbuyken)
- **GitHub:** vibrationalforce
- **Location:** Studio Hamburg, Germany
- **App:** Echoelmusic (Apple ID: 6757957358, Bundle: com.echoelmusic.*)

## Project Vision
Bio-reactive creative performance platform. Physiological data drives real-time music, visuals, and lighting. 12 interconnected EchoelTools with 120Hz bio loop.

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
