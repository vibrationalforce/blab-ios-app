# PLAN — Warm Restart: die bio-gepacte Session (2026-07-05)

Founder-Entscheidungen (protokolliert in decisions.csv):
warmer Neustart · Fokus NUR auf das, was Menschen gesundheitlich wirklich hilft ·
Umwelt/Ort als Session-Journal · Push · ehrliche Positionierung bestätigt ("Ja passt").

## 0 · Forschungs-Fundament (Deep Research 2026-07-05, 22/25 adversarial bestätigt)

DAS TRAGENDE (wir bauen NUR hierauf):
- Closed-Loop-Pacing (Ton/Licht-Ziel aus gemessenem Herz/Atem) → messbare kurzfristige
  parasympathische Beruhigung. DER wissenschaftlich ehrliche Kern.
- Persönliche Resonanz-Atmung 4,5–7/min (Lehrer-Protokoll; ResonanceFinder existiert).
- Sicherheit hart: Licht ≤3 Blitze/s, NIE 4–70 Hz, Helligkeitshub begrenzt, kein rotes
  Flimmern. FDA general-wellness + App Store: Selbstbeobachtung, keine Diagnose/Therapie.

DAS VERWORFENE (nie behaupten, nie drauf bauen):
- "Brainwave-Entrainment wirkt" (binaural widerlegt; AV-Überlegenheit widerlegt;
  SSVEP≠Entrainment). rPPG/HRV können kein Alpha messen. "Multidimensional" = Ästhetik.

## 1 · Architektur (super-senior Apple-Standard: klein, rein, testbar, sicher)

GEBAUT + CI-GRÜN (alle 4 Kerne, je pure Core + Tests):
  EntrainmentEngine   flash-sicherer Stimulations-Plan (Envelope als Invariante, getestet 0.01–500 Hz)
  SessionGuide        Guide-Gesetz: natürliches Tempo → Resonanz, nie hoch, Rückzug bei Nicht-Folgen
  SessionClock        Latenzausgleich: Phase bei Wahrnehmungszeitpunkt (audio outputLatency · displayLink)
  SessionEngine       @MainActor Orchestrator: 10 Hz Bus-Poll → Mirrors → launch-stiller
                      220-Hz-Atem-Ton (Render-Block audio-thread-reviewed: CLEAN)

GEERBT (bleibt, ist der Moat): rPPG-Trust-Gate + Selbstheilung · Rausch-Triade (protected)
· EngineBus/SPSC · AudioEngine-Resilienz · BreathPacer/ResonanceFinder · MetalBioView.

PRINZIPIEN (jede Zeile daran messen):
1. Pure Core zuerst (Enum/Struct, keine Actor-Abhängigkeit) → XCTest → dann Wiring.
2. Sicherheits-Envelope ist Typ-Invariante (EntrainmentPlan IST sicher), nie Renderer-Checkliste.
3. Cue lokal + latenz-kompensiert (Realtime-Gefühl), Sensor nur fürs LANGSAME Ziel.
4. Render: nur Float-atomare Mirrors; UI: 10-Hz-Reads nur in Leaf-Views; Sheets: nie anhängen.
5. xcode-compile-check ist das entscheidende Gate (Linux sieht den AVFoundation-Pfad nicht).

## 2 · Bau-Sequenz (Ralph Wiggum, je 1 Zyklus, CI-grün)

JETZT:
 5. SessionView — DER eine Screen: Start → Puls-Lock (BioStrip-Leaf) → Atem-Ton +
    Tempo-Anzeige ("6,0 Atemzüge/min") + Stop. Ein neuer Sheet-SLOT? NEIN — ersetzt
    einen bestehenden Slot oder eigene Route in WorkspaceView (Sheet-Kette NIE wachsen).
 6. Flimmer-sicheres Licht — MetalBioView-Uniform aus SessionEngine.visualBrightness
    (Leaf-Read!), targetTimestamp-kompensiert. Bio-safety-reviewer drüber.
 7. Session-Abschluss-Karte — Dauer · Puls-Verlauf · Kohärenz (ehrliche Zahlen, keine Scores).
DANN (Founder-Gates wo markiert):
 8. Umwelt/Ort-Journal — WeatherKit + reduced-accuracy CoreLocation NUR als Stempel am
    Session-Ende ("wo war ich, wie war das Wetter"). GATE: Info.plist + Portal-Capability
    ZUERST registrieren (CloudKit-Lektion!).
 9. Lokale Push — tägliche Session-Erinnerung, opt-in, keine Server (APNs-Remote bleibt aus).
10. Resonanz-Onboarding — ResonanceFinder-Protokoll als geführte Erst-Session (persönliche RF).
11. HealthKit-Write — Mindful Minutes am Session-Ende (ehrlich, systemkonform).
SPÄTER: Haptik als dritte Modalität (CoreHaptics, evidenznah: haptisches Pacing) ·
Session-Historie/Trends · Watch-Begleiter · Musik-Modus (der alte Instrument-Teil) als
zweite Tür. Echoel Pro IAP erst wenn die Session den Founder-Test besteht.

## 3 · Marketing (gesundheits-ehrlich; PIPELINE, vor Publikation the-council + bio-safety)

POSITIONIERUNG: "Dein Atem führt. Echoel folgt." — Selbstregulation über Resonanz-Atmung,
Ton + Licht atmen mit dem Körper, alles gemessen, nichts behauptet. Kategorie bleibt
Music/Lifestyle, NICHT Health&Fitness (Review-Risiko + Brand). KEIN "heilt/behandelt/
Gehirnwellen". Der Grenzen-Zettel (rPPG mag keine Bewegung etc.) bleibt Differenzierer.
CLAIMS-WHITELIST: "guides your breathing toward your personal resonance pace" ·
"tone and light follow your measured pulse and breath" · "for self-observation".
BLACKLIST: treat/cure/therapy/anxiety/brainwave/entrainment-efficacy/"proven to".
LAUNCH: unverändert Audiobus → Elektronauts → Reddit → CDM → Show HN (Sequenz im
MASTERPLAN §4) — aber ERST wenn die Session den Founder auf dem Gerät überzeugt.
Der 15-s-Preview ist der Produkt-Test: Finger drauf → Lock → Ton+Licht atmen → Ende-Karte.

## 4 · Definition of Done (pro Zyklus)
pure Core getestet · beide CI-Gates grün · Render-/Concurrency-Review wo Audio/UI berührt ·
kein neuer Sheet-Slot · keine neuen Deps · Selbstbeobachtungs-Sprache · SESSION_LOG aktuell.
