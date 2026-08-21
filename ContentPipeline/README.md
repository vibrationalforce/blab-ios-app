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
  liegen, lösen **keinen eigenen Merge** aus — dasselbe strukturelle Loch wie bei
  `README.md`, `fastlane/**` und `.deploy/release` (#252, founder-gated). Bis das
  gelöst ist: Änderungen hier zusammen mit einer Änderung unter `Sources/`/`Tests/`
  pushen, oder von Hand mergen.

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
