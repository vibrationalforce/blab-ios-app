#if canImport(SwiftUI)
import SwiftUI
import SwiftData

/// Main view — bio-reactive soundscape with live biometric display.
/// Minimal, clean. Science-first: real numbers, no decoration.
struct SoundscapeView: View {

    @Environment(SoundscapeEngine.self) private var engine
    @Environment(EchoelBioEngine.self) private var bio
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showCameraPulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Session history")

                    Spacer()

                    // Session timer (always when active)
                    if engine.sessionTracker.isActive {
                        Text(formatTimer(engine.sessionTracker.currentDuration))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.25))
                            .monospacedDigit()
                    }

                    Spacer()

                    // Camera pulse — always accessible
                    Button { showCameraPulse = true } label: {
                        Image(systemName: engine.bioSourceManager.isCameraActive
                            ? "heart.fill" : "heart.text.clipboard")
                            .font(.system(size: 16))
                            .foregroundStyle(engine.bioSourceManager.isCameraActive
                                ? .red.opacity(0.6) : .white.opacity(0.2))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pulse measurement")

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 8)

                Spacer()

                // Coherence ring — always visible
                coherenceRing

                Spacer()

                // Voice mixer — always visible (audio auto-starts)
                voiceMixer
                    .padding(.bottom, 12)

                // Bio metrics — always visible
                bioDisplay

                // Bio source status — shows detected source and flow zone
                signalStatusLED
                    .padding(.top, 16)

                // Pause/Resume — only visible when manually paused
                pauseResumeButton
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // Source + output device
                sourceLabel
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(engine)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistoryView()
        }
        .sheet(isPresented: $showCameraPulse) {
            CameraMeasurementView()
                .environment(engine)
        }
    }

    // MARK: - Timer Format

    private func formatTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Coherence Ring

    private var coherenceRing: some View {
        let coherence = engine.state.coherence
        let hr = engine.state.heartRate
        let hasBioSignal = engine.bioSourceManager.primarySource != .fallback

        return ZStack {
            // Outer ring — coherence glow
            Circle()
                .stroke(
                    Color.white.opacity(0.03 + coherence * 0.12),
                    lineWidth: 1
                )
                .frame(width: 200, height: 200)

            // Inner pulse
            Circle()
                .fill(Color.white.opacity(0.02 + coherence * 0.04))
                .frame(width: 140, height: 140)

            // Content: real BPM when bio signal, circadian phase when environment
            if hasBioSignal {
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
                .accessibilityLabel("Environment mode, \(engine.state.circadianPhase.rawValue) phase")
            }
        }
    }

    // MARK: - Signal Status LED

    private var signalStatusLED: some View {
        let source = engine.bioSourceManager.primarySource
        let conf = engine.bioSourceManager.confidence
        let coherence = engine.state.coherence
        let isPlaying = engine.isPlaying

        // Flow zone: coherence-based when playing with bio signal, confidence-based otherwise
        let color: Color = {
            if source == .fallback { return .white.opacity(0.15) }
            if isPlaying {
                if coherence > 0.6 { return .green }
                if coherence > 0.3 { return .yellow }
                return .orange
            }
            if conf > 0.7 { return .green }
            if conf > 0.4 { return .yellow }
            return .red
        }()

        let label: String = {
            if source == .fallback { return "Environment Mode" }
            if isPlaying {
                if coherence > 0.6 { return "Flow" }
                if coherence > 0.3 { return "Settling" }
                return "Searching"
            }
            return "Ready"
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: source != .fallback ? 4 : 0)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color.opacity(0.8))

                if source != .fallback {
                    Text("·  \(source.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            if source == .fallback {
                #if canImport(CoreMotion)
                let activity = engine.state.activityState
                Text("Time · Weather · Motion (\(activity))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.15))
                #else
                Text("Time · Weather")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.15))
                #endif
            }
        }
    }

    // MARK: - Voice Mixer (4 sliders — simpler than Mix+Sound tabs)

    private var voiceMixer: some View {
        @Bindable var eng = engine
        return VStack(spacing: 8) {
            voiceSlider(label: "Root", value: $eng.mixRoot)
            voiceSlider(label: "Third", value: $eng.mixFifth)
            voiceSlider(label: "Fifth", value: $eng.mixOctave)
            voiceSlider(label: "Octave", value: $eng.mixHigh)
        }
        .padding(.horizontal, 16)
    }

    private func voiceSlider(label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 44, alignment: .leading)

            Slider(value: value, in: 0...0.6)
                .tint(.white.opacity(0.2))

            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Bio Display

    private var bioDisplay: some View {
        VStack(spacing: 16) {
            HStack(spacing: 32) {
                metricItem(
                    value: String(format: "%.0f", engine.state.hrv * 100),
                    label: "HRV"
                )
                metricItem(
                    value: String(format: "%.0f%%", engine.state.coherence * 100),
                    label: "Coherence"
                )
                metricItem(
                    value: engine.state.circadianPhase.rawValue.capitalized,
                    label: "Phase"
                )
            }

            // Confidence bar
            let conf = engine.bioSourceManager.confidence
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(conf > 0 ? 0.25 : 0.05))
                    .frame(width: 20, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(conf > 0.3 ? 0.25 : 0.05))
                    .frame(width: 20, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(conf > 0.6 ? 0.25 : 0.05))
                    .frame(width: 20, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(conf > 0.9 ? 0.25 : 0.05))
                    .frame(width: 20, height: 3)
            }
        }
    }

    private func metricItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
                .textCase(.uppercase)
                .kerning(1.5)
        }
    }

    // MARK: - Pause/Resume Button (audio auto-starts — this is pause control only)

    private var pauseResumeButton: some View {
        Button {
            engine.togglePlayback()
            // Save session when stopping
            if !engine.isPlaying, let session = engine.lastCompletedSession {
                modelContext.insert(session)
                log.log(.info, category: .system, "Session saved: \(session.durationSeconds)s")
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 56, height: 56)

                if engine.isPlaying {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 3, height: 16)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 3, height: 16)
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

    // MARK: - Source Label

    private var sourceLabel: some View {
        let source = engine.state.source
        let weather = engine.state.weatherCondition

        return VStack(spacing: 3) {
            Text("\(source.displayName)  ·  \(weather.rawValue.capitalized)  ·  \(engine.audioOutputName)")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.12))
        }
    }
}

// MARK: - BioDataSource Display Name

extension BioDataSource {
    var displayName: String {
        switch self {
        case .healthKit, .appleWatch: return "Apple Watch"
        case .chestStrap: return "Chest Strap"
        case .ouraRing: return "Oura Ring"
        case .camera: return "Camera"
        case .arkit: return "Face Tracking"
        case .microphone: return "Microphone"
        case .fallback: return "Environment"
        }
    }
}
#endif
