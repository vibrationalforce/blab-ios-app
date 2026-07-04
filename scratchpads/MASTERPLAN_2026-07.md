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

DESIGN-SKIZZE (Minimal, dem Bio-Muster folgend — Details nach Repo-Audit-Agent):
EnvironmentContext (@MainActor @Observable, poll ~1×/15 min):
  → condition (clear/rain/storm/snow/fog), tempC, pressureTrend, isDay/goldenHour
  → mappt auf BioComposer.Input-Erweiterung (moodTint / scale-Bias / detail-Dichte):
    Regen → weichere Attacks, mehr Raum; Sturm/Druckabfall → dunklerer Modus, mehr
    Spannung; klarer Morgen → heller, offener; Nacht → tiefer, langsamer.
  → OPT-IN Toggle "Umwelt färbt die Musik" im Composition-Panel (aus = exakt heutiges
    Verhalten), Anzeige der Quelle ehrlich ("Rain · 14° · Hamburg approx.").
GATE: Council vor Implementierung (Entitlement + Info.plist + neues Permission-Prompt =
Founder-Entscheidung). Aufwand: ~2 Zyklen (Provider+Bus · Mapping+UI).

## 2 · MONETARISIERUNG (IAP)

GESICHERTE FAKTEN:
- Musiker-Community ist dokumentiert subscription-avers (Loopy-Pro-Forum u. a.);
  respektierte iOS-Instrumente (Moog, Korg, Loopy Pro) = Einmalkauf/Unlock.
- Apple 2026: volle Preistransparenz vor Kauf; bereits gekaufte Funktionalität darf
  nie wieder weggenommen werden (bindet: was einmal frei ist, bleibt frei).
EMPFEHLUNG (vorbehaltlich Marketing-Agent + Founder):
- Modell: EIN non-consumable "Echoel Pro" Unlock (StoreKit 2, Transaction.
  currentEntitlements) statt Abo. Kern-Instrument bleibt frei & vollwertig (Instrument-
  Glaubwürdigkeit + Viralität der Exporte), Pro gated ERWEITERUNGEN, nie den Kern.
- Kandidaten fürs Gating (Repo-Audit-Agent verifiziert): erweiterte Patch-/Look-
  Bibliothek, zusätzliche Genres/FX-Charaktere, erweiterte Export-Optionen (Stems,
  ACID-WAV), Community-Slots. NIEMALS gaten: Bio-Kern, Basis-Export (teilen = Marketing),
  Sicherheit/Accessibility.
GATE: Council + Founder für Preis & Schnitt. Aufwand: ~2 Zyklen (Store-Kern+Tests ·
Gates+Paywall-UI) + App-Store-Connect-Produktanlage (Founder).

## 3 · PUSH + MAIL

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

## 6 · ENTSCHEIDUNGEN FÜR DEN FOUNDER (bewusst offen)
- Umwelt-Quelle bauen? (Entitlement + Location-Permission + Info.plist = deine Freigabe)
- IAP: Modell "ein Pro-Unlock" ok? Preisvorstellung? Was ist dir heilig-frei?
- Newsletter auf echoelmusic.com (extern, Double-Opt-in) starten?
