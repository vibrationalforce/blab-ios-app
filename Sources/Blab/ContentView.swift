import SwiftUI

/// Main user interface for the Blab app
/// Optimized with proper state management and error handling
struct ContentView: View {

    /// Access to the microphone manager from the environment
    @EnvironmentObject var microphoneManager: MicrophoneManager

    /// Access to the central audio engine from the environment
    @EnvironmentObject var audioEngine: AudioEngine

    /// Access to HealthKit manager from the environment
    @EnvironmentObject var healthKitManager: HealthKitManager

    /// Access to Recording engine from the environment
    @EnvironmentObject var recordingEngine: RecordingEngine

    /// Show permission denial alert
    @State private var showPermissionAlert = false

    /// Show recording controls
    @State private var showRecordingControls = false

    /// Show binaural beat controls
    @State private var showBinauralControls = false

    /// Show spatial audio controls
    @State private var showSpatialControls = false

    /// Show visualization mode picker
    @State private var showVisualizationPicker = false

    /// Currently selected visualization mode
    @State private var selectedVisualizationMode: VisualizationMode = .particles

    /// Currently selected brainwave state
    @State private var selectedBrainwaveState: BinauralBeatGenerator.BrainwaveState = .alpha

    /// Binaural beat amplitude
    @State private var binauralAmplitude: Float = 0.3

    /// Computed property - single source of truth for recording state
    private var isRecording: Bool {
        microphoneManager.isRecording
    }

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

                Text("breath → sound")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(3)

                Spacer()

                // Visualization (mode-based)
                visualizationView
                    .frame(height: 350)
                    .padding(.horizontal, 30)

