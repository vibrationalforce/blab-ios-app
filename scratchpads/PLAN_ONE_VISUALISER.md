# PLAN — Ein Visualiser (Founder-Auftrag 2026-08-13)

> *"Alle visuals in den einen visualiser zusammenfassen und optimieren: Biophysikalische
> evidenzbasierte Health (no Claim) visuals, echte Wasser visuals, Spiegelneuronen Visuals,
> Kaleidoskop, Mandelbrot Fraktale, du checkst was noch gebraucht wird"*

**Status: PLAN, nichts gebaut.** Gemessen 2026-08-13 gegen `fc8161c`.

---

## 0. Der Befund, der den Auftrag verkleinert — und die Arbeit verschiebt

**Es gibt schon EINEN Renderer.** `Views/MetalBioView.swift` ist die einzige Metal-Fläche der
App; sie compiliert ihren Shader zur Laufzeit inline und hat einen `style`-Selektor plus
`styleB` + `blend`, kreuzblendet also von Haus aus zwischen zwei Looks. `Studio/LookBlendMap.swift`
ist die kuratierte Bibliothek darüber, mit EINEM stufenlosen Regler durch eine
nutzer-definierte Sequenz (persistiert als `"3,5,7"` unter `visual.sliderLooks`).

Was NICHT zusammengefasst ist, sind nicht die Renderer — es sind die **Montagestellen** und
die **Bibliothek**:

