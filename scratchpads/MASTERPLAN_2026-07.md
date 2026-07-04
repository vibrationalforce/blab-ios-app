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

## 4 · MARKETING (Agent-Befund folgt)

Guardrails fix: Science-first Instrument, keine Wellness/Esoterik, nur Shipping-Claims.
[PLATZHALTER: Positionierung · Beachhead-Audience · ASO · Launch-Sequenz · Creator-
Seeding · Preis-Anker · Growth-Loops (Export-Artefakte) — aus Marketing-Agent]

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
