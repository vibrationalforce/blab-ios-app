import Foundation

/// Peak / RMS / true-peak meter. Audio-thread safe (no allocation or locks in
/// the measurement loop). True-peak uses a 4× inter-sample estimate via
/// Catmull-Rom interpolation combined with the raw sample peak, so the reported
/// true-peak is always ≥ the sample peak — catching inter-sample overs that a
/// plain sample meter misses (cf. ITU-R BS.1770 true-peak intent).
///
/// Readings are held with per-call decay so a UI meter falls back smoothly;
/// `reset()` returns to the −120 dB floor.
public final class EchoelMeter: @unchecked Sendable {

    public static let floorDb: Float = -120

    /// Held sample-peak level in dBFS.
    public private(set) var peakDb: Float = floorDb
    /// Block RMS level in dBFS.
    public private(set) var rmsDb: Float = floorDb
    /// Held true-peak (inter-sample) level in dBTP.
    public private(set) var truePeakDb: Float = floorDb
    /// Max-hold true-peak (dBTP) — the highest inter-sample peak since the last
    /// `reset()`, never decays. Pro mastering reference for "did it ever clip".
    public private(set) var truePeakMaxDb: Float = floorDb

    /// Per-call hold decay (linear multiplier applied to the held peak before
    /// taking the max with the new block). 1.0 = infinite hold.
    public var holdDecay: Float = 0.85

    private var heldPeak: Float = 0
    private var heldTruePeak: Float = 0
    private var maxTruePeak: Float = 0

    // Cubic interpolation history (last three input samples).
    private var z1: Float = 0
    private var z2: Float = 0
    private var z3: Float = 0

    public init() {}

    // MARK: - Process

    /// Measure a mono buffer. Audio-thread safe.
    public func process(_ buf: [Float], frameCount: Int) {
        let n = Swift.min(frameCount, buf.count)
        guard n > 0 else { return }
        var peak: Float = 0
        var sumSq: Float = 0
        var tp: Float = 0
        for i in 0..<n {
            let x = buf[i]
            let a = abs(x)
            if a > peak { peak = a }
            sumSq += x * x
            let inter = interSampleMax(z3, z2, z1, x)
            if inter > tp { tp = inter }
            z3 = z2; z2 = z1; z1 = x
        }
        if peak > tp { tp = peak }   // true-peak is never below sample peak
        commit(peak: peak, rms: sqrtf(sumSq / Float(n)), truePeak: tp)
    }

    /// Measure a stereo pair, linking channels (the louder side drives the meter).
    public func processStereo(left: [Float], right: [Float], frameCount: Int) {
        let n = Swift.min(frameCount, Swift.min(left.count, right.count))
        guard n > 0 else { return }
        var peak: Float = 0
        var sumSq: Float = 0
        var tp: Float = 0
        for i in 0..<n {
            let l = left[i], r = right[i]
            let a = Swift.max(abs(l), abs(r))
            if a > peak { peak = a }
            sumSq += (l * l + r * r) * 0.5
            let inter = Swift.max(interSampleMax(z3, z2, z1, l), interSampleMax(z3, z2, z1, r))
            if inter > tp { tp = inter }
            z3 = z2; z2 = z1; z1 = a
        }
        if peak > tp { tp = peak }
        commit(peak: peak, rms: sqrtf(sumSq / Float(n)), truePeak: tp)
    }

    public func reset() {
        peakDb = Self.floorDb; rmsDb = Self.floorDb; truePeakDb = Self.floorDb
        truePeakMaxDb = Self.floorDb
        heldPeak = 0; heldTruePeak = 0; maxTruePeak = 0
        z1 = 0; z2 = 0; z3 = 0
    }

    /// Measure a stereo pair from raw channel pointers — no allocation, for use
    /// inside an `AVAudioEngine` tap callback. `right` may be nil for mono (the
    /// left channel is then used for both sides). Channels are linked: the louder
    /// side drives the meter.
    public func processStereo(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, frameCount n: Int) {
        guard n > 0 else { return }
        var peak: Float = 0
        var sumSq: Float = 0
        var tp: Float = 0
        for i in 0..<n {
            let l = left[i]
            let r = right?[i] ?? l
            let a = Swift.max(abs(l), abs(r))
            if a > peak { peak = a }
            sumSq += (l * l + r * r) * 0.5
            let inter = Swift.max(interSampleMax(z3, z2, z1, l), interSampleMax(z3, z2, z1, r))
            if inter > tp { tp = inter }
            z3 = z2; z2 = z1; z1 = a
        }
        if peak > tp { tp = peak }
        commit(peak: peak, rms: sqrtf(sumSq / Float(n)), truePeak: tp)
    }

    // MARK: - Helpers

    @inline(__always)
    private func commit(peak: Float, rms: Float, truePeak: Float) {
        heldPeak = Swift.max(peak, heldPeak * holdDecay)
        heldTruePeak = Swift.max(truePeak, heldTruePeak * holdDecay)
        maxTruePeak = Swift.max(maxTruePeak, truePeak)
        peakDb = Self.db(heldPeak)
        truePeakDb = Self.db(heldTruePeak)
        truePeakMaxDb = Self.db(maxTruePeak)
        rmsDb = Self.db(rms)
    }

    /// Max |Catmull-Rom| at t ∈ {0.25, 0.5, 0.75} between p1 and p2.
    /// Fully unrolled — no array literal — so it is allocation-free on the
    /// audio thread (called twice per sample from the stereo path).
    @inline(__always)
    private func interSampleMax(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float) -> Float {
        let a = abs(catmullRom(p0, p1, p2, p3, 0.25))
        let b = abs(catmullRom(p0, p1, p2, p3, 0.5))
        let c = abs(catmullRom(p0, p1, p2, p3, 0.75))
        return Swift.max(a, Swift.max(b, c))
    }

    @inline(__always)
    private func catmullRom(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ t: Float) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (2 * p1
            + (-p0 + p2) * t
            + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
            + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    public static func db(_ linear: Float) -> Float {
        guard linear > 1e-6 else { return floorDb }
        return Swift.max(floorDb, 20.0 * log10f(linear))
    }
}
