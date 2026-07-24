# PLAN — Ultra-Design + Brand-Konformität (Founder 2026-07-24 ultracode)

**Founder:** „Arbeite im no sleep mode ultracode ultra Design alles Echoel Brand konform ab.
User ist Komponist und Musiker. Echoelmusic = Inspiration durch Biofeedback und dessen
Umstellungen."

6-Agenten-Audit (5 Auditoren + Synthese-Lead, `ultracode-teams`) der reinen-Instrument-Front.
Lead hat jeden Fund adversarial gegen echten Source verifiziert (`file:line`) und in
reversible, gate-grüne Ralph-Slices gerankt. Ranking = Vision/Brand-Impact × Design-Gewinn ÷
(Render-Risiko + Aufwand).

## Ranked Slices (eine/Zyklus, Reviewer + Gates + NEEDS-FOUNDER-VERIFY)

1. ✅ **GESHIPPT (dieser Zyklus)** — **EchoelLux-Header-Tile Flash ≤3 Hz + Reduce Motion.**
   `HeaderMonitors.swift:337` `EchoelLuxMonitorMini`: 10-Hz-Hue-Recompute → 2.5-Hz-Cap
   (App-Ceiling, WCAG ≤3 Hz) + `accessibilityReduceMotion` hält steady. Spiegelt den schon
   gefixten Sibling `ImmersiveMonitorMini` (#112). **Hard ship-law** (Epilepsie).
2. **„Live pulse" a11y-Label → „Heart rate".** `HeaderMonitors.swift:121`. Uncodixfy verbietet
   Deko-Copy („Live Pulse" = das Muster-Beispiel); der BPM-Wert spricht schon via
   `accessibilityValue`. TINY, sicher (String).
3. **Bio-Grün-Akzent raus aus Chrome (Chip-Fills → `.text`).** `EchoelStudioView.swift:2297`
   (touchPatchChip), `:2341` (visualPresetRow), `:2220` (floating-visual toggle). EchoelTheme-
   Regel: accent = NUR live-bio/playing, nie Page-Chrome. Labels nutzen schon `.onPrimary`.
4. **Toter „Well"-Tab-Verweis raus.** `BreathGuideView.swift:191` „Start the camera in Well…"
   → „Start the camera…". Die Well/Tools/Works/Sync-Säulen existieren nicht (mehr). TINY.
5. **sessionEntryCard-Chrome von accent auf neutral.** `EchoelStudioView.swift:1050` (Icon),
   `:1069` (Border). NICHT die „Breathing Session"-Copy anfassen (siehe #124-Fold). TINY.
6. **Variations-Karte DE→EN.** `EchoelStudioView.swift:1681-1696`: „Variationen"→"Variations",
   „…dein Körper kuratiert, du wählst."→"…your body curates, you pick." usw. Copy-Konsistenz
   + on-vision (Bio-Instrument-Versprechen). Liest nur @State (kein live-bio).
7. **Visual-Fenster a11y-Copy DE→EN.** `FloatingVisualWindow.swift:760` „Finger auf die Kamera
   bringt es zum Leben…" → EN. (`:510-511` bleibt für #121/#124 — nennt die zu entfernende
   Timeline.) TINY.
8. **Chrome unter großem Dynamic Type begrenzen.** `WorkspaceView.swift:129-152` `.dynamicTypeSize(
   ...xxLarge)` + `:216-221` Titel `.lineLimit(1).minimumScaleFactor(0.7)`. Bars sind fix-
   gepinnt (50/44/40) → bei AccessibilityMedius..5 clippt/kollidiert der Titel. SMALL.
9. **Bio→Musik-Kausalität sichtbar (MEDIUM).** `EchoelStudioView.swift:~574` EIN kleiner
   Leaf-View (`BioDriveReadout`), 1-2 live cause→effect-Zeilen („Coherence 0.72 → warmer
   harmony"). **MUSS eigener Leaf sein** (Freeze-Gesetz 10.76.41/50 — nie im body/parent lesen).
   Direkt auf die Founder-Vision „Inspiration durch Biofeedback und dessen Umstellungen". Zuletzt,
   weil MEDIUM + 10-Hz-Read-sensibel.

## Bewusst VERWORFEN (Lead-Verifikation — nicht erneut aufmachen)
- Raw-Slider→EchoelValueField (`EchoelStudioView:2385`/`FloatingVisualWindow:522`): **Founder-
  Override** — der VJ-Crossfade-Slider ist bewusst KEINE Studio-Param-Row (`FloatingVisualWindow:513-518`).
- MeditationView-Streak/Wellness-Gamification: Surface ist bewusst TÜRLOS — Brand-Drift-Reservoir,
  erst bei Re-Dooring anfassen.
- loopLengthSelector/„Keep last"/„New idea"/Flow|Loop-Label-Platzierung: real, aber **#124 baut
  genau diesen Home gerade um** → in #124 falten, nicht als Solo-Slice (Merge-Konflikt-Risiko).
- Sheet-Count-Kommentar „~18"→„11": nur Kommentar, nicht selbst enumeriert → Doc-Hygiene später.
- StudioZoom-auf-Chrome + Header-Glyph-Skalierung: niedriger Wert / bewusster Layout-Schutz-Tradeoff.

## Status
- ✅ Slice 1 geshippt (dieser Zyklus) — Reviewer + Gates laufen.
- ▶ Nächste No-Sleep-Zyklen: 2→3→4→5→6→7→8→9 der Reihe nach, je Reviewer + Gates.
- Alles NEEDS-FOUNDER-VERIFY hinter TestFlight-Freeze.
