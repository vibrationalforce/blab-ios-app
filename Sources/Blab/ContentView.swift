import SwiftUI

/// Main user interface for the Blab app
/// This view contains the recording controls and visualizations
struct ContentView: View {

    /// Access to the microphone manager from the environment
    @EnvironmentObject var microphoneManager: MicrophoneManager

    /// Track whether we're currently recording
    @State private var isRecording = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),  // Deep blue-black
                    Color(red: 0.1, green: 0.05, blue: 0.2)      // Purple-black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {

                // App Title
                Text("BLAB")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 60)

                Spacer()

                // Particle visualization placeholder
                ParticleView(isActive: isRecording)
                    .frame(height: 300)
                    .padding(.horizontal, 40)

                Spacer()

                // Audio level indicator
                if isRecording {
                    HStack(spacing: 12) {
                        ForEach(0..<20, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(microphoneManager.audioLevel > Float(index) / 20.0 ?
                                      Color.green : Color.gray.opacity(0.3))
                                .frame(width: 8, height: CGFloat(20 + index * 3))
                        }
                    }
                    .padding(.bottom, 20)
                    .transition(.opacity)
                }

                // Start/Stop Button
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.green)
                            .frame(width: 100, height: 100)
                            .shadow(color: isRecording ? .red.opacity(0.5) : .green.opacity(0.5),
                                    radius: 20)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 40)

                // Status text
                Text(isRecording ? "Recording..." : "Tap to Start")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            // Request microphone permission when the app launches
            microphoneManager.requestPermission()
        }
    }

    /// Toggle recording on/off
    private func toggleRecording() {
        if isRecording {
            microphoneManager.stopRecording()
        } else {
            microphoneManager.startRecording()
        }

        // Animate the button with haptic feedback
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isRecording.toggle()
        }

        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

/// Preview for Xcode canvas (helpful for development)
#Preview {
    ContentView()
        .environmentObject(MicrophoneManager())
}
