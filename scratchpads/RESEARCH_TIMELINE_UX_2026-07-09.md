# Timeline-UX Deep-Research — Kernergebnisse (2026-07-09, wh7dc5fkc, 78 Agenten)
Voll-JSON: RESEARCH_TIMELINE_UX_2026-07-09.json. Verifiziert (3-Voter adversarial):
1. SNAP-MODELL (hoch, Apple-Doc 101913): GarageBand-iOS zoom-gekoppelt — Snap DEFAULT AN;
   Pinch auf Max-Zoom + nochmal = "Snap off"-Modus (sichtbar), rauszoomen = wieder an.
   Für Profis ZUSÄTZLICH expliziter Magnet-Toggle (nicht zu Max-Zoom zwingen).
   → Echoel: magneticSnap(zoom-abhängige magnetTicks) + Toolbar-Magnet + Zoom-Kopplung.
2. VIDEO-ZUM-TAKT (hoch, FCP-Guides): Beat-Grid opt-in PER CLIP (iPad: touch-and-hold →
   Enable Beat Detection); Einrasten NUR wenn Snapping an. Echoel-Vorteil: UNSER Grid IST
   schon das musikalische Raster — kein Detection-Schritt nötig, nur Magnet an/aus.
3. WELLENFORM (verifiziert): NIE Roh-PCM zeichnen. Min/Max je Pixelspalte + innerer
   RMS-Körper (zweischichtig = "professioneller" Look), mehrere Zoom-Stufen-Caches
   (MaxChannel/AvgChannel-Muster), vDSP_desamp/Accelerate → bestätigt WaveformCache-Plan.
