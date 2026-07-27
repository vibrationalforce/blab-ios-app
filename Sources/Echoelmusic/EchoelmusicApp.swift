#if canImport(SwiftUI)
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation   // AVAudioSession — Session-cue Latenzausgleich (outputLatency)
#endif
#if canImport(UIKit)
import UIKit          // applicationState — background idle-engine gate (2.5.4)
#endif

/// Stable, greppable names for the lifecycle breadcrumb. Written out rather than
/// interpolating `ScenePhase` directly: its `description` is a synthesised enum dump that
/// Apple is free to change, and these strings are what a founder's `echoel_diag.log` gets
/// grepped for — the same contract `PatternEngine.PlayCause`'s rawValues carry.
private func scenePhaseName(_ phase: ScenePhase) -> String {
    switch phase {
    case .active:     return "active"
    case .inactive:   return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
}

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
    /// UX-3 once-per-run latch: the deferred HealthKit ask fires at the first
    /// user-initiated bio start (.echoelBioSourceStarted), then never again this run.
    @State private var healthAskFired = false
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
    /// Dedicated TOUCH-INSTRUMENT voice (founder 2026-07-08: the play surface's sound
    /// must be individually settable and must not glitch the bed). Its own pool means
    /// touch notes never steal a generative voice mid-sustain (the audible "glitch"),
    /// and its patch/morph are independent of the take. Small pool: 4 touches max.
    @State private var touchVoice: PolySynthVoice
    @State private var subBass: SubBassVoice
    /// Steady click track — production/performance metronome (self-driving, silent
    /// until armed). Synced to the transport tempo by the studio view.
    @State private var metronome = MetronomeVoice()
    /// Multi-Roll voice rack (B07) — holds ZERO voices and is never attached unless
    /// FeatureFlags.multiRoll is ON, so the default (OFF) build is bit-identical.
    @State private var laneVoiceRack = LaneVoiceRack()
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
    /// Per-part mixer (bass/pad/lead user levels) — Module 1 of the comprehensive interface.
    @State private var mixerStore = MixerStore()

    /// Per-track FX (bass/melodic/drums inserts) — Module 2 of the comprehensive interface.
    @State private var trackFXStore = TrackFXStore()
    /// Linear song timeline — an ordered chain of sections, each playing a clip.
    @State private var arrangementStore = ArrangementStore()
    /// Beat-grid Arrange timeline (tick-positioned lanes/regions); migrates the
    /// legacy section song on first run (bootstrapIfNeeded in the surface).
    @State private var timelineStore = TimelineStore()
    /// Plays the arrangement back over the shared transport (fed via PianoRollModel).
    @State private var arrangementPlayer = ArrangementPlayer()
    /// Plays the arrange TIMELINE's regions over the shared transport (reorg P3).
    /// Opt-in: engaged only by the timeline's own Play control; a no-op otherwise.
    @State private var timelinePlayer = TimelineRegionPlayer()
    @State private var recordController = RecordController()
    /// The live immersive scene: every non-bio track is a positioned SpatialObject,
    /// moved by the Immersive Stage Touch surface. Control-plane only (no audio thread).
    @State private var spatialScene = SpatialSceneStore()
    /// Parameter automation (master level / tempo) played over the shared transport.
    @State private var automationPlayer = AutomationPlayer()
    /// Selectable recording inputs (mic / interface / Bluetooth) with latency notes.
    @State private var audioInputs = AudioInputManager()
    /// Universal signal router (patchbay): typed routes across all channels, persisted.
    @State private var signalRouter = SignalRouter()
    /// The parameter-apply spine (U2c): a router (keyPath → live setter) the
    /// AutomationPlayer dispatches through, so per-track automation reaches every
    /// internal DDSP parameter through one path. Constructed in init.
    @State private var parameterRouter: ParameterApplyRouter
    /// Broadcast (RTMP/SRT) publisher — the phone-native stream-out pillar.
    @State private var broadcast = BroadcastPublisher()
    #if canImport(CoreHaptics)
    /// Eyes-free haptic feedback (transport pulse). Off until armed.
    @State private var haptics = HapticController()
    #endif
    /// Artist · key · Kammerton — the persisted identity stamped on session names
    /// and export filenames.
    @State private var sessionContext = SessionContext()
    /// Opt-in on-device place token for the session name (default OFF; E2).
    /// Attached to the session context at startup (see body task).
    #if canImport(CoreLocation)
    @State private var locationNamer = LocationNamer(session: nil)
    #endif
    /// Opt-in weather flavour for the composer (default OFF; E3b) — one coarse
    /// WeatherKit fetch per session start, 30-min cache.
    #if canImport(WeatherKit) && canImport(CoreLocation)
    @State private var weatherProvider = WeatherProvider()
    #endif
    /// Opt-in news/event push via CloudKit public DB (default OFF; E4) —
    /// serverless, no account; the founder posts in the CloudKit Dashboard.
    #if canImport(CloudKit) && canImport(UserNotifications)
    @State private var announcements = AnnouncementCenter()
    #endif
    /// Loop → .wav export (live-capture) and the saved-projects library — the one
    /// window's output + persistence.
    @State private var loopExporter = LoopExporter()
    @State private var projectStore = ProjectStore()
    /// Clearly-labeled "Demo" bio source so every user hears the instrument
    /// without paired hardware (owned here now the single window is the root).
    @State private var demoSource = BioSimulator()

    // Resonance-breathing guide (the active half of the coherence loop).
    @State private var breathPacer = BreathPacer()
    // The bio-paced Session (warm restart 2026-07-05): closed-loop breathing cue —
    // guide → flash-safe entrainment plan → latency-compensated audio swell.
    @State private var sessionEngine = SessionEngine()
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
    /// Set when the user taps "Continue to Echoelmusic" in Safe Mode — renders the full
    /// app for the rest of this process even though this launch booted into Safe Mode.
    @State private var forceNormalMode = false
    @Environment(\.scenePhase) private var scenePhase
    /// Order-proof backgrounding marker: iOS may deliver .background → .inactive →
    /// .active, so a `oldPhase == .background` gate alone can miss the resume. Set on
    /// .background, consumed by the .active branch to restart the (possibly stopped)
    /// audio engine + bio loop exactly once per return to foreground.
    @State private var wasBackgrounded = false

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
        // Stage breadcrumbs (device log 1783269182: the diag ended at "launch" with
        // NO crash-handler line — an uncatchable kill (watchdog/jetsam) somewhere in
        // this ~20-constructor chain. These pins name the dying constructor in the
        // NEXT log instead of leaving a 50-line suspect list.)
        EchoelCrashLog.breadcrumb("init a: audio core")
        let mic = MicrophoneManager()
        let audio = AudioEngine(microphoneManager: mic)

        _microphoneManager = State(wrappedValue: mic)
        _audioEngine = State(wrappedValue: audio)
        EchoelCrashLog.breadcrumb("init b: store + beat + bus")
        _store = State(wrappedValue: EchoelStore())
        _beatPlayer = State(wrappedValue: BeatPlayer())
        _bus = State(wrappedValue: EngineBus())
        // Parameter-apply spine (U2c): tiny control-plane objects, no I/O.
        // The registry seeds with the internal DDSP inventory; the router binds
        // keyPath → live setter so automation reaches each parameter.
        let paramRegistry = EchoelParameterRegistry()
        paramRegistry.register(DDSPParameterCatalog.descriptors)
        _parameterRouter = State(wrappedValue: ParameterApplyRouter(registry: paramRegistry))
        EchoelCrashLog.breadcrumb("init c: bio publishers")
        #if canImport(HealthKit)
        _healthBio = State(wrappedValue: HealthKitBioPublisher())
        #endif
        #if canImport(CoreBluetooth)
        _polarH10 = State(wrappedValue: PolarH10BioPublisher())
        #endif
        EchoelCrashLog.breadcrumb("init d: synth voices")
        _bioVoice = State(wrappedValue: BioReactiveSynthVoice())
        // 12 voices: the composer emits up to ~12 notes/bar and the 2 s release
        // tails keep voices ringing across the bar, so 8 was oversubscribed →
        // constant voice-stealing caused clicks, instant pitch changes and tanh
        // level swings (device report: "Lautstärke-/Phasensprünge, Knacksen").
        _polyVoice = State(wrappedValue: PolySynthVoice(maxVoices: 12))
        // Lead voice: small pool (the melody is few-note) to keep the added CPU low.
        _leadVoice = State(wrappedValue: PolySynthVoice(maxVoices: 3))
        // Touch voice: 6 slots for max 4 fingers + release tails (steals only its own).
        _touchVoice = State(wrappedValue: PolySynthVoice(maxVoices: 6))
        _subBass = State(wrappedValue: SubBassVoice())
        _bioEvents = State(wrappedValue: BioEventPublisher())
        _bioFeedback = State(wrappedValue: BioFeedbackPublisher())
        EchoelCrashLog.breadcrumb("init e: midi + osc")
        #if canImport(CoreMIDI)
        let midi = MIDIInput()
        _midiInput = State(wrappedValue: midi)
        _midiPub = State(wrappedValue: MIDIBusPublisher(midi: midi))
        #endif
        #if canImport(Network)
        _osc = State(wrappedValue: OSCSender())
        #endif
        EchoelCrashLog.breadcrumb("init f: modulation + stores + roll")
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

    /// Bring outputs online/offline to match the Patchbay (see also `scenePhaseName`
    /// at file scope, used by the lifecycle breadcrumb). An enabled route to an
    /// output's port starts its sender (idempotent — each `start` guards `isActive`);
    /// removing the last route stops it. MIDI Out is a simple enable flag. Called on
    /// every routing change and once at launch (for persisted routes).
    @MainActor
    private func applyRouting() {
        let g = signalRouter.graph
        #if canImport(Network)
        if g.hasEnabledRoute(toSink: "osc.out") { osc.start(subscribing: bus) } else { osc.stop() }
        admOSC.attachScene(spatialScene)   // idempotent weak-ref; enables Immersive-Stage scene streaming
        if g.hasEnabledRoute(toSink: "adm.out") { admOSC.start(subscribing: bus) } else { admOSC.stop() }
        if g.hasEnabledRoute(toSink: "artnet.out") { artNet.start(subscribing: bus) } else { artNet.stop() }
        if g.hasEnabledRoute(toSink: "sacn.out") { sacn.start(subscribing: bus) } else { sacn.stop() }
        #endif
        midiOut.enabled = g.hasEnabledRoute(toSink: "midi.out")
        #if canImport(CoreMIDI)
        midiPub.thruEnabled = g.hasEnabledRoute(from: "midi.in", to: "midi.out")  // MIDI thru
        #endif
        // BLE-3 (ultrascan 2026-07-15): the strap has ONE owner — the pulse-pill
        // source dropdown (studio startBioSource). The former blehrs.in coupling
        // here made applyRouting a SECOND owner that stopped a pill-started strap
        // on EVERY unrelated Patchbay edit (mid-performance kill) and could start
        // it alongside the camera (the one real both-sources-at-once path). The
        // blehrs.in port remains a data-flow port; it no longer drives lifecycle.
        // Broadcast comes online on demand: a route to rtmp.out / srt.out starts the
        // stream (engine permitting), removing the last connection stops it.
        let wantsBroadcast = g.hasEnabledRoute(toSink: "rtmp.out") || g.hasEnabledRoute(toSink: "srt.out")
        broadcast.transport = g.hasEnabledRoute(toSink: "srt.out") ? .srt : .rtmp
        if wantsBroadcast { broadcast.start() } else { broadcast.stop() }
    }

    @ViewBuilder
    private var mainContent: some View {
        // The app home is the bio-generative INSTRUMENT (founder re-focus
        // 2026-07-06B: "keine Atemübung — Performance und Entspannung dadurch,
        // dass sich die Musik mit dem Biofeedback generativ verändert"). The
        // breathing-session experiment stays in code, unpresented (reversible).
        WorkspaceView()
            .environment(audioEngine)
            .environment(store)
            .environment(beatPlayer)
            .environment(bus)
            .environment(bioVoice)
            .environment(polyVoice)
            // Touch instrument's own voice — custom key: a second `.environment(PolySynthVoice)`
            // would silently REPLACE polyVoice for every consumer (last-writer-wins per type).
            .environment(\.touchSynth, touchVoice)
            .environment(\.leadSynth, leadVoice)
            .environment(subBass)
            .environment(laneVoiceRack)
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
            .environment(mixerStore)
            .environment(trackFXStore)
            .environment(arrangementStore)
            .environment(timelineStore)
            .environment(arrangementPlayer)
            .environment(timelinePlayer)
            .environment(recordController)
            .environment(spatialScene)
            .environment(automationPlayer)
            .environment(audioInputs)
            .environment(signalRouter)
            .environment(broadcast)
            .environment(midiOut)
            #if canImport(CoreHaptics)
            .environment(haptics)
            #endif
            .environment(sessionContext)
            #if canImport(CoreLocation)
            .environment(locationNamer)
            #if canImport(WeatherKit)
            .environment(weatherProvider)
            #endif
            #endif
            #if canImport(CloudKit) && canImport(UserNotifications)
            .environment(announcements)
            #endif
            .environment(loopExporter)
            .environment(projectStore)
            .environment(demoSource)
            .environment(breathPacer)
            .environment(sessionEngine)
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
                // Multi-Roll DEFAULT-ON (founder 2026-07-14: "das Spuren System … jede
                // Spur ein Instrument"): register the flag's fallback as true so multiple
                // MIDI lanes each play their own voice out of the box. Registering (not
                // setting) leaves an explicit dev-OFF override intact and does not disturb
                // the OFF-by-default contract of every OTHER feature flag. Must precede the
                // first `FeatureFlags.multiRoll` read below (rack attach).
                UserDefaults.standard.register(defaults: [FeatureFlags.Key.multiRoll.rawValue: true])
                // S2-W2 kind routing DEFAULT-ON (founder verdict 2026-07-17: "Es
                // funktioniert noch nichts … lockere zu dogmatische Grenzen"): a
                // drums/sub-bass track now actually SOUNDS like its instrument. The
                // old "OFF until device verify" gate was a deadlock — the founder
                // cannot verify a path he has no way to switch on (same rationale
                // that made multiRoll registration-ON). Risk
                // activates only through the explicit act of assigning a drums/sub
                // instrument to a track; `FeatureFlags.set(.voiceKindRouting, false)`
                // stays the one-line rollback lever. NEVER delete the OFF branches.
                UserDefaults.standard.register(defaults: [FeatureFlags.Key.voiceKindRouting.rawValue: true])
                // Instrument-Home DEFAULT-ON (founder 2026-07-22 vision Step 1): the
                // app opens directly into the living instrument (the existing
                // FloatingVisualWindow fullscreen), the DAW chrome stays mounted
                // beneath. Registration-ON for the SAME reason as multiRoll/
                // voiceKindRouting — a default-OFF flag with no UI to flip it is an
                // un-verifiable deadlock, and the founder must device-verify the new
                // front door. `FeatureFlags.set(.instrumentHome, false)` restores the
                // bit-identical chrome-first home (one-line rollback lever).
                UserDefaults.standard.register(defaults: [FeatureFlags.Key.instrumentHome.rawValue: true])
                // Breadcrumbs at every STARTUP milestone: this is the most crash-prone
                // window (the build-1363 hot-attach + audio-engine start). They land in
                // the shared diagnostic log, so a launch that dies here names the phase
                // instead of leaving only "launch" (the diagnostics gap behind a black
                // screen). Best-effort file appends on the main actor — negligible cost.
                EchoelCrashLog.breadcrumb("startup 1/4: audio session + graph")
                audioEngine.prepareGraph()
                // `beatPlayer.loadDefaultSamples()` used to sit here. Removed 2026-07-27:
                // it decoded 8 bundled drum WAVs into the pad voices on EVERY launch, and
                // since the drums removal (c9af52b) `BeatPlayer.attach(to:)` no longer
                // attaches those voices to the engine — so the samples were read, decoded
                // and held in memory for voices that cannot reach the output. Pure launch
                // cost, in the most crash-prone window of the app's life.
                //
                // IT ALSO STOPPED FOUR PERSISTENCE RESTORES, which the first version of
                // this comment failed to mention: `loadDefaultSamples()` was the sole
                // caller of `restoreCustomSamples/Shapes/ModesAndSynth/Mix`, so seven
                // UserDefaults-backed pad properties no longer reload at launch. Harmless
                // TODAY because every reader is an unreachable view — but if either view
                // is ever re-doored, that state will silently come back as DEFAULTS
                // instead of the user's saved kit. Restore this call with it, or move the
                // restores to the door.
                //
                // BeatPlayer itself STAYS, and is not a leftover. Two live surfaces:
                // `beatPlayer.pattern` (the PatternEngine — transport, tempo clock, what
                // `pianoRoll.start(pattern:)` drives) and the STATIC
                // `BeatPlayer.resolveSampleRef`, installed as `timelinePlayer
                // .slotSampleSink` below. Only the per-instance sampler half is dead.

                log.log(.info, category: .system, "STARTUP [2/4] Attaching voices...")
                EchoelCrashLog.breadcrumb("startup 2/4: attaching voices")
                beatPlayer.attach(to: audioEngine)
                bioVoice.attach(to: audioEngine)
                polyVoice.attach(to: audioEngine)
                leadVoice.attach(to: audioEngine)
                touchVoice.attach(to: audioEngine)
                subBass.attach(to: audioEngine)
                metronome.attach(to: audioEngine)
                // Session breathing cue — attached BEFORE start like every voice
                // (build-1363 rule). Launch-silent until the user starts a session.
                sessionEngine.attach(to: audioEngine)
                // Multi-Roll (B07): attach the per-lane voice rack BEFORE start()
                // (attach-before-start law). No-op + zero voices while the flag is OFF.
                if FeatureFlags.multiRoll {
                    laneVoiceRack.attachAll(to: audioEngine)
                    // S2-W1: seed the freshly-created rack voices with the PERSISTED
                    // melodic insert right at attach — otherwise a secondary lane
                    // plays unfiltered until the next Melodic edit pushes one.
                    laneVoiceRack.setInsert(trackFXStore.melodic)
                }

                log.log(.info, category: .system, "STARTUP [3/4] Starting audio engine...")
                EchoelCrashLog.breadcrumb("startup 3/4: starting audio engine")
                audioEngine.start()
                EchoelCrashLog.breadcrumb("startup 3/4: audio engine started OK")
                #if canImport(AVFoundation) && os(iOS)
                // Latenzausgleich: feed the measured audio output delay to the Session
                // clock so the heard breathing swell lands on the perceptual grid.
                let av = AVAudioSession.sharedInstance()
                sessionEngine.setAudioLatency(av.outputLatency + av.ioBufferDuration)
                #endif

                // The melodic instrument + shared transport — the core sound path.
                // Melody plays via pattern.onTick → polyVoice; drums via onStep.
                // PatternEngine relays each pulse into the authoritative Transport.
                // Not a passive mirror: the click/haptics subscribe to Transport below,
                // so this assignment is what makes them follow the tempo at all.
                beatPlayer.pattern.transport = transport
                // ONE BPM: the click FOLLOWS the authoritative clock instead of being
                // pushed from the UI. The ~6 scattered `metronome.bpm` writes are gone,
                // so this is now the ONLY writer — automation and the Body→Tempo route
                // no longer leave the click behind, and the two writes that sat after
                // `glideTempo` no longer run it ahead to the glide target.
                // Registered once here; the callback seeds itself with the current tempo.
                // The menu-freeze law is about view READS: this callback WRITES an
                // @Observable at up to ~20 Hz (the stopped-glide relay), which is only
                // harmless because no view body reads `metronome.bpm`. If one ever does,
                // it must be a leaf — never the root or a Picker host.
                transport.onTempoChange(id: "metronome") { [weak metronome] bpm in
                    metronome?.bpm = bpm
                }
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
                // Same coherence for the timeline player: any Stop resets its follow-state.
                transport.addStopSubscriber("timeline") { [weak timelinePlayer] in
                    timelinePlayer?.handleTransportStopped()
                }
                // HIG: unplugging headphones pauses playback instead of resuming on
                // the loudspeaker. The engine's route-loss recovery only re-wires the
                // graph (silent once stopped); THIS runs the exact TransportBar stop
                // cascade so every player/voice releases through the proven path.
                // The timeline half of this cascade is gone with ▶'s arrangement branch
                // (`TransportBar.toggle`): `TimelineRegionPlayer.isPlaying` has one write
                // site and no production caller reaches it, so the old two-branch form was
                // a dead choice that still read like a live one — the exact thing the ▶
                // change removed one file over. Leaving it here would have the repo assert
                // in one file what it denies in another.
                audioEngine.onOutputDeviceLost = { [weak beatPlayer] in
                    guard beatPlayer?.pattern.isPlaying == true else { return }
                    EchoelCrashLog.breadcrumb("stop source: route-lost (output device gone)")
                    beatPlayer?.pattern.stop()
                }
                #if canImport(UIKit)
                // 2.5.4, second hole (code review 2026-07-16): audio that ENDS while
                // the app is ALREADY backgrounded (an arrangement finishes on its own,
                // or the route-loss hook above stops it) previously left the engine
                // rendering silence indefinitely — the .background branch only checks
                // at the transition. Any transport stop landing in the background
                // re-runs the idle gate; recording / monitoring / held performer
                // notes still keep the session alive. stop() sets the engine's
                // intentionallyStopped flag, which also stands down the route-loss
                // recovery task, so this closes both reported paths.
                transport.addStopSubscriber("background-idle") {
                    [weak audioEngine, weak microphoneManager, weak polyVoice] in
                    guard UIApplication.shared.applicationState == .background,
                          let audioEngine else { return }
                    let audioNeeded = audioEngine.multiTrackRecorder.isRecording
                        || microphoneManager?.isRecording == true
                        || audioEngine.isInputMonitoring
                        || (polyVoice?.activeVoiceCount ?? 0) > 0
                    guard !audioNeeded else { return }
                    audioEngine.stop()
                    log.log(.info, category: .system,
                            "Transport stopped in background — idle audio engine stopped (2.5.4)")
                }
                #endif
                bioVoice.start(subscribing: bus)
                polyVoice.start(subscribing: bus)
                leadVoice.start(subscribing: bus)
                touchVoice.start(subscribing: bus)   // touch notes breathe with the body too
                // Multi-Roll (B07/B08): subscribe the rack's slot voices AND route each
                // SECONDARY lane's note events to its own voice (flag-ON only). The
                // primary lane keeps the rich PianoRollModel; additional MIDI lanes now
                // sound simultaneously through the rack. The sink runs on @MainActor
                // (called from timelinePlayer.transportStep) and only enqueues note
                // commands onto each voice's lock-free SPSC queue — no audio-thread work.
                // BodyVibe B1 + App-Group-Puls-Brücke: BOTH ride the GLOBAL
                // bio voice's existing 10 Hz tick — no second timer, no
                // per-frame MainActor hop. feedBio is timbre-only (the
                // sequencer note gate owns the envelope) and zero-cost
                // while the rack has no bio unit (voiceKindRouting OFF).
                // The global armed voice itself is untouched — the rack
                // unit is a SEPARATE BioReactiveSynthVoice instance.
                // publishTick() writes the latest usable bio frame into the
                // App Group for the AUv3/Widget/Watch — inert until
                // bioFeedback.start(...) arms it below, ≤10 Hz with per-frame
                // timestamp dedupe, HealthKit frames marked non-egress
                // (BioEgressPolicy, 5.1.3). Installed OUTSIDE the multiRoll
                // gate so the bridge survives the flag's rollback lever.
                let rackFeedsBio = FeatureFlags.multiRoll
                bioVoice.onPollTick = { [weak laneVoiceRack, weak bus, weak bioFeedback] in
                    bioFeedback?.publishTick()
                    guard rackFeedsBio, let bus else { return }
                    laneVoiceRack?.feedBio(from: bus)
                }
                if FeatureFlags.multiRoll {
                    laneVoiceRack.startAll(subscribing: bus)
                    // A nil-patch lane falls back to the SAME patch the primary voice
                    // gets (patchStore.patches.first, applied at line ~527), so an
                    // unset lane matches the primary timbre — never the bare DDSP default.
                    let fallbackPatch = patchStore.patches.first
                    timelinePlayer.enableMultiRoll(capacity: laneVoiceRack.capacity) { [weak laneVoiceRack] slot, events in
                        // S2-W2-4: the built-in path goes through the rack FACADE,
                        // which routes the slot to its bound KIND (poly/drums/sub). With
                        // voiceKindRouting OFF every slot binds .poly ⇒ the facade calls
                        // voice(slot:) — bit-identical to the pre-S2-W2 rack path.
                        for event in events {
                            if event.isOn {
                                laneVoiceRack?.noteOn(slot: slot, pitch: event.pitch, velocity: event.velocity)
                            } else {
                                laneVoiceRack?.noteOff(slot: slot, pitch: event.pitch)
                            }
                        }
                    } patchSink: { [weak laneVoiceRack] slot, patch in
                        // Facade: applies to the poly voice, a documented no-op for a
                        // kit/sub-bound slot (their timbre is the kit presets / sub voice).
                        if let resolved = patch ?? fallbackPatch { laneVoiceRack?.applyPatch(slot: slot, resolved) }
                    }
                    // S2-W2-4: publish each slot's voice KIND so the rack rebinds its
                    // physical voice. Idempotent + poly-only while voiceKindRouting is
                    // OFF (zero kind units ⇒ allocator resolves every slot to poly).
                    timelinePlayer.slotKindSink = { [weak laneVoiceRack] slot, kind in
                        laneVoiceRack?.setKind(slot: slot, kind: kind)
                    }
                    // S2-W3 (EchoelSampler klingt): the lane's persisted sample REF,
                    // fired right after the kind at the same player sites — resolved
                    // via the ONE ref lookup and loaded into the slot's bound sampler
                    // unit. That lookup now knows exactly ONE convention — a
                    // mediaRef-style absolute path. The two BUNDLE schemes it also used
                    // to accept, "drum:<Name>" and "lib:<Category>/<Name>", died with
                    // their assets (#167, 2026-07-27): a ref persisted under either by an
                    // older build resolves to nil today and the slot stays unloaded.
                    // Unresolvable/nil ⇒ the unit stays as-is (never a crash).
                    timelinePlayer.slotSampleSink = { [weak laneVoiceRack] slot, path in
                        laneVoiceRack?.setSample(slot: slot, url: BeatPlayer.resolveSampleRef(path))
                    }
                    // Per-instrument Transpose (founder 2026-07-14): pitch each SECONDARY
                    // lane's rack voice by its own semitone shift when the lane loads.
                    timelinePlayer.slotTransposeSink = { [weak laneVoiceRack] slot, semitones in
                        // Facade: poly shifts render-side; a sub-bound slot pitches its
                        // mono note at enqueue (and releases a held note on a change);
                        // a kit is unpitched (documented ignore).
                        laneVoiceRack?.setTranspose(slot: slot, semitones: semitones)
                    }
                    // Per-instrument Detune (founder 2026-07-14 "transpose detune"): fine
                    // cents offset per SECONDARY lane's rack voice, alongside transpose.
                    timelinePlayer.slotDetuneSink = { [weak laneVoiceRack] slot, cents in
                        laneVoiceRack?.setDetune(slot: slot, cents: cents)   // poly-only (documented)
                    }
                    // Per-instrument Oktaver (founder 2026-07-14 "transpose detune und
                    // Oktaver"): octave-double each SECONDARY lane's rack voice per its
                    // lane direction. Poly-only like detune (sub folds octaves, kit
                    // unpitched, AU lanes deliberately excluded).
                    timelinePlayer.slotOctaveSink = { [weak laneVoiceRack] slot, direction in
                        laneVoiceRack?.setOctave(slot: slot, direction: direction)
                    }
                    // H4 (healing wave 1, "Pan silently inert"): each SECONDARY lane's
                    // pan + continuous gain reach its rack voice — at region load AND
                    // live on a mid-play mixer edit (the player merges the store's
                    // mixer state each step via `liveDocument` below).
                    timelinePlayer.slotPanSink = { [weak laneVoiceRack] slot, pan in
                        laneVoiceRack?.setPan(slot: slot, pan)   // sub un-panned (documented no-op)
                    }
                    timelinePlayer.slotGainSink = { [weak laneVoiceRack] slot, gain in
                        laneVoiceRack?.setGain(slot: slot, gain)   // 0…2 per bound kind
                    }
                    // The roll-slot GAIN mirror (K2a), relocated here (heal-review
                    // HIGH): the old owner was ArrangeTimelineView.onChange, which
                    // UNMOUNTS when the timeline is folded (persisted @AppStorage) —
                    // a mixer edit or the Start-heal then never reached
                    // pianoRoll.mixGain and the roll stayed silent (or stale-loud)
                    // despite the healed document. This hook is always-mounted and
                    // fires synchronously inside persist(), so a heal is audible on
                    // the very Start that applied it. ONE writer of mixGain.
                    let syncRollMix = { [weak timelineStore, weak pianoRoll] in
                        guard let doc = timelineStore?.document, let roll = pianoRoll else { return }
                        let gain = doc.rollSlotGain
                        roll.mixGain = gain
                        if gain <= 0.001 { roll.allNotesOff() }   // mute cuts sounding notes now
                    }
                    syncRollMix()   // initial sync (launch-with-folded-timeline staleness)
                    // The roll-mix sync runs on every document change (assign/clear/
                    // lane-delete/undo — all funnel through persist), keeping the
                    // primary roll's gain live. (Per-lane AUv3 hosting removed
                    // 2026-07-24, pure-instrument verdict — the built-in rack voices
                    // are the lane instruments now.)
                    timelineStore.onDocumentChanged = {
                        syncRollMix()
                    }
                }
                // H4: let the region player pull LIVE mixer values (mute/solo/level/
                // pan) from the store each transport step — its play() snapshot alone
                // froze mid-play mixer edits until the next region boundary. The
                // primary roll lane stays live via the onDocumentChanged hook above.
                timelinePlayer.liveDocument = { [weak timelineStore] in
                    timelineStore?.document
                }
                // Bio-reactive FX: bind to the melody voice's chain + bio bus and run
                // the ~30 Hz control loop (idle until the user adds modulation routes).
                // Per-instrument Transpose for the PRIMARY roll lane (founder 2026-07-14):
                // the roll lane plays polyVoice (not a rack slot), so it gets its own hook.
                timelinePlayer.rollTransposeSink = { [weak polyVoice] semitones in
                    polyVoice?.setTranspose(semitones: semitones)
                }
                timelinePlayer.rollDetuneSink = { [weak polyVoice] cents in
                    polyVoice?.setDetune(cents: cents)
                }
                timelinePlayer.rollOctaveSink = { [weak polyVoice] direction in
                    polyVoice?.setOctaver(direction: direction)
                }
                // #23 S2b: the PRIMARY roll lane's own persisted SynthPatch, applied to
                // the global poly voice when its region loads. Fires ONLY when the lane
                // carries a patch (the player guards nil), so a lane with no patch keeps
                // the live-edited global sound — no clobber. This makes a primary lane's
                // timbre document-persistent, symmetric with the secondary slotPatchSink.
                timelinePlayer.rollPatchSink = { [weak polyVoice] patch in
                    polyVoice?.apply(patch)
                }
                // S2-W2-6: route the PRIMARY roll through its lane's kind voice when
                // that lane is a sub-bass. The rack's single sub backs it; nil (poly, OR
                // the unit is absent because voiceKindRouting is OFF ⇒ subs empty)
                // restores today's polyVoice path — bit-identical.
                //
                // NO DRUMS (founder 2026-07-26): a `case .drums` arm stood here, reading
                // `laneVoiceRack?.kits.first`. `LaneVoiceRack` no longer creates a kit, so
                // it could only ever have resolved to nil — exactly what `default` does —
                // and `TrackInstrument.voiceKind` no longer returns `.drums` at all, so the
                // arm was unreachable twice over. Removing it changes no behaviour.
                timelinePlayer.rollKindSink = { [weak pianoRoll, weak laneVoiceRack] kind in
                    guard let pianoRoll else { return }
                    switch kind {
                    case .subBass: pianoRoll.setKindVoice(laneVoiceRack?.subs.first)
                    // .sampler deliberately falls through to poly here (S2-W3):
                    // SamplerVoice is a nonisolated one-shot (fire/silence), not a
                    // NoteVoice — a PRIMARY-roll sampler lane would need an adapter
                    // the secondary-lane path doesn't. Secondary sampler lanes are
                    // fully audible via the rack facade; the primary roll keeps
                    // today's poly voice — honest, no lying half-path.
                    default:       pianoRoll.setKindVoice(nil)
                    }
                }
                // A1 (healing wave 1, audit-verified CRITICAL "audio lanes silent"):
                // the tested AudioLanePlayer coordinator finally gets its device sink —
                // one streaming AVAudioPlayerNode per audio lane, additive into the
                // master mix — and rides timelinePlayer's transport (prime/apply/stop).
                timelinePlayer.audioLanes = AudioLanePlayer(
                    makeSink: { [weak audioEngine] in TimelineAudioSink(engine: audioEngine) },
                    resolveURL: { [weak clipStore] id in
                        guard let clip = clipStore?.clip(id: id) else { return nil }
                        return MediaLibrary.resolveRef(clip.mediaRef)
                    },
                    // Stretch Slice B: the clip's native tempo feeds the region's
                    // StretchPlan, so a warp+Tape placement sounds on the timeline
                    // exactly like the editor preview.
                    resolveNativeBPM: { [weak clipStore] id in
                        clipStore?.clip(id: id)?.nativeBPM ?? 0
                    })
                fxModulator.attach(chain: polyVoice.fxChain, bus: bus)
                fxModulator.start()
                automationPlayer.wire(pattern: beatPlayer.pattern, audioEngine: audioEngine, voice: polyVoice)
                pianoRoll.start(pattern: beatPlayer.pattern, voice: polyVoice, lead: leadVoice, subVoice: subBass, midiOut: midiOut, arrangement: arrangementPlayer, bus: bus, automation: automationPlayer, timeline: timelinePlayer)
                if let firstPatch = patchStore.patches.first { polyVoice.apply(firstPatch) }
                // Touch voice pre-generate default: the RESPONSIVE "Echoel Synth" pad
                // (quick attack + unison width) so the play surface answers a finger
                // immediately instead of the mushy 0.5 s "Warm Pad" it used to launch
                // on (founder 2026-07-09: "Den Synth vom Visual Touch Instrument auch
                // optimieren"). The generate path re-syncs it to the take, or the
                // user's own touch patch overrides.
                if let touchPatch = patchStore.patches.first(where: { $0.id == SynthPatch.touchDefaultID })
                    ?? patchStore.patches.first {
                    touchVoice.apply(touchPatch)
                }
                // WARM default lead timbre (founder 2026-07-07: "warmen Synth-Sound …
                // quakige Töne raus"). The per-genre `leadPatchName` overrides this on
                // generate; this is just the pre-generate default, so it's warm, not the
                // old bright/cutting "Bright Lead" that read as nasal on the first sound.
                if let leadPatch = SynthPatch.factory.first(where: { $0.name == "Soft Keys" }) {
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
                // B26: every applied modulation ALSO streams over OSC as
                // /echoelmusic/mod/<key> (the documented mod-out address) for external
                // tools (TouchDesigner / Resolume / Max). The tap fires per applied
                // destination on the @MainActor control loop; OSCSender is @MainActor too,
                // and `sendModulation` no-ops while the sender is inactive — so this is
                // additive and silent until the user enables OSC out from the Patchbay.
                modulationEngine.outputTap = { [weak osc] destination, value in
                    osc?.sendModulation(key: destination.key, value: value)
                }
                modulationEngine.start(subscribing: bus)
                // Non-essential I/O (BLE straps, external MIDI, OSC/ADM/Art-Net/sACN
                // out) is NOT auto-started. It now comes online ON DEMAND from the
                // Patchbay: making a connection to an output starts its sender; the
                // last connection removed stops it. Launch stays lean (no routes =
                // nothing started, no extra permission prompts).
                signalRouter.onChange = { applyRouting() }
                applyRouting()   // honor any persisted routes from a previous session

                // Parameter-unification spine (U2c): the AutomationPlayer dispatches
                // its registry lanes through the shared router, so the built-in voice's
                // DDSP params are automatable in the track.
                automationPlayer.wire(router: parameterRouter)
                // Automation "all parameters" (founder 2026-07-14): bind the built-in
                // voice's bio-independent DDSP params into the SAME router, so drawn /
                // recorded automation lanes move them live — exactly how the AUv3 host
                // above binds a hosted plugin's knobs. Anything bound into
                // `parameterRouter` becomes automatable by name. Bio-contested params
                // are excluded in bindAutomatable (they need automation×bio composition).
                polyVoice.bindAutomatable(into: parameterRouter)
                // L2/L4 S2b: per-track automation DISPATCH. A namespaced
                // "track.<laneID>.<param>" lane resolves to the specific SECONDARY
                // lane's rack voice slot (not the global voice above), so two tracks
                // automating the same parameter move independently. The roll lane owns
                // no rack slot ⇒ its params stay on the global path. Byte-identical
                // no-op until a per-track lane is authored (no namespaced keyPaths
                // exist yet — the golden gate). Context is read per apply (laneID→slot
                // is rank-unstable between plays); the setter writes the slot voice's
                // own automatable param.
                parameterRouter.bindPerTrack(
                    context: { [weak timelineStore, weak laneVoiceRack] in
                        let doc = timelineStore?.document ?? TimelineDocument(lanes: [], regions: [])
                        return ParameterApplyRouter.PerTrackContext(
                            document: doc, rollLane: doc.rollLaneID,
                            capacity: laneVoiceRack?.capacity ?? 0)
                    },
                    setter: { [weak laneVoiceRack] slot, base, real in
                        laneVoiceRack?.voice(slot: slot)?.applyAutomatable(base: base, real: real) ?? false
                    })
                // External MIDI input: passive (the CoreMIDI client is created in
                // MIDIInput.init, no permission prompt), so start it at launch — a
                // connected keyboard plays the built-in voice. Idempotent.
                #if canImport(CoreMIDI)
                midiPub.start(publishing: bus, midiOut: midiOut)
                #endif

                // Record system (B): wire the take coordinator to the live clock + stores
                // and tee external MIDI notes into it. Arming a track's Record button +
                // playing captures its input into a Clip + region on that lane. The tee
                // closures are no-ops unless a take is running (RecordController gates).
                // Task #13 (PLAN_AUDIO_LANE_RECORDING_2026-07-21.md, S1): the real
                // mic-capture hook, gated OFF by default — FeatureFlags.audioLaneRecording
                // stays false until S2 (duration/latency) + a device verify land, so
                // this passes nil today and the app is behavior-identical.
                recordController.wire(transport: transport, timeline: timelineStore,
                                      clips: clipStore, bus: bus,
                                      audioRecorder: FeatureFlags.audioLaneRecording
                                          ? audioEngine.multiTrackRecorder : nil)
                midiPub.onRecordNoteOn = { [weak recordController] note, velocity in
                    recordController?.recordNoteOn(pitch: note, velocity: velocity)
                }
                midiPub.onRecordNoteOff = { [weak recordController] note in
                    recordController?.recordNoteOff(pitch: note)
                }

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
                // UX-3: launch may START Health publishing but never PROMPT — the
                // context-free full-screen Health sheet used to interrupt the very
                // first studio render (and could stack under the camera dialog if
                // the user tapped the pulse pill). Previously-granted users keep
                // their launch behavior; on a fresh install the ask fires at the
                // first real bio use (.echoelBioSourceStarted below).
                Task { await healthBio.startIfAlreadyAuthorized(publishing: bus) }
                // Opt-in Health write-back: the poll loop is started always but
                // no-ops unless the user has enabled it (near-zero cost when off).
                healthWriter.start(reading: bus)
                #endif
                // StoreKit only when a purchase surface is enabled (FeatureFlags.storeKit,
                // default OFF) — no product-load / entitlement network at launch otherwise.
                if FeatureFlags.storeKit {
                    Task {
                        await store.loadProducts()
                        await store.updateEntitlements()
                    }
                }
                #if canImport(CoreLocation)
                // Opt-in place token: attach feeds the session name; resolve()
                // only acts when the user has the toggle ON (default OFF).
                locationNamer.attach(session: sessionContext)
                #endif
            }
            #if canImport(HealthKit)
            // UX-3: the deferred HealthKit ask fires at the FIRST user-initiated bio
            // start of this run (the studio posts after its source is up, so the
            // camera dialog — if any — is already answered; system sheets appear
            // sequentially, never stacked). One ask per run: start() is idempotent
            // (isPublishing guard) and iOS re-prompts only while undetermined, but
            // the flag also spares repeated no-op authorization round-trips.
            .onReceive(NotificationCenter.default.publisher(for: .echoelBioSourceStarted)) { _ in
                guard !healthAskFired else { return }
                healthAskFired = true
                Task { await healthBio.start(publishing: bus) }
            }
            #endif
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // THE MISSING LINE IN EVERY DEVICE LOG SO FAR. Two founder logs in a row
                // produced a gap that could not be read: the camera reporting
                // `videoNotAvailableInBackground`, and a 40-minute stretch where the
                // visual's 5 s line stopped while `generate[evolve]` kept ticking. Both
                // are EXACTLY what a backgrounded app looks like — and both are also what
                // a stalled render loop or a hung session would look like. Without a
                // lifecycle mark in the diag file the two are indistinguishable, so each
                // one costs a triage cycle that ends in "probably backgrounded".
                //
                // The `log.log(.info, …)` in the `.active` branch below does NOT close
                // this: `os_log` goes to the system console, and what the founder shares
                // is `echoel_diag.log`, which only `EchoelCrashLog` writes (its
                // signal handler writes raw to the same fd — `breadcrumb` is the
                // non-crash path, not the only one).
                // The information existed and simply never reached the file we read.
                //
                // Frequency is a handful of transitions per session, so this cannot
                // approach the "no I/O on a hot path" rule.
                EchoelCrashLog.breadcrumb("scene: \(scenePhaseName(oldPhase)) → \(scenePhaseName(newPhase))")
                switch newPhase {
                case .active:
                    // Resume must survive BOTH transition orders — iOS can deliver
                    // .background → .active directly OR .background → .inactive →
                    // .active (then oldPhase is .inactive and an == .background gate
                    // never fires). The wasBackgrounded flag is order-proof; start()
                    // is idempotent (guards !masterEngine.isRunning), so a spurious
                    // call is a no-op. Critical since the .background branch may now
                    // deliberately STOP an idle engine (2.5.4) — a missed resume
                    // would mean silence until relaunch.
                    if oldPhase == .background || wasBackgrounded {
                        wasBackgrounded = false
                        audioEngine.start()
                        bioFeedback.start(publishingFrom: bus)
                        log.log(.info, category: .system, "App active — audio resumed")
                        EchoelCrashLog.breadcrumb("scene: audio resumed")
                    }
                case .background:
                    wasBackgrounded = true
                    // App-Group-Puls-Brücke (2026-07-17): bioFeedback deliberately
                    // KEEPS publishing in the background — the bridge's headline
                    // scenario is the HOST (GarageBand/AUM) in the foreground with
                    // Echoel backgrounded but still measuring (audio +
                    // bluetooth-central background modes). Cost is bounded: the
                    // 10 Hz tick only runs while the process runs anyway, and
                    // publishTick writes only NEW usable frames (timestamp dedupe)
                    // — a suspended app or dropped sensor writes nothing. The old
                    // `bioFeedback.stop()` here predated the AUv3 bridge (widget-
                    // only battery trim); restore that one line to revert.
                    // Task #56 C6: a debounced timeline save (see TimelineStore.persist())
                    // could still be sleeping when the app suspends — flush it now so a
                    // backgrounded/terminated app never loses the last un-flushed edit.
                    timelineStore.flushPendingSave()
                    // Guideline 2.5.4: the `audio` background mode may keep the session
                    // alive ONLY while something audible (or a recording) needs it. An
                    // idle engine would render silence forever — the classic "plays
                    // silent audio to stay alive" rejection signature, and a battery
                    // drain (real-time audio thread). stop() also deactivates the
                    // session with .notifyOthersOnDeactivation, giving other apps
                    // their audio back; the .active branch below restarts idempotently.
                    // `timelinePlayer.isPlaying` and `arrangementPlayer.isPlaying` are both
                    // constant-false today (neither `play(...)` has a production caller).
                    // They STAY: a redundant disjunct in an OR chain is not a lying choice
                    // the way the route-lost `if` above was — it cannot pick a wrong branch,
                    // only fail to add a `true` that is already covered. Editing a
                    // background-audio lifecycle guard for tidiness is the riskier move, and
                    // #132 Slice 5 removes the types outright.
                    let audioNeeded = transport.isPlaying
                        || beatPlayer.pattern.isPlaying
                        || timelinePlayer.isPlaying
                        || arrangementPlayer.isPlaying
                        || audioEngine.multiTrackRecorder.isRecording
                        || microphoneManager.isRecording
                        || audioEngine.isInputMonitoring
                        || polyVoice.activeVoiceCount > 0   // held MPE/performer notes
                    // The OUTCOME belongs in the diag file too, not only in os_log:
                    // during a long gap the founder's next question after "was it
                    // backgrounded?" is "did the engine go down, and did it come
                    // back?". Without these two lines the file marks the transition
                    // and stays silent on the one branch that produces silence.
                    if !audioNeeded {
                        audioEngine.stop()
                        log.log(.info, category: .system,
                                "App backgrounded — idle audio engine stopped (2.5.4)")
                        EchoelCrashLog.breadcrumb("scene: idle audio engine stopped (2.5.4)")
                    } else {
                        log.log(.info, category: .system, "App backgrounded — audio continues")
                        EchoelCrashLog.breadcrumb("scene: audio continues")
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
    }
}
#endif
