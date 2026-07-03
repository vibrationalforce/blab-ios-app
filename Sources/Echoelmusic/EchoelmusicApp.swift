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
    /// Opt-in "Works with Apple Health" write-back of Echoel's own HR / respiratory
    /// measurements (camera rPPG / BLE). Off by default.
    @State private var healthWriter = HealthKitWriter()
    #endif
    #if canImport(CoreBluetooth)
    @State private var polarH10: PolarH10BioPublisher
    #endif
    @State private var bioVoice: BioReactiveSynthVoice
    /// Polyphonic note instrument driven directly by the piano roll.
    @State private var polyVoice: PolySynthVoice
    /// Dedicated LEAD instrument voice (multitimbral): notes tagged `.lead` play
    /// through this with its own timbre so a take reads as separate instruments
    /// (bass · harmony · LEAD), not one surface. Small pool — the lead is few-note.
    @State private var leadVoice: PolySynthVoice
    @State private var subBass: SubBassVoice
    /// Steady click track — production/performance metronome (self-driving, silent
    /// until armed). Synced to the transport tempo by the studio view.
    @State private var metronome = MetronomeVoice()
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
    /// Live MIDI / MPE OUT — publishes the body-generated take as a virtual
    /// "Echoelmusic" source for a DAW to record. Off by default; armed from Sync.
    @State private var midiOut = MIDIOutput()
    #if canImport(MultipeerConnectivity)
    /// Live Colabo — nearby peer-to-peer session sharing. Off until the user goes
    /// live from Tools ▸ Live Colabo. No external dependency.
    @State private var colab = MultipeerSession()
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
    /// The single authoritative musical clock. PatternEngine relays its pulses
    /// here so position/tempo/play-state live in one observable place that the
    /// timeline, MIDI clock and Ableton Link can all ride.
    @State private var transport = Transport()
    /// Shared melodic piano-roll pattern — the body-generated melody.
    @State private var pianoRoll: PianoRollModel
    /// Session grid of launchable clips (drum pattern + melody snapshots).
    @State private var clipStore = ClipStore()
    /// Linear song timeline — an ordered chain of sections, each playing a clip.
    @State private var arrangementStore = ArrangementStore()
    /// Plays the arrangement back over the shared transport (fed via PianoRollModel).
    @State private var arrangementPlayer = ArrangementPlayer()
    /// Parameter automation (master level / tempo) played over the shared transport.
    @State private var automationPlayer = AutomationPlayer()
    /// Selectable recording inputs (mic / interface / Bluetooth) with latency notes.
    @State private var audioInputs = AudioInputManager()
    /// Universal signal router (patchbay): typed routes across all channels, persisted.
    @State private var signalRouter = SignalRouter()
    /// AUv3 host: discovers installed plugins and loads an instrument into the graph.
    @State private var auHost = AUv3Host()
    /// Broadcast (RTMP/SRT) publisher — the phone-native stream-out pillar.
    @State private var broadcast = BroadcastPublisher()
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

    // Resonance-breathing guide (the active half of the coherence loop).
    @State private var breathPacer = BreathPacer()
    // Records a meditation/coherence session (HR/HRV/coherence averages + peak) and
    // keeps the history — the dormant SessionRecorder, now wired for the Meditation pillar.
    @State private var sessionRecorder = SessionRecorder()
    // Battery/CPU/GPU resource conservation: reads thermal/power/battery + render FPS
    // and publishes one app-wide QualitySettings (visual FPS/detail, bio/OSC rates).
    @State private var resourceGovernor = ResourceGovernor()
    #if canImport(AVFoundation) && canImport(Metal)
    // Records the bio-reactive Metal visual to an .mp4 (the on-brand video source —
    // does NOT touch the rPPG camera). Fed by the fullscreen VJ MetalBioView.
    @State private var visualRecorder = VisualRecorder()
    #endif
    // Bio-reactive FX: the body (and LFOs) sculpt the melody voice's EchoelFX chain
    // live (coherence→reverb, breath→filter, HR→tremolo). Control-rate, off the
    // audio thread; idle until the user adds routes in the FX tool.
    @State private var fxModulator = FXBioModulator()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var shouldAutoPlay = false
    /// Set when the user taps "Continue to Echoel" in Safe Mode — renders the full
    /// app for the rest of this process even though this launch booted into Safe Mode.
    @State private var forceNormalMode = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        EchoelCrashLog.begin()   // diagnostics first: capture any crash from here on
        // Self-healing crash-loop guard: record this launch. If the previous one(s)
        // crashed before becoming healthy, `body` boots into Safe Mode instead of
        // re-rendering the view tree that crashed (no more black screen at launch).
        LaunchGuard.beginLaunch()
        if LaunchGuard.isSafeMode {
            EchoelCrashLog.breadcrumb("LaunchGuard: SAFE MODE (prior launch did not confirm healthy)")
        }
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
        // 12 voices: the composer emits up to ~12 notes/bar and the 2 s release
        // tails keep voices ringing across the bar, so 8 was oversubscribed →
        // constant voice-stealing caused clicks, instant pitch changes and tanh
        // level swings (device report: "Lautstärke-/Phasensprünge, Knacksen").
        _polyVoice = State(wrappedValue: PolySynthVoice(maxVoices: 12))
        // Lead voice: small pool (the melody is few-note) to keep the added CPU low.
        _leadVoice = State(wrappedValue: PolySynthVoice(maxVoices: 3))
        _subBass = State(wrappedValue: SubBassVoice())
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
        EchoelCrashLog.breadcrumb("init done: engines constructed, UI next")
    }

    var body: some Scene {
        WindowGroup {
            if LaunchGuard.isSafeMode && !forceNormalMode {
                // Self-healing recovery: the previous launch crashed before becoming
                // healthy. Show a legible recovery screen (never a black one). The
                // user can read/share the diagnostics and relaunch the full app.
                SafeModeView {
                    LaunchGuard.reset()
                    forceNormalMode = true
                }
                // Safe Mode is a ONE-SHOT speed bump, not a sticky state. Clear the
                // counter the moment the recovery screen appears: in Safe Mode the
                // studio's startup task never runs, so confirmHealthy() never fires —
                // without this, EVERY relaunch would re-enter Safe Mode until the user
                // happened to tap "Continue" (the lock-in a fast quit/relaunch caused).
                // Resetting here means the next launch tries the studio normally; if it
                // genuinely crashes again the counter simply rebuilds and Safe Mode
                // reappears after the next failure — protection without the trap.
                .onAppear {
                    EchoelCrashLog.breadcrumb("ui branch: SAFE MODE recovery screen (counter cleared)")
                    LaunchGuard.reset()
                }
            } else if hasCompletedOnboarding {
                mainContent
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding, shouldAutoPlay: $shouldAutoPlay)
                    .onAppear { EchoelCrashLog.breadcrumb("ui branch: ONBOARDING (not yet completed)") }
            }
        }
    }

    /// Bring outputs online/offline to match the Patchbay. An enabled route to an
    /// output's port starts its sender (idempotent — each `start` guards `isActive`);
    /// removing the last route stops it. MIDI Out is a simple enable flag. Called on
    /// every routing change and once at launch (for persisted routes).
    @MainActor
    private func applyRouting() {
        let g = signalRouter.graph
        #if canImport(Network)
        if g.hasEnabledRoute(toSink: "osc.out") { osc.start(subscribing: bus) } else { osc.stop() }
        if g.hasEnabledRoute(toSink: "adm.out") { admOSC.start(subscribing: bus) } else { admOSC.stop() }
        if g.hasEnabledRoute(toSink: "artnet.out") { artNet.start(subscribing: bus) } else { artNet.stop() }
        if g.hasEnabledRoute(toSink: "sacn.out") { sacn.start(subscribing: bus) } else { sacn.stop() }
        #endif
        midiOut.enabled = g.hasEnabledRoute(toSink: "midi.out")
        #if canImport(CoreMIDI)
        midiPub.thruEnabled = g.hasEnabledRoute(from: "midi.in", to: "midi.out")  // MIDI thru
        #endif
        // Broadcast comes online on demand: a route to rtmp.out / srt.out starts the
        // stream (engine permitting), removing the last connection stops it.
        let wantsBroadcast = g.hasEnabledRoute(toSink: "rtmp.out") || g.hasEnabledRoute(toSink: "srt.out")
        broadcast.transport = g.hasEnabledRoute(toSink: "srt.out") ? .srt : .rtmp
        if wantsBroadcast { broadcast.start() } else { broadcast.stop() }
    }

    @ViewBuilder
    private var mainContent: some View {
        // Workstation home: Arrangement/Clips timeline in the foreground, the
        // bio-compose instrument (EchoelStudioView) hosted as one surface. See
        // WorkspaceView / docs/dev/DMMW_ARCHITECTURE.md.
        WorkspaceView()
            .environment(audioEngine)
            .environment(store)
            .environment(beatPlayer)
            .environment(bus)
            .environment(bioVoice)
            .environment(polyVoice)
            .environment(subBass)
            .environment(metronome)
            .environment(bioEvents)
            #if canImport(CoreBluetooth)
            .environment(polarH10)
            #endif
            #if canImport(AVFoundation)
            .environment(cameraRPPG)
            #endif
            #if canImport(AVFoundation) && canImport(Metal)
            .environment(visualRecorder)
            #endif
            #if canImport(HealthKit)
            .environment(healthWriter)
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
            .environment(transport)
            #if canImport(MultipeerConnectivity)
            .environment(colab)
            #endif
            .environment(pianoRoll)
            .environment(clipStore)
            .environment(arrangementStore)
            .environment(arrangementPlayer)
            .environment(automationPlayer)
            .environment(audioInputs)
            .environment(signalRouter)
            .environment(auHost)
            .environment(broadcast)
            .environment(midiOut)
            #if canImport(CoreHaptics)
            .environment(haptics)
            #endif
            .environment(sessionContext)
            .environment(loopExporter)
            .environment(projectStore)
            .environment(demoSource)
            .environment(breathPacer)
            .environment(sessionRecorder)
            .environment(resourceGovernor)
            .environment(fxModulator)
            .task {
                // First line: proves the studio surface rendered AND its startup task
                // ran. If a shared diag log shows "init done" then this, the UI is the
                // studio; if it stops at "init done" with no branch/startup line, the
                // app never reached here (a hang or a non-studio branch).
                EchoelCrashLog.breadcrumb("ui branch: STUDIO — startup task running")
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
                // Breadcrumbs at every STARTUP milestone: this is the most crash-prone
                // window (the build-1363 hot-attach + audio-engine start). They land in
                // the shared diagnostic log, so a launch that dies here names the phase
                // instead of leaving only "launch" (the diagnostics gap behind a black
                // screen). Best-effort file appends on the main actor — negligible cost.
                EchoelCrashLog.breadcrumb("startup 1/4: audio session + graph")
                audioEngine.prepareGraph()
                beatPlayer.loadDefaultSamples()

                log.log(.info, category: .system, "STARTUP [2/4] Attaching voices...")
                EchoelCrashLog.breadcrumb("startup 2/4: attaching voices")
                beatPlayer.attach(to: audioEngine)
                bioVoice.attach(to: audioEngine)
                polyVoice.attach(to: audioEngine)
                leadVoice.attach(to: audioEngine)
                subBass.attach(to: audioEngine)
                metronome.attach(to: audioEngine)

                log.log(.info, category: .system, "STARTUP [3/4] Starting audio engine...")
                EchoelCrashLog.breadcrumb("startup 3/4: starting audio engine")
                audioEngine.start()
                EchoelCrashLog.breadcrumb("startup 3/4: audio engine started OK")

                // The melodic instrument + shared transport — the core sound path.
                // Melody plays via pattern.onTick → polyVoice; drums via onStep.
                // PatternEngine relays each pulse into the authoritative Transport
                // (additive mirror; existing onStep/onTick stay the live path).
                beatPlayer.pattern.transport = transport
                #if canImport(CoreHaptics)
                // Eyes-free transport: every quarter-note pulses the body (no-op
                // until the user arms haptics). Lowest-priority subscriber so it
                // never reorders the arrangement→roll note path.
                transport.addStepSubscriber("haptics", priority: 1000) { [weak haptics] pos in
                    haptics?.tapBeat(step: pos.step)
                }
                #endif
                // Keep the Arrangement's follow-state coherent with the ONE transport:
                // when the transport is stopped from anywhere (the global transport bar's
                // Stop calls PatternEngine.stop() directly, not ArrangementPlayer.stop()),
                // reset the song so it doesn't stay stuck "playing". No-op unless the
                // arrangement was following, so the arrangement's own stop/finish path
                // doesn't recurse.
                transport.addStopSubscriber("arrangement") { [weak arrangementPlayer] in
                    arrangementPlayer?.handleTransportStopped()
                }
                bioVoice.start(subscribing: bus)
                polyVoice.start(subscribing: bus)
                leadVoice.start(subscribing: bus)
                // Bio-reactive FX: bind to the melody voice's chain + bio bus and run
                // the ~30 Hz control loop (idle until the user adds modulation routes).
                fxModulator.attach(chain: polyVoice.fxChain, bus: bus)
                fxModulator.start()
                automationPlayer.wire(pattern: beatPlayer.pattern, audioEngine: audioEngine, voice: polyVoice)
                pianoRoll.start(pattern: beatPlayer.pattern, voice: polyVoice, lead: leadVoice, subVoice: subBass, midiOut: midiOut, arrangement: arrangementPlayer, bus: bus, auHost: auHost, automation: automationPlayer)
                if let firstPatch = patchStore.patches.first { polyVoice.apply(firstPatch) }
                // Give the lead voice a distinct, cutting timbre so .lead notes read as
                // a separate instrument over the (per-genre) harmony voice. Fixed for
                // now; a per-genre lead patch is the next step.
                if let leadPatch = SynthPatch.factory.first(where: { $0.name == "Bright Lead" }) {
                    leadVoice.apply(leadPatch)
                }

                // Bio essentials. The body's REAL signal drives everything — camera
                // rPPG (started when the user taps Create from Within), HealthKit, or
                // a BLE strap. No synthetic demo source: with no sensor the composer
                // uses neutral physiological defaults, and the strip reads "No signal".
                bioEvents.start(on: bus)
                bioFeedback.start(publishingFrom: bus)

                // Modulation routing: empty matrix → no behaviour change until the
                // user adds a route. Tempo handler scales [0..1] into [30..300] BPM raw,
                // then octave-folds into the playable window.
                //
                // THIS handler was the founder's "in dem Moment wo bpm locked springt die
                // bpm nach oben" (video, 79.45): a Body→Tempo route fires the instant the
                // pulse locks (first published frames) and the old raw setTempo BYPASSED
                // the global BPM lock and SNAPPED the clock (75 → 195.5 = 30+0.613×270).
                // Three rules now, matching the app-wide tempo philosophy:
                //   1. the user's BPM lock wins GLOBALLY — a locked take ignores the route;
                //   2. octave-fold the target (StudioCalculator.seedTempo) so a normalized
                //      signal can never demand an absurd 196–300 bpm;
                //   3. GLIDE, never snap — the beat eases toward the body (advance() ticks).
                modulationEngine.register(ModDestinationKey.tempo) { [weak beatPlayer] value in
                    guard !UserDefaults.standard.bool(forKey: "studio.lockBPM") else { return }
                    let raw = 30 + Double(value) * 270
                    beatPlayer?.pattern.glideTempo(to: StudioCalculator.seedTempo(raw))
                }
                modulationEngine.start(subscribing: bus)
                // Non-essential I/O (BLE straps, external MIDI, OSC/ADM/Art-Net/sACN
                // out) is NOT auto-started. It now comes online ON DEMAND from the
                // Patchbay: making a connection to an output starts its sender; the
                // last connection removed stops it. Launch stays lean (no routes =
                // nothing started, no extra permission prompts).
                signalRouter.onChange = { applyRouting() }
                applyRouting()   // honor any persisted routes from a previous session

                // AUv3 host: wire to the live graph so a user-chosen instrument can
                // be loaded into it. Discovery + load are user-driven (no auto-load).
                auHost.use(engine: audioEngine)

                // External MIDI input: passive (the CoreMIDI client is created in
                // MIDIInput.init, no permission prompt), so start it at launch — a
                // connected keyboard plays the built-in voice AND any hosted AUv3
                // instrument (host-MIDI). Idempotent.
                #if canImport(CoreMIDI)
                midiPub.start(publishing: bus, auHost: auHost, midiOut: midiOut)
                #endif

                log.log(.info, category: .system, "STARTUP [4/4] Core ready — instrument live")
                EchoelCrashLog.breadcrumb("startup 4/4: core ready — instrument live")

                // Self-healing: confirm this launch healthy NOW that the UI rendered and
                // the whole risky startup (graph build · voice attach · engine start —
                // the build-1363 crash zone) completed without crashing. A crash anywhere
                // BEFORE this point leaves LaunchGuard's counter raised → the next launch
                // boots into Safe Mode. Confirming at end-of-startup (was a 4 s wall-clock
                // sleep) shrinks the false-escalation window to the sub-second startup
                // duration — so quitting the app fast (e.g. to read the diagnostics log)
                // no longer risks a spurious Safe Mode on the next launch.
                LaunchGuard.confirmHealthy()
                EchoelCrashLog.breadcrumb("LaunchGuard: launch confirmed healthy")

                // ── BEST-EFFORT, NON-BLOCKING ────────────────────────────────
                // These await (HealthKit permission dialog, StoreKit network) and
                // run OFF the launch path so a hang here can never silence the app.
                #if canImport(HealthKit)
                Task { await healthBio.start(publishing: bus) }
                // Opt-in Health write-back: the poll loop is started always but
                // no-ops unless the user has enabled it (near-zero cost when off).
                healthWriter.start(reading: bus)
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
                    auHost.persistState()   // save hosted-plugin settings across relaunch
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
