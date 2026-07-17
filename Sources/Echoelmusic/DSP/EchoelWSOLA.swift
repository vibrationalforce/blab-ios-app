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
    /// repo NaN law); rate 1 is bit-transparent. Output length ≈ count / rate
    /// (never longer than one frame beyond it — see the render trim).
    public func stretch(_ input: [Float], rate: Float) -> [Float] {
        guard rate.isFinite, rate > 0, rate != 1.0, input.count > frameSize else { return input }
        let offsets = chosenOffsets(searching: input, rate: rate)
        return render(input, offsets: offsets, rate: rate)
    }

    /// Stretch every channel COHERENTLY: the similarity search runs ONCE on a
    /// mono downmix and the chosen segment offsets apply to ALL channels — so
    /// L/R stay phase-locked (independent per-channel searches pick different
    /// offsets wherever the content differs and smear the stereo image, exactly
    /// on the drum material Beats targets). Guards fail quiet: empty input → [],
    /// mismatched channel lengths / degenerate rate / sub-frame input →
    /// passthrough unchanged.
    public func stretchMultichannel(_ channels: [[Float]], rate: Float) -> [[Float]] {
        guard let first = channels.first else { return [] }
        guard channels.allSatisfy({ $0.count == first.count }),
              rate.isFinite, rate > 0, rate != 1.0, first.count > frameSize else { return channels }
        if channels.count == 1 { return [stretch(first, rate: rate)] }

        // Equal-weight mono downmix drives the ONE search.
        var mono = [Float](repeating: 0, count: first.count)
        for ch in channels {
            ch.withUnsafeBufferPointer { src in
                mono.withUnsafeMutableBufferPointer { dst in
                    guard let s = src.baseAddress, let d = dst.baseAddress else { return }
                    vDSP_vadd(s, 1, d, 1, d, 1, vDSP_Length(first.count))
                }
            }
        }
        var scale = 1.0 / Float(channels.count)
        mono.withUnsafeMutableBufferPointer { mb in
            guard let m = mb.baseAddress else { return }
            vDSP_vsmul(m, 1, &scale, m, 1, vDSP_Length(first.count))
        }
        let offsets = chosenOffsets(searching: mono, rate: rate)
        return channels.map { render($0, offsets: offsets, rate: rate) }
    }

    // MARK: - Search (offsets) + render, split so multichannel shares ONE search

    /// The per-frame analysis start offsets the search signal yields (frame 0 = 0).
    /// Textbook tail-continuation criterion; see `stretch` header for the laws.
    private func chosenOffsets(searching signal: [Float], rate: Float) -> [Int] {
        let n = frameSize
        let synthesisHop = n / 2                                   // Hann COLA at 50%
        let analysisHop = Double(synthesisHop) * Double(rate)      // rate-scaled read advance
        let outCount = Int(Double(signal.count) / Double(rate))
        let frames = Swift.max(1, (outCount - n) / synthesisHop + 1)
        var offsets = [Int]()
        offsets.reserveCapacity(frames)
        offsets.append(0)                                          // frame 0: input head
        var chosen = 0

        for k in 1..<frames {
            // The natural continuation: where the previous segment WOULD go on
            // if we kept reading — maximal waveform similarity by construction.
            let natural = chosen + synthesisHop
            let nominal = Int((Double(k) * analysisHop).rounded())
            // DSP-review L1: clamp lo into the valid range instead of breaking —
            // for rate < 1 the nominal can pass count−n+tolerance near the tail;
            // a break left hard zeros in the allocated end. Clamped, the search
            // window degenerates to the last valid positions and every frame
            // renders. lo ≤ hi now holds for all inputs (guard = belt-and-braces).
            let lo = Swift.max(0, Swift.min(nominal - tolerance, signal.count - n))
            let hi = Swift.min(signal.count - n, nominal + tolerance)
            guard lo <= hi, natural + synthesisHop <= signal.count else { break }

            // Pick the candidate whose first synthesisHop samples best match the
            // natural continuation (normalized cross-correlation via vDSP dot).
            var best = lo
            var bestScore = -Float.infinity
            signal.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                let refEnergy = energy(base + natural, count: synthesisHop)
                guard refEnergy > 0 else { best = Swift.min(Swift.max(natural, lo), hi); return }
                let refNorm = refEnergy.squareRoot()               // L3: no product overflow
                var d = lo
                while d <= hi {
                    var dot: Float = 0
                    vDSP_dotpr(base + natural, 1, base + d, 1, &dot, vDSP_Length(synthesisHop))
                    let candEnergy = energy(base + d, count: synthesisHop)
                    let score = candEnergy > 0 ? dot / (refNorm * candEnergy.squareRoot()) : -1
                    if score > bestScore { bestScore = score; best = d }
                    d += 1
                }
            }
            chosen = best
            offsets.append(chosen)
        }
        return offsets
    }

    /// Windowed overlap-add of `input` at the given per-frame offsets, then the
    /// M1 window-sum normalization and the L2 length trim. Linear per channel, so
    /// identical offsets ⇒ identical processing (the multichannel coherence law).
    private func render(_ input: [Float], offsets: [Int], rate: Float) -> [Float] {
        let n = frameSize
        let synthesisHop = n / 2
        let outCount = Int(Double(input.count) / Double(rate))

        // Hann window (vDSP's PERIODIC form: w[i]+w[i+n/2] == 1 exactly, so the
        // 50% overlap-add is constant-gain in the steady state; DENORM peaks at 1).
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))

        var out = [Float](repeating: 0, count: (offsets.count - 1) * synthesisHop + n)
        // Window-sum twin (DSP-review M1): the head/tail half-frames get only ONE
        // window contribution — unnormalized, a kick at sample 0 fades in over
        // ~5 ms, exactly the attack the Beats character exists to protect.
        var winSum = [Float](repeating: 0, count: out.count)
        for (k, from) in offsets.enumerated() {
            overlapAdd(input, from: from, into: &out, winSum: &winSum,
                       at: k * synthesisHop, window: window)
        }

        // M1: normalize by the window sum (floored — a zero window weight stays
        // silent rather than exploding). Steady state divides by exactly 1.
        // Explicit buffer pointers: the same array as vDSP in+out via implicit
        // conversion would be an overlapping-access violation (CLAUDE.md table).
        var floorVal: Float = 1e-3
        out.withUnsafeMutableBufferPointer { ob in
            winSum.withUnsafeMutableBufferPointer { wb in
                guard let op = ob.baseAddress, let wp = wb.baseAddress else { return }
                vDSP_vthr(wp, 1, &floorVal, wp, 1, vDSP_Length(wb.count))
                vDSP_vdiv(wp, 1, op, 1, op, 1, vDSP_Length(ob.count))
            }
        }
        // L2: never return MORE than the contracted length (reachable only for
        // sub-frame outCount, e.g. a <100 ms clip at rate 4 — frames floors at 1).
        if out.count > Swift.max(outCount, 1) { out.removeLast(out.count - Swift.max(outCount, 1)) }
        return out
    }

    // MARK: - Helpers (offline path — allocation-free inner ops)

    private func energy(_ p: UnsafePointer<Float>, count: Int) -> Float {
        var e: Float = 0
        vDSP_dotpr(p, 1, p, 1, &e, vDSP_Length(count))
        return e
    }

    /// Windowed overlap-add of `input[from ..< from+frameSize]` at `out[at...]`,
    /// accumulating the window itself into `winSum` for the M1 normalization.
    private func overlapAdd(_ input: [Float], from: Int, into out: inout [Float],
                            winSum: inout [Float], at: Int, window: [Float]) {
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
        winSum.withUnsafeMutableBufferPointer { wsBuf in
            window.withUnsafeBufferPointer { winBuf in
                guard let sp = wsBuf.baseAddress, let wp = winBuf.baseAddress else { return }
                vDSP_vadd(wp, 1, sp + at, 1, sp + at, 1, vDSP_Length(n))
            }
        }
    }
}