| Fläche | Zustand (gemessen) |
|---|---|
| `FloatingVisualWindow` | montiert, über das Monitor-Symbol im Marken-Header erreichbar |
| `ExternalDisplayScene` | montiert (externer Schirm / Beamer) |
| `AnalysisSpectrumView` · `AnalysisWavefrontView` | montiert im Instrument — **Messgeräte**, keine Looks |
| `visualVJOverlay` + `SpectralDonutView` | **türlos**: `showVisual` hat in `Sources/` KEINEN Schreiber von `true` (#270/#505) |
| `AnalysisScopeView` · `AnalysisPoincareView` | türlos, **absichtlich** (Founder-Screenshot 2026-08-02, rotes X) |
| `ImmersiveStageView` | türlos, absichtlich (Ship-Gate 4: „demonstrierbar, nicht erforderlich") |

⭐ **Die Arbeit ist also: eine Tür für das Vollbild, und die Look-Bibliothek füllen.**
Nicht: Renderer verschmelzen. Wer den Auftrag wörtlich als „Renderer zusammenfassen" liest,
baut etwas, das seit dem 2026-07-08-Kuratieren schon existiert.

---

## 1. Was die Bibliothek HEUTE hat — und was schon im Shader liegt

`LookBlendMap.library` zeigt **vier**: `0 Rings` · `3 Water` · `5 Aurora` · `7 Depth`.

**Im Shader compiliert, aus der UI zurückgezogen** (2026-07-08, drei Kuratier-Durchgänge —
*"Weniger ist mehr"*, *"Prism soll weg"*, *"Cymatics und Lissajous passt nicht zum Vibe"*):
`1 Cymatics` · `2 Plasma` · `4 Prism` · `6 Lissajous` · `8 Scope` · **`9 Fractal`**.

⭐ **Mandelbrot ist damit KEIN Neubau, sondern eine Zeile.** `9 Fractal` existiert im Shader;
`sequence(from:)` verwirft heute nur seinen persistierten Index. Ihn wieder in `library`
aufzunehmen ist der billigste Punkt der ganzen Liste — und der erste, der zu prüfen ist:
**sieht der vorhandene Fractal-Look nach Mandelbrot aus, oder ist es ein anderes Fraktal?**
Das entscheidet, ob es eine Zeile oder ein Shader-Zweig wird.

⚠️ **Und die Rücknahme von 2026-07-08 war eine FOUNDER-Entscheidung mit Begründung.** Sie
jetzt umzukehren ist legitim (der Auftrag sagt es) — aber sie wird umgekehrt, nicht
übersehen. Was 2026-07-08 „passt nicht zum Vibe" hieß, muss beim Zurückholen einen Grund
haben, sonst kommt derselbe Kuratier-Durchgang in vier Wochen wieder.

---

## 2. Die fünf gewünschten Looks, einzeln geprüft

### a) Biophysikalisch, evidenzbasiert, **ohne Claim**
**Schon der Entwurfsgrundsatz, nicht neu.** `LookBlendMap`s eigener Kopf sagt es:
*„All flash-safe, slow-motion fields: the calm register IS the health consideration."*
Dazu die harte Decke von **3 Hz** (W3C/WCAG, Epilepsie) und `BioVisualParams` als
flash-sicherer Puls. Die zitierte Forschung liegt in `BioScienceInfo` (HRV-Resonanz,
Lehrer/Vaschillo, Goessl 2017) — **Fakten und Selbstbeobachtung, kein Gesundheitsversprechen**.
→ **Kein Bauauftrag. Eine Prüfliste**, die jeder neue Look besteht, bevor er in `library` darf.

### b) Echte Wasser-Visuals
`3 Water` existiert (Atem-Wellen). „Echt" heißt: **Refraktion und Kaustiken** statt
Ringwellen — genau das, was `7 Depth` schon andeutet („underwater light caustics").
→ **Ein Shader-Zweig, kein neuer Look.** Der billigste Weg ist, `Water` zu vertiefen statt
einen fünften Wasser-Look danebenzustellen.

### c) Kaleidoskop
**Fehlt komplett.** Aber es ist der billigste NEUE Look von allen, weil es kein eigenes Feld
ist, sondern eine **Koordinaten-Faltung VOR jedem bestehenden Feld** (Polarwinkel modulo
`2π/n`, gespiegelt). Damit wird es zu einem *Modifikator*, der auf Rings · Water · Aurora ·
Depth · Fractal gleichzeitig wirkt — fünf neue Bilder aus einem Zweig.
→ **Empfehlung: als MODIFIKATOR bauen, nicht als Look.** Ein eigener Look-Slot wäre die
schwächere Version derselben Arbeit.

### d) Mandelbrot-Fraktale
Siehe §1 — `9 Fractal` ist da. → **Erst prüfen, dann entscheiden.**

### e) „Spiegelneuronen Visuals" — ⚠️ HIER GIBT ES EINEN KONFLIKT, DEN ICH NICHT STILL LÖSE

**Deine eigene Übergabe (C9, 2026-08-13) sagt wörtlich: der Begriff „mirror neuron" darf in
Code, UI und Docs NICHT vorkommen.** Der Auftrag von heute nennt ihn.

Ich löse das so, und sage es, statt es zu verschweigen:
- **Das VISUAL wird gebaut.** Was gemeint ist, ist real und in dieser App gut begründet: eine
  Bewegung, der der Körper von selbst folgt — ein Feld, das im Resonanz-Tempo atmet, und der
  Atem geht mit. Das ist **Entrainment**, es ist die Mechanik hinter der Resonanz-Atemführung,
  die es hier schon gibt, und `EntrainmentEngine` liegt kompilierend im Baum (Session-Experiment,
  unmontiert — ausdrücklich aufbewahrt, weil es die geprüften Flash-/Latenz-/Pacing-Gesetze hält).
- **Der BEGRIFF wird nicht benutzt.** Nicht im Look-Namen, nicht im Shader, nicht in der
  Panel-Kopie, nicht im Store-Text. Grund: er ist eine Aussage über einen neuronalen
  Mechanismus im Gehirn des Nutzers — also genau die Sorte Behauptung, die #184 zwölfmal aus
  dem App-Store-Text streichen musste und die unter 2.3 abgelehnt wird. Und die Marken-Zeile
  verbietet Wirkungs-Behauptungen ohne Beleg.
- **Vorgeschlagener Name: „Follow"** (oder „Breathe"). Er beschreibt, was man TUT, statt zu
  behaupten, was im Kopf passiert — und er ist die einzige Formulierung, die den Look
  gleichzeitig ehrlich und ausführlich beschreibbar macht.

**Ein Wort von Dir genügt, wenn Du einen anderen Namen willst.** Was ich nicht tue, ist den
Begriff in den Code schreiben und Deine C9-Zeile dabei überfahren.

---

## 3. Was ich als FEHLEND ergänze („du checkst was noch gebraucht wird")

1. **Die Tür zum Vollbild.** `showVisual` hat keinen Schreiber von `true`. Damit sind das
   VJ-Overlay UND `SpectralDonutView` unerreichbar — zwei fertige, verdrahtete Flächen hinter
   einer fehlenden Zeile. **Das ist der größte Ertrag pro Zeile im ganzen Auftrag.**
   ⚠️ Aber: die Präsentations-Kette steht auf **14** und darf nicht wachsen (Black-Screen-Gesetz
   10.76.34). Der Slot EXISTIERT bereits — es braucht nur einen Setzer, keinen 15. Modifier.
2. **Ein Look-Wähler, der die Bibliothek zeigt.** Heute wählt man eine SEQUENZ als
   `"3,5,7"`-Zeichenkette; mit acht bis zehn Looks braucht das eine Fläche, die zeigt, was
   es gibt.
3. **Die Grau-Frage aus 383 ist immer noch unbeantwortet.** Warm-mix 0,80 → 0,92 und Farb-Gate
   1,6 → 2,4 sind deployt und unbestätigt. **Neue Looks zu bauen, bevor die Farbkette bestätigt
   ist, heißt sie im Zweifel alle grau zu bauen.** Das gehört VOR §2.
4. **Ein Leistungs-Deckel.** `MetalBioView` steht statisch auf `preferredFramesPerSecond = 60`;
   der `ResourceGovernor` fährt heute nur Detailgrad und Reduce-Motion, nicht die Rate. Ein
   Kaleidoskop-Modifikator über einem Fraktal ist der erste Look, bei dem das zählt.

---

## 4. Reihenfolge (Vorschlag, ein Ralph-Punkt pro Zyklus)

| # | Punkt | Größe | Warum zuerst |
|---|---|---|---|
| V0 | **Grau bestätigen** (Gerät, Du) | 0 | sonst wird alles Weitere grau gebaut |
| V1 | **Tür zum Vollbild** (`showVisual`-Setzer, vorhandener Slot) | S | zwei fertige Flächen für eine Zeile |
| V2 | **`9 Fractal` prüfen + ggf. in `library`** | S | Mandelbrot ist evtl. schon da |
| V3 | **Kaleidoskop als Koordinaten-Modifikator** | M | fünf neue Bilder aus einem Zweig |
| V4 | **Water vertiefen** (Refraktion/Kaustik) | M | „echtes Wasser" |
| V5 | **„Follow"** — Entrainment-Feld, 3-Hz-Decke, ohne Begriff | M | braucht V0 und den Namens-Entscheid |
| V6 | **Look-Wähler-Fläche** | M | erst sinnvoll, wenn die Bibliothek gewachsen ist |

**Council-Gate vor V3 und V5** — beides sind Shader-Änderungen mit Flash-Sicherheits-Bezug,
und V5 berührt zusätzlich eine Marken-Rote-Linie.

---

## 5. Was dieser Plan NICHT tut

- Keine Renderer werden verschmolzen — es gibt nur einen.
- `AnalysisSpectrumView` / `AnalysisWavefrontView` bleiben, wo sie sind: **Messgeräte im
  Instrument, keine Looks.** Sie in den Visualiser zu falten würde eine Ablesung in eine
  Stimmung verwandeln, und die Marken-Zeile sagt „legible numbers first, visualization second".
- `AnalysisScopeView` · `AnalysisPoincareView` · `ImmersiveStageView` bleiben türlos —
  jede dieser Türlosigkeiten ist eine ausdrückliche Founder-Entscheidung, keine Lücke.
