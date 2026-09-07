---
name: doctor
description: Check whether the instruments that MEASURE this repo are telling the truth — masked CI gates, stale commands, doorless surfaces, drifted CLAUDE.md numbers. Use when a green check feels unearned, before trusting "gates green" as evidence that a test actually ran, or after deleting a feature (a removal orphans doors). NOT a code audit and NOT a status report — `/scan`, `/review` and `/deep-dive` look inside the code, `baustellen` tracks progress; this looks only at the layer that reports ON the code.
---

# Doctor — sind die Messinstrumente ehrlich?

**Das Gesetz dieser Skill: ein grünes Häkchen ist kein Beweis, dass etwas gelaufen ist.**

Sie existiert wegen eines bezahlten Fehlers. Am 2026-07-28 baute die Testsuite
(`Tests/EchoelmusicTests`) 14 Stunden lang nicht — und meldete durchgehend „success", weil `continue-on-error` in
`full-tests.yml` auf dem **Build**-Schritt sitzt. Die Zusammenfassung im selben Log druckte
`- build-for-testing: failure`. Niemand las sie. Zwei Commits (#182, #198) behaupteten in
dieser Zeit, ihre neuen Tests seien „grün verifiziert". Sie waren nie ausgeführt worden.

⛔ **HIER STANDEN DREI ZAHLEN FÜR EINE SUITE — „313 Dateien, `CLAUDE.md` sagt 305,
`full-tests.yml` sagt 294" — und sie sind GELÖSCHT statt nachgeführt (#1052, #818).** Der
Befund, den sie belegen sollten (dieselbe Suite hat je nach Quelle eine andere Größe), ist
weiterhin echt; die Zahlen selbst waren es 2026-09-07 nur noch zur Hälfte: `CLAUDE.md` nennt
**gar keine** mehr, sondern den Befehl — dort ist genau diese Lehre schon gezogen worden. Übrig
sind ZWEI Quellen, nicht drei. Und die 313 stand als Gegenwartsform in einem Absatz über 2026-07,
was sie wie eine Messung von heute las. **Das ist Sektion B in eigener Sache: beschreibt unser
eigenes Kommando noch dieses Repo?** Re-derivieren, nicht abschreiben:

```bash
git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l   # die Suite
grep -n 'suite' .github/workflows/full-tests.yml         # was der Workflow BEHAUPTET (#208, founder-gated)
```

Jede Prüfung hier ist eine, die einen echten, bereits bezahlten Fehler dieses Repos gefangen
hätte. Keine ist erfunden.

## Abgrenzung — was diese Skill NICHT ist

| Werkzeug | Fragt |
|---|---|
| `/scan`, `/deep-dive`, `/review`, `/full-repo-audit` | Ist der **Code** gut? Stubs, TODOs, Audio-Thread, Coverage. |
| `baustellen` | Ist die **Arbeit** abgeschlossen? Board, Verify-Weg, Slice-Fortschritt. |
| **`doctor`** | Sagt das **Messgerät** die Wahrheit? Gates, Werkzeuge, Türen, Zahlen. |

Wenn die Frage „ist dieser Code richtig?" lautet, ist das hier das falsche Werkzeug.

## Ablauf

```bash
python3 scripts/doctor.py --section A  # nur die Gates (unter 1 s)
python3 scripts/doctor.py --section C  # Türen — LANGSAM, siehe unten
python3 scripts/doctor.py --quiet      # alles, nur Befunde — Timeout setzen, siehe unten
```

⛔ **Hier stand „alles, ~10 s“, und das war 2026-09-02 eine abgelaufene Zahl, die den Lauf
KILLTE:** der Gesamtlauf riss den 2-Minuten-Standard-Timeout der Bash-Werkzeuge, und ein
Werkzeug, das im Timeout stirbt, druckt kein Häkchen und keinen Befund — es ist stumm, genau der
Zustand, vor dem der Abschnitt „Wann laufen lassen“ warnt. Gemessen mit `time`, Sektion für
Sektion, auf 370 Quelldateien: A 0,2 s · B 8,5 s · **C 72–81 s** · D 0,1 s. Sektion C war die
Erreichbarkeits-Suche als Views × Dateien Regex-Aufrufe (dazu die transitive Runde aus #947).
⭐ **Im nächsten Zyklus umgebaut:** ein Index-Durchlauf über alle Datei-Rümpfe (jeder Bezeichner
vor `(`/`{`, mit denselben Lookbehinds), **C 72 s → 4 s, Befundliste vor/nach dem Umbau per
`diff` identisch, Selbsttests grün.** Die Zahl hier NICHT nachführen (#818) — `time` danebenschreiben;
wenn der Gesamtlauf wieder über den Timeout wächst, ist das ein Sektion-D-Befund über dieses Werkzeug.

**Drei Exit-Codes, und der dritte ist der wichtigste.** 0 = kein CRITICAL. 1 = mindestens
einer. **2 = INSTRUMENT UNAVAILABLE** — das Skript konnte gar nicht schauen (git schlug fehl,
etwa `fatal: detected dubious ownership` im Container). Es gibt in diesem Fall bewusst KEIN
grünes Ergebnis zurück: eine erste Fassung fing den git-Fehler ab, lieferte leere Listen und
druckte für jede Sektion ein Häkchen. Das ist dieselbe Lüge wie ein maskiertes Gate, nur im
Diagnosewerkzeug selbst. Wer Exit 2 sieht, hat KEINE Aussage über das Repo.

Das Skript ist read-only, ohne Abhängigkeiten, ohne Netz, ohne Build. Es entscheidet nichts —
es legt Belege vor.

**Danach kommt der Teil, den das Skript nicht kann.** Jeder Befund ist eine Frage, keine
Diagnose. Die vier Sektionen und was DU dann tun musst:

### A — GATES: bedeutet grün, dass es lief?
Prüft **drei** Wege, auf denen ein Build-Fehler nichts rot färben kann — Schritt-`continue-on-error`,
**Job**-`continue-on-error` (maskiert mehr und liegt auf einer anderen Einrückung) und den
Fall, dass der Exit-Status den Runner nie erreicht (`|| true`, oder eine Pipe ohne
`set -o pipefail`/`${PIPESTATUS[0]}`, so dass der Status des LETZTEN Befehls zählt). Dazu:
Test-Bundles, die nicht die Verzeichnisse bauen, in denen die Tests liegen, und
`-only-testing:`-Filter auf nicht existierende Suiten.

**Reihenfolge der Reparatur ist nicht beliebig:** erst muss der eigene Exit-Status des
Schritts ehrlich sein (`|| true` weg, Pipe abgesichert), dann kann ein Wächter-Schritt auf
`steps.<id>.outcome` prüfen — und der braucht ein `id:`. Ein Wächter über einem `|| true`
liest für immer Erfolg. Genau deshalb steht die Reparatur pro Zeile im Befund und nicht
pauschal.

**Deine Aufgabe:** CI-Konfiguration ist in diesem Repo **founder-gated**. Berichten, nicht
editieren. Trage den Befund in die Task-Liste und in das Status-Delta — und benutze bis zur
Freigabe die Log-Zeile statt der Conclusion:
```
gh-Log der Full Test Suite → "- build-for-testing:" / "- test-without-building:"
```

**Und die Gegenrichtung, seit 2026-08-07 belegt: ein rotes Gate kann über die SCHULD lügen,
nicht nur ein grünes über den Lauf.** `** TEST BUILD FAILED **` liest sich wie „dein Commit
kompiliert nicht" und ist manchmal Infrastruktur. Der Diskriminator ist eine einzige Frage
an den Job-Log:

```
nennt IRGENDEINE `error:`-Zeile eine Datei unter Sources/ oder Tests/ ?
```

Null Treffer → nicht dein Commit. Gemessen an `998af71` (Lauf 31186349705): 4 `error:`-Zeilen,
**0** mit einer Repo-Datei, alle vier gegen `Xcode_26.2.app/…/SDKs/…` bzw.
`DerivedData/ModuleCache.noindex`. Der unmittelbar davor liegende Commit (`1118b55`) baute
mit **demselben Runner-Image und demselben zurückgespielten Cache-Schlüssel** — also ein
FLAKE, und die Antwort ist ein erneuter Lauf, keine Code-Änderung. Wer stattdessen die
eigene Scheibe debuggt, debuggt korrekten Code; das ist die teuerste Reaktion auf ein
unehrliches Messgerät. Ausführliche Fassung samt latentem Cache-Schlüssel-Defekt: der
CI-Abschnitt in `CLAUDE.md`.

### B — TOOLING: beschreiben unsere eigenen Kommandos noch dieses Repo?
Prüft Pfade in `.claude/commands/*.md` und `.claude/skills/*/SKILL.md`, die es nicht mehr
gibt, und Kommandos, die `swift build`/`swift test` verlangen, obwohl hier keine Toolchain
existiert. **Und die Nadeln der Wächter:** ein `contains("func …")` in `Tests/CISmoke`, dessen
Deklaration nirgends steht, kann nicht für seinen genannten Grund rot werden (#367).

⚠️ Zwei Formen sind davon AUSGENOMMEN, und beide Ausnahmen sind bezahlt: eine Nadel in einer
Abwesenheits-Behauptung (`XCTAssertFalse`, …) und — seit #754 — eine Nadel in einem
NEGIERTEN `contains(`, also die Ausschluss-Form `contains("foo()") && !contains("func foo")`.
Die zweite Form ist ein No-op, wenn sie ins Leere zeigt, und die POSITIVE Hälfte derselben
Zeile wird weiter geprüft. Ausgenommen wird die einzelne NADEL, nie die Zeile.
⛔ **„`--selftest` prüft genau diese eine Regel — und sonst nichts" stand hier und ist seit
#762 falsch, seit #1048 doppelt falsch (korrigiert #1052).** `--selftest` fährt **jede**
registrierte Regel und druckt pro Regel eine Zeile; heute sind es die Negations-Regel dieses
Abschnitts, „ein Kommentar ist keine Aufrufstelle" (Sektion C) und „ein `#if DEBUG`-Zweig ist
keine Tür" (Sektion C). **Hier steht bewusst keine ANZAHL** (#818/#1050) — die Liste ist
zweimal in zwei Monaten gewachsen, und ein Doc-Satz, der eine Prüfung für schmaler erklärt als
sie ist, lädt die nächste Sitzung ein, sie für unzureichend zu halten und eine zweite zu bauen.
Die Ausgabe IST die Liste:

```bash
python3 scripts/doctor.py --selftest          # eine Zeile je Regel
grep -c '^def selftest_' scripts/doctor.py    # dieselbe Zahl, aus der Quelle
```

**Deine Aufgabe:** Ein Kommando, das gelöschte Verzeichnisse scannt, meldet „sauber" für
Arbeit, die es nie angesehen hat — das ist dieselbe Lüge wie ein maskiertes Gate, nur eine
Ebene höher. Korrigieren oder löschen; ein Kommando anzupassen ist NICHT founder-gated.

### C — SURFACES: gibt es eine Tür zu dem, was der Code baut?
Listet `View`-Typen, die **nirgends** in `Sources/` konstruiert werden, und Modal-Flaggen,
die nichts auf `true` setzen kann.

**Deine Aufgabe — und hier ist die Skill am meisten auf Urteil angewiesen:**
- Nirgends konstruiert ist ein **Beweis** für Unerreichbarkeit.
- Irgendwo konstruiert ist **kein Beweis** für Erreichbarkeit — der Aufrufer kann selbst tot
  sein. Genau so überlebten die Tools-Grid-Ansichten wochenlang als „verdrahtet".
- Unerreichbar ist **an sich kein Defekt**. `ImmersiveStageView` und `BroadcastView` sind
  bewusst geparkt. Der Defekt ist **unerreichbar UND nirgends aufgeschrieben** — dann plant
  die nächste Session aus einer Tür heraus, die es nicht gibt.
- Vor dem Löschen eines UI-Blocks: **welche Modelle schreibt er als EINZIGER?** Ein Toggle mit
  persistiertem Flag hinterlässt beim Löschen einen unwiderruflichen Zustand, keine Lücke.
- Setterlose Modal-Slots sind **Kopfraum**: sie zählen gegen das Präsentations-Budget
  (Black-Screen-Gesetz 10.76.34). Wer einen neuen Modal braucht, nimmt zuerst einen davon.

### D — DOCS: stimmen die Zahlen in CLAUDE.md noch?
Zählt Quelldateien, Testdateien und Präsentations-Modifier und stellt sie neben die Zeilen,
die in CLAUDE.md eine Behauptung aufstellen.

**Deine Aufgabe:** Das Skript vergleicht absichtlich nicht selbst — Prosa zu parsen wäre
brüchig und würde falsche Sicherheit erzeugen. Lies die zitierten Zeilen gegen die Zahlen.
Der Modifier-Wert ist **dateiweit**, nicht nur die Body-Kette; ein Modifier im Content-Closure
eines anderen zählt hier mit, sitzt aber nicht auf dem generischen Typ des Body. Wer diese
Zahl korrigiert, zieht in CLAUDE.md nur noch EINE Stelle mit (der Presentation-Absatz);
ihre Provenienz liegt seit #707 in `memory/LEDGER_COUNTS.md` §D. ⛔ Hier stand „muss beide
Stellen in CLAUDE.md mitziehen … die Datei sagt selbst, dass sie synchron zu halten sind" —
alle drei Teilaussagen sind seit #707 falsch: der CRAFT-TOOL-DOORS-Absatz trägt keinen Zähler
mehr, und der zitierte Selbst-Hinweis („keep the two in sync or delete one") ist derselbe
Commit los geworden, weil er die Entdopplung ausdrücklich erlaubt hatte. Eine veraltete
Anweisung in DIESEM Werkzeug ist teurer als anderswo — es ist das, was eine Sitzung laufen
lässt, BEVOR sie einer Zahl glaubt (#708).

## Wann laufen lassen

- **Vor** „die Gates sind grün" als Beleg dafür, dass ein neuer Test lief.
- **Nach** dem Löschen eines Features (#121, #166/#167 haben je eine Tür verwaist).
- **Nicht** als Antwort auf „wie steht das Repo?" — das ist `baustellen` oder `/scan`. Diese
  Skill beantwortet eine engere Frage und wirkt breiter, als sie ist.
- **Nicht** in jedem Ralph-Zyklus. Ein Werkzeug, das ständig dasselbe meldet, wird stumm
  geschaltet — das ist genau der Mechanismus, der `continue-on-error` unsichtbar gemacht hat.

## Grenzen — ehrlich, weil eine Diagnose ohne Grenzen selbst eine Lüge ist

- Erreichbarkeit ist grep-basiert. Das echte Werkzeug wäre **Periphery** (SourceKit-basiert,
  findet unbenutzte Deklarationen exakt) — es braucht einen vollständigen Build und ist hier
  deshalb nicht einsetzbar. Wenn dieses Repo je eine lokale Toolchain bekommt, ersetzt
  Periphery Sektion C.
- Für die Workflows wäre **actionlint** das passende Zusatzwerkzeug (fängt Tippfehler in
  `if:`-Bedingungen, die Schritte still überspringen lassen). Nicht installiert, keine
  Abhängigkeiten heute.
- Nichts hier kompiliert oder führt etwas aus. Ein grüner Doctor sagt, dass die Instrumente
  ehrlich aussehen — nie, dass der Code funktioniert.
- **Klang, Gefühl und Geräteverhalten liegen vollständig außerhalb.** Die bleiben beim Founder
  am Gerät; das ist die Modus-Lehre und keine Lücke, die man wegprogrammiert.

## Wenn du eine Prüfung hinzufügst

Nur wenn sie einen Fehler fängt, der in diesem Repo **schon einmal passiert ist** — sonst
wächst die Ausgabe, bis niemand sie liest. Jeder Befund druckt `datei:zeile` plus den
Treffertext, damit er in zehn Sekunden von Hand prüfbar ist. Und schreib den Fehlschlag der
eigenen ersten Fassung als `⛔`-Kommentar dazu: die `\s*`-Rückverfolgung, die
`(?!false\b)` unwirksam machte, und das zu weite `\bbuild\b`, das drei Fehlalarme erzeugte,
stehen genau deshalb im Skript.
