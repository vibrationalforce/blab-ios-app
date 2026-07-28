#if canImport(Accelerate)
import Foundation
import Accelerate

// MARK: - EchoelVDSPKit — Extended Accelerate DSP Utilities
// Real FFT, convolution, windowing, biquad cascades, and matrix ops.
//
// Fills the gaps identified in the vDSP usage analysis:
//  - Real FFT (vDSP_fft_zrop) — 100x faster than DFT for large N
//  - Convolution (vDSP_conv) — FIR filtering at SIMD speed
//  - Blackman/Kaiser windowing — better spectral leakage control
//  - Biquad cascade (vDSP_biquad) — multiband filtering
//  - Decimation (vDSP_desamp) — efficient downsampling
//
// Performance:
//  - All operations use pre-allocated buffers
//  - Zero runtime allocation in real-time paths
//  - Thread-safe for concurrent read access

// MARK: - Complex DFT Engine (Forward)

/// Managed wrapper around `vDSP_DFT_zop_CreateSetup` with overlapping-access-safe execution.
/// Replaces 6+ identical `vDSP_DFT_zop_CreateSetup / Execute / DestroySetup` patterns across the codebase.
///
/// Usage:
/// ```swift
/// let dft = EchoelComplexDFT(size: 2048)
/// let (outR, outI) = dft.forward(real: realIn, imag: imagIn)
/// ```
///
/// Thread-safety: NOT safe for concurrent use. `@unchecked Sendable` because instances
/// are stored in @MainActor classes but never accessed from multiple threads simultaneously.
/// Pre-allocated output buffers are mutated on each call.
public final class EchoelComplexDFT: @unchecked Sendable {

    public let size: Int
    private let setup: OpaquePointer?

    /// Whether the DFT setup was successfully created
    public var isValid: Bool { setup != nil }

    /// Pre-allocated output buffers (avoids overlapping access violations)
    private var outReal: [Float]
    private var outImag: [Float]

    /// Create a forward complex DFT of the given size.
    /// - Parameter size: Transform length (need not be power of 2).
    /// Falls back gracefully if vDSP setup allocation fails (returns zero output).
    public init(size: Int) {
        precondition(size > 0, "DFT size must be positive")
        // Try requested size, then fall back to smaller sizes on memory pressure
        if let s = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD) {
            self.size = size
            self.setup = s
        } else if size > 512, let s = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(512), .FORWARD) {
            self.size = 512
            self.setup = s
        } else if size > 256, let s = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(256), .FORWARD) {
            self.size = 256
            self.setup = s
        } else if let s = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(128), .FORWARD) {
            self.size = 128
            self.setup = s
        } else {
            // Catastrophic memory — degrade gracefully instead of crashing
            self.size = size
            self.setup = nil
        }
        self.outReal = [Float](repeating: 0, count: self.size)
        self.outImag = [Float](repeating: 0, count: self.size)
    }

    deinit {
        if let setup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Execute the forward DFT.
    /// Input arrays are copied internally to prevent overlapping access.
    /// - Returns: Tuple of (realOut, imagOut) arrays of length `size`. Returns zeros if setup failed.
    public func forward(real: [Float], imag: [Float]) -> (real: [Float], imag: [Float]) {
        guard let setup else {
            return (outReal, outImag)
        }
        var inReal = real
        var inImag = imag
        vDSP_DFT_Execute(setup, &inReal, &inImag, &outReal, &outImag)
        return (Array(outReal), Array(outImag))
    }
}

// MARK: - Real FFT Engine

/// Real-to-complex FFT using vDSP_fft_zrop for maximum performance.
/// ~100x faster than DFT for sizes >= 1024.
///
/// Thread-safety: NOT safe for concurrent use — mutable output buffers. Single-thread only.
public final class EchoelRealFFT: @unchecked Sendable {

    public let size: Int
    public let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    // Split complex buffers (pre-allocated)
    private var splitReal: [Float]
    private var splitImag: [Float]

    // Window buffer
    private var windowBuffer: [Float]
    /// Pre-allocated windowed input — avoids heap allocation in forward()/inverse()
    private var windowedBuffer: [Float]
    private var windowType: WindowType

    public enum WindowType: String, CaseIterable, Sendable {
        case hann = "Hann"
        case blackman = "Blackman"
        case hamming = "Hamming"
        case kaiser = "Kaiser"
        case flatTop = "FlatTop"
    }

