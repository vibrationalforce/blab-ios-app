# ContentPipeline

Struktur für Kurzvideo-Content (TikTok · Reels · Shorts) zu Echoel.
Founder-Auftrag 2026-07-30.

**PIPELINE-ONLY.** Nichts hier wird ausgeliefert, nichts hier fasst `Sources/` an —
dieselbe Grenze, die für die `echoel-marketing`-Skill gilt.

---

## Verzeichnisse

| Pfad | Inhalt |
|---|---|
| `CLAIMS.md` | **Zuerst lesen.** Was heute wahr ist, was gestrichen ist, mit Begründung. |
| `Scripts/` | Skript-Templates. `template_short_form.md` ist die Basis. |
| `Assets/` | Bildschirmaufnahmen, Audio-Stems, Markenmaterial. **Nicht committen, was groß ist** — siehe unten. |
| `Prompts/` | Wiederverwendbare Prompts für Skript-/Caption-Varianten. |
| `Automation/` | Hilfsskripte (Aufnahme, Schnitt, Verpacken). |
| `Published/` | Log des Veröffentlichten: Datum, Plattform, Link, Zahlen. |

## Ablauf

1. **`CLAIMS.md` gegen `CLAUDE.md` „CURRENT STATE" prüfen.** Das Repo verliert und
   gewinnt Fähigkeiten schnell — die Drums verschwanden an einem Tag, der AUv3-Zweig
   an einem anderen. Ein Skript aus der letzten Woche kann heute falsch sein.
2. **Skript** aus `Scripts/template_short_form.md` ableiten.
3. **Aufnehmen.** Am Gerät, nicht im Simulator: die Kamera-Pulsmessung ist der Kern
   des Materials und im Simulator gibt es sie nicht (kein HealthKit, keine Kamera).
   Simulator taugt für reine UI-Aufnahmen.
4. **Checkliste** am Ende des Templates abarbeiten.
5. **Nach `Published/` eintragen** — sonst weiß in vier Wochen niemand, was schon lief.

## Was NICHT automatisiert wird

Kein Auto-Posting. Jede Veröffentlichung ist eine Außenwirkung mit Markenrisiko und
geht über einen Menschen. Die Pipeline erzeugt Entwürfe, keine Posts.

## Zwei technische Randnotizen

- **`project.yml` braucht KEINE Änderung.** Xcode-Targets deklarieren ihre Quellen als
  explizite Pfade (`Sources/Echoelmusic`, `Sources/EchoelmusicWidgets`, …), nicht als
  Wurzel-Scan. Ein neues Verzeichnis auf oberster Ebene wird von XcodeGen nie
  eingesammelt, also gibt es auch nichts auszuschließen. (Der Auftrag verlangte eine
  Ausschluss-Regel — geprüft und als unnötig verworfen, statt sie kosmetisch
  einzutragen.)
