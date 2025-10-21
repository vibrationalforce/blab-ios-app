import Foundation
import Combine
import AVFoundation

/// Central orchestrator for all input modalities in BLAB
///
/// UnifiedControlHub manages the fusion of multiple input sources and routes
/// control signals to audio, visual, and light output systems.
///
/// **Input Priority:** Touch > Gesture > Face > Gaze > Position > Bio
///
/// **Control Loop:** 60 Hz (16.67ms update interval)
///
/// **Usage:**
/// ```swift
/// let hub = UnifiedControlHub(audioEngine: audioEngine)
/// hub.start()
/// ```
@MainActor
public class UnifiedControlHub: ObservableObject {

    // MARK: - Published State

    /// Current active input mode
    @Published public private(set) var activeInputMode: InputMode = .automatic

    /// Whether conflict resolution successfully resolved ambiguous inputs
    @Published public private(set) var conflictResolved: Bool = true

    /// Current control loop frequency (Hz)
    @Published public private(set) var controlLoopFrequency: Double = 0

    // MARK: - Dependencies (Injected)

    private let audioEngine: AudioEngine?
    private var faceTrackingManager: ARFaceTrackingManager?
    private var faceToAudioMapper: FaceToAudioMapper?
    private var handTrackingManager: HandTrackingManager?
    private var gestureRecognizer: GestureRecognizer?
    private var gestureConflictResolver: GestureConflictResolver?
    private var gestureToAudioMapper: GestureToAudioMapper?
    private var healthKitManager: HealthKitManager?
    private var bioParameterMapper: BioParameterMapper?
    private var midi2Manager: MIDI2Manager?
    private var mpeZoneManager: MPEZoneManager?
    private var midiToSpatialMapper: MIDIToSpatialMapper?

    // TODO: Add when implementing
    // private let gazeTracker: GazeTracker?

    // MARK: - Control Loop

    private var controlLoopTimer: AnyCancellable?
    private let controlQueue = DispatchQueue(
        label: "com.blab.control",
        qos: .userInteractive
    )

    private var lastUpdateTime: Date = Date()
    private let targetFrequency: Double = 60.0  // 60 Hz

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(audioEngine: AudioEngine? = nil) {
        self.audioEngine = audioEngine
        self.faceToAudioMapper = FaceToAudioMapper()
    }

    /// Enable face tracking integration
    public func enableFaceTracking() {
        let manager = ARFaceTrackingManager()
        self.faceTrackingManager = manager

        // Subscribe to face expression changes
        manager.$faceExpression
            .sink { [weak self] expression in
                self?.handleFaceExpressionUpdate(expression)
            }
            .store(in: &cancellables)

        print("[UnifiedControlHub] Face tracking enabled")
    }

    /// Disable face tracking
    public func disableFaceTracking() {
        faceTrackingManager?.stop()
        faceTrackingManager = nil
        print("[UnifiedControlHub] Face tracking disabled")
    }

    /// Enable hand tracking and gesture recognition
    public func enableHandTracking() {
        let handManager = HandTrackingManager()
        let gestureRec = GestureRecognizer(handTracker: handManager)
        let conflictRes = GestureConflictResolver(
            handTracker: handManager,
            faceTracker: faceTrackingManager
        )
        let gestureMapper = GestureToAudioMapper()

        self.handTrackingManager = handManager
        self.gestureRecognizer = gestureRec
        self.gestureConflictResolver = conflictRes
        self.gestureToAudioMapper = gestureMapper

        // Subscribe to gesture changes
        gestureRec.$leftHandGesture
            .sink { [weak self] gesture in
                self?.handleGestureUpdate(hand: .left, gesture: gesture)
            }
            .store(in: &cancellables)

        gestureRec.$rightHandGesture
            .sink { [weak self] gesture in
                self?.handleGestureUpdate(hand: .right, gesture: gesture)
            }
            .store(in: &cancellables)

        print("[UnifiedControlHub] Hand tracking enabled")
    }

