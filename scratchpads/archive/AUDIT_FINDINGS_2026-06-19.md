# Bug/Optimization Audit — 2026-06-19

Triage of a parallel code audit (DSP/Audio, Sequencer, Bio/Sync, Studio/Core) plus
the website. Each finding was re-verified against the actual code before action —
several audit claims were **false positives** and are recorded as such so we don't
"fix" non-bugs later.

## Fixed this cycle (CI-verified, branch `claude/piano-roll-clip-view-wozlie`)

| Severity | File | Bug | Commit |
|---|---|---|---|
| CRITICAL | DSP/EchoelDDSP.swift (EchoelPolyDDSP.render) | `let mixL = mixBufferL` + inout vDSP_vadd forced a COW heap alloc per voice/block on the audio thread | `d8630b0` in-place vDSP via withUnsafeMutableBufferPointer |
| CRITICAL | Core/SPSCQueue.swift:148 | drop-oldest advanced `head` unmasked → once head==mask, next dequeue indexes buffer[capacity] (OOB) | `7cbcaa5` masked compare-and-swap |
| CRITICAL | Audio/RetroCapture.swift deinit | deinit deallocated ring/file/flag pointers without removing the tap → use-after-free if a callback fires after dealloc | `656512e` weak node + removeTap before dealloc |
| MED | Audio/AudioConfiguration.swift:238 | `mach_thread_self()` send right leaked every call | `039ddb7` mach_port_deallocate via defer |
| LOW→quality | DSP/EchoelDDSP.swift | all poly voices shared one noise PRNG seed → correlated/comb-filtered noise | `b30d598` per-voice golden-ratio seed |
| CRITICAL(web) | docs/*.html (14) | inline cache-guardian stuck at V='10.14.0' vs version.json 10.21.0 → nuke+reload every visit | `10cad00` synced to 10.21.0 |

## False positives (verified NOT bugs — do not "fix")

- **MIDIInput.swift:149 pitch-bend precedence** — `|` and `-` are both
  `AdditionPrecedence`, left-associative, so it already evaluates as
  `(data1 | (msb<<7)) - 8192`. Correct.
- **EchoelDDSP.swift:687 phase wrap (`if` vs `while`)** — partials break at Nyquist,
  so `phaseInc = partialFreq * 2π/sr < π` always; a single subtraction suffices.
- **EchoelDDSP.swift:287 noise can hit ~-1.0000000005** — once per 4e9 samples, well
  within the downstream tanh soft-limiter. Negligible.

## Deferred (real, but not fixed — risk/scope vs. "keep stable", no local Swift build)

1. **MIDIInput.swift:113 `Mirror(reflecting: packet.words)`** — allocates on the
   CoreMIDI read thread (jitter, not a render-thread glitch). Real, but the fix
   (`withUnsafeBytes` tuple read) changes the live MIDI/MPE-in parse and needs
   on-device MIDI verification. Do in a cycle where a controller is available.
2. **EchoelMeter.swift:76,106 stereo true-peak history** — channel-linked rectified
   value fed to the Catmull-Rom interpolator → inaccurate true-peak. Bounded, no
   crash. Keep separate signed per-channel history (zL1..3 / zR1..3).
3. **EchoelModalBank.swift:730 `morphMaterials` custom-restore** — re-interpolates an
   already-blended `modeRatios` against itself in the custom branch. Drum-synth edge
   case; interpolate from local from/to scratch and restore `material` explicitly.
4. **MultiTrackRecorder.swift:147 / RetroCapture.swift:106** — `AVAudioFile.write` (file
   I/O + locking) inside the tap callback → dropouts under disk pressure. This is the
   current design; proper fix is an SPSC ring drained on a background queue (refactor).
5. **EchoelDDSP.swift:434 convolution-reverb kernel race** — control thread mutates
   taps while render reads. LATENT (conv reverb currently disabled). Double-buffer the
   kernel before re-enabling.
6. **SingleExport.swift:136,204 CMBlockBuffer contiguity** — assumes a single 4-byte-
   multiple block; multi-segment buffer → OOB. Export path; use `lengthAtOffset` and
   guard `% 4 == 0`.

## Full-app sweep #2 ("Unstimmigkeiten, Design & Code fehler")

Three parallel audits — UI/design, code-quality, brand/claims. Device log reviewed: healthy
(rPPG locks conf=1.00 bpm=65, tempo follows HR, re-seed loop nominal — no bug).

**Fixed:**
- `fix(dsp)` `2a7fb3c` — EchoelMeter true-peak: per-channel signed interpolation history
  (was mixing rectified linked value with signed sample). Metering only.
- `fix(audio)` `a05266a` — SingleExport walks CMBlockBuffer segments (was OOB read/write on a
  segmented block via totalLength/4 from one pointer). Behaviour-identical for normal LPCM.
- `chore` `c567219` — AudioEngine docstring "soundscape" → "synthesis"; removed unused
  `.quantum`/`.wellness` LogCategory cases + their dead convenience methods (brand + dead code).

**Code-quality sweep: NO REAL ISSUES** across Studio/Views/Tools/Core/Sync (force-unwraps,
print, ObservableObject, divisions, OOB, retain cycles, dead code, dup types all clean).

**Verified NOT issues:** SubBassVoice IS fully wired (App:196 attach + env + subGain control),
so the website "Sub-bass / LFE felt" claim is accurate. Zero banned terminology in user copy.
No raw Slider/Stepper for parameters anywhere. Env-injection chain intact. No banned UI patterns.

**Deferred design-consistency items (founder design call — not blind-changed):**
- `Views/OnboardingView.swift` (127–198) bypasses EchoelTheme (hardcoded white/black + system
  fonts). It's a deliberate high-contrast first-run look with white CTA buttons; EchoelTheme's
  accent is "signal-only" green and has no button-fill token, so a blind swap would change the
  design. Re-theme only if the founder wants onboarding aligned to the app theme.
- `Studio/EchoelStudioView.swift:1128` hardcoded `Color.black.opacity(0.35)` scrim (≠ the light
  `EchoelTheme.fill`); likely intentional. LOW.

## Config decisions (founder: "du entscheidest" — kept, stability-first)

- **wrangler.toml** — kept. Inert if unused; removing risks the website if Cloudflare
  is the host. Website stability is priority #1.
- **ci_scripts/** — kept. Clean, current Xcode Cloud scripts (no stale Tuist/JUCE
  refs); a valid optional backup CI path.
- **launch workflows** (benchmark/screenshots/send-push/trigger-testflight/deploy-on-tag)
  — kept. Plausibly-live automation, not the dead/contradictory tooling already pruned
  (Tuist/JUCE/Android). Pruning deploy infra unverified-dead = risk, no stability gain.
