import Foundation
import UIKit
import AVFoundation

/// Detects device capabilities for BLAB
/// - iPhone model detection
/// - iOS version check
/// - ASAF (Apple Spatial Audio Features) support
/// - AirPods model detection
/// - Audio codec capabilities
@MainActor
class DeviceCapabilities: ObservableObject {

    // MARK: - Published Properties

    /// Current device model (e.g., "iPhone 16 Pro Max")
    @Published var deviceModel: String = ""

    /// iOS version (e.g., "17.0")
    @Published var iOSVersion: String = ""

    /// Whether device supports ASAF (iOS 19+ with compatible hardware)
    @Published var supportsASAF: Bool = false

    /// Whether AirPods are connected
    @Published var hasAirPodsConnected: Bool = false

    /// AirPods model if detected
    @Published var airPodsModel: String? = nil

    /// Whether APAC codec is available (AirPods Pro 3 with iOS 19+)
    @Published var supportsAPACCodec: Bool = false


    // MARK: - Device Models

    /// Known iPhone models that support advanced spatial audio
    private let spatialAudioCapableModels: Set<String> = [
        "iPhone16,1",  // iPhone 16 Pro
        "iPhone16,2",  // iPhone 16 Pro Max
        "iPhone17,1",  // iPhone 17
        "iPhone17,2",  // iPhone 17 Pro
        "iPhone17,3",  // iPhone 17 Pro Max
    ]


    // MARK: - Initialization

    init() {
        detectCapabilities()
    }


    // MARK: - Detection Methods

    /// Detect all device capabilities
    func detectCapabilities() {
        detectDeviceModel()
        detectiOSVersion()
        detectASAFSupport()
        detectAirPods()
    }

    /// Detect iPhone model
    private func detectDeviceModel() {
        var systemInfo = utsname()
        uname(&systemInfo)

        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        deviceModel = mapDeviceIdentifier(identifier)

        print("📱 Device: \(deviceModel) (\(identifier))")
    }

    /// Map device identifier to human-readable name
    private func mapDeviceIdentifier(_ identifier: String) -> String {
        switch identifier {
        // iPhone 16 Series
        case "iPhone16,1": return "iPhone 16 Pro"
        case "iPhone16,2": return "iPhone 16 Pro Max"
        case "iPhone16,3": return "iPhone 16"
        case "iPhone16,4": return "iPhone 16 Plus"

        // iPhone 17 Series (future)
        case "iPhone17,1": return "iPhone 17"
        case "iPhone17,2": return "iPhone 17 Pro"
        case "iPhone17,3": return "iPhone 17 Pro Max"

        // iPhone 15 Series
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"

        // Simulator
        case "x86_64", "arm64": return "iOS Simulator"

        default: return identifier
        }
    }

    /// Detect iOS version
    private func detectiOSVersion() {
        let version = UIDevice.current.systemVersion
        iOSVersion = version

        print("🔧 iOS Version: \(version)")
    }

    /// Check if device supports ASAF (Apple Spatial Audio Features)
    /// Requires: iOS 19+ AND compatible hardware (iPhone 16+)
    private func detectASAFSupport() {
        // Get iOS major version
        let versionComponents = iOSVersion.components(separatedBy: ".")
        guard let majorVersion = versionComponents.first,
              let majorInt = Int(majorVersion) else {
            supportsASAF = false
            return
        }

        // Check iOS version (19+)
        let hasRequiredOS = majorInt >= 19

        // Check hardware capability
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        let hasCapableHardware = spatialAudioCapableModels.contains(identifier)

        supportsASAF = hasRequiredOS && hasCapableHardware

        if supportsASAF {
            print("✅ ASAF Supported (iOS \(majorVersion)+ with \(deviceModel))")
        } else {
            print("⚠️  ASAF Not Supported (Need iOS 19+ and iPhone 16+)")
            print("   Current: iOS \(iOSVersion), \(deviceModel)")
        }
    }

