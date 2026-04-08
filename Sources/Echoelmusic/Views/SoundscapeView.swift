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
    @State private var selectedTab: ControlTab = .mix

    enum ControlTab: String, CaseIterable {
        case mix = "Mix"
        case sound = "Sound"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Session history")

                    Spacer()

                    // Session timer
                    if engine.sessionTracker.isActive {
                        Text(formatTimer(engine.sessionTracker.currentDuration))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.25))
                            .monospacedDigit()
                    }

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
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

                // Coherence ring — subtle visual feedback
                coherenceRing

                Spacer()

                // Sound controls — Mix + Sound Design tabs
                if engine.isPlaying {
                    controlTabs
                        .padding(.bottom, 12)
                }

                // Bio metrics
                bioDisplay

                // Biofeedback signal status LED
                signalStatusLED
                    .padding(.top, 16)

                // Play/Pause
                playButton
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // Source indicator
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

        return ZStack {
            // Outer ring — coherence glow
            Circle()
                .stroke(
                    Color.white.opacity(0.03 + coherence * 0.12),
                    lineWidth: 1
                )
                .frame(width: 200, height: 200)

            // Inner pulse — heart rate driven (subtle glow)
            Circle()
                .fill(Color.white.opacity(0.02 + coherence * 0.04))
                .frame(width: 140, height: 140)

            // Heart rate number (primary)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Heart rate \(Int(hr)) BPM, Coherence \(Int(coherence * 100)) percent")
        }
    }

    // MARK: - Signal Status LED

    private var signalStatusLED: some View {
        let source = engine.bioSourceManager.primarySource
        let conf = engine.bioSourceManager.confidence

        let color: Color = {
            if source == .fallback { return .white.opacity(0.15) }
            if conf > 0.7 { return .green }
            if conf > 0.4 { return .yellow }
            return .red
        }()

        let label: String = {
            if source == .fallback { return "Environment Mode" }
            if conf > 0.7 { return "Bio Signal Stable" }
            if conf > 0.4 { return "Bio Signal Weak" }
            return "Searching..."
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // LED dot
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: source != .fallback ? 4 : 0)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color.opacity(0.7))

                if source != .fallback {
                    Text("via \(source.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            // When in fallback mode, show what IS driving the sound
            if source == .fallback {
                #if canImport(CoreMotion)
                let activity = engine.state.activityState
                Text("Time + Weather + Motion (\(activity))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.15))
                #else
                Text("Time + Weather")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.15))
                #endif
            }
        }
    }

    // MARK: - Control Tabs (Mix + Sound Design)

    private var controlTabs: some View {
        VStack(spacing: 10) {
            // Tab picker
            HStack(spacing: 0) {
                ForEach(ControlTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(selectedTab == tab ? 0.5 : 0.15))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03)))
            .padding(.horizontal, 16)

            // Content
            switch selectedTab {
            case .mix:
                harmonySliders
            case .sound:
                soundDesignPanel
            }
        }
    }

    private var harmonySliders: some View {
        @Bindable var eng = engine
        return VStack(spacing: 8) {
            harmonySlider(label: "Root", value: $eng.mixRoot)
            harmonySlider(label: "Third", value: $eng.mixFifth)
            harmonySlider(label: "Fifth", value: $eng.mixOctave)
            harmonySlider(label: "Octave", value: $eng.mixHigh)
        }
        .padding(.horizontal, 16)
    }

    private var soundDesignPanel: some View {
        VStack(spacing: 8) {
            compactSlider("Filter", value: filterCutoffBinding, range: 200...12000, log: true)
            compactSlider("Warmth", value: harmonicityBinding, range: 0.3...1.0)
            compactSlider("Space", value: reverbMixBinding, range: 0...0.8)
            compactSlider("Texture", value: noiseLevelBinding, range: 0...0.2)
            compactSlider("Attack", value: attackBinding, range: 0.1...3.0)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Sound Design Bindings (write to all 4 voices)

    private var filterCutoffBinding: Binding<Float> {
        Binding(
            get: { engine.voiceRoot.filterCutoff },
            set: { v in for voice in engine.allVoices { voice.filterCutoff = v } }
        )
    }

    private var harmonicityBinding: Binding<Float> {
        Binding(
            get: { engine.voiceRoot.harmonicity },
            set: { v in for voice in engine.allVoices { voice.harmonicity = v } }
        )
    }

    private var reverbMixBinding: Binding<Float> {
        Binding(
            get: { engine.voiceRoot.reverbMix },
            set: { v in for voice in engine.allVoices { voice.reverbMix = v } }
        )
    }

    private var noiseLevelBinding: Binding<Float> {
        Binding(
            get: { engine.voiceRoot.noiseLevel },
            set: { v in for voice in engine.allVoices { voice.noiseLevel = v } }
        )
    }

    private var attackBinding: Binding<Float> {
        Binding(
            get: { engine.voiceRoot.attack },
            set: { v in for voice in engine.allVoices { voice.attack = v } }
        )
    }

    // MARK: - Slider Components

    private func harmonySlider(label: String, value: Binding<Float>) -> some View {
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

    @ViewBuilder
    private func compactSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, log: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 50, alignment: .leading)

            if log {
                // Logarithmic slider for frequency
                let logMin = log2(max(1, range.lowerBound))
                let logMax = log2(range.upperBound)
                let logBinding = Binding<Float>(
                    get: { log2(max(1, value.wrappedValue)) },
                    set: { value.wrappedValue = powf(2, $0) }
                )
                Slider(value: logBinding, in: logMin...logMax)
                    .tint(.white.opacity(0.2))
            } else {
                Slider(value: value, in: range)
                    .tint(.white.opacity(0.2))
            }

            Text(log ? String(format: "%.0f", value.wrappedValue) : String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 36, alignment: .trailing)
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

    // MARK: - Play Button

    private var playButton: some View {
        Button {
            engine.togglePlayback()
            // Auto-save session when stopping
            if !engine.isPlaying, let session = engine.lastCompletedSession {
                modelContext.insert(session)
                log.log(.info, category: .system, "Session saved: \(session.durationSeconds)s, avg coherence \(String(format: "%.0f%%", session.avgCoherence * 100))")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(engine.isPlaying ? 0.08 : 0.05))
                    .frame(width: 72, height: 72)

                if engine.isPlaying {
                    // Pause icon
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 3, height: 20)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 3, height: 20)
                    }
                } else {
                    // Play icon (triangle)
                    Image(systemName: "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(x: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isPlaying ? "Pause soundscape" : "Play soundscape")
    }

    // MARK: - Source Label

    private var sourceLabel: some View {
        let source = engine.state.source
        let weather = engine.state.weatherCondition

        return VStack(spacing: 4) {
            Text("\(source.displayName) · \(weather.rawValue.capitalized)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.15))
                .kerning(1)

            Text(engine.audioOutputName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.1))
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
        case .fallback: return "Simulated"
        }
    }
}
#endif