- **`ContentPipeline/**` steht in KEINEM Pfad-Filter der Auto-Merge-Workflows**
  (`auto-merge-claude.yml`: `Sources/**`, `Tests/**`, `Package.swift`, `project.yml`,
  `.github/workflows/**`; `auto-merge-docs.yml`: `docs/**`). Commits, die nur hier
  liegen, lösen **keinen eigenen Merge** aus (#252, founder-gated). Bis das
  gelöst ist: Änderungen hier zusammen mit einer Änderung unter `Sources/`/`Tests/`
  pushen, oder von Hand mergen.

  ⛔ **#720: hier stand „dasselbe strukturelle Loch wie bei `README.md`, `fastlane/**`
  und `.deploy/release`" — eine AUFZÄHLUNG, wo die Sache eine UMKEHRUNG ist.** Der
  Filter oben ist eine **Erlaubnis-Liste aus fünf Einträgen**; das Loch haben also
  nicht drei Geschwister, sondern **jeder andere getrackte Pfad**. Eine Teil-Liste in
  einem Register liest sich als vollständig, und das ist teurer als eine falsche Zahl:
  sie beantwortet die Frage „bin ich betroffen?" mit Nein für alles, was nicht
  dasteht. Nicht dastanden unter anderem `scripts/**`, `memory/**`, `scratchpads/**`,
  `CLAUDE.md`, `decisions.csv`, `Resources/**`, `ci_scripts/**` und die
  `*.entitlements` — die letzten drei sind ship-relevant.

  ⭐ **Aufgefallen ist es an drei eigenen Commits** (#717–#719, alle nur unter
  `scripts/**`): kein Gate lief, kein Merge feuerte. **Präzise gesagt**, weil `scripts/`
  nicht pauschal ungesehen ist: `xcode-compile-check.yml` listet **eine einzelne Datei
  daraus**, `scripts/check-infoplist.sh`. Ein Commit an DIESER Datei zieht also sehr
  wohl ein Gate; einer an `scripts/doctor.py` nicht. „`scripts/**` steht in keinem
  Filter" wäre die nächste Über-Behauptung gewesen.

  ⚠️ **Die Pfad-Filter, gemessen am 2026-08-22** (`grep -A12 '^on:' .github/workflows/*.yml`;
  Befehl daneben, weil diese Liste altert):
  `ci.yml` und `full-tests.yml` = `Sources/** · Tests/** · Package.swift · project.yml` plus
  je die eigene Workflow-Datei · `xcode-compile-check.yml` zusätzlich `Package.resolved ·
  Resources/iOS/Info.plist · scripts/check-infoplist.sh` · `quick-test.yml` = `Sources/**/*.swift ·
  Tests/**/*.swift · Package.swift` · `benchmark.yml` = `Sources/** · Package.swift · project.yml` ·
  `testflight.yml` = **nur** `.deploy/release` · `pages.yml` = `docs/**`.

  ⭐ **#932: DIESE PROSA HAT SEIT HEUTE EINEN WÄCHTER** —
  `Tests/CISmoke/TheLawFileNeverReachesMainByItselfTests.swift`, Ansprüche 6 und 7. Er pinnt
  die zwei Sätze, die von selbst altern: dass `xcode-compile-check.yml` **genau EINE** Datei
  aus `scripts/` beim Namen nennt (die Tatsache, ohne die „`scripts/**` steht in keinem
  Filter" unwiderstehlich klingt), und dass dieser Eintrag die Sache weiterhin als
  **Erlaubnis-Liste** rahmt statt als Geschwister-Aufzählung. **Anlass war ein Rückfall:**
  eine Sitzung hat genau diese Über-Behauptung ein zweites Mal gemessen und als neuen Befund
  angekündigt, weil sie den Glob gegrept hat und diese Datei nicht kannte. Wer die zwei Sätze
  ändert, zieht den Wächter im selben Commit mit (#456) — und umgekehrt: wird der Filter
  breiter, ist er zuerst rot und nennt diese Stelle.

  ⚠️ **Und „kein eigener Merge" heißt nicht „erreicht `main` nie"** — das ist die
  #699-Rücknahme, die eine Zeile höher schon steht: der Merge nimmt `${{ github.sha }}`
  samt Vorgeschichte, ein solcher Commit fährt als **Passagier** auf dem nächsten
  Commit mit, der einen gefilterten Pfad berührt. Unbegrenzt lange wartend, dauerhaft
  hängend nur, wenn ein Zweig darauf ENDET.

  ⛔ **#699: hier stand „erreichen `main` durch KEINE Automatik", und das war zu stark
  — widerlegt von `CLAIMS.md` in DIESEM Verzeichnis**, das die Passagier-Wirkung seit
  jeher richtig beschreibt („ein Commit, der beide anfasst, zieht diese Datei mit nach
  `main`"). Der Merge nimmt `${{ github.sha }}`, also die ganze Vorgeschichte: ein
  reiner Pipeline-Commit fährt auf dem nächsten `Sources/`/`Tests/`-Commit mit. Genau
  diese Formulierung ist am 2026-08-21 in CLAUDE.md neu erfunden und dort als #698
  zurückgenommen worden — **zwei Dateien nebeneinander, eine richtig, eine falsch, und
  die falsche wurde eine Ebene höher kopiert, statt die richtige gelesen zu werden.**
  Die HANDLUNGSANWEISUNG darüber bleibt unverändert richtig: wer Isolation WILL, fasst
  `Tests/` nicht an; wer den Merge will, hängt sich an einen Code-Commit.

## Große Dateien

`Assets/` ist für Verweise und kleine Vorlagen gedacht. Rohvideo gehört nicht in ein
Git-Repo ohne LFS — das Repo hat kein LFS und soll keins bekommen, ohne dass darüber
entschieden wurde. Große Medien lokal oder in der Cloud halten und hier nur benennen.
