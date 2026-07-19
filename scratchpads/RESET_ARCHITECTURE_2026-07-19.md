# Echoel — Architektur-of-Record & Reset-Plan (2026-07-19)

**Founder-Entscheidung (Grand Council):** KEIN From-scratch-Rewrite. **Reset-in-place** —
den funktionierenden Kern behalten, den Cruft rausschneiden, Architektur + Plan
festschreiben. Dieses Dokument ist ab jetzt die **Quelle der Wahrheit** für Scope &
Struktur (löst die verstreuten PLAN_*/Vision-Docs als Nordstern ab).

**Grounding (heute gemessen, nicht behauptet):** 343 Swift-Dateien (CLAUDE.md sagt noch
~212 → +62 % gewachsen), davon **80 allein in `Studio/`**. Mehrere Views von 0 Dateien
referenziert (`BroadcastView`, `ArrangementView`). `FeatureFlags` existiert (16+ Flags).
→ Die Cruft-Diagnose ist messbar, nicht gefühlt.

---

## 1. NORDSTERN (Scope-Lock — das eine Gesetz über allen)

**Echoel ist ein bio-reaktives Performance-INSTRUMENT.** Der Körper (Puls, Atem, HRV,
Kohärenz) verändert generativ Klang und Bild in Echtzeit. Das ist der Kern-Job (JTBD).
**Alles andere ist optional und muss sich diesem Kern unterordnen** — oder es fliegt raus
bzw. wird hinter ein FeatureFlag gegated.

Der Fokusverlust seit „DMMW" war: zu viele Nebenjobs gleichzeitig halb gebaut. Der Reset
stellt den Kern als Rückgrat wieder her.

---

## 2. ARCHITEKTUR-OF-RECORD (die reale, funktionierende Spine — NICHT anfassen)

```
Körper → Bio-Publisher → EngineBus → Instrument → Klang + Bild
```

- **EngineBus** (`@MainActor @Observable` Kontroll-Ebene + lock-freie SPSCQueue) = die EINE
  echte Kopplungs-Spine. Module koppeln NUR über den Bus. 3 Topics; Bio fließt über den
  `latestBio`-Snapshot (10 Hz Poll), MIDI über die SPSC-Queue.
- **Bio-Quellen (live):** HealthKit · Kamera-rPPG (lockt on-device — v296-Log: 64 bpm,
  conf 0.76) · Universal BLE HR (0x180D) · Demo. → Bio-Snapshot.
- **Geschützte DSP-Triad (READ-ONLY, Rausch):** BioSignalDeconvolver · HilbertSensorMapper ·
  BioEventGraph. Nie vereinfachen.
- **Instrument-Kern (funktioniert, geshippt):** EchoelDDSP (bio-reaktive Synth-Voice) +
  PolySynthVoice + SubBassVoice + DrumSynthVoice/BeatPlayer · Patch-Editor/Presets ·
  Sequencer/Transport · MIDI-Export · Clips + Arrangement (Timeline).
- **Egress (live):** OSC (`/echoelmusic/bio/*`) · ADM-OSC (immersive Objekte) · Art-Net +
  sACN (EchoelLux). CoreMIDI MPE In.
- **Visual:** MetalBioView (flash-safe ≤3 Hz) + FloatingVisualWindow.

**Diese Spine ist gesund.** Der Reset fasst sie NICHT an — er räumt drumherum auf.

---

## 3. DIE GESETZE (gerät-erkaufte Invarianten — nicht verhandelbar)

Jede dieser Regeln hat einen Device-Crash/Freeze/Stille-Zyklus gekostet. Sie sind der
Hauptgrund, warum ein Rewrite dumm wäre — sie neu zu lernen = Monate Schmerz.

1. **Sheet-Chain nicht wachsen lassen** — SwiftUI-Metadata-Limit → Black-Screen-SIGSEGV.
   Neuen Modal: bestehenden Slot wiederverwenden / zu einem `.sheet(item:)`-Enum
   konsolidieren. Nie anhängen.
2. **Kein 10-Hz-`@Observable`-Read in Root/Ancestor-Body** (auch nicht via `AnyView`) —
   Menü-Freeze. Live-Bio nur in eigenen Leaf-Views lesen.
3. **Audio-Thread: lock-/alloc-/ObjC-/GCD-/IO-frei.** `nonisolated(unsafe)`-Mirror für
   Render-Reads.
4. **Nie `Task { @MainActor }` pro Frame** aus 30-fps-Quelle — in Low-Rate-Poll batchen.
5. **`DSP/` ohne `Core`/`Sequencer`-Typen** — AUv3 kompiliert `DSP/` isoliert.
6. **Flash ≤3 Hz, Slews ratenbasiert** (WCAG/Epilepsie).
7. **AUv3-Registrierung:** AudioComponents unter `NSExtensionAttributes`; **Host braucht
   `inter-app-audio`-Entitlement** (v297-Fix). AVAudioEngine.connect() RAISED → Format-
   Preflight-Gate vor attach.
8. **Kein Heilungs-/Wellness-/esoterik-Claim.** EchoelValueField für alle Parameter.
9. **@AppStorage-Keys nur über StudioDefaultKeys** (Divergenz = stille Bug-Klasse).

(Vollständig + Fix-Muster in `.claude/skills/` + `HARNESS_LEDGER.md`.)

---

## 4. BESTANDSAUFNAHME — jede Oberfläche: KEEP-CORE / GATE / CUT

**Prinzip (Taleb, via negativa):** Im Zweifel CUT oder GATE, nicht behalten. Jede sichtbare
Fläche muss einen Job erfüllen; jede unsichtbare tote Fläche ist Verwirrungs-Schulden.

