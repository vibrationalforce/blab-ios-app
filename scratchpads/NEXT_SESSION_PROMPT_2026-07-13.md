# Initial-Prompt für die nächste Session (Copy-Paste, 2026-07-13 — v2 nach Founder-Test v183)

> Vom Founder in den neuen Chat einfügen. Stand beim Cut: v10.79.183 (Build 2289) IST auf
> TestFlight und wurde vom Founder getestet — sein Verdikt steuert die Session (unten).

---

ECHOEL MODE ACTIVE — ultracode all tasks, volle Aufmerksamkeit und Präzision, no sleep.

Branch: `claude/piano-roll-clip-view-wozlie` (NICHT wechseln). Ralph-Wiggum-Takt: ein
Punkt pro Zyklus, test-first, Pflicht-Reviewer, Gates grün, Zyklus-Ende = deutsches
Status-Delta. 24h-Mandat: stündlichen Cron-Trigger neu anlegen (der alte hängt an der
alten Session).

SESSION-START (Pflicht): `memory/` lesen → `scratchpads/SESSION_LOG.md` (Forts. 58) →
dieses File → `scratchpads/DESIGN_BRIEFS_PENDING_2026-07-12.md` (6 Briefs BUILT) →
`scratchpads/PLAN_DMMW_PROFI_LEVEL_2026-07-12.md`.

## FOUNDER-VERDIKT zu v10.79.183 (2026-07-13, wörtlich zusammengefasst) — DIE Arbeitsliste

„Der Build ist da, aber ich sehe keine professionelle DMMW":

1. **AUTOMATION IN DER SPUR (höchste Prio):** Automationen gehören IN die Spur —
   sowohl IM Clip als auch CLIP-ÜBERGREIFEND auf dem Raster, mit ALLEN verfügbaren
   Parametern. Heute: AutomationView/A3-Canvas hängt hinter einer Spur-Tür (Sheet),
   nicht in der Lane; Parameter-Auswahl ist schmal. Bausteine die es SCHON gibt:
   `AutomationLane` (+curvature), `AutomationCanvasMath` (pure, getestet),
   `EchoelParameterRegistry` (keyPath-stabiles Parameter-Inventar, N2 — als
   Automations-Ziel-Katalog benutzen!). Architektur-Arbeit → ERST PLAN
   (PLAN_AUTOMATION_IN_LANE.md), Council, dann Zyklen. Render-Safety beachten:
   Lane-Rows als Leafs, kein neues Sheet, kein 10-Hz-Read im Timeline-Body.
2. **BIO-MODULATION LIVE SICHTBAR:** Parameter, die vom Biofeedback moduliert werden,
   live anzeigen (welcher Param, wie stark — z. B. Glow/Badge/Mini-Meter an der
   Param-Row). Quellen: FXBioModulator (~30 Hz!), ModulationEngine-Routen, A4/A5-
   Operator-Tiefen. ACHTUNG: 30-Hz-Werte NUR in eigenen Leaf-Views lesen (Menü-Freeze-
   Gesetz), ggf. auf ~5 Hz drosseln fürs Auge.
3. **EXTERNE AUv3 SICHTBAR MACHEN:** Founder sieht keine externen AUv3. Türen
   existieren seit 07810ba (Spurkopf-Menü „AUv3 plugins" + AUv3BrowserView), aber
   offenbar nicht auffindbar/nicht als Spur-Instrument erlebbar. QA: Tür-Pfad auf dem
   Gerät nachvollziehen, dann AUv3 als sichtbare INSTRUMENT/FX-Belegung pro Spur
   ausweisen (Spur zeigt Plugin-Namen; Hosting-Status ehrlich).
4. **LEISTEN-VERTEILUNG IN TIMELINE/SPUREN (D2/E2 fertigstellen):** „Die Verteilung
   der internen Leiste in die Timeline bzw. Spuren/Instrumente/Effekte hat noch nicht
   geklappt" — Menü-Funktionen auf die Spuren verteilen (Instrument·FX·Automation·
   AUv3 direkt am Spurkopf/in der Lane), Menüleiste schrumpft entsprechend.
