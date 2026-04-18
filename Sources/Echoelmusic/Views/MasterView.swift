#if canImport(SwiftUI)
import SwiftUI
import SwiftData
import os.log

/// One-screen Live Music Studio.
/// Portrait: full-screen instrument + status bar + mode strip.
/// Landscape: instrument (left) | mix + bio + stream (right).
/// No navigation stack. No window switching. Everything visible.
struct MasterView: View {

    let clipEngine: ClipEngine

    @Environment(SoundscapeEngine.self) private var engine
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(EchoelBioEngine.self) private var bio
    @Environment(\.modelContext) private var modelContext

    @State private var activeMode: StudioMode = .perform

    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showCameraPulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if geo.size.width > geo.size.height {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(engine)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistoryView()
        }
        .sheet(isPresented: $showCameraPulse) {
            CameraMeasurementView().environment(engine)
        }
    }

    // MARK: - Layouts

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            ZStack {
                switch activeMode {
                case .perform: performContent
                case .mix:     mixContent
                case .stream:  streamContent
                case .export:  exportContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.15), value: activeMode)

            modeStrip.padding(.bottom, 24)
        }
    }

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left column — instrument + controls
            VStack(spacing: 0) {
                statusBar.padding(12)
                performContent
                modeStrip.padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            // Right column — mix, bio, stream stacked
            VStack(spacing: 0) {
                mixContent.padding(.top, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.vertical, 8)

                bioCompactRow.padding(.horizontal, 16)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.vertical, 8)

                streamStatusRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                Spacer()
            }
            .frame(maxWidth: 280)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            // REC button — wired to RetroCapture
            Button {
                if audioEngine.retroCapture.isRecording {
                    audioEngine.retroCapture.stopRecording()
                } else {
                    audioEngine.retroCapture.startRecording()
                }
            } label: {
                let rec = audioEngine.retroCapture.isRecording
                HStack(spacing: 6) {
                    Circle()
                        .fill(rec ? Color.red : Color.white.opacity(0.15))
                        .frame(width: 7, height: 7)
                    Text(rec ? formatTimer(audioEngine.retroCapture.recordingSeconds) : "REC")
                        .font(.system(size: 11, weight: .semibold, design: rec ? .monospaced : .default))
                        .foregroundStyle(rec ? .red : .white.opacity(0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke((audioEngine.retroCapture.isRecording ? Color.red.opacity(0.35) : Color.white.opacity(0.08)), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioEngine.retroCapture.isRecording ? "Stop recording" : "Start recording")

            if engine.sessionTracker.isActive {
                Text(formatTimer(engine.sessionTracker.currentDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.18))
            }

            Spacer()

            // Bio badge — always visible, driven by BioSourceManager
            bioBadge

            // LIVE badge — Phase 2 placeholder
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.18))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )

            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Session history")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Mode Strip

    private var modeStrip: some View {
        HStack(spacing: 0) {
            ForEach(StudioMode.allCases, id: \.self) { mode in
                Button {
                    activeMode = mode
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 14))
                        Text(mode.label)
                            .font(.system(size: 9, weight: .medium))
                            .kerning(0.5)
                    }
                    .foregroundStyle(activeMode == mode ? .white : .white.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    // MARK: - Perform

    private var performContent: some View {
        VStack(spacing: 0) {
            // Compact header: coherence ring miniature + play/pause
            HStack(spacing: 16) {
                pauseResumeButton
                coherenceMini
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Scene launcher grid
            SessionGridView(clipEngine: clipEngine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Mix

    private var mixContent: some View {
        @Bindable var eng = engine
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Voice Mix")
                    .padding(.top, 20)

                voiceSlider(label: "Root",   value: $eng.mixRoot)
                voiceSlider(label: "Fifth",  value: $eng.mixFifth)
                voiceSlider(label: "Octave", value: $eng.mixOctave)
                voiceSlider(label: "High",   value: $eng.mixHigh)

                separator.padding(.vertical, 8)

                // AutoMixChain — master processing
                autoMixPanel

                separator.padding(.vertical, 8)

                signalStatusRow

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private var autoMixPanel: some View {
        let mix = audioEngine.autoMixChain
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Auto Master")
                Spacer()
                // LUFS reading
                Text(mix.lufsReading > -59
                     ? String(format: "%.1f LUFS", mix.lufsReading)
                     : "– LUFS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(lufsColor(mix.lufsReading))
                // Enable toggle
                Button {
                    mix.isEnabled.toggle()
                } label: {
                    Text(mix.isEnabled ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(mix.isEnabled ? .white.opacity(0.7) : .white.opacity(0.2))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(mix.isEnabled ? 0.25 : 0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // Target LUFS row
            HStack(spacing: 10) {
                Text("Target")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(width: 44, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach([(-14, "Stream"), (-9, "Club"), (-23, "Broadcast")], id: \.0) { val, label in
                        Button {
                            mix.targetLUFS = Float(val)
                        } label: {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(mix.targetLUFS == Float(val) ? .white : .white.opacity(0.25))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(mix.targetLUFS == Float(val) ? 0.2 : 0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Preset row
            HStack(spacing: 10) {
                Text("Sound")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(width: 44, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach([
                        (AutoMixChain.Preset.balanced,    "Balanced"),
                        (AutoMixChain.Preset.warm,        "Warm"),
                        (AutoMixChain.Preset.bright,      "Bright"),
                        (AutoMixChain.Preset.transparent, "Flat"),
                    ], id: \.1) { preset, label in
                        Button { mix.preset = preset } label: {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(mix.preset == preset ? .white : .white.opacity(0.25))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(mix.preset == preset ? 0.2 : 0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func lufsColor(_ lufs: Float) -> Color {
        guard lufs > -59 else { return .white.opacity(0.15) }
        let target = audioEngine.autoMixChain.targetLUFS
        let diff = abs(lufs - target)
        if diff < 1.5 { return .green }
        if diff < 4.0 { return .yellow }
        return .orange
    }

    // MARK: - Bio Badge (status bar — always visible, no dedicated tab)

    private var bioBadge: some View {
        let hr = engine.state.heartRate
        let coherence = engine.state.coherence
        let hasBio = engine.bioSourceManager.primarySource != .fallback

        let dotColor: Color = hasBio ? (coherence > 0.6 ? .green : coherence > 0.3 ? .yellow : .orange) : .white.opacity(0.1)

        return Button { showCameraPulse = true } label: {
            HStack(spacing: 5) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(hasBio ? "\(Int(hr))" : "–")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(hasBio ? 0.4 : 0.15))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasBio ? "Heart rate \(Int(hr)) BPM — tap for camera pulse" : "No bio signal — tap to measure")
    }

    // MARK: - Stream (Phase 2 placeholder)

    private var streamContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.1))
            Text("Live Stream")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
            Text("Next build")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.1))
            Spacer()
        }
    }

    // MARK: - Export (Phase 1 shell — SingleExport wires here)

    private var exportContent: some View {
        VStack(spacing: 20) {
            Spacer()

            if engine.sessionTracker.isActive {
                VStack(spacing: 6) {
                    Text(formatTimer(engine.sessionTracker.currentDuration))
                        .font(.system(size: 52, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Session in progress")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.2))
                }

                // LUFS meter placeholder
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Level")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.2))
                            .textCase(.uppercase)
                            .kerning(1.5)
                        Spacer()
                        Text("– LUFS")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                }
                .padding(.horizontal, 40)

                Button {
                    // Phase 1: SingleExport will hook here
                    if engine.isPlaying { engine.togglePlayback() }
                    if let session = engine.lastCompletedSession {
                        modelContext.insert(session)
                        log.log(.info, category: .system, "Session saved: \(session.durationSeconds)s")
                    }
                } label: {
                    Text("Finalize & Export")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finalize and export session")

            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white.opacity(0.1))
                Text("No active session")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.2))
            }

            Spacer()
        }
    }

    // MARK: - Compact landscape sub-views

    private var bioCompactRow: some View {
        HStack(spacing: 20) {
            bioMetricSmall(value: "\(Int(engine.state.heartRate))", unit: "BPM")
            bioMetricSmall(value: String(format: "%.0f%%", engine.state.coherence * 100), unit: "Coh")
            bioMetricSmall(value: String(format: "%.0f", engine.state.hrv * 100), unit: "HRV")
            Spacer()
            Button { showCameraPulse = true } label: {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Measure pulse via camera")
        }
    }

    private var streamStatusRow: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.white.opacity(0.07)).frame(width: 6, height: 6)
            Text("Stream offline")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.14))
            Spacer()
        }
    }

    private var signalStatusRow: some View {
        let source = engine.bioSourceManager.primarySource
        let conf = engine.bioSourceManager.confidence
        let coherence = engine.state.coherence

        let color: Color = {
            guard source != .fallback else { return .white.opacity(0.15) }
            if coherence > 0.6 { return .green }
            if coherence > 0.3 { return .yellow }
            return .orange
        }()

        let label: String = {
            guard source != .fallback else { return "Environment Mode" }
            if coherence > 0.6 { return "Flow" }
            if coherence > 0.3 { return "Settling" }
            return "Searching"
        }()

        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color.opacity(0.8))
            if source != .fallback {
                Text("·  \(source.displayName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.2))
            }
            Spacer()
            // Confidence dots
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(conf > Float(i) * 0.25 ? 0.28 : 0.05))
                        .frame(width: 12, height: 3)
                }
            }
        }
    }

    // MARK: - Coherence Mini (perform header)

    private var coherenceMini: some View {
        let coherence = engine.state.coherence
        let hr = engine.state.heartRate
        let hasBio = engine.bioSourceManager.primarySource != .fallback

        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.05 + coherence * 0.15), lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                if hasBio {
                    Text("\(Int(hr))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(hasBio ? "BPM" : engine.state.circadianPhase.rawValue.capitalized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.18))
                    .textCase(.uppercase)
                    .kerning(1)
                Text(String(format: "%.0f%% coh", coherence * 100))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .accessibilityLabel(hasBio ? "Heart rate \(Int(hr)) BPM, coherence \(Int(coherence * 100))%" : "Environment mode")
    }

    // MARK: - Coherence Ring (reused from SoundscapeView)

    private var coherenceRing: some View {
        let coherence = engine.state.coherence
        let hr = engine.state.heartRate
        let hasBio = engine.bioSourceManager.primarySource != .fallback

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.03 + coherence * 0.12), lineWidth: 1)
                .frame(width: 200, height: 200)
            Circle()
                .fill(Color.white.opacity(0.02 + coherence * 0.04))
                .frame(width: 140, height: 140)

            if hasBio {
                VStack(spacing: 4) {
                    Text("\(Int(hr))")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                        .textCase(.uppercase)
                        .kerning(2)
                }
                .accessibilityLabel("Heart rate \(Int(hr)) BPM")
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(engine.state.circadianPhase.rawValue.capitalized)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .kerning(1.5)
                }
                .accessibilityLabel("Environment mode \(engine.state.circadianPhase.rawValue)")
            }
        }
    }

    // MARK: - Pause/Resume

    private var pauseResumeButton: some View {
        Button {
            engine.togglePlayback()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 56, height: 56)
                if engine.isPlaying {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35)).frame(width: 3, height: 16)
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35)).frame(width: 3, height: 16)
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.4))
                        .offset(x: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isPlaying ? "Pause" : "Resume")
    }

    // MARK: - Reusable Atoms

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.25))
            .textCase(.uppercase)
            .kerning(1.5)
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private func voiceSlider(label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: 0...0.6).tint(.white.opacity(0.2))
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func bioMetricLarge(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
                .textCase(.uppercase)
                .kerning(1.5)
        }
    }

    private func bioMetricSmall(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.18))
                .textCase(.uppercase)
                .kerning(1)
        }
    }

    private func formatTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

}

// MARK: - StudioMode

enum StudioMode: String, CaseIterable {
    case perform, mix, stream, export

    var label: String {
        switch self {
        case .perform: return "Perform"
        case .mix:     return "Mix"
        case .stream:  return "Stream"
        case .export:  return "Export"
        }
    }

    var icon: String {
        switch self {
        case .perform: return "music.quarternote.3"
        case .mix:     return "slider.horizontal.3"
        case .stream:  return "dot.radiowaves.left.and.right"
        case .export:  return "square.and.arrow.up"
        }
    }
}
#endif
