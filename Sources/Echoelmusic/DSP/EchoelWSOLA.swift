// EchoelWSOLA.swift
// Echoel — Stretch Slice 2 (Beats-Executor): pure, offline WSOLA time-stretch.
// Textbook Verhelst–Roelands (1993), patent-free: fixed SYNTHESIS hop, a
// rate-scaled ANALYSIS hop, and per frame a ±tolerance waveform-similarity
// search (vDSP cross-correlation) against the natural continuation of the
// previously chosen segment, then Hann 50% overlap-add. Time changes, pitch
// stays — transients smear less than in spectral stretching, which is why this
// is the BEATS character next to Clean (Apple spectral) and Tape (varispeed).
//
// PURE OFFLINE CORE: buffer in → buffer out, no nodes, no audio-thread claims.
// Allocation happens here (offline render path); the realtime node wrapper is
// its own later slice and must pre-render or pre-allocate. DSP/ isolation law:
// Foundation + Accelerate only — no Core/Sequencer types (the AUv3 target
// compiles DSP/ standalone).

import Foundation
import Accelerate

/// Offline WSOLA time-stretcher. `rate` is the PLAYBACK SPEED factor, matching
/// `StretchPlan.rate`: 2.0 = twice as fast (half as long), 0.5 = half speed
/// (twice as long). Pitch is preserved at every rate.
public struct WSOLAStretcher: Sendable {

    /// Analysis/synthesis frame length (Hann window). Power-of-two, ≥ 256.
    public let frameSize: Int
    /// Similarity-search tolerance (± samples around the nominal position).
    public let tolerance: Int

    public init(frameSize: Int = 1024, tolerance: Int = 256) {
        let n = Swift.max(256, frameSize)
        self.frameSize = n
        self.tolerance = Swift.min(Swift.max(0, tolerance), n / 2)
    }

    /// Stretch `input` by `rate`. Degenerate input (shorter than one frame) or a
    /// non-finite / non-positive rate passes through unchanged (fail quiet, the
    /// repo NaN law); rate 1 is bit-transparent. Output length ≈ count / rate.
    public func stretch(_ input: [Float], rate: Float) -> [Float] {
        guard rate.isFinite, rate > 0, rate != 1.0, input.count > frameSize else { return input }

        let n = frameSize
        let synthesisHop = n / 2                                   // Hann COLA at 50%
        let analysisHop = Double(synthesisHop) * Double(rate)      // rate-scaled read advance
        let outCount = Int(Double(input.count) / Double(rate))
        let frames = Swift.max(1, (outCount - n) / synthesisHop + 1)

        // Hann window (periodic form keeps the 50% overlap-add constant-gain).
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        // vDSP_HANN_DENORM peaks at 1.0 → 50% OLA sums to unit gain.

        var out = [Float](repeating: 0, count: (frames - 1) * synthesisHop + n)
        var chosen = 0                                             // analysis start of frame 0

        // Frame 0: straight copy-in (windowed) from the input head.
        overlapAdd(input, from: 0, into: &out, at: 0, window: window)

        for k in 1..<frames {
            let outPos = k * synthesisHop
            // The natural continuation: where the previous segment WOULD go on
            // if we kept reading — maximal waveform similarity by construction.
            let natural = chosen + synthesisHop
            let nominal = Int((Double(k) * analysisHop).rounded())
            let lo = Swift.max(0, nominal - tolerance)
            let hi = Swift.min(input.count - n, nominal + tolerance)
            guard lo <= hi, natural + synthesisHop <= input.count else { break }

            // Pick the candidate whose first synthesisHop samples best match the
            // natural continuation (normalized cross-correlation via vDSP dot).
            var best = lo
            var bestScore = -Float.infinity
            input.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                let refEnergy = energy(base + natural, count: synthesisHop)
                guard refEnergy > 0 else { best = Swift.min(Swift.max(natural, lo), hi); return }
                var d = lo
                while d <= hi {
                    var dot: Float = 0
                    vDSP_dotpr(base + natural, 1, base + d, 1, &dot, vDSP_Length(synthesisHop))
                    let candEnergy = energy(base + d, count: synthesisHop)
                    let score = candEnergy > 0 ? dot / (refEnergy * candEnergy).squareRoot() : -1
                    if score > bestScore { bestScore = score; best = d }
                    d += 1
                }
            }
            chosen = best
            overlapAdd(input, from: chosen, into: &out, at: outPos, window: window)
        }
        return out
    }

    // MARK: - Helpers (offline path — allocation-free inner ops)

    private func energy(_ p: UnsafePointer<Float>, count: Int) -> Float {
        var e: Float = 0
        vDSP_dotpr(p, 1, p, 1, &e, vDSP_Length(count))
        return e
    }

    /// Windowed overlap-add of `input[from ..< from+frameSize]` at `out[at...]`.
    private func overlapAdd(_ input: [Float], from: Int, into out: inout [Float],
                            at: Int, window: [Float]) {
        let n = frameSize
        guard from >= 0, from + n <= input.count, at >= 0, at + n <= out.count else { return }
        input.withUnsafeBufferPointer { inBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                window.withUnsafeBufferPointer { winBuf in
                    guard let ip = inBuf.baseAddress, let op = outBuf.baseAddress,
                          let wp = winBuf.baseAddress else { return }
                    // out[at+i] += input[from+i] * window[i]
                    vDSP_vma(ip + from, 1, wp, 1, op + at, 1, op + at, 1, vDSP_Length(n))
                }
            }
        }
    }
}
