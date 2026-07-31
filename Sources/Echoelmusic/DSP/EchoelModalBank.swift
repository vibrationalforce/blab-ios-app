#if canImport(Accelerate)
import Foundation
import Accelerate

// MARK: - EchoelModalBank — Physics-Constrained Modal Resonator Bank
// Physically-inspired modal synthesis: models vibrating objects as a bank of
// exponentially decaying sinusoidal modes (bells, plates, bars, strings, etc).
//
// Architecture:
//   1. Mode Bank: N resonant modes, each with frequency, amplitude, decay, phase
//      - y(t) = A * exp(-d*t) * sin(2π*f*t + φ)
//      - Per-sample: amplitude *= exp(-decayRate / sampleRate), advance phase
//   2. Excitation: Impulse or continuous input drives the modes
//      - Strike position weighting: sin(n*π*pos) for mode n at position pos
//   3. Material Presets: Frequency ratios, amplitudes, decay profiles
//      - Bell, Plate, Bar, String, Glass, Drum, Gong, Custom
//   4. Physics Parameters:
//      - Stiffness (inharmonicity), Damping, Size, Brightness, Strike position
//   5. Bio-Reactive Integration:
//      - Coherence → Material morph (harmonic ↔ inharmonic)
//      - HRV → Damping (calm = long ring, stressed = short)
//      - Breathing → Continuous excitation amplitude
//
// References:
//   - Adrien (1991) "Representations of Musical Signals" — modal synthesis foundations
//   - Cook (2002) "Real Sound Synthesis for Interactive Applications"
//   - Bilbao (2009) "Numerical Sound Synthesis" — finite difference modal methods

/// EchoelModalBank — Physics-Constrained Modal Resonator Bank Synthesizer
/// Models vibrating objects as a bank of exponentially decaying sinusoidal modes
///
/// ⚠️ THE `@unchecked Sendable` CONTRACT — write it down or the next adopter inherits a
/// promise nobody made. This class has ~10 public mutable `var`s (`frequency`, `amplitude`,
/// `stiffness`, `damping`, `size`, `brightness`, `strikePosition`, `strikeVelocity`,
/// `material`, …) and NO lock. The opt-out was earned by its only owner,
/// `DrumRenderState` (itself `@unchecked Sendable`), which confined every instance to a
/// SINGLE render thread. #167 deleted that owner, so today `Sources/` instantiates this
/// class **nowhere** — it is test-only, and cannot race anything.
/// **The contract any future adopter must satisfy: confine one instance to one thread.**
/// Mutating it from two isolation domains is a data race the compiler has been told not to
/// check. If a future owner cannot promise that, narrow this to an actor or add a lock
/// rather than inheriting the opt-out silently.
public final class EchoelModalBank: @unchecked Sendable {

    // MARK: - Configuration

    /// Number of resonant modes
    public let modeCount: Int

    /// Sample rate (Hz)
    public let sampleRate: Float

    /// Frame size for parameter updates
    public let frameSize: Int

    // MARK: - Fundamental Frequency

    /// Fundamental frequency (Hz) — mode frequencies are derived from this
    public var frequency: Float = 220.0

    /// Global amplitude (0-1)
    public var amplitude: Float = 0.8

    // MARK: - Physics Parameters

    /// Material stiffness — affects inharmonicity (0 = harmonic, 1 = very inharmonic)
    public var stiffness: Float = 0.0 {
        didSet { recalculateModeFrequencies() }
    }

    /// Global damping multiplier (0 = no damping/infinite ring, 1 = heavily damped)
    public var damping: Float = 0.3

    /// Object size — scales frequencies inversely (0.1 = small/high, 2.0 = large/low)
    public var size: Float = 1.0 {
        didSet { recalculateModeFrequencies() }
    }

    /// Brightness — high-frequency mode amplitude boost/cut (0 = dark, 1 = bright)
    public var brightness: Float = 0.5 {
        didSet { recalculateBrightnessWeights() }
    }

    /// Strike position (0-1) — affects which modes are excited
    /// 0 = center, 0.5 = edge, maps to sin(n*π*pos) weighting
    public var strikePosition: Float = 0.15