                // Visualization mode picker button
                Button(action: { showVisualizationPicker.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: selectedVisualizationMode.icon)
                            .font(.system(size: 12))
                        Text(selectedVisualizationMode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedVisualizationMode.color.opacity(0.2))
                    )
                }

                Spacer()

                // Frequency and amplitude display
                if isRecording {
                    HStack(spacing: 40) {
                        // FFT Frequency display
                        VStack(spacing: 4) {
                            Text("\(Int(microphoneManager.frequency))")
                                .font(.system(size: 36, weight: .light, design: .monospaced))
                                .foregroundColor(Color(hue: 0.55, saturation: 0.8, brightness: 0.9))
                            Text("FFT Hz")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // Amplitude display
                        VStack(spacing: 4) {
                            Text(String(format: "%.2f", microphoneManager.audioLevel))
                                .font(.system(size: 36, weight: .light, design: .monospaced))
                                .foregroundColor(Color(hue: 0.4, saturation: 0.8, brightness: 0.9))
                            Text("level")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale))

                    // YIN Pitch display (more accurate for voice)
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("\(Int(microphoneManager.currentPitch))")
                                .font(.system(size: 30, weight: .light, design: .monospaced))
                                .foregroundColor(pitchColor(microphoneManager.currentPitch))
                            Text("voice pitch (YIN)")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // Display musical note if pitch detected
                        if microphoneManager.currentPitch > 0 {
                            VStack(spacing: 4) {
                                Text(musicalNote(microphoneManager.currentPitch))
                                    .font(.system(size: 30, weight: .light, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("note")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale))
                }

                // HRV Biofeedback Display
                if healthKitManager.isAuthorized && isRecording {
                    HStack(spacing: 40) {
                        // Heart Rate
                        VStack(spacing: 4) {
                            Text("\(Int(healthKitManager.heartRate))")
                                .font(.system(size: 30, weight: .light, design: .monospaced))
                                .foregroundColor(Color.red.opacity(0.8))
                            Text("BPM")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // HRV RMSSD
                        VStack(spacing: 4) {
                            Text(String(format: "%.1f", healthKitManager.hrvRMSSD))
                                .font(.system(size: 30, weight: .light, design: .monospaced))
                                .foregroundColor(Color.green.opacity(0.8))
                            Text("HRV ms")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // Coherence Score
                        VStack(spacing: 4) {
                            Text("\(Int(healthKitManager.hrvCoherence))")
                                .font(.system(size: 30, weight: .light, design: .monospaced))
                                .foregroundColor(coherenceColor(healthKitManager.hrvCoherence))
                            Text("coherence")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(.bottom, 15)
                    .transition(.opacity.combined(with: .scale))
                }

                // Audio level bars (improved visualization)
                if isRecording {
                    HStack(spacing: 8) {
                        ForEach(0..<24, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor(for: index))
                                .frame(width: 6, height: barHeight(for: index))
                        }
                    }
                    .padding(.bottom, 20)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: microphoneManager.audioLevel)
                }

                // Control Buttons
                HStack(spacing: 30) {
                    // Binaural beats toggle
                    Button(action: toggleBinauralBeats) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(audioEngine.binauralBeatsEnabled ? Color.purple : Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .shadow(
                                        color: audioEngine.binauralBeatsEnabled ? .purple.opacity(0.5) : .clear,
                                        radius: 15
                                    )

                                Image(systemName: audioEngine.binauralBeatsEnabled ? "waveform.circle.fill" : "waveform.circle")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }

                            if audioEngine.binauralBeatsEnabled {
                                Text("Binaural ON")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.white.opacity(0.7))
                            } else {
                                Text("Beats OFF")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }

                    // Main record button
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red : Color(hue: 0.55, saturation: 0.8, brightness: 0.7))
                                .frame(width: 100, height: 100)
                                .shadow(
                                    color: isRecording ? .red.opacity(0.5) : Color.cyan.opacity(0.3),
                                    radius: 20
                                )

                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(!microphoneManager.hasPermission && isRecording)

                    // Spatial audio toggle (if available)
                    if audioEngine.spatialAudioEngine != nil {
                        Button(action: { showSpatialControls.toggle() }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(audioEngine.spatialAudioEnabled ? Color.cyan.opacity(0.3) : Color.gray.opacity(0.3))
                                        .frame(width: 60, height: 60)
                                        .shadow(
                                            color: audioEngine.spatialAudioEnabled ? .cyan.opacity(0.3) : .clear,
                                            radius: 10
                                        )

                                    Image(systemName: "airpodspro")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }

                                Text("Spatial")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }

                    // Recording controls toggle
                    Button(action: { showRecordingControls.toggle() }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(recordingEngine.isRecording ? Color.red.opacity(0.3) : Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .shadow(
                                        color: recordingEngine.isRecording ? .red.opacity(0.3) : .clear,
                                        radius: 10
                                    )

                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }

                            Text("Studio")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // Binaural controls toggle
                    Button(action: { showBinauralControls.toggle() }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)

                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }

                            Text("Settings")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.bottom, 20)

                // Spatial Audio Controls (NEW!)
                if showSpatialControls && audioEngine.spatialAudioEngine != nil {
                    VStack(spacing: 15) {
                        HStack {
                            Image(systemName: "airpodspro")
                                .font(.system(size: 18))
                                .foregroundColor(.cyan)

                            Text("Spatial Audio")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))

                            Spacer()

                            // Status indicator
                            Circle()
                                .fill(audioEngine.spatialAudioEnabled ? .green : .gray)
                                .frame(width: 10, height: 10)
                        }

                        // Toggle
                        Toggle(isOn: Binding(
                            get: { audioEngine.spatialAudioEnabled },
                            set: { _ in audioEngine.toggleSpatialAudio() }
                        )) {
                            Text("Enable 3D Audio")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))

                        // Device Info
                        if let capabilities = audioEngine.deviceCapabilities {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Device: \(capabilities.deviceModel)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))

                                if capabilities.hasAirPodsConnected {
                                    Text("AirPods: \(capabilities.airPodsModel ?? "Unknown")")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                if capabilities.supportsASAF {
                                    Text("✅ ASAF Supported (iOS 19+)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green.opacity(0.7))
                                } else {
                                    Text("⚠️ ASAF requires iOS 19+ & iPhone 16+")
                                        .font(.system(size: 10))
                                        .foregroundColor(.yellow.opacity(0.6))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.4))
                    )
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .scale))
                    .padding(.bottom, 10)
                }

                // Binaural beat controls (expandable)
                if showBinauralControls {
                    VStack(spacing: 15) {
                        Text("Binaural Beat Controls")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))

                        // Brainwave state picker
                        Picker("Brainwave State", selection: Binding(
                            get: { audioEngine.currentBrainwaveState },
                            set: { audioEngine.setBrainwaveState($0) }
                        )) {
                            ForEach(BinauralBeatGenerator.BrainwaveState.allCases, id: \.self) { state in
                                Text(state.rawValue.capitalized).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)

                        // State description
                        Text(audioEngine.currentBrainwaveState.description)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.6))

                        // Amplitude control
                        VStack(spacing: 5) {
                            HStack {
                                Text("Volume")
                                    .font(.system(size: 12, weight: .light))
                                Spacer()
                                Text(String(format: "%.0f%%", audioEngine.binauralAmplitude * 100))
                                    .font(.system(size: 12, weight: .light, design: .monospaced))
                            }
                            .foregroundColor(.white.opacity(0.7))

                            Slider(value: Binding(
                                get: { audioEngine.binauralAmplitude },
                                set: { audioEngine.setBinauralAmplitude($0) }
                            ), in: 0.0...0.6)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.4))
                    )
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .scale))
                    .padding(.bottom, 10)
                }

                // Status text
                Text(statusText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            // Request microphone permission when the app launches
            checkPermissions()

            // Request HealthKit authorization
            Task {
                try? await healthKitManager.requestAuthorization()
            }
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings", action: openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Blab needs microphone access to create music from your voice. Please enable it in Settings.")
        }
        .sheet(isPresented: $showVisualizationPicker) {
            VisualizationModePicker(selectedMode: $selectedVisualizationMode)
        }
        .sheet(isPresented: $showRecordingControls) {
            RecordingControlsView()
                .environmentObject(recordingEngine)
                .environmentObject(healthKitManager)
                .environmentObject(microphoneManager)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Computed Properties

    /// Status text based on current state
    private var statusText: String {
        if !microphoneManager.hasPermission {
            return "Grant Microphone Access"
        } else if isRecording {
            if microphoneManager.frequency > 50 {
                return "Listening... \(Int(microphoneManager.frequency)) Hz"
            } else {
                return "Listening..."
            }
        } else {
            return "Tap to Start"
        }
    }

    /// Visualization view based on selected mode
    @ViewBuilder
    private var visualizationView: some View {
        switch selectedVisualizationMode {
        case .particles:
            ParticleView(
                isActive: isRecording,
                audioLevel: microphoneManager.audioLevel,
                frequency: microphoneManager.frequency > 0 ? microphoneManager.frequency : nil,
                voicePitch: microphoneManager.currentPitch,
                hrvCoherence: healthKitManager.hrvCoherence,
                heartRate: healthKitManager.heartRate
            )
        case .cymatics:
            CymaticsView(
                audioLevel: microphoneManager.audioLevel,
                frequency: microphoneManager.frequency,
                hrvCoherence: healthKitManager.hrvCoherence,
                heartRate: healthKitManager.heartRate
            )
        case .waveform:
            WaveformMode(
                audioBuffer: microphoneManager.audioBuffer ?? [],
                audioLevel: microphoneManager.audioLevel,
                hrvCoherence: healthKitManager.hrvCoherence
            )
        case .spectral:
            SpectralMode(
                fftMagnitudes: microphoneManager.fftMagnitudes ?? [],
                audioLevel: microphoneManager.audioLevel,
                hrvCoherence: healthKitManager.hrvCoherence
            )
        case .mandala:
            MandalaMode(
                audioLevel: microphoneManager.audioLevel,
                frequency: microphoneManager.frequency,
                hrvCoherence: healthKitManager.hrvCoherence,
                heartRate: healthKitManager.heartRate
            )
        }
    }

    /// Calculate bar height based on audio level
    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index) / 24.0
        let active = microphoneManager.audioLevel > threshold
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 60

        if active {
            let relativeHeight = CGFloat(microphoneManager.audioLevel - threshold) * 4.0
            return baseHeight + min(relativeHeight * maxHeight, maxHeight)
        }
        return baseHeight
    }

    /// Color for audio bars based on level
    private func barColor(for index: Int) -> Color {
        let threshold = Float(index) / 24.0
        let active = microphoneManager.audioLevel > threshold

        if active {
            // Gradient from cyan to yellow to red as level increases
            let normalizedIndex = Double(index) / 24.0
            return Color(hue: 0.55 - normalizedIndex * 0.4, saturation: 0.8, brightness: 0.9)
        }
        return Color.gray.opacity(0.2)
    }

    /// Color for coherence score based on HeartMath zones
    /// 0-40: Low coherence (red) - stress/anxiety
    /// 40-60: Medium coherence (yellow) - transitional
    /// 60-100: High coherence (green) - optimal/flow state
    private func coherenceColor(_ score: Double) -> Color {
        if score < 40 {
            return Color.red.opacity(0.8)
        } else if score < 60 {
            return Color.yellow.opacity(0.8)
        } else {
            return Color.green.opacity(0.8)
        }
    }

    /// Color for pitch based on frequency range
    /// Low (bass) = blue, Mid (voice) = purple, High (soprano) = pink
    private func pitchColor(_ pitch: Float) -> Color {
        if pitch < 100 {
            return Color.blue.opacity(0.7)
        } else if pitch < 200 {
            return Color(hue: 0.6, saturation: 0.7, brightness: 0.85) // Blue-purple
        } else if pitch < 400 {
            return Color(hue: 0.75, saturation: 0.7, brightness: 0.85) // Purple
        } else if pitch < 800 {
            return Color(hue: 0.85, saturation: 0.7, brightness: 0.85) // Pink-purple
        } else {
            return Color.pink.opacity(0.8)
        }
    }

    /// Convert frequency to musical note name (12-tone equal temperament)
    /// A4 = 440 Hz is the reference
    private func musicalNote(_ frequency: Float) -> String {
        guard frequency > 0 else { return "-" }

        // Note names in chromatic scale
        let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

        // Calculate semitones from A4 (440 Hz)
        let semitonesFromA4 = 12.0 * log2(frequency / 440.0)
        let roundedSemitones = Int(round(semitonesFromA4))

        // A4 is note index 9 (A) in octave 4
        let noteIndex = (9 + roundedSemitones) % 12
        let octave = 4 + (9 + roundedSemitones) / 12

        // Handle negative modulo correctly
        let positiveNoteIndex = (noteIndex + 12) % 12

        return "\(noteNames[positiveNoteIndex])\(octave)"
    }

    // MARK: - Actions

    /// Toggle recording on/off with proper error handling
    private func toggleRecording() {
        if isRecording {
            // Stop via AudioEngine (handles all components)
            audioEngine.stop()
            healthKitManager.stopMonitoring()
        } else {
            if microphoneManager.hasPermission {
                // Start via AudioEngine (handles all components)
                audioEngine.start()

                // Start HealthKit monitoring if authorized
                if healthKitManager.isAuthorized {
                    healthKitManager.startMonitoring()
                }

                // Provide haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            } else {
                // Request permission and show alert if denied
                microphoneManager.requestPermission()

                // Check again after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !microphoneManager.hasPermission {
                        showPermissionAlert = true
                    }
                }
            }
        }
    }

    /// Toggle binaural beats on/off
    private func toggleBinauralBeats() {
        // Use AudioEngine to toggle (handles configuration)
        audioEngine.toggleBinauralBeats()

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    /// Check permissions on launch
    private func checkPermissions() {
        if !microphoneManager.hasPermission {
            microphoneManager.requestPermission()
        }
    }

    /// Open iOS Settings app
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Preview for Xcode canvas
#Preview {
    ContentView()
        .environmentObject(MicrophoneManager())
}
