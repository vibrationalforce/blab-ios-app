import SwiftUI

/// Main entry point for the Blab app
/// This is where your iOS app starts running
@main
struct BlabApp: App {

    /// StateObject ensures the MicrophoneManager stays alive
    /// throughout the app's lifetime
    @StateObject private var microphoneManager = MicrophoneManager()

    /// Central AudioEngine coordinates all audio components
    @StateObject private var audioEngine: AudioEngine

    /// HealthKit manager for biofeedback
    @StateObject private var healthKitManager = HealthKitManager()

    /// Recording engine for multi-track recording
    @StateObject private var recordingEngine = RecordingEngine()

    init() {
        // Initialize AudioEngine with MicrophoneManager
        let micManager = MicrophoneManager()
        _microphoneManager = StateObject(wrappedValue: micManager)
        _audioEngine = StateObject(wrappedValue: AudioEngine(microphoneManager: micManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(microphoneManager)  // Makes mic manager available to all views
                .environmentObject(audioEngine)         // Makes audio engine available
                .environmentObject(healthKitManager)    // Makes health data available
                .environmentObject(recordingEngine)     // Makes recording engine available
                .preferredColorScheme(.dark)            // Force dark theme
                .onAppear {
                    // Connect HealthKit to AudioEngine for bio-parameter mapping
                    audioEngine.connectHealthKit(healthKitManager)

                    // Connect RecordingEngine to AudioEngine for audio routing
                    recordingEngine.connectAudioEngine(audioEngine)

                    print("🎵 BLAB App Started - All Systems Connected!")
                }
        }
    }
}
