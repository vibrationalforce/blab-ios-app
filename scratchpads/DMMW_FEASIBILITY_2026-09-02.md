# DMMW-Machbarkeit, gemessen — 2026-09-02

> **Founder-Frage (2026-09-02, wörtlich):** „DMMW vorhaben überprüfen ob es mit [dem neuen Modell]
> nun endlich machbar ist". Dies ist eine **MESSUNG, keine Tür** — `decisions.csv:685` verbietet bis
> zur Founder-Antwort jede DAW-Tür und jede Löschung. Nichts hier wurde gebaut.
>
> **Methode:** Workflow `wf_8d20bfce-a99`, 4 Teams × (3 Worker + 1 Lead), read-only, jede Behauptung
> mit Befehl. **Ehrliche Reichweite:** 89 Agenten gestartet, 70 fertig, **19 am Sitzungslimit
> gestorben** — darunter die Widerleger für 9 Befunde und die **Synthese-Stufe**. Dieser Bericht ist
> daher von der Sitzung aus den vier LEAD-Antworten geschrieben, nicht vom Workflow synthetisiert.
> Stand: 17 Befunde adversarial bestätigt, 10 „widerlegt" (davon 8 nur auf der Linse „schon
> aufgeschrieben", die Messungen selbst reproduzieren), 9 ungeprüft. Alle Zahlen sind auf
> `2f4e6cd`…`14c403c` gemessen; Zahlen einer lebenden Datei sind Daten, keine Tatsachen —
> **den Befehl daneben ausführen, nicht die Zahl zitieren.**

## 0. Antwort in einem Satz

**Nein — nicht „endlich machbar mit dem neuen Modell", weil das Modell nie die Grenze war.** Die
DMMW-Maschine ist seit 07-31 vollständig im Baum und GEWACHSEN; was fehlt, sind (a) drei
Founder-Entscheidungen, die ein Workstation-Comeback umkehren müsste, und (b) vier physische
Prüf-Kanäle (Compiler, Simulator-Smoke, Merge-Gate, Founder-Ohr/Gerät), die kein Modell ersetzt.
Ein stärkeres Modell macht das Bauen billiger und das Beweisen keinen Cent billiger — es würde die
Lücke „gebaut, aber nicht bewiesen angeschlossen" vergrößern, die heute die dominante Defektklasse
des Repos ist.

## 1. Die 07-31-Diagnose hat gehalten (Team DIRECTION)

`ULTRAARCHITECTURE_DMMW_2026-07-31.md` sagte: Scheitern = Richtungs-Flips + Prüfkapazität, nicht
Fähigkeit. Gemessen heute:

| Größe | 07-31 | 09-02 | Befehl |
|---|---|---|---|
| Richtungswechsel seit 07-31 | — | **0** (4 fokus-bestätigende Zeilen: L330/L388/L584/L618) | `python3`-csv-Scan `decisions.csv`, Regex des 07-31-Docs |
| Längste Strecke ohne Flip | 29 Tage (05-22→06-20) | **42 Tage** (seit Flip 15, 07-22) | `datetime` |
| Flip-Zähler | 18 | **18** — diese Frage ist NICHT Nr. 20 (L685 loggt sie als Frage) | `decisions.csv:685` |
| A0 (Slice 5b–5d HOLD/verwerfen) | offen | **immer noch keine Zeile** | `grep -n "Slice 5" decisions.csv` |
| 90-Tage-Sperrfrist (§5.2) | empfohlen | **nie angelegt** (einziger Treffer ist CI-Retention) | `grep -in sperrfrist decisions.csv memory/decisions.md` |

⚠️ Gemessener Druck in Richtung Flip 20: zwei Founder-Fragen zur selben stillgelegten Richtung in
33 Tagen, plus der Stunden-Cron (`trig_01Mio4dc5T4KJPfRZKguy9mn`, erstellt 2026-07-13, nie
umgeschrieben — `created_at == updated_at`), der weiter drei DAW-förmige Punkte und einen toten
Branch nennt. Jede Sitzung überstimmt ihn durch Lesen; das ist Disziplin, kein Mechanismus.

## 2. Die Maschine lebt und ist gewachsen (Team REWIRE-COST)

Alle zehn Modell-Typen der 07-31-Inventur mit gleich vielen oder mehr Referenzen: Timeline 61→75,
TimelineStore 9→12, AudioLanePlayer 6→8, MultiTrackRecorder 6→7, LaneVoiceRack 17→19, TrackFX 11→13
(`git grep -l <Typ> -- 'Sources/**/*.swift' | wc -l`, ungebunden wie im Plan). Sources 333→370 Dateien
(`git ls-files 'Sources/**/*.swift' | wc -l`).

