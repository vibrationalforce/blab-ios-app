# PLAN — Visual Finishing (nach B9b-Gamma-Fix) — Research-Sweep 2026-07-13

Quelle: 3-Agenten-Research (Apple-Ground-Truth · OSS-Visualizer-Pipelines · Pro-Tool-Radar),
Workflow wf_e227cd59. Alle Netz-Zugriffe erfolgreich (networkLimited=false). Kontext: Founder
"immer noch grau" → B9b sRGB-Drawable-Fix (455c951, v185). DMMW-Ziel, scoped auf Farbe/Finishing.

## Apple-Ground-Truth — bestätigt den B9b-Fix VOLLSTÄNDIG
- `.bgra8Unorm_srgb` auf View + Pipeline = der komplette, Apple-korrekte Fix. GPU wendet die
  exakte piecewise-sRGB-Kurve beim Write an (nicht pow 1/2.2), dekodiert bei Reads, blendet linear.
- `layer.colorspace` auf iOS: **nil = korrekt** (Bytes gelten als display-referred sRGB; iOS
  mappt selbst nach P3-Panel). NICHT linearSRGB setzen (Doppel-Interpretation = crush/wash).
- Shader darf KEIN eigenes pow-Gamma zusätzlich machen (sonst doppelt kodiert → milchig).
- Blit `_srgb`→`bgra8Unorm`-CVPixelBuffer: copy-kompatibel, kopiert ROHE (kodierte) Bytes →
  AVAssetWriter bekommt endlich display-referred Frames (Aufnahmen waren bisher zu dunkel).
  Bedingung `framebufferOnly=false` beim Blit-Source: haben wir (readyToCapture-Flip).
- **WARNUNG aus der OSS-Welt:** Legacy-Visualizer (MilkDrop & Ports) wurden im FALSCHEN, aber
  konsistenten Raum getuned — nach einem korrekten Gamma-Fix wirken alte Tunings oft "zu hell/
  milchig". Falls Founder das sagt: NICHT sRGB zurückdrehen, sondern V-F1 (Tone-Map) + Re-Grade.

## Die geordnete Finishing-Leiter (Impact ÷ Aufwand, je EIN Zyklus)
- **V-F1 — ACES-Filmic-Tone-Map statt Terminal-Clamps (~6 Shader-Zeilen, lizenzfrei
  [Narkowicz-Fit]):** heutige `clamp()`s (energy 1610, intensity-Cap, S-Kurve, outCol) kappen
  Highlights hart → Puls sättigt zu flachem Neon statt weiß-heiß auszurollen. Filmic-Schulter =
  Resolume/Notch-Look, gratis Desaturation-zu-Weiß. Display-Transform NACH der physikalischen
  Ton→Licht-Rechnung → Wissenschafts-Gesetz unberührt. **Erst nach Founder-Verify von v185.**
- **V-F2 — OKLab-Interpolation für ästhetische Blends** (Cloud-Mix/Gradients, NICHT das
  Wellenlängen-Gesetz): RGB-Lerp geht durchs Grau in der Mitte — OKLab-Lerp bleibt bunt.
  SpectralColor hat Ottosson-OKLab-Code SCHON — pure Funktion wiederverwenden.
- **V-F3 — Triangular-Dither** (1–2 Zeilen): heutiger 1/255-Hash-Dither → triangular verteilt;
  OLED-Banding bei langsamen Bio-Gradienten ist DER sichtbare Amateur-Artefakt.
- **V-F4 — Zurückhaltende Vignette + globaler Grade** nach dem Tone-Map (~10–15 % Randabdunklung).
  Finishing muss unsichtbar sein (CLAUDE.md-Glow-Verbot bleibt).
- **WATCH — P3/EDR ("wow"-Ausbau, eigener Council-Zyklus):** (a) P3 via `bgra10_xr_srgb`
  (HW-Encode bleibt, 64 bpp = 2× Bandbreite) · (b) EDR: `rgba16Float` +
  `wantsExtendedDynamicRangeContent` + `extendedLinearDisplayP3`; `currentEDRHeadroom` pro Frame
  abfragen + hineintonemappen; MUSS in AdaptiveQuality/ResourceGovernor (EDR zuerst degradieren)
  + Flash-Safety wird KRITISCHER (EDR-Pulse sind physisch heller). iOS 26: HDR-Screenshots gehen.
  Kein neues EDR bei WWDC25 (Metal 4: FrameInterpolation/Neural — nichts Farb-relevantes).
- **Bloom: DEFER** (Glow-Ästhetik in CLAUDE.md gebannt; wenn je, dann linear-HDR energie-erhaltend).

## Palette-Wissen (für spätere Look-Zyklen, lizenz-sicher)
- iq-Cosine-Palette `a + b·cos(2π(c·t+d))` — 4×float3 = unendliche geschmackvolle Gradients,
  trivial bio-fahrbar. Wissenschafts-Colormaps (viridis/inferno/magma, CC0): Luminanz steigt
  MONOTON mit dem Wert → Energie liest sich als Helligkeit. MilkDrop-Feedback-Decay (0.96–0.98)
  = der Signature-Trail-Look (Butterchurn MIT = beste lesbare Referenz; NUR reimplementieren).
