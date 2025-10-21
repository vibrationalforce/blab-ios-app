import Foundation
import Vision
import Combine

/// Recognizes hand gestures from HandTrackingManager data
/// Supports: Pinch, Spread, Fist, Point, Swipe
@MainActor
class GestureRecognizer: ObservableObject {

    // MARK: - Published Properties

    /// Currently detected gesture for left hand
    @Published var leftHandGesture: Gesture = .none

    /// Currently detected gesture for right hand
    @Published var rightHandGesture: Gesture = .none

    /// Gesture confidence (0.0 - 1.0)
    @Published var gestureConfidence: Float = 0.0

    /// Pinch amount (0 = released, 1 = fully pinched)
    @Published var leftPinchAmount: Float = 0.0
    @Published var rightPinchAmount: Float = 0.0


    // MARK: - Gesture Types

    enum Gesture: String {
        case none = "None"
        case pinch = "Pinch"
        case spread = "Spread"
        case fist = "Fist"
        case point = "Point"
        case swipe = "Swipe"
    }


    // MARK: - Private Properties

    private weak var handTracker: HandTrackingManager?
    private var gestureHistory: [GestureHistoryEntry] = []
    private let historySize = 5 // Smooth over 5 frames

    private struct GestureHistoryEntry {
        let gesture: Gesture
        let confidence: Float
        let timestamp: Date
    }

    // Gesture thresholds
    private let pinchThreshold: Float = 0.05 // Distance between thumb and index
    private let spreadThreshold: Float = 0.25 // Min distance for spread
    private let fistThreshold: Float = 0.3 // Max extension for closed fist
    private let pointThreshold: Float = 0.6 // Min extension for pointing
    private let swipeVelocityThreshold: Float = 0.5 // Min velocity for swipe

    // Gesture state tracking
    private var lastHandPosition: SIMD3<Float> = .zero
    private var handVelocity: SIMD3<Float> = .zero


    // MARK: - Initialization

    init(handTracker: HandTrackingManager) {
        self.handTracker = handTracker
        print("✋ GestureRecognizer initialized")
    }


    // MARK: - Gesture Recognition

    /// Update gesture recognition from current hand state
    func updateGestures() {
        guard let tracker = handTracker else { return }

        // Recognize gestures for each hand
        if tracker.leftHandDetected {
            let gesture = recognizeGesture(for: .left)
            leftHandGesture = gesture.type
            leftPinchAmount = gesture.pinchAmount

            // Update history
            addToHistory(gesture: gesture.type, confidence: gesture.confidence)
        } else {
            leftHandGesture = .none
            leftPinchAmount = 0.0
        }

        if tracker.rightHandDetected {
            let gesture = recognizeGesture(for: .right)
            rightHandGesture = gesture.type
            rightPinchAmount = gesture.pinchAmount
        } else {
            rightHandGesture = .none
            rightPinchAmount = 0.0
        }

        // Calculate overall confidence from history
        gestureConfidence = calculateAverageConfidence()

        // Update hand velocity (for swipe detection)
        updateHandVelocity()
    }

    private func recognizeGesture(for hand: HandTrackingManager.Hand) -> (type: Gesture, confidence: Float, pinchAmount: Float) {
        guard let tracker = handTracker else {
            return (.none, 0.0, 0.0)
        }

        // Check each gesture in priority order
        // 1. Pinch (highest priority - most precise)
        if let pinchResult = detectPinch(hand: hand, tracker: tracker) {
            return (pinchResult.isPinched ? .pinch : .none, pinchResult.confidence, pinchResult.amount)
        }

        // 2. Fist
        if detectFist(hand: hand, tracker: tracker) {
            return (.fist, 0.9, 0.0)
        }

        // 3. Spread
        if detectSpread(hand: hand, tracker: tracker) {
            return (.spread, 0.85, 0.0)
        }

        // 4. Point
        if detectPoint(hand: hand, tracker: tracker) {
            return (.point, 0.8, 0.0)
        }

        // 5. Swipe (check velocity)
        if detectSwipe(hand: hand) {
            return (.swipe, 0.75, 0.0)
        }

        return (.none, 0.0, 0.0)
    }


    // MARK: - Gesture Detection Methods

    /// Detect pinch gesture (thumb + index finger close together)
    private func detectPinch(hand: HandTrackingManager.Hand, tracker: HandTrackingManager) -> (isPinched: Bool, confidence: Float, amount: Float)? {
        guard let distance = tracker.getJointDistance(hand: hand, from: .thumbTip, to: .indexTip) else {
            return nil
        }

        // Calculate pinch amount (0 = fully released, 1 = fully pinched)
        let pinchAmount = max(0, min(1, 1.0 - (distance / pinchThreshold)))

        let isPinched = distance < pinchThreshold
        let confidence: Float = isPinched ? min(pinchAmount * 1.2, 1.0) : 0.0

        return (isPinched, confidence, pinchAmount)
    }

