# ADR-004 — Cross-Platform-Strategie (Spatial Expansion v2, documentation-only)

- **Status:** Accepted (documentation-only für v1 — es wird KEIN nicht-Apple-Binary gebaut)
- **Datum:** 2026-07-12
- **Kontext:** Founder-Prompt SPATIAL EXPANSION v2.0, §CROSS-PLATFORM ROADMAP.
  Gilt zusammen mit `docs/SPATIAL_EXPANSION_AUDIT.md` §6 und CLAUDE.md
  (überstimmt bei Konflikt). JUCE bleibt rejected. Zero-Dependency-Politik gilt.

## Entscheidung

**v1 shippt ausschließlich Apple.** Portabilität wird JETZT nur über zwei
billige, nicht-bindende Mechanismen geschützt:

1. **P3 — Protokoll zuerst.** Alles, was ein Gerät können muss, ist in
   dokumentierten Wire-Protokollen ausdrückbar: OSC-Dialekte (IEM-Konvention +
   ADM-OSC als Industrie-Lingua-franca — bei uns bereits live über
   `ADMOSCSender`) für Echtzeit-Spatial-Daten, plus ein versioniertes
   JSON-Schema für Szene/Layout/Session (`docs/ECHOEL_SESSION_PROTOCOL.md`,
   entsteht im selben Zyklus wie das Szenen-Modell S1). Ein fremder Client
   braucht unseren Swift-Code nie.
2. **P4 — Portabler Kern.** Nicht-UI-Logik (Szene, OSC-Codecs, VBAP/FDN-Mathe,
   MotionEngine, Sync-Modell) bleibt Foundation-only; Apple-Frameworks
   (AVFoundation, CoreMotion, NearbyInteraction, MultipeerConnectivity) nur
   hinter injizierbaren Protokoll-Adaptern. Durchsetzung Stufe 1: CI-Grep-Job
   (Import-Bann `UIKit|AppKit|SwiftUI` in Kern-Pfaden; heutiger einziger
   Verstoß im Kandidatenkreis: `MultipeerSession` → wird bei Layer-5-Arbeit
   hinter ein Transport-Protokoll gezogen). Stufe 2 (echter SwiftPM-Paket-
   Split) = ADR-005, eigener Council-gegateter Zyklus.

## Bewertete Pfade für später

| Pfad | Bewertung |
|---|---|
| **(b) Protokoll-Clients** (Web/Android/Windows implementieren ECHOEL_SESSION_PROTOCOL + ADM-OSC) | **EMPFOHLEN als erster nicht-Apple-Schritt.** Kosten ~0 auf unserer Seite (Spec existiert dann schon), null Rewrite, sofort rig-relevant (FletcherMachine/L-ISA/d&b konsumieren ADM-OSC heute). |
| **(a) Swift-on-Linux/Windows** der Kern-Pakete + native UI-Shells | **Produkt-Pfad**, realistisch erst nach ADR-005-Paket-Split; der headless-CI-Build (Linux `swift build` läuft heute schon als Gate!) hält diesen Pfad kontinuierlich offen. |
| **(c) C-Interop-Extraktion** der DSP-Hot-Paths | Nur falls (a) an Toolchain-Grenzen scheitert. Nicht vorbereiten, nur nicht verbauen (pure Swift-Mathe ohne Framework-Typen erfüllt das nebenbei). |

## Nicht-Ziele v1

- Kein nicht-Apple-Binary, kein Web-Client, kein Android-Client von uns.
- Kein JUCE, kein CMake, keine Wiedereinführung der 2026-06-19 gelöschten
  Desktop-Scaffolds.

## Konsequenzen

- Jede Protokoll-/Schema-Änderung ist versioniert und aktualisiert
  `ECHOEL_SESSION_PROTOCOL.md` im selben Commit (P3-Regel).
- Der bestehende Linux-CI-Lauf (`ci.yml`, SwiftPM build+test) ist de facto
  schon der P4-Wächter — der Import-Bann-Grep wird dort angehängt (kleiner,
  eigener Zyklus, kein neuer Workflow).
- Review-Datum: mit Abschluss von Layer 6 Gate A oder 2026-10-01, je nachdem
  was früher eintritt.
