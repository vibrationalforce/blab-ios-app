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
    /// Polyphonic note instrument driven directly by the piano roll.
    @State private var polyVoice: PolySynthVoice
    @State private var bioEvents: BioEventPublisher
    @State private var bioFeedback: BioFeedbackPublisher
    #if canImport(AVFoundation)
    // Opt-in camera rPPG bio source — started explicitly from WellView, never auto-run.
    @State private var cameraRPPG = CameraRPPGBioPublisher()
    #endif
    #if canImport(CoreMIDI)
    @State private var midiInput: MIDIInput
    @State private var midiPub: MIDIBusPublisher
    #endif
    #if canImport(Network)
    @State private var osc: OSCSender
    /// Opt-in ADM-OSC bridge (immersive object positioning). Off by default;
    /// started from the Sync tab. Not auto-run — most users have no renderer.
    @State private var admOSC = ADMOSCSender()
    /// Opt-in Art-Net light output (EchoelLux). Off by default; started from
    /// the Sync tab. Not auto-run — most users have no lighting rig.
    @State private var artNet = ArtNetSender()
    @State private var sacn = SACNSender()
    #endif
    @State private var modulationEngine: ModulationEngine
    /// Library of user + factory synth sounds for the patch editor.
    @State private var patchStore: PatchStore
    /// Shared melodic piano-roll pattern — the body-generated melody.
    @State private var pianoRoll: PianoRollModel
    #if canImport(CoreHaptics)
    /// Eyes-free haptic feedback (transport pulse). Off until armed.
    @State private var haptics = HapticController()
    #endif
    /// Artist · key · Kammerton — the persisted identity stamped on session names
    /// and export filenames.
    @State private var sessionContext = SessionContext()
    /// Loop → .wav export (live-capture) and the saved-projects library — the one
    /// window's output + persistence.
    @State private var loopExporter = LoopExporter()
    @State private var projectStore = ProjectStore()
    /// Clearly-labeled "Demo" bio source so every user hears the instrument
    /// without paired hardware (owned here now the single window is the root).
    @State private var demoSource = BioSimulator()
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
        _polyVoice = State(wrappedValue: PolySynthVoice())
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
        _patchStore = State(wrappedValue: PatchStore())
        _pianoRoll = State(wrappedValue: PianoRollModel())

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
        EchoelStudioView()
            .environment(audioEngine)
            .environment(store)
            .environment(beatPlayer)
            .environment(bus)
            .environment(bioVoice)
            .environment(polyVoice)
            .environment(bioEvents)
            #if canImport(CoreBluetooth)
            .environment(polarH10)
            #endif
            #if canImport(AVFoundation)
            .environment(cameraRPPG)
            #endif
            #if canImport(CoreMIDI)
            .environment(midiPub)
            #endif
            #if canImport(Network)
            .environment(osc)
            .environment(admOSC)
            .environment(artNet)
            .environment(sacn)
            #endif
            .environment(modulationEngine)
            .environment(patchStore)
            .environment(pianoRoll)
            #if canImport(CoreHaptics)
            .environment(haptics)
            #endif
            .environment(sessionContext)
            .environment(loopExporter)
            .environment(projectStore)
            .environment(demoSource)
            .task {
                // ── ESSENTIALS FIRST ─────────────────────────────────────────
                // The core instrument (audio + melodic synth + demo bio) must
                // start with NO awaiting dependency in front of it. Previously
                // `await store.loadProducts()` (StoreKit network) and
                // `await healthBio.start()` (HealthKit permission dialog) sat
                // AHEAD of the synth/demo start — if either stalled, the app
                // launched SILENT with a dead bio strip. They now run as
                // detached, best-effort tasks (bottom) so they can never block
                // the core path.
                //
                // Audio topology is built BEFORE the engine starts: hot-attaching
                // source nodes to a running AVAudioEngine has crashed at launch
                // (build 1363). Attach all voices first, then a single .start().
                log.log(.info, category: .system, "STARTUP [1/4] Audio session + master graph...")
                audioEngine.prepareGraph()
                beatPlayer.loadDefaultSamples()

                log.log(.info, category: .system, "STARTUP [2/4] Attaching voices...")
                beatPlayer.attach(to: audioEngine)
                bioVoice.attach(to: audioEngine)
                polyVoice.attach(to: audioEngine)

                log.log(.info, category: .system, "STARTUP [3/4] Starting audio engine...")
                audioEngine.start()

                // The melodic instrument + shared transport — the core sound path.
                // Melody plays via pattern.onTick → polyVoice; drums via onStep.
                bioVoice.start(subscribing: bus)
                polyVoice.start(subscribing: bus)
                pianoRoll.start(pattern: beatPlayer.pattern, voice: polyVoice)
                if let firstPatch = patchStore.patches.first { polyVoice.apply(firstPatch) }

                // Bio essentials. The demo source ALWAYS runs so the body readout
                // and "Generate from Body" are alive on any device; real sensors
                // override it (BioSimulator defers to non-fallback frames, and the
                // strip shows the real source whenever one is publishing).
                bioEvents.start(on: bus)
                bioFeedback.start(publishingFrom: bus)
                demoSource.start(publishing: bus)

                // Modulation routing: empty matrix → no behaviour change until the
                // user adds a route. Tempo handler scales [0..1] into [30..300] BPM.
                modulationEngine.register(ModDestinationKey.tempo) { [weak beatPlayer] value in
                    beatPlayer?.pattern.setTempo(30 + Double(value) * 270)
                }
                modulationEngine.start(subscribing: bus)
                // Non-essential I/O (BLE straps, external MIDI, OSC out) is NOT
                // auto-started — the essential instrument is camera/Demo bio →
                // generate → play → export. These remain available but opt-in,
                // so launch stays lean and triggers no extra permission prompts.

                log.log(.info, category: .system, "STARTUP [4/4] Core ready — instrument live")

                // ── BEST-EFFORT, NON-BLOCKING ────────────────────────────────
                // These await (HealthKit permission dialog, StoreKit network) and
                // run OFF the launch path so a hang here can never silence the app.
                #if canImport(HealthKit)
                Task { await healthBio.start(publishing: bus) }
                #endif
                Task {
                    await store.loadProducts()
                    await store.updateSubscriptionStatus()
                }
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