    /// Initialize with FFT size (must be power of 2)
    public init(size requestedSize: Int = 2048, window: WindowType = .blackman) {
        precondition(requestedSize > 0 && (requestedSize & (requestedSize - 1)) == 0, "FFT size must be power of 2")

        let requestedLog2n = vDSP_Length(Int(Foundation.log2(Double(requestedSize))))

        // Try requested size first; fall back to 256-point FFT on memory pressure
        let actualSize: Int
        let actualLog2n: vDSP_Length
        let setup: FFTSetup

        if let s = vDSP_create_fftsetup(requestedLog2n, FFTRadix(kFFTRadix2)) {
            actualSize = requestedSize
            actualLog2n = requestedLog2n
            setup = s
        } else if let fallback256 = vDSP_create_fftsetup(8, FFTRadix(kFFTRadix2)) {
            // Fallback to 256-point FFT on memory pressure
            actualSize = 256
            actualLog2n = 8
            setup = fallback256
        } else if let fallback128 = vDSP_create_fftsetup(7, FFTRadix(kFFTRadix2)) {
            // Extreme fallback to 128-point FFT
            actualSize = 128
            actualLog2n = 7
            setup = fallback128
        } else if let fallback64 = vDSP_create_fftsetup(6, FFTRadix(kFFTRadix2)) {
            // Absolute minimum: 64-point FFT
            actualSize = 64
            actualLog2n = 6
            setup = fallback64
        } else {
            // Allocation failed entirely — last-resort minimal setup
            // This should never happen on any Apple hardware, but avoids a crash
            actualSize = 16
            actualLog2n = 4
            guard let lastResort = vDSP_create_fftsetup(4, FFTRadix(kFFTRadix2)) else {
                // If even a 16-point FFT fails, we are in catastrophic memory state.
                // Crash with a clear diagnostic rather than undefined behavior.
                preconditionFailure("EchoelRealFFT: cannot allocate even a 16-point FFT setup — system out of memory")
            }
            setup = lastResort
        }

        self.size = actualSize
        self.log2n = actualLog2n
        self.fftSetup = setup
        self.splitReal = [Float](repeating: 0, count: actualSize / 2)
        self.splitImag = [Float](repeating: 0, count: actualSize / 2)
        self.windowBuffer = [Float](repeating: 0, count: actualSize)
        self.windowedBuffer = [Float](repeating: 0, count: actualSize)
        self.windowType = window
        updateWindow(window)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Window Functions

    /// Update window function
    public func updateWindow(_ type: WindowType) {
        windowType = type
        switch type {
        case .hann:
            vDSP_hann_window(&windowBuffer, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        case .blackman:
            vDSP_blkman_window(&windowBuffer, vDSP_Length(size), 0)
        case .hamming:
            vDSP_hamm_window(&windowBuffer, vDSP_Length(size), 0)
        case .kaiser:
            // Kaiser window with beta=8 (good sidelobe suppression)
            for i in 0..<size {
                let n = 2.0 * Float(i) / Float(size - 1) - 1.0
                let arg = Float.pi * 8.0 * sqrt(max(0, 1.0 - n * n))
                // Approximate I0(x) for Kaiser
                windowBuffer[i] = besselI0(arg) / besselI0(Float.pi * 8.0)
            }
        case .flatTop:
            // Flat-top window for accurate amplitude measurement
            let a0: Float = 0.21557895
            let a1: Float = 0.41663158
            let a2: Float = 0.277263158
            let a3: Float = 0.083578947
            let a4: Float = 0.006947368
            for i in 0..<size {
                let x = 2.0 * Float.pi * Float(i) / Float(size - 1)
                windowBuffer[i] = a0 - a1 * cos(x) + a2 * cos(2 * x) - a3 * cos(3 * x) + a4 * cos(4 * x)
            }
        }
    }

    /// Modified Bessel function I0 (for Kaiser window)
    private func besselI0(_ x: Float) -> Float {
        var sum: Float = 1.0
        var term: Float = 1.0
        let x2 = x * x * 0.25
        for k in 1...20 {
            term *= x2 / Float(k * k)
            sum += term
            if term < 1e-10 { break }
        }
        return sum
    }

    // MARK: - Forward FFT

    /// Perform forward real FFT. Returns (magnitudes, phases) of size/2 bins.
    public func forward(_ input: [Float]) -> (magnitudes: [Float], phases: [Float]) {
        guard input.count >= size else {
            return ([Float](repeating: 0, count: size / 2),
                    [Float](repeating: 0, count: size / 2))
        }

        // Apply window
        // Use pre-allocated buffer — no heap allocation on audio thread
        vDSP_vmul(input, 1, windowBuffer, 1, &windowedBuffer, 1, vDSP_Length(size))

        // Pack into split complex
        windowedBuffer.withUnsafeBufferPointer { inBuf in
            splitReal.withUnsafeMutableBufferPointer { realBuf in
                splitImag.withUnsafeMutableBufferPointer { imagBuf in
                    guard let realBase = realBuf.baseAddress,
                          let imagBase = imagBuf.baseAddress,
                          let inBase = inBuf.baseAddress else { return }
                    var splitComplex = DSPSplitComplex(
                        realp: realBase,
                        imagp: imagBase
                    )
                    inBase.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(size / 2))
                    }
                    // Forward FFT
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
        }

        // Compute magnitudes and phases
        let halfSize = size / 2
        var magnitudes = [Float](repeating: 0, count: halfSize)
        var phases = [Float](repeating: 0, count: halfSize)

        splitReal.withUnsafeBufferPointer { realBuf in
            splitImag.withUnsafeBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress,
                      let imagBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realBase),
                    imagp: UnsafeMutablePointer(mutating: imagBase)
                )
                // Magnitudes
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
                // Phases
                vDSP_zvphas(&split, 1, &phases, 1, vDSP_Length(halfSize))
            }
        }

