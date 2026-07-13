// EchoelFDNReverb.swift
// Echoel — Spatial S4: a PURE, deterministic Feedback-Delay-Network room reverb whose
// parameters are DERIVED from a RoomModel (Spatial layer). Eight delay lines are mixed
// by an orthonormal (normalized Hadamard) feedback matrix — energy-preserving, so the
// ONLY loss is the per-line gains, which are set from RoomModel.decayTime by Jot's RT60
// formula. That gives a provably stable network (every g_i < 1 × a lossless mix = a
// contraction) whose measured RT60 tracks the room. Input diffusion is a short Schroeder
// allpass chain scaled by RoomModel.diffusion.
//
// SCOPE (S4): the CORE only. It is NOT added to the live render graph in this slice
// (flag-neutral, Release bit-identical); the future insert is gated by
// FeatureFlags.spatialEngine (default OFF) at the S5 wiring site. Built + proven first.
//
// Reuses the audited zero-alloc EchoelDelayLine ring buffer. `process(_:)` allocates its
// output (offline/test); `processInPlace(_:)` is real-time-safe (all scratch pre-allocated
// in init) and bit-identical to `process(_:)` for an identically-configured instance.
//
// Reference: J.-M. Jot & A. Chaigne, "Digital delay networks for designing artificial
// reverberators" (AES 1991); Julius O. Smith III, "Physical Audio Signal Processing".

#if canImport(Accelerate)
import Foundation
import Accelerate

public final class EchoelFDNReverb: @unchecked Sendable {

    /// Number of delay lines in the network (Hadamard needs a power of two).
    public static let n = 8

    /// 1/√8 — the orthonormal Hadamard scale, precomputed (no per-sample sqrt).
    private static let hadamardNorm: Float = 1.0 / Float(n).squareRoot()

    /// RoomModel → FDN parameters. Pure, deterministic (no RNG-per-call, no wall clock).
    public struct Params: Equatable, Sendable {
        /// Eight delay lengths in samples — DISTINCT primes (⇒ mutually coprime ⇒ dense,
        /// non-degenerate modal spacing). Bigger room → longer, sparser.
        public var lengths: [Int]
        /// Eight Jot feedback gains g_i = 10^(−3·L_i/(RT60·fs)) — each < 1.
        public var gains: [Float]
    }

    // MARK: - State (all allocated in init)

    private let sampleRate: Float
    private let maxBlock: Int
    private var lines: [EchoelDelayLine]
    private var lengthsF: [Float]
    private var gains: [Float]
    /// Reused 8-vector scratch for the per-sample read/mix — never re-allocated.
    private var s: [Float]

    // Input diffusion: two Schroeder allpasses in series.
    private let diffusers: [EchoelDelayLine]
    private let diffLen: [Int]
    private var diffCoeff: Float

    private let outScale: Float = 1.0 / Float(n).squareRoot()
    private let inputGain: Float = 1.0

    /// Dry→wet amount, 0…1.
    public private(set) var mix: Float
    /// The parameters currently in force (exposed for tests/telemetry).
    public private(set) var params: Params

    // MARK: - Init

    public init(room: RoomModel = RoomModel(), sampleRate: Float = 48_000,
                maxBlock: Int = 2048, mix: Float = 0.25, seed: UInt64 = 0xFD2) {
        let fs = (sampleRate.isFinite && sampleRate > 0) ? sampleRate : 48_000
        self.sampleRate = fs
        self.maxBlock = Swift.max(1, maxBlock)
        self.mix = Self.clamp01(mix)

        let p = Self.params(from: room, sampleRate: fs, seed: seed)
        self.params = p
        self.gains = p.gains
        self.lengthsF = p.lengths.map { Float($0) }

        let maxLen = (p.lengths.max() ?? 1) + 8
        self.lines = (0..<Self.n).map { i in
            EchoelDelayLine(maxDelaySeconds: Float(maxLen) / fs, sampleRate: fs)
        }
        self.s = [Float](repeating: 0, count: Self.n)

        // Diffuser: two short, distinct-prime allpass delays; coefficient set by diffusion.
        self.diffLen = [Self.primeAtLeast(Int(0.0043 * fs), excluding: []),
                        Self.primeAtLeast(Int(0.0037 * fs), excluding: [])]
        self.diffusers = diffLen.map { EchoelDelayLine(maxDelaySeconds: Float($0 + 8) / fs, sampleRate: fs) }
        self.diffCoeff = 0.6 * (room.diffusion.isFinite ? Swift.min(Swift.max(room.diffusion, 0), 1) : 0.7)
    }

