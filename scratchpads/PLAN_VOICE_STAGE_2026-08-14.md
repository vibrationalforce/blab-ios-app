# PLAN — Voice Stage: Monitoring · Routen · Feedback · Harmonizer · Tönen

**Stand:** 2026-08-14, Founder-Ask (wörtlich: Direktmonitoring am Handy · Bluetooth
optimieren · USB-C-Kopfhörer · USB-Mikro/Interface-Auto-Erkennung · Fiepen automatisch
unterdrückt · Harmonizer mit Voice-Clone · evidenzbasiertes Tönen). Jede Zeile unten ist
gegen den Quelltext gemessen, nicht erinnert — die Hälfte der Liste ist GEBAUT und braucht
nur die Geräteprobe, nicht den Neubau.

## Was EXISTIERT (Tür: Master-Panel → „Audio input" — Geräteprobe, kein Neubau!)

| Founder-Ask | Stand | Beleg |
|---|---|---|
| Direktmonitoring am Handy | ✅ GEBAUT: „Live monitoring"-Toggle + Monitor-Level (`EchoelValueField`) | `AudioInputPickerView.monitoringSection` → `AudioEngine.setInputMonitoring` |
| Fiepen erkannt + unterdrückt | **GANZ seit #595** (2026-08-14): DUCK live (~15 Hz, NUR Mic-Monitor) **+ NOTCH verdrahtet** — `AVAudioUnitEQ`-Band im Monitor-Pfad, Tap→`MonitorTapWindow`→FFT→`ringingBin` im Guard-Tick, Gain über `slewedNotchGainDB` geslewt, ~2 s Hold. Nur AEC (`setVoiceProcessingEnabled`) bleibt NIRGENDS (absichtlich, Council-gated) | `FeedbackGuard.swift`-Header, `AudioEngine.updateFeedbackGuard()` + `setInputMonitoring` |
| Bluetooth optimieren | ✅ Latenz-EHRLICHKEIT gebaut: Hinweis „~150–250 ms … wired/USB für delay-freies Self-Monitoring" wenn Output-Route high-latency | `AudioInputPickerView` `outputIsHighLatency`-Zweig |
| USB-C-Kopfhörer | ✅ Route-Liste mit Latenz-Note pro Route; Refresh bei Route-Wechsel (Kabel rein/raus), solange das Sheet offen ist | `AudioInputManager.available` + `routeChangeNotification`-Subscriber im Sheet |
| USB-Mikro/Interface-Erkennung | **HALB**: erkannt ja (Liste), aber nur SICHTBAR, solange das Sheet offen ist — keine App-weite Reaktion aufs Einstecken | Route-Observer lebt im Sheet-Leaf, nicht app-weit |

**Wichtigste Session-Regel dahinter (gemessen):** `availableInputs` ist unter `.playback`
LEER — die Kategorie wird erst bei einer expliziten Mic-Aktion `.playAndRecord`. Ein
„automatisch bei Einstecken" muss also entweder (a) nur den ROUTE-CHANGE hören (geht auch
unter `.playback`) und eine Einladung zeigen, oder (b) beim Einstecken selbst upgraden —
(b) zieht fremde BT-Audio auf HFP herunter, genau das, was #299 beendet hat. **Entwurf: (a).**

## Die Scheiben (Ralph, je 1 Zyklus, Reihenfolge nach Risiko/Nutzen)

1. ~~**#595 NOTCH-Verdrahtung**~~ — **GEBAUT 2026-08-14** (Council: proceed). Umsetzung wich
   im Detail ab: `AVAudioUnitEQ`-Parametric-Band statt `EchoelBiquadCascade` (Graph-Node,
   kein Render-Code), Engage nur bei `ducking && ringingBin`, Slew ±4 dB/Tick, ~2 s Hold.
   Duck drückt den Pegel, Notch nimmt die Pfeif-Frequenz raus. Geräteprobe offen
   (NEEDS-FOUNDER-VERIFY: Lautsprecher-Monitoring, Fiepen provozieren).
