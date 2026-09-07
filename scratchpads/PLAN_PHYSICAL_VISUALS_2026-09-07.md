# PLAN — Physikalisch echte Visuals (Wasserklangbilder / Cymatics)

**Founder-Ask 2026-09-07:** "Können wir die Visuals noch um mehrere physikalisch
assoziierte Visuals ergänzen? Echte Wasserklangbilder etc. Deep Research, Generative
Art, ultracode."

Quelle: Ultracode-Schwarm `wf_e1d68fc7-fca` — 14 Agenten (4 Physik + Lead, 4 Repo +
Lead, 3 adversariale Widerleger, 1 Synthese), 2,77 M Token, 354 Werkzeugaufrufe.
Jede Behauptung unten ist vom Lead ODER von einem Widerleger gegengeprüft; was nicht
hielt, steht unter GETÖTET und darf nicht still wieder auftauchen.

**STAND: Scheibe 1 ist GEBAUT (#1078, `3353ad5a`).** Scheiben 2–5 warten; 3 ist
founder-gated.

---

## Kopfzeile des Schwarms

> Slice 1 is not Chladni — style 1 is unreachable (I traced all three filters), so "fixing" it ships zero pixels. The smallest move that makes a picture a real user sees MORE physically true is giving the SHIPPED Water look the capillary dispersion law λ ∝ f^(−2/3): no menu row, no flash-budget row, no test pin moved, zero new per-fragment transcendentals.

---

## Gemessene Tatsachen, die stehen

- THE m==n FLOOD IS REAL, AND I REPRODUCED IT AT 3,000,000 LOG-STEPS. When m == n the antisymmetric basis is identically zero (cos(a1x)cos(a1y) − cos(a1x)cos(a1y) ≡ 0), so abs(s)*amp = 0, smoothstep(0,w,0) = 0, and fieldChladni returns 1.0 across the whole frame. FIVE contiguous runs over the code's ACTUAL clamp (20–20000 Hz, MetalBioView.swift:751): 445.7–484.0 (m=n=4) · 588.1–704.0 (5) · 776.0–1351.2 (6 then 2) · 1489.4–1782.9 (3) · 2166.4–2352.5 (4) = 18.68 semitones. A#4 (466.16) floods; A4 (440) and B4 (493.88) do not.

- BUT STYLE 1 IS UNREACHABLE, AND I TRACED EVERY FILTER MYSELF — this is the single fact that reorders the whole plan. (1) LookBlendMap.sequence(from:) drops any persisted index not in `library` (LookBlendMap.swift:~126, `library.contains(where: { $0.index == i })`). (2) The customizer is `ForEach(LookBlendMap.library, id: \.index)` (EchoelStudioView.swift:5967), so only Rings/Water/Aurora/Depth can be offered. (3) The launch snap `if !spectralDonuts, !sliderLooks.contains(visualStyle) { visualStyle = sliderLooks.first ?? 3; visualStyleB = 0; visualBlend = 0 }` (EchoelStudioView.swift:1344-1347) rewrites a hand-edited 1 away, with the `else if` covering the B slot. The only two other writers (EchoelStudioView.swift:6016, FloatingVisualWindow.swift:414) write `m.a` from LookBlendMap.blend(at:sequence:), i.e. always a library index. Default is 5 (StudioDefaultKeys.swift:216). NOTHING in Sources ever writes 1.

- THE SHIPPED WATER LOOK IS REACHABLE, IS IN THE DEFAULT SEQUENCE, AND HAS THE SAME CLASS OF DEFECT — this is the opening nobody in either team found. `fieldWater` sets its spatial frequency with `float scale = mix(4.0, 7.0, breath);` (MetalBioView.swift:~1666-1678). The wavelength of a WATER look is driven by breath and by nothing else; the sounding pitch never reaches it. LookBlendMap.defaultSequence = [3, 5, 7] and 3 is Water, so this look is on screen for every user out of the box.

- THE CAPILLARY LAW FITS THE SCREEN WITH ENORMOUS HEADROOM — no aliasing anywhere in the musical range, which I measured rather than assumed. Solving ω² = (gk + σk³/ρ)·tanh(kh) at ω = 2π(f/2), h = 3 mm: λ = 8.00 mm at C2 (65.4 Hz), 3.02 mm at C4, 1.19 mm at C6, 0.47 mm at C8. Local exponent d ln k / d ln f measured 0.6756 over 200–800 Hz, converging to 2/3. Anchoring scale = 4.5 at C3 and scaling by k(f)/k(C3): period = 1342 px at C2, 817 px at C3, 199 px at C6, 79 px at C8 (pf ∈ [−1,1] over ~1170 px). The narrowest case in the whole 20–20000 Hz clamp stays ~8× above the ~10 px/period aliasing floor.

- CHANGING `scale` COSTS ZERO FLASH BUDGET, AND THAT IS THE STRUCTURAL REASON SLICE 1 IS FREE. `scale` multiplies the SPATIAL coordinate only — the phase-bearing terms are `t = 0.4·phase` and its 0.7t / 1.1t partners, all untouched. So the Water row in FlashGuardTests (0.68, folds:false → 1.70 Hz) stays valid verbatim, and `testReachableLookSetIsExactlyTheBudgetedOne` and `LookBlendMapTests`' [0,3,5,7] pin are not touched at all.

- THE GUIDED-EDGE PLATE IS AN EXACT EIGENFUNCTION, so the ladder is real physics and not a Rayleigh–Ritz approximation. For w = cos(aπx)cos(bπy), ∇²w = −(a²+b²)w so ∇⁴w = (a²+b²)²w identically; and ∂w/∂n ∝ sin(mπ) = 0 at all four edges — the SLIDING/GUIDED end condition. Hence ω = √(D/ρh)(π/L)²(m²+n²) is exact for the basis the shader already draws. I recomputed S = (2L²/π)√(ρh/D) = 0.036797 s for 300×300×1 mm aluminium and the ladder head: (1,0) 27.2 · (2,0) 108.7 · (2,1) 135.9 · (3,0) 244.6 · (3,1) 271.8 · (3,2) 353.3 · (4,0) 434.8 · (4,1) 462.0 · (4,2) 543.5 · (4,3) 679.4 · (5,0) 679.4 Hz. The (4,3)≡(5,0) degeneracy at N=25 is real for this basis.

- THE UNIFORMS HEADROOM IS NOT UNKNOWN — I counted it. `sed -n '1347,1364p' | grep -o 'float [a-zA-Z0-9_]*' | wc -l` → 95 floats = 380 bytes, far under the 4 KB setFragmentBytes limit. Adding one scalar for k(f) costs 384 B. Both teams left this UNMEASURED and two workers guessed different numbers.

- THE RENDER TARGET IS 60 fps (MetalBioView.swift:458, `view.preferredFramesPerSecond = 60`; the only other hit at :879 is a comment). CLAUDE.md's PERFORMANCE table and the task brief both say 120 and are stale. This doubles the frame budget — so cost was never the reason to refuse any of this; scope is.

- THE MENU COST OF A NEW LOOK IS ONE CHIP, NOT A ROW — measured, and it is the answer to the compactness tension. `LookBlendMap.library` has exactly ONE production consumer: a horizontal `ScrollView` of chips at EchoelStudioView.swift:5967. The SLIDER fades through `sliderLooks` (default [3,5,7]), which does NOT lengthen unless the founder toggles the new chip in. So a library row = +1 chip in an existing horizontal scroller, +0 rows, +0 captions, +0 sheets, +0 slider length.

- THE RENDERER BINDS ZERO TEXTURES (`git grep 'setFragmentTexture|texture2d<|makeTexture' -- Sources` → nothing), so any LUT would be new pipeline plumbing. The one MTLTexture in Sources is VisualRecorder.swift:219, on the capture path, not the shader's. Reject LUTs — but on plumbing and accuracy, not on 'the first texture this renderer has ever had', which is the wrong reason since MetalBioView already flips `framebufferOnly` for that capture.

- BOTH TRIPWIRES ARE NON-BLOCKING. FlashGuardTests.swift and LookBlendMapTests.swift live in Tests/EchoelmusicTests/, and Tests/CISmoke does carry flash guards (TheFlashCeilingIsOneNumberTests, FlashSlewIsPerSecondTests, GlitterCannotBecomeAFlashTests, VisualLookTruthTests) but NONE of them pins the look set or the four budget rows. Combined with auto-merge waiting for no gate, an unbudgeted look can reach `main` — so a door slice must carry both pins in the same commit.

- THE spf DOMAIN WARP FALSIFIES ANY WAVELENGTH CLAIM, and it is a live user control. `spf = pf + [sin(3.7y+sin(2.9x)), sin(3.1x+sin(2.3y))]·0.09·structureAmt` (MetalBioView.swift:1832-1841) is passed to BOTH looks (:1863, :1869). Its own comment defends only the FLASH property, which is true and irrelevant here. `structureAmt` is the persisted 'Structure' row read by three surfaces — so the fix is to CONDITION the claim on structureAmt = 0 in the doc comment, never to silently pass `pf` and kill the dial.

---

## Scheiben

### Scheibe 1 — Give the SHIPPED Water look the real capillary dispersion law (λ from pitch, not from breath)

**Was.** `fieldWater`'s spatial frequency is `mix(4.0, 7.0, breath)` — the wavelength of a water look is set by breath and the sounding pitch never reaches it. Replace it with the Faraday capillary wavenumber k(f), computed once per frame on the CPU and passed as ONE new uniform float. Breath moves from wavelength to DRIVE AMPLITUDE (the 0.18 coefficient on the wave sum), which is the physically correct channel: drive frequency sets λ, drive amplitude sets whether and how strongly a pattern appears. The doc comment states the validity conditions AND that the λ(f) law holds at structureAmt = 0, because the spf warp bends the local wavelength.

**Dateien.** `Sources/Echoelmusic/Views/MetalBioView.swift` · `Tests/CISmoke/TheWaterLookObeysCapillaryDispersionTests.swift`

**Physik.** Faraday parametric instability, subharmonic response: solve ω² = (gk + σk³/ρ)·tanh(kh) at ω = 2π·(f_drive/2). VALIDITY: linear inviscid Benjamin–Ursell, principal Mathieu tongue, single-frequency vertical forcing, weak damping. Above ~60 Hz drive tanh(kh) ≥ 0.998 for h = 2–5 mm (measured), so it reduces to the pure capillary branch ω² ≈ σk³/ρ ⇒ k ∝ f^(2/3); I measured the local exponent d ln k/d ln f = 0.6756 over 200–800 Hz, converging to 2/3. λ per octave ×0.630. The ½ is a LENGTH fact, not a rate fact: using f instead of f/2 makes the pattern 2^(2/3) = 1.5874× too fine — a full octave of fineness, measurable with a ruler on a still frame. NOT VALID and must not be claimed: multi-frequency (chord) forcing, where combination tongues open and superposition fails. This slice drives it with the single eased toneHz, honestly, and says so.

**Angetrieben von.** `uniforms.toneHz` — clamped 20–20000 Hz (MetalBioView.swift:751), eased tau 0.45 s (f_c = 0.354 Hz) at MetalBioView.swift:1091, written every draw frame at 60 fps. Its upstream is the sounding note, i.e. the note/glide rate, not the bio frame. `breath` is a bio channel applied at ~1 Hz (10 Hz poll, deduped on frame.timestamp), eased tau 0.35 s.

**Blitz-Budget.** ZERO CHANGE — 0.68, folds:false → 1.70 Hz, and the existing FlashGuardTests row stays valid verbatim. The reason is structural, not a coincidence: `scale` multiplies the SPATIAL coordinate only. The phase-bearing terms are t = 0.4·phase and its 0.7t/1.1t partners, none of which is touched. Breath's new role is a multiplicative amplitude on an already-summed non-phase-bearing quantity, and breath carries no phase. No non-monotone operation is added, no second phase-bearing factor is multiplied in, so no sideband and no fold. This is the only slice in the plan that needs no budget re-derivation.

**Kosten.** ZERO new per-fragment transcendentals. k(f) has the closed capillary form k = (ρω²/σ)^(1/3) and is solved once per frame on the CPU (or by 40-step bisection on the full relation if the gravity term is kept below 60 Hz). Shader-side it is one extra uniform multiply. Uniforms struct 95 → 96 floats, 380 → 384 bytes, far under the 4 KB setFragmentBytes limit — counted, not guessed. Against a 60 fps / 16.7 ms frame, not 120.

**Wächter.** Tests/CISmoke (blocking, unlike FlashGuardTests). THREE claims: (1) the exponent — k(2f)/k(f) = 2^(2/3) ± 2 % over 100–1000 Hz, so a future 'simplification' to a linear or log map goes red; (2) the sampling floor — the rendered period stays ≥ 60 px at the 20 kHz clamp (I measure 79 px at C8), so no future retune can alias the pattern into moiré; (3) the flash multipliers of fieldWater are UNCHANGED, pinned by string against the shader source, so the FlashGuardTests row cannot silently go stale.

**Risiko.** The look's FEEL changes for every user out of the box — Water is index 3 and sits in `LookBlendMap.defaultSequence = [3,5,7]`. That is the point (it is the only way to ship physical truth without touching the menu) and also the risk: a bass note now renders a visibly coarser net than a lead. Mitigation is that the range is gentle and bounded (period 1342 px at C2 → 199 px at C6, both comfortable), and the change is a two-line revert. NOT device-verified — no Swift toolchain, no GPU ran, nothing compiled.

### Scheibe 2 — Kill the m==n flood: exact guided-edge plate ladder in fieldChladni

**Was.** Replace `m = 2 + floor(fract(b*0.50)*5)` / `n = 2 + floor(fract(b*0.37+0.3)*5)` — two unrelated hashes that collide over 18.68 semitones and render a solid flood — with the plate's own inverse: N = S·f, then the integer pair (m,n) with m > n ≥ 0 nearest N. m > n is enforced by construction, so the identically-zero basis becomes unreachable. Computed on the CPU, passed as two uniform floats. KEEP `amp = 0.7 + 0.3·sin(0.5·phase)` — it is the look's only bio channel. Correct the doc comment's object: this is a SLIDING/GUIDED-edge plate, a symmetry cell, not the free-edge rig of a real Chladni experiment.

**Dateien.** `Sources/Echoelmusic/Views/MetalBioView.swift` · `Tests/CISmoke/ThePlateModesAreNeverDegenerateTests.swift`

**Physik.** Kirchhoff–Love: D∇⁴w + ρh·∂²w/∂t² = 0, D = Eh³/12(1−ν²). For w = cos(mπx)cos(nπy) on the unit square, ∇⁴w = (a²+b²)²w EXACTLY and ∂w/∂n ∝ sin(mπ) = 0 at all four edges — so ω = √(D/ρh)(π/L)²(m²+n²) is exact for this basis, not a Rayleigh–Ritz approximation. Inverse: N = m²+n² = S·f with S = (2L²/π)√(ρh/D) = 0.036797 s for 300×300×1 mm aluminium (recomputed). VALIDITY: h/L < 1/20, kh ≪ 1, small deflection — all satisfied for a 1 mm plate across the audio band. HARD INVARIANT: m ≠ n, because the minus sign selects the diagonally antisymmetric partner of a symmetry-degenerate pair and that combination vanishes identically when m = n. HONEST LIMITS to state in the comment and never in marketing: the guided plate is a symmetry cell, not a free plate; many N are not sums of two squares, so most frequencies have no exact mode; and S is a chosen plate geometry, so the law fixes how the pattern CHANGES with pitch, never how fine it is in absolute terms.

**Angetrieben von.** `uniforms.toneHz`, same channel and same measured rate as Slice 1: 60 fps writes, eased tau 0.45 s, clamped 20–20000 Hz. At 4 kHz, N = 147 so m ≤ 12 — about 97 px/period, no aliasing anywhere in the band (the plate is immune where the dish would need care).

**Blitz-Budget.** UNCHANGED at 0.5, folds:false → 1.25 Hz — the joint-safest field in the shader. `s` contains no `phase` token, so `abs(s)` folds a purely spatial quantity and creates no temporal extrema; `amp` is strictly positive ([0.4, 1.0], never crosses zero) and multiplies OUTSIDE the abs, so it is one phase-bearing factor times a constant with no sideband. THE UNBUDGETED HAZARD, stated rather than hidden: the mode indices are discrete, so a pitch crossing a ladder step repaints the whole frame — a full-area luminance change riding toneHz, which `effectiveFieldHz` cannot model (it describes ONE oscillator on `phase`). It is NOT fixed in this slice, deliberately: it is unobservable while the look is undoored, and the CPU slew limiter that bounds it belongs in Slice 3 where it becomes reachable. The tau 0.45 s ease attenuates a 6 Hz vibrato ~17× but does not rate-limit a slow wide bend.

**Kosten.** Two hash computations and two floor/fract calls leave the fragment; two uniform reads replace them. Net per-fragment work is unchanged or slightly lower (still 5 transcendentals: 4 cos + 1 sin). NOT claimed as a performance win — no GPU ran, nothing compiled, and the Chebyshev multi-mode scheme is deliberately NOT taken here because it introduces uniform-driven array indexing, a different cost class.

**Wächter.** Tests/CISmoke. TWO claims: (1) sweep 20–20000 Hz at fine log steps and assert m ≠ n at every step — the flood becomes structurally unreachable rather than merely absent; (2) assert the ladder is monotone non-decreasing in f, so a future 'tuning' of S cannot reintroduce a sawtooth. The guard must NOT assert the look is doorless (#364) — it says in its failure message which prose moves if it is doored.

**Risiko.** HONEST AND LOAD-BEARING: this changes ZERO pixels for ZERO users today, because style 1 is unreachable by three independent filters I traced line by line. It is a prerequisite that makes Slice 3 a one-commit door instead of a door plus a physics rebuild, and it removes a real correctness bug from code the repo still compiles and still describes as 'a real physical pitch→pattern mapping'. Do not present it to the founder as a shipped improvement.

### Scheibe 3 — The door — one library row, its budget row, and both pins in the SAME commit (FOUNDER-GATED)

**Was.** Add the repaired plate to `LookBlendMap.library` under an honest name, add its budget row to `testEveryReachableLookObeysTheThreeHzLaw`, and move the two equality pins that go red on the first line of the change. Add the CPU slew limiter (0.35 full-scale transitions/second on the mode indices) plus an explicit FlashGuard constant, because the mode snap only becomes observable here. Menu cost, measured: +1 chip in the ONE existing horizontal scroller at EchoelStudioView.swift:5967; the slider sequence is `sliderLooks` (default [3,5,7]) and does NOT lengthen unless he toggles the chip in.

**Dateien.** `Sources/Echoelmusic/Studio/LookBlendMap.swift` · `Tests/EchoelmusicTests/FlashGuardTests.swift` · `Tests/EchoelmusicTests/LookBlendMapTests.swift`

**Physik.** No new equation — this slice ships Slice 2's ladder. It DOES ship the honest copy: 'exact eigenmode of a square plate with sliding edges'; nodal lines; mode numbers rise with the sounding pitch by the plate's own law. Never 'physikalisch exakt' unqualified, because S is a chosen geometry and the guided plate is not a free Chladni rig.

**Angetrieben von.** Nothing new. The look's inputs stay toneHz (60 fps writes, tau 0.45 s), coherence (~1 Hz applied) for line width, and the bio-driven `phase` (≤2.5 Hz) for the breathe.

**Blitz-Budget.** New table row: 0.5, folds:false → 1.25 Hz, with 1.75 Hz of margin against the 3.0 Hz law — the safest reachable look, less than half of Aurora which ships today at exactly 3.00 Hz with zero margin. PLUS a slew-limit assertion for the mode snap, which the one-oscillator model cannot express: 2R + R = 1.05 Hz at R = 0.35, following the heartbeat-bloom precedent (an explicit constant with its own assertion) rather than a fifth table row. CRITICAL, and it is the one thing that must not be skipped: never blend this look against Aurora without per-pixel photometry — `effectiveFieldHz` explicitly cannot model two additive oscillators, and the A↔B crossfade is exactly that.

**Kosten.** No shader change at all — Slice 2 already shipped the field. The per-frame CPU adds a mode solve plus a slew step on the main actor that also runs the meters and the eased uniforms; unmeasured, and it must not be called free.

**Wächter.** The two pins ARE the guard and both are in the NON-blocking Tests/EchoelmusicTests while auto-merge waits for no gate — so carrying them in this commit is not tidiness, it is the only thing preventing a red guard landing on `main`. While in that file, fix its docstring's Scope figure: it cites ~3.0 Hz to make its own safety argument, and re-deriving from the shader gives 3.90 Hz (fastest term 0.78 via t*1.3, folded ×2 by abs(p.y − wave)). A safety guard understating a retired look in the unsafe direction is the same defect class it exists to catch.

**Risiko.** TWO, and both are founder-shaped. (1) SCOPE: the live visual epic excludes new looks BY NAME ('D10 NOT IN THIS EPIC: new looks', AUDIT_VISUAL_2026-09-06.md:280), and its parent ask is his own 'kompakter und übersichtlicher'. This is founder-versus-founder and only he can rank it — see founder_questions. (2) REGISTER: he retired this look as 'passt nicht zum Vibe', and a physically correct version still renders hard nodal lines. Slices 1 and 2 are deliberately ordered so that if the answer is 'no', the physically-true water picture has already shipped and nothing is wasted.

### Scheibe 4 — Split the geometry claim from the colour claim wherever the app or the site makes one

> ⛔ **NACHGEMESSEN 2026-09-07 (#1090): BEREITS WAHR, nicht zu bauen.** `LightScienceInfo.swift:65`
> trägt die Trennung seit jeher wörtlich („The transposition is exact mathematics and an artistic
> convention: sound and light are different physical phenomena, so no health or cosmic effect is
> implied"). Beide Store-Beschreibungen sagen „transposed by whole octaves" / „oktavweise
> transponiert" ohne Mechanismus-Behauptung. Der einzige „cosmic octave"-Treffer im Repo ist
> `docs/version.json:38`, ein CHANGELOG-Eintrag (v10.19.0) unter der Zeile „HISTORY NOTE … entries
> below this line are a historical record"; die Seiten lesen aus dieser Datei nur `d.version`
> (Cache-Bust), nichts rendert die Liste. Geschichte wird nicht umgeschrieben. Der vorgeschlagene
> Wächter `TheColourClaimNamesItsConventionTests` existiert nicht und wird nicht angelegt: ein
> Negativ-Scan auf ein Wort, das nur in einem Historien-Eintrag steht, wäre #491 (er träfe die
> Zeile, die seine eigene Rücknahme erklärt). Was BLEIBT: die Store-Wächter verbieten Solfeggio/
> chakra/healing bereits (`testTheProducerlessChannelsAreNotNamedAsDrivers` ist die Nachbar-Nadel).

**Was.** The tone→wavelength step is an octave transposition with no physical mechanism; the wavelength→sRGB step is a genuine CIE 1931 path (multi-lobe CMF fit → XYZ → linear sRGB → gamut map). Everywhere the app or the site describes the visual as physical, say which half is which. Reuse the one defensible sentence that already exists verbatim in-app rather than writing a new one. Remove the 'cosmic octave' string from docs/version.json — correctly labelled as hygiene in a machine-read manifest, since no page renders the `changelog` key.

**Dateien.** `Sources/Echoelmusic/Studio/LightScienceInfo.swift` · `docs/version.json` · `Tests/CISmoke/TheColourClaimNamesItsConventionTests.swift`

**Physik.** CIE 1931 2° colour-matching functions → XYZ → linear sRGB, with the octave fold anchored at 780 nm and the purple line closed between 640 and 420 nm. VALIDITY: the colorimetry is exact for a monochromatic stimulus; the transposition from an acoustic frequency to an optical one is a CONVENTION, because nothing carries an acoustic oscillation into the electromagnetic band. A further limit worth stating once: after the field and colour are computed the fragment applies a warm tint, a warm lift, a coherence gain, a luminance floor of 0.35, then user Saturation, Hue SHIFT and Intensity — a hue shift on a spectrally-derived colour is a lie by construction, so 'physically correct colour' is false at the last step for any user who moves that dial.

**Angetrieben von.** No runtime signal — this is copy and a manifest string. It changes no pixel and no rate.

**Blitz-Budget.** None — no field, no colour path, no phase touched. 0.00 Hz.

**Kosten.** Zero per-fragment. Zero uniform. Zero shader.

**Wächter.** Tests/CISmoke, positive form only: assert the in-app science sentence still contains the convention clause, and assert the banned-term list (cosmic octave, Solfeggio, chakra, healing frequency, water memory, Emoto) matches nowhere in the visual copy or docs/version.json. Deliberately NOT a negative scan on CLAUDE.md (#491 — that file quotes retracted claims on purpose and would fail its own retraction).

**Risiko.** Lowest of the plan and near-zero to revert. The only trap is over-claiming the version.json find as an App-Store-class red line: it is a machine-read key nothing displays, and inflating it would drag a website sweep into a slice that does not need one.

### Scheibe 5 — Close the two guard gaps that any future colour-bearing look would walk through

**Was.** The 3 Hz law is enforced on the scalar FIELD only; COLOUR travels a separate path in the fragment and no test covers it, so a look whose colour oscillates would pass the four-row table while flashing. And WCAG's saturated-red-flash clause is encoded nowhere reachable: FlashGuard has no red term, and the only red-flicker ban in the repo sits in the doorless Session/Entrainment subsystem. Add a colour-path rate term to FlashGuard and a red-flash predicate, both with their own blocking assertions.

**Dateien.** `Sources/Echoelmusic/Core/FlashGuard.swift` · `Tests/CISmoke/TheColourPathHasAFlashBudgetTests.swift`

**Physik.** W3C WCAG 2.3.1: a general flash is a pair of opposing relative-luminance changes ≥ 10 % where the darker state is < 0.80, over more than 25 % of the visual field within 10 degrees; a red flash is any opposing transition involving a saturated red, and it is counted SEPARATELY from luminance. VALIDITY: the existing `isFlash` tests a relative-luminance delta only — correct as far as it goes, and structurally blind to the red clause. Note the mitigating structure for a future thin-film or interference look: the three channels fold at different periods, so LUMINANCE is smoother than any single channel — which is why the red clause needs its own term rather than a tighter luminance bound.

**Angetrieben von.** No runtime signal — this is a law and its assertions. It bounds every future look rather than reading anything today.

**Blitz-Budget.** This slice IS the budget. It does not add a phase term; it adds the ability to express one that today's model cannot see.

**Kosten.** Zero per-fragment, zero uniform. Pure Swift value logic plus tests.

**Wächter.** Its own assertions, and they must be in Tests/CISmoke — the existing four-row table is in the NON-blocking suite and is precisely why an unbudgeted look can reach `main`. Pin the RELATIONSHIP (ceiling read from the constant, never re-typed), following the existing precedent where re-typing 2.5 left a whole proof green while Aurora went to 3.6 Hz.

**Risiko.** It may go red on something already shipping, which would be a finding rather than a failure — and the honest response is to report it, not to loosen the constant. Low reversibility risk: it adds law and tests, touches no render path, and can be reverted without touching a pixel.

---

## Fragen, die nur der Founder beantworten kann

1. SCOPE, AND ONLY YOU CAN RANK IT — it is your own ask against your own ask. 'Cymatics-Go' has been an open gate since 2026-07-10 (you asked for Wasserklangbilder two days after retiring Cymatics; the plan was written that day and the go-ahead never came). But yesterday's visual epic excludes new looks BY NAME, derived from your 'kompakter und übersichtlicher … alles zu einem Ding zusammen gefasst'. Which wins: open D10 for one new look now, or after the one-unit merge lands? Measured cost if you open it: +1 chip in one existing horizontal scroller, and the slider does NOT get longer unless you toggle the chip in.

2. REGISTER, AND A MEASUREMENT CANNOT SETTLE IT. You retired Cymatics as 'technische Figuren, nicht der weiche Vibe'. The physically real PLATE still renders hard black-and-white nodal lines — that is what the physics IS. The physically real WATER DISH is a continuous refractive surface, which is the register of the three looks that survived. Slice 1 gives you the true water picture with no menu change at all. Do you want the plate look at all, or is the water dish the only register you want this in?

3. HONESTY VERSUS DRAMA, AND IT IS A TASTE CALL. A real 1 mm aluminium plate has Q ≈ 10²–10³: it shows NOTHING for more than 99 % of a continuous pitch glide, and figures snap into existence only at discrete resonances. Making it show something continuously requires choosing Q ≈ 8–20, which the material does not have. Do you want the honest version (silent between resonances — dramatic, and genuinely 'echt'), or the dramatised Q (always something on screen, and then we say so in the comment and never in the marketing)?

4. DOES SLICE 1 NEED YOUR GO AT ALL? It adds no look, no chip, no row, no caption and no sheet — it makes the Water look you already ship physically true, with its wavelength driven by the sounding pitch through the capillary dispersion law instead of by breath. I read it as inside the current visual epic ('physikalisch korrekte Darstellung'), not as a new look. Confirm, or hold it with the rest.

---

## NICHT bauen (physikalisch echt, für dieses Produkt trotzdem falsch)

- A DEPTH SLIDER FOR THE WATER DISH — a knob that provably does nothing. I measured tanh(kh) ≥ 0.998 at 200 Hz for h = 2–5 mm, so a shallow dish is already DEEP water for every audio ripple; depth only re-enters below ~20 Hz drive (17.98 vs 22.17 mm, a 23 % spread). Shipping it would be a physically-labelled control with no effect, which is worse than no control.

- A BESSEL OR THIN-FILM LOOKUP TEXTURE — physically fine, architecturally wrong here. The shader binds zero textures and is a runtime-compiled string fed only by setFragmentBytes; a LUT means texture lifetime, device-loss rebuild, MTKView reconfiguration and a second thing VisualRecorder's framebufferOnly flip must reason about. McMahon nodal radii are 0.005–0.44 % at i=1 for ~6 FLOP and zero transcendentals; the Hankel two-term form covers x ≳ m+4 at ~1 % of envelope. Inline beats a texture on both accuracy and plumbing.

- REACTION–DIFFUSION (Turing patterns) — chemical kinetics with no honest driver, and it needs frame-to-frame state (ping-pong textures plus a second pass), which breaks the single stateless fragment dispatch outright. The look would be beautiful and the physics would be about something that is not happening in the room.

- RAYLEIGH–BÉNARD CONVECTION — strictly dominated. Its hexagons look like Faraday hexagons, and the only temperature signal in the app is the phone's own thermal throttling, so the 'physical' input would be the device complaining about the render.

- FERROFLUID / ROSENSWEIG SPIKES — there is no magnetic field anywhere in Echoel. The drive would be a metaphor wearing an equation, which is precisely the defect this whole plan exists to remove.

- ANY DOPPLER OR MOTION-DRIVEN FIELD — nothing moves. `motionEnergy` is written as 0 at all six BioSampleFrame construction sites, `ModulationMatrix.hasProducer` returns false for `.motion`, and the shader's `motion` uniform is a UI look multiplier, not a velocity. A Doppler shift computed from a constant zero is a fake with extra steps.

- KUNDT'S TUBE OR SCHLIEREN — correct physics, wrong register. One-dimensional grey bands are the Lissajous/Scope aesthetic that has now been rejected three times, most recently by you.

- DIFFRACTION / AIRY PATTERNS FROM THE SOUNDING PITCH — it conflates an acoustic frequency with an optical wavelength, and it would contradict the app's own documented tone→colour convention in the same frame.

- A CHORD-DRIVEN FARADAY DISH — the physics does not license it. Benjamin–Ursell's subharmonic result is the principal tongue for SINGLE-frequency forcing; multi-frequency forcing opens harmonic and combination tongues whose winner depends on amplitude ratio and phase, and a parametric instability with a threshold and mode competition cannot be built by superposing per-partial linear responses. (Superposition IS legitimate for the PLATE, which is a linear forced response — that asymmetry is the whole reason Slice 2 is a plate and Slice 1 is a single-tone dish.)

- A RE-DOORED CHLADNI THAT IS STILL SAND LINES ON BLACK — the honest warning, and the reason this plan leads with water. You retired it once for its register, not for its physics, and a physically correct rebuild that still renders hard high-contrast nodal figures on a rigid square plate will be rejected again, correctly, for the identical reason. Worse, the version the physics team recommended DELETES the breathing term, which is the look's only bio channel — making the 'honest' version both more static and less bio-reactive than the decorative one it replaces, in an instrument whose one sentence is 'your body plays it'.

- A SECOND FFT PATH INTO MetalBioView FOR A CHORD-DRIVEN FIELD — not yet, and not as 'no plumbing'. MetalBioView holds no AudioEngine reference at all, and its second construction site (ExternalDisplayScene) injects a different environment set, so an optional read there resolves nil and the beamer would silently render a different picture from the phone. The master-mix ring and its main-thread FFT are real and reusable; wiring them is its own slice with its own cross-scene decision, not a free line in the draw loop.

---

## Von den Widerlegern GETÖTET — nicht still wiederbeleben

- THE PHYSICS LEAD'S FLAGGED DISCOVERY IS ITSELF THE ERROR, and acting on it would make the shader LESS correct. It claimed k = (π/L)√(m²+n²) is the simply-supported eigenvalue wrongly paired with a free-plate basis, and that free-free roots (m+½)π must be substituted — hence 'ship S as a tuned artistic constant, do not sell the degeneracy'. cos(mπx) is neither: it has w' = 0 and w'' ≠ 0 at the ends, the GUIDED/sliding condition. I verified ∇⁴w = (a²+b²)²w exactly and ∂w/∂n ∝ sin(mπ) = 0 at every edge. The ladder is EXACT for the shipped basis. Substituting free-free beam roots would bolt a cosh+cos eigenvalue onto a cosine eigenfunction — an inconsistent pairing where an exact one exists.

- 'THE SHIPPED EQUATION ASSUMES A CENTRE-CLAMPED SQUARE PLATE, THE CLASSIC CHLADNI/WALLER RIG' — killed, and the brief and the in-shader comment carry the same error. The minus sign selects the combination antisymmetric under (x,y)→(y,x) out of a symmetry-degenerate pair; the node at the centre is a CONSEQUENCE of that antisymmetry, not evidence of a clamp. Deriving a rig from it inverts the logic. Honest label: 'exact eigenmode of a square plate with sliding edges' — more accurate AND a weaker marketing claim than anyone wrote.

- 'FIX fieldChladni FIRST — IT IS ALREADY COMPILED, ALREADY HAS A SLOT, AND IS ALREADY BROKEN' — killed as a Slice 1. It conflates COMPILED with DOORED, this repo's most-catalogued error class. The verdict chose Chladni over the water dish precisely to avoid a `LookBlendMap.library` row, then justified it with a defect only that row exposes. Circular. And it answers the wrong question: 'ergänzen' is ADD.

- 'FLOODS THE SCREEN SOLID OVER 20.1 % OF THE MUSICAL RANGE' — killed as a headline; the denominator was shopped. 18.68 semitones is 15.6 % against the code's actual 20–20000 Hz clamp, 20.2 % against an unsourced 4200 Hz ceiling, and 47.9 % across C4–C7 where a lead melody lives. A number that moves 15.6 → 47.9 with the denominator must never lead, and it was quoted twice including in the founder-facing paragraph.

- 'THE SIGNAL ALREADY SHIPS — REUSE THOSE THREE CALL LINES IN MetalBioView'S DRAW LOOP; IT NEEDS NO NEW PLUMBING' — killed. MetalBioView has NO AudioEngine reference (`grep 'AudioEngine|audioEngine'` returns nothing); its whole dependency surface is four optional environment reads. And it has a SECOND construction site in ExternalDisplayScene, whose scene injects bus/governor/recorder/synth and no AudioEngine — so an optional read there resolves nil and the beamer would silently render a different figure from the phone, on the external-display path the founder asked for by name.

- 'RENDER THE FARADAY DISH WITH THE CHORD SPECTRUM, HALVING EACH FFT PEAK AND SUPERPOSING' — killed as physics. Benjamin–Ursell's uncoupled single-tongue subharmonic result holds for single-frequency vertical forcing of a weakly damped layer. Multi-frequency forcing opens harmonic tongues and combination resonances, and which wins depends on amplitude ratio and relative phase. Faraday is a parametric INSTABILITY with a threshold and nonlinear mode competition — superposing per-partial linear responses is exactly the fudge-dressed-as-physics this task exists to remove, one abstraction layer higher. The asymmetry nobody stated: superposition IS legitimate for the PLATE (linear forced response), and is not for the DISH.

- 'DROP THE DECORATIVE amp = 0.7 + 0.3·sin(0.5·phase) — A CHLADNI FIGURE AT FIXED DRIVE IS STATIC' — killed on product grounds even though the arithmetic is right. That term is the ONLY bio-linked temporal quantity in fieldChladni; `phase` is integrated from the bio-driven pulseHz. Delete it and heart rate reaches the field nowhere, breath is not even passed to the function, and a motionless high-contrast line drawing walks straight INTO the register complaint that retired the look. In an instrument whose one sentence is 'your body plays it', the honest version would be LESS bio-reactive than the decorative one.

- 'ALSO REQUIRED: PASS pf, NOT spf' — killed as stated. `structureAmt` is a live persisted 'Structure' EchoelValueField read by three surfaces; feeding one look the unwarped coordinate makes that dial silently do nothing on that look. This repo already paid for exactly this defect once — `LookBlendMap.detailReach` exists solely because the 'Detail' row silently does nothing on every look except Rings. The correct cost is pf + a second reach predicate + a caption + a guard pinning it, not one argument swap.

- 'THE HONEST VERSION IS CHEAPER THAN THE FAKE ONE' (2 transcendentals vs 5) — killed as a settled result. The Chebyshev recurrence identity is correct, but every figure on both sides is an op count read off Metal source with no compile, no GPU capture, no thermal run. Its own fp32-stability caveat is admitted to be a condition-number argument, not an experiment, at exactly the M=9 the ladder needs. And it silently introduces UNIFORM-DRIVEN array indexing (cx[m_j]), where every existing array index in this shader is a loop counter over fixed bounds that the compiler unrolls into registers — a different cost class, not a smaller one. Do not put 'cheaper' in front of the founder.

- 'THIN-FILM INTERFERENCE IS THE ONE CANDIDATE WHERE COLOUR IS DEDUCED, NOT MAPPED' — killed. R(λ) ∝ sin²(2πnd·cosθ/λ) is deduced from ONE scalar, the OPD. Nothing in acoustics sets n, d or θ, so whatever drives the OPD from pitch is a free choice with no mechanism — the identical defect as fract(log2(toneHz)), pushed one level deeper and made HARDER to audit because the last step really is rigorous optics. A rigorous half laundering an arbitrary half.

- 'BRAND RED-LINE HIT IN PUBLISHED COPY: docs/version.json:38' — killed as a classification. The 'cosmic octave' string is there and is worth removing, but version.json has four keys and every page's inline script reads only `d.version` for cache-busting; `changelog` is never rendered. It is hygiene in a machine-read manifest, not user-facing copy, and mis-classifying it inflates a slice with a website sweep that nothing displays.

- 'A BESSEL LUT WOULD BE THIS RENDERER'S FIRST TEXTURE EVER' — the conclusion survives, the reason does not. MTLTexture handling and a `framebufferOnly` flip already exist in this exact render path (VisualRecorder capture). Reject LUTs on accuracy and plumbing cost — McMahon nodal radii are 0.005–0.44 % at i=1 with zero transcendentals — not on a false novelty claim.

- 'THE FARADAY DISH IS THE BETTER LONG-RUN ANSWER, SHIP IT AS A SECOND REGISTER' — killed as anything near-term. Measured, it is strictly LARGER than the option it was offered against: new field function + library row + budget row against a table whose binding constraint (Aurora, 1.20, no fold) computes to exactly 3.00 Hz with zero margin + a 4096-point FFT wired across two scenes + new uniforms + both non-blocking pins + a docs sweep. Its own verdict concedes the fullscreen bar already sheds the look slider on every shipped phone. Two epics, not a slice.

- THE '120 fps' TARGET — killed by three independent readings including mine. MetalBioView.swift:458 pins 60. Note the direction: this REMOVES cost pressure rather than rescuing any cost claim.