    /// Disable hand tracking
    public func disableHandTracking() {
        handTrackingManager?.stopTracking()
        handTrackingManager = nil
        gestureRecognizer = nil
        gestureConflictResolver = nil
        gestureToAudioMapper = nil
        print("[UnifiedControlHub] Hand tracking disabled")
    }

    /// Enable biometric monitoring (HealthKit)
    public func enableBiometricMonitoring() async throws {
        let healthKit = HealthKitManager()
        let bioMapper = BioParameterMapper()

        // Request HealthKit authorization
        try await healthKit.requestAuthorization()

        guard healthKit.isAuthorized else {
            throw NSError(
                domain: "com.blab.healthkit",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit authorization denied"]
            )
        }

        self.healthKitManager = healthKit
        self.bioParameterMapper = bioMapper

        // Subscribe to HRV changes
        healthKit.$hrvCoherence
            .sink { [weak self] coherence in
                self?.handleBioSignalUpdate()
            }
            .store(in: &cancellables)

        healthKit.$heartRate
            .sink { [weak self] _ in
                self?.handleBioSignalUpdate()
            }
            .store(in: &cancellables)

        // Start monitoring
        healthKit.startMonitoring()

        print("[UnifiedControlHub] Biometric monitoring enabled")
    }

    /// Disable biometric monitoring
    public func disableBiometricMonitoring() {
        healthKitManager?.stopMonitoring()
        healthKitManager = nil
        bioParameterMapper = nil
        print("[UnifiedControlHub] Biometric monitoring disabled")
    }

    /// Handle bio signal updates from HealthKit
    private func handleBioSignalUpdate() {
        // Bio signal updates happen via Combine subscriptions
        // Actual mapping happens in updateFromBioSignals()
    }

    /// Enable MIDI 2.0 + MPE output
    public func enableMIDI2() async throws {
        let midi2 = MIDI2Manager()
        try await midi2.initialize()

        let mpe = MPEZoneManager(midi2Manager: midi2)
        let spatialMapper = MIDIToSpatialMapper()

        self.midi2Manager = midi2
        self.mpeZoneManager = mpe
        self.midiToSpatialMapper = spatialMapper

        // Configure MPE zone (15 member channels)
        mpe.sendMPEConfiguration(memberChannels: 15)
        mpe.setPitchBendRange(semitones: 48)  // ±4 octaves

        print("[UnifiedControlHub] MIDI 2.0 + MPE enabled")
    }

    /// Disable MIDI 2.0
    public func disableMIDI2() {
        // Release all active voices
        mpeZoneManager?.releaseAllVoices()

        // Cleanup MIDI
        midi2Manager?.cleanup()

        midi2Manager = nil
        mpeZoneManager = nil
        midiToSpatialMapper = nil

        print("[UnifiedControlHub] MIDI 2.0 disabled")
    }

    // MARK: - Lifecycle

    /// Start the unified control system
    public func start() {
        print("[UnifiedControlHub] Starting control system...")

        // Start face tracking if enabled
        faceTrackingManager?.start()

        // Start hand tracking if enabled
        handTrackingManager?.startTracking()

        // HealthKit monitoring already started in enableBiometricMonitoring()

        // Start control loop
        startControlLoop()
    }

    /// Stop the unified control system
    public func stop() {
        print("[UnifiedControlHub] Stopping control system...")
        controlLoopTimer?.cancel()
        controlLoopTimer = nil
    }

    // MARK: - Control Loop (60 Hz)

