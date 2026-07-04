# ECHOEL MASTER PLAN — 2026-07 (Deep Audit II + Deep Research + Marketing)

Founder-Auftrag (2026-07-04): "Wetter- und Standortdaten könnten auch die Komposition
beeinflussen. Pushbenachrichtigungen und Mail? Für In-App-Purchases? Deep Audit + Deep
Research + Marketing-Brainstorming + Echoel Master Plan."

STATUS: Gerüst + gesicherte Fakten; Agent-Befunde (Repo-Audit Env/IAP/Push · Marketing)
werden eingearbeitet, sobald sie landen. Ehrlichkeits-Regel gilt: geplant ≠ shipping.

---

## 0 · WO ECHOEL HEUTE STEHT (verifiziert, 2026-07-04 abends)

SHIPPING (CI-grün, TestFlight): bio-reaktives Instrument (Kamera-rPPG mit Trust-Gate/
Selbstheilung, BLE, HealthKit) · generative Komposition (23 Genres, in-key, Mehr-Takt-
Arrangement) · Poly-Synth + Sub + Drums (Hüllkurve korrigiert, Pitch- + Pegel-Drift,
subtile Bio-Modulation um den Patch, Raum-Floor) · EINE mitlaufende Tempo-Anzeige
(4 Dezimalstellen, lockbar) · N-Takt-MIDI-Export mit Tonart/Taktart · WAV-Export ·
MP4-Visual-Clips · Immersive Visuals (10 Looks, adaptiv) · OSC/ADM-OSC/Art-Net/sACN ·
MIDI/MPE · Presets/Projekte.
NICHT shipping (nie behaupten): RTMP-Streaming, Video-Capture/-Schnitt, Multitrack-
Recorder, Remote-Push, IAP, Wetter/Standort.

OFFENE SOUND/LOOP-ROADMAP (aus Deep Audit I, PLAN_SOUND_AND_LOOP_QUALITY.md):
B4/B5 Genre-Tempo+Drums live · B1–B3 Loop-Form/Motiv/Kadenz · A2/A4 Nyquist-Filter +
Filter-EG · A5/A6 Synth-Drum-Realismus · C6/C7 WAV Takt-Trim/Downbeat-Align · PPQ 480 ·
Makro-Artikulation (Power/Soft/Breathy/Chest).

## 1 · UMWELT ALS QUELLE (Wetter + Standort → Komposition)

VISION-FIT: JA — Echoel ist "Physical Computing": der Körper ist die primäre Quelle,
die UMWELT (Wetter, Tageszeit, Ort) ist die zweite physikalische Realität. Kein Wellness-
Reframe nötig: Wetter ist messbare Physik (hPa, °C, Lux, Niederschlag).
GESCHICHTE: WeatherProvider/CircadianClock existierten, waren aber NIE verdrahtet und
wurden 2026-06-19 als toter Code entfernt. Regel diesmal: NUR gebaut, wenn im selben
Zyklus hörbar VERDRAHTET (Quelle → Komposition), sonst gar nicht.

GESICHERTE FAKTEN (Research 2026-07-04):
- WeatherKit: iOS 16+ (Floor 18 ✓), braucht Entitlement `com.apple.developer.weatherkit`
  + Developer-Portal-Freischaltung; 500.000 Calls/Monat frei pro Team (wir: ~1/Stunde,
  trivial); Swift-API mit async/await; Attribution ( Weather + Legal-Link) NUR wenn
  Wetterdaten im UI ANGEZEIGT werden → kleine Attributionszeile im Panel, fertig.
- Location: CoreLocation "reduced accuracy" reicht völlig (Wetter ist Stadt-genau) —
  privacy-first: approximate, on-device, kein eigener Server, keine Speicherung.
- CLAUDE.md-Bau-Regeln: #if canImport(WeatherKit) + @available; Info.plist-Änderung
  (Location-Usage-String) NUR nach Founder-Freigabe (Regel: Info.plist fragen).

