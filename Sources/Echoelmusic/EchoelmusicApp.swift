#if canImport(SwiftUI)
import SwiftUI
import SwiftData

/// Echoelmusic — Bio-Reactive Soundscape Generator
/// Your body, weather, and time of day create evolving ambient soundscapes.
@main
struct EchoelmusicApp: App {

    @State private var audioEngine: AudioEngine
    @State private var microphoneManager: MicrophoneManager
    @State private var soundscapeEngine: SoundscapeEngine
    @State private var store: EchoelStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let mic = MicrophoneManager()
        let audio = AudioEngine(microphoneManager: mic)

        _microphoneManager = State(wrappedValue: mic)
        _audioEngine = State(wrappedValue: audio)
        _soundscapeEngine = State(wrappedValue: SoundscapeEngine())
        _store = State(wrappedValue: EchoelStore())

        _ = MemoryPressureHandler.shared
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                mainContent
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        SoundscapeView()
        .environment(audioEngine)
        .environment(EchoelBioEngine.shared)
        .environment(soundscapeEngine)
        .environment(store)
        .modelContainer(for: SoundscapeSession.self)
        .task {
            log.log(.info, category: .system, "STARTUP [1/4] Starting audio engine...")
            audioEngine.start()

            log.log(.info, category: .system, "STARTUP [2/4] Starting bio streaming...")
            soundscapeEngine.bioSourceManager.startStreaming()

            log.log(.info, category: .system, "STARTUP [3/4] Connecting soundscape engine...")
            soundscapeEngine.connect(audio: audioEngine, bio: EchoelBioEngine.shared)

            log.log(.info, category: .system, "STARTUP [4/4] Loading store products...")
            await store.loadProducts()
            await store.updateSubscriptionStatus()

            log.log(.info, category: .system, "STARTUP COMPLETE — Soundscape ready")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                if oldPhase == .background {
                    audioEngine.start()
                    soundscapeEngine.bioSourceManager.startStreaming()
                    log.log(.info, category: .system, "App active — audio + bio resumed")
                }
            case .background:
                log.log(.info, category: .system, "App backgrounded — audio continues")
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
#endif
