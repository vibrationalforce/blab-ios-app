# PLAN — EchoelWeather-Synth (task #59)

Founder (2026-07-16): *"Bei Wetter waere geil einen eigenen Synth zu machen der auch
sagt, wie das Wetter ist und dementsprechend anders klingt und Noten generiert."*
→ An own weather SOUND (patch layer) + honest weather DISPLAY (real values) + notes
influenced by weather. **Brand law: the body stays the LEADING modulation source;
weather is a second, optional, slow source.** No esoteric copy. WeatherKit surfaces
carry the Apple " Weather" attribution (already done at the toggle).

Status: read-only investigation 2026-07-16. No code changed.

---

## 1 · DATA TRUTH — what exists TODAY (a lot more than the task assumed)

The old "WeatherProvider was removed" note is stale — the E3a/E3b weather stack was
**re-built and is live** on this branch:

| Piece | File | Truth |
|---|---|---|
| `WeatherSnapshot` | `Sources/Echoelmusic/Core/WeatherMood.swift` | Pure Codable value: `temperatureC: Double`, `condition` (8-case enum: clear/partlyCloudy/overcast/fog/drizzle/rain/storm/snow), `isDaylight: Bool`, `windKph: Double`. **NO pressure field today.** WeatherKit raw-string → coarse case mapping is pure (Linux-testable), unknown → nil → provider falls back `.partlyCloudy`. |
| `WeatherProvider` | `Sources/Echoelmusic/Core/WeatherProvider.swift` | `@MainActor @Observable`, gated `#if canImport(WeatherKit) && canImport(CoreLocation)`. ONE coarse fetch per session start via `WeatherService.shared`, 30-min in-memory cache (`isCacheValid` pure + tested), in-flight dedupe, never throws (every failure → nil, composition plays weatherless). Location = the SAME opt-in coarse fix as the place token (`LocationNamer.lastFix`). Injected `.environment(weatherProvider)` in `EchoelmusicApp.swift:385`. |
| Gate | `Core/StudioDefaultKeys.swift:80` | `weather.enabled` StudioDefault, **default false** (opt-in). `@AppStorage` in `EchoelStudioView:95`. |
| `WeatherMood` mapping | `Core/WeatherMood.swift` | Pure + tested (`Tests/EchoelmusicTests/WeatherMoodTests.swift`, 237 lines). `Contribution` = `structureSalt` (FNV-1a over descriptor `"rain-day-cold"` — stable per weather situation, NEVER `Hasher`) + SOUND targets `darknessTarget/livelinessTarget/tensionTarget` (MoodProfile 0…1 space) + VISUAL `hue/saturation/glow/motion`. 8 per-param intensity mixers (`WeatherMood.Param`, persisted `weather.mix.<param>`, default 0.5 / structure 1.0, `blend()` crossfade, 0 = bit-identical off). |
| Wiring | `Studio/EchoelStudioView.swift` | On Start: `fetchWeatherFlavour()` (~3312) → `weatherContribution` @State. Structure salt XORs `BioComposer.Input.structureSeed` (~3628); warmth/energy/drama blend into `mood` before compose (~3673-3682). UI = Session panel `weatherRow` (~1815): toggle + **descriptor token only** ("Now: rain-day-cold") + mixer groups (`WeatherMixRow` uses `EchoelValueField` ✓) + Apple attribution `Link` ✓. |
| Entitlement | `Echoelmusic.entitlements` | `com.apple.developer.weatherkit = true` **already present**, portal-registered per founder 2026-07-10, validated by the v10.79.141 archive. |

### The GAP task #59 actually asks for
1. **Own synth SOUND** — weather never touches TIMBRE today (patch = `style.synthPatch`
   / factory preset only; weather only nudges mood + skeleton salt + visuals).
2. **"Sagt, wie das Wetter ist"** — the UI shows a log token (`rain-day-cold`), not
   honest real values (temp °C, condition word, wind km/h, day/night, pressure).
3. **Notes from weather** — partially exists (salt = skeleton, energy = density via
   liveliness); missing: a **scale hint** and register bias, surfaced honestly.
4. **Per-track opt-in** — no lane field lets ONE track follow the sky.

---

## 2 · REUSE MAP (patterns the slices plug into)

