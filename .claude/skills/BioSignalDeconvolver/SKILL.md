---
name: BioSignalDeconvolver
description: Use when working with raw, noisy biosignals that need to be cleaned — motion-artifact removal from PPG, electrode noise on ECG/EEG, baseline drift, mixed sources that need separation, or any task that asks for "clean" sensor data downstream. Load this skill before reading, calling, debugging, or writing tests against BioSignalDeconvolver. Do NOT load for unrelated audio, UI, or MIDI work.
---

# BioSignalDeconvolver — Protected DSP Component

## Status: READ-ONLY

`BioSignalDeconvolver` is core IP. **It is not modified, refactored, "cleaned up", "optimized", or wrapped in adapters without an explicit written "APPROVED: modify BioSignalDeconvolver" from the owner.** If a compile error, crash, or test failure points at this file, fix the caller, the input data quality, or the threading — not the component.

## Conceptual Overview

`BioSignalDeconvolver` is the first DSP block that touches raw sensor data after acquisition. It does signal separation and artifact rejection: pulling the actual physiological signal out of a stream that also contains motion, electrical interference, baseline drift, and sensor noise.

Conceptually it treats the observed sample stream as a convolution of (a) the true underlying biosignal with (b) sensor transfer functions and noise sources, and inverts that mixing — hence "deconvolver". It is the upstream gatekeeper for `HilbertSensorMapper` and `BioEventGraph`. If the deconvolver's output is dirty, everything downstream is dirty.

Its responsibilities, in order:

1. **Detrend** — remove DC offset and slow baseline drift
2. **Notch** — reject mains interference (50/60 Hz, configurable)
3. **Separate** — isolate the physiological band from motion/electrical artifacts
4. **Validate** — mark sample windows as `valid` / `corrupt` / `recovering` so downstream consumers know whether to trust them

It does **not** do event detection (that's `BioEventGraph`) and does **not** do phase analysis (that's `HilbertSensorMapper`). It produces clean, validated, continuous samples ready for those next stages.

## How to use it (the caller's side)

- Feed it raw sensor frames directly from the sensor abstraction layer. Don't pre-filter — that's its job.
- Configure it per sensor type (PPG, ECG, EEG, accelerometer-derived) using the documented presets. Don't mix presets.
- Always read the **validity flag** alongside the sample. Samples marked `corrupt` must be treated as missing data by downstream consumers, not used as if clean.
- The deconvolver has a warm-up period (typically a few seconds). Downstream code must tolerate `recovering` periods at session start and after motion bursts.
- Subscribe via `EngineBus` to its cleaned output stream. Do not reach into internal buffers.

## How to debug it (without touching it)

1. Log the **raw** input stream and the **cleaned** output stream side by side at the boundaries.
2. Verify the validity flag is being honored downstream. The most common "deconvolver bug" is actually a downstream consumer ignoring `corrupt` samples.
3. If the cleaned signal looks wrong (clipped, inverted, scaled): check the sensor preset configuration, not the deconvolver code.
4. If motion artifacts are bleeding through: verify the accelerometer cross-feed is wired in (it requires the motion stream as a reference; without it, motion artifact rejection is degraded by design).
5. If the deconvolver itself appears broken after exhausting the above, file a documented issue with raw input capture — do not patch.

## Constraints for any code that touches it

- No allocation, no locks, no GCD calls on the thread feeding it.
- Input frames must match the configured sample rate and channel count exactly.
- The motion reference channel (if configured) must arrive time-aligned with the primary signal — misalignment silently degrades output.
- One deconvolver instance per physical sensor; never share across sensors.
- Tests use canned raw-data captures (clean and motion-contaminated); never synthetic perfect signals.

## What you may freely do

- Add new sensor adapters that produce input in the expected raw frame format
- Add validity-aware consumers (visuals that fade out when `corrupt`, OSC senders that send a flag)
- Configure new instances using documented presets
- Write integration tests with recorded raw-data fixtures
- Document observed validity-flag behavior in this SKILL.md

## What you may NOT do

- Edit the Swift file(s) implementing `BioSignalDeconvolver`
- Add "alternative" cleaning paths that bypass the deconvolver for the same signal class
- Disable or ignore the validity flag in production code paths
- Rename, move, or split the module