    // MARK: - Control (control thread only)

    /// Recompute lengths/gains for a new room (control-rate, never the render block).
    public func setRoom(_ room: RoomModel, sampleRate: Float? = nil) {
        let fs = sampleRate ?? self.sampleRate
        let p = Self.params(from: room, sampleRate: fs, seed: 0xFD2)
        self.params = p
        self.gains = p.gains
        self.lengthsF = p.lengths.map { Float($0) }
        self.diffCoeff = 0.6 * (room.diffusion.isFinite ? Swift.min(Swift.max(room.diffusion, 0), 1) : 0.7)
        // Note: delay-line capacity is fixed at init (from the initial room's max length);
        // a room whose max length grows past that is read-clamped by EchoelDelayLine — the
        // live re-size belongs to the S5 wiring slice, not this pure core.
    }

    public func setMix(_ m: Float) { self.mix = Self.clamp01(m) }

    // MARK: - Process

    /// Dry block → wet block (same length). ALLOCATES the output — offline/test only.
    public func process(_ dry: [Float]) -> [Float] {
        let count = dry.count
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        let wet = Self.clamp01(mix)
        for i in 0..<count {
            let w = renderSample(dry[i])
            let v = dry[i] * (1 - wet) + w * wet
            out[i] = v.isFinite ? v : 0
        }
        return out
    }

    /// Real-time-safe: process `buffer` IN PLACE (dry → wet). No allocation. Bit-identical
    /// to `process(_:)` for an identically-configured instance.
    public func processInPlace(_ buffer: inout [Float]) {
        let count = buffer.count
        guard count > 0 else { return }
        let wet = Self.clamp01(mix)
        for i in 0..<count {
            let w = renderSample(buffer[i])
            let v = buffer[i] * (1 - wet) + w * wet
            buffer[i] = v.isFinite ? v : 0
        }
    }

    public func reset() {
        for l in lines { l.reset() }
        for d in diffusers { d.reset() }
        for i in 0..<Self.n { s[i] = 0 }
    }

    // MARK: - Per-sample render (pure, zero-alloc)

    @inline(__always)
    private func renderSample(_ x: Float) -> Float {
        // 1) Input diffusion (Schroeder allpass chain) — denser as diffusion rises.
        var d = allpass(x, index: 0)
        d = allpass(d, index: 1)

        // 2) Read the eight delay-line outputs.
        for i in 0..<Self.n { s[i] = lines[i].read(delaySamples: lengthsF[i]) }

        // 3) Wet output = normalized sum of the taps.
        var wet: Float = 0
        for i in 0..<Self.n { wet += s[i] }
        wet *= outScale

        // 4) Per-line Jot gain, then the orthonormal (energy-preserving) mix.
        for i in 0..<Self.n { s[i] *= gains[i] }
        hadamard8(&s)

        // 5) Inject the diffused input + feedback back into each line.
        for i in 0..<Self.n {
            let v = d * inputGain + s[i]
            lines[i].write(v.isFinite ? v : 0)
        }
        return wet
    }

    /// One Schroeder allpass (single-multiply form): a pure delay at coeff 0, smearing as
    /// coeff rises. Unit-magnitude (allpass) → stable for |coeff| < 1.
    @inline(__always)
    private func allpass(_ x: Float, index: Int) -> Float {
        let delayed = diffusers[index].read(delaySamples: Float(diffLen[index]))
        let v = x + diffCoeff * delayed
        let y = -diffCoeff * v + delayed
        diffusers[index].write(v)
        return y
    }

