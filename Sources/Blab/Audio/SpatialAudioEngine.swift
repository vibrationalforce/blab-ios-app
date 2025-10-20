import Foundation
import AVFoundation
import Combine

/// Spatial Audio Engine for BLAB
/// Manages 3D audio positioning using AVAudioEnvironmentNode
/// Integrates with head tracking for immersive spatial audio
/// Supports ASAF (Apple Spatial Audio Features) on iOS 19+
@MainActor
class SpatialAudioEngine: ObservableObject {

    // MARK: - Published Properties

    /// Whether spatial audio is currently active
    @Published var isActive: Bool = false

    /// Whether spatial audio is available (device + headphones)
    @Published var isAvailable: Bool = false

    /// Current spatial audio mode
    @Published var spatialMode: SpatialMode = .binaural


    // MARK: - Audio Components

    /// Main audio engine
    private var audioEngine: AVAudioEngine?

    /// Environment node for 3D audio positioning
    private var environmentNode: AVAudioEnvironmentNode?

    /// Audio player node for generated audio
    private var playerNode: AVAudioPlayerNode?

    /// Source node for voice input
    private var sourceNode: AVAudioSourceNode?

    /// Format for audio processing
    private var audioFormat: AVAudioFormat?


    // MARK: - Dependencies

    /// Head tracking manager
    private let headTrackingManager: HeadTrackingManager

    /// Device capabilities
    private let deviceCapabilities: DeviceCapabilities


    // MARK: - Configuration

    /// Sample rate (Hz)
    private let sampleRate: Double = 48000.0

    /// Buffer size
    private let bufferSize: AVAudioFrameCount = 1024

    /// Distance attenuation model
    private let distanceModel: AVAudioEnvironmentDistanceAttenuationModel = .inverse

    /// Reverb blend (0.0 - 1.0)
    private var reverbBlend: Float = 0.3


    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()


    // MARK: - Spatial Modes

    enum SpatialMode: String, CaseIterable {
        case binaural = "Binaural"              // Standard binaural (stereo headphones)
        case spatial3D = "Spatial 3D"           // 3D audio with head tracking
        case asaf = "ASAF"                      // Apple Spatial Audio Features (iOS 19+)

        var description: String {
            switch self {
            case .binaural:
                return "Standard binaural beats for headphones"
            case .spatial3D:
                return "3D spatial audio with head tracking"
            case .asaf:
                return "Apple Spatial Audio Features with APAC codec"
            }
        }
    }


    // MARK: - Initialization

    init(headTrackingManager: HeadTrackingManager, deviceCapabilities: DeviceCapabilities) {
        self.headTrackingManager = headTrackingManager
        self.deviceCapabilities = deviceCapabilities

        checkAvailability()
        setupAudioEngine()
    }


    // MARK: - Availability Check

    /// Check if spatial audio is available
    private func checkAvailability() {
        // Spatial audio requires:
        // 1. Head tracking support
        // 2. Headphones connected
        // 3. iOS 14+ for basic 3D audio
        // 4. iOS 19+ for ASAF

        let hasHeadTracking = headTrackingManager.isAvailable
        let hasHeadphones = deviceCapabilities.hasAirPodsConnected
        let canUseHeadTracking = deviceCapabilities.canUseHeadTracking

        isAvailable = hasHeadTracking && hasHeadphones && canUseHeadTracking

        if isAvailable {
            print("✅ Spatial audio available")

            // Set default mode based on capabilities
            if deviceCapabilities.supportsASAF {
                spatialMode = .asaf
                print("   Mode: ASAF (iOS 19+)")
            } else {
                spatialMode = .spatial3D
                print("   Mode: Spatial 3D")
            }
        } else {
            print("⚠️  Spatial audio not available")
            print("   Head tracking: \(hasHeadTracking ? "✅" : "❌")")
            print("   Headphones: \(hasHeadphones ? "✅" : "❌")")
            print("   iOS version: \(canUseHeadTracking ? "✅" : "❌")")

            // Fallback to binaural
            spatialMode = .binaural
        }
    }


