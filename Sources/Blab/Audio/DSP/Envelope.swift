import Foundation

/// Collection of envelope generators used by the Blab audio engine. Envelopes
/// are pure Swift implementations so they can be reused on the audio thread as
/// well as inside visualization and biofeedback subsystems.
public struct ADSREnvelope {
    public var attack: Double
    public var decay: Double
    public var sustain: Double
    public var release: Double
    private var sampleRate: Double
    private var state: State = .idle
    private var value: Float = 0

    private enum State {
        case idle
        case attack
        case decay
        case sustain
        case release
    }

    public init(
        attack: Double = 0.01,
        decay: Double = 0.1,
        sustain: Double = 0.8,
        release: Double = 0.2,
        sampleRate: Double = 48_000
    ) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.sampleRate = sampleRate
    }

    /// Reset the internal state without changing the configuration.
    public mutating func reset() {
        state = .idle
        value = 0
    }

    /// Trigger the start of the envelope (note on).
    public mutating func trigger() {
        state = .attack
    }

    /// Begin the release portion of the envelope (note off).
    public mutating func releaseGate() {
        state = .release
    }

    /// Render the next block of envelope values.
    public mutating func process(frames: Int) -> [Float] {
        guard frames > 0 else { return [] }
        var buffer = [Float](repeating: 0, count: frames)

        for index in 0..<frames {
            switch state {
            case .idle:
                value = max(0, value * 0.99)
            case .attack:
                let increment = attack <= 0 ? 1 : Float(1.0 / (attack * sampleRate))
                value += increment
                if value >= 1 {
                    value = 1
                    state = .decay
                }
            case .decay:
                let decrement = decay <= 0 ? 1 : Float((1 - sustain) / (decay * sampleRate))
                value -= decrement
                if value <= Float(sustain) {
                    value = Float(sustain)
                    state = .sustain
                }
            case .sustain:
                value = Float(sustain)
            case .release:
                let decrement = release <= 0 ? 1 : Float(sustain / (release * sampleRate))
                value -= decrement
                if value <= 0.0001 {
                    value = 0
                    state = .idle
                }
            }

            buffer[index] = max(0, min(value, 1))
        }

        return buffer
    }
}

/// Multi-stage envelope used for automation curves and gesture mapping. Each
/// stage is defined by a target value and a duration (seconds).
public struct MultiStageEnvelope {
    public struct Stage {
        public let target: Float
        public let duration: Double

        public init(target: Float, duration: Double) {
            self.target = target
            self.duration = duration
        }
    }

    public var stages: [Stage]
    private var currentStageIndex: Int = 0
    private var sampleRate: Double
    private var currentValue: Float = 0
    private var stageProgress: Double = 0

    public init(stages: [Stage], sampleRate: Double = 48_000) {
        self.stages = stages
        self.sampleRate = sampleRate
    }

    public mutating func reset(startValue: Float = 0) {
        currentStageIndex = 0
        currentValue = startValue
        stageProgress = 0
    }

    public mutating func process(frames: Int) -> [Float] {
        guard !stages.isEmpty else { return [Float](repeating: currentValue, count: frames) }
        var buffer = [Float](repeating: 0, count: frames)

        for index in 0..<frames {
            let stage = stages[min(currentStageIndex, stages.count - 1)]
            let framesPerStage = max(1, Int(stage.duration * sampleRate))
            let increment = (stage.target - currentValue) / Float(framesPerStage - Int(stageProgress))

            currentValue += increment
            stageProgress += 1

            if stageProgress >= Double(framesPerStage) {
                currentStageIndex = min(currentStageIndex + 1, stages.count - 1)
                stageProgress = 0
            }

            buffer[index] = currentValue
        }

        return buffer
    }
}

/// Envelope follower used for dynamic effects and biofeedback mapping.
public final class EnvelopeFollower {
    public var attack: Double
    public var release: Double
    public var lookahead: Int
    private var sampleRate: Double
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var detectorValue: Float = 0

    public init(attack: Double = 0.02, release: Double = 0.2, lookahead: Int = 0, sampleRate: Double = 48_000) {
        self.attack = attack
        self.release = release
        self.lookahead = lookahead
        self.sampleRate = sampleRate
        self.buffer = [Float](repeating: 0, count: max(1, lookahead))
    }

    public func reset() {
        buffer = [Float](repeating: 0, count: buffer.count)
        detectorValue = 0
        writeIndex = 0
    }

    public func process(sample: Float) -> Float {
        let absSample = fabsf(sample)
        buffer[writeIndex % buffer.count] = absSample
        writeIndex += 1

        let readIndex = (writeIndex + buffer.count - 1) % buffer.count
        let target = buffer[readIndex]

        let attackCoeff = exp(-1.0 / (attack * sampleRate))
        let releaseCoeff = exp(-1.0 / (release * sampleRate))
        let coefficient = target > detectorValue ? attackCoeff : releaseCoeff

        detectorValue = (coefficient * detectorValue) + (1 - coefficient) * target
        return detectorValue
    }
}