    private func startControlLoop() {
        let interval = 1.0 / targetFrequency  // ~16.67ms for 60 Hz

        controlLoopTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.controlLoopTick()
            }
    }

    private func controlLoopTick() {
        // Measure actual frequency
        let now = Date()
        let deltaTime = now.timeIntervalSince(lastUpdateTime)
        controlLoopFrequency = 1.0 / deltaTime
        lastUpdateTime = now

        // Priority-based parameter updates
        updateFromBioSignals()
        updateFromFaceTracking()
        updateFromHandGestures()
        updateFromGazeTracking()

        // Check for gesture conflicts
        resolveConflicts()

        // Update all output systems
        updateAudioEngine()
        updateVisualEngine()
        updateLightSystems()
    }

    // MARK: - Input Updates (Placeholder implementations)

    private func updateFromBioSignals() {
        guard let healthKit = healthKitManager,
              let mapper = bioParameterMapper else {
            return
        }

        // Get current biometric data
        let hrvCoherence = healthKit.hrvCoherence
        let heartRate = healthKit.heartRate
        let voicePitch: Float = 0.0  // TODO: Get from audio analysis
        let audioLevel: Float = 0.5  // TODO: Get from audio engine

        // Update bio parameter mapping
        mapper.updateParameters(
            hrvCoherence: hrvCoherence,
            heartRate: heartRate,
            voicePitch: voicePitch,
            audioLevel: audioLevel
        )

        // Apply bio-derived audio parameters
        applyBioAudioParameters(mapper)
    }

    /// Apply bio-derived audio parameters to audio engine and spatial mapping
    private func applyBioAudioParameters(_ mapper: BioParameterMapper) {
        // Apply filter cutoff
        // TODO: Apply to actual AudioEngine filter node
        // print("[Bio→Audio] Filter Cutoff: \(Int(mapper.filterCutoff)) Hz")

        // Apply reverb wetness
        // TODO: Apply to actual AudioEngine reverb node
        // print("[Bio→Audio] Reverb Wet: \(Int(mapper.reverbWet * 100))%")

        // Apply amplitude
        // TODO: Apply to actual AudioEngine master volume
        // print("[Bio→Audio] Amplitude: \(Int(mapper.amplitude * 100))%")

        // Apply tempo
        // TODO: Apply to tempo-synced effects (delay, arpeggiator)
        // print("[Bio→Audio] Tempo: \(String(format: "%.1f", mapper.tempo)) BPM")

        // Apply bio-reactive spatial field (AFA)
        if let mpe = mpeZoneManager, let spatialMapper = midiToSpatialMapper {
            // Convert active MPE voices to spatial field
            let voiceData = mpe.activeVoices.map { voice in
                MPEVoiceData(
                    id: voice.id,
                    note: voice.note,
                    velocity: voice.velocity,
                    pitchBend: voice.pitchBend,
                    brightness: voice.brightness
                )
            }

            // Morph AFA field geometry based on HRV coherence
            let fieldGeometry: MIDIToSpatialMapper.AFAField.FieldGeometry
            let coherence = healthKitManager?.hrvCoherence ?? 50.0

            if coherence < 40 {
                // Low coherence (stress) = Grid (structured, grounding)
                fieldGeometry = .grid(rows: 3, cols: 3, spacing: 0.5)
            } else if coherence < 60 {
                // Medium coherence = Circle (transitional)
                fieldGeometry = .circle(radius: 1.5, sourceCount: voiceData.count)
            } else {
                // High coherence (flow) = Fibonacci Sphere (natural, harmonious)
                fieldGeometry = .fibonacci(sourceCount: voiceData.count)
            }

            // Generate AFA field
            if !voiceData.isEmpty {
                let afaField = spatialMapper.mapToAFA(voices: voiceData, geometry: fieldGeometry)
                spatialMapper.afaField = afaField

                // TODO: Apply AFA field to SpatialAudioEngine
                // print("[Bio→AFA] Field geometry: \(fieldGeometry), Sources: \(afaField.sources.count)")
            }
        }
    }

    private func updateFromFaceTracking() {
        // Face tracking updates happen via Combine subscription
        // See handleFaceExpressionUpdate()
    }

    /// Handle face expression updates from ARKit
    private func handleFaceExpressionUpdate(_ expression: FaceExpression) {
        guard let mapper = faceToAudioMapper else { return }

        // Map face expression to audio parameters
        let audioParams = mapper.mapToAudio(faceExpression: expression)

        // Apply to audio engine (if available)
        applyFaceAudioParameters(audioParams)
    }

    /// Apply face-derived audio parameters to audio engine and MPE
    private func applyFaceAudioParameters(_ params: AudioParameters) {
        // Apply to audio engine
        // TODO: Apply to actual AudioEngine once extended
        // print("[Face→Audio] Cutoff: \(Int(params.filterCutoff)) Hz, Q: \(String(format: "%.2f", params.filterResonance))")

        // Apply to all active MPE voices
        if let mpe = mpeZoneManager {
            for voice in mpe.activeVoices {
                // Jaw open → Per-note brightness (CC 74)
                let jawOpen = params.filterCutoff / 8000.0  // Normalize cutoff to 0-1
                mpe.setVoiceBrightness(voice: voice, brightness: jawOpen)

                // Smile → Per-note timbre (CC 71)
                let smile = params.filterResonance / 5.0  // Normalize resonance to 0-1
                mpe.setVoiceTimbre(voice: voice, timbre: smile)
            }
        }
    }

    private func updateFromHandGestures() {
        guard let gestureRecognizer = gestureRecognizer,
              let handTrackingManager = handTrackingManager,
              let conflictResolver = gestureConflictResolver else {
            return
        }

        // Update gesture recognition
        gestureRecognizer.updateGestures()

        // Apply gestures to audio parameters (if validated)
        applyGestureParameters()
    }

    /// Handle gesture updates from GestureRecognizer
    private func handleGestureUpdate(hand: HandTrackingManager.Hand, gesture: GestureRecognizer.Gesture) {
        guard let gestureRecognizer = gestureRecognizer,
              let conflictResolver = gestureConflictResolver else {
            return
        }

        // Validate gesture with conflict resolver
        let confidence = gestureRecognizer.leftGestureConfidence // Use appropriate confidence
        guard conflictResolver.shouldProcessGesture(gesture, hand: hand, confidence: confidence) else {
            return
        }

        // Gesture is valid - mapping happens in applyGestureParameters()
    }

    /// Apply gesture-derived audio parameters to audio engine
    private func applyGestureParameters() {
        guard let gestureRecognizer = gestureRecognizer,
              let mapper = gestureToAudioMapper else {
            return
        }

        // Map gestures to audio parameters
        let audioParams = mapper.mapToAudio(gestureRecognizer: gestureRecognizer)

        // Apply parameters to audio engine
        applyGestureAudioParameters(audioParams)
    }

    /// Apply gesture-derived audio parameters to audio engine
    private func applyGestureAudioParameters(_ params: GestureToAudioMapper.AudioParameters) {
        // Apply filter parameters
        if let cutoff = params.filterCutoff {
            // TODO: Apply to actual AudioEngine filter node
            // print("[Gesture→Audio] Filter Cutoff: \(Int(cutoff)) Hz")
        }

        if let resonance = params.filterResonance {
            // TODO: Apply to actual AudioEngine filter node
            // print("[Gesture→Audio] Filter Resonance: \(String(format: "%.2f", resonance))")
        }

        // Apply reverb parameters
        if let size = params.reverbSize {
            // TODO: Apply to actual AudioEngine reverb node
            // print("[Gesture→Audio] Reverb Size: \(String(format: "%.2f", size))")
        }

        if let wetness = params.reverbWetness {
            // TODO: Apply to actual AudioEngine reverb node
            // print("[Gesture→Audio] Reverb Wetness: \(String(format: "%.2f", wetness))")
        }

        // Apply delay parameters
        if let delayTime = params.delayTime {
            // TODO: Apply to actual AudioEngine delay node
            // print("[Gesture→Audio] Delay Time: \(String(format: "%.3f", delayTime)) s")
        }

        // Trigger MIDI notes via MPE
        if let midiNote = params.midiNoteOn {
            if let mpe = mpeZoneManager {
                // Allocate MPE voice for polyphonic expression
                if let voice = mpe.allocateVoice(
                    note: midiNote.note,
                    velocity: Float(midiNote.velocity) / 127.0
                ) {
                    print("[Gesture→MPE] Voice allocated: Note \(midiNote.note), Channel \(voice.channel + 1)")

                    // Apply initial per-note expression from gestures
                    if let gestureRec = gestureRecognizer {
                        // Pinch amount → Pitch bend
                        let pinchBend = (gestureRec.leftPinchAmount * 2.0) - 1.0  // Map 0-1 to -1 to +1
                        mpe.setVoicePitchBend(voice: voice, bend: pinchBend)

                        // Spread amount → Brightness
                        mpe.setVoiceBrightness(voice: voice, brightness: gestureRec.leftSpreadAmount)
                    }
                }
            } else {
                // Fallback to MIDI 1.0 if MPE not enabled
                print("[Gesture→MIDI] Note On: \(midiNote.note), Velocity: \(midiNote.velocity)")
            }
        }

        // Handle preset changes
        if let presetChange = params.presetChange {
            // TODO: Change to preset
            print("[Gesture→Audio] Switch to preset: \(presetChange)")
        }
    }

    private func updateFromGazeTracking() {
        // TODO: Implement when GazeTracker is integrated
    }

    // MARK: - Conflict Resolution

    private func resolveConflicts() {
        guard let conflictResolver = gestureConflictResolver else {
            conflictResolved = true
            return
        }

        // Check for input conflicts
        // Priority: Touch > Gesture > Face > Gaze > Position > Bio

        // For now, check if gestures conflict with face tracking
        let hasActiveGesture = gestureRecognizer?.leftHandGesture != .none ||
                               gestureRecognizer?.rightHandGesture != .none
        let hasActiveFace = faceTrackingManager?.isTracking ?? false

        if hasActiveGesture && hasActiveFace {
            // Gesture takes priority over face (per priority rules)
            // Mark as resolved since we have a clear priority
            conflictResolved = true
        } else {
            // No conflict
            conflictResolved = true
        }
    }

    // MARK: - Output Updates

    private func updateAudioEngine() {
        // Audio engine updates happen in specific input handlers
        // This is called after all inputs have been processed
    }

    private func updateVisualEngine() {
        // TODO: Update visual engine with current state
    }

    private func updateLightSystems() {
        // TODO: Update LED/DMX lights with current state
    }

    // MARK: - Utilities

    /// Map a value from one range to another
    public func mapRange(
        _ value: Double,
        from: ClosedRange<Double>,
        to: ClosedRange<Double>
    ) -> Double {
        let normalized = (value - from.lowerBound) / (from.upperBound - from.lowerBound)
        let clamped = max(0, min(1, normalized))
        return to.lowerBound + clamped * (to.upperBound - to.lowerBound)
    }
}

// MARK: - Input Mode

extension UnifiedControlHub {

    public enum InputMode: Equatable {
        /// System automatically prioritizes inputs
        case automatic

        /// Only accept touch input
        case touchOnly

        /// Only accept gesture input
        case gestureOnly

        /// Only accept face tracking input
        case faceOnly

        /// Only accept biofeedback input
        case bioOnly

        /// Custom combination of input sources
        case hybrid(Set<InputSource>)
    }

    public enum InputSource: Hashable {
        case touch
        case gesture
        case face
        case gaze
        case position
        case bio
    }
}

// MARK: - Statistics

extension UnifiedControlHub {

    /// Get current control loop statistics
    public var statistics: ControlStatistics {
        ControlStatistics(
            frequency: controlLoopFrequency,
            targetFrequency: targetFrequency,
            activeInputMode: activeInputMode,
            conflictResolved: conflictResolved
        )
    }

    public struct ControlStatistics {
        public let frequency: Double
        public let targetFrequency: Double
        public let activeInputMode: InputMode
        public let conflictResolved: Bool

        public var isRunningAtTarget: Bool {
            abs(frequency - targetFrequency) < 5.0  // Within 5 Hz tolerance
        }
    }
}