        // Scale
        var scale: Float = 1.0 / Float(size)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfSize))

        return (magnitudes, phases)
    }

    /// Perform forward FFT, returning only the power spectrum (magnitude squared)
    public func powerSpectrum(_ input: [Float]) -> [Float] {
        guard input.count >= size else {
            return [Float](repeating: 0, count: size / 2)
        }

        // Use pre-allocated buffer — no heap allocation on audio thread
        vDSP_vmul(input, 1, windowBuffer, 1, &windowedBuffer, 1, vDSP_Length(size))

        windowedBuffer.withUnsafeBufferPointer { inBuf in
            splitReal.withUnsafeMutableBufferPointer { realBuf in
                splitImag.withUnsafeMutableBufferPointer { imagBuf in
                    guard let realBase = realBuf.baseAddress,
                          let imagBase = imagBuf.baseAddress,
                          let inBase = inBuf.baseAddress else { return }
                    var splitComplex = DSPSplitComplex(
                        realp: realBase,
                        imagp: imagBase
                    )
                    inBase.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(size / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
        }

        let halfSize = size / 2
        var power = [Float](repeating: 0, count: halfSize)

        splitReal.withUnsafeBufferPointer { realBuf in
            splitImag.withUnsafeBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress,
                      let imagBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realBase),
                    imagp: UnsafeMutablePointer(mutating: imagBase)
                )
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(halfSize))
            }
        }

        var scale: Float = 1.0 / Float(size * size)
        vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(halfSize))

        return power
    }

    /// Get frequency for a given bin index
    public func frequencyForBin(_ bin: Int, sampleRate: Float) -> Float {
        return Float(bin) * sampleRate / Float(size)
    }
}

// MARK: - Convolution Engine

/// Fast FIR convolution using vDSP_conv for impulse response filtering
///
/// Thread-safety: NOT safe for concurrent use — mutable kernel/overlap buffers. Single-thread only.
public final class EchoelConvolution: @unchecked Sendable {

    private let kernelSize: Int
    private var kernel: [Float]                // IR, reversed for vDSP_conv
    /// Last (kernelSize-1) input samples — the streaming history (overlap-save).
    private var inputHistory: [Float]
    /// Pre-allocated [history ++ input] scratch, sized so vDSP_conv NEVER reads
    /// past the end: it reads `inputLength + kernelSize - 1` samples, and this
    /// buffer holds exactly `maxInputLength + kernelSize - 1`.
    private var convScratch: [Float]
    /// Pre-allocated output buffer — avoids heap allocation on every process() call.
    private var outputBuffer: [Float]
    private var maxInputLength: Int

    /// Initialize with FIR kernel
    public init(kernel: [Float], maxInputLength: Int = 2048) {
        self.kernelSize = max(1, kernel.count)
        // Reverse kernel for vDSP_conv (it correlates; reversed kernel → convolution).
        self.kernel = kernel.reversed()
        self.maxInputLength = max(1, maxInputLength)
        let hist = max(0, self.kernelSize - 1)
        self.inputHistory = [Float](repeating: 0, count: hist)
        self.convScratch = [Float](repeating: 0, count: self.maxInputLength + hist)
        self.outputBuffer = [Float](repeating: 0, count: self.maxInputLength + hist)
    }

    /// Update kernel coefficients IN PLACE — writes the reversed taps into the
    /// existing `kernel` storage without reseating the array reference, so a
    /// concurrent audio-thread reader (vDSP_conv) never sees a freed/reallocated
    /// buffer or a torn pointer. Worst case is one render block of mixed old/new
    /// taps (inaudible) — the same benign tradeoff used for the Float params.
    /// This is what makes live reverb-decay changes safe while audio is running.
    public func setKernel(_ newKernel: [Float]) {
        guard newKernel.count == kernelSize else { return }
        let n = kernelSize
        kernel.withUnsafeMutableBufferPointer { dst in
            newKernel.withUnsafeBufferPointer { src in
                guard let d = dst.baseAddress, let s = src.baseAddress else { return }
                for i in 0..<n { d[i] = s[n - 1 - i] }   // reversed, in place
            }
        }
    }