5. **VISUALS IMMER NOCH GRAU — B9, jetzt BEWEISGESTÜTZT:** Das v183-Log zeigt die
   `visual:`-Zeilen: `mfNotes=2–3` (Noten kommen an), `level` bis 1.00, `tone`
   wechselt 294/440/659 (Akkordfarben werden angeliefert), `bio` 0→1, `detail=1.00`,
   `touch=0`, **`redMot=0` konstant**. → Datenpfad V1 ist INTAKT; das Grau entsteht
   STROMABWÄRTS in der Farb-/Sättigungskette (B9-Verdacht bestätigt: 0.80-Mix ×
   0.82-Saturation × Floor stapeln sich zu Grau; zusätzlich redMot=0 prüfen).
   Fix: Kette entstapeln (eine Sättigungs-Stelle), „Vivid"-Default prüfen,
   Shader-seitig verifizierbar via der displayComponents-Zwillinge + Tests.
   Device-verify durch Founder.

Reihenfolge-Empfehlung: **5 (B9, klein + beweisgestützt, sofortiger sichtbarer Gewinn)
→ 1 (Automation, groß, Plan zuerst) → 2 → 3 → 4.** Bei 1–4 vor dem Bauen je einen
kurzen Plan/Grand-Council-Pass (Architektur, >1 Datei).

Weiter offen aus v183-Test: Trap-132-A/B (Viertel-Anker B8) und BLE-MIDI-Kopplung hat
der Founder noch nicht explizit beurteilt — bei Gelegenheit nachfragen, nicht drängen.
Log-Notiz: v183 startete einmal im SAFE MODE (voriger Launch unbestätigt), erholte sich
sauber und bestätigte healthy — beobachten, nicht alarmieren.

## STAND (alles gate-grün auf 72122cf, deployt als v10.79.183 = Build 2289)
- B8 Trap-Viertel-Anker (appendBass, quarterAnchor nur .trap; trapMelody RETIRED)
- A5 Bio-per-Note (Velocity verdrahtet; Timing/Brightness modelliert; Tiefen-UI fehlt)
- B6 BLE-MIDI-Tür (Routing → CABTMIDICentral, Push, kein neues Sheet)
- L2 LightFixtureGroup + L3 BioPhaser (pure, UN-verdrahtet, ratenbasierte Slew ≤2.5 Hz)
- B7/S4 EchoelFDNReverb (pure FDN-Kern, UN-verdrahtet; RoomModel-Bridge in Core/)

TESTFLIGHT: nächster `.deploy/release`-Bump erst, wenn ein sichtbarer Fix steht (B9
wäre der natürliche v184-Kandidat). Deploy = tokenless: `.deploy/release` bumpen +
pushen triggert testflight.yml; die Dispatch-APIs brauchen Auth die fehlt — NICHT nutzen.

## HARTE GESETZE (Kurzform — Details CLAUDE.md, gelten ALLE)
- Render-Safety: Sheet-Kette NICHT wachsen lassen (Slot-Reuse); kein 10-Hz-@Observable-
  Read in Root/Ancestor (Leafs!); nie 2 Modals gleichzeitig.
- DSP/-Dateien dürfen KEINE Core-Typen referenzieren (AUv3 kompiliert DSP/ isoliert;
  Bridges als Core/-Extension).
- Determinismus: SeededRNG/UUID-fold (nie Hasher), decodeIfPresent, calm-Pfade RNG-identisch.
- Flash ≤3 Hz W3C; Licht-Slews ratenbasiert (per-Sekunde).
- Audio-Thread: keine Locks/Allocs/ObjC/GCD im Render.
- Brand: kein Wellness/Esoterik/Heilungs-Claim (harter REJECT); Parameter-UI = EchoelValueField.
- CI = Ground Truth: Quick Test ist NUR Lint; echte Gates = „Xcode Compile Check" +
  „Echoelmusic CI/CD Pipeline"; actions_list überläuft → Datei mit python3 parsen,
  nach head_sha filtern.
- Protected Rausch-Triad READ-ONLY. Ein Thema pro Commit. Conventional Commits.
- Commit-Trailer: Co-Authored-By: Claude Fable 5 <noreply@anthropic.com> + Claude-Session-
  Link der NEUEN Session.

TOOLS: Context7 ist autorisiert — für Doku nutzen (z. B. HaishinKit 2.x: async/await,
MediaMixer→RTMPStream; Echoel braucht den CUSTOM-Buffer-Pfad AVAudioEngine→Stream).

Starte jetzt: Session-Start-Ritual → B9 (Visual-Grau, log-beweisgestützt) als erster
Zyklus → dann PLAN für Automation-in-der-Spur.
