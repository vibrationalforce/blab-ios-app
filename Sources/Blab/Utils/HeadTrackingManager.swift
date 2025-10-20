import Foundation
import CoreMotion
import Combine

/// Manages head tracking using CMHeadphoneMotionManager
/// Provides real-time head orientation data for spatial audio
/// Requires: AirPods Pro/Max with iOS 14+
@MainActor
class HeadTrackingManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether head tracking is currently active
    @Published var isTracking: Bool = false

    /// Whether head tracking is available (requires compatible AirPods)
    @Published var isAvailable: Bool = false

    /// Current head rotation (yaw, pitch, roll) in radians
    @Published var headRotation: HeadRotation = HeadRotation()

    /// Normalized head position (-1.0 to 1.0 for UI display)
    @Published var normalizedPosition: NormalizedPosition = NormalizedPosition()


    // MARK: - Private Properties

    /// CoreMotion manager for headphone motion
    private let motionManager = CMHeadphoneMotionManager()

    /// Update frequency (Hz)
    private let updateFrequency: Double = 60.0  // 60 Hz for smooth tracking

    /// Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()

    /// Smoothing factor for head rotation (0.0 = no smoothing, 1.0 = max smoothing)
    private let smoothingFactor: Double = 0.7


    // MARK: - Data Structures

    /// Head rotation in 3D space
    struct HeadRotation {
        var yaw: Double = 0.0     // Left-right rotation (looking left/right)
        var pitch: Double = 0.0   // Up-down rotation (looking up/down)
        var roll: Double = 0.0    // Tilt rotation (head tilt)

        /// Convert to degrees for debugging
        var degrees: (yaw: Double, pitch: Double, roll: Double) {
            (yaw * 180 / .pi, pitch * 180 / .pi, roll * 180 / .pi)
        }
    }

    /// Normalized position for UI display (-1.0 to 1.0)
    struct NormalizedPosition {
        var x: Double = 0.0  // -1.0 (left) to 1.0 (right)
        var y: Double = 0.0  // -1.0 (down) to 1.0 (up)
        var z: Double = 0.0  // -1.0 (back) to 1.0 (forward)
    }


    // MARK: - Initialization

    init() {
        checkAvailability()
    }


    // MARK: - Availability Check

    /// Check if head tracking is available
    private func checkAvailability() {
        isAvailable = motionManager.isDeviceMotionAvailable

        if isAvailable {
            print("✅ Head tracking available")
        } else {
            print("⚠️  Head tracking not available")
            print("   Requires: AirPods Pro/Max with iOS 14+")
        }
    }


    // MARK: - Tracking Control

    /// Start head tracking
    func startTracking() {
        guard isAvailable else {
            print("❌ Cannot start head tracking: Not available")
            return
        }

        guard !isTracking else {
            print("⚠️  Head tracking already active")
            return
        }

        // Configure motion manager
        motionManager.deviceMotionUpdateInterval = 1.0 / updateFrequency

        // Start receiving motion updates
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Head tracking error: \(error.localizedDescription)")
                self.stopTracking()
                return
            }

            guard let motion = motion else { return }

            // Update head rotation
            self.updateHeadRotation(from: motion)
        }

        isTracking = true
        print("🎧 Head tracking started (\(updateFrequency) Hz)")
    }

    /// Stop head tracking
    func stopTracking() {
        guard isTracking else { return }

        motionManager.stopDeviceMotionUpdates()
        isTracking = false

        // Reset to neutral position
        headRotation = HeadRotation()
        normalizedPosition = NormalizedPosition()

        print("🎧 Head tracking stopped")
    }


    // MARK: - Motion Processing

    /// Update head rotation from motion data
    private func updateHeadRotation(from motion: CMDeviceMotion) {
        let attitude = motion.attitude

        // Get raw rotation values (in radians)
        let rawYaw = attitude.yaw
        let rawPitch = attitude.pitch
        let rawRoll = attitude.roll

        // Apply exponential smoothing for smoother motion
        headRotation.yaw = smooth(headRotation.yaw, target: rawYaw)
        headRotation.pitch = smooth(headRotation.pitch, target: rawPitch)
        headRotation.roll = smooth(headRotation.roll, target: rawRoll)

        // Normalize for UI display (-1.0 to 1.0)
        updateNormalizedPosition()

        // Log debug info (throttled to avoid spam)
        #if DEBUG
        if Int(Date().timeIntervalSince1970 * 2) % 2 == 0 {  // Every 0.5 seconds
            let degrees = headRotation.degrees
            print("🎧 Head: Y:\(Int(degrees.yaw))° P:\(Int(degrees.pitch))° R:\(Int(degrees.roll))°")
        }
        #endif
    }

    /// Exponential smoothing for smoother motion
    private func smooth(_ current: Double, target: Double) -> Double {
        return current * smoothingFactor + target * (1.0 - smoothingFactor)
    }

    /// Update normalized position for UI display
    private func updateNormalizedPosition() {
        // Map rotation angles to -1.0 to 1.0 range

        // Yaw: -π to π → -1.0 to 1.0 (left-right)
        normalizedPosition.x = headRotation.yaw / .pi

        // Pitch: -π/2 to π/2 → -1.0 to 1.0 (up-down)
        normalizedPosition.y = headRotation.pitch / (.pi / 2.0)

        // Roll: -π to π → -1.0 to 1.0 (tilt)
        normalizedPosition.z = headRotation.roll / .pi

        // Clamp to -1.0 to 1.0 range
        normalizedPosition.x = max(-1.0, min(1.0, normalizedPosition.x))
        normalizedPosition.y = max(-1.0, min(1.0, normalizedPosition.y))
        normalizedPosition.z = max(-1.0, min(1.0, normalizedPosition.z))
    }


    // MARK: - Utility Methods

    /// Reset head tracking to neutral position
    func resetOrientation() {
        guard isTracking else { return }

        // Reset the reference frame
        motionManager.stopDeviceMotionUpdates()

        // Restart with new reference frame
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Head tracking error: \(error.localizedDescription)")
                return
            }

            guard let motion = motion else { return }
            self.updateHeadRotation(from: motion)
        }

        print("🔄 Head tracking orientation reset")
    }

    /// Get human-readable status
    var statusDescription: String {
        if !isAvailable {
            return "Head tracking not available"
        } else if isTracking {
            let degrees = headRotation.degrees
            return "Tracking: Y:\(Int(degrees.yaw))° P:\(Int(degrees.pitch))° R:\(Int(degrees.roll))°"
        } else {
            return "Head tracking ready"
        }
    }


    // MARK: - Cleanup

    deinit {
        stopTracking()
    }
}


