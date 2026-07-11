# PLAN — One-View: „Die Spuren sind die App" (Founder-Direktive + 2 Senior-Pitch-Schleifen, 2026-07-11)

**Founder (verbatim-Kern):** Nur EINE Ansicht (die Arrange-View; das Label „Arrange"
kann weg). Alles konzentriert sich darauf, die SPUREN so perfekt auszuarbeiten, dass
man Clips LIVE performen UND arrangen kann. Pro Spur ein Bio-Generator-Knopf
(Founder-Name: „EchoelBio") für Audio-FX, MIDI/Instrument-Parameter, Video/Visual-
Parameter. Ein Arrangement-Play mit QUANTISIERTEM Hinspringen + Loop-Setzen. Pro Clip
ein Live-Play: antippen = loopt bis zum nächsten Tipp; LANGE drücken = Editor-Fenster
(Audio/MIDI/Video). „Vorbilder ja, aber wir kombinieren holistisch statt zu trennen."

## Schleife 1 — drei Senior-Reviews (SwiftUI/HIG · Core-Audio · Produkt/Visual)

**Konsens aller drei Panels:**
1. **Die Richtung ist richtig — und zu ~70 % schon gebaut.** Timeline-über-Instrument
   IST seit v10.79.144 die eine Hauptansicht; K2a-Mixer-Strips sind drin. Der Vorschlag
   ist kein Pivot, sondern die Benennung der laufenden Konvergenz (K2b/K3 + Lane-Formel).
2. **Das eine GEFÄHRLICHE Stück ist der Clip-Live-Launch in der Arrangement-View** —
   nicht konzeptionell (das ist der Pionier-Teil), sondern weil er heute in EIN
   geteiltes PianoRollModel/PatternEngine feuern würde (Clip auf Spur 2 antippen
   ersetzt stumm den Inhalt von Spur 1). Er BRAUCHT A1 (Multi-Roll) und sauberes
   Timeline-Playback (K3) als Fundament. Erst Fundament, dann Pioniertat.
3. **Launch-JETZT bleibt heilig** (Beschluss 2026-07-10B): nichts hiervon gated v1.0.
   Die Umstrukturierung ist die v1.0.x-Leiter NACH dem Submit.

**Die wichtigsten Einzel-Findings:**
- **HIG:** Label „Arrange" löschen (Zeile gewonnen). Long-Press-Editor MUSS in den
  EINEN vorhandenen `.sheet(item:)`-Slot der ArrangeTimelineView (Enum
  `ArrangeModal { case lane(...), region(...) }`) — nie ein neues Sheet anhängen
  (Metadata-SIGSEGV-Gesetz). Gesten-Baum für Regionen: Tap = Launch/Audition ·
  Long-Press-RELEASE = Editor · Long-Press-DANN-ZIEHEN = Move (K3), Resize nur über
  Handles auf SELEKTIERTER Region; Launch-Tap erst ab ≥24 pt gerenderter Breite.
  Bio-Live-Indikatoren pro Spur nur als eigene Leaf-Structs (10-Hz-Gesetz; die
  Spur-Köpfe sind Menus — ein Ancestor-Rebuild reißt sie ab).
- **Core-Audio:** Loop-Range + bar-quantisierter Seek gehören in den TRANSPORT (ein
  Wrap-Chokepoint, pur testbar). Bar-quantisierte Sprünge sind für v1 die ehrliche
  Grenze (Main-Queue-Timer-Clock). ZWEI konkrete Bugs beim Springen heute:
  `playedBars`-Zähler statt Positions-Ableitung (Sounding-Bar dauerhaft phasenversetzt)
  + veraltetes `pendingNotes` (ein falscher Takt nach jedem Sprung) → Fix: Bar-Index
  aus `transport.position.bar % N` ableiten, pendingNotes im Sprung-Handler neu stagen.
  Clip-Launch = EIN Lane-Player mit „latched region override" (KEIN zweiter paralleler
  Player), LaunchQuantizer generalisiert auf Lane-Ziele; MIDI-Latch zuerst (driftfrei),
  Audio-Latch erst nach K3 (braucht Boundary-Re-Scheduling). Per-Lane-FX: Ketten beim
  Lane-Anlegen VOR-attachen, mit Bypass schalten — nie mid-play attach/detach.
  Bio+Automation-Präzedenz einmal definieren: Automation = Basiswert, Bio = begrenzter
  Offset obendrauf (nie last-writer-wins).
