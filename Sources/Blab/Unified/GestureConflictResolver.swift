import Foundation
import Combine

/// Resolves conflicts between gestures and other input sources
/// Prevents accidental triggers and ensures intentional control
@MainActor
class GestureConflictResolver: ObservableObject {

    // MARK: - Published Properties

    /// Whether gesture input is currently allowed
    @Published var gesturesEnabled: Bool = true

    /// Reason for gesture blocking (for debugging)
    @Published var blockingReason: String? = nil


    // MARK: - Configuration

    /// Minimum time gesture must be held to be considered intentional (seconds)
    var minimumGestureHoldTime: TimeInterval = 0.1 // 100ms

    /// Minimum confidence threshold for gesture recognition
    var minimumConfidenceThreshold: Float = 0.7

    /// Distance threshold for hand-near-face conflict (normalized)
    var handNearFaceDistanceThreshold: Float = 0.2


    // MARK: - Private Properties

    private var gestureStartTimes: [GestureRecognizer.Gesture: Date] = [:]
    private var lastGestureEndTime: Date?

    private weak var gestureRecognizer: GestureRecognizer?
    private weak var handTracker: HandTrackingManager?
    private weak var faceTracker: ARFaceTrackingManager?


    // MARK: - Initialization

    init(
        gestureRecognizer: GestureRecognizer,
        handTracker: HandTrackingManager,
        faceTracker: ARFaceTrackingManager? = nil
    ) {
        self.gestureRecognizer = gestureRecognizer
        self.handTracker = handTracker
        self.faceTracker = faceTracker

        print("🔀 GestureConflictResolver initialized")
    }


    // MARK: - Conflict Resolution

    /// Check if gesture is valid and should be processed
    func shouldProcessGesture(
        _ gesture: GestureRecognizer.Gesture,
        hand: HandTrackingManager.Hand,
        confidence: Float
    ) -> Bool {
        // Rule 1: Confidence threshold
        guard confidence >= minimumConfidenceThreshold else {
            blockingReason = "Low confidence (\(String(format: "%.2f", confidence)))"
            return false
        }

        // Rule 2: Minimum hold time
        guard isGestureHeldLongEnough(gesture) else {
            blockingReason = "Gesture not held long enough"
            return false
        }

        // Rule 3: Hand-near-face conflict
        if isHandNearFace(hand) {
            blockingReason = "Hand too close to face (likely touching face)"
            return false
        }

        // Rule 4: Rapid gesture switching prevention
        if isRapidGestureSwitching() {
            blockingReason = "Too rapid gesture switching"
            return false
        }

        // Rule 5: Check if gestures are globally disabled
        guard gesturesEnabled else {
            blockingReason = "Gestures disabled"
            return false
        }

        // All checks passed
        blockingReason = nil
        return true
    }


    // MARK: - Conflict Detection Rules

    /// Check if gesture has been held long enough to be intentional
    private func isGestureHeldLongEnough(_ gesture: GestureRecognizer.Gesture) -> Bool {
        // Record start time for new gestures
        if gestureStartTimes[gesture] == nil {
            gestureStartTimes[gesture] = Date()
            return false // First frame, not held yet
        }

        // Check hold duration
        guard let startTime = gestureStartTimes[gesture] else {
            return false
        }

        let holdDuration = Date().timeIntervalSince(startTime)
        return holdDuration >= minimumGestureHoldTime
    }

    /// Check if hand is near face (potential accidental touch)
    private func isHandNearFace(_ hand: HandTrackingManager.Hand) -> Bool {
        guard let handTracker = handTracker,
              let faceTracker = faceTracker,
              faceTracker.isFaceDetected else {
            return false // Can't detect conflict without face tracking
        }

        // Get hand position
        let handPosition = hand == .left ? handTracker.leftHandPosition : handTracker.rightHandPosition

        // Simple proximity check (face is approximately at center of frame)
        let faceCenter = SIMD3<Float>(0, 0, 0.5) // Normalized face position

        let distance = simd_distance(handPosition, faceCenter)

        return distance < handNearFaceDistanceThreshold
    }

    /// Check if user is rapidly switching between gestures (likely unintentional)
    private func isRapidGestureSwitching() -> Bool {
        guard let lastEndTime = lastGestureEndTime else {
            return false // No previous gesture
        }

        let timeSinceLastGesture = Date().timeIntervalSince(lastEndTime)
        return timeSinceLastGesture < 0.15 // 150ms cooldown
    }


    // MARK: - Gesture State Management

    /// Notify when gesture starts
    func gestureDidStart(_ gesture: GestureRecognizer.Gesture) {
        gestureStartTimes[gesture] = Date()
        print("✋ Gesture started: \(gesture.rawValue)")
    }

    /// Notify when gesture ends
    func gestureDidEnd(_ gesture: GestureRecognizer.Gesture) {
        gestureStartTimes[gesture] = nil
        lastGestureEndTime = Date()
        print("✋ Gesture ended: \(gesture.rawValue)")
    }

    /// Reset all gesture state
    func reset() {
        gestureStartTimes.removeAll()
        lastGestureEndTime = nil
        blockingReason = nil
    }


    // MARK: - Input Priority Management

    /// Determine which input source should have priority
    /// Returns: .gesture, .face, .bio, or .none
    func determineInputPriority() -> InputSource {
        // Priority order: Touch > Gesture > Face > Gaze > Bio
        // (Touch is handled separately in UnifiedControlHub)

        // Check if gestures are active and valid
        if let recognizer = gestureRecognizer,
           (recognizer.leftHandGesture != .none || recognizer.rightHandGesture != .none),
           recognizer.gestureConfidence > minimumConfidenceThreshold {
            return .gesture
        }

        // Check if face tracking is active
        if let face = faceTracker, face.isFaceDetected {
            return .face
        }

        // Default to bio signals
        return .bio
    }

    enum InputSource {
        case gesture
        case face
        case gaze
        case bio
        case none
    }


    // MARK: - Configuration

    /// Enable/disable gesture input
    func setGesturesEnabled(_ enabled: Bool) {
        gesturesEnabled = enabled
        if !enabled {
            reset()
        }
        print("✋ Gestures \(enabled ? "enabled" : "disabled")")
    }

    /// Update confidence threshold
    func setConfidenceThreshold(_ threshold: Float) {
        minimumConfidenceThreshold = max(0.1, min(1.0, threshold))
        print("✋ Confidence threshold: \(minimumConfidenceThreshold)")
    }

    /// Update minimum hold time
    func setMinimumHoldTime(_ time: TimeInterval) {
        minimumGestureHoldTime = max(0.05, min(1.0, time))
        print("✋ Minimum hold time: \(minimumGestureHoldTime)s")
    }


    // MARK: - Debugging

    /// Get current conflict state for debugging
    func getConflictState() -> ConflictState {
        return ConflictState(
            gesturesEnabled: gesturesEnabled,
            blockingReason: blockingReason,
            activeGestures: Array(gestureStartTimes.keys.map { $0.rawValue }),
            timeSinceLastGesture: lastGestureEndTime.map { Date().timeIntervalSince($0) }
        )
    }

    struct ConflictState {
        let gesturesEnabled: Bool
        let blockingReason: String?
        let activeGestures: [String]
        let timeSinceLastGesture: TimeInterval?
    }
}
