---
name: HilbertSensorMapper
description: Use when laying out 1-D sensor channels (EEG electrodes, multi-band coherence values, biosignal arrays) into a 2-D texture, grid, or visual map such that numerically adjacent channels land at spatially adjacent cells. Load this skill before reading, calling, debugging, or writing tests against HilbertSensorMapper. Do NOT load for unrelated audio, UI, or MIDI work. For Hilbert-transform (analytic-signal) usage see the separate `HilbertAnalyticSignal` module if/when it exists.
---

# HilbertSensorMapper — Protected DSP Component

## Status: READ-ONLY

`HilbertSensorMapper` is core IP. **It is not modified, refactored, "cleaned up", "optimized", or wrapped in adapters without an explicit written "APPROVED: modify HilbertSensorMapper" from the owner.** If a compile error, crash, or test failure points at this file, fix the caller, the input ordering, or the grid sizing — not the component.

## Conceptual Overview

`HilbertSensorMapper` implements the **Hilbert space-filling curve** for 1-D → 2-D locality-preserving layout. Given a linear index along the curve, it returns 2-D coordinates such that numerically adjacent indices (i and i+1) always land at spatially adjacent grid cells (Manhattan distance ≤ 1). This matters whenever a one-dimensional sequence of sensor channels — EEG electrodes, frequency bands, coherence sweeps, sample buffers — needs to be visualised or processed as a 2-D texture without breaking the locality of nearby channels.

The Hilbert curve is defined on square grids whose side length is a power of two; the mapper rounds the requested `order` up to the next power of two internally. The output 2-D grid is exactly `gridSize × gridSize` in `mapToGrid`.

> Naming note: This component is named for the **Hilbert curve** (space-filling fractal), not the **Hilbert transform** (analytic-signal phase / amplitude). The two are distinct mathematical objects. If a later cycle needs instantaneous phase from band-limited biosignals, that ships as a separate `HilbertAnalyticSignal` module so the two concerns don't get conflated.

## API surface

```swift
public enum HilbertSensorMapper {
    public static func map(index: Int, order: Int) -> (Int, Int)
    public static func mapToGrid(values: [Float], gridSize: Int) -> [[Float]]
}
```

Both members are pure, nonisolated, and safe to call from any thread.

## How to use it (the caller's side)

- Decide your grid size based on how many channels you actually have. `gridSize = 8` accommodates up to 64 channels.
- Pass channel values in the order you want adjacency preserved — typically the natural sensor order or a frequency-ordered EEG band sweep.
- Treat the returned `[[Float]]` as `grid[y][x]` (row-major). Empty cells (beyond `values.count`) are zero.
- Edge case: `order = 0` returns `(0, 0)` — safe degenerate value, do not treat as an error.

## How to debug it (without touching it)

1. If 1-D adjacent values appear to land far apart in 2-D, check that you're treating `grid[y][x]` correctly — not `grid[x][y]`.
2. If `mapToGrid` returns fewer rows / columns than expected, verify `gridSize` was the correct power-of-two for your channel count.
3. The map is fully deterministic — the same `(index, order)` always returns the same `(x, y)`. If you see non-determinism, the bug is in the caller's input ordering, not here.
4. For visualisation: a useful sanity render is to colour `grid[y][x]` by `(x + y * gridSize) / Float(gridSize*gridSize)` — you should see a continuous gradient that snakes through the grid in the Hilbert pattern.

## Constraints for any code that touches it

- Inputs are pure value types (Int, [Float]). No external state, no allocations beyond the returned 2-D array.
- Don't pass negative `order` or `gridSize` — both clamp to safe defaults but the caller intent is unclear.
- For very large grids (`order > 1024`) the recursion depth is fine (iterative algorithm) but the returned 2-D `[[Float]]` array allocates `O(n²)` cells. If that matters, the caller should reuse buffers.

## What you may freely do

- Layout EEG electrode arrays, frequency band sweeps, coherence values into Metal textures via `mapToGrid`
- Build visual modes (Hilbert visualization in EchoelVis) on top of its output
- Compose with image filters or Metal shaders that consume the 2-D grid
- Write integration tests with deterministic input vectors

## What you may NOT do

- Edit the Swift file implementing `HilbertSensorMapper`
- Replace the iterative algorithm with an alternative (Moore curve, Z-order / Morton, Peano) — even if "more efficient"
- Add coordinate-system variants without owner approval (the current convention is row-major `grid[y][x]`)
- Rename, move, or split the module
