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
    @State private var bioFeedback: BioFeedbackPublisher
    #if canImport(CoreMIDI)
    @State private var midiInput: MIDIInput
    @State private var midiPub: MIDIBusPublisher
    #endif
    #if canImport(Network)
    @State private var osc: OSCSender
    #endif
    @State private var modulationEngine: ModulationEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var shouldAutoPlay = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        log.log(.info, category: .system, "APP INIT [start] — constructing engines (no audio I/O here)")
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
        _bioFeedback = State(wrappedValue: BioFeedbackPublisher())
        #if canImport(CoreMIDI)
        let midi = MIDIInput()
        _midiInput = State(wrappedValue: midi)
        _midiPub = State(wrappedValue: MIDIBusPublisher(midi: midi))
        #endif
        #if canImport(Network)
        _osc = State(wrappedValue: OSCSender())
        #endif
        _modulationEngine = State(wrappedValue: ModulationEngine())

        _ = MemoryPressureHandler.shared
        log.log(.info, category: .system, "APP INIT [done] — UI next (audio/bio start post-UI in .task)")
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
            .environment(modulationEngine)
            .task {
                // Configure audio topology BEFORE starting the engine.
                // Hot-attaching source nodes to a running AVAudioEngine
                // causes pause/restart cycles that have crashed at launch
                // (build 1363). Attaching first keeps masterEngine stopped
                // until all 8 voices are wired, then a single .start().
                //
                // All AVAudioSession/AVAudioEngine work runs HERE (post-UI), never
                // in App.init(): prepareGraph() builds the session + master graph.
                log.log(.info, category: .system, "STARTUP [1/5] Preparing audio session + master graph...")
                audioEngine.prepareGraph()

                log.log(.info, category: .system, "STARTUP [2/5] Loading drum samples...")
                beatPlayer.loadDefaultSamples()

                log.log(.info, category: .system, "STARTUP [3/5] Attaching beat voices to audio engine...")
                beatPlayer.attach(to: audioEngine)
                bioVoice.attach(to: audioEngine)

                log.log(.info, category: .system, "STARTUP [4/5] Starting audio engine...")
                audioEngine.start()

                log.log(.info, category: .system, "STARTUP [5/5] Loading store products...")
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
                // Mirror live vitals into the shared App Group (~1 Hz, off the
                // audio thread) so the Widget + Watch glance surfaces show real
                // data instead of "No session yet", and nudge WidgetKit.
                bioFeedback.start(publishingFrom: bus)
                #if canImport(CoreMIDI)
                midiPub.start(publishing: bus)
                #endif
                #if canImport(Network)
                osc.start(subscribing: bus)
                #endif

                // Modulation routing: wire real destinations, then go live.
                // Default matrix is empty → nothing is applied until the user
                // adds a route, so this is a zero-behavior-change wiring.
                // Tempo handler scales the [0..1] modulation into [30..300] BPM.
                modulationEngine.register(ModDestinationKey.tempo) { [weak beatPlayer] value in
                    beatPlayer?.pattern.setTempo(30 + Double(value) * 270)
                }
                modulationEngine.start(subscribing: bus)
                #if canImport(Network)
                // Stream every active modulation output out as /echoelmusic/mod/<key>.
                modulationEngine.outputTap = { [weak osc] destination, value in
                    osc?.sendModulation(key: destination.key, value: value)
                }
                #endif
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    if oldPhase == .background {
                        audioEngine.start()
                        bioFeedback.start(publishingFrom: bus)
                        log.log(.info, category: .system, "App active — audio resumed")
                    }
                case .background:
                    bioFeedback.stop()
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