    /// Core overlap-save convolution: builds `convScratch = [history ++ input]`,
    /// convolves to produce exactly `inputLength` correctly-aligned output samples
    /// in `outputBuffer`, then refreshes the history. vDSP_conv reads
    /// `convScratch[0 ... inputLength + kernelSize - 2]`, always within bounds.
    /// Audio-thread safe: memcpy-style index writes only, no allocation.
    private func convolve(_ input: [Float], _ inputLength: Int) {
        let hist = kernelSize - 1
        convScratch.withUnsafeMutableBufferPointer { dst in
            guard let d = dst.baseAddress else { return }
            if hist > 0 {
                inputHistory.withUnsafeBufferPointer { h in
                    if let hb = h.baseAddress { d.update(from: hb, count: hist) }
                }
            }
            input.withUnsafeBufferPointer { s in
                if let sb = s.baseAddress { (d + hist).update(from: sb, count: inputLength) }
            }
        }
        // N = inputLength outputs; P = kernelSize. Reads convScratch up to
        // index inputLength + kernelSize - 2 (< convScratch.count). Safe.
        vDSP_conv(convScratch, 1, kernel, 1, &outputBuffer, 1,
                  vDSP_Length(inputLength), vDSP_Length(kernelSize))
        // New history = the last (kernelSize-1) samples of the stream, i.e. the
        // tail of convScratch ([history ++ input]).
        if hist > 0 {
            inputHistory.withUnsafeMutableBufferPointer { dst in
                guard let d = dst.baseAddress else { return }
                convScratch.withUnsafeBufferPointer { src in
                    guard let s = src.baseAddress else { return }
                    d.update(from: s + inputLength, count: hist)
                }
            }
        }
    }

    /// Apply convolution to an input buffer (allocating result — non-audio-thread
    /// callers only). Input is clamped to `maxInputLength` to keep bounds-safe.
    public func process(_ input: [Float]) -> [Float] {
        let inputLength = Swift.min(input.count, maxInputLength)
        guard inputLength > 0 else { return [] }
        convolve(input, inputLength)
        var result = Array(outputBuffer.prefix(inputLength))
        for i in 0..<result.count where !result[i].isFinite { result[i] = 0 }
        return result
    }

    /// Audio-thread-safe variant of `process(_:)` — writes the wet result into a
    /// caller-provided, pre-allocated `output` buffer (no allocation). `output`
    /// must have `count >= min(input.count, maxInputLength)`. Returns the number
    /// of valid samples written.
    @discardableResult
    public func process(_ input: [Float], into output: inout [Float]) -> Int {
        let inputLength = Swift.min(input.count, maxInputLength)
        guard inputLength > 0, output.count >= inputLength else { return 0 }
        convolve(input, inputLength)
        for i in 0..<inputLength {
            let v = outputBuffer[i]
            output[i] = v.isFinite ? v : 0
        }
        return inputLength
    }

    /// Clear streaming state so a reused convolution does not bleed the previous
    /// note's reverb tail into the next note assigned to a recycled voice.
    /// Audio-thread safe: index writes only, no allocation.
    public func reset() {
        for i in 0..<inputHistory.count { inputHistory[i] = 0 }
        for i in 0..<outputBuffer.count { outputBuffer[i] = 0 }
        for i in 0..<convScratch.count { convScratch[i] = 0 }
    }

    // MARK: - Factory Methods

    /// The smallest tap count at which ALL THREE factories return a finite, non-zero
    /// kernel. Not "the smallest that filters well" — the smallest that is defined.
    ///
    /// The Blackman window is zero at BOTH endpoints, so a short kernel is mostly
    /// endpoints, and each of the counts below it fails differently and SILENTLY:
    /// - `taps <= 0` → `[Float](repeating:count:)` **traps** on a negative count, as does
    ///   `highpassKernel`'s `for i in 0..<taps`.
    /// - `taps == 1` → the window divides by `Float(taps - 1)` == 0 → 0/0 → the kernel is
    ///   **NaN**. `sum > 0` is false for NaN, so the old normalize step skipped and
    ///   returned it as if fine.
    /// - `taps == 2` → both taps are endpoints → windowed to zero → an all-zero kernel →
    ///   **permanent silence**, and `sum > 0` is false for zero as well: same silence.
    /// - `taps == 3` → finite and non-zero, but only the centre tap survives the window,
    ///   so the lowpass normalizes to `[0, 1, 0]` — the identity. The HIGHPASS is then
    ///   `δ − δ`, i.e. an energy of ~3e-8 (≈ −150 dBFS): silence again, just a rounding
    ///   artefact away from exactly zero.
    ///
    /// So the bound is **5**: the first count with a non-endpoint tap on either side of
    /// the centre, which is what makes the spectral inversion in `highpassKernel` produce
    /// an actual highpass instead of a cancelled impulse. An earlier version of this
    /// constant was 3 and its doc called that "a filter at all" — measured, it is not.
    ///
    /// All of this is reachable from outside the module: `EchoelDecimator(factor:
    /// filterTaps:)` hands `filterTaps` straight through, and all three factories are
    /// `public`.
    public static let minimumKernelTaps = 5

