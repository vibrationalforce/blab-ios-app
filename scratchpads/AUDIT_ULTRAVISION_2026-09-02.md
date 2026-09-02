# ULTRAVISION-AUDIT 2026-09-02 — Codebase · Architektur · Skills · DMMW-Stand · Vision-Dokumente · Deploy

**Auftrag (Founder, wörtlich):** „Ultravisionaudith Codebase and Architecture skill Management ultracode
DMMW entfalt Echoelmusic Vision merge und TestFlight deploy"

**Verfahren:** 5 Teams (je 3 Leser + 1 Lead, alle read-only), danach 3 unabhängige Widerleger pro
Major-Befund, danach ein Vollständigkeits-Kritiker. Gemessen an HEAD `a82942a`/`d1dd1f2`.
117 Agenten, 797 Werkzeugaufrufe, 133 Minuten.
⚠️ **Das Verfahren ist NICHT vollständig gelaufen:** nach 17 von 32 Widerlegungs-Runden griff das
Sitzungslimit; **15 Major-Befunde sind UNGEPRÜFT** (§3) und der Kritiker lief nicht (§6 ist daher
meine eigene Liste, keine gemessene). Wer einen §3-Punkt umsetzt, misst ihn vorher selbst.

---

## 0. Das Urteil in fünf Zeilen

1. **Die Architektur ist gesund.** Ein Bus (`EngineBus`), Audio-Datenpfad bewusst bus-frei, sieben
   Render-Rümpfe ohne verbotene Token, `DSP/` importiert exakt {Foundation, Accelerate}, die
   Präsentationskette steht bei den gepinnten 14. Schulden sind RICHTUNGS-Schulden (Ordner), keine
   funktionalen.
2. **Die DMMW lebt als Code, ist tot als Fähigkeit — unverändert seit 07-31, und niemand hat das
   formal entschieden.** Alle zehn Modell-Typen existieren mit gleich vielen oder mehr Referenzen
   (Timeline 61→75). `#132 Slice 5b–5d` (Modell-Entfernung) ist weder ausgeführt noch auf HOLD.
   `decisions.csv` zeigt seit 07-31 **null** Richtungswechsel — die Sperrfrist hält.
3. **Die Messinstrumente sind ehrlich, die Anweisungen nicht überall:** neun Zeilen der immer
   geladenen `CLAUDE.md` verlangen `swift build`/`swift test`, ohne dass hier eine Toolchain
   existiert; `CLAUDE.md` steht 1.100 B unter seiner blockierenden Decke.
4. **Vision-Dokumente:** Store-Text, README, Website und `CLAIMS.md` sind bei den GESTRICHENEN
   Behauptungen konsistent. Die Drift sitzt im Ring, den kein Wächter liest: fünf Website-Sätze
   verkaufen Türloses oder verschweigen Ausgeliefertes (§1).
5. **v10.79.436 ist deployt** (TestFlight-Build 2554, App Store Connect `VALID`, 10:10 UTC). Und
   die Build-Notiz von 434, 435 UND 436 macht einen blockierenden Wächter rot (§4).

---

## 1. Bestätigte Befunde (11 — je drei Widerleger, höchstens einer hat widersprochen)

