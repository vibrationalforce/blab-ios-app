import Foundation

/// Ordered, audio-thread-safe composition of the EchoelFX processors — the unit
/// the render block, UI, and (later) AUv3 wrapper drive. Signal flow:
///
///   in → chorus → flanger → phaser → tremolo → delay → compressor → limiter → out
///
/// Each stage is individually bypassable; a bypassed stage is skipped entirely
/// (no work, no state advance). The limiter sits last as a safety brick-wall and
/// is enabled by default. No allocation or locks in the hot loop.
public final class EchoelFXChain: @unchecked Sendable {

    // MARK: - Stages

    public let chorus: EchoelChorus
    public let flanger: EchoelFlanger
    public let phaser: EchoelPhaser
    public let tremolo: EchoelTremolo
    public let delay: EchoelDelay
    public let compressor: EchoelCompressor
    public let limiter: EchoelLimiter

    // MARK: - Per-stage bypass (plain reads on the audio thread)

    public var chorusEnabled: Bool = false
    public var flangerEnabled: Bool = false
    public var phaserEnabled: Bool = false
    public var tremoloEnabled: Bool = false
    public var delayEnabled: Bool = false
    public var compressorEnabled: Bool = false
    public var limiterEnabled: Bool = true

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.chorus = EchoelChorus(sampleRate: sampleRate)
        self.flanger = EchoelFlanger(sampleRate: sampleRate)
        self.phaser = EchoelPhaser(sampleRate: sampleRate)
        self.tremolo = EchoelTremolo(sampleRate: sampleRate)
        self.delay = EchoelDelay(sampleRate: sampleRate)
        self.compressor = EchoelCompressor(sampleRate: sampleRate)
        self.limiter = EchoelLimiter(sampleRate: sampleRate)
    }

    // MARK: - Process

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        var l = inL
        var r = inR
        if chorusEnabled     { (l, r) = chorus.processStereo(l, r) }
        if flangerEnabled    { (l, r) = flanger.processStereo(l, r) }
        if phaserEnabled     { (l, r) = phaser.processStereo(l, r) }
        if tremoloEnabled    { (l, r) = tremolo.processStereo(l, r) }
        if delayEnabled      { (l, r) = delay.processStereo(l, r) }
        if compressorEnabled { (l, r) = compressor.processStereo(l, r) }
        if limiterEnabled    { (l, r) = limiter.processStereo(l, r) }
        return (l, r)
    }

    /// Process separate L/R buffers in place.
    public func processBuffer(left bufL: inout [Float], right bufR: inout [Float], frameCount: Int) {
        let n = Swift.min(frameCount, Swift.min(bufL.count, bufR.count))
        for i in 0..<n {
            let (l, r) = processStereo(bufL[i], bufR[i])
            bufL[i] = l
            bufR[i] = r
        }
    }

    /// Process a mono buffer in place — the chain runs with both channels fed
    /// the same sample and the left result is taken back. Used by mono source
    /// nodes (e.g. the bio synth voice). Audio-thread safe.
    public func processBufferMono(_ buf: inout [Float], frameCount: Int) {
        let n = Swift.min(frameCount, buf.count)
        for i in 0..<n {
            let x = buf[i]
            let (l, _) = processStereo(x, x)
            buf[i] = l
        }
    }

    // MARK: - Reset

    public func reset() {
        chorus.reset()
        flanger.reset()
        phaser.reset()
        tremolo.reset()
        delay.reset()
        compressor.reset()
        limiter.reset()
    }
}
