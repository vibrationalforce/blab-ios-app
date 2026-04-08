#if canImport(SwiftUI)
import SwiftUI

/// Minimal settings: Oura Ring connection, audio output, bio source info.
struct SettingsView: View {

    @Environment(SoundscapeEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var showCameraMeasurement = false

    var body: some View {
        NavigationStack {
            List {
                // Bio Sources
                Section {
                    bioSourceRow(
                        name: "Apple Watch",
                        status: engine.bioSourceManager.primarySource == .healthKit
                            || engine.bioSourceManager.primarySource == .appleWatch
                            ? "Connected" : "Not connected",
                        connected: engine.bioSourceManager.primarySource == .healthKit
                            || engine.bioSourceManager.primarySource == .appleWatch
                    )
                    cameraRow
                    ouraRow
                } header: {
                    Text("Bio Sources")
                }

                // Audio
                Section {
                    HStack {
                        Text("Output")
                        Spacer()
                        Text(engine.audioOutputName)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Connect Bluetooth speakers via iOS Settings > Bluetooth.")
                }

                // Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Rows

    private func bioSourceRow(name: String, status: String, connected: Bool) -> some View {
        HStack {
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(name)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
        }
    }

    private var cameraRow: some View {
        HStack {
            Circle()
                .fill(engine.bioSourceManager.isCameraActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text("Camera Pulse")
            Spacer()
            if engine.bioSourceManager.isCameraActive {
                Button("Stop") {
                    engine.bioSourceManager.stopCamera()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Measure") {
                    showCameraMeasurement = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .sheet(isPresented: $showCameraMeasurement) {
            CameraMeasurementView()
                .environment(engine)
        }
    }

    private var ouraRow: some View {
        HStack {
            Circle()
                .fill(OuraRingClient.shared.authState == .authenticated
                    ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text("Oura Ring")
            Spacer()
            switch OuraRingClient.shared.authState {
            case .authenticated:
                Text("Connected")
                    .foregroundStyle(.secondary)
            case .unauthenticated:
                Button("Connect") {
                    connectOura()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            default:
                Text(OuraRingClient.shared.authState.rawValue.capitalized)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Oura OAuth

    private func connectOura() {
        // Oura OAuth requires a client ID from developer portal
        // For now, show that the flow is wired
        guard let url = OuraRingClient.shared.authorizationURL() else {
            log.log(.warning, category: .biofeedback, "Oura: Client ID not configured")
            return
        }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}
#endif