    /// Strike velocity (0-1) — excitation strength
    public var strikeVelocity: Float = 0.8

    // MARK: - Material

    /// Active material preset.
    ///
    /// The equality guard is an AUDIO-THREAD requirement, not an optimisation.
    /// ⛔ Its ORIGINAL caller is gone: `DrumRenderState.applyPendingRequests`
    /// (`Sequencer/DrumSynthVoice.swift`) assigned this from the render block on every
    /// config-version bump, and `LaneDrumKitVoice.noteOn` bumped that version whenever a
    /// pitch mapped to different drum params — so a melodic tom/perc line reconfigured on
    /// nearly every note. Without the guard, each of those assignments ran the full
    /// `applyMaterial` (mode loop + normalisation) in the render block for a material that
    /// had not changed. Both files were DELETED with #167 (founder 2026-07-27, no drums).
    /// The guard STAYS, and be exact about why: `Sources/` instantiates this class NOWHERE
    /// today (it is test-only), so the guard is DORMANT, not load-bearing. It is kept because
    /// `material` is still a plain settable property and the next render-side assigner
    /// inherits the identical hazard — do not read the absence of today's caller as licence
    /// to drop it, and do not read its presence as proof something is calling it.
    ///
    /// Skipping the re-apply is inaudible under ONE PRECONDITION, which is not automatic:
    /// the mode arrays must still hold this preset's values. `configureModes` derives them
    /// purely from the preset and touches no per-note state (phases, amplitudes, envelope),
    /// so a re-apply would write bit-identical values — but anything that mutates the arrays
    /// BEHIND the marker breaks that. `morphMaterials` is exactly such a routine: it exits
    /// with `material == to` while the arrays hold interpolated values. It therefore calls
    /// `applyMaterial` directly instead of assigning `material`; see the note there. Any new
    /// code that writes the mode arrays must do the same, or restore the marker honestly.
    public var material: MaterialPreset = .bell {
        didSet { if material != oldValue { applyMaterial(material) } }
    }

    // MARK: - Types

    /// Material preset defining the modal character of a vibrating object
    public enum MaterialPreset: String, CaseIterable, Sendable {
        case bell = "Bell"               // Inharmonic, long decay
        case plate = "Plate"             // Dense modes, medium decay
        case bar = "Bar"                 // Quasi-harmonic, medium decay
        case string = "String"           // Harmonic, variable decay
        case glass = "Glass"             // Inharmonic, bright, medium decay
        case drum = "Drum"               // Membrane modes, short decay
        case gong = "Gong"              // Complex inharmonic, very long decay
        case custom = "Custom"           // User-defined
    }

    /// Excitation type for driving modes
    public enum ExcitationType: String, CaseIterable, Sendable {
        case impulse = "Impulse"         // Single strike
        case continuous = "Continuous"   // Sustained excitation (bowed, breath)
        case noise = "Noise"             // Noise burst excitation
    }

    // MARK: - Internal State — Per-Mode Arrays

    /// Current frequency of each mode (Hz)
    private var modeFrequencies: [Float]

    /// Base frequency ratios relative to fundamental (from material preset)
    private var modeRatios: [Float]

    /// Current amplitude of each mode (decaying after excitation)
    private var modeAmplitudes: [Float]

    /// Initial amplitude of each mode when excited (from material preset)
    private var modeInitialAmplitudes: [Float]

    /// Decay rate per mode (1/seconds — higher = faster decay)
    private var modeDecayRates: [Float]

    /// Phase accumulator per mode
    private var modePhases: [Float]

    /// Brightness weights per mode (updated when brightness changes)
    private var modeBrightnessWeights: [Float]

    /// Smoothed output amplitude (click avoidance)
    private var smoothedOutputLevel: Float = 0

    /// Target output level for smoothing
    private var targetOutputLevel: Float = 0

    /// Whether modes are currently ringing
    private var isRinging: Bool = false

    /// Continuous excitation amplitude (bio-reactive breathing drives this)
    private var continuousExcitationLevel: Float = 0

