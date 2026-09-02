# PLAN — die vier Baustellen ("Alles", Founder 2026-07-13)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Kontext: Nach v189 (Spuren = Zuhause) hat der Founder auf die AskUserQuestion
"Was zuerst wirklich funktionsfähig machen?" mit **"Alles"** geantwortet. Er hat
zudem gebeten, ZUERST zu bestätigen, dass "Spuren als Zuhause" sich richtig
anfühlt, BEVOR ich die vier Baustellen darauf baue. → v189 muss erst auf dem
Gerät ankommen + Founder-Verdikt. Dieser Plan sequenziert die vier ehrlich nach
Risiko/Verifizierbarkeit, damit die Ausführung nach dem Verdikt sofort läuft.

## Ehrlicher Risiko-Check pro Baustelle

### A) 3rd-Party-AUv3 sichtbar — **GERÄTE-GEBUNDEN, kein Blind-Fix**
- `AUv3Host.scan()` ist bereits KANONISCH: all-zero-Wildcard + explizite Typen
  (MusicDevice/Effect/MusicEffect) + volle Registry-Enumeration
  (`components(passingTest:)`) + `kAudioComponentRegistrationsChangedNotification`
  Re-Scan für asynchrone Registrierung. Mehr kann die Query nicht tun.
- Geräte-Log v187: "2 instruments + 17 effects — makers: Apple". Wenn `passingTest`
  nur Apple liefert, registriert iOS die 3rd-Party-Extensions dem Prozess NICHT —
  Umgebung/Gerät, nicht Code. AUM/Cubasis nutzen exakt dieses Muster.
- **Nächster Schritt = Diagnose AUF DEM GERÄT**, nicht Code: (1) Sind die
  installierten Apps echte AUv3-Extension-Hosts (nicht nur Standalone/IAA)? (2)
  Taucht in `auv3 scan`-Breadcrumb je ein Nicht-Apple-Maker auf, wenn man die
  Container-App einmal startet? (3) Prüfen, ob unser App-Prozess evtl. eine
  fehlende Capability hat (unwahrscheinlich — iOS braucht keine für Hosting).
- Bis Geräte-Signal: NICHT blind umbauen. Als Frage/Diagnose an Founder, kein Code.

### B) Aufnahme-Knopf — **SICHTBAR, aber AUDIO-ROUTE-RISIKO (Geräte-Verify)**
- Engine da: `MultiTrackRecorder` + `AudioConfiguration.configureAudioSessionForRecording()`
  (Upgrade `.playback`→`.playAndRecord`).
- Sichtbarer Ort: Record-Button in die PERSISTENTE `TransportBar` (immer da,
  layout-agnostisch, KEINE Sheet-Kette). Direkt gegen "recordbutton fehlt".
- RISIKO: `.playAndRecord`-Umschalten MITTEN in laufendem Generativ-Graph + aktiver
  Kamera. CLAUDE.md warnt stark vor Kamera↔Audio-Session-Wechselwirkung. Blind
  destabilisierend → NUR mit Geräte-Verify. Reihenfolge: erst pure Record-State-
  Maschine + sichtbarer Button (compile-safe), Wiring hinter Founder-Deploy-Verify.
- Ambiguität: "aufnehmen" = Output/Performance mitschneiden (universell) vs.
  Multitrack-Mic-über-Beats. Default-Annahme: Output-Mitschnitt zum Teilen (der
  einfachste ehrliche erste Schritt) — im Deploy-Note klarstellen.

### C) Audio-Dateien reinziehen + loopen — **GRÖSSTENTEILS SCHON GEBAUT (2026-07-13 verifiziert)**
- **Import + Trim + Loop + Fade EXISTIEREN und sind getestet:** `AudioClipRegion`
  (pure: `filePosition(atElapsed:)` Loop-Wrap, `isActive`, `fadeMultiplier`,
  Frame-Konversion) + `AudioClipPlayer.play(region:)` (`.loops`-Buffer-Option,
  Fades in den Buffer gebacken, additiv am Master) + `AudioClipView` (fileImporter
  `.audio` → WaveformTrimEditor → Loop/Gain/Fade → Play/Stop). Tests:
  `AudioClipRegionTests`, `AudioClipFadeTests`. Erreichbar über die Audio-Spur-Tür
  ("Open audio editor"). Der Founder fand es nur nicht, weil die Spuren zugeklappt
  waren → v189 (Spuren = Zuhause) legt genau diese Tür frei.
- **EINZIGE echte Lücke = Clip→Timeline-Region-Wiring:** der importierte Clip
  spielt im Editor-Sheet, wird aber NICHT als persistente `TimelineRegion` auf der
  Spur abgelegt, die bei Transport-Wiedergabe (mit Loop) mitläuft. Code-Kommentar
  sagt selbst "the timeline/ClipStore wiring builds on the same player next".
- Dieses Wiring ist fundament-abhängig (Region-Modell/Spur) + Live-Audio-Graph →
  Geräte-Verify. GEGATET hinter dem v189-Verdikt. Kein Blind-Bau.

### D) EchoelTools-Türen zurück — **SHEET-KETTEN-RISIKO (SIGSEGV-Gesetz)**
- Deep Audit 2026-07-12: FeedbackGuard/AudioInputPicker, BroadcastView,
  SpectralDonutView u.a. verloren mit dem Tools-Grid (2026-07-02) ihren Trigger.
- Türen zurückbringen = neue Präsentationen an der Modal-Decke → GENAU das
  SIGSEGV-Wachstums-Gesetz (10.76.34 Black Screen). Regel: NICHT anhängen —
  bestehenden Slot wiederverwenden ODER erst die ganze Kette in EIN `.sheet(item:)`-
  Enum konsolidieren. Höchstes Regressionsrisiko der vier → zuletzt, mit Council.

## Vorgeschlagene Reihenfolge (nach Founder-Verdikt zu v189)
1. **C-pure** (Loop-Mapping-Kern + Tests) — sofort, sicher, layout-agnostisch, TDD.
2. **B-sichtbar** (Record-Button in TransportBar, pure State-Maschine) — sichtbar,
   Wiring hinter Geräte-Verify.
3. **A-Diagnose** (AUv3 3rd-party) — als gezielte Geräte-Frage/Breadcrumb, kein Blind-Code.
4. **C-Wiring + Import-Tür** — Sheet-Budget zuerst prüfen.
5. **D** (Tools-Türen) — nur nach Sheet-Ketten-Konsolidierung, Council-Pflicht.

## Gate
NICHTS von B/C-Wiring/D wird gebaut, bevor der Founder "Spuren als Zuhause"
bestätigt — sonst Gefahr, erneut auf ein Fundament zu bauen, das er ändern will.
Bis dahin: nur C-pure ist unbedenklich (Fundament-unabhängig).
