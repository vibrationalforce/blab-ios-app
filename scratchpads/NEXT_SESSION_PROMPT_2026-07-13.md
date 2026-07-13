# Initial-Prompt für die nächste Session (Copy-Paste, 2026-07-13)

> Vom Founder in den neuen Chat einfügen. Stand beim Cut: v10.79.183 / TestFlight-Run
> #2289 dispatcht (b536e55), Founder testet den Build.

---

ECHOEL MODE ACTIVE — ultracode all tasks, volle Aufmerksamkeit und Präzision, no sleep.

Branch: `claude/piano-roll-clip-view-wozlie` (NICHT wechseln). Arbeite autark im
Ralph-Wiggum-Takt: ein Punkt pro Zyklus, test-first, Pflicht-Reviewer, Gates grün,
am Zyklus-Ende ein deutsches Status-Delta (Was neu · Was fehlt · nächster Schritt).
Wenn das 24h-Mandat weiterlaufen soll: stündlichen Cron-Trigger neu anlegen (der alte
hängt an der vorigen Session).

SESSION-START (Pflicht, in dieser Reihenfolge):
1. `memory/` komplett lesen, dann `scratchpads/SESSION_LOG.md` (neuester Eintrag
   Forts. 58 = die komplette letzte Session), `scratchpads/DESIGN_BRIEFS_PENDING_2026-07-12.md`
   (alle 6 Briefs BUILT, Status-Blöcke oben je Brief) und
   `scratchpads/PLAN_DMMW_PROFI_LEVEL_2026-07-12.md` (Restpunkte).
2. TestFlight-Run #2289 (v10.79.183, SHA b536e55) prüfen: grün? Wenn rot → Logs lesen,
   minimal fixen, `.deploy/release` NICHT erneut bumpen ohne Founder-Ok.
3. `git log --oneline -15` — letzte Commits e503d04→b536e55 sind der verifizierte Batch.

STAND (alles gate-grün auf 72122cf, deployt als v10.79.183):
- B8 Trap-Viertel-Anker (aroused → 808-Pedal {0,4,8,12}, nur Trap; appendBass, trapMelody ist RETIRED)
- A5 Bio-per-Note (Kohärenz+Atem → Velocity; neutral/kein Körper = Identität; Tiefen-UI fehlt noch)
- B6 BLE-MIDI-Tür (Routing-Panel → CABTMIDICentral, NavigationLink-Push, kein neues Sheet)
- L2 LightFixtureGroup + L3 BioPhaser (pure, UN-verdrahtet, ratenbasierte Flash-Slew ≤2.5 Hz)
- B7/S4 EchoelFDNReverb (pure FDN-Kern, UN-verdrahtet; RoomModel-Bridge in Core/, NICHT in DSP/)

FOUNDER-VERIFY OFFEN (v10.79.183 auf dem Gerät): (a) Trap-132-Lock A/B ruhig vs. bewegt —
kommen die Viertel? (b) BLE-MIDI-Controller koppeln (Master→Routing→Bluetooth MIDI) —
klingen die Tasten? (c) Gesamteindruck. Founder-Feedback steuert den nächsten Zyklus.

TESTFLIGHT-FREEZE: wieder AKTIV bis Founder-Urteil zu 183 (keine weiteren
`.deploy/release`-Bumps stapeln, solange er A/B-t).

NÄCHSTE BAU-KANDIDATEN (in dieser Reihenfolge, sofern Founder nichts anderes sagt):
1. B9 Visual-Polish-Audit (Wärme/Sättigungs-Kette 0.80-Mix+0.82-Sat+Floor, „Vivid"-Preset)
2. VIS-Spur VIS1-4 (Kompositions-Passes · Zustands-Übergänge · 4-Punkt-Corner-Pin · …)
3. A5-Tiefen-UI (EchoelValueField-Row im bestehenden Roll-Kontext, KEIN neues Sheet)
4. W2 Lyrics-Lane im Roll (LyricsModel W1 ist fertig) · Task #20 Voice Live VL3+
5. Wiring-Zyklen (Council-gated, device-verify): L2/L3 → Art-Net/sACN-Sender opt-in;
   S5 FDN → Master-Graph hinter FeatureFlags.spatialEngine (setRoom-Handoff MUSS
   double-buffered werden — audio-thread-Reviewer-Auflage).

HARTE GESETZE (Kurzform — Details in CLAUDE.md, gelten ALLE weiter):
- Render-Safety: EchoelStudioView-Sheet-Kette NICHT wachsen lassen (Slot-Reuse/Konsolidierung);
  kein 10-Hz-@Observable-Read in Root/Ancestor-Bodies (Leaf-Views!); nie 2 Modals gleichzeitig.
- NEU ZEMENTIERT: jede Datei in DSP/ darf KEINE Core-Typen referenzieren (AUv3 kompiliert
  DSP/ isoliert — Bridges nach Core/ als Extension).
- Determinismus: SeededRNG/UUID-fold (nie Hasher), decodeIfPresent-Migration, calm-Pfade RNG-identisch.
- Flash ≤3 Hz W3C; Licht-Slews ratenbasiert (per-Sekunde, nicht per-Tick).
- Audio-Thread: keine Locks/Allocs/ObjC/GCD im Render; @MainActor-Props nie aus Render lesen.
- Brand: kein Wellness/Esoterik/Heilungs-Claim (harter REJECT); Parameter-UI = EchoelValueField.
- CI = Ground Truth (kein lokaler Swift-Build): Quick Test ist NUR Lint; echte Gates =
  „Xcode Compile Check" + „Echoelmusic CI/CD Pipeline"; actions_list überläuft → Datei
  mit python3 json.load parsen, nach head_sha filtern.
- Protected Rausch-Triad READ-ONLY. Ein Thema pro Commit. Conventional Commits.
- Commit-Trailer: Co-Authored-By: Claude Fable 5 <noreply@anthropic.com> + Claude-Session-Link
  der NEUEN Session.

TOOLS: Context7 ist jetzt autorisiert — nutze es für Doku (z. B. HaishinKit 2.x für P4
Broadcast: async/await, MediaMixer→RTMPStream; Echoel braucht den CUSTOM-Buffer-Pfad
AVAudioEngine→Stream statt AVCaptureDevice). GitHub via MCP (github-Server) — wenn er
Auth verlangt, tokenless deployen: `.deploy/release`-Bump pushen = TestFlight-Trigger.

Starte jetzt: Session-Start-Ritual, dann #2289-Status, dann den ersten Zyklus.