// MARK: - Spatial Audio Integration

extension HeadTrackingManager {

    /// Get 3D position for spatial audio
    /// Returns (x, y, z) coordinates suitable for AVAudioEnvironmentNode
    func get3DAudioPosition() -> (x: Float, y: Float, z: Float) {
        // Convert head rotation to 3D audio position
        // In AVAudioEnvironmentNode:
        // - X axis: left (-) to right (+)
        // - Y axis: down (-) to up (+)
        // - Z axis: front (+) to back (-)

        let x = Float(normalizedPosition.x)  // Left-right
        let y = Float(normalizedPosition.y)  // Up-down
        let z = Float(-normalizedPosition.z) // Front-back (inverted)

        return (x, y, z)
    }

    /// Get listener orientation for spatial audio
    /// Returns (yaw, pitch, roll) in radians
    func getListenerOrientation() -> (yaw: Float, pitch: Float, roll: Float) {
        let yaw = Float(headRotation.yaw)
        let pitch = Float(headRotation.pitch)
        let roll = Float(headRotation.roll)

        return (yaw, pitch, roll)
    }
}


// MARK: - UI Helpers

extension HeadTrackingManager {

    /// Get color based on head position (for visualization)
    func getVisualizationColor() -> (red: Double, green: Double, blue: Double) {
        // Map normalized position to RGB colors
        let r = (normalizedPosition.x + 1.0) / 2.0  // 0.0 to 1.0
        let g = (normalizedPosition.y + 1.0) / 2.0  // 0.0 to 1.0
        let b = (normalizedPosition.z + 1.0) / 2.0  // 0.0 to 1.0

        return (r, g, b)
    }

    /// Get arrow direction for UI (→ ← ↑ ↓)
    func getDirectionArrow() -> String {
        let threshold = 0.3

        if normalizedPosition.x > threshold {
            return "→"
        } else if normalizedPosition.x < -threshold {
            return "←"
        } else if normalizedPosition.y > threshold {
            return "↑"
        } else if normalizedPosition.y < -threshold {
            return "↓"
        } else {
            return "○"  // Neutral
        }
    }
}
