# PLAN — Visual-Sektion: EINE Einheit (2026-09-06, #1030 ff.)

**Founder-Ask 1 (wörtlich):** „Hetzte die visual Sektion insgesamt überarbeiten und
korrigieren. Die physikalisch korrekte Darstellung der Farbtöne, das Ton Gitter, das Menü
kompakter. … Insgesamt soll das User Erlebnis im fordergrund stehen kompakter und
übersichtlicher gestalten mit einer Einheit zum steuern aktuell gibt es fullscreen Mode das
soll aber alles zu einem Ding zusammen gefasst werden"

**Founder-Ask 2 (wörtlich):** „Ultraplan Ultracode ultrausablitiy
ultraaudiovisionbiofeedbackcomposition"

## Woher dieser Plan kommt

54-Agenten-Audit (read-only) → **17 bestätigte Defekte** (`scratchpads/AUDIT_VISUAL_2026-09-06.md`,
#1029) → PM-Entscheidungen **D1–D10** → vier Planer mit vier Linsen (Usability · One-Unit ·
Composition · Ship-Risk) → zwei Richter. **Der dritte Richter und die Synthese fielen ins
Session-Limit; diese Synthese ist von Hand gemacht.** Die vier Plan-Objekte und die zwei
Richter-Urteile liegen als JSON im Sitzungs-Scratchpad; ihre Substanz steht unten.

**Richter-Ergebnis:** Founder-Intent/Usability → Plan 3 (7) > Plan 1 (6) > Plan 2 = Plan 4 (5).
Ingenieurs-Risiko/Shipbarkeit → Plan 4 (7) > Plan 2 (6) > Plan 3 (5) > Plan 1 (4).
**Kein Plan gewinnt beide.** Diese Synthese nimmt Plan 4s Topologie (Verschmelzung in vier
Commits) und Risiko-Register, Plan 1/3s Founder-Reihenfolge (sichtbares zuerst), Plan 2s
Wächter-Hygiene an der Leiste, Plan 3s Beamer-Messung.

## Die sechs Korrekturen, die BEIDE Richter an den Planern fanden

Sie sind hier Gesetz, nicht Empfehlung — jede ist ein gemessener Fehler in mindestens einem Plan:

1. **Verstecken der Chrome ist KEIN Tipp auf die Leinwand.** Die Leinwand des Fensters IST
   `TouchInstrumentView(` (`FloatingVisualWindow.swift:798`, gemessen: die einzige
   Konstruktionsstelle in `Sources/`; die Datei hat **null** `onTapGesture`). Ein Tipp ist eine
   NOTE. Portiert wird der Leisten-Knopf, den der Cover schon hat (`EchoelStudioView.swift:1550`),
   **nicht** der Leinwand-Tipp (`:1536`). Ein dauerhaftes 44-pt-Wiederzeigen bleibt sichtbar.