    /// The tap count all three factories actually use.
    ///
    /// They MUST agree — `bandpassKernel` adds a lowpass and a highpass element-wise over
    /// `taps` samples, so a disagreement reads past the end of one of them. Idempotent,
    /// so the double application (here and again inside a delegated call) is harmless.
    ///
    /// `| 1` FORCES AN ODD LENGTH, and that is a correctness fix, not tidiness:
    /// `highpassKernel` does `lp[taps / 2] += 1.0`, a spectral inversion that assumes a
    /// true integer centre tap (Type-I linear phase). An even length has no centre, so
    /// the inversion lands off-centre and the response is wrong — a pre-existing defect
    /// that was one line away from this, the only chokepoint all three share. No caller
    /// is affected: the sole production call site asks for 63 and the tests for 31, both
    /// odd. An even REQUEST now comes back one sample longer; callers read `.count`.
    private static func usableTaps(_ taps: Int) -> Int {
        Swift.max(minimumKernelTaps, taps) | 1
    }

    /// A kernel that changes nothing: unity at the centre tap, zero elsewhere.
    ///
    /// This is the fallback for every degenerate request, and the choice is deliberate.
    /// The two alternatives are worse in this app specifically: zeros are permanent
    /// silence (indistinguishable, at the end of the chain, from a dead audio route —
    /// this codebase has shipped that bug), and NaN poisons every downstream accumulator
    /// it touches. A passthrough loses the filtering and keeps the instrument audible,
    /// which is the failure a performer can hear and a test can catch.
    private static func passthroughKernel(taps: Int) -> [Float] {
        var kernel = [Float](repeating: 0, count: usableTaps(taps))
        kernel[kernel.count / 2] = 1.0
        return kernel
    }

    /// Create a lowpass FIR filter kernel
    ///
    /// Degenerate input (see `minimumKernelTaps`) yields a unity passthrough of at least
    /// `minimumKernelTaps` samples rather than NaN, zeros, or a trap. INSIDE the valid
    /// range — `taps >= 3`, finite positive `sampleRate`, `0 < cutoffHz <= Nyquist` — the
    /// result is bit-identical to the unguarded design; this bound must not be audible.
    public static func lowpassKernel(cutoffHz: Float, sampleRate: Float, taps: Int = 127) -> [Float] {
        let taps = usableTaps(taps)
        // Non-finite in, non-finite out: `fc` would be inf or NaN and `sin(inf)` is NaN.
        // Checked BEFORE the divide. `sampleRate > 0` is doing two jobs — it rejects a
        // negative rate AND it excludes the 0/0 that is the only way a finite÷finite
        // quotient becomes NaN.
        guard cutoffHz.isFinite, sampleRate.isFinite, sampleRate > 0 else {
            return passthroughKernel(taps: taps)
        }
        // Clamp into the only band a sampled sinc can express. Above Nyquist it aliases;
        // at or below zero it collapses to an all-zero kernel. The lower bound is a tiny
        // positive number rather than zero on purpose: a 0 Hz request then designs the
        // lowest lowpass this kernel CAN express (a near-DC filter), which is what the
        // caller asked for, instead of falling through to a passthrough that would let
        // everything past.
        // Argument order matters: `max(x, y)` is `y >= x ? y : x`, so the known-good value
        // goes FIRST and a NaN can never survive the clamp (CLAUDE.md's `max(NaN, 0)`
        // rule). The guard above already makes NaN unreachable here — this is
        // defence-in-depth for whoever relaxes that guard, and it costs nothing.
        let fc = Swift.min(Swift.max(1e-6, cutoffHz / sampleRate), 0.5)
        var kernel = [Float](repeating: 0, count: taps)
        let m = Float(taps - 1) / 2.0

        for i in 0..<taps {
            let n = Float(i) - m
            if n == 0 {
                kernel[i] = 2.0 * fc
            } else {
                kernel[i] = sin(2.0 * Float.pi * fc * n) / (Float.pi * n)
            }
            // Blackman window
            let w = 0.42 - 0.5 * cos(2.0 * Float.pi * Float(i) / Float(taps - 1))
                + 0.08 * cos(4.0 * Float.pi * Float(i) / Float(taps - 1))
            kernel[i] *= Float(w)
        }

        // Normalize to unity DC gain.
        var sum: Float = 0
        vDSP_sve(kernel, 1, &sum, vDSP_Length(taps))
        // `sum > 0` alone was NOT a guard — it was how the two silent failures escaped:
        // the comparison is false for NaN and false for an all-zero kernel alike, so both
        // fell straight through to `return kernel` unnormalized. Make the else-branch say
        // what it means. Everything above is guarded now, so reaching here would be a new
        // defect rather than a known input, and a passthrough is the honest answer to it.
        guard sum.isFinite, sum > 0 else { return passthroughKernel(taps: taps) }
        kernel.withUnsafeMutableBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            vDSP_vsdiv(ptr, 1, &sum, ptr, 1, vDSP_Length(taps))
        }

