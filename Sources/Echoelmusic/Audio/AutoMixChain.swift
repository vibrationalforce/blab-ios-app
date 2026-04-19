#if canImport(AVFoundation)
import AVFoundation
import Accelerate
import Observation

/// Transparent mastering chain inserted between masterMixer and mainMixerNode.
/// Makes any improv session sound release-ready without user intervention.
///
/// Graph after install: masterMixer → EQ → gainNode → mainMixerNode
///
/// Controls:
/// - isEnabled: bypass entire chain
/// - targetLUFS: auto-gain target (-14 streaming, -9 club, -23 broadcast)
/// - preset: tonal character (balanced / warm / bright / transparent)
@MainActor @Observable
final class AutoMixChain {

    // MARK: - Observable state

    var isEnabled: Bool = true {
        didSet { applyBypass() }
    }
    var targetLUFS: Float = -14 {          // Spotify / Apple Music standard
        didSet { updateAutoGain() }
    }
    private(set) var lufsReading: Float = -60
    private(set) var isInstalled: Bool = false

    // MARK: - Preset

    enum Preset: Equatable { case balanced, warm, bright, transparent }
    var preset: Preset = .balanced {
        didSet { applyPreset() }
    }

    // MARK: - AVAudio nodes

    @ObservationIgnored private let eq      = AVAudioUnitEQ(numberOfBands: 4)
    @ObservationIgnored private let gainNode = AVAudioMixerNode()

    // MARK: - LUFS meter (via metering timer reading masterLevel RMS)
    @ObservationIgnored private var masterLevelRef: (() -> Float)?
    @ObservationIgnored private var lufsTimer: Timer?

    // MARK: - Install

    /// Call from setupMasterEngine() BEFORE engine.start().
    /// Replaces the direct masterMixer → mainMixerNode connection.
    func insert(
        into engine: AVAudioEngine,
        from source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat
    ) {
        engine.attach(eq)
        engine.attach(gainNode)

        engine.connect(source,   to: eq,       format: format)
        engine.connect(eq,       to: gainNode, format: format)
        engine.connect(gainNode, to: destination, format: format)

        configureEQ()
        isInstalled = true
        log.audio("AutoMixChain inserted — EQ → gainNode → mainMixer")
    }

    /// Provide a closure that returns the current master RMS (0-1 linear).
    /// AutoMixChain uses this to compute LUFS and drive auto-gain.
    func connectMeter(_ getter: @escaping () -> Float) {
        masterLevelRef = getter
        lufsTimer?.invalidate()
        lufsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateLUFS() }
        }
    }

    // MARK: - LUFS update (called every 200ms on main thread)

    private func updateLUFS() {
        guard let getter = masterLevelRef else { return }
        let rmsLinear = getter() / 3.0          // undo the *3 scaling in AudioEngine meter
        guard rmsLinear > 0.0001 else {
            lufsReading = -60
            return
        }
        // BS.1770 approximation: LUFS ≈ dBFS - 0.1 (K-weighting offset)
        let dBFS = 20 * Foundation.log10(rmsLinear)
        lufsReading = dBFS - 0.1
        updateAutoGain()
    }

    private func updateAutoGain() {
        guard isInstalled, lufsReading > -59 else { return }
        let gainDB = Swift.min(Swift.max(targetLUFS - lufsReading, -12), 12)
        let linearGain = Foundation.pow(10.0, Double(gainDB) / 20.0)
        gainNode.outputVolume = Float(Swift.min(Swift.max(linearGain, 0.25), 4.0))
    }

    // MARK: - Node configuration

    private func configureEQ() {
        // Band 0: High-pass 40Hz — remove sub-bass rumble
        eq.bands[0].filterType  = .highPass
        eq.bands[0].frequency   = 40
        eq.bands[0].bypass      = false

        // Band 1: Low-shelf warmth +1.5dB at 180Hz
        eq.bands[1].filterType  = .lowShelf
        eq.bands[1].frequency   = 180
        eq.bands[1].gain        = 1.5
        eq.bands[1].bypass      = false

        // Band 2: Presence dip -1.5dB at 3kHz (tames harshness)
        eq.bands[2].filterType  = .parametric
        eq.bands[2].frequency   = 3000
        eq.bands[2].bandwidth   = 1.0
        eq.bands[2].gain        = -1.5
        eq.bands[2].bypass      = false

        // Band 3: Air shelf +2dB at 10kHz (clarity, openness)
        eq.bands[3].filterType  = .highShelf
        eq.bands[3].frequency   = 10000
        eq.bands[3].gain        = 2.0
        eq.bands[3].bypass      = false
    }

    // MARK: - Preset switching

    private func applyPreset() {
        switch preset {
        case .balanced:
            eq.bands[1].gain =  1.5
            eq.bands[2].gain = -1.5
            eq.bands[3].gain =  2.0
        case .warm:
            eq.bands[1].gain =  3.0
            eq.bands[2].gain = -2.5
            eq.bands[3].gain =  0.5
        case .bright:
            eq.bands[1].gain =  0.5
            eq.bands[2].gain = -0.5
            eq.bands[3].gain =  3.5
        case .transparent:
            eq.bands[1].gain =  0
            eq.bands[2].gain =  0
            eq.bands[3].gain =  0
        }
    }

    // MARK: - Bypass

    private func applyBypass() {
        eq.bypass = !isEnabled
        if !isEnabled { gainNode.outputVolume = 1.0 }
        log.audio("AutoMixChain \(isEnabled ? "enabled" : "bypassed")")
    }
}
#endif
