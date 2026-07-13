# PLAN — Mastering-Kette (Founder-Ask 2026-07-13)

Founder: "Als mastering chain brauche ich für verschiedene musikstile und Anwendungen
gute onboard Einstellungsmöglichkeiten und auch die Einbindung von auv3 Effekten als
Inspiration: Fabfilter, brainworx, multiband clipper, DOCtron IMC, Neve, ssl, tegeler
creme, multiband limiter. Aber auch für spatial audio Formate ohne Effekte und
gainreduction auf dem Master."

## Ground Truth (verifiziert im Code)
- **Onboard-Master heute:** `AutoMixChain` = masterMixer → EQ → AutoGain → Apple
  PeakLimiter (brick-wall, BEWUSST immer an) → mainMixer. LUFS-Ziele −14/−9/−23
  (Streaming/Club/Broadcast), 4 Tonal-Presets (balanced/warm/bright/transparent),
  danach −1 dBFS True-Peak-Trim (AudioEngine:331ff).
- **AUv3 auf dem Master EXISTIERT SCHON:** `AUv3Host.loadedMasterEffects` — Kette
  zwischen Main-Mixer und Output, verarbeitet den GESAMTEN Mix; UI in
  `AUv3BrowserView` (effectTarget == .master). D.h. FabFilter/DOCtron/Brainworx etc.
  sind als USER-Plugins heute einsetzbar — Problem ist AUFFINDBARKEIT (= Mandat-Item 3).
- **Fehlt onboard:** Multiband (Comp/Clipper/Limiter — Apple PeakLimiter ist
  single-band) · mehr Stil-Charaktere · ein SPATIAL-Master-Modus, der Limiter +
  Trim ehrlich BYPASST (heute ist der Limiter by design nie abschaltbar).

## Leitplanken
- Inspiration = KOLLABIEREN-NICHT-KOPIEREN: FabFilter/Neve/SSL/Tegeler sind
  Referenz-CHARAKTERE. In-App-Copy NIE Fremdmarken nennen (Brand-/Markenrecht):
  Stile heißen z. B. "Transparent · Warm Console · Glue · Punch · Tape/Creme-artig"
  → eigene Namen, ehrliche Beschreibung.
- Onboard-DSP = Swift, zero deps (kein JUCE). Multiband = Linkwitz-Riley-Splits +
  vorhandene Kompressor-/Clipper-Bausteine (DSP/, AUv3-isoliert, pure, test-first).
- **Spatial-Deliverable-Gesetz:** Objekt-/ADM-Ausgabe braucht UNBERÜHRTE Dynamik —
  Limiting/GR passiert downstream im Renderer. Der Spatial-Modus muss Limiter + Trim
  + AutoGain bypassen und das im UI ehrlich sagen ("Master untouched — für
  Objekt-/Binaural-Render"). Safety: Bypass nur in diesem expliziten Modus.

## Zyklen (nach Automation-Spur, außer Founder priorisiert um)
M1. **Spatial-Clean-Master-Modus** (klein): AutoMixChain.mode = .mastered | .spatialClean;
    bypass EQ+Gain+Limiter+Trim; ehrliches UI-Label; Tests (Bypass = bit-transparent).
    Reviewer: audio-thread + dsp.
M2. **Stil-Presets erweitern** (Charakter-Kurven auf bestehender EQ/Comp-Basis, pro
    Genre-Familie; EchoelValueField-Rows; keine Fremdnamen).
M3. **Multiband-Kern** (DSP/, pure): LR4-Split 3-Band + Comp/Clipper/Limiter pro Band,
    test-first, un-verdrahtet (Release bit-identisch), dann Verdrahtung als eigener Zyklus.
M4. **Master-AUv3-Tür sichtbar machen** = Teil von Mandat-Item 3 (QA + Sichtbarkeit).

## Offen beim Founder
- Reihenfolge: Automation zu Ende zuerst (Default) oder Mastering vorziehen?
- M3-Ambition: 3-Band reicht? (DOCtron-IMC-artig "ein Regler" vs. Profi-Detail)
