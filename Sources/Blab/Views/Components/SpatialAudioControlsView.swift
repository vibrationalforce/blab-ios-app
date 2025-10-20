import SwiftUI

/// UI Controls for Spatial Audio
/// Shows spatial audio toggle, mode selector, and status
struct SpatialAudioControlsView: View {

    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var deviceCapabilities: DeviceCapabilities
    @ObservedObject var headTrackingManager: HeadTrackingManager
    @ObservedObject var spatialAudioEngine: SpatialAudioEngine

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 15) {
            // Header
            HStack {
                Image(systemName: "airpodspro")
                    .font(.system(size: 20))
                    .foregroundColor(.cyan)

                Text("Spatial Audio")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.5), radius: 5)

                // Expand button
                Button(action: { withAnimation { showDetails.toggle() } }) {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // Main Toggle
            Toggle(isOn: $audioEngine.spatialAudioEnabled) {
                HStack {
                    Text(spatialStatusText)
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.8))

                    if !deviceCapabilities.canUseSpatialAudio {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow.opacity(0.7))
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .disabled(!spatialAudioEngine.isAvailable)

            // Expanded Details
            if showDetails {
                VStack(spacing: 12) {
                    Divider()
                        .background(Color.white.opacity(0.2))

                    // Spatial Mode Picker
                    if audioEngine.spatialAudioEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mode")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))

                            Picker("Spatial Mode", selection: Binding(
                                get: { spatialAudioEngine.spatialMode },
                                set: { spatialAudioEngine.setSpatialMode($0) }
                            )) {
                                ForEach(SpatialAudioEngine.SpatialMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Head Tracking Status
                    HStack {
                        Image(systemName: headTrackingManager.isTracking ? "gyroscope" : "gyroscope.slash")
                            .font(.system(size: 14))
                            .foregroundColor(headTrackingManager.isTracking ? .green : .gray)

                        Text(headTrackingManager.statusDescription)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        if headTrackingManager.isTracking {
                            Text(headTrackingManager.getDirectionArrow())
                                .font(.system(size: 20))
                                .foregroundColor(.cyan)
                        }
                    }

                    // Device Info
                    VStack(spacing: 4) {
                        deviceInfoRow(
                            icon: "iphone",
                            label: "Device",
                            value: deviceCapabilities.deviceModel
                        )

                        if deviceCapabilities.hasAirPodsConnected {
                            deviceInfoRow(
                                icon: "airpodspro",
                                label: "Audio",
                                value: deviceCapabilities.airPodsModel ?? "Unknown"
                            )
                        }

                        deviceInfoRow(
                            icon: deviceCapabilities.supportsASAF ? "checkmark.circle.fill" : "xmark.circle",
                            label: "ASAF",
                            value: deviceCapabilities.supportsASAF ? "Supported" : "Not Available",
                            color: deviceCapabilities.supportsASAF ? .green : .red
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Helper Views

    private func deviceInfoRow(icon: String, label: String, value: String, color: Color = .white.opacity(0.7)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 11, weight: .light))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if !spatialAudioEngine.isAvailable {
            return .gray
        } else if audioEngine.spatialAudioEnabled && spatialAudioEngine.isActive {
            return .green
        } else {
            return .yellow
        }
    }

    private var spatialStatusText: String {
        if !spatialAudioEngine.isAvailable {
            return "Not Available"
        } else if audioEngine.spatialAudioEnabled {
            return "Active"
        } else {
            return "Ready"
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.05, blue: 0.2)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        let micManager = MicrophoneManager()
        let audioEngine = AudioEngine(microphoneManager: micManager)
        let capabilities = DeviceCapabilities()
        let headTracking = HeadTrackingManager()
        let spatial = SpatialAudioEngine(
            headTrackingManager: headTracking,
            deviceCapabilities: capabilities
        )

        SpatialAudioControlsView(
            audioEngine: audioEngine,
            deviceCapabilities: capabilities,
            headTrackingManager: headTracking,
            spatialAudioEngine: spatial
        )
        .padding()
    }
}