    /// In-place radix-2 fast Walsh–Hadamard transform for N=8, normalized by 1/√8 so the
    /// matrix is ORTHONORMAL (H·Hᵀ = I) — energy-preserving ⇒ the network is lossless
    /// except for the per-line gains ⇒ unconditionally stable given every gain < 1.
    @inline(__always)
    private func hadamard8(_ a: inout [Float]) {
        var stride = 1
        while stride < Self.n {
            var i = 0
            while i < Self.n {
                for j in i..<(i + stride) {
                    let aa = a[j]
                    let bb = a[j + stride]
                    a[j] = aa + bb
                    a[j + stride] = aa - bb
                }
                i += stride << 1
            }
            stride <<= 1
        }
        for k in 0..<Self.n { a[k] *= Self.hadamardNorm }
    }

    // MARK: - Parameter derivation (pure, deterministic — exposed for tests)

    /// Derive the eight delay lengths + Jot gains from a room. Deterministic: same
    /// (room, sampleRate, seed) → identical Params. Bigger room → longer, sparser delays.
    public static func params(from room: RoomModel, sampleRate: Float, seed: UInt64 = 0xFD2) -> Params {
        let fs = (sampleRate.isFinite && sampleRate > 0) ? sampleRate : 48_000
        let width  = room.width.isFinite  ? Swift.min(Swift.max(room.width, 1), 200)  : 8
        let depth  = room.depth.isFinite  ? Swift.min(Swift.max(room.depth, 1), 200)  : 10
        let height = room.height.isFinite ? Swift.min(Swift.max(room.height, 1), 60)  : 4
        let rt60   = room.decayTime.isFinite ? Swift.min(Swift.max(room.decayTime, 0.1), 30) : 1.2

        // Round-trip acoustic time of the mean dimension (≈ 2·d / c, c = 343 m/s), spread
        // geometrically into eight target lengths — a small room clusters short + dense,
        // a large room spreads long + sparse.
        let meanDim = (width + depth + height) / 3
        let baseSec = 2 * meanDim / 343
        let minLen = Swift.max(23, Int(baseSec * 0.5 * fs))
        let maxLen = Swift.max(minLen + 16, Int(baseSec * 1.7 * fs))
        let jitter = Int(seed % 7)                      // deterministic per-seed nudge

        var used = Set<Int>()
        var lengths = [Int]()
        lengths.reserveCapacity(n)
        for i in 0..<n {
            let f = n > 1 ? Float(i) / Float(n - 1) : 0
            let target = Int(Float(minLen) * powf(Float(maxLen) / Float(minLen), f)) + jitter
            let p = primeAtLeast(target, excluding: used)
            used.insert(p)
            lengths.append(p)
        }
        lengths.sort()

        let gains = lengths.map { L -> Float in
            // Jot: g = 10^(−3·L/(RT60·fs)) → after RT60 s the line is −60 dB. Always < 1.
            let g = powf(10, -3 * Float(L) / (rt60 * fs))
            return Swift.min(0.9999, Swift.max(0, g.isFinite ? g : 0))
        }
        return Params(lengths: lengths, gains: gains)
    }

    // MARK: - Helpers

    static func clamp01(_ x: Float) -> Float { Swift.min(1, Swift.max(0, x)) }

    /// Smallest prime ≥ `n` not already used — deterministic prime search (no RNG).
    static func primeAtLeast(_ n: Int, excluding used: Set<Int>) -> Int {
        var c = Swift.max(2, n)
        while !isPrime(c) || used.contains(c) { c += 1 }
        return c
    }

    static func isPrime(_ n: Int) -> Bool {
        if n < 2 { return false }
        if n < 4 { return true }
        if n % 2 == 0 { return false }
        var i = 3
        while i * i <= n {
            if n % i == 0 { return false }
            i += 2
        }
        return true
    }
}
#endif