    /// Detect connected AirPods
    private func detectAirPods() {
        // Check for connected audio outputs
        let session = AVAudioSession.sharedInstance()

        // Get current route
        let outputs = session.currentRoute.outputs

        for output in outputs {
            let portType = output.portType
            let portName = output.portName

            // Check if AirPods are connected
            if portType == .bluetoothA2DP || portType == .bluetoothHFP || portType == .bluetoothLE {
                hasAirPodsConnected = true

                // Detect AirPods model from name
                if portName.contains("AirPods Pro") {
                    if portName.contains("3") || portName.contains("Third") {
                        airPodsModel = "AirPods Pro (3rd generation)"
                        supportsAPACCodec = true  // APAC codec on AirPods Pro 3
                    } else if portName.contains("2") || portName.contains("Second") {
                        airPodsModel = "AirPods Pro (2nd generation)"
                    } else {
                        airPodsModel = "AirPods Pro"
                    }
                } else if portName.contains("AirPods Max") {
                    airPodsModel = "AirPods Max"
                } else if portName.contains("AirPods") {
                    airPodsModel = "AirPods"
                } else {
                    airPodsModel = "Bluetooth Audio Device"
                }

                print("🎧 Audio Output: \(airPodsModel ?? "Unknown")")
                if supportsAPACCodec {
                    print("✅ APAC Codec Available")
                }

                return
            }
        }

        // No AirPods detected
        hasAirPodsConnected = false
        airPodsModel = nil
        supportsAPACCodec = false

        print("🔇 No AirPods detected")
    }


    // MARK: - Capability Queries

    /// Check if full spatial audio features are available
    /// (ASAF support + AirPods connected)
    var canUseSpatialAudio: Bool {
        supportsASAF && hasAirPodsConnected
    }

    /// Check if basic head tracking is available (iOS 14+)
    var canUseHeadTracking: Bool {
        let versionComponents = iOSVersion.components(separatedBy: ".")
        guard let majorVersion = versionComponents.first,
              let majorInt = Int(majorVersion) else {
            return false
        }
        return majorInt >= 14
    }

    /// Check if AVAudioEnvironmentNode is available (iOS 15+)
    var canUseSpatialAudioEngine: Bool {
        let versionComponents = iOSVersion.components(separatedBy: ".")
        guard let majorVersion = versionComponents.first,
              let majorInt = Int(majorVersion) else {
            return false
        }
        return majorInt >= 15
    }

    /// Get capability summary
    var capabilitySummary: String {
        var summary = "Device: \(deviceModel) (iOS \(iOSVersion))\n"
        summary += "ASAF Support: \(supportsASAF ? "✅" : "❌")\n"
        summary += "AirPods: \(hasAirPodsConnected ? "✅ \(airPodsModel ?? "Unknown")" : "❌ Not Connected")\n"
        summary += "APAC Codec: \(supportsAPACCodec ? "✅" : "❌")\n"
        summary += "Head Tracking: \(canUseHeadTracking ? "✅" : "❌")\n"
        summary += "Full Spatial Audio: \(canUseSpatialAudio ? "✅" : "❌")"
        return summary
    }


    // MARK: - Audio Route Monitoring

    /// Start monitoring audio route changes (detect AirPods connection/disconnection)
    func startMonitoringAudioRoute() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        print("🔊 Started monitoring audio route changes")
    }

    /// Stop monitoring audio route changes
    func stopMonitoringAudioRoute() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        print("🔇 Stopped monitoring audio route changes")
    }

    /// Handle audio route changes
    @objc private func audioRouteChanged(notification: Notification) {
        print("🔄 Audio route changed, re-detecting AirPods...")
        detectAirPods()
    }


    // MARK: - Cleanup

    deinit {
        stopMonitoringAudioRoute()
    }
}


// MARK: - Convenience Extensions

extension DeviceCapabilities {

    /// Get recommended audio configuration based on capabilities
    var recommendedAudioConfig: AudioConfiguration {
        if canUseSpatialAudio {
            return .spatialAudio
        } else if hasAirPodsConnected {
            return .binauralBeats
        } else {
            return .standard
        }
    }

    enum AudioConfiguration {
        case spatialAudio    // Full 3D spatial audio with head tracking
        case binauralBeats   // Binaural beats for headphones
        case standard        // Standard stereo

        var description: String {
            switch self {
            case .spatialAudio:
                return "Spatial Audio with Head Tracking"
            case .binauralBeats:
                return "Binaural Beats (Headphones)"
            case .standard:
                return "Standard Stereo"
            }
        }
    }
}
