import Foundation
import AVFoundation
import Combine
import CoreMotion

/// Spatial Audio Engine with 3D/4D positioning and head tracking
/// Supports iOS 15+ with runtime feature detection for iOS 19+ spatial audio
/// Integrates with MIDIToSpatialMapper for bio-reactive spatial fields
@MainActor
class SpatialAudioEngine: ObservableObject {

    // MARK: - Published State

    @Published var isActive: Bool = false
    @Published var currentMode: SpatialMode = .stereo
    @Published var headTrackingEnabled: Bool = false
    @Published var spatialSources: [SpatialSource] = []

    // MARK: - Audio Engine Components

    private let audioEngine = AVAudioEngine()
    private var environmentNode: AVAudioEnvironmentNode?
    private var sourceNodes: [UUID: AVAudioPlayerNode] = [:]
    private var mixerNode: AVAudioMixerNode?

    // MARK: - Head Tracking (iOS 19+)

    private var motionManager: CMMotionManager?
    private var headTrackingCancellable: AnyCancellable?

    // MARK: - Spatial Modes

    enum SpatialMode: String, CaseIterable {
        case stereo = "Stereo"
        case surround_3d = "3D Spatial"
        case surround_4d = "4D Orbital"
        case afa = "AFA Field"
        case binaural = "Binaural"
        case ambisonics = "Ambisonics"

        var description: String {
            switch self {
            case .stereo: return "L/R panning"
            case .surround_3d: return "3D positioning (X/Y/Z)"
            case .surround_4d: return "3D + temporal evolution"
            case .afa: return "Algorithmic Field Array"
            case .binaural: return "HRTF binaural rendering"
            case .ambisonics: return "Higher-order ambisonics"
            }
        }
    }

    // MARK: - Spatial Source

    struct SpatialSource: Identifiable {
        let id: UUID
        var position: SIMD3<Float>  // X, Y, Z
        var velocity: SIMD3<Float> = .zero
        var amplitude: Float = 1.0
        var frequency: Float = 440.0

        // 4D orbital parameters
        var orbitalRadius: Float = 0.0
        var orbitalSpeed: Float = 0.0
        var orbitalPhase: Float = 0.0

        // AFA field parameters
        var fieldIndex: Int = 0
        var fieldGeometry: FieldGeometry = .circle

        enum FieldGeometry {
            case circle
            case sphere
            case fibonacci
            case grid
        }
    }

    // MARK: - Initialization

    init() {
        setupAudioEngine()
    }

    deinit {
        stop()
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        // Create mixer node
        let mixer = AVAudioMixerNode()
        audioEngine.attach(mixer)
        self.mixerNode = mixer

        // Connect mixer to output
        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: nil)

