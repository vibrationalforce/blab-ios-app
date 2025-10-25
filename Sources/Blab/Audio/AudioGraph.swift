import Foundation
import AVFoundation

/// Modular audio graph builder that exposes the core routing primitives used
/// throughout the Blab engine. The graph owns an `AVAudioEngine` instance and
/// provides helpers for registering inputs, effect chains, and analysis taps
/// without leaking implementation details to higher layers.
struct AudioGraph {

    // MARK: - Public Types

    /// Configuration parameters for the audio graph.
    struct Configuration {
        /// Preferred processing sample rate. If `nil` the hardware sample rate
        /// of the input node is used.
        var preferredSampleRate: Double?

        /// Number of output channels. Defaults to stereo.
        var channelCount: AVAudioChannelCount

        /// Whether an analysis tap bus should be created. When enabled the
        /// master mixer will mirror audio into a dedicated mixer to simplify
        /// metering and FFT inspection.
        var enableAnalysisBus: Bool

        /// Initial output gain applied to the master mixer.
        var masterGain: Float

        /// Creates the default configuration used across the app.
        init(
            preferredSampleRate: Double? = nil,
            channelCount: AVAudioChannelCount = 2,
            enableAnalysisBus: Bool = true,
            masterGain: Float = 1.0
        ) {
            self.preferredSampleRate = preferredSampleRate
            self.channelCount = channelCount
            self.enableAnalysisBus = enableAnalysisBus
            self.masterGain = masterGain
        }

