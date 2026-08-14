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
5. **#598 TÖNEN-WISSEN (Learn)** — s. Rote-Linie-Absatz unten.

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
