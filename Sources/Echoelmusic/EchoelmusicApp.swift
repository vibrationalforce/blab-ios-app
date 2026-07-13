#if canImport(SwiftUI)
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation   // AVAudioSession — Session-cue Latenzausgleich (outputLatency)
#endif

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
    /// Dedicated TOUCH-INSTRUMENT voice (founder 2026-07-08: the play surface's sound
    /// must be individually settable and must not glitch the bed). Its own pool means
    /// touch notes never steal a generative voice mid-sustain (the audible "glitch"),
    /// and its patch/morph are independent of the take. Small pool: 4 touches max.
    @State private var touchVoice: PolySynthVoice
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
    /// Parameter automation (master level / tempo) played over the shared transport.
    @State private var automationPlayer = AutomationPlayer()
    /// Selectable recording inputs (mic / interface / Bluetooth) with latency notes.
    @State private var audioInputs = AudioInputManager()
    /// Universal signal router (patchbay): typed routes across all channels, persisted.
    @State private var signalRouter = SignalRouter()
    /// AUv3 host: discovers installed plugins and loads an instrument into the graph.
    @State private var auHost = AUv3Host()
    /// The parameter-unification spine (U2c): one registry (queryable inventory)
    /// + one router (keyPath → live setter). Shared by the AUv3 host (hosted-plugin
    /// params register/bind on load) and the AutomationPlayer (extra registry lanes
    /// dispatch through it) — so per-track automation is identical for internal and
    /// hosted parameters. Constructed in init (router depends on registry).
    @State private var parameterRegistry: EchoelParameterRegistry
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
        // Parameter-unification spine (U2c): tiny control-plane objects, no I/O.
        // The registry seeds with the internal DDSP inventory; hosted-plugin params
        // join on load via AUv3Host's bridge. The router binds keyPath → live setter.
        let paramRegistry = EchoelParameterRegistry()
        paramRegistry.register(DDSPParameterCatalog.descriptors)
        _parameterRegistry = State(wrappedValue: paramRegistry)
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
        // B4/#21: the universal BLE heart-rate strap (0x180D). Wiring the
        // "Herzgurt (BLE)" source in the Patchbay starts the scan (this is the
        // user-initiated moment for the Bluetooth permission prompt); removing
        // the last route stops it. start/stop are idempotent. NEEDS-FOUNDER-
        // VERIFY with a real strap at the milestone.
        #if canImport(CoreBluetooth)
        if g.hasEnabledRoute(fromSource: "blehrs.in") {
            polarH10.start(publishing: bus)
        } else {
            polarH10.stop()
        }
        #endif
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
                touchVoice.attach(to: audioEngine)
                subBass.attach(to: audioEngine)
                metronome.attach(to: audioEngine)
                // Session breathing cue — attached BEFORE start like every voice
                // (build-1363 rule). Launch-silent until the user starts a session.
                sessionEngine.attach(to: audioEngine)

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
                // Same coherence for the timeline player: any Stop resets its follow-state.
                transport.addStopSubscriber("timeline") { [weak timelinePlayer] in
                    timelinePlayer?.handleTransportStopped()
                }
                bioVoice.start(subscribing: bus)
                polyVoice.start(subscribing: bus)
                leadVoice.start(subscribing: bus)
                touchVoice.start(subscribing: bus)   // touch notes breathe with the body too
                // Bio-reactive FX: bind to the melody voice's chain + bio bus and run
                // the ~30 Hz control loop (idle until the user adds modulation routes).
                fxModulator.attach(chain: polyVoice.fxChain, bus: bus)
                fxModulator.start()
                automationPlayer.wire(pattern: beatPlayer.pattern, audioEngine: audioEngine, voice: polyVoice)
                pianoRoll.start(pattern: beatPlayer.pattern, voice: polyVoice, lead: leadVoice, subVoice: subBass, midiOut: midiOut, arrangement: arrangementPlayer, bus: bus, auHost: auHost, automation: automationPlayer, timeline: timelinePlayer)
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
                // Parameter-unification spine (U2c): the host registers + binds a
                // loaded plugin's parameters into this registry/router, and the
                // AutomationPlayer dispatches its extra registry lanes through the
                // SAME router — so a hosted plugin's knobs are automatable in the
                // track exactly like Echoel's own.
                auHost.useParameters(registry: parameterRegistry, router: parameterRouter)
                automationPlayer.wire(router: parameterRouter)

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
                    await store.updateEntitlements()
                }
                #if canImport(CoreLocation)
                // Opt-in place token: attach feeds the session name; resolve()
                // only acts when the user has the toggle ON (default OFF).
                locationNamer.attach(session: sessionContext)
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