### KEEP-CORE (die Spine — bleibt sichtbar, wird poliert)
- WorkspaceView-Shell (Header + TransportBar + EchoelStudioView + FloatingVisualWindow)
- EchoelStudioView (das Instrument), Bio-Strip (Leaf), Composition-Panel, FX-Character
- Timeline: Spuren/Lanes, Clips, Piano-Roll, per-Lane-Patch, Automation-in-Clip
- Patch-Editor, Sample-Browser, AUv3-Browser (jetzt mit Entitlement)
- Bio-Guide (tap-to-learn + „how your body shapes the sound")

### GATE (existiert, hinter FeatureFlag/founder-Tür — nicht im Weg, nicht gelöscht)
- Immersive Stage / Spatial (`spatialEngine`, `bioSpace`) — bereits geflaggt
- EchoelAI-Foundation (`echoelAI`, default OFF) — behalten, geflaggt
- Kamera-Expression-Modulator (`cameraExpression`) — geflaggt; braucht Info.plist-Kamera-OK
- Multi-Roll / Lane-AU (`multiRoll`, `laneAUInstruments`) — geflaggt
- Session-Engine (SessionView/SessionGuide/EntrainmentEngine) — **türlos lassen**, hält die
  getesteten Flash-Safety/Pacing-Gesetze; nicht löschen, nicht präsentieren.

### CUT-KANDIDATEN (tot / doppelt / abgeschaltet — Reset-Kandidaten, einzeln verifizieren)
- **`BroadcastView`** — 0 Referenzen, RTMP nicht integriert (HaishinKit nicht gelinkt). CUT
  oder in einen `broadcast`-Flag-Stub. RTMP ist Roadmap, nicht v1.
- **`ArrangementView`** — 0 Referenzen (Timeline hat es ersetzt). CUT nach Verify.
- **`SpectralDonutView`, `MeditationView`, `AudioInputPickerView`** — je 1 Referenz, türlos.
  Verify: echter Consumer oder toter Slot? Toter Slot → CUT.
- **`EchoelStore`/`ProGate`/`ProUnlockView`/`AnnouncementCenter`** — hat jetzt Consumer
  (WorkspaceView/App), aber Monetarisierung ist NICHT v1-Scope und CloudKit ist gated OFF.
  **Founder-Entscheidung nötig:** One-time-Unlock jetzt oder ganz raus bis v1.1?
- **Doppelte alte Surfaces** (ClipView/ChannelRackView/BrowserView) vs. Timeline — prüfen,
  welche die Timeline schon ersetzt hat → Duplikat CUT.

**Regel:** kein CUT ohne (a) 0-Referenz-Verify bzw. Founder-OK bei sichtbarem Feature,
(b) eigener Ralph-Zyklus, (c) grüne Gates. Reversibel via git.

---

## 5. DER RESET-PLAN (phasiert, ein Zyklus pro Punkt)

**Phase 0 — AUv3 schließen (läuft):** v297-Entitlement-Test. Grün → item 3 erlebbar. Rot →
Weg B. *Blocker-Priorität, alles andere wartet bis das Ergebnis da ist.*

**Phase 1 — CRUFT SCHNEIDEN (die eigentliche „Reset"-Arbeit, ~5–8 Zyklen):**
Je Zyklus EINE tote/doppelte Fläche aus §4 CUT-Liste: 0-Referenz verifizieren → löschen →
Gates grün → Ledger-Zeile. Ziel: 343 → spürbar kleiner, keine türlosen Views mehr, keine
Duplikate. CLAUDE.md „CURRENT STATE" + FEATURE_MATRIX synchronisieren (der 212-vs-343-Drift
zeigt: die Doku hinkt — Teil des Resets).

**Phase 2 — KERN POLIEREN (das reine Instrument großartig machen):**
Founder-Prioritäten in Reihenfolge: (1) Automation-in-Spur fertig · (2) Bio-Modulation live
sichtbar (Leaf) · (3) AUv3-Belegung pro Spur (nach Phase 0) · (4) MIDI/MPE-Station aus
„rudimentär" heben · Klang organisch/professionell + Visual „wow".

**Phase 3 — NEBENJOBS (nur nach Kern-Politur, je einzeln, geflaggt):**
Video-Spuren · Warp · EchoelPublish · Weather-Synth · EEG. Jeder als abgeschlossener,
sichtbarer Job — NICHT wieder fünf gleichzeitig halb.

**Kadenz-Gesetz gegen Rückfall:** Ab jetzt gilt „**erst fertig, dann nächstes**". Eine Fläche
ist erst „fertig", wenn sie sichtbar erreichbar, getestet und auf dem Gerät bestätigt ist.
Kein neuer Nebenjob, solange ein angefangener nicht fertig ist. Das ist die Kur gegen den
DMMW-Fokusverlust.

---

## 6. SOFORT NÖTIGE FOUNDER-ENTSCHEIDUNGEN (blockieren Phase 1)
1. **Monetarisierung** (EchoelStore/ProGate): jetzt One-time-Unlock verdrahten, oder ganz
   raus bis v1.1? (beeinflusst, ob wir es CUTten oder polieren)
2. **RTMP/Broadcast**: als Roadmap bestätigen → BroadcastView CUT/Stub? (Apple 2.1-Frage
   war schon offen)
3. Sonst: freie Hand für Phase-1-Schnitte nach dem 0-Referenz-Verify-Gesetz.

---

*Dieses Dokument ersetzt als Nordstern die verstreuten Vision-Docs. Änderungen am Scope
laufen über The Council; große Gabelungen über Grand Council. Entscheidung geloggt in
`decisions.csv`.*