- **Produkt/Visual:** Namens-KOLLISION: „EchoelBio" ist bereits Tool #6 (Bio-QUELLEN:
  HealthKit/BLE/rPPG) + Klasse `EchoelBioEngine`. Panel-Empfehlung: Knopf heißt „Bio"
  (Zustände Off / Live / Hold wie ModulationMatrix), Copy „bio-conducted track";
  „Create from Within" als UI-Text ist Uncodixfy-verboten (Deko-Copy). → FOUNDER
  ENTSCHEIDET den Namen (er hat „EchoelBio" gesetzt; Kollision ist ihm vorzulegen).
  Science-first-Darstellung: beim Armen zeigt der Spur-Kopf WELCHES Signal WELCHEN
  Parameter mit AKTUELLEM Wert treibt (`HRV 0.62 → brightness`, EchoelValueField-Zeile).
  **Visual-Brücke = 3 ehrliche Modi eines Renderers:** (a) Ästhetik „Perform" =
  heutiges MetalBioView/VJ (FloatingVisualWindow) · (b) physikalisch ehrlich
  „Resonance" = Cymatics-Plan wörtlich (stehende Wellen der real klingenden Hz) ·
  (c) Engineering „Inspect" = Meter/Kurven IN den Lanes (Bio-Lane zeichnet die
  Messkurve, Automation als Zahl+Kurve). Regel: (a)/(b) nur im Visual-Fenster,
  (c) nur in Lanes, nichts Dekoratives in der Timeline-Chrome.
- **Demo-Moment, der das Produkt verkauft (ein 20-s-Screen-Recording, ungeschnitten):**
  Finger auf Kamera → Bio-Knopf auf Visual- + Melodie-Spur → Play: das Cymatics-Muster
  der real klingenden Noten wird schärfer, wenn die Kohärenz steigt, während die
  Melodie-Brightness der HRV folgt. Herzschlag → Musik → physikalisch wahres Bild.

## Schleife 2 — adversariales Verifikations-Review (Findings EINGEARBEITET unten)

- T1/K2b/A1/K3 waren heimlich Mehrfach-Zyklen → gesplittet.
- `Transport.seek` hat heute NULL Aufrufer und ist ein stummer Positions-Write —
  T1b muss seek zum echten Event machen (Subscriber benachrichtigen).
- `LaunchQuantizer` ist heute KOMPLETT unverdrahtet (dead code) und sein `fire()`
  lädt auch die DRUMS mit — L1 muss lane-scopen und den Drum-Pfad abtrennen.
- **A1 muss `rollSlotGain` + das `.onChange`-Binding in ArrangeTimelineView
  ERSETZEN** (per-Lane effectiveGain → per-Roll mixGain), sonst muted nach
  Multi-Roll die falsche Spur. Außerdem: Rolls auf `Transport.addStepSubscriber`
  umziehen (der eine `pattern.onTick`-Slot trägt keine N Rolls) + Voice-Zuteilung
  entscheiden (N Rolls vs. 1 PolySynth-Satz).
- Latch-Semantik definieren: Präzedenz über ArrangementPlayer-Re-Staging am Takt,
  Snapshot des Vor-Latch-Inhalts für Re-Tap, Stop löscht den Latch.
- 10-Hz-FALLE in der eigenen K2b-Spec: der Live-Routing-Wert (`HRV 0.62 → …`) darf
  NIE als Binding durch den Spur-Kopf fließen (der hostet Menus) — nur als eigene
  Leaf-Struct, die den EngineBus direkt liest (read-only Anzeige).