        /// Optional audio format to use for newly connected nodes.
        var processingFormat: AVAudioFormat? {
            guard let preferredSampleRate else { return nil }
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: preferredSampleRate,
                channels: channelCount,
                interleaved: false
            )
        }
    }

    /// Classification for the different input sources that can be registered
    /// with the graph.
    enum InputKind: Hashable {
        case microphone
        case external(name: String)
        case virtualInstrument(name: String)

        /// Human readable label.
        var displayName: String {
            switch self {
            case .microphone:
                return "Microphone"
            case .external(let name):
                return name
            case .virtualInstrument(let name):
                return name
            }
        }
    }

    /// Handle representing a registered input channel. The handle is returned
    /// to callers and can be used to adjust gain, install taps, or disconnect
    /// the channel later.
    struct InputChannel: Identifiable, Hashable {
        public let id: UUID
        public let kind: InputKind
        fileprivate let mixer: AVAudioMixerNode
        fileprivate let analysisMixer: AVAudioMixerNode?
        fileprivate let bus: AVAudioNodeBus

        init(id: UUID, kind: InputKind, mixer: AVAudioMixerNode, analysisMixer: AVAudioMixerNode?, bus: AVAudioNodeBus) {
            self.id = id
            self.kind = kind
            self.mixer = mixer
            self.analysisMixer = analysisMixer
            self.bus = bus
        }
    }

    /// Errors thrown by the audio graph when configuration is invalid.
    enum Error: Swift.Error {
        case invalidFormat
        case channelMissing
    }

    // MARK: - Internal State

    /// Internal reference type that owns the actual engine. The `AudioGraph`
    /// itself is a lightweight value wrapper so it can be passed around without
    /// copying heavy state.
    private final class State {
        let configuration: Configuration
        let engine: AVAudioEngine
        let input: AVAudioInputNode
        let output: AVAudioOutputNode
        let masterMixer: AVAudioMixerNode
        let analysisMixer: AVAudioMixerNode?
        let inputMixer: AVAudioMixerNode
        private var inputChannels: [UUID: InputChannel]
        private let syncQueue = DispatchQueue(label: "com.blab.audio.graph", qos: .userInteractive)

        init(configuration: Configuration) {
            self.configuration = configuration
            self.engine = AVAudioEngine()
            self.input = engine.inputNode
            self.output = engine.outputNode
            self.masterMixer = AVAudioMixerNode()
            self.inputMixer = AVAudioMixerNode()

            if configuration.enableAnalysisBus {
                self.analysisMixer = AVAudioMixerNode()
            } else {
                self.analysisMixer = nil
            }

            self.inputChannels = [:]

            // Attach nodes
            engine.attach(masterMixer)
            engine.attach(inputMixer)
            if let analysisMixer {
                engine.attach(analysisMixer)
            }

            // Determine processing format
            let format = configuration.processingFormat ?? input.outputFormat(forBus: 0)

            // Route: inputMixer → masterMixer → mainMixer → output
            engine.connect(inputMixer, to: masterMixer, format: format)
            engine.connect(masterMixer, to: engine.mainMixerNode, format: format)
            engine.connect(engine.mainMixerNode, to: output, format: format)

            if let analysisMixer {
                engine.connect(masterMixer, to: analysisMixer, format: format)
            }

            masterMixer.outputVolume = configuration.masterGain
        }

        func registerInput(node: AVAudioNode, kind: InputKind, format explicitFormat: AVAudioFormat?) throws -> InputChannel {
            try syncQueue.sync {
                let channelID = UUID()
                let mixer = AVAudioMixerNode()
                engine.attach(mixer)

                let format = explicitFormat
                    ?? configuration.processingFormat
                    ?? node.outputFormat(forBus: 0)

                guard let resolvedFormat = format else {
                    throw Error.invalidFormat
                }

                // Connect node → channel mixer → input mixer
                engine.connect(node, to: mixer, format: resolvedFormat)
                engine.connect(mixer, to: inputMixer, format: resolvedFormat)

                let analysisMixer = analysisMixer.map { mixerNode -> AVAudioMixerNode in
                    let branch = AVAudioMixerNode()
                    engine.attach(branch)
                    engine.connect(mixer, to: branch, format: resolvedFormat)
                    engine.connect(branch, to: mixerNode, format: resolvedFormat)
                    return branch
                }

                let channel = InputChannel(
                    id: channelID,
                    kind: kind,
                    mixer: mixer,
                    analysisMixer: analysisMixer,
                    bus: 0
                )

                inputChannels[channelID] = channel
                return channel
            }
        }

        func removeChannel(_ channel: InputChannel) {
            syncQueue.sync {
                inputChannels.removeValue(forKey: channel.id)
                engine.disconnectNodeOutput(channel.mixer)
                engine.detach(channel.mixer)

                if let analysisMixer = channel.analysisMixer {
                    engine.disconnectNodeOutput(analysisMixer)
                    engine.detach(analysisMixer)
                }
            }
        }

        func setGain(_ gain: Float, for channel: InputChannel) {
            syncQueue.async { channel.mixer.outputVolume = gain }
        }

        func installTap(on channel: InputChannel, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock) {
            syncQueue.sync {
                channel.mixer.installTap(
                    onBus: channel.bus,
                    bufferSize: bufferSize,
                    format: format ?? configuration.processingFormat,
                    block: block
                )
            }
        }

        func removeTap(from channel: InputChannel) {
            syncQueue.sync {
                channel.mixer.removeTap(onBus: channel.bus)
            }
        }

        func start() throws {
            try syncQueue.sync {
                if !engine.isRunning {
                    try engine.start()
                }
            }
        }

        func stop() {
            syncQueue.sync {
                if engine.isRunning {
                    engine.stop()
                }
            }
        }
    }

    // MARK: - Instance Storage

    private let state: State

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.state = State(configuration: configuration)
    }

    // MARK: - Public Accessors

    /// Underlying AVAudioEngine instance.
    var engine: AVAudioEngine { state.engine }

    /// Shared input node (microphone, audio interface, etc.).
    var input: AVAudioInputNode { state.input }

    /// Master mixer node that aggregates all registered inputs.
    var mixer: AVAudioMixerNode { state.masterMixer }

    /// Output node representing the final hardware destination.
    var output: AVAudioOutputNode { state.output }

    /// Optional analysis mixer. When available, taps should be installed here
    /// to avoid impacting the main mixer's performance.
    var analysisMixer: AVAudioMixerNode? { state.analysisMixer }

    // MARK: - Input Management

    /// Register a new input node with the graph.
    @discardableResult
    mutating func registerInput(
        node: AVAudioNode,
        kind: InputKind,
        format: AVAudioFormat? = nil
    ) throws -> InputChannel {
        try state.registerInput(node: node, kind: kind, format: format)
    }

    /// Remove a previously registered channel from the graph.
    mutating func removeInput(_ channel: InputChannel) {
        state.removeChannel(channel)
    }

    /// Adjust the gain applied to a specific channel.
    func setGain(_ gain: Float, for channel: InputChannel) {
        state.setGain(gain, for: channel)
    }

    /// Install an analysis tap on the provided channel.
    func installTap(
        on channel: InputChannel,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat? = nil,
        block: @escaping AVAudioNodeTapBlock
    ) {
        state.installTap(on: channel, bufferSize: bufferSize, format: format, block: block)
    }

    /// Remove an existing analysis tap from a channel.
    func removeTap(from channel: InputChannel) {
        state.removeTap(from: channel)
    }

    /// Start the underlying AVAudioEngine if it is not running.
    func start() throws {
        try state.start()
    }

    /// Stop the engine and release audio resources.
    func stop() {
        state.stop()
    }
}
