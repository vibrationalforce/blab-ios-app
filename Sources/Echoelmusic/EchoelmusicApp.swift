#if canImport(SwiftUI)
import SwiftUI

/// Echoelmusic — Make Beats. Record Video. Stream Live.
@main
struct EchoelmusicApp: App {

    @State private var audioEngine: AudioEngine
    @State private var microphoneManager: MicrophoneManager
    @State private var store: EchoelStore
    @State private var beatPlayer: BeatPlayer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var shouldAutoPlay = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let mic = MicrophoneManager()
        let audio = AudioEngine(microphoneManager: mic)

        _microphoneManager = State(wrappedValue: mic)
        _audioEngine = State(wrappedValue: audio)
        _store = State(wrappedValue: EchoelStore())
        _beatPlayer = State(wrappedValue: BeatPlayer())

        _ = MemoryPressureHandler.shared
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                mainContent
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding, shouldAutoPlay: $shouldAutoPlay)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        StudioRoot()
            .environment(audioEngine)
            .environment(store)
            .environment(beatPlayer)
            .task {
                log.log(.info, category: .system, "STARTUP [1/3] Starting audio engine...")
                audioEngine.start()

                log.log(.info, category: .system, "STARTUP [2/3] Loading drum samples + attaching voices...")
                beatPlayer.loadDefaultSamples()
                beatPlayer.attach(to: audioEngine)

                log.log(.info, category: .system, "STARTUP [3/3] Loading store products...")
                await store.loadProducts()
                await store.updateSubscriptionStatus()

                log.log(.info, category: .system, "STARTUP COMPLETE — Echoel Studio ready")
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    if oldPhase == .background {
                        audioEngine.start()
                        log.log(.info, category: .system, "App active — audio resumed")
                    }
                case .background:
                    log.log(.info, category: .system, "App backgrounded")
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
    }
}
#endif
