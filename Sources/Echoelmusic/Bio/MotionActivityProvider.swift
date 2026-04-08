#if canImport(CoreMotion)
import Foundation
import CoreMotion
import Observation

/// Detects user activity state (stationary, walking, running, automotive)
/// using Core Motion. Feeds into SoundscapeEngine for environment-reactive audio.
///
/// Core Motion activity recognition is extremely reliable on iPhone and works
/// without any user permission for basic activity data (CMMotionActivityManager).
/// Accelerometer data requires no special entitlement.
///
/// Mapping to soundscape:
///   - Stationary → darker, slower, more harmonic (meditation mode)
///   - Walking → moderate brightness, gentle texture evolution
///   - Running → brighter, more energy, faster modulation
///   - Automotive → smooth, spacious, long reverb
@MainActor
@Observable
final class MotionActivityProvider {

    // MARK: - Output

    /// Current activity state
    var activityState: ActivityState = .unknown

    /// Movement intensity (0 = still, 1 = vigorous) from accelerometer magnitude
    var movementIntensity: Float = 0.0

    /// Smoothed movement intensity for audio modulation
    var smoothedIntensity: Float = 0.0

    // MARK: - Activity States

    enum ActivityState: String {
        case stationary = "Stationary"
        case walking = "Walking"
        case running = "Running"
        case cycling = "Cycling"
        case automotive = "Driving"
        case unknown = "Unknown"

        /// Soundscape brightness multiplier (0 = darkest, 1 = brightest)
        var brightnessMultiplier: Float {
            switch self {
            case .stationary:  return 0.0
            case .walking:     return 0.4
            case .cycling:     return 0.6
            case .running:     return 0.8
            case .automotive:  return 0.2
            case .unknown:     return 0.1
            }
        }

        /// Soundscape evolution speed multiplier
        var evolutionSpeed: Float {
            switch self {
            case .stationary:  return 0.3   // Glacial
            case .walking:     return 0.7   // Moderate
            case .cycling:     return 0.9
            case .running:     return 1.0   // Full speed
            case .automotive:  return 0.5   // Smooth cruise
            case .unknown:     return 0.5
            }
        }

        /// Reverb amount (more for still/driving, less for active)
        var reverbBoost: Float {
            switch self {
            case .stationary:  return 0.3   // Spacious
            case .walking:     return 0.1
            case .cycling:     return 0.0
            case .running:     return 0.0   // Dry
            case .automotive:  return 0.25  // Smooth
            case .unknown:     return 0.1
            }
        }
    }

    // MARK: - Private

    private let activityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private var isMonitoring = false

    /// Smoothing coefficient for movement intensity
    private let smoothingAlpha: Float = 0.05

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard CMMotionActivityManager.isActivityAvailable() else {
            log.log(.warning, category: .biofeedback, "Motion activity not available on this device")
            return
        }

        isMonitoring = true

        // Activity recognition (walking, running, stationary, etc.)
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor [weak self] in
                self?.processActivity(activity)
            }
        }

        // Accelerometer for movement intensity (~10 Hz is enough for this purpose)
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor [weak self] in
                    self?.processAccelerometer(data)
                }
            }
        }

        log.log(.info, category: .biofeedback, "Motion activity monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        activityManager.stopActivityUpdates()
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        log.log(.info, category: .biofeedback, "Motion activity monitoring stopped")
    }

    // MARK: - Processing

    private func processActivity(_ activity: CMMotionActivity) {
        if activity.running {
            activityState = .running
        } else if activity.cycling {
            activityState = .cycling
        } else if activity.walking {
            activityState = .walking
        } else if activity.automotive {
            activityState = .automotive
        } else if activity.stationary {
            activityState = .stationary
        } else {
            activityState = .unknown
        }
    }

    private func processAccelerometer(_ data: CMAccelerometerData) {
        // Magnitude of acceleration minus gravity (~1g when stationary)
        let x = Float(data.acceleration.x)
        let y = Float(data.acceleration.y)
        let z = Float(data.acceleration.z)
        let magnitude = sqrtf(x * x + y * y + z * z)

        // Deviation from 1g (gravity) = user-generated movement
        let movement = abs(magnitude - 1.0)
        // Normalize: 0 = still, ~0.5 = walking, ~1.0 = vigorous
        movementIntensity = min(movement * 3.0, 1.0)

        // Exponential moving average for smooth audio modulation
        smoothedIntensity = smoothedIntensity * (1.0 - smoothingAlpha) + movementIntensity * smoothingAlpha
    }
}
#endif