| # | Team | Befund | Reparatur |
|---|---|---|---|
| 1 | ARCH | Drei Nicht-UI-Module importieren aus `Studio/`, weil vier reine Gesetz-Enums dort liegen: `FeedbackGuard`, `FlashGuard`, `LoudnessTarget`, `SpectralColor` (Audio→Studio 13 Refs, Sync→Studio 15, Sequencer→Studio 6). | Ordner-Umzug nach `Core/`, kein Code-Wechsel. ⚠️ `project.yml` listet explizite Pfade (founder-gated) — vorher prüfen, ob es eine Zeile braucht. |
| 2 | DMMW | `#132 Slice 5` (DAW-Modell-Entfernung) ist NICHT ausgeführt (nur 5a: `LaunchQuantizer`+`ClipLaunchGlyph` weg) und NICHT formal auf HOLD — das A0 aus `ULTRAARCHITECTURE_DMMW_2026-07-31.md` hat keine `decisions.csv`-Zeile. Die Schicht wird bei jedem Start konstruiert; `TimelineRegionPlayer.play(` hat null Produktions-Aufrufer. | **Founder-Entscheidung** (§5, Frage 1). Eine Zeile in `decisions.csv`, egal in welche Richtung. |
| 3 | DMMW | `scratchpads/HANDOVER_2026-08-13.txt` §3 „DMMW GATE CHARTER" ist das EINE Dokument nach 07-31, das BREITE liest (Stufen bis „AUv3 GENERATOR revived", „Stage 4 IS the workstation") — ohne Superseded-Banner, während `decisions.csv` L388 (#590, Folgetag) „kein Plugin-System" sagt. | ⛔-Banner an §3 mit Zeiger auf `PRODUCT_DEFINITION.md` + #590. |
| 4 | SKILLS | `.claude/commands/workflow.md:24-25` verlangt `swift build`/`swift test` als Phase 3 ohne CI-Fallback; `doctor.py` sieht es nicht, weil sein Regex zeilen-initial ist (`doctor.py:716`). | Phase 3 in der `verify.md`-Form umschreiben; Doctor-Regex auf `(^|[\`\s])swift\s+(build|test)\b`. |
| 5 | SKILLS | `CLAUDE.md` verlangt `swift build`/`swift test` unbedingt in RALPH-Protokoll (430, 433), SESSION START (463, 465), 4-Phase (797, 799, 803, 804); nur 553 hedgt. `command -v swift` → nichts. | EIN Satz je Block: „Web-Sessions: pushen, die zwei CI-Gates lesen (`Tests/CISmoke/CLAUDE.md` §5)". ⚠️ Kostet Bytes gegen 1.100 B Kopfraum — vorher einen Provenienz-Block ins Ledger. |
| 6 | SKILLS | `CLAUDE.md` sagt „Read first" über ein 1,81-MB-`SESSION_LOG.md` und „scan HARNESS_LEDGER" (298 KB), während der Hook nur `sed -n '1,80p'` liest und das Ledger gar nicht. | Gedeckeltes Rezept in `CLAUDE.md`: „der Hook druckt head-80; DEAD-ENDS-Index = `grep -n '^## ' HARNESS_LEDGER.md`". |
| 7 | DOCS | `docs/architecture.html:279` verkauft „a 60-second camera-pulse measurement" — `PulseMeasurementView` ist türlos (`BioSourceView` hat 0 Konstruktionsstellen). | Halbsatz streichen; erreichbar ist die Puls-Pille → `bioPanel`/`BioStripView`. |
| 8 | DOCS | Website führt den externen Bildschirm auf drei Seiten als „Planned" (`architecture.html:358`, `overview.html:170/:243`, `faq.html:44/:114`), während #206 ausgeliefert ist und `CLAIMS.md` ihn freigibt. | Auf LIVE ziehen, alle drei Seiten inkl. JSON-LD in EINEM Commit; Projection-Mapping bleibt geplant. |
| 9 | DOCS | `architecture.html` widerspricht sich bei MPE Press: `:390` listet „channel pressure" als Roadmap, `:189` sagt „not available on the way in", `:195-196` und der Code sagen: klingt seit #939. | `:390` → „MPE zone detection (RPN 6,6) on input"; „and channel pressure" aus `:189` streichen. |
| 10 | DOCS | `architecture.html:253` „breath depth scales pad and bass level" — der Wert kommt aus der Kohärenz (`EchoelStudioView.swift` `dynamicDepth = 0.3 + 0.5·liveCoh`); der echte Atemtiefen-Produzent hat null Aufrufer. | Umformulieren auf Kohärenz; den Producerless-Wächter auf `architecture.html` ausdehnen. |
| 11 | DOCS | `README.md:32` beschreibt fünf Chips; der Code rendert acht (`studioChips` inkl. Master, Composition, Export). | README `:32-42` auf acht Chips; Bio (Puls-Pille), Video (Header), Tempo als Nicht-Chip-Türen. |

## 2. Widerlegt (6) — und WARUM, weil die Widerleger hier echte Über-Behauptungen gefangen haben

- **„Core/ verletzt Einweg-Abhängigkeiten (150 Refs nach Sequencer)"** — Messung stimmt, aber das Repo
  behauptet nirgends Einweg-Abhängigkeit für `Core/`; die Spine-Dateien selbst sind sauber. Bleibt als
  Messung, nicht als Defekt.