        return kernel
    }

    /// Create a highpass FIR filter kernel
    ///
    /// Same degenerate-input contract as `lowpassKernel`, and it must clamp `taps` with
    /// the SAME helper: it indexes the lowpass result directly, so a disagreement about
    /// length is an out-of-bounds read, not a cosmetic mismatch.
    public static func highpassKernel(cutoffHz: Float, sampleRate: Float, taps: Int = 127) -> [Float] {
        let taps = usableTaps(taps)
        // ⚠️ THIS GUARD CANNOT BE DELEGATED, and the first version of this fix wrongly
        // assumed it could. Spectral inversion is `δ − lowpass`, so when `lowpassKernel`
        // returns its passthrough fallback (δ) for a degenerate rate or cutoff, this
        // computes `δ − δ` = an ALL-ZERO kernel. That is precisely the permanent silence
        // the fallback exists to prevent — the bug survived the fix, in the one third of
        // the API that inverts it. Measured before this line existed:
        // `highpassKernel(cutoffHz: .nan, sampleRate: 48000)` → total energy 0.0.
        guard cutoffHz.isFinite, sampleRate.isFinite, sampleRate > 0 else {
            return passthroughKernel(taps: taps)
        }
        var lp = lowpassKernel(cutoffHz: cutoffHz, sampleRate: sampleRate, taps: taps)
        // Spectral inversion
        for i in 0..<taps { lp[i] = -lp[i] }
        lp[taps / 2] += 1.0
        return lp
    }

    /// Create a bandpass FIR filter kernel
    ///
    /// `vDSP_vadd` reads `taps` elements out of BOTH halves — the shared `usableTaps`
    /// clamp is what keeps that in bounds when a caller asks for fewer.
    public static func bandpassKernel(lowHz: Float, highHz: Float, sampleRate: Float, taps: Int = 127) -> [Float] {
        let taps = usableTaps(taps)
        // Guarded here too, for a quieter reason than the other two: a non-finite `lowHz`
        // alone does not silence this: the highpass half collapses and the sum is just
        // the lowpass. No NaN, no zeros — a BANDPASS request answered with a LOWPASS.
        // Wrong filter, no complaint, nothing in a spectrum plot that says "degenerate
        // input" rather than "that is how this bandpass sounds".
        guard lowHz.isFinite, highHz.isFinite, sampleRate.isFinite, sampleRate > 0 else {
            return passthroughKernel(taps: taps)
        }
        let lp = lowpassKernel(cutoffHz: highHz, sampleRate: sampleRate, taps: taps)
        let hp = highpassKernel(cutoffHz: lowHz, sampleRate: sampleRate, taps: taps)
        var bp = [Float](repeating: 0, count: taps)
        vDSP_vadd(lp, 1, hp, 1, &bp, 1, vDSP_Length(taps))
        return bp
    }
}

// MARK: - Biquad Cascade Filter

/// Hardware-accelerated biquad cascade using vDSP_biquad
///
/// Thread-safety: NOT safe for concurrent use — mutable state/coefficient arrays. Single-thread only.
public final class EchoelBiquadCascade: @unchecked Sendable {

    /// Maximum sections (each section = 2nd order IIR = 12dB/oct)
    public let sectionCount: Int

    /// Coefficients: [b0, b1, b2, a1, a2] per section, flattened
    private var coefficients: [Double]

    /// Internal delay state (Float for vDSP_biquad processing)
    private var delays: [Float]

    /// vDSP biquad setup
    private var setup: vDSP_biquad_Setup?

    public init(sectionCount: Int = 4) {
        self.sectionCount = sectionCount
        self.coefficients = [Double](repeating: 0, count: sectionCount * 5)
        self.delays = [Float](repeating: 0, count: (sectionCount + 1) * 2)

        // Initialize as passthrough (b0=1, rest=0)
        for i in 0..<sectionCount {
            coefficients[i * 5] = 1.0 // b0
        }

        rebuildSetup()
    }

    deinit {
        if let setup = setup {
            vDSP_biquad_DestroySetup(setup)
        }
    }

    // MARK: - Configuration

