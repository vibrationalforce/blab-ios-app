#if canImport(SwiftUI)
import SwiftUI

/// Primary screen: fullscreen bio-reactive Metal visual + one-tap capture.
struct MomentCaptureView: View {

    @Environment(AudioEngine.self) private var audioEngine
    @Environment(SoundscapeEngine.self) private var soundscape
    @Environment(EchoelStore.self) private var store

    let clipEngine: ClipEngine

    @State private var renderer: BioVisualRenderer?
    @State private var capture = MomentCapture()
    @State private var activeKernel: VisualKernel = .cymatics
    @State private var showStudio = false
    @State private var shareItem: URL?

    private var heartRate: Int { Int(soundscape.state.heartRate.rounded()) }
    private var coherence: Double { soundscape.state.coherence }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Fullscreen Metal visual
            #if canImport(Metal) && canImport(MetalKit)
            if let r = renderer {
                MetalBioView(renderer: r)
                    .ignoresSafeArea()
            } else {
                bioFallbackBackground
            }
            #else
            bioFallbackBackground
            #endif

            // Overlay
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { setupRenderer() }
        .onChange(of: activeKernel) { _, k in renderer?.setKernel(k) }
        .sheet(isPresented: $showStudio) {
            MasterView(clipEngine: clipEngine)
                .environment(audioEngine)
                .environment(soundscape)
                .environment(store)
        }
        .sheet(item: $shareItem) { url in
            ShareSheet(url: url)
        }
    }

    // MARK: - Top bar: HR + coherence + settings

    private var topBar: some View {
        HStack {
            bioReadout
            Spacer()
            settingsButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var bioReadout: some View {
        HStack(spacing: 10) {
            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(coherenceColor)
                Text("\(heartRate)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            // Coherence dots
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(Double(i) < coherence * 5 ? coherenceColor : Color.white.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var settingsButton: some View {
        Button {
            showStudio = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Studio controls")
    }

    // MARK: - Bottom: kernel picker + capture button

    private var bottomControls: some View {
        VStack(spacing: 20) {
            kernelPicker
            captureButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
    }

    private var kernelPicker: some View {
        HStack(spacing: 12) {
            ForEach(VisualKernel.allCases, id: \.self) { kernel in
                Button {
                    activeKernel = kernel
                } label: {
                    Text(kernel.shortLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(activeKernel == kernel ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeKernel == kernel ? .white : Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Visual: \(kernel.shortLabel)")
            }
        }
    }

    private var captureButton: some View {
        Group {
            switch capture.state {
            case .idle:
                Button {
                    capture.connect(retroCapture: audioEngine.retroCapture, singleExport: audioEngine.singleExport)
                    capture.startCapture()
                } label: {
                    captureButtonLabel(isRecording: false)
                }
                .accessibilityLabel("Start recording")

            case .recording(let elapsed):
                Button { capture.stopCapture() } label: {
                    captureButtonLabel(isRecording: true, elapsed: elapsed)
                }
                .accessibilityLabel("Stop recording — \(Int(elapsed)) seconds")

            case .processing:
                captureButtonLabel(isProcessing: true)

            case .done(let url):
                HStack(spacing: 12) {
                    Button {
                        shareItem = url
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Share recording")

                    Button { capture.reset() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Discard recording")
                }

            case .error(let msg):
                VStack(spacing: 8) {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                    Button("Try again") { capture.reset() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func captureButtonLabel(isRecording: Bool = false, elapsed: TimeInterval = 0, isProcessing: Bool = false) -> some View {
        HStack(spacing: 10) {
            if isProcessing {
                ProgressView()
                    .tint(.black)
                    .scaleEffect(0.8)
                Text("Mastering…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
            } else if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text(elapsedLabel(elapsed))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black)
            } else {
                Circle()
                    .fill(.black.opacity(0.6))
                    .frame(width: 10, height: 10)
                Text("Capture")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(isRecording ? Color.white.opacity(0.9) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Fallback background (no Metal)

    private var bioFallbackBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.12), Color(red: 0.02, green: 0.06, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(coherenceColor.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
        }
    }

    // MARK: - Helpers

    private var coherenceColor: Color {
        let c = coherence
        if c > 0.7 { return Color(red: 0.3, green: 0.8, blue: 0.7) }
        if c > 0.4 { return Color(red: 0.8, green: 0.7, blue: 0.3) }
        return Color(red: 0.8, green: 0.4, blue: 0.3)
    }

    private func elapsedLabel(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func setupRenderer() {
        #if canImport(Metal) && canImport(MetalKit)
        renderer = BioVisualRenderer(soundscape: soundscape)
        renderer?.setKernel(activeKernel)
        #endif
    }
}

// MARK: - Kernel label

extension VisualKernel {
    var shortLabel: String {
        switch self {
        case .cymatics:  return "Wave"
        case .mandala:   return "Mandala"
        case .particles: return "Particles"
        case .waveform:  return "Form"
        case .spectral:  return "Spectral"
        }
    }
}

// MARK: - URL Identifiable

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - ShareSheet

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
#endif
