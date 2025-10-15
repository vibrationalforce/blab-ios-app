import SwiftUI

/// Main entry point for the Blab app
/// This is where your iOS app starts running
@main
struct BlabApp: App {

    /// StateObject ensures the MicrophoneManager stays alive
    /// throughout the app's lifetime
    @StateObject private var microphoneManager = MicrophoneManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(microphoneManager)  // Makes mic manager available to all views
                .preferredColorScheme(.dark)  // Force dark theme
        }
    }
}
