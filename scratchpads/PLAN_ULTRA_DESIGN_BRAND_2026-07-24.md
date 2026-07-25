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

## Status — No-Sleep-Lauf (2026-07-24/25)
- ✅ **Slice 1** `689dc5c` — EchoelLux Flash-Policy-Parität (Reduce Motion + 10→2.5 Hz), ehrliches
  Framing (kein harter Content-Cap — Content-Slew ist #127-Follow-up). ui-state-reviewer PASS.
- ✅ **Slices 2/4/7** `54a19d9` — Copy/a11y: „Live pulse"→„Heart rate", toter „Well"-Verweis raus,
  Visual-Fenster-a11y DE→EN. Pure Strings, audit-lead-verifiziert.
- ✅ **Slices 3/5** `8cd175c` — Bio-Grün-Akzent raus aus Studio-Chrome (Chip-Fills + Session-Karte
  → neutrale Tokens). Reine Color-Token-Swaps, Diff exakt 5 Zeilen.
- ✅ **Slice 6** `3f73435` — Variations-Karte DE→EN (inkl. densityWord). „your body curates, you pick".
- ✅ **Slice 8** `d8392b4` — Dynamic-Type-Clamp auf die fix-hohen Chrome-Bars (Group→xxLarge),
  Instrument behält volle a11y-Skalierung (enger gescoped als der Audit-Vorschlag). ui-state PASS.
- ⏸ **Slice 9 (BioDriveReadout) — HELD-FOR-FOUNDER**, NICHT geshippt. Konflikt mit **B3-Entscheid
  (2026-07-12)**: der Founder ENTFERNTE die always-on `BioStripView` vom Home („Header-Puls-Monitor
  ist der at-a-glance-Ersatz"). Ein neues always-on Bio→Musik-Element unter dem Transport würde ein
  bewusst entferntes Muster wieder einführen. Die Bio→Musik-Kausalität existiert bereits LESBAR als
  reine statische `BioSoundMapping.all` (Bio/BioSoundMapping.swift, „Coherence → heller · harmonischer"
  usw.) im erreichbaren Bio-Guide + Bio-Dropdown. **Founder-Frage:** soll der Home eine always-on
  Bio→Musik-Zeile tragen (gegen B3) — oder reicht die Kausalität im Bio-Dropdown/Guide (B3-konform)?
  Sichere Alternative ohne B3-Bruch: `BioSoundMapping` IM Bio-Dropdown zeigen (kein neues always-on).

Alles NEEDS-FOUNDER-VERIFY hinter dem TestFlight-Freeze (Render/Launch/Pixel-Fit nur am Gerät).
8/9 Slices geshippt + gate-grün; #9 bewusst gehalten (Founder-Entscheid-Konflikt).