    // MARK: - Audio Engine Setup

    /// Setup audio engine with environment node
    private func setupAudioEngine() {
        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        // Create environment node for 3D audio
        environmentNode = AVAudioEnvironmentNode()
        guard let envNode = environmentNode else { return }

        // Configure environment node
        envNode.distanceAttenuationParameters.distanceAttenuationModel = distanceModel
        envNode.distanceAttenuationParameters.maximumDistance = 10.0  // meters
        envNode.distanceAttenuationParameters.referenceDistance = 1.0  // meters

        // Set reverb blend
        envNode.reverbBlend = reverbBlend

        // Attach environment node to engine
        engine.attach(envNode)

        // Create player node
        playerNode = AVAudioPlayerNode()
        if let player = playerNode {
            engine.attach(player)
        }

        // Setup audio format
        audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2  // Stereo
        )

        print("🎵 Spatial audio engine configured")
    }


    // MARK: - Start/Stop

    /// Start spatial audio
    func start() throws {
        guard isAvailable else {
            throw SpatialAudioError.notAvailable
        }

        guard !isActive else {
            print("⚠️  Spatial audio already active")
            return
        }

        guard let engine = audioEngine,
              let envNode = environmentNode,
              let player = playerNode,
              let format = audioFormat else {
            throw SpatialAudioError.engineNotConfigured
        }

        // Connect audio nodes
        // Player → Environment → Main Mixer → Output
        engine.connect(player, to: envNode, format: format)
        engine.connect(envNode, to: engine.mainMixerNode, format: format)

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth])
        try audioSession.setActive(true)

        // Start audio engine
        engine.prepare()
        try engine.start()

        // Start player node
        player.play()

        // Start head tracking
        if spatialMode != .binaural {
            headTrackingManager.startTracking()

            // Subscribe to head tracking updates
            headTrackingManager.$headRotation
                .sink { [weak self] rotation in
                    self?.updateListenerOrientation(rotation: rotation)
                }
                .store(in: &cancellables)
        }

        isActive = true
        print("🎵 Spatial audio started (\(spatialMode.rawValue))")
    }

    /// Stop spatial audio
    func stop() {
        guard isActive else { return }

        // Stop player
        playerNode?.stop()

        // Stop audio engine
        audioEngine?.stop()

        // Stop head tracking
        headTrackingManager.stopTracking()

        // Clear subscriptions
        cancellables.removeAll()

        isActive = false
        print("🎵 Spatial audio stopped")
    }


    // MARK: - Listener Positioning

    /// Update listener orientation based on head tracking
    private func updateListenerOrientation(rotation: HeadTrackingManager.HeadRotation) {
        guard let envNode = environmentNode else { return }

        // Get listener orientation from head tracking
        let orientation = headTrackingManager.getListenerOrientation()

        // Update environment node listener orientation
        envNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: orientation.yaw,
            pitch: orientation.pitch,
            roll: orientation.roll
        )

        #if DEBUG
        // Log occasionally (avoid spam)
        if Int(Date().timeIntervalSince1970 * 2) % 10 == 0 {
            let degrees = rotation.degrees
            print("🎧 Listener: Y:\(Int(degrees.yaw))° P:\(Int(degrees.pitch))° R:\(Int(degrees.roll))°")
        }
        #endif
    }

    /// Position audio source in 3D space
    /// - Parameters:
    ///   - x: Left (-) to right (+)
    ///   - y: Down (-) to up (+)
    ///   - z: Front (+) to back (-)
    func positionSource(x: Float, y: Float, z: Float) {
        guard let player = playerNode else { return }

        // Set player position in 3D space
        player.position = AVAudio3DPoint(x: x, y: y, z: z)

        #if DEBUG
        print("🎵 Source positioned: X:\(x) Y:\(y) Z:\(z)")
        #endif
    }


    // MARK: - Audio Generation

    /// Play audio buffer with spatial positioning
    func playBuffer(_ buffer: AVAudioPCMBuffer, position: AVAudio3DPoint) {
        guard let player = playerNode, isActive else { return }

        // Set position
        player.position = position

        // Schedule buffer
        player.scheduleBuffer(buffer) {
            // Buffer finished playing
        }

        // Start if not playing
        if !player.isPlaying {
            player.play()
        }
    }

    /// Generate and position audio source
    /// - Parameters:
    ///   - frequency: Tone frequency (Hz)
    ///   - duration: Duration (seconds)
    ///   - position: 3D position
    func generateTone(frequency: Float, duration: Float, position: AVAudio3DPoint) throws {
        guard let format = audioFormat else {
            throw SpatialAudioError.engineNotConfigured
        }

        // Calculate frame count
        let frameCount = AVAudioFrameCount(duration * Float(sampleRate))

        // Create buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SpatialAudioError.bufferCreationFailed
        }

        buffer.frameLength = frameCount

        // Generate sine wave
        guard let channelData = buffer.floatChannelData else { return }

        for frame in 0..<Int(frameCount) {
            let time = Float(frame) / Float(sampleRate)
            let sample = sin(2.0 * .pi * frequency * time)

            // Write to both channels (stereo)
            channelData[0][frame] = sample * 0.5  // Left
            channelData[1][frame] = sample * 0.5  // Right
        }

        // Play buffer at position
        playBuffer(buffer, position: position)
    }


    // MARK: - Configuration

    /// Set reverb blend (0.0 - 1.0)
    func setReverbBlend(_ blend: Float) {
        reverbBlend = max(0.0, min(1.0, blend))
        environmentNode?.reverbBlend = reverbBlend

        print("🎵 Reverb blend: \(Int(reverbBlend * 100))%")
    }

    /// Set distance attenuation model
    func setDistanceModel(_ model: AVAudioEnvironmentDistanceAttenuationModel) {
        environmentNode?.distanceAttenuationParameters.distanceAttenuationModel = model

        print("🎵 Distance model: \(model.rawValue)")
    }

    /// Change spatial mode
    func setSpatialMode(_ mode: SpatialMode) {
        // Check if mode is supported
        if mode == .asaf && !deviceCapabilities.supportsASAF {
            print("⚠️  ASAF not supported on this device")
            return
        }

        let wasActive = isActive

        // Stop if active
        if isActive {
            stop()
        }

        // Change mode
        spatialMode = mode

        // Restart if was active
        if wasActive {
            try? start()
        }

        print("🎵 Spatial mode changed: \(mode.rawValue)")
    }


    // MARK: - Status

    /// Get human-readable status
    var statusDescription: String {
        if !isAvailable {
            return "Spatial audio not available"
        } else if isActive {
            return "Spatial audio active: \(spatialMode.rawValue)"
        } else {
            return "Spatial audio ready: \(spatialMode.rawValue)"
        }
    }


    // MARK: - Errors

    enum SpatialAudioError: Error, LocalizedError {
        case notAvailable
        case engineNotConfigured
        case bufferCreationFailed

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Spatial audio is not available on this device"
            case .engineNotConfigured:
                return "Audio engine is not properly configured"
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            }
        }
    }


    // MARK: - Cleanup

    deinit {
        stop()
    }
}


// MARK: - Presets

extension SpatialAudioEngine {

    /// Spatial audio presets for different use cases
    enum SpatialPreset {
        case meditation     // Close, intimate positioning
        case immersive      // Surround sound experience
        case focused        // Centered, forward positioning

        var configuration: (reverbBlend: Float, distanceModel: AVAudioEnvironmentDistanceAttenuationModel) {
            switch self {
            case .meditation:
                return (0.5, .inverse)  // More reverb, softer
            case .immersive:
                return (0.7, .exponential)  // Lots of reverb, dynamic
            case .focused:
                return (0.2, .linear)  // Less reverb, direct
            }
        }
    }

    /// Apply preset configuration
    func applyPreset(_ preset: SpatialPreset) {
        let config = preset.configuration
        setReverbBlend(config.reverbBlend)
        setDistanceModel(config.distanceModel)

        print("🎵 Applied preset: \(preset)")
    }
}