    /// Smoothed continuous excitation (to avoid clicks)
    private var smoothedContinuousExcitation: Float = 0

    /// Pre-allocated scratch buffer for vDSP operations
    private var scratchBuffer: [Float]

    /// Pre-allocated buffer for sine computation
    private var sineBuffer: [Float]

    // MARK: - Envelope

    /// Current envelope value
    private var envelopeValue: Float = 0

    /// Envelope stage
    private var envelopeStage: EnvelopeStage = .idle

    /// Samples elapsed in current envelope stage
    private var envelopeSamples: Int = 0

    /// Attack time (seconds)
    public var attack: Float = 0.001

    /// Release time (seconds) — for noteOff fade
    public var release: Float = 0.05

    private enum EnvelopeStage {
        case idle, attack, active, release
    }

    // MARK: - Init

    /// Initialize EchoelModalBank
    /// - Parameters:
    ///   - modeCount: Number of resonant modes (default 64)
    ///   - sampleRate: Audio sample rate (default 48000)
    ///   - frameSize: Parameter update frame size (default 192)
    public init(
        modeCount: Int = 64,
        sampleRate: Float = 48000.0,
        frameSize: Int = 192
    ) {
        self.modeCount = modeCount
        self.sampleRate = sampleRate
        self.frameSize = frameSize

        self.modeFrequencies = [Float](repeating: 0, count: modeCount)
        self.modeRatios = [Float](repeating: 0, count: modeCount)
        self.modeAmplitudes = [Float](repeating: 0, count: modeCount)
        self.modeInitialAmplitudes = [Float](repeating: 0, count: modeCount)
        self.modeDecayRates = [Float](repeating: 0, count: modeCount)
        self.modePhases = [Float](repeating: 0, count: modeCount)
        self.modeBrightnessWeights = [Float](repeating: 1, count: modeCount)
        self.scratchBuffer = [Float](repeating: 0, count: modeCount)
        self.sineBuffer = [Float](repeating: 0, count: modeCount)

        // Apply default material
        applyMaterial(.bell)
        recalculateBrightnessWeights()
    }

    // MARK: - Material Presets

    /// Membrane mode ratios for `.drum` (Bessel-function zeros): 1.00, 1.59, 2.14, 2.30,
    /// 2.65, 2.92, 3.16, 3.50, …
    ///
    /// Hoisted out of `applyMaterial`'s `.drum` branch because that branch COULD run on the
    /// AUDIO THREAD (`DrumRenderState.applyPendingRequests` → `material` didSet), where an
    /// array literal is a heap allocation. Same fix, same reason as `EchoelDDSP.formantBands`.
    /// ⛔ That caller was deleted with #167 (founder 2026-07-27) — the `static let` stays for
    /// the same reason the `material` equality guard does: it costs nothing and the hazard
    /// returns with the next render-side adopter. Present tense here would send a session
    /// looking for `Sequencer/DrumSynthVoice.swift`, which no longer exists.
    /// Read-only; indexing a stored array allocates nothing.
    private static let drumRatios: [Float] = [
        1.000, 1.593, 2.136, 2.296, 2.653, 2.917, 3.156, 3.500,
        3.600, 3.652, 4.060, 4.154, 4.480, 4.600, 4.903, 5.132
    ]

    /// Apply a material preset, setting mode ratios, amplitudes, and decay rates
    private func applyMaterial(_ preset: MaterialPreset) {
        guard preset != .custom else { return }

        switch preset {
        case .bell:
            // Bell — inharmonic ratios based on vibrating circular plate eigenvalues
            // Classic bronze bell mode structure
            configureModes(
                ratioGenerator: { n in
                    let nf = Float(n + 1)
                    return nf * (1.0 + 0.02 * nf * nf) // Quadratic inharmonicity
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 0.7)
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 0.3 + nf * 0.15 // Higher modes decay faster
                }
            )

        case .plate:
            // Plate — dense, slightly inharmonic modes
            configureModes(
                ratioGenerator: { n in
                    let nf = Float(n + 1)
                    return nf * sqrt(nf) * 0.7 // Plate eigenvalues scale as n*sqrt(n)
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 0.9)
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 0.8 + nf * 0.3
                }
            )