2. **#596 PLUG-IN-EINLADUNG (Auto-Erkennung app-weit)** — app-weiter
   `routeChangeNotification`-Beobachter (Leaf/Controller, kein Root-Read): neues
   EXTERNES Input erscheint → unaufdringliche Zeile im Studio („USB-Interface erkannt —
   Monitoring einschalten?"), Tap öffnet das vorhandene Input-Sheet. KEIN Auto-Arm
   (Konsens-Form #277; und kein stiller Kategorie-Upgrade, s.o.).
3. **#597 HARMONIZER × VOICE** — gemessen zuerst: `EchoelHarmonizer` sitzt im FX-Pfad
   (Audio-Verarbeitung), das Voice-Profil im Synth (Timbre). Zwei ehrliche Formen:
   (a) Body-voice/Poly MIT Voice-Profil durch den vorhandenen Harmonizer = „mein Ton,
   harmonisiert" — vermutlich NUR Verdrahtungs-/Preset-Arbeit; (b) „anderer Voice-Clone"
   = zweites Profil auf einer zweiten Stimme — braucht #593 (Persistenz/Teilen) zuerst.
   Scheibe = (a); (b) nach #593.
4. **#593 PERSISTENZ + TEILEN** — **#593a GEBAUT 2026-08-14** (`970f0bb`, Council: proceed;
   Steward-Review PASS, kein CRITICAL/HIGH): `SynthPatch.voiceProfileTaps/Label/Blend` als
   Einheit, decodeIfPresent, kein Schema-Bump, Apply durch #591a-Staging, Clear strippt die
   Patch-Erinnerung. **#593b (Save-Flow) ERBT VIER STEWARD-BEFUNDE als Checkliste:**
   (1) MEDIUM: die LÄNGEN-Garantie gehört dem Save-Flow — der Decoder akzeptiert 1…63 Taps,
   die die Engine still verweigert (Residual am Decoder-Branch dokumentiert);
   (2) das schlafende `SynthPatch(name:from:)` (:672, null Aufrufer) baut OHNE Voice-Felder —
   naiv als Save-Baustein benutzt verliert es die eingebettete Stimme;
   (3) Label-PFLICHT am Speichern (der Decoder defaultet nur defensiv);
   (4) Ehrlichkeits-Kanten für eine „Voice aktiv"-Anzeige: Embed- und Capture-Herkunft sind
   nach Apply ununterscheidbar, und Blend 0 (aus negativ geklemmt) armiert die Memory bei
   deaktivierter Engine-Stufe.
   **#593b GEBAUT 2026-08-14** (`2475f28` + F1-Fix): Save-as bettet die live Stimme ein,
   Label über `typedArtistName`, Blend 1; **F1 (HIGH, im Review gefunden und gefixt):**
   ein recallter Embed-Patch behält beim Umbenennen sein ORIGINAL-Label (Taps-Vergleich
   VOR der Zuweisung) — sonst Misattribution fremder Stimmen. **#593c GEBAUT 2026-08-14 —
   alle VIER geerbten Befunde in EINER Definition aufgelöst** (`patchCarryingLiveVoice`
   in `EchoelStudioView`, #416: beide Save-Türen rufen sie): (1) F2 Stale-Half → der
   else-Zweig strippt, wenn `appliedVoiceProfile == nil` (Reviewer-verifiziert: der
   Gegen-Fall erreicht den Zweig nicht — `apply(_:)` installiert ein eingebettetes
   Profil immer als das live); (2) F5a Clear-hält-nicht → der Clear-Knopf strippt
   zusätzlich die `currentPatch`-Kopie über ein `@Binding` der Row; (3) F5b
   Recall-No-op → `clearApplied(synth:)` nimmt den Synth als PFLICHT-Parameter (die
   weak-Referenz war nur nach `begin()` gesetzt), die Row reicht ihren
   `@Environment`-Synth; (4) Check-4-Asymmetrie → „Save changes" ruft dieselbe
   Definition und aktualisiert erst die View-Kopie (`currentPatch =`), dann den Store.
   Der Undo-Delete-Save bleibt absichtlich UNANGEREICHERT (stellt einen Snapshot wieder
   her). Wächter: `TheVoiceTravelsWithThePatchTests` Tests 8–10 (Test 8 re-verankert,
   9–10 neu; die `synth?.`-Null-Zählung ist die eine ECHTE Regression gegen den
   Parent, #367). Geräteprobe erweitert: Clear → Regler-Tweak → Save — die Farbe darf
   NICHT zurückkehren.
   **REVIEW-RUNDE 2 (ui-state, 2026-08-14): 4 Fixes bestätigt, 2 tiefere Löcher
   gefunden und im Follow-up-Commit geschlossen — die Wurzelursache war PROXY STATT
   GEDÄCHTNIS.** (F1 HIGH) Der Taps-Gleichheits-Guard brach bei jedem Patch-Wechsel
   unter überlebendem Profil (X recallen → Genre-Default wählen → speichern = X' Stimme
   unter eigenem Namen). Fix: `PolySynthVoice.appliedVoiceProfileLabel/Blend` —
   PROVENANCE-Gedächtnis, gesetzt nur bei AKZEPTIERTEM Embed (`applyVoiceProfile` gibt
   jetzt Bool zurück), genil't bei Capture und Clear; der Helper trägt eingebettete
   Herkunft wörtlich weiter (und lässt eine Basis MIT eigener Hälfte byte-identisch —
   keine 64→32-Trunkierung mehr), nur eine frische Capture wird beim Speichern vom
   Spieler etikettiert. Der Gleichheits-Proxy ist GELÖSCHT und per Null-Zählung
   verboten. (F2) „live-nil = Clear" gilt nur für eine AKZEPTIERTE Hälfte — der
   else-Strip ist jetzt auf `voiceProfileTapFloor` (public, die eine Socket-Definition)
   gegated; eine kurze Fremd-Hälfte bleibt inert-aber-erhalten. (F3) DRITTE Kopie:
   `patchBeforeSoundChange` — Clear strippt den Prompt-Undo-Snapshot über `onClear`.
   (F4) In-place-Ordnung (Anreicherung VOR Store-Call) jetzt gepinnt. (F5) Writer-
   Registry nachgetragen. (F6) `VoiceTimbreProfiler`-Kommentar korrigiert (Engine-Socket
   ist 32, nicht 64; Gleichheits-Behauptung war die falsche-Begründung-Klasse).
   Wächter: Test 8 auf Provenance umgeschrieben, Test 11 neu (30 Needles gesamt,
   Ganz-Datei-Transkription). Geräteprobe NOCH einmal erweitert: Clear → Undo-Pfeil —
   auch DER darf die Farbe nicht zurückbringen.
5. **#598 TÖNEN-WISSEN (Learn)** — s. Rote-Linie-Absatz unten.
6. **#599 IN-KEY-PITCH-CORRECTION (VL3) — GEBAUT 2026-08-14** (Founder-Ask: „optional
   per pitch correction mit Charakter an die Tonart"). Gemessen zuerst:
   `VoicePitchCorrector` (VL1) + `VoiceHarmony` (VL2) lagen als pure, getestete Kerne
   in `Sequencer/` mit NULL Produktions-Aufrufern — der eigene Dateikopf nannte VL3 als
   Plan. Jetzt verdrahtet, alles wiederverwendet: Mic-Tap → `MonitorTapWindow` (mit dem
   #595-Notch GETEILT — `copyLatest` kopiert, zwei Leser legal) → `PitchTracker` (YIN,
   ~15-Hz-Guard-Tick, MainActor) → `VoicePitchCorrector` → `AVAudioUnitTimePitch`
   zwischen `notchEQ` und `monitorMixer` (Graph-Node, kein Render-Code — das
   #595-Muster). OPTIONAL: Default-AUS-Toggle „Tune to key" im Input-Sheet; CHARAKTER:
   „Tune"-Feld (1 = klassischer Hard-Snap, 0 = sanfter Drift) + „Amount". Tonart +
   Kammerton kommen ~1 Hz aus DENSELBEN Defaults, die das Studio schreibt
   (`StudioDefaultKeys.rootIndex/scale` + `SessionContext.a4StorageKey` — #416; ein
   Tonart-Wechsel erreicht die Stimme binnen einer Sekunde, Kammerton-treu 432/440).
   Wächter: `TheVoiceTuneSnapsToTheSessionKeyTests` (E2E auf den Kernen + Joins).
   Geräteprobe offen (NEEDS-FOUNDER-VERIFY): Monitoring an, Tune to key an, schief
   singen — der Monitor zieht in die Tonart; Latenz/CPU der TimePitch-Stufe anhören.
   ~~**VL2→Harmonizer = #599b, nächste Scheibe**~~ — **#599b GEBAUT 2026-08-14**
   (Founder delegierte: „Du entscheidest, optimierst brand-conform" — Council: kein
   Scaler-EQ-Klon [das Instrument komponiert per Konstruktion in der Tonart; ein
   Tonart-EQ wäre Kosmetik], stattdessen die registrierte Tonart-Fähigkeit):
   `DiatonicHarmonyFollower` (Tools/, App-owned, ~10-Hz-Task NUR bei aktivem Toggle)
   liest `EngineBus.latestMusical` (lauteste Note + publizierte Tonart) und schreibt
   diatonische Terz+Quinte über der Lead-Note in `harmonizer.interval1/2` beider
   Chains (#386-Inventar). Tür: FX → Harmonizer → „Follow the key"; die Interval-Rows
   verstecken sich währenddessen (ein Regler, der lügt, ist schlimmer als keiner);
   der AUS-Pfad re-fant die VM-Werte (Follower hält KEINE Baseline — ein mitten im
   Follow recallter Preset restauriert auf SEINE Werte). Kammerton-treu; unbrauchbarer
   Frame → halten statt raten. Wächter: `TheHarmonizerFollowsTheKeyTests` (E2E auf
   der puren Entscheidung + Joins). Geräteprobe: Melodie spielen — die Harmonie bleibt
   auf JEDER Note in der Tonart; ~10-Hz-Intervallwechsel auf gehaltenem Akkord anhören.

## Pre-Release-Sweep 2026-08-14 (3 Leads, vor dem v10.79.391-Bump) — Befunde & Stand

- **C1 BEHOBEN (im Sweep-Commit):** #599 machte den NACHBAR-Wächter rot —
  `TheNotchIsSlewedAndMonitorOnlyTests` pinnte `connect(notchEQ, to: monitorMixer…)`
  auf ==1, der setVoiceTune-Off-Zweig machte 2 daraus. Beide Wächter pinnen dieselbe
  Tatsache jetzt konsistent auf 2; das Rot versteckte sich unter #396 (#445: Abwesenheit
  im Log beweist nichts). **Lehre: §4 gilt für GESCHWISTER-Wächter — nach jedem Edit die
  kürzeste Substring-Needle über ALLE CISmoke-Dateien grepen, nicht nur die eigene.**
- **M1 BEHOBEN:** `voiceTuneEnabled` war ein Latch über Monitoring-Aus hinweg, aber die
  einzige Fläche, die ihn zeigen/klären kann, rendert nur bei laufendem Monitoring —
  die Monitor-Tür im Mixer-Strip hätte einen unsichtbaren Tune re-armiert. Monitoring-OFF
  entwaffnet jetzt (via `setVoiceTune(false)`, der eine Schreiber).
- **M2 ENTSCHIEDEN + GEBAUT (#600, 2026-08-14, PM-Entscheid nach Delegation):**
  Route, nicht Caption — `currentProject()` füllt `patch:` jetzt durch
  `patchCarryingLiveVoice(currentPatch)`, damit Save/Autosave/Live-Colabo dieselbe
  Antwort geben wie beide Patch-Türen (#416; die Caption hätte die #593b-Check-4-
  Asymmetrie beschrieben statt sie zu schließen). Round-Trip verifiziert am Code:
  `open(_:)` → `applyTakeSound(p.patch)` → `synth.apply` wendet die Voice-Hälfte
  MIT Provenance an (PolySynthVoice.swift:594). Live-Colabo teilt die Stimme damit
  MIT Label — das Share-Label-Gesetz, nie anonym. Wächter: `TheVoiceTravelsWith
  ThePatchTests` Test 9 (==2→==3 + neue `patch:`-Nadel, Test umbenannt #374) und
  `TheSavePromiseMatchesTheSaveTests` (Sound-Nadel folgt der neuen Schreibweise).
  Drei Prosa-Stellen im selben Commit mitgezogen (Helper-Doc „drei Türen",
  VoiceCaptureRow „persists exactly two ways", dieser Eintrag).
- **M3 registriert (Geräteprobe):** Ein Routen-Wechsel 44,1↔48 kHz mitten im Monitoring
  verstimmt „Tune to key" um ~147 Cent bis Monitoring recycelt (stale Tap-Rate, #595-F2).
  Route-Change-Re-Arm ist der registrierte Fix, wenn die Probe es zeigt.
- **L3 registriert:** `VoiceCaptureEngine.lastPitchHz` hat null Produktions-Leser
  (nur der Wächter liest es) — schlafend, unschädlich, hier vermerkt, damit der
  nächste Sweep es nicht neu entdeckt.
- **Komplett verifiziert (Lead-Bericht):** Capture-Kette Ende-zu-Ende · Persistenz mit
  allen drei Clear-Kopien · Harmonizer-Join · #599-Verdrahtung · Notch monitor-only ·
  Plug-in-Einladung erreichbar und arm-frei. Geräteprobe-Restposten: Capture WÄHREND
  Monitoring = zwei live Input-Engines gleichzeitig (Tap-Kollisions-Analyse deckt den
  Recorder ab, nicht diesen Fall).

## ⚠️ Tönen & „Hormone" — die Form, in der es shipppt (Body-Science-Präzedenz)

Die SUBSTANZ ist willkommen und hat echte Literatur (Humming↔nasales Stickstoffmonoxid,
langsames Chanten↔HRV/Baroreflex, Gruppensingen↔Oxytocin-Studien). Die FORM ist durch die
harte Produktlinie festgelegt und durch #184 (zwölf Store-Claims) teuer bezahlt: **zitierte
Befunde + Selbstbeobachtung, nie Heil- oder Wirkversprechen.** Konkret: eine „Voice
Science"-Sektion neben Body Science („Studien beobachteten…", mit Quellen, test-guarded
wie `BioScienceInfo`) plus praktische Laut-Anleitungen (Vokale, Summen) als PRAXIS im
Guide — nicht „regt Hormon X an" als App-Aussage. **Founder-Deep-Research bitte in
`inspiration_intake` geben** — dann werden die Quellen daraus zitiert statt aus Modell-
Erinnerung (die Zitate oben sind bis dahin ZU VERIFIZIEREN, nicht copy-fähig).

**NICHT bauen:** Auto-Arm des Mikros beim Einstecken · stiller Session-Upgrade unter
fremdem BT-Audio · Heilungs-/Hormon-Claims in nutzersichtbarer Kopie · AEC (eigene
Entscheidung, `setVoiceProcessingEnabled` ändert den ganzen I/O-Charakter — erst Council).
