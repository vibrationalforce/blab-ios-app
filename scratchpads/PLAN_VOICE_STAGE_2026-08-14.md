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
| Fiepen erkannt + unterdrückt | **HALB**: der DUCK ist live (~15 Hz, duckt NUR den Mic-Monitor, nie die Musik; Status-Punkt „Feedback guard — ducking runaway" in der UI). Die NOTCH ist NICHT verdrahtet (`ringingBin` = null Aufrufer in `Sources/`), AEC (`setVoiceProcessingEnabled`) NIRGENDS | `FeedbackGuard.swift`-Header (selbst korrigiert #298/‑07‑31), `AudioEngine.updateFeedbackGuard()` |
| Bluetooth optimieren | ✅ Latenz-EHRLICHKEIT gebaut: Hinweis „~150–250 ms … wired/USB für delay-freies Self-Monitoring" wenn Output-Route high-latency | `AudioInputPickerView` `outputIsHighLatency`-Zweig |
| USB-C-Kopfhörer | ✅ Route-Liste mit Latenz-Note pro Route; Refresh bei Route-Wechsel (Kabel rein/raus), solange das Sheet offen ist | `AudioInputManager.available` + `routeChangeNotification`-Subscriber im Sheet |
| USB-Mikro/Interface-Erkennung | **HALB**: erkannt ja (Liste), aber nur SICHTBAR, solange das Sheet offen ist — keine App-weite Reaktion aufs Einstecken | Route-Observer lebt im Sheet-Leaf, nicht app-weit |

**Wichtigste Session-Regel dahinter (gemessen):** `availableInputs` ist unter `.playback`
LEER — die Kategorie wird erst bei einer expliziten Mic-Aktion `.playAndRecord`. Ein
„automatisch bei Einstecken" muss also entweder (a) nur den ROUTE-CHANGE hören (geht auch
unter `.playback`) und eine Einladung zeigen, oder (b) beim Einstecken selbst upgraden —
(b) zieht fremde BT-Audio auf HFP herunter, genau das, was #299 beendet hat. **Entwurf: (a).**

## Die Scheiben (Ralph, je 1 Zyklus, Reihenfolge nach Risiko/Nutzen)

1. **#595 NOTCH-Verdrahtung** — `FeedbackGuard.ringingBin` (reiner Kern, getestet, türlos)
   → ein Notch-Biquad im Monitor-Pfad (NUR Monitor, wie der Duck; `EchoelBiquadCascade`
   existiert). Council vorher: berührt den Audio-Graph. Das macht „Fiepen unterdrückt"
   von halb auf ganz — Duck drückt den Pegel, Notch nimmt die Pfeif-Frequenz raus.
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
4. **#593 PERSISTENZ + TEILEN** (aus PLAN_ECHOEL_VOICE, Council-Gate) — Voraussetzung für
   „mit anderem Voice-Clone" und fürs Teilen. `SynthPatch.voiceProfile` via
   `decodeIfPresent` + Pflicht-Label.
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
