---
name: HilbertSensorMapper
description: Use when working with phase analysis of biosignals — breath phase, heartbeat phase, instantaneous amplitude, phase coherence, phase-locking between signals, or any task that needs the analytic signal of a sensor stream. Load this skill before reading, calling, debugging, or writing tests against HilbertSensorMapper. Do NOT load for unrelated audio, UI, or MIDI work.
---

# HilbertSensorMapper — Protected DSP Component

## Status: READ-ONLY

`HilbertSensorMapper` is core IP. **It is not modified, refactored, "cleaned up", "optimized", or wrapped in adapters without an explicit written "APPROVED: modify HilbertSensorMapper" from the owner.** If a compile error, crash, or test failure points at this file, fix the caller, the filtering upstream, or the threading — not the component.

## Conceptual Overview

`HilbertSensorMapper` applies a Hilbert transform to band-limited biosignals to produce the **analytic signal** — a complex-valued representation from which two derived signals are continuously available:

- **Instantaneous amplitude** (envelope): how strong the signal is at this moment
- **Instantaneous phase** (in radians, unwrapped or wrapped to [-π, π]): where in its cycle the signal currently is

It is the mathematical foundation for everything in the app that needs to know not just "what value is this signal right now" but "where in its cycle is it" — breath-phase-driven modulation, heart-coherent visuals, phase-locked-loop-style synchronization between two biosignals, etc.

Hilbert transforms are mathematically well-defined only for **narrow-band signals**. The mapper assumes its input is already band-pass filtered to the frequency range of interest (e.g. 0.05–0.5 Hz for breath, 0.5–4 Hz for HR envelope). Feeding it broadband signals produces meaningless phase output.

## How to use it (the caller's side)

- Always band-pass filter upstream before handing samples to the mapper. The filter is the caller's responsibility, not the component's.
- Sample-rate matters. Configure the mapper for the actual sample rate of the input stream; don't assume defaults.
- The first samples after start contain transient artifacts. Discard or mark them as invalid for at least one full cycle of the slowest expected oscillation.
- For phase-locking comparisons between two streams, both must come from the same Hilbert configuration window — don't compare phases from differently-configured instances.
- Consume outputs via `EngineBus` or the documented public stream API. Don't reach into internal buffers.

## How to debug it (without touching it)

1. Plot the input signal and verify it is **band-limited** (looks roughly sinusoidal in the target band).
2. Plot the instantaneous amplitude — it should be a smooth envelope, not noisy.
3. Plot the instantaneous phase — it should be monotonically increasing (modulo 2π wraps).
4. If amplitude is noisy or phase jumps erratically: the upstream filter is wrong or the input is broadband. **Fix upstream**, not the mapper.
5. If output is correct in isolation but consumers misbehave: the bug is in phase unwrapping or comparison logic at the consumer.

## Constraints for any code that touches it

- No allocation, no locks, no GCD calls on the audio/processing thread that feeds it.
- Sample buffers passed in must match the configured block size and sample rate exactly.
- Don't create multiple instances of the mapper against the same input stream; fan out from one instance.
- Tests use canned sine/chirp/breath-shaped vectors; never live sensors.

## What you may freely do

- Build consumers (visuals, synth modulators, OSC senders) on top of its output
- Configure new instances for new band-limited streams (after filtering)
- Write integration tests with canned input vectors
- Document phase conventions actually used by consumers in this SKILL.md

## What you may NOT do

- Edit the Swift file(s) implementing `HilbertSensorMapper`
- Replace the Hilbert implementation with an alternative (FFT-based, FIR-based, etc.) — even if "more efficient"
- Bypass it and compute phase another way for the same signal class
- Rename, move, or split the module
