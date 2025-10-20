import SwiftUI

/// Main recording controls view with session management
struct RecordingControlsView: View {
    @EnvironmentObject var recordingEngine: RecordingEngine
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var microphoneManager: MicrophoneManager

    @State private var showSessionNamePrompt = false
    @State private var newSessionName = ""
    @State private var showTrackList = false
    @State private var showMixer = false
    @State private var showExportOptions = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Recording")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Session indicator
                if let session = recordingEngine.currentSession {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.cyan)

                        Text("\(session.tracks.count) tracks")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            // Session controls
            if recordingEngine.currentSession == nil {
                // New session button
                Button(action: { showSessionNamePrompt = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("New Session")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cyan.opacity(0.3))
                    )
                }
            } else {
                // Recording controls
                recordingControlsSection

                // Transport controls
                transportControlsSection

                // Track management buttons
                trackManagementSection
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.4))
        )
        .sheet(isPresented: $showSessionNamePrompt) {
            sessionNamePromptView
        }
        .sheet(isPresented: $showTrackList) {
            if let session = recordingEngine.currentSession {
                TrackListView(session: .constant(session))
                    .environmentObject(recordingEngine)
            }
        }
        .sheet(isPresented: $showMixer) {
            if let session = recordingEngine.currentSession {
                MixerView(session: .constant(session))
                    .environmentObject(recordingEngine)
            }
        }
        .sheet(isPresented: $showExportOptions) {
            exportOptionsView
        }
    }

    // MARK: - Recording Controls Section

    private var recordingControlsSection: some View {
        HStack(spacing: 15) {
            // Record button
            Button(action: toggleRecording) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(recordingEngine.isRecording ? Color.red : Color.red.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .shadow(
                                color: recordingEngine.isRecording ? .red.opacity(0.5) : .clear,
                                radius: 15
                            )

                        Image(systemName: recordingEngine.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }

                    Text(recordingEngine.isRecording ? "Stop" : "Record")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            // Time display
            VStack(spacing: 4) {
                Text(timeString(recordingEngine.currentTime))
                    .font(.system(size: 24, weight: .light, design: .monospaced))
                    .foregroundColor(.white)

                Text(recordingEngine.isRecording ? "Recording" : recordingEngine.isPlaying ? "Playing" : "Ready")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Level meter
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)

                    // Animated level ring
                    Circle()
                        .trim(from: 0, to: CGFloat(recordingEngine.recordingLevel))
                        .stroke(
                            recordingEngine.recordingLevel > 0.8 ? Color.red : Color.green,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.1), value: recordingEngine.recordingLevel)

                    Text("\(Int(recordingEngine.recordingLevel * 100))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Text("Level")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Transport Controls Section

    private var transportControlsSection: some View {
        HStack(spacing: 20) {
            // Play button
            Button(action: togglePlayback) {
                Image(systemName: recordingEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(recordingEngine.isPlaying ? Color.cyan : Color.cyan.opacity(0.3))
                    )
            }
            .disabled(recordingEngine.isRecording)

            // Stop button
            Button(action: stopPlayback) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    )
            }
            .disabled(!recordingEngine.isPlaying)

            // Progress slider
            if let session = recordingEngine.currentSession, session.duration > 0 {
                Slider(
                    value: Binding(
                        get: { recordingEngine.currentTime },
                        set: { recordingEngine.seek(to: $0) }
                    ),
                    in: 0...session.duration
                )
                .tint(.cyan)
                .disabled(recordingEngine.isRecording || recordingEngine.isPlaying)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Track Management Section

    private var trackManagementSection: some View {
        HStack(spacing: 12) {
            // Tracks list button
            Button(action: { showTrackList.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                    Text("Tracks")
                        .font(.system(size: 11, weight: .medium))
                    if let session = recordingEngine.currentSession {
                        Text("(\(session.tracks.count))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }

            // Mixer button
            Button(action: { showMixer.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Text("Mixer")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }

            // Export button
            Button(action: { showExportOptions.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                    Text("Export")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }
            .disabled(recordingEngine.currentSession?.tracks.isEmpty ?? true)
        }
    }

    // MARK: - Session Name Prompt

    private var sessionNamePromptView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create New Session")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.top, 40)

                TextField("Session Name", text: $newSessionName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)

                // Template buttons
                VStack(spacing: 12) {
                    Text("Choose Template")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    templateButton(title: "Meditation", icon: "leaf.fill", template: .meditation)
                    templateButton(title: "Healing", icon: "heart.fill", template: .healing)
                    templateButton(title: "Creative", icon: "sparkles", template: .creative)
                    templateButton(title: "Custom", icon: "wand.and.stars", template: .custom)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationBarItems(
                leading: Button("Cancel") {
                    showSessionNamePrompt = false
                    newSessionName = ""
                },
                trailing: Button("Create") {
                    createSession(template: .custom)
                }
                .disabled(newSessionName.isEmpty)
            )
        }
    }

    private func templateButton(title: String, icon: String, template: Session.SessionTemplate) -> some View {
        Button(action: {
            if newSessionName.isEmpty {
                newSessionName = title
            }
            createSession(template: template)
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
            )
        }
    }

    // MARK: - Export Options View

    private var exportOptionsView: some View {
        NavigationView {
            List {
                Section(header: Text("Audio Format")) {
                    exportFormatButton(title: "WAV", icon: "waveform", format: .wav)
                    exportFormatButton(title: "M4A", icon: "music.note", format: .m4a)
                    exportFormatButton(title: "AIFF", icon: "waveform.circle", format: .aiff)
                }

                Section(header: Text("Bio-Data")) {
                    exportBioDataButton(title: "JSON", icon: "doc.text", format: .json)
                    exportBioDataButton(title: "CSV", icon: "tablecells", format: .csv)
                }

                Section(header: Text("Complete Package")) {
                    Button(action: exportPackage) {
                        HStack {
                            Image(systemName: "archivebox.fill")
                            Text("Export Session Package")
                            Spacer()
                            Image(systemName: "arrow.down.doc")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarItems(trailing: Button("Done") {
                showExportOptions = false
            })
        }
    }

    private func exportFormatButton(title: String, icon: String, format: ExportManager.ExportFormat) -> some View {
        Button(action: { exportAudio(format: format) }) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "arrow.down.doc")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func exportBioDataButton(title: String, icon: String, format: ExportManager.BioDataFormat) -> some View {
        Button(action: { exportBioData(format: format) }) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "arrow.down.doc")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func createSession(template: Session.SessionTemplate) {
        let name = newSessionName.isEmpty ? "New Session" : newSessionName
        _ = recordingEngine.createSession(name: name, template: template)
        showSessionNamePrompt = false
        newSessionName = ""
    }

    private func toggleRecording() {
        if recordingEngine.isRecording {
            try? recordingEngine.stopRecording()
        } else {
            try? recordingEngine.startRecording()

            // Start capturing bio-data
            startBioDataCapture()
        }
    }

    private func togglePlayback() {
        if recordingEngine.isPlaying {
            recordingEngine.pausePlayback()
        } else {
            try? recordingEngine.startPlayback()
        }
    }

    private func stopPlayback() {
        recordingEngine.stopPlayback()
    }

    private func startBioDataCapture() {
        // Capture bio-data every 0.5 seconds while recording
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !recordingEngine.isRecording {
                timer.invalidate()
                return
            }

            recordingEngine.addBioDataPoint(
                hrv: healthKitManager.hrv,
                heartRate: healthKitManager.heartRate,
                coherence: healthKitManager.hrvCoherence,
                audioLevel: microphoneManager.audioLevel,
                frequency: microphoneManager.frequency
            )
        }
    }

    private func exportAudio(format: ExportManager.ExportFormat) {
        guard let session = recordingEngine.currentSession else { return }

        let exportManager = ExportManager()
        Task {
            do {
                let url = try await exportManager.exportAudio(session: session, format: format)
                print("📤 Exported to: \(url.path)")
                // TODO: Show share sheet
            } catch {
                print("❌ Export failed: \(error)")
            }
        }
    }

    private func exportBioData(format: ExportManager.BioDataFormat) {
        guard let session = recordingEngine.currentSession else { return }

        let exportManager = ExportManager()
        do {
            let url = try exportManager.exportBioData(session: session, format: format)
            print("📤 Exported bio-data to: \(url.path)")
            // TODO: Show share sheet
        } catch {
            print("❌ Export failed: \(error)")
        }
    }

    private func exportPackage() {
        guard let session = recordingEngine.currentSession else { return }

        let exportManager = ExportManager()
        Task {
            do {
                let url = try await exportManager.exportSessionPackage(session: session)
                print("📦 Exported package to: \(url.path)")
                // TODO: Show share sheet
            } catch {
                print("❌ Export failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}
