# Founder Device Session — was NUR am Gerät entschieden werden kann

**Stand 2026-08-25 (#816).** Diese Datei ist die **Urteils-Hälfte** der Geräte-Sitzung.
Die code-verankerten Bitten stehen NICHT hier, sondern im Werkzeug:

```
python3 scripts/founder-verify.py
```

Es sammelt jede `NEEDS-FOUNDER-VERIFY`-Zeile aus `Sources/`, `Tests/` und `CLAUDE.md` und
gruppiert sie nach Bereich. **`scratchpads/` durchsucht es ABSICHTLICH nicht** (sein eigener
Kopf sagt: „scratchpads sind Sitzungsprosa, keine Bitten"). Genau daran ist diese Datei
kaputtgegangen: sie war eine ZWEITE Liste, die kein Werkzeug sah und kein Wächter prüfte —
und deshalb konnte sie zwei Monate lang um Prüfungen bitten, die niemand mehr ausführen kann.
Der ⛔-Abschnitt unten führt jede einzelne mit Messung auf.

**Was hier steht:** nur Punkte, die kein Marker tragen kann, weil sie an keiner Codezeile
hängen — Screenshots, Ein-Feld-Entscheide, Klang- und Gefühls-Urteile, offene Fragen an Dich.

**Was in DIESEM Build zu drücken ist,** steht in der Build-Notiz `.deploy/release`.
Diese Datei wiederholt sie nicht (#416: eine Entscheidung, ein Zuhause).

---

## 1 · Der eine Handgriff — er blockiert die ganze Vokal-Kette

Steht wörtlich in `.deploy/release` (heute v10.79.418) und wird hier nur VERORTET, nicht
wiederholt: Mix-Panel → „Voice - your microphone" → „Choose input…" → **Live monitoring**.

**Warum das ein Blocker ist und keine Fleißaufgabe:** `decisions.csv:398` staffelt die
Vokal-Kette als V0 → V1a → V1b. V0 IST dieser Handgriff. Solange nicht feststeht, ob der
Monitorpfad am Gerät überhaupt anläuft, würde jede weitere Stufe (Harmonizer und Granular
auf die STIMME statt auf die Musik) auf einen unbewiesenen Pfad gebaut.

---

## 2 · Kern-Klangpfad — die Punkte, die weiterhin ausführbar sind

⚠️ **Diese Liste stand schon in der Fassung von 2026-07-16 und wäre bei der #816-Aufräumung
beinahe mit-gestrichen worden.** Der erste Entwurf schob sie „in die `NEEDS-FOUNDER-VERIFY`-
Marker" — ohne sie dorthin zu schreiben. Gemessen: das Werkzeug deckt keinen dieser Punkte ab.
**Eine Streichung mit dem Zusatz „gehört woanders hin" ist erst dann eine, wenn der Umzug
stattgefunden hat.** Bis Marker existieren, ist das hier ihr Zuhause.

- [ ] **multiRoll** (Flag registriert, also AN): zwei dichte MIDI-Spuren gleichzeitig hörbar?
      Jede mit eigenem Timbre? CPU < 30 %, Speicher im Rahmen (Xcode-Gauge beim Spielen)?
- [ ] **voiceKindRouting** — **Bass-Spur wummert** fühlbaren Sub, und **bei A≠440 in Tune**
      (einmal mit A = 432 gegenprüfen). Poly-Spuren unverändert.
- [ ] **Kein hängender Ton** beim Instrumentwechsel mitten im Take.
- [ ] **Live-Same-Region-Wechsel:** Instrument der Primary-Spur MITTEN im Take ändern, ohne eine
      Regionsgrenze zu kreuzen — bindet der Roll die Stimme erst an der nächsten Grenze neu?
      Falls das stört, ist der Fix ein gezieltes Re-Fire, kein Umbau.
- [ ] **Launch bleibt still** bis zum ersten Arm (keine Bio-Stimme beim Start).
- **Rollback für jedes Flag:** `FeatureFlags.set(.<flag>, false)` — eine Zeile.
- ⛔ **Der Punkt „Drums-Spur trommelt" ist hier ersatzlos weg**, siehe ⛔-Tabelle: es gibt keine
      Schlagzeug-Stimme mehr.

---

## 3 · Die zwei Ship-Gate-Checks, die nur ein Mensch schließen kann

Von den fünf Checks des Gates „Instrument-Complete v1" (CLAUDE.md) sind **Kontrolle** und
**Modi** code-belegt und zu. Offen sind genau die zwei sensorischen:

- [ ] **Klang** — klingen die kuratierten Genres professionell? Bleibt die Identität eines
      Genres über eine Session erhalten (kein Zusammenlaufen)? Die strukturelle Hälfte ist
      im Repo gepinnt (`GenreFamilyDistinctnessTests`) — dass es GUT klingt, beweist kein Test.
- [ ] **Stabilität** — sauberer Start, kein Schwarzbild, kein Menü-Freeze während Biofeedback.
- [ ] (halb) **Ausgabe** — die Code-Hälfte ist seit #748 zu; offen bleibt das Urteil, ob das
      Visual auf dem Gerät wirklich **kontemplativ** wirkt.

---

## 4 · Screenshots — nur Du, am echten Gerät

- [ ] 6.9" Set (1320×2868), 8 Shots laut `docs/dev/APP_STORE_LISTING_v1.md` — die ersten drei:
      (1) Instrument spielt + Bio-Strip, (2) Immersive Visual, (3) „Generate from Body".
      Captions sind fertig getextet (keyword-tragend) — verbatim übernehmen.
- [ ] 6.5" Set falls bequem.

---

## 5 · Ein-Feld-Entscheide (kurz bestätigen, kein Gerät nötig)

- [ ] Privacy-Label = **„Data Not Collected"** (on-device, kein Server/Analytics/Account) — OK?
- [ ] Kategorie Music + Health & Fitness — OK?
- [ ] Preis Free, kein IAP in v1.0 — OK (Echoel Live = v1.1)?

---

## 6 · Offene Frage an Dich

- [ ] **Voice clone — ja oder nein?** Aus Deiner Liste vom 2026-08-20 ist das der einzige
      Punkt, der eine Richtungsentscheidung braucht und keine Prüfung.

---

## ⛔ Was gestrichen ist — und warum, gemessen am 2026-08-25

Die erste Fassung dieser Datei (2026-07-16) bündelte „ALLE geräte-gebundenen Punkte in EINE
Sitzung". Vier ihrer sieben Abschnitte baten danach um Prüfungen an Oberflächen, die es nicht
mehr gibt. **Das ist die teuerste Sorte veralteter Prosa in diesem Projekt: Geräte-Zeit ist die
knappste Ressource, und ein Posten, der auf ein entferntes Bedienelement zeigt, kostet eine
Probe, die nichts entscheiden kann** (dieselbe Lehre wie #525, nur auf Dokument-Ebene).

| Gestrichener Posten | Messung heute |
|---|---|
| **Piano-Roll-Editing** (6 Primitive, Velocity-Lane, Pin-Frage) | `grep -c "struct PianoRollView" Sources/Echoelmusic/Studio/PianoRollView.swift` → **0**. Der Editor ist mit #475 gelöscht, die Tür schon 2026-07-26 auf Founder-Wunsch („Pianoroll soll raus"). Keines der sechs Primitive ist ausführbar. |
| **Drums-Spur trommelt** (Slice-7-Gate, `.drums`-Bus-Frage) | Es gibt keine Schlagzeug-Stimme mehr: `DrumSynthVoice`, `LaneDrumKitVoice` und `DrumNoteMap` sind mit #166/#167 als Dateien gelöscht. Es kann kein Drum-Klang entstehen. Das Flag `voiceKindRouting` existiert weiter — der Rest des Gates (Bass, Poly, Stuck-Note) ist als Bitte in den `NEEDS-FOUNDER-VERIFY`-Markern zu führen, nicht hier. |
| **`laneAUInstruments`-Flag prüfen** | `git grep -l laneAUInstruments -- Sources Tests | wc -l` → **0**. Das Flag existiert nicht. |
| **AUv3 im Fremd-Host** (AUM/GarageBand) | Das AUv3-Target ist am 2026-07-24 entfernt (`project.yml` sagt es selbst). Zusätzlich: die Listing-Zeile, die dieser Test verteidigen sollte, steht nicht mehr in `fastlane/metadata/` — `grep -rn "AUv3\|AUM\|GarageBand" fastlane/metadata/ | wc -l` → **0** (#184). |
| **Warp-Hörtest im Audio-Clip-Editor** | Es gibt keine Clip-Editor-Tür: `git grep -ln "clipEditor\|ClipEditorView\|AudioClipEditor" -- Sources | wc -l` → **0**. Die Clip-/Arrangement-Fläche ging mit #121 Slice 4. Die Stretch-Kerne (`StretchPlan`, `AudioClipPlayer`) leben weiter, sind aber unerreichbar. |
| **BLE-Gurt-Begründung** | Die PRÜFUNG bleibt gültig und gehört zu den `NEEDS-FOUNDER-VERIFY`-Markern (CLAUDE.md: „Gerät-Verify wartet auf Gurt-Eintreffen"). Gestrichen ist nur ihre BEGRÜNDUNG: die Listing-Zeile „Polar, Wahoo, Garmin" steht nicht mehr in `fastlane/metadata/`. |
| **„352 geräte-unverifizierte Commits"** | Eine Zahl vom 2026-07-16 — ein Datum, keine Tatsache. Ersatzlos gestrichen statt fortgeschrieben (dieselbe Regel wie in `.claude/rules/context.md` §2). |
| **Sheet-Chain: „12×.sheet + 2×.fullScreenCover auf 4360 Zeilen"** | Die Datei hat heute 11 749 Zeilen; die verbindliche Zahl der Kette steht an genau einer Stelle, im Präsentations-Absatz von CLAUDE.md. Hier zu wiederholen war #416. Die SACHLICHE Entscheidung bleibt: die Konsolidierung ist geräte-gepaart, nicht blind-autonom. |

**Wächter:** `Tests/CISmoke/TheDeviceChecklistOnlyAsksWhatExistsTests.swift`. Er prüft nur die
Ankreuz-Zeilen (`- [ ]`), nie die Prosa — ein negativer Scan über die ganze Datei träfe genau
diese ⛔-Tabelle, die die gestrichenen Namen absichtlich zitiert (#491). Und er verbietet die
Rückkehr keiner dieser Flächen (#364): kommt eine zurück, wird er rot und nennt diese Tabelle
als die Prosa, die dann im selben Commit mitzuziehen ist.