    /// Set a parametric EQ band
    public func setParametricEQ(section: Int, frequency: Float, gain: Float, q: Float, sampleRate: Float) {
        guard section >= 0, section < sectionCount else { return }   // section*5 must not index negative
        guard q > Float.ulpOfOne, sampleRate > Float.ulpOfOne else { return }

        let a = pow(10.0, Double(gain) / 40.0)
        let w0 = 2.0 * Double.pi * Double(frequency) / Double(sampleRate)
        let alpha = sin(w0) / (2.0 * Double(q))

        let b0 = 1.0 + alpha * a
        let b1 = -2.0 * cos(w0)
        let b2 = 1.0 - alpha * a
        let a0 = 1.0 + alpha / a
        let a1 = -2.0 * cos(w0)
        let a2 = 1.0 - alpha / a

        let idx = section * 5
        coefficients[idx + 0] = b0 / a0
        coefficients[idx + 1] = b1 / a0
        coefficients[idx + 2] = b2 / a0
        coefficients[idx + 3] = a1 / a0
        coefficients[idx + 4] = a2 / a0

        rebuildSetup()
    }

    /// Set a lowpass filter on given section
    public func setLowpass(section: Int, frequency: Float, q: Float = 0.707, sampleRate: Float) {
        guard section >= 0, section < sectionCount else { return }   // section*5 must not index negative
        guard q > Float.ulpOfOne, sampleRate > Float.ulpOfOne else { return }

        let w0 = 2.0 * Double.pi * Double(frequency) / Double(sampleRate)
        let alpha = sin(w0) / (2.0 * Double(q))

        let b1 = 1.0 - cos(w0)
        let b0 = b1 / 2.0
        let b2 = b0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cos(w0)
        let a2 = 1.0 - alpha

        let idx = section * 5
        coefficients[idx + 0] = b0 / a0
        coefficients[idx + 1] = b1 / a0
        coefficients[idx + 2] = b2 / a0
        coefficients[idx + 3] = a1 / a0
        coefficients[idx + 4] = a2 / a0

        rebuildSetup()
    }

    /// Set a highpass filter on given section
    public func setHighpass(section: Int, frequency: Float, q: Float = 0.707, sampleRate: Float) {
        guard section >= 0, section < sectionCount else { return }   // section*5 must not index negative
        guard q > Float.ulpOfOne, sampleRate > Float.ulpOfOne else { return }

        let w0 = 2.0 * Double.pi * Double(frequency) / Double(sampleRate)
        let alpha = sin(w0) / (2.0 * Double(q))

        let cosW0 = cos(w0)
        let b0 = (1.0 + cosW0) / 2.0
        let b1 = -(1.0 + cosW0)
        let b2 = b0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha

        let idx = section * 5
        coefficients[idx + 0] = b0 / a0
        coefficients[idx + 1] = b1 / a0
        coefficients[idx + 2] = b2 / a0
        coefficients[idx + 3] = a1 / a0
        coefficients[idx + 4] = a2 / a0

        rebuildSetup()
    }

    private func rebuildSetup() {
        if let old = setup {
            vDSP_biquad_DestroySetup(old)
        }
        setup = vDSP_biquad_CreateSetup(coefficients, vDSP_Length(sectionCount))
        delays = [Float](repeating: 0, count: (sectionCount + 1) * 2)
    }

    // MARK: - Processing

    /// Process audio buffer through biquad cascade
    public func process(_ input: [Float]) -> [Float] {
        guard let setup = setup else { return input }

        let count = input.count
        var output = [Float](repeating: 0, count: count)

        // vDSP_biquad processes Float signals (setup uses Double coefficients internally)
        vDSP_biquad(setup, &delays, input, 1, &output, 1, vDSP_Length(count))

        // NaN/Inf guard — IIR filters can go unstable with extreme coefficients
        for i in 0..<count where !output[i].isFinite {
            output[i] = 0
        }

        return output
    }

    /// Reset filter state
    public func reset() {
        delays = [Float](repeating: 0, count: (sectionCount + 1) * 2)
    }
}

// MARK: - Decimator (Sample Rate Reduction)

/// Efficient decimation using vDSP_desamp for multirate DSP
///
/// Thread-safety: NOT safe for concurrent use — mutable anti-alias filter. Single-thread only.
public final class EchoelDecimator: @unchecked Sendable {

    public let factor: Int
    private var antiAliasFilter: [Float]

    /// Initialize with decimation factor and anti-alias filter taps
    public init(factor: Int, filterTaps: Int = 63) {
        let safeFactor = max(1, factor)
        self.factor = safeFactor
        // Design anti-alias lowpass at Nyquist/factor
        self.antiAliasFilter = EchoelConvolution.lowpassKernel(
            cutoffHz: 1.0 / Float(2 * safeFactor),
            sampleRate: 1.0,
            taps: filterTaps
        )
    }