REPO-AUDIT-BEFUND (2026-07-04): Der alte WeatherProvider (entfernt in cf21ff3) hatte
NIE echtes WeatherKit — der Fetch war ein auskommentierter Stub, geliefert wurde nur
ein Tageszeit-Sinus-Fallback. Es gibt also keinen "Restore"-Shortcut; aber die
WeatherSnapshot-Form (temperature/condition/wind/humidity, normalisiert 0–1) ist ein
bewährtes Muster zum Wiederverwenden. CoreLocation wird heute NIRGENDS benutzt —
das ist eine komplett neue Permission-Oberfläche.

MINIMAL-DESIGN (verifiziert gegen die echte Architektur):
1. Core/EnvironmentContextProvider.swift: @MainActor @Observable, CoreLocation mit
   kCLLocationAccuracyReduced (approximate!) + WeatherKit-Fetch ~alle 10 min →
   normalisierter WeatherSnapshot. #if canImport(WeatherKit/CoreLocation).
2. Verdrahtung = EIN Blend an der EINEN Input-Stelle: in generate() (EchoelStudioView
   :2215) bei aktivem Opt-in-Toggle mood.darkness/tension/liveliness begrenzt biasen
   (±0.15) + optional Scale-Vorschlag (Sturm→Moll). Pure testbare Funktion
   `tinted(mood, by: snapshot)`. KEIN Bus-Umbau, KEIN ModulationEngine-Umbau.
3. Später (nur wenn Visuals/Licht es wollen): latestEnvironment auf dem Bus nach dem
   latestMusical-Muster + env.weather-Port im SignalRouter.
FRIKTION (Founder-Gates): Info.plist braucht NSLocationWhenInUseUsageDescription
(existiert nicht); Entitlements brauchen WeatherKit — und WICHTIG: die Capability MUSS
ZUERST im Developer-Portal an der App-ID registriert werden, sonst blockiert die
Provisionierung den TestFlight-Upload (exakt das passierte mit CloudKit — deshalb ist
dessen Entitlement heute auskommentiert). Ehrliches Privacy-Framing: "Apple-Dienst,
ungefährer Standort, kein Drittserver, kein Konto" — nicht "völlig offline".
Aufwand: ~2 Zyklen (Provider · Blend+UI+Attribution).

## 2 · MONETARISIERUNG (IAP)

GESICHERTE FAKTEN:
- Musiker-Community ist dokumentiert subscription-avers (Loopy-Pro-Forum u. a.);
  respektierte iOS-Instrumente (Moog, Korg, Loopy Pro) = Einmalkauf/Unlock.
- Apple 2026: volle Preistransparenz vor Kauf; bereits gekaufte Funktionalität darf
  nie wieder weggenommen werden (bindet: was einmal frei ist, bleibt frei).
REPO-AUDIT-BEFUND (Überraschung): `Core/EchoelStore.swift` EXISTIERT BEREITS — ein
kompletter, schlafender StoreKit-2-Manager (@MainActor @Observable, purchase/restore/
Transaction.currentEntitlements/updates-Listener), in EchoelmusicApp verdrahtet und
beim Start geladen — aber von NULL Views konsumiert, kein Gate, kein Paywall, keine
Tests. Er trägt ABO-IDs (monthly 4,99 / yearly 39,99) — das widerspricht der
Instrument-Positionierung ("kein Abo") und sollte auf den Einmalkauf umgestellt werden.

EMPFEHLUNG (Marketing-Brainstorm + Audit einig):
- Modell: EIN non-consumable "Echoel Pro" (com.echoelmusic.app.pro) statt Abo. Store-
  Änderung ist WINZIG: neue Produkt-ID + isPro aus currentEntitlements; Klassenform
  bleibt exakt. Kern-Instrument bleibt frei & vollwertig; Pro gated ERWEITERUNGEN.
- Gate-Stellen (verifiziert): exportMIDI() · LoopExporter-Render · optional User-Patch-
  Limit in PatchStore.save — `guard store.isPro else { showPaywall }`. NIEMALS gaten:
  Bio-Messung, Klang-Erzeugung (CLEAR-SOFTWARE Regel 4), Sicherheit/Accessibility.
