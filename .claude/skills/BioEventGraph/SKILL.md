---
name: BioEventGraph
description: Use when working with biosignal event detection — heartbeat peaks, breath cycles, motion onsets, EEG bursts, or any task that needs to detect, route, or react to discrete events extracted from continuous biosignals. Load this skill before reading, calling, debugging, or writing tests against BioEventGraph. Do NOT load for unrelated audio, UI, or MIDI work.
---

# BioEventGraph — Protected DSP Component

## Status: READ-ONLY

`BioEventGraph` is core IP. **It is not modified, refactored, "cleaned up", "optimized", or wrapped in adapters without an explicit written "APPROVED: modify BioEventGraph" from the owner.** If a compile error, crash, or test failure points at this file, fix the caller, the input data, or the threading — not the component.

## Conceptual Overview

`BioEventGraph` is a graph-based event-detection layer for continuous biosignals. Continuous sample streams (HR, PPG, breath, accelerometer, EEG bands) flow in; discrete, timestamped events flow out. Nodes in the graph represent detectors (peak finders, threshold crossings, phase markers, burst detectors); edges represent dependencies and gating relationships between them.

Typical produced events:

- `heartbeat` (with confidence, inter-beat interval)
- `breath.inhale.onset` / `breath.exhale.onset`
- `motion.peak` (with axis and magnitude)
- `eeg.{band}.burst` (with band power)
- `coherence.shift` (when HRV-breath coherence crosses a threshold)

Events are the **only** sanctioned way for the rest of the app to react to biosignals discretely. Modules subscribe to event types via `EngineBus`; they do not poll sample buffers.

## How to use it (the caller's side)

- Feed it sample buffers from the sensor abstraction layer, not raw HealthKit/CoreMotion objects — the conversion happens upstream.
- Read its outputs as immutable `BioEvent` values; don't mutate, don't cache, don't assume monotonic timestamps without checking.
- Subscribe via the published event stream on `EngineBus`. Do not call internal graph nodes directly even if they appear accessible.
- If you need a new event type that doesn't exist yet, that's a design conversation with the owner — not a code change.

## How to debug it (without touching it)

1. Log the **input** sample stream at the boundary (before it enters the graph).
2. Log the **output** event stream at the subscription site.
3. If output is wrong, the bug is almost always in (a) input scaling/units, (b) sample rate mismatch, or (c) caller threading. Verify those three first.
4. If after exhausting (a)-(c) the bug truly lives inside the component, file a documented issue with reproducible input — do not patch.

## Constraints for any code that touches it

- No allocation, no locks, no GCD calls on the same thread that feeds the graph.
- Sample-rate must match the configured rate; resample upstream if needed.
- Never run two instances against the same sensor stream — use `EngineBus` fan-out instead.
- Tests against the graph use canned input vectors; never use live sensors in unit tests.

## What you may freely do

- Add new subscribers on `EngineBus` that consume its events
- Write integration tests that feed canned data in and assert on emitted events
- Add new sensor adapters upstream that produce its expected input format
- Document observed behavior in this SKILL.md

## What you may NOT do

- Edit the Swift file(s) implementing `BioEventGraph`
- Subclass it, extend it, or wrap it in a way that depends on internal state
- Rename, move, or split the module
- "Modernize" its API surface
