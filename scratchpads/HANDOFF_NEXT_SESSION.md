# HANDOFF — nächste Claude-Code-Session (Fable 5), Echoelmusic

Kopiere den Block unten als erste Nachricht in den neuen Chat.

---

Du bist Claude Code (Fable 5) für Echoelmusic (iPhone-first bio-reaktives
generatives Instrument, Repo vibrationalforce/Echoelmusic, Branch
`claude/piano-roll-clip-view-wozlie`, Founder Michael, deutschsprachig).
Lies zuerst: CLAUDE.md · memory/*.md · scratchpads/SESSION_LOG.md (Forts. 16
oben) · scratchpads/PLAN_ONE_VIEW_CONVERGENCE_2026-07-10.md ·
docs/dev/VISION_REALITY_2026-07.md. Kein lokaler Swift-Build — CI-Gates
(Quick Test/CI/Xcode Compile Check) + TestFlight via `.deploy/release`-Bump
sind die einzige Wahrheit. GitHub nur über MCP (Ergebnisse überlaufen →
in Datei speichern, mit python3 parsen).

## PRIORITÄT 1 — offener BLOCKER: Launch-Crash
v10.79.144 stürzte SOFORT beim Öffnen ab (kurzes Aufblinken → weg) =
SwiftUI-Metadata-Crashklasse (wie 10.76.34; CI grün, Gerät tot). Fix
v10.79.145 (Commit f8f7ade): AnyView-Erasure der SurfaceHost-Naht +
Sheet-Muster in ArrangeTimelineView. v145 ist grün + auf TestFlight.
→ WARTE auf Founder-Antwort: „Öffnet v10.79.145?" (er muss in TestFlight
  die Build-NUMMER 145 prüfen, nicht 144 testen).
→ Falls JA: Gerätetest (quer/hochkant, Spur-Kopf-Menüs, Piano Roll, stummer
  Push nach News-Toggle aus→an).
→ Falls NEIN: Founder um Analysedaten-Screenshots bitten (Einstellungen →
  Datenschutz & Sicherheit → Analyse & Verbesserungen → Analysedaten →
  „Echoelmusic-…"). Lade dann das device-log-triage + swiftui-render-safety
  Skill. NOTBETRIEB-Plan B (bereit, 1 Zeile): SurfaceHost temporär auf den
  v143-Baum zurück (nur EchoelStudioView im Vollbild, Timeline zu), der
  nachweislich startete → als v146 raus, während die Screenshots die echte
  Absturzstelle zeigen. KEIN dritter Blindfix ohne Log.

## Aktueller Produktstand (heute 2026-07-10 gebaut, alles gepusht + grün)
- **EINE Hauptansicht (Ableton-Layout, founder-Auftrag):** SurfaceHost =
  Arrange-Timeline ÜBER dem Instrument, quer+hochkant, keine Chip-Leiste mehr.
  Spur-Köpfe = Türen (MIDI→Piano Roll, Audio→Audio-Editor, Rename, Delete, +).
  Dateien: Studio/SurfaceSwitcher.swift (SurfaceHost), ArrangeTimelineView.swift,
  WorkspaceView.swift. SurfaceSwitcherBar bleibt im Code, unmounted.
- **Stiller Push:** AnnouncementCenter.swift — soundName entfernt + .sound aus
  Auth raus. notificationInfo liegt SERVERSEITIG → Founder muss News-Toggle
  einmal aus→an schalten, damit die Subscription neu speichert.
- **Regel (Founder):** außer der Musik macht die App KEINE Töne (Sweep bestätigt).

## Nächste Bau-Reihenfolge (SOBALD Crash verifiziert weg)
K2 → K3 → Mix-Balance → Sample-Browser → Video-Lanes (Plan im Konvergenz-Doc):
- **K2 (generalisiert, Founder-Beschluss 2026-07-10):** Spur = universeller
  Mixer-Strip für ALLE Typen (MIDI/Audio/Video/Visual/Light/FX) — Level/Mute/Solo
  im Spur-Kopf. ChannelRackView (heute Drum-Kanäle) wird internes Detail.
  Drums SAMPLE-FIRST (Geräte-/Drive-Samples via Files, funktioniert schon
  security-scoped); neurale Sample-Synthese GEPARKT (klappte nicht, verschmiert
  Transienten). TimelineLane braucht optionale Engine-Referenz — heute NULL
  Bindung (Audit-Kernlücke). BeatPlayer unangetastet.
- **K3:** Regionen drag/move/resize (magneticSnap + TimelineStore-APIs existieren)
  + Timeline TREIBT das Playback (heute noch bar-granularer Legacy-ArrangementPlayer).
- **Mix-Balance-Zyklus (masteringthemix-Level, Founder-Anspruch):** MESSBARE
  Ziele — der Werks-Kit ist NICHT angeglichen (One-Shots alle auf 0 dBFS ohne
  Headroom, RMS-Streuung ~20 dB). Export hat schon EQ→Comp→Limiter→LUFS −1 dBTP.
- Video: Stage V/3–5 (Aufnahme gegen Transport-Clock → Schnitt-Lane → MP4).

## Pipeline offen: Sample-Kuration
Tool fertig + am Werks-Kit erprobt: scratchpads/tools/sample_curator.py
(klassifiziert → EchoelDrums/Break/Sampler, Pitch-Angleichung in Cents,
Leveling-Gains, Legal-Flags per Name+Länge → Review/Legal, manifest.csv).
Founder-Samples liegen in Google Drive — **aus der Sandbox NICHT erreichbar**
(Proxy-Policy blockt drive.google.com hart, 403/000; Drive-Inhalt ist nicht
ergoogelbar). Founder muss ENTWEDER das ZIP direkt in den Chat hochladen ODER
`drive.google.com`+`drive.usercontent.google.com` in der Network Policy erlauben
UND eine NEUE Session starten (Policy greift erst dann). Bei großem Pack: Git-LFS
oder Teilmenge klären. Legal-geflaggte Samples NIE in die App bündeln ohne
Einzelprüfung.

## Founder-To-dos (Launch, alles bei ihm — kein Code offen)
1) v145 am Gerät testen (s. o.) 2) CloudKit-Dashboard: Announcement-Schema anlegen
+ in PRODUCTION deployen + Push-E2E (docs/dev/CLOUDKIT_ANNOUNCEMENTS.md)
3) 8 Screenshots (docs/dev/APP_STORE_LISTING_v1.md) 4) ASC-Listing einreichen —
ERST nach seiner Gerät-Verifikation.

## Geschäftsmodell / Vision (Kurz)
v1.0 = freies Instrument JETZT (keine Kauf-UI; EchoelStore/ProGate/ProUnlockView
kompilieren unpräsentiert). v1.1 = „Echoel Live" Jahresabo ~29,99 € (SharePlay-
Sessions; wir syncen Puls+Partitur taktquantisiert, NIE Audio). v1.2 = Broadcast
(HaishinKit, die eine erlaubte Dep) + Host-Fee + Cause-Events (Partner, kein
eigener Server). Multi-Interface-Verdikt: iPhone unmöglich (OS); virtuelle
Soundkarte umgeht die Clock-Latenz NICHT (widerlegt); Mac-Version kann das
Aggregat via AudioHardwareCreateAggregateDevice automatisch in-app bauen
(Roadmap). Multichannel-Stems auf EIN Interface = der iPhone-Weg fürs BiG-SiX-
/Xone-Live-Set.

## Guardrails (hart)
Ralph Wiggum: EIN Fix/Zyklus, ≤3 Dateien, Build-grün = einziges Gate; Crash offen
= keine Features. Geschützte Rausch-Triade (BioEventGraph/HilbertSensorMapper/
BioSignalDeconvolver) read-only. Render-Safety: NIE .sheet an EchoelStudioView
anhängen (Metadata-Limit → Black Screen); NIE 10-Hz-@Observable in Ancestor-Body
(Menü-Freeze) — nur in Leaf-Views. Kein force-unwrap/print/ObservableObject;
log.log(.info, category:…). Model-Identifier NIE in Commits/PRs/Code. Nichts an
App Review VOR Founder-Gerätetest. EchoelValueField/EchoelNumberPad für alle
Parameter-UIs. Deutsche Founder-Kommunikation, ehrlich (real vs. gebaut vs.
roadmap), keine Wellness/Esoterik-Copy.