- WARNUNG (render-safety): Paywall-Präsentation MUSS einen bestehenden Sheet-Slot in
  EchoelStudioView wiederverwenden oder im Export-Flow-Sheet leben — NIE ein neues
  .sheet anhängen (Metadaten-Limit → Black-Screen-Klasse).
GATE: Council + Founder für Preis & Schnitt; ASC-Produktanlage + .storekit-Testconfig.
Aufwand: ~2 Zyklen.

## 3 · PUSH + MAIL

REPO-BEFUND (Audit 2026-07-04):
- IN-APP: NULL Push-Code. Kein `registerForRemoteNotifications`, kein UNUserNotificationCenter-
  Flow, kein Token-Upload, kein `aps-environment`-Entitlement. Der APNs-Key des Founders
  (Key-ID LBY89HTN2C) hat heute KEINEN Empfänger.
- CI: `.github/workflows/send-push.yml` war ein toter Sender mit FALSCHEN Behauptungen
  ("Device tokens are stored in CloudKit public database" — es gibt keinerlei Token-
  Registrierung) und MARKEN-VERSTOSS (Kategorien `ECHOEL_WELLNESS`/`ECHOEL_BIO_ALERT`,
  Deep-Link `/wellness`). → GELÖSCHT 2026-07-04 (reversibel via Git-History); neu bauen
  erst, wenn ein echtes Server-Feature Push rechtfertigt — dann ohne Wellness-Framing.

GESICHERTE FAKTEN:
- Apple 4.5.4: Marketing-Push NUR mit explizitem In-App-Opt-in + Opt-out-Weg; Push darf
  nie Funktionsvoraussetzung sein. Remote-Push braucht einen SERVER (haben wir nicht;
  APNs-Key des Founders liegt bereit, .p8 NIE ins Repo).
- TestFlight-Benachrichtigungen: macht Apple automatisch, brauchen NICHTS von uns.
- IAP braucht KEINEN Push und KEINE Mail (StoreKit wickelt Kauf/Restore ab; Belege
  verschickt Apple).
- Mail-Marketing: DSGVO (Founder = DE): Double-Opt-in, Impressum, Abmeldelink —
  sinnvoll erst mit echtem Newsletter-Inhalt; Infrastruktur extern (z. B. Buttondown/
  Mailchimp), NIE in-app gesammelt ohne Consent-Flow.
EMPFEHLUNG: JETZT: nichts bauen. Push erst mit einem echten Server-Feature (z. B. Live
Colabo). Mail erst mit Website-Newsletter (docs/-Seite bekommt ein Signup-Feld, extern
gehostet, Double-Opt-in) — Marketing-Agent liefert den Rahmen.

## 4 · MARKETING (Brainstorm-Ergebnis 2026-07-04, guardrail-geprüft — VOR Publikation
##     durch the-council + vision-gate + bio-safety-reviewer)

POSITIONIERUNG (das Fundament, kostet nichts):
- P1 (Kategorie-Gründer, der Keeper): "Echoel ist das erste bio-reaktive Performance-
  Instrument. Herzschlag, Atem, Bewegung sind echte Kontrollsignale — gemessen, nicht
  behauptet — für Synthese, MIDI, Spatial-Audio-Objekte und Licht über offene Standards."
- P2 (Producer-Nutzen): "Echoel macht aus deinem Puls in-key MIDI. Tonart + Genre wählen,
  Finger auf die Kamera, gestempelte tempo-feste Melodie direkt in Ableton/Logic/FL."
- One-Liner DE: "Spiel das Instrument, das du schon bist." / "Dein Herzschlag. In deiner
  Tonart. In deiner DAW."
- BEACHHEAD: Electronic Producer/Beatmaker (einzige Audience, die der Shipping-Stand
  END-TO-END bedient: generate → hören → exportieren → im Track nutzen; größte zahlende
  iOS-Musik-Population). Installations-/AV-Szene (OSC/ADM-OSC/Art-Net) bleibt die
  strategische ERZÄHLUNG (Presse/CDM), nicht der Beachhead.