- **„Geräte-Verifikation der Ausgabestufe ist unaufgezeichnet (80 offene Bitten)"** — stimmt, ist aber
  vollständig in `CLAUDE.md` (Ship-Gate 4) und `founder-verify.py` aufgezeichnet. Nicht neu.
- **„doctor.py: 2 CRITICAL in Sektion A"** — reproduziert, aber beide sind #208/#396, founder-gated,
  längst bekannt. Nicht neu.
- **„CLAUDE.md 1.100 B unter der Decke"** — Zahl stimmt, steht aber schon in vier Stellen; die Folge
  („nächster Absatz macht das Gate rot") ist überzogen, weil der Wächter genau dafür gebaut ist.
- **„Website verkauft eine unerreichbare Atem-Führung"** — **FALSCH**: die ~6/min-Führung ist über eine
  DRITTE Fläche erreichbar, die der Leser übersehen hat (Widerleger hat die `pacer.start(`-Treffer
  neu zugeordnet). Ein Hinweis auf `BreathGuideView` ist NICHT die einzige Tür.
- **„Haptik als körpergetrieben verkauft"** — die Code-Hälfte stimmt (Haptik folgt der Transport-Uhr,
  `breath(phase:coherence:)` hat null Aufrufer), ist aber als #552 (2026-08-12) bereits entschieden
  und aufgezeichnet.

## 3. UNGEPRÜFT (15 — das Sitzungslimit hat die Widerleger gestoppt; vorher selbst messen)

DOCS: Ship-Gate-Lohn „lift the TestFlight freeze" ist in `CLAUDE.md:34` und `PRODUCT_DEFINITION.md:107`
veraltet (Freeze am 07-17/07-31 gehoben, 55 Bumps seither) · `ROADMAP.md` nennt sich kanonisch, letzte
Struktur 06-19, kennt `PRODUCT_DEFINITION` nicht · `ROADMAP.md:106` vs `:131` Broadcast-Widerspruch ·
nur 9 von 108 `PLAN_*/VISION_*` tragen ein SUPERSEDED-Banner · `VJ_BRIDGE.md` §5 verkauft Broadcast im
Präsens unter einer „CUT"-Überschrift · `memory/decisions.md` spiegelt 0 der letzten 10 csv-Zeilen ·
`./review.sh` → 246 fällige Entscheidungen · `memory/preferences.md:80-85` trägt die DMMW-Leitlinie
unretrahiert. RELEASE: siehe §4 (davon habe ich den Wächter-Befund selbst nachgemessen).

## 4. Deploy v10.79.436 — Stand und der Fehler darin

- **Hochgeladen und verifiziert:** Lauf 33617257066, Build 2554, `state=VALID` 10:10:41 UTC. Alle
  Jobs grün. Code = `a82942a` (Compile Check grün, Build for Testing grün, 0 Fehler im Log-Fenster).
- ⛔ **`TheDeployNoteNamesRealDoorsTests` Anspruch 2 ist ROT auf `.deploy/release` — seit v434
  (drei Deploys).** Der Wächter (#820, 2026-08-25) verlangt einen `X-Chip`/`X-Panel`-Pfad, damit der
  Founder mit dem Telefon in der Hand eine Tür findet; die Notiz hat keinen. Selbst transkribiert:
  `tokens: []`. Unsichtbar, weil CI/CD auf jedem Push rot ist (#396). Drei weitere Einwände geprüft:
  „alle 14 Code-Commits" (13 — `ed4849e` ist kommentar-only) · „stiller Start endet an
  `session: configure FAILED`" (falsch — die Zeile steht MITTEN im Log, `prepareGraph` baut weiter;
  ein stiller Start endet an `engine: start FAILED — <Schritt>`) · „verweigert statt abzustürzen"
  (zu viel — der Code nennt die asynchrone Neuverhandlung als Rest-Fenster, `AudioEngine.swift` ~2847).
- **Entscheidung:** kein 437 nur für die Notiz (jede Änderung an `.deploy/release` = Apple-Upload).
  Die korrigierte Notiz fährt mit der nächsten Code-Scheibe. Bis dahin ist der Wächter bewusst rot.

## 5. Fragen an den Founder (konsolidiert aus fünf Leads)

1. **DMMW — A0:** `#132 Slice 5b–5d` (Audio-Region-Playback, Arrangement-Playback, Clip/ClipStore):
   **HOLD oder VERWERFEN?** Heute: bei jedem Start konstruiert, von zwei CISmoke-Wächtern gehalten,
   42 von 58 `TimelineStore`-Methoden ohne Aufrufer. Eine Zeile entscheidet es.
2. **„DMMW entfalt"** in Deinem Auftrag: meinst Du (a) die AUSGABESTUFE ausbauen (Bild · Licht · Raum ·
   Haptik — die überlebende Hälfte, `PRODUCT_DEFINITION.md`), oder (b) die WORKSTATION-Hälfte wieder
   öffnen (Spuren, Clips, Automation-Flächen)? (b) kehrt die Grand-Council-Entscheidung vom 07-25 um
   und wäre Nr. 20 im eigenen Flip-Log — `ULTRAARCHITECTURE_DMMW_2026-07-31.md` §7 sagt dazu:
   „Wenn diese Frage in zwei Wochen erneut kippt, ist die Ursache nicht der Plan."
