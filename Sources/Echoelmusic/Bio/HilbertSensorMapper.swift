//
//  HilbertSensorMapper.swift
//  Echoelmusic — Protected DSP Component
//
//  Hilbert-curve based 1D → 2D locality-preserving mapper for laying
//  out sensor channels (e.g., EEG electrodes, multi-band coherence
//  values, biosignal grids) into a 2D texture or grid such that
//  numerically adjacent 1D indices land at spatially adjacent 2D
//  coordinates.
//
//  This is the SPACE-FILLING-CURVE interpretation per master prompt
//  §2: "Hilbert curves | 1D→2D locality-preserving sensor mapping."
//  Not to be confused with the Hilbert TRANSFORM (analytic-signal /
//  instantaneous phase + amplitude) which, if added later, will
//  ship as a separate `HilbertAnalyticSignal` module.
//
//  Algorithm: standard iterative d2xy (Skiena / Wikipedia formulation).
//  Order `n` is the side length of the square grid; it is internally
//  rounded up to the next power of two. `order = 0` returns (0, 0)
//  as a safe degenerate value.
//
//  See SKILL.md for caller-side conventions. All members are
//  nonisolated and pure — safe to call from any thread.
//

import Foundation

public enum HilbertSensorMapper {

    /// Map a 1D index to its 2D coordinate on a Hilbert curve of
    /// side length `order`. Adjacent indices land at neighbouring
    /// 2D cells (Manhattan distance ≤ 1).
    ///
    /// - Parameters:
    ///   - index: position along the curve, 0 ..< order*order
    ///   - order: grid side length (rounded up to next power of two
    ///            internally; the canonical Hilbert curve is defined
    ///            on powers of two)
    /// - Returns: (x, y) coordinates in 0 ..< order. For `order <= 0`
    ///            returns (0, 0).
    public static func map(index: Int, order: Int) -> (Int, Int) {
        guard order > 0 else { return (0, 0) }
        let n = nextPowerOfTwo(order)
        var x = 0
        var y = 0
        var t = index
        var s = 1
        while s < n {
            let rx = 1 & (t / 2)
            let ry = 1 & (t ^ rx)
            if ry == 0 {
                if rx == 1 {
                    x = s - 1 - x
                    y = s - 1 - y
                }
                swap(&x, &y)
            }
            x += s * rx
            y += s * ry
            t /= 4
            s *= 2
        }
        return (x, y)
    }

    /// Fill a `gridSize × gridSize` 2D grid by laying out `values`
    /// along a Hilbert curve. Cells beyond `values.count` stay 0.
    /// `gridSize` is internally rounded up to the next power of two
    /// when computing curve positions, but the returned grid is
    /// exactly `gridSize × gridSize` (truncated if rounding bumps it).
    public static func mapToGrid(values: [Float], gridSize: Int) -> [[Float]] {
        guard gridSize > 0 else { return [] }
        var grid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        let cellCount = gridSize * gridSize
        let usable = min(values.count, cellCount)
        for i in 0..<usable {
            let (x, y) = map(index: i, order: gridSize)
            if x < gridSize, y < gridSize {
                grid[y][x] = values[i]
            }
        }
        return grid
    }

    // MARK: - Internals

    private static func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