ASO:
- Titel: "Echoel: Bio-Reactive Synth" (26 Z.) · Untertitel EN: "Your heartbeat plays
  the synth" (30) / DE: "Dein Herzschlag spielt Synth" (28)
- Keywords (100 Z., ohne Titel-Wiederholung): biofeedback,hrv,pulse,generative,
  sequencer,drum,machine,midi,mpe,osc,beat,maker,ppg
- Kategorie: Music (NIE Health & Fitness — falsches Framing + Review-Risiko)
- Screenshot-Story: 1) Finger auf Kamera, live PPG-Lock — "Your pulse. Measured.
  Playing." 2) Generate from Body (Tonart+Genre → Melodie) 3) DAW-Handoff mit echtem
  Stempel-Dateinamen → Ableton. Dann Sequencer/FX/Roll + 1 Pro-I/O-Shot.
- App-Preview: 15 s, ein Take, ungeschnitten: Finger drauf → Lock → Sound → Export.

LAUNCH-SEQUENZ (Solo-Founder-realistisch):
1) TestFlight-Public-Link + Build-in-Public-Thread im Audiobus-Forum (dichteste
   iOS-Musik-Community) → erste 50 Evangelisten
2) Elektronauts (Ehrlichkeit über rPPG-Grenzen = Glaubwürdigkeits-Hook)
3) r/synthesizers + r/iosmusicproduction (30-s-Video Puls→Melodie→Ableton)
4) CDM / Peter Kirn Direkt-Pitch (Body-as-Controller + offene Standards = sein Beat)
5) Show HN (Engineering-Hook: 100 % Swift, eine Dependency, lock-free DSP)
6) KVR + Product Hunt am App-Store-Launch-Tag
7) Creator-Seeding (8 Archetypen: iOS-YouTuber, TD/VJ, DAWless/Eurorack-MPE,
   Ambient-Producer [nie "calming"], Lighting-Designer, Educator, QS-Reviewer,
   Spatial-Operator) — je mit Free-Code + EHRLICHKEITS-BLATT über Grenzen (rPPG-
   Bewegungsempfindlichkeit, Watch-Latenz) — das Limits-Blatt ist selbst Differenzierer
8) DE-Schiene: Amazona, Bonedo, Sequencer.de, SynthAnatomy; Superbooth nächster Zyklus

MONETARISIERUNGS-MESSAGING:
- Kernsatz: "Einmal kaufen. Es ist ein Instrument, kein Abo."
- Preis-Anker (iOS-Instrumente, einmalig): Minimoog 14,99 · Moog Model 15 29,99 ·
  Korg Gadget ~39,99 · AUM 23,99 · Drambo 19,99 · Loopy Pro ~29,99
- Empfehlung: Free + "Echoel Pro" 14,99–19,99 € einmalig. Free = voller Magic-Moment
  (Puls-Lock, Generate, einige Genres/Patches); Pro = alle 23 Genres, volle Patch-
  Bibliothek, FX-Charaktere, MIDI-Export, AUv3, Pro-I/O. NIE die Bio-Messung gaten.
  Kein Launch-Rabatt-Theater — stabiler Preis signalisiert Instrument.

GROWTH-LOOPS (ehrlich, produkt-nah, gerankt):
1) SMF-Meta "Made with Echoel — echoelmusic.com" im MIDI-Export (1 Datei, trivial)
2) MP4-Visual-Clips: SHIPPING (VisualRecorder, benannte Dateien) — KORREKTUR zum
   Agent-Stand: existiert bereits! → Clean-Fullscreen ohne HUD als Share-Qualität
   (render-safety-gated), Insta/TikTok-Kanal ist damit offen
3) Share-Sheet-Vorschlagstext: "Cm · 124 BPM · A440 · generated from my pulse in
   Echoel" (löschbar, faktisch)
4) AUv3-Name/-Icon crisp (jeder AUM/Logic-Screenshot = Impression)
5) NIEMALS: Audio-Watermarks, Zwangs-Attribution, share-to-unlock. Instrument-Würde.