        case .bar:
            // Bar/Marimba — quasi-harmonic, modes at n^2 ratios
            configureModes(
                ratioGenerator: { n in
                    let nf = Float(n + 1)
                    // Bar modes: 1, 2.76, 5.40, 8.93, ... ≈ (2n+1)^2 / 9
                    let ratio = pow(2.0 * nf - 1.0, 2) / 9.0
                    return Swift.max(ratio, nf * 0.5) // Ensure monotonic
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 1.0)
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 0.5 + nf * 0.2
                }
            )

        case .string:
            // String — nearly harmonic, low inharmonicity
            configureModes(
                ratioGenerator: { n in
                    let nf = Float(n + 1)
                    // String inharmonicity: f_n = n * f0 * sqrt(1 + B * n^2)
                    let inharmonicity: Float = 0.0003
                    return nf * sqrt(1.0 + inharmonicity * nf * nf)
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 1.2)
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 0.2 + nf * 0.08 // Higher partials ring shorter
                }
            )

        case .glass:
            // Glass — inharmonic, bright, crystalline
            configureModes(
                ratioGenerator: { n in
                    let nf = Float(n + 1)
                    // Glass cylinder modes
                    return nf * (1.0 + 0.015 * nf * nf) + 0.5 * sin(nf * 0.7)
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 0.5) // Slow rolloff = bright
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 0.6 + nf * 0.2
                }
            )

        case .drum:
            // Read the static ONCE per call, not once per mode. `configureModes` invokes the
            // generator `modeCount` times (64 by default), and each `Self.drumRatios` touch is
            // a `swift_once` token check plus a retain/release on the array buffer. Matches how
            // `EchoelDDSP.formantBands` is read (once, in the `for` header).
            let drumRatios = Self.drumRatios
            configureModes(
                ratioGenerator: { n in
                    if n < drumRatios.count {
                        return drumRatios[n]
                    }
                    let nf = Float(n + 1)
                    return nf * 1.1 // Approximate higher modes
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 1.5)
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 2.0 + nf * 0.8 // Short decay
                }
            )

        case .gong:
            // Gong — complex inharmonic, very long decay, dense spectrum
            configureModes(
                ratioGenerator: { n in
                    let nf = Float(n + 1)
                    // Gong has very dense, inharmonic modes
                    return nf * (1.0 + 0.03 * nf * nf) + 0.3 * sin(nf * 1.5)
                },
                amplitudeGenerator: { n in
                    let nf = Float(n + 1)
                    return 1.0 / pow(nf, 0.6)
                },
                decayGenerator: { n in
                    let nf = Float(n + 1)
                    return 0.08 + nf * 0.03 // Very long decay
                }
            )

        case .custom:
            break
        }

        recalculateModeFrequencies()
    }

    /// Configure modes from generator closures
    private func configureModes(
        ratioGenerator: (Int) -> Float,
        amplitudeGenerator: (Int) -> Float,
        decayGenerator: (Int) -> Float
    ) {
        for i in 0..<modeCount {
            modeRatios[i] = ratioGenerator(i)
            modeInitialAmplitudes[i] = amplitudeGenerator(i)
            modeDecayRates[i] = decayGenerator(i)
        }

        // Normalize initial amplitudes
        var maxAmp: Float = 0
        for i in 0..<modeCount {
            maxAmp = Swift.max(maxAmp, modeInitialAmplitudes[i])
        }
        if maxAmp > 0 {
            let invMax = 1.0 / maxAmp
            for i in 0..<modeCount {
                modeInitialAmplitudes[i] *= invMax
            }
        }
    }

    /// Recalculate absolute mode frequencies from ratios, stiffness, and size
    private func recalculateModeFrequencies() {
        let baseFreq = frequency / max(size, 0.001)

        for i in 0..<modeCount {
            let ratio = modeRatios[i]
            // Stiffness adds additional inharmonicity on top of material preset
            let stiffnessShift = 1.0 + stiffness * 0.01 * ratio * ratio
            modeFrequencies[i] = baseFreq * ratio * stiffnessShift
        }
    }

    /// Recalculate brightness weights per mode
    private func recalculateBrightnessWeights() {
        for i in 0..<modeCount {
            let normalizedIndex = Float(i) / Float(modeCount)
            // Brightness tilts the spectral balance
            // 0 = strong rolloff of high modes, 1 = boost high modes
            let tilt = 2.0 * (brightness - 0.5) // -1 to +1
            modeBrightnessWeights[i] = pow(10.0, tilt * normalizedIndex * 0.5)
        }

        // Normalize
        var maxWeight: Float = 0
        for i in 0..<modeCount {
            maxWeight = Swift.max(maxWeight, modeBrightnessWeights[i])
        }
        if maxWeight > 0 {
            let invMax = 1.0 / maxWeight
            for i in 0..<modeCount {
                modeBrightnessWeights[i] *= invMax
            }
        }
    }

    // MARK: - Strike Position

    /// Compute excitation weight for mode n at given strike position
    /// Based on standing wave: sin(n * π * position)
    /// A strike at a node of mode n will not excite that mode
    private func strikeWeight(modeIndex: Int, position: Float) -> Float {
        let n = Float(modeIndex + 1)
        let weight = sin(n * .pi * position)
        return weight * weight // Squared for always-positive weighting
    }

    // MARK: - Excitation

    /// Excite the mode bank (strike/pluck) at the current strike position
    /// - Parameters:
    ///   - velocity: Strike velocity (0-1), nil uses strikeVelocity property
    ///   - position: Strike position (0-1), nil uses strikePosition property
    public func excite(velocity: Float? = nil, position: Float? = nil) {
        let vel = velocity ?? strikeVelocity
        let pos = position ?? strikePosition

        recalculateModeFrequencies()
        recalculateBrightnessWeights()

        let nyquist = sampleRate * 0.5

        for i in 0..<modeCount {
            // Skip modes above Nyquist
            guard modeFrequencies[i] < nyquist else {
                modeAmplitudes[i] = 0
                continue
            }

            let posWeight = strikeWeight(modeIndex: i, position: pos)
            let brightWeight = modeBrightnessWeights[i]
            let initialAmp = modeInitialAmplitudes[i] * posWeight * brightWeight * vel

            // Add to existing amplitude (modes can accumulate from multiple strikes)
            modeAmplitudes[i] += initialAmp

            // Clamp to prevent runaway
            modeAmplitudes[i] = Swift.min(modeAmplitudes[i], 2.0)
        }

        isRinging = true
    }

    /// Trigger note on — excites the modes like a strike
    /// - Parameters:
    ///   - frequency: Fundamental frequency (Hz), nil keeps current
    ///   - velocity: Strike velocity (0-1), nil uses strikeVelocity property
    public func noteOn(frequency: Float? = nil, velocity: Float? = nil) {
        if let f = frequency {
            self.frequency = f
        }
        envelopeStage = .attack
        envelopeSamples = 0
        excite(velocity: velocity)
    }

    /// Trigger note off — begins release fade
    public func noteOff() {
        envelopeStage = .release
        envelopeSamples = 0
    }

    /// Set continuous excitation level (for bowed/breath-driven modes)
    /// - Parameter level: Excitation amplitude (0-1)
    public func setContinuousExcitation(_ level: Float) {
        continuousExcitationLevel = level
    }

    // MARK: - Custom Mode Configuration

    /// Set mode ratios directly (for custom material)
    /// - Parameter ratios: Frequency ratios relative to fundamental
    public func setModeRatios(_ ratios: [Float]) {
        guard material == .custom else { return }
        let count = Swift.min(ratios.count, modeCount)
        for i in 0..<count {
            modeRatios[i] = ratios[i]
        }
        // Fill remaining with harmonic extension
        for i in count..<modeCount {
            modeRatios[i] = Float(i + 1)
        }
        recalculateModeFrequencies()
    }

    /// Set initial amplitudes directly (for custom material)
    /// - Parameter amplitudes: Per-mode initial amplitudes (0-1)
    public func setModeAmplitudesPreset(_ amplitudes: [Float]) {
        guard material == .custom else { return }
        let count = Swift.min(amplitudes.count, modeCount)
        for i in 0..<count {
            modeInitialAmplitudes[i] = amplitudes[i]
        }
        for i in count..<modeCount {
            modeInitialAmplitudes[i] = 0
        }
    }

    /// Set decay rates directly (for custom material)
    /// - Parameter rates: Per-mode decay rates (1/seconds)
    public func setModeDecayRates(_ rates: [Float]) {
        guard material == .custom else { return }
        let count = Swift.min(rates.count, modeCount)
        for i in 0..<count {
            modeDecayRates[i] = rates[i]
        }
        for i in count..<modeCount {
            modeDecayRates[i] = 1.0
        }
    }

    // MARK: - Audio Generation

    /// Generate audio samples into buffer
    /// - Parameters:
    ///   - buffer: Output buffer (pre-allocated, will be overwritten)
    ///   - frameCount: Number of audio frames to generate
    ///   - stereo: If true, interleaved stereo (buffer must be 2x frameCount)
    public func render(buffer: inout [Float], frameCount: Int, stereo: Bool = false) {
        let channelCount = stereo ? 2 : 1
        guard buffer.count >= frameCount * channelCount else { return }

        let nyquist = sampleRate * 0.5
        let twoPi: Float = 2.0 * .pi
        guard sampleRate > 0 else { return }
        let invSampleRate = 1.0 / sampleRate
        let smoothCoeff: Float = 0.999
        let oneMinusSmooth: Float = 1.0 - smoothCoeff

        // Precompute per-mode decay factors: exp(-decayRate * damping / sampleRate)
        // Using vDSP for batch exponential where beneficial
        // Compute decay factors in-place in scratchBuffer (avoids COW heap allocation)
        for i in 0..<modeCount {
            let effectiveDecay = modeDecayRates[i] * Swift.max(0.01, damping)
            scratchBuffer[i] = exp(-effectiveDecay * invSampleRate)
        }

        for frame in 0..<frameCount {
            // Update envelope
            updateEnvelope()

            // Apply continuous excitation (smoothed)
            smoothedContinuousExcitation = smoothedContinuousExcitation * smoothCoeff
                + continuousExcitationLevel * oneMinusSmooth
            if smoothedContinuousExcitation > 0.001 {
                // Continuous excitation re-energizes modes at low level
                for i in 0..<modeCount {
                    guard modeFrequencies[i] < nyquist else { continue }
                    let posWeight = strikeWeight(modeIndex: i, position: strikePosition)
                    let brightWeight = modeBrightnessWeights[i]
                    let target = modeInitialAmplitudes[i] * posWeight * brightWeight
                        * smoothedContinuousExcitation * 0.1
                    // Gently push amplitude toward target if below
                    if modeAmplitudes[i] < target {
                        modeAmplitudes[i] += (target - modeAmplitudes[i]) * 0.01
                    }
                }
                isRinging = true
            }

            // Smooth output level transition
            targetOutputLevel = amplitude * envelopeValue
            smoothedOutputLevel = smoothedOutputLevel * smoothCoeff
                + targetOutputLevel * oneMinusSmooth

            // Sum all modes
            var sample: Float = 0

            for i in 0..<modeCount {
                // Skip silent or super-Nyquist modes
                guard modeAmplitudes[i] > 1.0e-7 else { continue }
                guard modeFrequencies[i] < nyquist else { continue }

                // Advance phase
                let phaseInc = modeFrequencies[i] * invSampleRate * twoPi
                modePhases[i] += phaseInc
                if modePhases[i] > twoPi {
                    modePhases[i] -= twoPi
                }

                // Damped sinusoid: A * sin(phase)
                sample += modeAmplitudes[i] * sin(modePhases[i])

                // Exponential decay
                modeAmplitudes[i] *= scratchBuffer[i]
            }

            // Normalize by approximate active mode count to prevent clipping
            let normFactor: Float = 1.0 / sqrt(Float(modeCount))
            sample *= normFactor * smoothedOutputLevel

            // Soft clip
            sample = softClip(sample)

            if stereo {
                buffer[frame * 2] = sample
                buffer[frame * 2 + 1] = sample
            } else {
                buffer[frame] = sample
            }
        }

        // Check if all modes have decayed to silence
        checkRinging()
    }

    // MARK: - Envelope

    private func updateEnvelope() {
        envelopeSamples += 1

        switch envelopeStage {
        case .idle:
            envelopeValue = 0

        case .attack:
            let attackSamples = Swift.max(1, Int(attack * sampleRate))
            envelopeValue = Swift.min(1.0, Float(envelopeSamples) / Float(attackSamples))
            if envelopeSamples >= attackSamples {
                envelopeStage = .active
                envelopeSamples = 0
            }

        case .active:
            envelopeValue = 1.0

        case .release:
            let releaseSamples = Swift.max(1, Int(release * sampleRate))
            let progress = Float(envelopeSamples) / Float(releaseSamples)
            envelopeValue = Swift.max(0, 1.0 - progress)
            if envelopeSamples >= releaseSamples {
                envelopeStage = .idle
                envelopeSamples = 0
                envelopeValue = 0
                // Kill all modes on full release
                for i in 0..<modeCount {
                    modeAmplitudes[i] = 0
                }
                isRinging = false
            }
        }
    }

    // MARK: - Utility

    /// Soft clip to prevent harsh digital clipping
    private func softClip(_ x: Float) -> Float {
        if x > 1.0 {
            return 1.0 - exp(-(x - 1.0))
        } else if x < -1.0 {
            return -(1.0 - exp(-(-x - 1.0)))
        }
        return x
    }

    /// Check if any modes are still ringing above threshold
    private func checkRinging() {
        guard isRinging else { return }
        var maxAmp: Float = 0
        for i in 0..<modeCount {
            maxAmp = Swift.max(maxAmp, modeAmplitudes[i])
        }
        if maxAmp < 1.0e-7 {
            isRinging = false
        }
    }

    // MARK: - Bio-Reactive Integration

    /// Apply bio-reactive parameters from coherence, HRV, and breathing
    /// - Parameters:
    ///   - coherence: HRV coherence (0-1). High = harmonic/string-like, Low = inharmonic/bell-like
    ///   - hrvVariability: HRV variability normalized (0-1). Calm/low = long ring, stressed/high = short
    ///   - breathPhase: Breathing phase (0-1, 0 = exhale, 1 = inhale peak)
    public func applyBioReactive(coherence: Float, hrvVariability: Float = 0.5, breathPhase: Float = 0.5) {
        // Coherence → Material morph via stiffness (inharmonicity)
        // High coherence = low stiffness (harmonic, string-like)
        // Low coherence = high stiffness (inharmonic, bell-like)
        stiffness = (1.0 - coherence) * 0.8

        // Coherence also shifts brightness — coherent = warmer, incoherent = brighter/harsher
        brightness = 0.3 + coherence * 0.4

        // HRV → Damping (calm/low variability = long ring, high variability = short decay)
        damping = 0.1 + hrvVariability * 0.8

        // Breathing → Continuous excitation amplitude
        // Inhale drives excitation, exhale lets modes ring freely
        continuousExcitationLevel = breathPhase * 0.6

        // Breathing also modulates global amplitude gently
        amplitude = 0.6 + breathPhase * 0.25
    }

    /// Morph between two material presets based on a blend factor
    /// - Parameters:
    ///   - from: Source material
    ///   - to: Destination material
    ///   - blend: Blend factor (0 = source, 1 = destination)
    public func morphMaterials(from: MaterialPreset, to: MaterialPreset, blend: Float) {
        let clampedBlend = Swift.max(0, Swift.min(1, blend))

        // Store current material as custom to prevent didSet re-applying
        let savedMaterial = material

        // Temporarily configure "from" preset into scratch arrays
        var fromRatios = [Float](repeating: 0, count: modeCount)
        var fromAmps = [Float](repeating: 0, count: modeCount)
        var fromDecays = [Float](repeating: 0, count: modeCount)

        let prevRatios = modeRatios
        let prevAmps = modeInitialAmplitudes
        let prevDecays = modeDecayRates

        // Apply "from" material.
        //
        // Calls `applyMaterial` DIRECTLY rather than assigning `material`. This routine uses
        // the setter as a command ("fill the mode arrays with this preset, so I can read them
        // back"), which the setter's equality guard would silently swallow whenever
        // `material` already equalled `from` — the morph would then blend whatever the arrays
        // happened to hold. Worse, this routine deliberately EXITS with `material == to` while
        // the arrays hold interpolated values, so before the guard existed the next
        // `material = to` from any caller healed the state back to a pure preset; with the
        // guard, that heal is skipped and the blend would be permanent. Going straight at
        // `applyMaterial` keeps the morph independent of the marker's current value.
        applyMaterial(from)
        for i in 0..<modeCount {
            fromRatios[i] = modeRatios[i]
            fromAmps[i] = modeInitialAmplitudes[i]
            fromDecays[i] = modeDecayRates[i]
        }

        // Apply "to" material. The marker moves first (its didSet may or may not fire,
        // depending on the guard), then the explicit call guarantees the arrays hold the pure
        // `to` preset regardless — which the interpolation below reads as its second endpoint.
        // The marker CANNOT be moved after the interpolation: its didSet would overwrite the
        // blend it is meant to label.
        material = to
        applyMaterial(to)

        // Interpolate between from and to
        let oneMinusBlend = 1.0 - clampedBlend
        for i in 0..<modeCount {
            modeRatios[i] = fromRatios[i] * oneMinusBlend + modeRatios[i] * clampedBlend
            modeInitialAmplitudes[i] = fromAmps[i] * oneMinusBlend + modeInitialAmplitudes[i] * clampedBlend
            modeDecayRates[i] = fromDecays[i] * oneMinusBlend + modeDecayRates[i] * clampedBlend
        }

        // Restore custom marker if needed, suppress didSet
        if savedMaterial == .custom {
            // Restore previous state since we clobbered custom settings
            for i in 0..<modeCount {
                modeRatios[i] = prevRatios[i] * oneMinusBlend + modeRatios[i] * clampedBlend
                modeInitialAmplitudes[i] = prevAmps[i] * oneMinusBlend + modeInitialAmplitudes[i] * clampedBlend
                modeDecayRates[i] = prevDecays[i] * oneMinusBlend + modeDecayRates[i] * clampedBlend
            }
        }

        recalculateModeFrequencies()
    }

    // MARK: - State Access

    /// Get current spectral envelope for visualization
    /// Returns per-mode amplitude values (current ringing state)
    public func getSpectralEnvelope() -> [Float] {
        var envelope = [Float](repeating: 0, count: modeCount)
        for i in 0..<modeCount {
            envelope[i] = modeAmplitudes[i] * modeBrightnessWeights[i]
        }
        return envelope
    }

    /// Get current mode frequencies for visualization
    public func getModeFrequencies() -> [Float] {
        return Array(modeFrequencies.prefix(modeCount))
    }

    /// Whether the resonator is currently producing sound
    public func isActive() -> Bool {
        return isRinging || envelopeStage != .idle
    }

    /// Get the current damping-adjusted decay time for the fundamental mode
    public func getEffectiveDecayTime() -> Float {
        guard !modeDecayRates.isEmpty, modeDecayRates[0] > 0 else { return 0 }
        return 1.0 / (modeDecayRates[0] * Swift.max(0.01, damping))
    }

    // MARK: - Reset

    /// Reset all state — silences all modes and resets envelope
    public func reset() {
        for i in 0..<modeCount {
            modeAmplitudes[i] = 0
            modePhases[i] = 0
        }
        envelopeStage = .idle
        envelopeValue = 0
        envelopeSamples = 0
        smoothedOutputLevel = 0
        smoothedContinuousExcitation = 0
        continuousExcitationLevel = 0
        isRinging = false
    }
}
#endif
