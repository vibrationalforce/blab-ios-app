# PLAN — EchoelVoice: die Stimme als Struktur-Patch (Voice→Timbre→Color)

**Stand:** 2026-08-14, aus dem 8-Agenten-Scout (`wf_828098b0-3e1`), beide Leads adversarial
verifiziert, jede tragende Behauptung mit `file:line` nachgeprüft. Founder-Ask: Stimm-Clone
(Nia9ara), teilbar; „Knüpfele Voice to color"; Fokus Tönen & Stimmlaute — **als Praxis/
Selbstbeobachtung formuliert, nie als Heilung** (harte rote Linie, CLAUDE.md BRAND).

## Die eine Idee

Die Stimme wird nicht aufgenommen und wiedergegeben — sie wird **vermessen und destilliert**:
5–10 s Tönen → `VoiceAnalyzer` (F0 + Voicing, EXISTIERT, getestet) + `EchoelRealFFT`
(Spektrum, EXISTIERT) → **`VoiceTimbreProfiler`** (NEU, der eine reine Kern): pro Frame
|X(f)| an k·F0 abtasten (k=1…64, interpolierte Bins, 0 über Nyquist), über den Take
**Median pro Harmonischer, nur stimmhafte Frames**, max-normalisiert → 64-Tap-Vektor →
**`EchoelDDSP.loadTimbreProfile(_:blend:)`** (EXISTIERT, `EchoelDDSP.swift:2310`, heute
türlos — dieser Plan ist sein erster Produzent). Ergebnis: die Engine KLINGT nach der
Stimme, als spielbares Timbre — kein TTS, kein Deepfake (kann keine Sprache erzeugen).

**Voice→Color:** dasselbe Profil hat einen Schwerpunkt (spektraler Centroid) und eine
Rauheit — zwei Skalare, die die Visual-Palette ziehen können (Hue/Warmth), über den
vorhandenen `MusicalFrame`/Bio-Pfad. Eigene Scheibe NACH dem hörbaren Kern.

## Verifizierte Fundamente (nicht neu bauen!)

| Baustein | Ort | Status |
|---|---|---|
| `VoiceAnalyzer` (F0, Voicing, Energie) | `Studio/VoiceAnalyzer.swift:39` | rein, 11 Tests, türlos |
| `EchoelRealFFT` + `powerSpectrum` | `DSP/EchoelVDSPKit.swift:99` | live |
| `loadTimbreProfile(_:blend:)` | `DSP/EchoelDDSP.swift:2310` | **null Aufrufer** — die Steckdose existiert |
| `SynthPatch` decodeIfPresent-Decoder | `DSP/SynthPatch.swift:236` | Feld-Zuwachs decode-sicher |
| Patch speichern/teilen (mailto, kein Server) | `presetRow`, `EchoelStudioView.swift:6664/:6752` | live |
| Mic-Tap (1024er Fenster) | `MicrophoneManager.swift:232` | live, s. Falle 2 |

## Die drei Fallen (vom Audio-Lead, je verifiziert)

1. **Der Recall LÖSCHT das Profil.** Jeder Produktions-Patch-Weg endet im `ResolvedPatch`-
   Drain auf dem Audio-Thread, und der ruft `applyTimbre(timbre,…)` **bedingungslos** —
   für einen Voice-Patch ist `timbre` nil → `clearTimbreProfile()`. `ResolvedPatch` ist
   absichtlich POD (kein Array!, Kommentar `SynthPatch.swift:~703`). Persistenz muss also
   NACH dem Drain sequenziert werden (Control-Thread-Hook nach Apply), nicht hineingelegt.
2. **Mic-Tap hoppt pro Buffer auf Main** (`:243`, ~47/s) — für „aufnehmen während Bio
   läuft" gilt das 10.76.48-Batching-Muster, nicht der Ist-Zustand.
3. **F0-Fenster:** 1024 Samples @48 kHz sind für tiefe Männerstimmen (70 Hz) knapp —
   Analyse auf 2048–4096er Fenstern auf dem Control-Thread aggregieren.

## Konsens & Marke (vom Product-Lead, verifiziert)

- **Nur die eigene Stimme, per Konstruktion:** einzige Quelle ist das live-Mikrofon in
  einer nutzer-scharfgeschalteten Session (#277-Muster). KEIN Datei-Import — das blockiert
  Fremdstimmen strukturell, nicht per Policy-Text.
- **⛔ Info.plist-Blocker (founder-gated, NUR berichten):** der Mic-String verspricht
  „Audio is not recorded" (`Info.plist:84-85`). **v1 ist deshalb analysis-only: nur
  PARAMETER werden persistiert, nie eine Audio-Datei.** Das shippt unter dem heutigen
  String. Ein v2 mit .caf-Aufnahme braucht ZUERST die founder-genehmigte String-Änderung.
- **Teilen:** vorhandener mailto-Weg, nur Parameter. Pflicht-Label: „Derived from the
  sharer's own voice. Contains synth parameters only — no audio recording."
- **Tür:** `soundPanel` (Sound-Chip, `dropdownContent .sound` → type-erased, **null
  Modifier-Kosten**), neben `presetRow`. KEIN neues Sheet (14er-Decke).
- **Kein Plugin-System** (decisions.csv 2026-08-14): der Patch IST die Erweiterungsfläche.

## Scheibenfolge (Ralph, je 1 Zyklus)

1. **#590 `VoiceTimbreProfiler`** — der reine Kern, TEST-FIRST (Sägezahn-Spektrum → 1/k;
   Zwischen-Bin-F0; Nyquist-Nullen; NaN-Grenze; Median-Aggregation; count==64 gegen
   `harmonicCount`). 2 Dateien, keine UI, kein Engine-Call.
2. **#591 hörbarer Beweis** — Control-Pfad: Profil → `loadTimbreProfile`, Sequenzierung
   nach dem Recall-Drain (Falle 1), Debug-Tür hinter vorhandenem Slot.
3. **#592 Capture-Fluss** — Mic-Fenster (2048+, gebatcht), Fortschritt/Voicing-Anzeige
   im `soundPanel`, Arm-Schalter nach #277-Form.
4. **#593 Persistenz** — `SynthPatch.voiceProfile: [Float]?` via decodeIfPresent +
   Label; Council-Gate vor diesem Schritt (persistiertes Körper-Derivat).
5. **#594 Voice→Color** — Centroid/Rauheit → Visual-Palette (Leaf, Freeze-Gesetz).

**NICHT bauen:** TTS · Fremdstimmen-Import · Heilungs-Sprache · neues Modal · Server.