PUSH/MAIL (bewusst minimal):
- Push: KEINER in v10 — kein ehrlicher wiederkehrender Anlass; jede gesparte
  Permission-Abfrage ist Onboarding-Qualität.
- Mail: EIN Feld auf echoelmusic.com — "Get the launch email — one message when it
  ships, nothing else." Double-Opt-in (DSGVO), EU-Provider (Buttondown/Brevo), exakt
  3 Mails bis auf Weiteres: Beta offen · Launch-Tag · erstes großes Update. Der
  Launch-Tag-Burst (24–48 h) ist der einzige ASO-Hebel, den ein Solo-Founder voll
  kontrolliert → die Liste ist DAS Pre-Launch-Asset.

TOP-3 WENN NUR DREI DINGE: (1) Positionierung P1/P2 + 3-Screenshot-Story fixieren,
(2) TestFlight-Public + Audiobus-Loop JETZT öffnen, (3) Double-Opt-in-Launch-Mail-Feld
auf die Website.

## 5 · SEQUENZIERUNG (Vorschlag, je 1 Zyklus, CI-grün, Ralph Wiggum)

JETZT (Sound zu Ende — das Fundament von allem):
 1. B4/B5 Genre-Tempo + Genre-Drums live (Genre-Identität)
 2. B1–B3 Loop-Form/Motiv/Kadenz ("Sinn ab Takt 1" vollenden)
 3. A2/A4 Nyquist-Filter + Filter-EG ("Air" + klassischer Sweep)
DANN (neue Achsen, jede hinter Council-Gate):
 4. Umwelt-Quelle (2 Zyklen, opt-in, privacy-first)
 5. IAP "Echoel Pro" (2 Zyklen + ASC-Produktanlage)
 6. Marketing-Execution (Website/ASO/Launch — PIPELINE, nie Sources/)
SPÄTER: A5/A6 Synth-Drums · C6/C7 WAV-Align · Makro-Artikulation · P3 Video · P4 Broadcast.

## 7 · QUERSCHNITT: GEFUNDENE UNGENAUIGKEITEN (Aufräum-Liste, Stand 2026-07-04)

Beim Deep Audit für diesen Plan gefundene Widersprüche Doku ↔ Code (Founder-Direktive
"zu viele Ungenauigkeiten"):
1. ✅ CLAUDE.md "KEY TESTS (15 files)" listete 11 NICHT existierende Testdateien
   (BusinessTests, MIDITests, RecordingTests, …) — Realität: 140 Testdateien.
   → korrigiert 2026-07-04.
2. ✅ EchoelStore (StoreKit-2-Abo-Gerüst, in EchoelmusicApp verdrahtet, NULL Konsumenten)
   war NIRGENDS dokumentiert — Überraschungsfund. → in CLAUDE.md "Absent" vermerkt;
   Abo-IDs widersprechen der Instrument-Positionierung (Abschnitt 2: ein Pro-Unlock).
3. ✅ send-push.yml: falsche CloudKit-Behauptung + ECHOEL_WELLNESS (Markenverstoß),
   ohne jeden In-App-Empfänger. → gelöscht (Abschnitt 3).
4. Offen: Konsistenz-Vollaudit (Docs/Website/FEATURE_MATRIX/CLAUDE.md vs Code) läuft
   als Agent; Ergebnisse werden hier bzw. direkt als Fixes nachgetragen.
Regel für alle Achsen dieses Plans: KEINE neuen Dependencies, KEINE neuen Top-Level-
Verzeichnisse, jede Achse hinter Council-Gate, Render-Safety-Regeln gelten (Paywall/
Umwelt-UI = bestehenden Sheet-Slot wiederverwenden, nie Kette verlängern).

## 6 · ENTSCHEIDUNGEN FÜR DEN FOUNDER (bewusst offen)
- Umwelt-Quelle bauen? (Entitlement + Location-Permission + Info.plist = deine Freigabe)
- IAP: Modell "ein Pro-Unlock" ok? Preisvorstellung? Was ist dir heilig-frei?
- Newsletter auf echoelmusic.com (extern, Double-Opt-in) starten?