- **`GenrePatches.swift` (Sequencer/)** — the exact precedent: pure `MusicStyle →
  SynthPatch` data. **Its location law applies to us**: a file touching `SynthPatch`
  (DSP/) + Core/Sequencer types must live in **Sequencer/ (or Core/), never DSP/**
  (AUv3 target globs DSP/ only; DSP/ must not import Core/Sequencer types).
  Also its enum-string law: `noiseColor/spectralShape/envelopeCurve/timbreProfile`
  must be **Capitalized EchoelDDSP rawValues** ("Pink", "Dark", "Bell", "Exponential")
  or `SynthPatch.apply(to:)` silently ignores them — guard with a GenrePatchesTests-style test.
- **`WeatherMood.Param` mixer machinery** — adding a case auto-appears in the
  Session-panel mixer UI (`weatherMixGroup` filters by `.domain`) with persistence,
  default intensity, explanation line, `EchoelValueField` row. Free UI for a new
  "Timbre" influence.
- **`LaneComposerInput.apply` + `TimelineLane.genreOverride/mood/variationSeed`**
  (ce248bf pattern) — per-track optional override seam, `decodeIfPresent` back-compat,
  pure + Linux-tested (`LaneComposerInputTests`). Lane patch flows to voices via
  `TimelineRegionPlayer.slotPatchSink` (task #23 spine).
- **`ModulationEngine`** — the control-plane routing pattern (100 ms poll, closure
  destinations). NOT needed for v1: weather changes at most every 30 min — a
  fetch-time application (like today's mood blend) is the right rate; no new runtime.
- **`SeededRNG` (SplitMix64) + FNV-1a fold** — determinism law. Seed any weather
  variation from `WeatherMood.contribution(for:).structureSalt`; **NO `Date.now`**
  anywhere in the pure core or tests.
- **`ArrangeTimelineView.ArrangeModal`** — the ONE allowed sheet enum; the per-track
  toggle goes inside the existing `.lane(TimelineLane)` editor sheet (no new case
  needed, certainly no new root sheet — `EchoelStudioView`'s chain has ZERO free slots).

---

## 3 · MAPPING TABLE — weather dimension → param → audible effect → displayed number

All offsets are **clamped deltas on the lane/genre base patch** (never absolute
replacements — the user's/genre's sound survives), scaled by the new `timbre`
intensity mixer (0 = bit-identical off). Deterministic: same snapshot → same patch.

| Weather dimension | Synth param (SynthPatch) | Audible effect | Displayed (honest, science-first) |
|---|---|---|---|
| `temperatureC` band (freezing/cold/mild/warm/hot) | `brightness` −0.15…+0.10 · `filterCutoff` ×0.7…×1.15 | cold = darker, muted; hot = open, present | `14.2 °C` |
| `condition = rain/drizzle` | `noiseLevel` +0.06/+0.03, `noiseColor = "Pink"` · `reverbMix` +0.08 | soft rain-wash air in the voice, wetter space | condition word "Rain" |
| `condition = fog/overcast` | `filterCutoff` ×0.75 · `reverbDecay` +0.4 s · `attack` +0.05 | veiled, slow-blooming pads | "Fog" |
| `condition = storm` | `filterResonance` +0.08 · `filterLFORate` ×1.5 · `filterLFODepth` +0.06 | restless, edgier filter movement | "Storm" |
| `condition = snow` | `noiseLevel` +0.04, `noiseColor = "Violet"` · `brightness` +0.05 | icy, glassy shimmer | "Snow" |
| `condition = clear` | `noiseLevel` −0.02 · `harmonicLevel` +0.04 | clean, open, consonant | "Clear" |
| `windKph` band (<8/<20/<40/≥40) | `vibratoDepth` +0…+0.05 · `filterLFODepth` +0…+0.08 | still air = steady tone; wind = audible motion | `22 km/h` |
| `isDaylight` | `reverbDecay` +0.3 s at night · hint `registerBias −12` at night | night = deeper register, longer tail | `day` / `night` |
| condition+daylight+temp band (existing salt) | `BioComposer.Input.structureSeed` XOR (SHIPPED) | same sky = same harmonic skeleton | descriptor kept in logs only |
| condition → **scale hint** (`Hints.scale`) | suggestion only: clear→`.lydian`, partlyCloudy→`.major`, overcast→`.dorian`, fog→`.pentatonicMinor`, drizzle/rain→`.minor`, storm→`.phrygian`, snow→`.harmonicMajor` | offered, never forced — one tap applies it to the session key (body/user stays boss) | "Sky suggests: Dorian" + Apply button |
| `windKph`+condition → `Hints.densityBias` | already flows via `energy` mixer → `liveliness` (SHIPPED) | wind = busier note placement | same wind number |
| `pressureHPa` (NEW optional field) | **display only in v1** — no mapping until we claim one | — | `1013 hPa` (row absent when nil) |

Interplay rule (write into the core's doc header): **weather = SLOW flavour**
(per-session fetch, 30-min cache — patch offsets, skeleton, scale hint);
**bio = FAST expressive control** (per-take mood/detail/velocity/tempo — untouched).
Weather offsets are computed and applied on the **control plane at Generate /
patch-load time** via the existing `SynthPatch.apply` path — zero audio-thread work,
zero new runtime loops.

---

## 4 · ATOMIC SLICES (Ralph Wiggum — ≤3 files each, pure core first)

### S1 — `WeatherPatch` pure core + tests (Linux CI; ZERO behavior change) ← smallest shippable
- **NEW** `Sources/Echoelmusic/Sequencer/WeatherPatch.swift` (Sequencer/, NOT DSP/ — GenrePatches location law):
  - `WeatherPatch.apply(_ w: WeatherSnapshot, to base: SynthPatch, intensity: Float) -> SynthPatch`
    — clamped deltas per table §3, intensity 0 returns `base` byte-identical
    (reuse `WeatherMood.blend`), all values clamped into SynthPatch's real ranges.
  - `WeatherPatch.Hints` (`scale: Scale?`, `registerBias: Int`) + `hints(for:)`.
  - `WeatherPatch.summary(for:) -> String` — the honest sentence from REAL values:
    `"Rain · 14.2 °C · 22 km/h wind · day"` (+ `" · 1013 hPa"` when present).
    Plain measured numbers, no adjectives, no weather-woo.
- **EDIT** `Core/WeatherMood.swift`: add `pressureHPa: Double?` to `WeatherSnapshot`
  (optional with default nil in init → Codable stays back-compat, synthesized
  `decodeIfPresent` for optionals; **NOT folded into descriptor/salt** — salt
  stability "same sky, same skeleton" must hold). Add `case timbre` to
  `WeatherMood.Param` (domain `.sound`, label "Timbre", explanation
  "Shifts the synth voice toward the sky — rain adds air, cold darkens, wind moves the filter.",
  default 0.5) — the mixer UI/persistence appears for free.
- **NEW** `Tests/EchoelmusicTests/WeatherPatchTests.swift`: determinism (same
  snapshot → identical patch, twice); intensity-0 byte-identity; all 8 conditions ×
  day/night × 5 temp bands stay in-range (no NaN, clamped); enum-string
  capitalization guard (every emitted `noiseColor`/`spectralShape` round-trips
  through the EchoelDDSP enums — GenrePatchesTests pattern); `summary` contains the
  literal numbers; snapshot decode without `pressureHPa` key succeeds; **no Date()**.
- 3 files. Gate: `swift test --filter Weather`.

### S2 — Honest display: the synth SAYS the weather (UI, slot-reuse)
- **EDIT** `Studio/EchoelStudioView.swift` `weatherRow`: replace
  `"Now: \(weatherDescriptor)"` with `WeatherPatch.summary(for: snapshot)` — real
  values, monospaced-digit, read-only (measurements are display, not parameters —
  `EchoelValueField` stays for the adjustable mixers, which already use it ✓).
  Keep the attribution Link untouched. Add the scale-hint line + one "Apply"
  button that sets the session key's scale (explicit user action — body/user leads;
  never auto-applied).
- **EDIT** `Core/WeatherProvider.swift`: fetch `pressure` (`c.pressure.converted(to:
  .hectopascals).value`) into the new optional field.
- 2 files. No new sheet, no root-body high-frequency reads (weather updates ≤1×/30 min
  and only inside the already-conditional Session panel — swiftui-render-safety OK).

### S3 — The weather SOUND: timbre offsets on the global generate path
- **EDIT** `Studio/EchoelStudioView.swift`: at the generate patch-resolution points
  (~575 / ~2813 / ~2865 — extract ONE helper `effectivePatch(for style:)`), when
  `weatherEnabled && weatherContribution != nil`, wrap:
  `WeatherPatch.apply(snap, to: base, intensity: WeatherMood.Param.timbre.currentIntensity())`.
  Keep the raw snapshot alongside `weatherContribution` in the existing @State fetch.
- **EDIT** `Tests/EchoelmusicTests/WeatherPatchTests.swift`: helper-level test that
  intensity 0 → base patch unchanged (regression lock for "weather off = bit-identical").
- ≤2 files. Applied at Generate on the control plane; voices get it through the
  existing `synth.apply(patch)` / `slotPatchSink` routes — attach-before-start
  untouched, no runtime graph mutation.

### S4 — Per-track opt-in: one lane follows the sky
- **EDIT** `Sequencer/Timeline.swift`: `TimelineLane.weatherFollows: Bool`
  (init default false, `decodeIfPresent ?? false` — pre-existing docs unaffected,
  never pruned).
- **EDIT** `Sequencer/LaneComposerInput.swift` (or the fan-out caller): when
  `lane.weatherFollows`, fold `Hints.registerBias` + apply `WeatherPatch.apply` to
  that lane's effective patch (lane.patch ?? genre patch) before `slotPatchSink`.
  A lane with the flag false stays byte-identical (test).
- **EDIT** `Studio/ArrangeTimelineView.swift`: toggle row "Follows the weather"
  inside the EXISTING `.lane` editor sheet (ArrangeModal untouched — no new case,
  no new root sheet), visible only while `weather.enabled` is on; row repeats the
  attribution requirement is already met at the master toggle.
- 3 files + test additions ride in the LaneComposerInputTests file next cycle if 3-file cap binds.

### Deferred (needs founder ask, not in this task)
- Pressure → any audible mapping (claim only what ships — display-only in v1).
- Weather as a `ModulationEngine` source (only worth it if weather ever updates fast).
- Forecast/hourly data (quota + scope creep; one coarse current fetch stays the law).

---

## 5 · COUNCIL (one line per seat)

- **Architect:** Sequencer/ placement + reuse of Param-mixer/LaneComposerInput seams keeps this a data feature, not a new system — no new runtime, no new sheet. ✔ proceed.
- **DSP Purist:** offsets are clamped control-plane patch deltas through the existing `SynthPatch.apply`; render blocks never see weather — guard the Capitalized enum strings or offsets silently no-op.
- **Vision-Keeper:** copy states the MECHANISM only ("Rain adds a pink-noise wash") — never "the sky plays your soul"; body remains the headline modulator; sharpest risk = scale-hint auto-apply, so it is tap-to-apply only.
- **Shipper:** smallest slice S1 is pure + Linux-CI-green with zero UI and zero behavior change — ship it first and the rest can trail cycle by cycle.
- **Skeptic:** WeatherKit entitlement/portal is already validated (10.79.141 archive), but simulator/offline/no-fix returns nil — every slice must be provably silent-no-op then; also `Param.allCases` UI means the new `timbre` case surfaces instantly, so its explanation string ships in the same commit.
- **User-Advocate:** the display must show exactly the numbers the mapping consumes (temp/wind/condition/day-night) — an honest instrument, not a weather app; keep the row inside the Session panel where place/weather already live.

Gate: **proceed** — S1 first, one slice per cycle.

---

## 6 · ATTRIBUTION / ENTITLEMENT CHECKLIST

- [x] `com.apple.developer.weatherkit` in `Echoelmusic.entitlements` (portal-registered, archive-validated 10.79.141).
- [x] Apple " Weather" attribution + legal link at the weather toggle (`weatherRow`) — REQUIRED on every surface showing weather-derived state; the per-track row (S4) points to the same master surface; if weather values ever appear elsewhere, the link must appear there too.
- [x] Location = opt-in coarse fix only (`LocationNamer.lastFix`); no fetch without it; nothing persisted beyond the 30-min in-memory cache.
- [x] Quota: 1 fetch / session-start / 30 min ≪ 500k/month free tier.
- [ ] S2: confirm WeatherKit `currentWeather.pressure` unit conversion on device (simulator has no WeatherKit auth — expect nil path).
- [ ] Release-notes claim discipline: say "weather shapes the synth voice" only once S3 ships; S1/S2 alone = display + plumbing.
