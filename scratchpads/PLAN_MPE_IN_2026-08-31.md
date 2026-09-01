# PLAN — MPE **IN**, der Rest der Ausdrucks-Kette (Council + Scheiben)

**Datum:** 2026-08-31 · **Zweig:** `claude/echoelmusic-neustart-auv3-6ri2ek`
**Status:** PLAN. Nichts davon ist gebaut. Scheibe 1 ist die nächste Ralph-Runde.

---

## WARUM DIESE ARBEIT UND NICHT DIE REIHENFOLGE

Der Stunden-Cron trägt eine REIHENFOLGE (5→1→2→3→4) aus **v10.79.183**. Gemessen am
heutigen Baum ist **kein einziger Punkt davon noch baubar**, und das gehört
aufgeschrieben, statt still übergangen zu werden:

| # | Punkt | Stand, gemessen |
|---|---|---|
| 5 | Visuals grau (B9) | **ausgeliefert**, wartet auf Founder-Ohr/Auge am Gerät |
| 1 | Automation in der Spur | **gegen die ratifizierte Produktdefinition** — Timeline/Arrangement/Clips sind ausdrücklich CUT; `ClipView` (807dc0d) und `ArrangeTimelineView` (eb58e7a) gelöscht, `TimelineAutomationRow` mit #473. Bauen hieße das Workstation-Halb zurückholen, das der Founder abgerissen hat |
| 2 | Bio-Modulation live sichtbar | **FERTIG UND ERREICHBAR**: `BioModLiveView(modulator:)` + `AlwaysOnBioView()` stehen in `EchoelFXView`s `Form` (Zeilen 506/507), und `EchoelFXView` hängt an `showAllFX`, dessen Setter ein echter Knopf im `effectsPanel` ist (`EchoelStudioView:7772`). Kein Bau nötig |
| 3 | Externe AUv3 sichtbar | **Target 2026-07-24 entfernt** (#121 Slice 2). Es gibt nichts, was sichtbar werden könnte |
| 4 | Leisten-Verteilung Timeline/Spuren | starb mit der Timeline, siehe 1 |

⭐ **Die Anweisung wird NICHT umgeschrieben** (#885: „eine Sitzung, die die Anweisung ihres
Auftraggebers umschreibt, weil sie sie für veraltet hält, ist ein größerer Defekt als eine
veraltete Anweisung"). Sie wird gemessen, das Ergebnis berichtet, und die Arbeit wird aus der
Produktdefinition abgeleitet statt aus einer Liste, deren Gegenstände es nicht mehr gibt.

---

## WAS STATTDESSEN — UND WARUM ES ZUM PRODUKT GEHÖRT

**MPE IN.** Die Identitätszeile von `CLAUDE.md` hat „MPE" aus dem I/O-Satz gestrichen, und die
Begründung ist heute exakt halb: **MPE OUT ist real und schaltbar (#713), MPE IN nicht.**

Gemessen (nicht abgeleitet), heute:

- `MIDIEventParse.event(word0:word1:)` dekodiert **vier** Dinge — Note On, Note Off, CC,
  Pitch Bend. **Channel Pressure (0xD0 / 0xD) hat keinen Fall** und fällt in
  `default: return nil`; `MIDIInEvent` hat keinen Fall, der es tragen könnte.
- `BioReactiveSynthVoice.apply(controller:)` läuft für `.slide`, `.airCC` und
  `.channelPressure` in **ein einziges `break`** und liest `event.channel` nirgends.
- Zonen-Erkennung (RPN 6,6) und Master-gegen-Member-Kanal kommen nirgends vor.
- ⛔ **DIESE ZEILE STAND FALSCH IN DER ERSTEN FASSUNG DIESES PLANS, gefangen beim Nachmessen
  vor dem Commit — und es ist eine NAMENSKOLLISION, dieselbe Gattung, die diese Sitzung heute
  schon fünfmal gekostet hat.** Sie behauptete „`PolySynthVoice` verbraucht `.slide` und
  `.expression` sehr wohl, die Kette ist ungleich weit gebaut". `PolySynthVoice.drainNoteCommands`
  schaltet auf `cmd.kind` einer EIGENEN, internen Notenbefehl-Warteschlange, die auf dem
  Audio-Thread geleert wird — mit einem gleichnamigen `.slide`, das mit `ControllerEvent.slide`
  vom Bus nichts zu tun hat. Gemessen (`git grep -n "ControllerEvent\b" -- Sources`, ohne
  `EngineBus.swift`): der Bus-Typ erreicht genau ZWEI Dateien — `MIDIBusPublisher` (Erzeuger)
  und `BioReactiveSynthVoice` (Verbraucher). **`BioReactiveSynthVoice.apply(controller:)` ist
  der EINZIGE Verbraucher von `ControllerEvent` in `Sources/`**, und er verwirft drei von fünf
  Arten. Der wahre Befund ist damit SCHÄRFER als der falsche: die Kette ist nicht ungleich weit
  gebaut, sie hat genau einen Verbraucher mit genau einem `break`. **Gesetz: ein Enum-Fall
  gleichen Namens in zwei unverwandten Typen ist keine Fähigkeit — dem TYP folgen, nicht dem
  Wort.**

Das ist **Instrumenten-Arbeit** im Sinne der Produktdefinition: es geht um den Klang, der
JETZT entsteht, nicht um das Anordnen von Material über die Zeit. Ein Spieler mit einem
MPE-Controller (Seaboard, LinnStrument, Osmose) drückt heute fester und nichts passiert.

---

## COUNCIL

- **Architect:** Scheibe 1 ist auf `MIDIEventParse` + das Ereignis-Enum begrenzt. Kein neuer
  Kopplungspfad, `EngineBus` bleibt die Wirbelsäule.
- **DSP Purist:** Parsen läuft nicht auf dem Audio-Thread. Der VERBRAUCH schon — jede Scheibe,
  die eine Stimme anfasst, geht durch den `audio-thread-reviewer`, ohne Ausnahme.
- **Vision-Keeper:** ⛔ **Aus keiner dieser Scheiben darf „Echoel unterstützt MPE" werden.**
  Erst nach Zonen-Erkennung ist das wahr. Bis dahin heißt es, was es ist: „Channel Pressure
  wird empfangen und bewegt den Klang". Store-Text, Website und `ContentPipeline/CLAIMS.md`
  bleiben unangetastet, bis Scheibe 4 steht.
- **Shipper:** Scheibe 1 ist eine Datei plus Tests. Passt in eine Runde.
- **Skeptic:** ⚠️ **Die stärkste Einrede, und sie steuert die Reihenfolge.** Scheibe 1 allein
  erzeugt ein geparstes Ereignis, das **niemand verbraucht** — genau die Kategorie „gebaut,
  verdrahtet, wirkungslos", die dieses Repo an sechs Stellen als Defekt führt. **Antwort:
  Scheibe 1 und 2 gehören in EINEN Zyklus oder gar nicht.** Ein Parser ohne Verbraucher wird
  nicht ausgeliefert.
- **User-Advocate:** Der Gewinn ist erst mit Scheibe 2 spürbar. Deshalb ist 1+2 die Einheit.

**Gate: PROCEED mit 1+2 als EINER Scheibe.** 3 und 4 danach, jede mit eigenem Council.

---

## SCHEIBEN

### S1+S2 (eine Runde) — Channel Pressure wird empfangen UND gehört
- `MIDIEventParse`: Fall für 0xD0 (MIDI 1.0, 2 Byte) und 0xD (UMP), beide Protokolle, mit
  Kanal. Normalisierung auf 0…1 wie bei CC.
- `MIDIInEvent` / `ControllerEvent`: der Fall existiert bereits als `.channelPressure` —
  **prüfen, nicht neu erfinden**.
- `BioReactiveSynthVoice.apply(controller:)`: `.channelPressure` bewegt die Hüllkurven-
  Amplitude der gehaltenen Note. NaN/inf am Rand abfangen (die `bent.isFinite`-Form eine
  Zeile höher ist die Vorlage).
- **Test-first**, rein: Parse-Tests für beide Protokolle + ein Verbraucher-Test über die
  vorhandene `applyControllerForTests`-Naht.
- **Pflicht-Reviewer: `audio-thread-reviewer`** (die Stimme wird angefasst).
- ⚠️ **Wächter mitziehen, und er ist BREITER als sein Name:**
  `TheMPEInputHasNoZonesTests` pinnt nicht nur „die drei Dimensionen landen in EINEM
  `break`" (`testTheThreeExpressionDimensionsAreDiscarded`), sondern auch
  `testTheVoiceReadsNoMemberChannel`, `testThePerformerPathIsMonophonic` und
  `testTheRoutingScreenOffersNoMPEInput` — und seine Prosa nennt die Zahl DREI an mindestens
  fünf weiteren Stellen. **Wer S1+S2 baut, zieht ihn im SELBEN Commit mit** (#456), und zwar
  auf „zwei", nicht auf „keine": Slide und Air bleiben verworfen, der Kanal wird weiterhin
  nicht gelesen, der Pfad bleibt monophon. **Ein Wächter, der korrekte Arbeit verbietet, ist
  selbst der Defekt (#364)** — aber die drei Ansprüche, die NACH S1+S2 weiterhin wahr sind,
  bleiben stehen und werden nicht mit abgeräumt.

### S3 — die zweite Dimension: Slide / CC 74 bewegt die Klangfarbe · ✅ AUSGELIEFERT (#942)
`MIDIBusPublisher` bildete CC 74 schon auf `.slide` ab — der Erzeuger stand, nur der einzige
Verbraucher verwarf es. Council gehalten, weil „Timbre" beim Bio-Synth eine
Design-Entscheidung ist und keine Verdrahtung. **Ergebnis: `EchoelDDSP.renderCutoffScale`,
nicht `brightness`.** Die Messung, die es entschieden hat, und warum sie nicht offensichtlich
war:
- `brightness` ist ZWEIMAL falsch. `applyBioReactive` schreibt es aus `bioBaseBrightness` plus
  Kohärenz/HR/HRV-Abweichungen bei JEDEM Bio-Frame neu — ein Slide wäre in ~1 s gelöscht (die
  Bio-Rate ist ~1 Hz, nicht 10). Und `brightness` trägt `didSet { updateSpectralEnvelope() }`,
  eine Schleife über alle Harmonischen: ein CC-74-Strom liefe die Neuberechnung hunderte Male
  pro Sekunde. Dieselbe Falle, die #939 für Press vermieden hat.
- `renderCutoffScale` ist ein öffentlicher Pro-SAMPLE-Multiplikator auf den Cutoff, Default
  1.0 (bit-identisch), gelesen im Render innerhalb des Ein-Pol-Glides (0,01/Sample ≈ 2 ms),
  ohne `didSet` und damit ohne Neuberechnungskosten.
- Tiefe: `slideDepth = 3.0` (×4 = zwei Oktaven Cutoff), benannte Konstante,
  **NEEDS-FOUNDER-VERIFY** — Handgriff: MPE-Controller anschließen, auf einer gehaltenen Note
  den Finger senkrecht bewegen; klingt der Sweep musikalisch oder zu weit/zu eng?
- Nebenbefund, im selben Commit repariert: `renderCutoffScale` hatte ZWEI Schreiber und nur
  einer war saniert. `clampExpressionScale` war `private` in `EchoelPolyDDSP`, während sein
  eigener Doc-Satz „One clamp for every writer" behauptete; es ist auf `EchoelDDSP` gezogen
  (EINE Definition, #416), nicht kopiert.
- Der Wächter heißt seit diesem Commit `TheMPEInputHasNoZonesTests` — der alte Name
  (`TheMPEDimensionsReachNoVoiceTests`) wurde durch S2+S3 unwahr.

### S4 — die eigentliche MPE-Hälfte: Zonen · OFFEN, und jetzt die EINZIGE offene Hälfte
RPN 6,6, Master- gegen Member-Kanal, Per-Note-Bend-Bereich. **Erst danach** darf irgendeine
nutzersichtbare Fläche das Wort MPE für die EINGABE benutzen.

---

## WAS DIESER PLAN NICHT BEHAUPTET

- Kein Gerät wurde angefasst. Es gibt keinen MPE-Controller in dieser Umgebung; jede Scheibe
  endet mit einem `NEEDS-FOUNDER-VERIFY`, das den konkreten Handgriff nennt.
- Kein lokaler Compiler. „grün" heißt hier immer CI, nie eine lokale Prüfung.
- Die Reihenfolge S1..S4 ist eine Empfehlung, keine Zusage. Jede Scheibe darf am eigenen
  Council scheitern.
