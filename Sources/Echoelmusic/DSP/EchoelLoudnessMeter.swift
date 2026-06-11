import Foundation

/// ITU-R BS.1770 loudness meter — K-weighted, gated mean-square loudness in LUFS.
/// Provides momentary (400 ms) and short-term (3 s) loudness over sliding
/// windows. Audio-thread safe: ring buffers are pre-allocated at init, the
/// per-sample path does only filtering and O(1) running-sum updates.
///
/// K-weighting coefficients are the canonical 48 kHz set (stage-1 high-shelf +
/// stage-2 RLB high-pass). The app runs at 48 kHz; at other rates this is a
/// close approximation (coefficients are not re-derived per rate).
///
/// Reference: ITU-R BS.1770-4; EBU R128.
public final class EchoelLoudnessMeter: @unchecked Sendable {

    public static let floorLUFS: Float = -120

    public private(set) var momentaryLUFS: Float = floorLUFS
    public private(set) var shortTermLUFS: Float = floorLUFS

    // MARK: - K-weighting biquads (per channel)

    private var kL1 = Biquad.kStage1()
    private var kL2 = Biquad.kStage2()
    private var kR1 = Biquad.kStage1()
    private var kR2 = Biquad.kStage2()

    // MARK: - Sliding windows (squared, K-weighted)

    private var mRing: [Float]
    private var sRing: [Float]
    private let mLen: Int
    private let sLen: Int
    private var mIdx = 0
    private var sIdx = 0
    private var mSum: Double = 0
    private var sSum: Double = 0

    private static let offsetLUFS: Float = -0.691  // BS.1770 absolute offset

    public init(sampleRate: Float = 48000) {
        self.mLen = Swift.max(1, Int(0.4 * sampleRate))
        self.sLen = Swift.max(1, Int(3.0 * sampleRate))
        self.mRing = [Float](repeating: 0, count: mLen)
        self.sRing = [Float](repeating: 0, count: sLen)
    }

    // MARK: - Process

    /// Measure a mono buffer (channel weight 1.0). Audio-thread safe.
    public func process(_ buf: [Float], frameCount: Int) {
        let n = Swift.min(frameCount, buf.count)
        guard n > 0 else { return }
        for i in 0..<n {
            let y = kL2.process(kL1.process(buf[i]))
            accumulate(Double(y * y))
        }
        updateReadings()
    }

    /// Measure a stereo pair — sum of K-weighted channel powers (L,R weight 1.0).
    public func processStereo(left: [Float], right: [Float], frameCount: Int) {
        let n = Swift.min(frameCount, Swift.min(left.count, right.count))
        guard n > 0 else { return }
        for i in 0..<n {
            let yl = kL2.process(kL1.process(left[i]))
            let yr = kR2.process(kR1.process(right[i]))
            accumulate(Double(yl * yl + yr * yr))
        }
        updateReadings()
    }

    /// Measure a stereo pair from raw channel pointers — no allocation, for use
    /// inside an `AVAudioEngine` tap callback. `right` may be nil for mono (the
    /// left channel is then used for both sides).
    public func processStereo(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, frameCount n: Int) {
        guard n > 0 else { return }
        for i in 0..<n {
            let l = left[i]
            let r = right?[i] ?? l
            let yl = kL2.process(kL1.process(l))
            let yr = kR2.process(kR1.process(r))
            accumulate(Double(yl * yl + yr * yr))
        }
        updateReadings()
    }

    public func reset() {
        kL1.reset(); kL2.reset(); kR1.reset(); kR2.reset()
        for i in 0..<mLen { mRing[i] = 0 }
        for i in 0..<sLen { sRing[i] = 0 }
        mIdx = 0; sIdx = 0; mSum = 0; sSum = 0
        momentaryLUFS = Self.floorLUFS
        shortTermLUFS = Self.floorLUFS
    }

    // MARK: - Internals

    @inline(__always)
    private func accumulate(_ sq: Double) {
        mSum += sq - Double(mRing[mIdx]); mRing[mIdx] = Float(sq)
        mIdx += 1; if mIdx >= mLen { mIdx = 0 }
        sSum += sq - Double(sRing[sIdx]); sRing[sIdx] = Float(sq)
        sIdx += 1; if sIdx >= sLen { sIdx = 0 }
    }

    @inline(__always)
    private func updateReadings() {
        momentaryLUFS = loudness(meanSquare: mSum / Double(mLen))
        shortTermLUFS = loudness(meanSquare: sSum / Double(sLen))
    }

    @inline(__always)
    private func loudness(meanSquare: Double) -> Float {
        guard meanSquare > 1e-12 else { return Self.floorLUFS }
        return Self.offsetLUFS + 10.0 * Float(log10(meanSquare))
    }

    // MARK: - Biquad (Direct Form II transposed)

    private struct Biquad {
        let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        var s1: Float = 0
        var s2: Float = 0

        @inline(__always)
        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + s1
            s1 = b1 * x + s2 - a1 * y
            s2 = b2 * x - a2 * y
            return y
        }

        mutating func reset() { s1 = 0; s2 = 0 }

        /// Stage 1 — high-shelf "head" filter (BS.1770, 48 kHz).
        static func kStage1() -> Biquad {
            Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                   a1: -1.69065929318241, a2: 0.73248077421585)
        }

        /// Stage 2 — RLB high-pass (BS.1770, 48 kHz).
        static func kStage2() -> Biquad {
            Biquad(b0: 1.0, b1: -2.0, b2: 1.0,
                   a1: -1.99004745483398, a2: 0.99007225036621)
        }
    }
}