        // Setup environment node if available (iOS 19+)
        if #available(iOS 19.0, *) {
            setupEnvironmentNode()
        } else {
            print("⚠️ iOS 19+ required for full spatial audio. Using stereo fallback.")
        }
    }

    @available(iOS 19.0, *)
    private func setupEnvironmentNode() {
        let environment = AVAudioEnvironmentNode()
        audioEngine.attach(environment)

        // Configure environment
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0, pitch: 0, roll: 0
        )

        // Set rendering algorithm
        environment.renderingAlgorithm = .HRTFHQ  // High-quality HRTF
        environment.distanceAttenuationParameters.maximumDistance = 100.0
        environment.distanceAttenuationParameters.referenceDistance = 1.0

        self.environmentNode = environment

        // Connect environment to mixer
        if let mixer = mixerNode {
            audioEngine.connect(environment, to: mixer, format: nil)
        }
    }

    // MARK: - Start/Stop

    func start() throws {
        guard !isActive else { return }

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true)

        // Start engine
        try audioEngine.start()
        isActive = true

        print("✅ SpatialAudioEngine started (mode: \(currentMode.rawValue))")

        // Enable head tracking if available
        if headTrackingEnabled {
            startHeadTracking()
        }
    }

    func stop() {
        guard isActive else { return }

        stopHeadTracking()
        audioEngine.stop()
        isActive = false

        print("🛑 SpatialAudioEngine stopped")
    }

    // MARK: - Source Management

    func addSource(position: SIMD3<Float>, amplitude: Float = 1.0, frequency: Float = 440.0) -> UUID {
        let source = SpatialSource(
            id: UUID(),
            position: position,
            amplitude: amplitude,
            frequency: frequency
        )

        spatialSources.append(source)
        createAudioSourceNode(for: source)

        return source.id
    }

    func removeSource(id: UUID) {
        spatialSources.removeAll { $0.id == id }

        if let node = sourceNodes[id] {
            node.stop()
            audioEngine.detach(node)
            sourceNodes.removeValue(forKey: id)
        }
    }

    func updateSourcePosition(id: UUID, position: SIMD3<Float>) {
        guard let index = spatialSources.firstIndex(where: { $0.id == id }) else { return }
        spatialSources[index].position = position
        applyPositionToNode(id: id, position: position)
    }

    func updateSourceOrbital(id: UUID, radius: Float, speed: Float, phase: Float) {
        guard let index = spatialSources.firstIndex(where: { $0.id == id }) else { return }
        spatialSources[index].orbitalRadius = radius
        spatialSources[index].orbitalSpeed = speed
        spatialSources[index].orbitalPhase = phase
    }

    // MARK: - Audio Node Creation

    private func createAudioSourceNode(for source: SpatialSource) {
        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)

        // Create format
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: 1  // Mono source for spatial positioning
        )

        // Connect based on mode
        if #available(iOS 19.0, *), let environment = environmentNode, currentMode != .stereo {
            audioEngine.connect(playerNode, to: environment, format: format)
        } else if let mixer = mixerNode {
            audioEngine.connect(playerNode, to: mixer, format: format)
        }

        sourceNodes[source.id] = playerNode

        // Apply initial position
        applyPositionToNode(id: source.id, position: source.position)

        // Start playback (with generated tone)
        playerNode.play()
        scheduleAudioBuffer(for: source.id, frequency: source.frequency, amplitude: source.amplitude)
    }

    private func scheduleAudioBuffer(for sourceID: UUID, frequency: Float, amplitude: Float) {
        guard let playerNode = sourceNodes[sourceID] else { return }

        // Generate 1-second sine wave buffer
        let sampleRate: Double = 48000
        let duration: Double = 1.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )!,
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return }
        let samples = channelData[0]

        // Generate sine wave
        let angularFrequency = 2.0 * Float.pi * frequency
        for frame in 0..<Int(frameCount) {
            let time = Float(frame) / Float(sampleRate)
            samples[frame] = amplitude * sin(angularFrequency * time)
        }

        // Schedule buffer with looping
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
    }

    // MARK: - Spatial Positioning

    private func applyPositionToNode(id: UUID, position: SIMD3<Float>) {
        guard let playerNode = sourceNodes[id] else { return }

        switch currentMode {
        case .stereo:
            applyStereoPosition(node: playerNode, position: position)

        case .surround_3d, .surround_4d, .afa:
            if #available(iOS 19.0, *), let environment = environmentNode {
                apply3DPosition(node: playerNode, environment: environment, position: position)
            } else {
                applyStereoPosition(node: playerNode, position: position)
            }

        case .binaural:
            if #available(iOS 19.0, *), let environment = environmentNode {
                apply3DPosition(node: playerNode, environment: environment, position: position)
                environment.renderingAlgorithm = .HRTFHQ
            }

        case .ambisonics:
            // Higher-order ambisonics (future implementation)
            if #available(iOS 19.0, *), let environment = environmentNode {
                apply3DPosition(node: playerNode, environment: environment, position: position)
            }
        }
    }

    private func applyStereoPosition(node: AVAudioPlayerNode, position: SIMD3<Float>) {
        // Simple L/R panning based on X coordinate
        let pan = max(-1.0, min(1.0, position.x))
        node.pan = pan
    }

    @available(iOS 19.0, *)
    private func apply3DPosition(node: AVAudioPlayerNode, environment: AVAudioEnvironmentNode, position: SIMD3<Float>) {
        // Set 3D position
        node.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)

        // Distance attenuation
        let distance = sqrt(position.x * position.x + position.y * position.y + position.z * position.z)
        environment.distanceAttenuationParameters.maximumDistance = max(10.0, distance * 2.0)
    }

    // MARK: - 4D Orbital Motion

    func update4DOrbitalMotion(deltaTime: Double) {
        guard currentMode == .surround_4d else { return }

        for i in 0..<spatialSources.count {
            let source = spatialSources[i]
            guard source.orbitalRadius > 0 else { continue }

            // Update orbital phase
            let newPhase = source.orbitalPhase + source.orbitalSpeed * Float(deltaTime)
            spatialSources[i].orbitalPhase = newPhase.truncatingRemainder(dividingBy: 2.0 * .pi)

            // Calculate orbital position
            let x = source.orbitalRadius * cos(newPhase)
            let y = source.orbitalRadius * sin(newPhase)
            let z = source.position.z  // Keep Z constant

            let newPosition = SIMD3<Float>(x, y, z)
            spatialSources[i].position = newPosition
            applyPositionToNode(id: source.id, position: newPosition)
        }
    }

    // MARK: - AFA Field Application

    func applyAFAField(geometry: AFAFieldGeometry, coherence: Double) {
        guard currentMode == .afa else { return }

        let positions = generateAFAPositions(geometry: geometry, count: spatialSources.count)

        for (index, source) in spatialSources.enumerated() {
            if index < positions.count {
                updateSourcePosition(id: source.id, position: positions[index])
            }
        }

        print("🌊 AFA field applied: \(geometry) (coherence: \(Int(coherence)))")
    }

    enum AFAFieldGeometry {
        case grid(rows: Int, cols: Int)
        case circle(radius: Float)
        case fibonacci(count: Int)
        case sphere(radius: Float)
    }

    private func generateAFAPositions(geometry: AFAFieldGeometry, count: Int) -> [SIMD3<Float>] {
        var positions: [SIMD3<Float>] = []

        switch geometry {
        case .grid(let rows, let cols):
            let spacing: Float = 0.5
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = (Float(col) - Float(cols) / 2.0) * spacing
                    let y = (Float(row) - Float(rows) / 2.0) * spacing
                    positions.append(SIMD3(x, y, 1.0))
                    if positions.count >= count { return positions }
                }
            }

        case .circle(let radius):
            for i in 0..<count {
                let angle = 2.0 * Float.pi * Float(i) / Float(count)
                let x = radius * cos(angle)
                let y = radius * sin(angle)
                positions.append(SIMD3(x, y, 1.0))
            }

        case .fibonacci(let targetCount):
            // Fibonacci sphere distribution
            let goldenRatio: Float = (1.0 + sqrt(5.0)) / 2.0
            for i in 0..<targetCount {
                let t = Float(i) / Float(targetCount)
                let theta = 2.0 * Float.pi * Float(i) / goldenRatio
                let phi = acos(1.0 - 2.0 * t)

                let x = sin(phi) * cos(theta)
                let y = sin(phi) * sin(theta)
                let z = cos(phi)

                positions.append(SIMD3(x, y, z))
            }

        case .sphere(let radius):
            // Evenly distributed sphere
            for i in 0..<count {
                let phi = Float.pi * (3.0 - sqrt(5.0))  // Golden angle
                let y = 1.0 - (Float(i) / Float(count - 1)) * 2.0
                let radiusAtY = sqrt(1.0 - y * y)
                let theta = phi * Float(i)

                let x = cos(theta) * radiusAtY * radius
                let z = sin(theta) * radiusAtY * radius

                positions.append(SIMD3(x, y * radius, z))
            }
        }

        return positions
    }

    // MARK: - Head Tracking

    private func startHeadTracking() {
        guard motionManager == nil else { return }

        let manager = CMMotionManager()
        manager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz

        guard manager.isDeviceMotionAvailable else {
            print("⚠️ Device motion not available")
            return
        }

        motionManager = manager

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.updateListenerOrientation(attitude: motion.attitude)
        }

        print("✅ Head tracking started")
    }

    private func stopHeadTracking() {
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
    }

    @available(iOS 19.0, *)
    private func updateListenerOrientation(attitude: CMAttitude) {
        guard let environment = environmentNode else { return }

        // Convert quaternion to Euler angles
        let yaw = Float(attitude.yaw)
        let pitch = Float(attitude.pitch)
        let roll = Float(attitude.roll)

        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: yaw,
            pitch: pitch,
            roll: roll
        )
    }

    // MARK: - Mode Switching

    func setMode(_ mode: SpatialMode) {
        currentMode = mode

        // Reconfigure audio graph for new mode
        for source in spatialSources {
            applyPositionToNode(id: source.id, position: source.position)
        }

        print("🎚️ Spatial mode: \(mode.rawValue)")
    }

    // MARK: - Debug Info

    var debugInfo: String {
        """
        SpatialAudioEngine:
        - Mode: \(currentMode.rawValue)
        - Active: \(isActive)
        - Sources: \(spatialSources.count)
        - Head Tracking: \(headTrackingEnabled ? "✅" : "❌")
        - iOS 19+ Features: \(environmentNode != nil ? "✅" : "❌")
        """
    }
}
