# PLAN — Color-Music (Cousto octave), Tone Systems & Visual Menu Rework

Founder request (2026-06-25): rework the immersive-visual menu (categories, design);
deepen the prism/rainbow → natural light on regular devices; add Hans Cousto's color
octave; expand Tonarten — planet tones, jazz/blues/rock scales, church modes, more
tone systems/tunings. Deep research + test simulation + cleanup, crash-free, no freeze.

Brand guardrail (locked): ship the MATH (octave transposition f×2ⁿ → light; planetary
orbital periods → pitch). Label everything as **creative tuning / acoustics / astronomy**.
NO healing / chakra / Solfeggio / "energy" claims. (Consistent with prior founder
exchange on therapeutic claims.)

Tasks: #13 Cousto color-octave · #14 scales+tonesystems+planet tones · #15 visual menu
rework · #16 prism/natural-light · #17 test-sim + stability.

---

## RESEARCH DATA (verified — see agent report; sources: Planetware/Cousto, std music theory)

### A) Cousto color-octave
- Formula: `f_color_THz = f_tone_Hz × 2^40 / 1e12`  (2^40 = 1_099_511_627_776). λ_nm = 299792.458 / THz.
- Visible band ≈ 380–780 nm ≈ 384–789 THz (≈ one octave → 12 tones tile the full hue wheel).
- **Color = pitch class.** Drive hue from the 12-step wheel; let exact λ follow the played
  frequency (so A440 / A432 / maqam all color correctly). Micro-shift hue by cents dev optionally.
- Note → Cousto color name → approx sRGB (perceptual approximation; gamut-limited — label "approx"):

  | Note | color name      | sRGB (R,G,B)   |
  |------|-----------------|----------------|
  | F#   | Rot             | (255,0,0)      |
  | G    | Rotorange       | (255,69,0)     |
  | G#   | Orange          | (255,140,0)    |
  | A    | Gelborange      | (255,191,0)    |
  | A#   | Gelb            | (255,255,0)    |
  | H/B  | Gelbgrün        | (173,255,47)   |
  | C    | Grün            | (0,200,0)      |
  | C#   | Blaugrün        | (0,200,160)    |
  | D    | Blau            | (0,90,255)     |
  | D#   | Blauviolett     | (75,0,200)     |
  | E    | Violett         | (148,0,211)    |
  | F    | Rotviolett      | (200,0,140)    |

  (Cousto ref tuning is C≈432-based; the named hue↔note boundaries are Cousto's convention,
  the octave math is exact physics — present accordingly.)