    /// Detect spread gesture (all fingers extended and separated)
    private func detectSpread(hand: HandTrackingManager.Hand, tracker: HandTrackingManager) -> Bool {
        // Check if all fingers are extended
        let fingers: [HandTrackingManager.Finger] = [.thumb, .index, .middle, .ring, .little]

        for finger in fingers {
            let extension = tracker.getFingerExtension(hand: hand, finger: finger)
            if extension < 0.6 {
                return false // Finger not extended enough
            }
        }

        // Check finger spacing (distance between tips)
        guard let indexTip = tracker.getJointPosition(hand: hand, joint: .indexTip),
              let middleTip = tracker.getJointPosition(hand: hand, joint: .middleTip),
              let ringTip = tracker.getJointPosition(hand: hand, joint: .ringTip) else {
            return false
        }

        let indexMiddleDist = distance(indexTip, middleTip)
        let middleRingDist = distance(middleTip, ringTip)

        // Fingers should be spread apart
        return indexMiddleDist > spreadThreshold && middleRingDist > spreadThreshold
    }

    /// Detect fist gesture (all fingers closed)
    private func detectFist(hand: HandTrackingManager.Hand, tracker: HandTrackingManager) -> Bool {
        let fingers: [HandTrackingManager.Finger] = [.index, .middle, .ring, .little]

        for finger in fingers {
            if !tracker.isFingerCurled(hand: hand, finger: finger) {
                return false // At least one finger not closed
            }
        }

        return true
    }

    /// Detect point gesture (index finger extended, others closed)
    private func detectPoint(hand: HandTrackingManager.Hand, tracker: HandTrackingManager) -> Bool {
        // Index finger must be extended
        let indexExtension = tracker.getFingerExtension(hand: hand, finger: .index)
        guard indexExtension > pointThreshold else {
            return false
        }

        // Other fingers must be curled
        let otherFingers: [HandTrackingManager.Finger] = [.middle, .ring, .little]

        for finger in otherFingers {
            if !tracker.isFingerCurled(hand: hand, finger: finger) {
                return false
            }
        }

        return true
    }

    /// Detect swipe gesture (fast hand movement)
    private func detectSwipe(hand: HandTrackingManager.Hand) -> Bool {
        // Check hand velocity magnitude
        let velocityMagnitude = length(handVelocity)
        return velocityMagnitude > swipeVelocityThreshold
    }


    // MARK: - Helper Methods

    /// Calculate distance between two points
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> Float {
        let dx = Float(p2.x - p1.x)
        let dy = Float(p2.y - p1.y)
        return sqrt(dx * dx + dy * dy)
    }

    /// Update hand velocity for swipe detection
    private func updateHandVelocity() {
        guard let tracker = handTracker else { return }

        let currentPosition = tracker.rightHandDetected ? tracker.rightHandPosition : tracker.leftHandPosition

        // Calculate velocity (change in position)
        handVelocity = currentPosition - lastHandPosition
        lastHandPosition = currentPosition
    }

    /// Add gesture to history for smoothing
    private func addToHistory(gesture: Gesture, confidence: Float) {
        let entry = GestureHistoryEntry(
            gesture: gesture,
            confidence: confidence,
            timestamp: Date()
        )

        gestureHistory.append(entry)

        // Keep only recent history
        if gestureHistory.count > historySize {
            gestureHistory.removeFirst()
        }
    }

    /// Calculate average confidence from history
    private func calculateAverageConfidence() -> Float {
        guard !gestureHistory.isEmpty else { return 0.0 }

        let totalConfidence = gestureHistory.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(gestureHistory.count)
    }

    /// Get most common gesture from history (for stability)
    func getStableGesture(for hand: HandTrackingManager.Hand) -> Gesture {
        let recentGestures = gestureHistory.suffix(3).map { $0.gesture }

        // Find most common gesture
        let gestureCounts = Dictionary(grouping: recentGestures) { $0 }
            .mapValues { $0.count }

        let mostCommon = gestureCounts.max { $0.value < $1.value }
        return mostCommon?.key ?? .none
    }


    // MARK: - Public Helpers

    /// Get gesture strength (0-1) for mapping to audio parameters
    func getGestureStrength(for hand: HandTrackingManager.Hand) -> Float {
        switch hand {
        case .left:
            return leftHandGesture == .pinch ? leftPinchAmount : (leftHandGesture != .none ? 1.0 : 0.0)
        case .right:
            return rightHandGesture == .pinch ? rightPinchAmount : (rightHandGesture != .none ? 1.0 : 0.0)
        }
    }

    /// Check if specific gesture is active
    func isGestureActive(_ gesture: Gesture, hand: HandTrackingManager.Hand) -> Bool {
        let currentGesture = hand == .left ? leftHandGesture : rightHandGesture
        return currentGesture == gesture && gestureConfidence > 0.5
    }
}