3. **„Mehrere Spuren"** (Deine Bitte in `decisions.csv` L474) gegen CUT „Multi-track" in der
   Produktdefinition: mehrere INSTRUMENT-Stimmen (was `mixerPanel` heute mischt) oder mehrere
   Timeline-Spuren?
4. **Ship-Gate-Lohn:** „alle fünf Checks wahr" löste früher das Freeze-Ende aus; das gibt es nicht
   mehr. Was soll es heute auslösen — App-Store-Einreichung, ein v1.0-Tag, nichts Formales?
5. **Ordner-Umzug** der vier Gesetz-Enums `Studio/`→`Core/`: darf eine Sitzung das tun, wenn
   `project.yml` keine Zeile braucht?
6. **Mono-Route** (Bluetooth-Headset im HFP-Modus bei Mikrofon an): tun Harmony/Granular dann hörbar
   nichts? Der Insert schaltet sich bei 1-Kanal-Master ab (`MonitorInsertAU.swift:329`). Ein Gerätelauf.
7. **Gerätesitzung Ausgabestufe:** `artnet.out`/`sacn.out` mit einem sACN-Viewer im LAN, `adm.out` mit
   einem OSC-Monitor — treibt Musik/Körper den Empfänger sichtbar? Dann kann `SACNSender.swift:277`
   ein `VERIFIED-<Datum>` tragen (heute: null VERIFIED-Marken im ganzen Baum).
8. **ci.yml:290-291** filtert eine Testklasse `ComprehensiveTestSuite`, die nicht existiert, und der
   Job ist mit `|| true` maskiert (founder-gated): Maske heben, oder den Performance-Job löschen?
9. **TestFlight-Kontingent:** `preferences.md` sagt „kein Limit" (06-20), `auto-merge-claude.yml` wurde
   am 06-16 wegen Kontingent-Erschöpfung abgeschaltet. Was gilt für den manuellen Pfad?

## 6. Was dieses Audit NICHT angesehen hat (der Kritiker lief nicht — meine Liste)

Bio/rPPG-Vertrauen (`CameraRPPGTrustTests`) · Sync-Egress im Detail (Art-Net/sACN-Paketbau) ·
Video-Capture (`VisualRecorder`/`VideoMuxer`) · Watch-Target (kein Transport, #549) · `EchoelAI/`
(null Aufrufer, `FeatureFlags.echoelAI` ohne Leser) · `EchoelStore`/StoreKit (unerreichbar) ·
Entitlements/`Info.plist`-Sync · Sicherheits-Scan (Secrets, OSC-Klartext). Jeder Punkt ist ein
eigenes Team, nicht ein Nachtrag.

## 7. Merge-Stand

`origin/main` == `a82942a` (Auto-Merge). Der Bump `d1dd1f2` erreicht `main` mit dem nächsten
Code-Commit als Passagier (`.deploy/release` steht in keinem Merge-Pfadfilter, #697). Nichts wartet.

---
*Belege: `/tmp/…/tasks/wzlnp1xgk.output` (Sitzungs-Scratch, nicht im Repo) — jede Zeile oben trägt ihre
Datei:Zeile oder ihren Befehl; wer sie umsetzt, führt den Befehl noch einmal aus.*