### B) Planet tones (Cousto) — Hz + nearest note (A440), store Hz as authoritative
Sun 126.22 (B2 +38¢) · Moon synodic 210.42 (G#3 +23) · Mercury 141.27 (C#3 +33) ·
Venus 221.23 (A3 +10) · Earth YEAR/"OM" 136.10 (C#3 −31) · Earth DAY 194.18 (G3 −16) ·
Earth Platonic year 172.06 (F3 −25) · Mars 144.72 (D3 −25) · Jupiter 183.58 (F#3 −13) ·
Saturn 147.85 (D3 +12) · Uranus 207.36 (G#3 −2) · Neptune 211.44 (G#3 +31) · Pluto 140.25 (C#3 +21).
⚠️ FIX CLAUDE.md: OM 136.10 = Earth **year** (C#), NOT sidereal day (~194.18 Hz, G).

### C) Scales (semitones from root)
Church modes: Ionian 0,2,4,5,7,9,11 · Dorian 0,2,3,5,7,9,10 · Phrygian 0,1,3,5,7,8,10 ·
Lydian 0,2,4,6,7,9,11 · Mixolydian 0,2,4,5,7,9,10 · Aeolian 0,2,3,5,7,8,10 · Locrian 0,1,3,5,6,8,10.
("Duchords" = church modes / Kirchentonarten — confirmed.)
Melodic-minor modes: MelMinor 0,2,3,5,7,9,11 · Dorian♭2 0,1,3,5,7,9,10 · LydAug 0,2,4,6,8,9,11 ·
LydDom 0,2,4,6,7,9,10 · Mixo♭6 0,2,4,5,7,8,10 · Locrian♮2 0,2,3,5,6,8,10 · Altered 0,1,3,4,6,8,10.
Bebop: dom 0,2,4,5,7,9,10,11 · maj 0,2,4,5,7,8,9,11.
Symmetric: dim(W-H) 0,2,3,5,6,8,9,11 · dim(H-W) 0,1,3,4,6,7,9,10 · whole-tone 0,2,4,6,8,10.
Blues: minor 0,3,5,6,7,10 · major 0,2,3,4,7,9.
Rock/pop: maj pent 0,2,4,7,9 · min pent 0,3,5,7,10 · nat minor 0,2,3,5,7,8,10 · harm minor 0,2,3,5,7,8,11.

### D) Microtonal/world tunings (cents, 12 steps unless noted)
Pythagorean: 0,90,204,294,408,498,612,702,792,906,996,1110
5-limit just: 0,112,204,316,386,498,590,702,814,884,996,1088
1/4-comma meantone: 0,76,193,310,386,503,580,697,773,890,1007,1083
19-EDO: i*1200/19 (19 steps) · 31-EDO: i*1200/31 (31 steps)
Maqam Rast: 0,204,355,498,702,906,1057 · Bayati: 0,150,294,498,702,792,996
Pelog(7): 0,120,270,540,670,785,945 · Slendro(5): 0,231,474,717,955 (family, variable)
Shruti(22): 0,90,112,182,204,294,316,386,408,498,520,590,610,702,792,814,884,906,996,1018,1088,1110
(EDO/Pythagorean/just/meantone = precise; maqam/pelog/slendro/shruti = "one common tuning", tradition-variable.)

### E) Brand-safe UI copy
- Feature name: "Cosmic Octave" / "Planet & Color Tuning" (NOT "Healing Frequencies").
- Tooltip: "Transposes a pitch up by octaves (×2ⁿ) into the visible-light band and shows the
  matching colour. Based on Hans Cousto's Cosmic Octave (1978). A creative tuning."
- Planet picker: "Tunes the root to the octave-equivalent of a planet's orbital period (Cousto).
  Astronomy-derived pitch — for sound design."
- Disclaimer: "Creative tuning inspired by astronomy and acoustics. Not therapeutic."

---

## CODE GROUNDING (exact edit points)
- Scales: `Sequencer/MusicalKey.swift` — `enum Scale` (10 cases: major/minor/dorian/phrygian/
  lydian/mixolydian/pentMajor/pentMinor/harmonicMinor/chromatic). Add cases → `.intervals`,
  `.displayName`, `.shortTag`. `MusicalKey` (root+scale; quantize/degree). `MusicStyle.scale`
  maps genres→scale.
- Tunings: `Sequencer/MicrotonalTuning.swift` — `struct TuningSystem` (id/name/family/degreesCents/
  periodCents) + static `library` (edo12/24/19/31, just-major/minor, pythagorean, maqam rast/bayati/
  hijaz, gamelan slendro/pelog, hirajoshi, bohlen-pierce) + `named(_:)`. Add entries to `library`.
  Applied via `applyTuning()` → `pitchClassCents(root:)` → `synth.setTuningCents`.
- Pickers in `EchoelStudioView.swift`: `genrePicker`, `tonartRow` (key+scale), `tuningRow`
  (tone system, @AppStorage "toneSystemID"), `kammertonRow` (a4Hz), in `compositionPanel`.
- Tone→colour: **`Studio/SpectralColor.swift`** already does pitch-class→OKLCH hue (hueOffsetDegrees=0),
  CIE-1931 wavelengthToLinearRGB, chord OKLab mixing, `visibleWavelength(forToneHz:)` octave-transpose.
  **`Views/MetalBioView.swift`** shader: `toneWavelengthNm` (octave transpose to ~555nm),
  `wavelengthToRGB` (CIE), `toneCloudColour` (odd-harmonic clouds), warm-desaturation (≈3500K),
  `echoelSaturate`/`echoelHue`. BioUniforms: toneHz/hueShift/saturation/style/styleB/blend.
  NEW: `Studio/ColorOctave.swift` = Cousto note→colour wheel + octave math (this cycle).
- Visual menu (`EchoelStudioView.swift`): `visualPanel` → `visualLookStrip` (Donuts/Rings/Chladni/
  Plasma/Water), `visualBlendControls`, `visualPresetRow` (`VisualPreset.factory`), `musicColourRow`
  (uses SpectralColor), 6× EchoelValueField, `bioVisualSection`. Duplicated in `visualVJOverlay`
  (fullscreen). @AppStorage: visual.style/styleB/blend/spectralDonuts/preset.
- Design system: `EchoelPanel` (DisclosureGroup card), `EchoelValueField` (mandatory param control),
  `EchoelTheme` (bg/surface/text/dim/border/fill/accent; font; radius 8/12), category helpers
  `toolGroup` (2-col grid), `groupHeader`, `labeledRow`.
- ⚠️ METADATA-OVERFLOW DISCIPLINE: any new panel/section added to a launch-rendered aggregate
  (soundControls / visualPanel) MUST be `AnyView(...)`-wrapped (see 10.76.20 fix). Never inline
  a new deep `some View` into those VStacks.
- Tests exist: `SpectralColorTests`, `TuningReferenceTests`, `VisualPresetTests`. New: `ColorOctaveTests`.

## DONE
- ColorOctave core + ColorOctaveTests (Cousto note→colour wheel + octave math, any-tuning lookup).

## LAMBDA SEQUENCE (one verified TestFlight ship each; AnyView panel boundaries kept)
1. #13 Cousto color-octave as the visual's color basis (MetalBioView + a ColorOctave core + test). Verify launch + colors.
2. #16 Prism/natural-light deepening on that basis.
3. #14a Scales: add church modes + jazz + blues + rock + symmetric to Scale model + picker (+tests).
4. #14b Tone systems: add microtonal tunings to TuningSystem library (+tests).
5. #14c Planet tones: planetary root tuning (+ honest copy) (+tests).
6. #15 Visual menu rework: categories + design.
7. #17 runs throughout: tests, cleanup, perf/no-freeze, metadata-overflow guard.