**Aber jede Tür steht auf null Aufrufstellen**, und **jeder löschende Commit liegt VOR dem Graft
`545b19e`** (807dc0d, eb58e7a, #167, #473, #475, AUv3 07-24) — in diesem Shallow-Klon nicht
inspizierbar. Eine Rückkehr ist deshalb ein **Neubau nach aufgezeichneten Zahlen, kein Revert**.
Zeilenzahlen für ClipView/ArrangeTimelineView/ChannelRackView/AUv3 sind UNGEMESSEN (zwei
widersprüchliche Aufzeichnungen für AUv3: 383 vs 536) und dürfen nicht als Größe zitiert werden.

Preis je B-Scheibe des 07-31-Plans, gemessen:

| Scheibe | Code-Kosten | Was sie WIRKLICH blockiert |
|---|---|---|
| B1 Mehrspur-Tür | klein: eine `register(defaults:)`-Zeile + ein Arm-Bedienelement + zwei Wächter | kehrt `decisions.csv:330` um (Founder-Entscheidung, #204) |
| B2 Arrangement-Ansicht | **größte Scheibe**, Größe nicht rekonstruierbar; 42 von 58 Store-Methoden aufruferlos | Modal-Decke 14, Hot-State-Gesetz (Playhead = fünfter heißer Erzeuger), 5 von 10 Panels reflowen nicht |
| B3 Automations-Tür | Canvas über lebendem `TimelineAutomationRowMath`; heute nur der Lese-Streifen | dieselbe Decke; Founder-Ohr für jede Kurve |
| B4 Patch/FX pro Spur | halb Tür (Lane-Patch modelliert, persistiert, angewandt, ohne Editor), halb NEUES Modell (`TrackFXStore` hat drei feste Rollen-Slots, kein per-Lane-FX) | Council-Frage #23 offen |
| C2/D AUv3 Host/Target | — | **geschlossen durch #590** (`decisions.csv:388`, 2026-08-14: kein Plugin-System) |
| C1 Watch-Hälfte | — | kein Transport (`WCSession` 0 Code-Treffer) |

Von den vier A-Vorbedingungen des Plans ist nur A3 erfüllt: **A0** keine Zeile · **A1**
Simulator-UI-Smoke existiert nicht (`grep -rn XCUIApplication Tests` → 0, kein UITest-Target) ·
**A2** der L0⊥L2-Wächter existiert nicht und **wäre am ersten Tag rot**, weil `EchoelStudioView`
`timelineStore`/`clipStore`/`TrackFXStore` bereits direkt liest.

## 3. Die Grenze ist die Prüfschleife, nicht das Modell (Team VERIFY-CAPACITY)

Was eine Sitzung allein beweisen kann, ist unverändert: kein Compiler (`command -v swift` → nichts),
kein Simulator, Wächter per Transkription benotet, und das einzige ausgeführte Verdikt kommt durch
ein `tail -200 test.log` hinter einer Pipeline, die auf jedem Push `failure` meldet
(`ci.yml:197/206`, #807/#396, beide founder-gated). Folge, aus dem Repo selbst belegt: **fünf
blockierende Wächter saßen rot auf korrektem Baum** — Spannen 7, 178, 100, 390 Commits
(`git rev-list --count`) — und **zwei Kontrollen (#686, #943b) zeigen, dass ein sicher fallender Test
mit grünem Gate auslieferte**, ohne eine Ergebniszeile dieser Suite im Fenster.

Was der Founder prüfen kann, ebenfalls unverändert und jetzt beziffert:

| Kanal | Messung | Befehl |
|---|---|---|
| Deploys seit Graft | 54 Commits an `.deploy/release`, v384→v436 (~2/Tag) | `git log --format=%s 545b19e..HEAD -- .deploy/release \| wc -l` |
| Founder-Geräteartefakte | 13 Builds, 9 davon Crash-Logs EINER Familie (`isInputConnToConverter`) | SESSION_LOG-Lesung, Muster bestätigt, Zahl nicht zeilenweise |
| Angenommene Builds | **0** | — |
| Offene Geräte-Bitten | **80 in 68 Dateien, 0 beantwortet** (61→80 in drei Tagen) | `python3 scripts/founder-verify.py` |
| `VERIFIED-2026-…`-Marken | **0** | `git grep -c 'VERIFIED-20' -- Sources Tests` |

Das ist das Ventil, das der 07-31-Plan selbst setzte (§5.2 Nr. 5: keine neue Fläche, solange
diese Liste nicht leer ist). Es steht bei 80/0. Die Founder-Schleife ist schnell, wenn ein Absturz
reproduziert, und still sonst — **sie verifiziert Scheitern, nicht Funktionen.** Ein DMMW-Plan, der
auf „Founder hat abgenommen" gatet, hat in diesem Protokoll kein Gate.

## 4. Was seit 07-31 WIRKLICH anders ist — und was ein stärkeres Modell bewegt (Team WHAT-CHANGES)

**Geändert hat sich das MESSGERÄT, nicht die Größe, die es misst:** blockierendes Bundle 78→404
Dateien (`git ls-files 'Tests/CISmoke/*.swift' | wc -l`), acht read-only selbstgetestete Skripte
(dead-needles, gh-test-verdict, doorless-state, founder-verify, needle-reachability, count-pins,
window-margins, diag-ladder), #316 LUFS repariert, 6 der 7 namentlich genannten 07-31-Defekte gelöst
oder gepinnt (#204 bleibt aufruferlos). **Nicht geändert:** kein Compiler · kein Simulator-Smoke
im blockierenden Pfad (`.mcp.json` ios-simulator `disabled: true`, 0 UITest-Dateien — der
„größte einzelne Hebel" des 07-31-Docs hat null Fortschritt) · Auto-Merge wartet auf kein Gate ·
Modal-Decke 14 auf einer 11.988-Zeilen-Wurzel · 313 nicht-blockierende Tests hinter
founder-gated Workflow-Dateien mit null Commits seit dem Graft.

§5.2-Vorbedingungen für einen dritten Anlauf: 1 erledigt (#316b) · 1 durch Disziplin statt
Mechanismus gehalten (keine Sperrfrist-Zeile; `decisions.csv:302` review_date 08-25 überfällig,
`./review.sh` → 246 fällig) · 1 praktiziert, nicht erzwungen (Wächter ≠ Merge-Gate) ·
2 abwesend (Simulator-Smoke, Flächen-Deckel).

**Zum Modell — das Repo kann nicht „ja" sagen:** Der Wechsel auf die neue Modellfamilie ist am
07-03 geloggt (`SESSION_LOG:6102`); **DMMW-Anlauf #2 (07-10→07-24) lief also bereits unter der
Modellfamilie, nach der jetzt gefragt wird**, und wurde vom Founder-Verdikt beendet, nicht von einer
Fähigkeitsmauer (einziges aufgezeichnetes „Limit" war ein Sitzungsbudget, `SESSION_LOG:8166`).
Die Commits des heutigen Modells sind Dokumente, ein Bump und eine Datei-Verschiebung — **null
Daten** für Workstation-Arbeit; ungetestet, nicht widerlegt. Jedes Modell mit Protokoll landet bei
49–60 % Selbstkorrektur-Commits: **die Korrekturquote ist die Signatur der Schleife, nicht des
Modells.** Ein stärkeres Modell bewegt plausibel genau EINE der sieben 07-31-Ursachen — die Klasse
„mehr gebaut als angeschlossen bewiesen" (267 ⛔-Rücknahmen in 241 Sitzungen seit August), indem es
misst statt zitiert — und die Baurate, die nie der Engpass war (767 Commits in 25 Tagen, Sources
+37 Dateien, Bundle +175 Dateien, während die Prüfliste 51→80 wuchs).

## 5. Die drei Kriterien des Founders

„Einfach zu begreifen, zu vermarkten und zu pflegen" (`PRODUCT_DEFINITION.md`). Ein Modell bewegt
höchstens das dritte. **Begreifen** (ein Akronym, ein zweites Produkt) und **Vermarkten** (ein
Konkurrenzfeld, dem der Founder am 05-22 bewusst „andere Achsen zugestand") sind strukturell — ein
besserer Coder verlängert den Satz, er verkürzt ihn nicht.

## 6. Was JETZT zu entscheiden ist, unabhängig von der Antwort

1. **A0** — `#132 Slice 5b–5d`: HOLD oder verwerfen. Seit 33 Tagen ohne Zeile; die Maschine wird
   persistiert (#527/#541), Abklemmen macht „abwesend" zu „still stumm".
2. **Sperrfrist** auf die Richtung von `decisions.csv:302` (review_date-Mechanik), oder bewusst
   keine — aber als Zeile.
3. **Cron-Text** (Founder-Besitz, lebt außerhalb des Repos): Punkte 1/3/4 streichen oder
   umschreiben; Branch-Name korrigieren.
4. Wenn der Founder die Modell-Hypothese TESTEN will: **eine** begrenzte Workstation-Scheibe mit
   Foundation-only-Kern, ein Wächter, dessen Ergebniszeile der Founder im Log-Fenster bestätigt,
   und eine Geräteprobe, die er selbst mit `VERIFIED-JJJJ-MM-TT` markiert. Vorher ist Machbarkeit
   eine Frage seiner Prüf-Stunden, und die Zahl, die sie beantwortet, heißt **80/0**.

## 7. Was dieser Bericht NICHT geprüft hat

Die 9 UNVERIFIED-Befunde (Modell-Zuordnung von Flip 13/14, Kriterien-Struktur, §5.1 A/B/C/E im
Detail, Modal-Decke als Wächter-Zitat) reproduzieren in ihren Kern-Befehlen, haben aber keinen
Widerleger gesehen. Kein Klang, kein Gerät, keine Nutzerstudie — alles Quelltext und Protokoll.
