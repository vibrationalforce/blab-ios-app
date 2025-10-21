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

    // TODO: Add when implementing
    // private let bioManager: HealthKitManager?
    // private let handTrackingManager: HandTrackingManager?

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

    // MARK: - Lifecycle

    /// Start the unified control system
    public func start() {
        print("[UnifiedControlHub] Starting control system...")

        // Start face tracking if enabled
        faceTrackingManager?.start()

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
        // TODO: Implement when HealthKitManager is integrated
        // Example:
        // guard let bioManager = bioManager else { return }
        // let hrv = bioManager.hrv
        // let heartRate = bioManager.heartRate
        // mapBioToAudio(hrv: hrv, heartRate: heartRate)
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

    /// Apply face-derived audio parameters to audio engine
    private func applyFaceAudioParameters(_ params: AudioParameters) {
        // TODO: Apply to actual AudioEngine once extended
        // For now, just log for debugging
        // print("[Face→Audio] Cutoff: \(Int(params.filterCutoff)) Hz, Q: \(String(format: "%.2f", params.filterResonance))")
    }

    private func updateFromHandGestures() {
        // TODO: Implement when HandTrackingManager is integrated
    }

    private func updateFromGazeTracking() {
        // TODO: Implement when GazeTracker is integrated
    }

    // MARK: - Conflict Resolution

    private func resolveConflicts() {
        // TODO: Implement conflict detection
        // For now, always mark as resolved
        conflictResolved = true
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