2. **Die Wächter-Wiederverankerung ist die VEREINIGUNG dreier Listen**, nicht die eines Plans:
   Plan 2 S5 ∪ Plan 3 S7 ∪ Plan 4 S10 — plus `AutoModeStartsOffAndOwnsNoTempo…:540`
   (`autoAttuned: autoMode` kommt NUR im gelöschten Cover vor) und
   `TheLogoHoldsItsPlaceTests:150/:222-223` (`private let handleHeight` als Regex-Anker).
   Auto-Merge wartet auf kein Gate (#683) — ein roter Wächter steht sofort auf `main`.
3. **D3 heißt LÖSCHEN, nicht Umgehen.** Der `.onAppear`-Wiederauftrag des Presets fliegt raus.
   „no-op bei leerem String" reicht nicht: auf dem Gerät des Founders IST Vapor gewählt, dort
   stirbt Hue 0 sonst beim nächsten Start — genau der Nutzer, der den Defekt gemeldet hat.
4. **Ein beschrifteter „Physical"-Knopf gehört dazu.** `EchoelStudioView.swift:5702` löscht nur
   die Preset-ID; Hue 0.82 bleibt persistiert. Ohne den Knopf gibt es keinen benannten Rückweg.
5. **`SpectralColor.displayComponents` (Core/SpectralColor.swift:287-295) muss wirklich
   angefasst werden** (0.22-Weiß-Lift + `pow(1/2.2)`), sonst sprechen Zelle und Wolke weiter
   zwei Sprachen — D5(f) war in zwei Plänen als erledigt behauptet und nirgends gemacht.
6. **`updateKeepAwake` darf nicht verwaisen.** Sein einziger Aufrufer auf einem
   Fullscreen-Übergang ist `.onChange(of: showVisual)` (`:1446`) — beim Löschen des Covers
   braucht der Größen-Key einen eigenen `onChange`.

## Gestrichen (bewusst NICHT im Epos)

- **OKLab-Mittelung im Shader** (Plan 3 S12): außerhalb D1–D10, ungemessene GPU-Kosten, und der
  schlimmste Fehlermodus des Epos — Shader kompilieren zur LAUFZEIT (`makeLibrary(source:)`),
  ein MSL-Tippfehler ist ein schwarzes Bild bei grünem CI.
- **`ChromeFit` um Felder erweitern**, die nach D7 nie mehr abgeworfen werden (Plan 3 S6,
  Plan 4 S6): drei Pins bewegen für null Verhalten.
- **`visualLookStrip` in die Schublade** (Plan 4 S10): die Leiste trägt den Look-Regler schon
  (`FloatingVisualWindow.swift:1053`) — zwei Regler auf einem Schirm ist genau das „nicht eine
  Einheit", das der Ask streicht.

## Die Reihenfolge (13 Scheiben)

Der Founder startet KALT in das Fullscreen des Fensters (`WorkspaceView.swift:333`). Also:
zuerst das, was er in Sekunde 1 sieht, dann die Verschmelzung, dann Pixel/Gitter, dann die
Kompaktheit. Die Verschmelzung liegt bewusst FRÜH (Commit 3–5): zwei vollständige Fullscreens
gleichzeitig sind der Risiko-Posten, den Richter 2 an Plan 1 und 3 bestraft hat.

| # | Scheibe | Dateien | Verifikation |
|---|---|---|---|
| **S1** | **Doppel-Aufnahme sperren (Stopgap).** `.disabled(visualRecorder.isRecording)` + Hinweis am „Full screen"-Knopf. Schließt den HIGH-Befund (zwei aufnehmende `MetalBioView` auf einen Recorder), bevor irgendein Merge-Commit fährt. Stirbt mit dem Cover. | 1 | compile |
| **S2** | **Erster Start = physikalische Farbe (D3).** `visualSaturation` 1.05 → 1.0, kein Default-Preset, `.onAppear`-Wiederauftrag GELÖSCHT, beschrifteter „Physical"-Knopf. Vier zustimmende Pins ziehen mit. **Der Founder sieht es sofort — ein Tipp auf „Physical".** FLAGGED REVERSIBEL (sein „Bunter" 2026-08-13 = eine Konstante). | 5 | compile + V5 |
| **S3** | **Fullscreen-Leiste umbricht statt abzuwerfen (D7a).** Früh-Return NACH dem Degenerate-Width-Guard (`FloatingVisualLayout.swift:326`), damit `ChromeBudgetFitsTests:112/:122` grün bleiben. `handleHeight` behält seinen Namen. Beschriftetes „Studio", Look-Regler, Gitter, Still, Donut überleben auf 375 pt. | 3 | compile + V4 |
| **S4** | **Die vier Cover-Eigentümer ins Fenster portieren.** Donut-Zweig als nicht-aufnehmendes Blatt · `StillShutterButton` · Chrome-Verstecken **als Leisten-Umschalter** (Korrektur 1) · Keep-Awake mit eigenem `onChange` (Korrektur 6). | 4 | compile |
| **S5** | **Cover zurückziehen — EINE Fläche.** „Full screen" wird ein Schreiben von `visual.floating.size`; Kette **14 → 13** (die erste Schrumpfung überhaupt). Vollständige Wächter-Liste (Korrektur 2), `#if canImport(MetalKit)`-Paar geprüft, CLAUDE.md-Kehraus **netto-negativ** (heute 149 062 B von 150 000 B — `wc -c CLAUDE.md`). | ~18 | compile, roter Wächter je Nadel benannt |
| **S6** | **Physikalisch am Pixel (D4).** 0.35-Luminanz-Boden wird verhältniswahrend (keine Kanal-Klemme → keine Hue-Drehung von D#/E/F um +15…+19°); „filmische" Affine wird hue-wahrend; `echoelHue` bei 0 übersprungen; Swift↔MSL-Paritäts-Anspruch in CISmoke. NICHT angefasst: Warmton, Kohärenz-Lift, Glitter (founder-zitiert, Geschmack). | 4 | compile + V4 |
| **S7** | **Die Wolke landet auf der berührten Zelle (D5a).** `SpectralColor.notePosition` wird key/gitter-bewusst; Grundton links. **Auch für Composer/MIDI-Noten** (`bus?.freshMusical`, `MetalBioView.swift:910`), nicht nur für Berührungen — sonst sitzt die Wolke der selbst erzeugten Aufnahme weiter falsch. | 5 | compile |
| **S8** | **b-Tonarten schreiben sich mit ♭ (D5b).** `NoteNaming` key-bewusst; Gitter, Picker und Titel stimmen überein. | 5 | compile |
| **S9** | **Tür für das Gitter + Lesbarkeit (D5c/d/e).** „Fretboard / Note grid" bekommt eine Tür im Field-Panel, wird im Fullscreen NIE abgeworfen, Beschriftungen verstecken sich unter einer reinen Breitenschwelle, ganzes Gitter unter dem Abwurfpunkt. Default bleibt AUS (FLAGGED REVERSIBEL). | 3 | compile + V3 |
| **S10** | **EINE Steuer-Definition (D2).** Look · Preset · Energie/Fine-tune · Farbe existieren EINMAL als geteilte Zeilenbauer, montiert im Field-Panel und als Fenster-Schublade. Keine 560/360-Deckel (#1027-Gesetz). Zwei Wirt-Listen ziehen mit (`GlitterCannotBecomeAFlash:114-117`, `TheFinishDialsReachTheShader:145-147`). | ~8 | compile |
| **S11** | **Kompakt und ehrlich (D8).** Höchstens EINE Bildunterschrift pro Gruppenkopf; der Farb-Satz wird WAHR umgeschrieben (Purpurlinien-Interpolation, „Default" nur ohne Preset); drei Chip-Streifen werden umbrechende Reihen bzw. Picker; Blitz-Sicherheits-Satz und Anspruchs-Sätze bleiben. | 3 | compile |
| **S12** | **Eine Farbsprache (D5f · D6).** Der 0.22-Lift in `displayComponents` fällt (Korrektur 5), Gitter == Feld auf 1e-9 gepinnt; Donuts falten wie das Feld; inerte Donut-Zeilen verstecken sich nur bei `spectralDonuts && !ExternalStageBridge.shared.isConnected` (der Beamer rendert sie live — `TheDetailCaption` Anspruch 4 wird zur Bedingung im Code, nicht zum Rücknahmegrund). | 5 | compile + V3 |
| **S13** | **Eine Hue/Saturation-Quelle für Fenster UND Beamer (D7b).** `ExternalDisplayScene` erbt kein `@Environment` (`:121-122`) — der Weg ist `ExternalStageBridge`. Danach zeigt der Projektor dasselbe wettergemischte Bild wie das Telefon, und die Tonart reist mit (Wolken stimmen überein). | 5 | compile + Gerät |

## Gesetze, die JEDE Scheibe binden (D9)

- Freeze-Gesetz: kein ~10-Hz-`@Observable`-Lesen in einem menü-tragenden Rumpf oder Vorfahren.
- Ein `MetalBioView` pro Datei; versteckt = `Color.clear` + inert.
- Die Präsentations-Kette wächst **nie**; sie schrumpft in S5 auf 13.
- `EchoelValueField` für Zahlen, `Picker` für benannte Werte; Uncodixfy (Radius ≤16, kein Glühen,
  nur Deckkraft-Übergänge); Blitz ≤3 Hz.
- Wächter werden im SELBEN Commit wiederverankert (#456), nie gelöscht, wenn sie Gesetz sind (#364).
- ≤3 Dateien je Scheibe, wo möglich — eine größere Scheibe sagt, warum.
- Jede Scheibe nennt: compile-verifiziert (CI) vs. nur am Gerät.

## Offen, nur am Gerät (NEEDS-FOUNDER-VERIFY nach S5 bzw. S13)

- **V1** Fullscreen-Aufnahme: genau ein Renderer, sauberes MP4.
- **V2** Fullscreen hält den Bildschirm wach.
- **V3** Gitter-Lesbarkeit bei klein/mittel, nachdem der Lift weg ist.
- **V4** Das Aussehen des verschmolzenen Fullscreens (Rand, Leisten-Umbruch).
- **V5** Sättigung 1.0 gegen 1.05 — ein Wort des Founders kippt es zurück.
