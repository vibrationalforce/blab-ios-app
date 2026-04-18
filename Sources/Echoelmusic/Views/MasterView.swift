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
                // Pre-roll adds 30s — show total captured duration including pre-roll
                let totalSecs = audioEngine.retroCapture.recordingSeconds + (rec ? 30 : 0)
                HStack(spacing: 6) {
                    Circle()
                        .fill(rec ? Color.red : Color.white.opacity(0.15))
                        .frame(width: 7, height: 7)
                    Text(rec ? formatTimer(totalSecs) : "REC")
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

    // MARK: - Stream

    private var streamContent: some View {
        let stream = audioEngine.liveStream
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                streamStatusHeader(stream: stream)
                    .padding(.top, 20)

                // Live camera preview
                if stream.state.isLive && stream.cameraEnabled {
                    #if canImport(UIKit)
                    CameraPreviewView(session: stream.captureSession)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.35), lineWidth: 1)
                        )
                    #endif
                }

                separator

                // Done state — show ShareLink to upload
                if let url = stream.state.doneURL {
                    streamDoneView(url: url, stream: stream)
                } else {
                    // Destination picker
                    sectionHeader("Upload To")
                        .padding(.top, 4)
                    VStack(spacing: 6) {
                        ForEach(LiveStreamEngine.destinations) { dest in
                            Button { stream.selectedDestination = dest } label: {
                                HStack {
                                    Text(dest.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(stream.selectedDestination == dest ? 0.85 : 0.35))
                                    Spacer()
                                    if stream.selectedDestination == dest {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(stream.selectedDestination == dest ? 0.2 : 0.07), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Camera toggle
                    HStack {
                        Text("Front Camera")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { stream.cameraEnabled },
                            set: { stream.cameraEnabled = $0 }
                        ))
                        .tint(.white.opacity(0.4))
                        .labelsHidden()
                    }
                    .padding(.top, 4)

                    separator

                    streamGoLiveButton(stream: stream)
                        .padding(.vertical, 8)

                    Text("Records video + audio locally. Upload via ShareLink when done.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.18))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private func streamDoneView(url: URL, stream: LiveStreamEngine) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.green.opacity(0.6))

            VStack(spacing: 4) {
                Text("Recording ready")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(url.lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineLimit(1)
            }

            ShareLink(item: url) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share / Upload to \(stream.selectedDestination.name)")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button { stream.resetAfterDone() } label: {
                Text("Record Again")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func streamStatusHeader(stream: LiveStreamEngine) -> some View {
        HStack(spacing: 10) {
            switch stream.state {
            case .idle:
                Circle().fill(Color.white.opacity(0.1)).frame(width: 8, height: 8)
                Text("Ready to record")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
            case .connecting:
                ProgressView().scaleEffect(0.7).tint(.white.opacity(0.4))
                Text("Starting camera…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            case .live(let duration):
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("REC  \(formatTimer(duration))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.9))
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green.opacity(0.6))
                Text("Saved")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green.opacity(0.6))
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func streamGoLiveButton(stream: LiveStreamEngine) -> some View {
        let isLive = stream.state.isLive
        let isConnecting = stream.state == .connecting
        return Button {
            if isLive || isConnecting {
                stream.stopStream()
            } else {
                stream.startStream()
            }
        } label: {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView().scaleEffect(0.7).tint(.black)
                } else {
                    Circle()
                        .fill(isLive ? Color.red : Color.white.opacity(0.7))
                        .frame(width: 7, height: 7)
                }
                Text(isLive ? "Stop Recording" : isConnecting ? "Starting…" : "Start Recording")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isLive ? Color.red.opacity(0.85) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .accessibilityLabel(isLive ? "Stop recording" : "Start recording for stream")
    }

    // MARK: - Export

    private var exportContent: some View {
        let exporter = audioEngine.singleExport
        let rec = audioEngine.retroCapture

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Recording status header
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Recording")
                        .padding(.top, 20)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(rec.isRecording ? Color.red : Color.white.opacity(0.12))
                            .frame(width: 7, height: 7)
                        if rec.isRecording {
                            Text(formatTimer(rec.recordingSeconds))
                                .font(.system(size: 20, weight: .light, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("No active recording")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        Spacer()
                        // LUFS from master chain
                        let lufs = audioEngine.autoMixChain.lufsReading
                        Text(lufs > -59 ? String(format: "%.1f LUFS", lufs) : "– LUFS")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lufsColor(lufs))
                    }
                }

                // Waveform preview — live ring buffer visualization
                WaveformView(samples: rec.waveformSamples, isRecording: rec.isRecording)
                    .frame(height: 48)

                separator

                // Format + target
                sectionHeader("Export Format")
                HStack(spacing: 6) {
                    ForEach(SingleExport.OutputFormat.allCases) { fmt in
                        Button { exporter.outputFormat = fmt } label: {
                            Text(fmt.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(exporter.outputFormat == fmt ? .white : .white.opacity(0.3))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(exporter.outputFormat == fmt ? 0.2 : 0.07), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionHeader("Target Level")
                HStack(spacing: 6) {
                    ForEach([(-14, "Stream"), (-9, "Club"), (-23, "Broadcast")], id: \.0) { val, label in
                        Button { exporter.targetLUFS = Float(val) } label: {
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(exporter.targetLUFS == Float(val) ? .white : .white.opacity(0.3))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(exporter.targetLUFS == Float(val) ? 0.2 : 0.07), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                separator

                // Export progress / done state
                exportStateView(exporter: exporter)

                // Export trigger
                exportActionButton(exporter: exporter, rec: rec)
                    .padding(.vertical, 8)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func exportStateView(exporter: SingleExport) -> some View {
        switch exporter.exportState {
        case .idle:
            EmptyView()
        case .analyzing:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7).tint(.white.opacity(0.4))
                Text("Analyzing…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            }
        case .exporting(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Exporting")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)
                        .kerning(1)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    }
                }
                .frame(height: 3)
            }
        case .done(let url):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green.opacity(0.7))
                Text(url.lastPathComponent)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                Spacer()
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                }
            }
        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineLimit(2)
            }
        }
    }

    private func exportActionButton(exporter: SingleExport, rec: RetroCapture) -> some View {
        let isDone = exporter.exportState.isDone
        let isBusy: Bool = {
            switch exporter.exportState {
            case .analyzing, .exporting: return true
            default: return false
            }
        }()

        return Button {
            if isDone {
                exporter.reset()
            } else if let url = rec.lastURL {
                Task { await exporter.export(sourceURL: url) }
            } else {
                // Stop recording first, then export
                rec.stopRecording { url in
                    guard let url else { return }
                    Task { await exporter.export(sourceURL: url) }
                }
            }
        } label: {
            Text(isDone ? "Export Again" : isBusy ? "Processing…" : "Master & Export")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isBusy ? Color.white.opacity(0.4) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isBusy || (!isDone && rec.lastURL == nil && !rec.isRecording))
        .accessibilityLabel(isDone ? "Export again" : "Master and export recording")
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
        let s = audioEngine.liveStream.state
        let isLive = s.isLive
        let isDone = s.doneURL != nil
        return HStack(spacing: 8) {
            Circle()
                .fill(isLive ? Color.red : isDone ? Color.green.opacity(0.6) : Color.white.opacity(0.07))
                .frame(width: 6, height: 6)
            Text(isLive ? "REC" : isDone ? "Saved" : "Stream ready")
                .font(.system(size: 11, weight: isLive ? .semibold : .regular))
                .foregroundStyle(isLive ? .red.opacity(0.9) : isDone ? .green.opacity(0.6) : .white.opacity(0.14))
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

// MARK: - WaveformView

/// Draws a symmetric RMS waveform from 200 pre-downsampled bins.
/// Each bin is a centered vertical bar; height = RMS amplitude 0–1.
private struct WaveformView: View {

    let samples: [Float]
    let isRecording: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = samples.count
            let barW = w / CGFloat(count)

            Canvas { ctx, size in
                let barColor = isRecording
                    ? Color.red.opacity(0.55)
                    : Color.white.opacity(0.18)

                for (i, sample) in samples.enumerated() {
                    let amp   = CGFloat(min(sample * 4, 1.0))  // boost low-level audio visually
                    let barH  = max(amp * h, 1)
                    let x     = CGFloat(i) * barW + barW * 0.2
                    let y     = (h - barH) / 2
                    let rect  = CGRect(x: x, y: y, width: barW * 0.6, height: barH)
                    let path  = Path(roundedRect: rect, cornerRadius: barW * 0.2)
                    ctx.fill(path, with: .color(barColor))
                }
            }
            .frame(width: w, height: h)
        }
        .animation(.linear(duration: 0.5), value: samples.map { $0 })
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