- Sheet-Budget-Klarstellung: `EchoelValueField`s eingebetteter Keypad-Sheet ist ein
  SUBVIEW-Sheet — zählt NICHT gegen den einen `ArrangeModal`-Slot; nie „konsolidieren".
- Widerspruch aufgelöst: **MIDI-Latch braucht nur T1+A1; Audio-Latch ist auf K3
  gegated** (Boundary-Re-Scheduling gegen Drift).

## Bau-Reihenfolge v3 (ersetzt K2b→A1→B2→A2→K3; ein Zyklus = ein Commit + Gerätetest)

0. ✅ v1.0-Submit-Vorbereitung bleibt unberührt davor/parallel (Listing, Review).
1. **U1 — UI-Konsolidierung (1 Datei, kein Engine-Risiko):** „Arrange"-Label raus;
   Modal → `ArrangeModal`-Enum (lane/region); Long-Press-Region → Editor-Sheet.
2. **T1a — Jump-Bugfix (pur):** PianoRollModel-Bar-Index aus `transport.position.bar`
   ableiten statt `playedBars`-Zähler + pendingNotes-Re-Stage; Transport-Handle
   durch `start()` plumben. Tests.
3. **T1b — Transport-Fundament:** `loopRange` (Takte) + bar-quantisierter `seek`,
   der Subscriber WIRKLICH benachrichtigt (heute stummer Write, null Aufrufer). Tests.
4. **A1a/A1b — Multi-Roll (2 Zyklen):** (a) Roll-Registry pro MIDI-Lane +
   Transport-Step-Fan-out; (b) `rollSlotGain`/onChange-Binding ersetzen durch
   per-Lane→per-Roll-Gain + Voice-Zuteilung. Tests pro Zyklus.
5. **L1 — Clip-Live-Launch, NUR MIDI-Lanes:** LaunchQuantizer lane-scopen (ohne
   Drum-Seiteneffekt), erstmals verdrahten; Latch ersetzt Lane-Inhalt am Takt
   (Präzedenz ÜBER ArrangementPlayer-Restaging), Re-Tap = Rückkehr via Snapshot,
   Stop löscht Latch; „live"-Badge als Leaf-Struct. Gesten-Spec aus Schleife 1.
6. **K2b-1 — Engine:** vor-attachte per-Lane-FX-Ketten + Bypass (nie mid-play
   attach/detach).
7. **K2b-2 — Bio-Key-Registry:** Namespace `lane.{id}.fx.{param}`, Präzedenz
   Automation-Basis + begrenzter Bio-Offset (B2 dockt hier an).
8. **K2b-3 — Bio-Knopf-UI** (Name: Founder-Entscheid) mit Off/Live/Hold; Routing
   editierbar (EchoelValueField), Live-WERT nur als Bus-lesende Leaf-Anzeige.
9. **B2 — Automations-Ziele auf dieselbe Registry.**
10. **A2 — MPE-Record auf Spur.**
11. **K3a — Region-Move/Resize (Gesten)** · **K3b — Timeline treibt Playback**
    (Engine); DANACH **L2 Audio-Latch** + **C Video-Block** (Capture/Trim/
    Bio-Grade/Export, kein NLE).
12. **Visual-Modi:** Cymatics „Resonance" auf Founder-Go (Screenshot-Loop);
    Lane-„Inspect"-Meter mit K2b/B2 zusammen.

## Gates / offene Founder-Entscheide
- **Name des Per-Spur-Knopfs:** „EchoelBio" (Founder) vs „Bio" (Panel, wg. Kollision
  mit Tool-Namen EchoelBio = Quellen-Gruppe + EchoelBioEngine-Klasse).
- Cymatics-Go (steht seit 07-10).
- v1.0-Submit geht VOR U1 los — nichts hiervon verzögert den Launch.

Guardrails unverändert: Render-Safety-Gesetze, Audio-Thread-Regeln, Rausch-Triade
read-only, EchoelValueField überall, Uncodixfy, ≤3-Hz-Flash, ein Zyklus pro Commit.