    /// Decimate a COMPLETE, FINITE signal (allocating result — non-audio-thread callers
    /// only; it allocates twice, since the tail pad forces a copy of the input).
    ///
    /// ONE-SHOT CONTRACT — do NOT call this per block on a continuous stream:
    /// - Returns `input.count / factor` samples; `input.count % factor` trailing input
    ///   samples are DISCARDED (per block that would be progressive time drift).
    /// - The tail is zero-padded, so the last `(taps - 1) / (2 · factor)` outputs taper
    ///   toward zero (31 of 64 for the 63-tap default at factor 2). Per block that is
    ///   not a subtle seam but an amplitude notch plus phase break at every boundary.
    /// - The output LEADS the input by `(taps - 1) / 2` input samples (31 by default):
    ///   `output[n]` is the filter centred on `input[n·factor + 31]`.
    /// Streaming needs a different shape entirely — pre-allocated scratch, overlap-save
    /// history and a leftover carry, like `EchoelConvolution` above. Add that as its own
    /// type rather than changing these semantics under existing callers.
    ///
    /// WHY THE PAD EXISTS. `vDSP_desamp` computes
    /// `output[n] = Σ_k filter[k] · input[n·factor + k]`, and Apple documents the
    /// required input length as `(outputLength - 1) · factor + roundUpToMultipleOf4(taps)`
    /// — the rounding is the SIMD tap block, which is why padding to the bare `taps`
    /// still under-provisions by up to 3 elements. Before this pad the call read far
    /// past the end of `input`: about 60 floats of foreign memory, for essentially every
    /// input length (61 at factor 2 with an even count, 60 with an odd one, and
    /// `59 - count % 4` at factor 4 — it is not the single constant an earlier version
    /// of this comment claimed). The result was therefore nondeterministic, which is how
    /// it surfaced: `EchoelDecimatorTests.testNoNaN` is fully deterministic — fixed
    /// input, fresh instance, no clock, no RNG — yet passed one CI run and failed the
    /// next on identical code.
    public func process(_ input: [Float]) -> [Float] {
        let outputLength = input.count / factor
        guard outputLength > 0 else { return [] }

        let filterLength = antiAliasFilter.count
        // Round the tap count up to the 4-wide block vDSP actually reads, not the bare
        // tap count — see the doc above. Cheap: at worst 3 extra zeros.
        let alignedTaps = (filterLength + 3) & ~3
        let required = (outputLength - 1) * factor + alignedTaps
        var padded = input
        if required > padded.count {
            padded.append(contentsOf: repeatElement(0, count: required - padded.count))
        }

        var output = [Float](repeating: 0, count: outputLength)

        vDSP_desamp(padded, vDSP_Stride(factor), antiAliasFilter, &output,
                    vDSP_Length(outputLength), vDSP_Length(filterLength))

        return output
    }
}

// MARK: - Spectral Analysis Utilities

/// High-level spectral analysis combining Real FFT with band extraction
public struct EchoelSpectralAnalyzer {

    private let fft: EchoelRealFFT
    public let sampleRate: Float

    public init(size: Int = 2048, sampleRate: Float = 48000, window: EchoelRealFFT.WindowType = .blackman) {
        self.fft = EchoelRealFFT(size: size, window: window)
        self.sampleRate = sampleRate
    }

    /// Get power in a frequency band (Hz range)
    public func bandPower(_ input: [Float], band: ClosedRange<Float>) -> Float {
        let spectrum = fft.powerSpectrum(input)
        let freqRes = sampleRate / Float(fft.size)
        let startBin = max(0, Int(band.lowerBound / freqRes))
        let endBin = min(spectrum.count - 1, Int(band.upperBound / freqRes))
        guard startBin <= endBin else { return 0 }

        var sum: Float = 0
        let slice = Array(spectrum[startBin...endBin])
        vDSP_sve(slice, 1, &sum, vDSP_Length(slice.count))
        return sum
    }

    /// Find dominant frequency in a band
    public func dominantFrequency(_ input: [Float], band: ClosedRange<Float>) -> Float {
        let spectrum = fft.powerSpectrum(input)
        let freqRes = sampleRate / Float(fft.size)
        let startBin = max(0, Int(band.lowerBound / freqRes))
        let endBin = min(spectrum.count - 1, Int(band.upperBound / freqRes))
        guard startBin <= endBin else { return 0 }

        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        let slice = Array(spectrum[startBin...endBin])
        vDSP_maxvi(slice, 1, &maxVal, &maxIdx, vDSP_Length(slice.count))

        return Float(startBin + Int(maxIdx)) * freqRes
    }

    /// Full spectral centroid (brightness indicator)
    public func spectralCentroid(_ input: [Float]) -> Float {
        let spectrum = fft.powerSpectrum(input)
        let freqRes = sampleRate / Float(fft.size)

        var weightedSum: Float = 0
        var totalPower: Float = 0
        for i in 0..<spectrum.count {
            weightedSum += spectrum[i] * Float(i) * freqRes
            totalPower += spectrum[i]
        }
        return totalPower > 0 ? weightedSum / totalPower : 0
    }
}
#endif
