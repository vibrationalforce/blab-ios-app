#if canImport(SwiftUI)
import SwiftUI

/// Echoelmusic — Make Beats. Record Video. Stream Live.
@main
struct EchoelmusicApp: App {

    @State private var audioEngine: AudioEngine
    @State private var microphoneManager: MicrophoneManager
    @State private var store: EchoelStore
    @State private var beatPlayer: BeatPlayer
    @State private var bus: EngineBus
    #if canImport(HealthKit)
    @State private var healthBio: HealthKitBioPublisher
    #endif
    #if canImport(CoreBluetooth)
    @State private var polarH10: PolarH10BioPublisher
    #endif
    @State private var bioVoice: BioReactiveSynthVoice
    @State private var bioEvents: BioEventPublisher
    #if canImport(CoreMIDI)
    @State private var midiInput: MIDIInput
    @State private var midiPub: MIDIBusPublisher
    #endif
    #if canImport(Network)
    @State private var osc: OSCSender
    #endif
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
        _bus = State(wrappedValue: EngineBus())
        #if canImport(HealthKit)
        _healthBio = State(wrappedValue: HealthKitBioPublisher())
        #endif
        #if canImport(CoreBluetooth)
        _polarH10 = State(wrappedValue: PolarH10BioPublisher())
        #endif
        _bioVoice = State(wrappedValue: BioReactiveSynthVoice())
        _bioEvents = State(wrappedValue: BioEventPublisher())
        #if canImport(CoreMIDI)
        let midi = MIDIInput()
        _midiInput = State(wrappedValue: midi)
        _midiPub = State(wrappedValue: MIDIBusPublisher(midi: midi))
        #endif
        #if canImport(Network)
        _osc = State(wrappedValue: OSCSender())
        #endif

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
            .environment(bus)
            .environment(bioVoice)
            .environment(bioEvents)
            #if canImport(CoreMIDI)
            .environment(midiPub)
            #endif
            #if canImport(Network)
            .environment(osc)
            #endif
            .task {
                // Configure audio topology BEFORE starting the engine.
                // Hot-attaching source nodes to a running AVAudioEngine
                // causes pause/restart cycles that have crashed at launch
                // (build 1363). Attaching first keeps masterEngine stopped
                // until all 8 voices are wired, then a single .start().
                log.log(.info, category: .system, "STARTUP [1/4] Loading drum samples...")
                beatPlayer.loadDefaultSamples()

                log.log(.info, category: .system, "STARTUP [2/4] Attaching beat voices to audio engine...")
                beatPlayer.attach(to: audioEngine)
                bioVoice.attach(to: audioEngine)

                log.log(.info, category: .system, "STARTUP [3/4] Starting audio engine...")
                audioEngine.start()

                log.log(.info, category: .system, "STARTUP [4/4] Loading store products...")
                await store.loadProducts()
                await store.updateSubscriptionStatus()

                log.log(.info, category: .system, "STARTUP COMPLETE — Echoel Studio ready")

                #if canImport(HealthKit)
                await healthBio.start(publishing: bus)
                #endif
                #if canImport(CoreBluetooth)
                polarH10.start(publishing: bus)
                #endif
                bioVoice.start(subscribing: bus)
                bioEvents.start(on: bus)
                #if canImport(CoreMIDI)
                midiPub.start(publishing: bus)
                #endif
                #if canImport(Network)
                osc.start(subscribing: bus)
                #endif
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
