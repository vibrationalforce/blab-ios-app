#if canImport(AVFoundation)
import AVFoundation
import SwiftUI
import Accelerate
import Observation

/// Manages microphone access and advanced audio processing
/// Now includes FFT for frequency detection and professional-grade DSP
@MainActor
@Observable
final class MicrophoneManager: NSObject {

    // MARK: - Observed Properties

    /// Current audio level (0.0 to 1.0)
    var audioLevel: Float = 0.0

    /// Detected frequency in Hz (fundamental pitch from FFT)
    var frequency: Float = 0.0

    /// Current pitch in Hz (fundamental frequency from YIN algorithm)
    var currentPitch: Float = 0.0

    /// Whether we have microphone permission
    var hasPermission: Bool = false

    /// Whether the user explicitly denied microphone permission
    var permissionDenied: Bool = false

    /// Whether we're currently recording
    var isRecording: Bool = false

    /// Audio buffer for waveform visualization (last 512 samples)
    var audioBuffer: [Float]? = nil

    /// FFT magnitudes for spectral visualization (256 bins)
    var fftMagnitudes: [Float]? = nil


    // MARK: - Private Properties

    /// The audio engine that processes audio input
    @ObservationIgnored nonisolated(unsafe) private var audioEngine: AVAudioEngine?

    /// The input node that captures microphone data
    @ObservationIgnored private var inputNode: AVAudioInputNode?

    /// FFT setup for frequency analysis
    private var complexDFT: EchoelComplexDFT?

    /// Buffer size for FFT (power of 2)
    /// Reduced from 2048 to 1024 for lower latency (46ms → 23ms)
    /// Trade-off: frequency resolution 21.5Hz → 43Hz per bin (still acceptable)
    private let fftSize = 1024

    /// Sample rate (will be set from audio format)
    private var sampleRate: Double = AudioConfiguration.preferredSampleRate

    /// Pitch detection disabled (PitchDetector removed in soundscape refactor)

    /// Dedicated queue for FFT/pitch processing — keeps audio render thread unblocked
    private let processingQueue = DispatchQueue(label: "com.echoelmusic.audio.processing", qos: .userInteractive)

    // MARK: - Pre-allocated FFT Buffers (avoid per-callback allocation)

    /// Pre-allocated buffers for FFT processing — reused every callback
    private var fftRealParts: [Float]
    private var fftWindow: [Float]
    private var fftWindowedParts: [Float]
    private var fftImagZeros: [Float]
    private var fftMagnitudesBuffer: [Float]
    private var fftVisualMagnitudes: [Float]
    private var capturedBufferStorage: [Float]

    // MARK: - Initialization

    override init() {
        // Pre-allocate FFT buffers to avoid per-callback heap allocation
        self.fftRealParts = [Float](repeating: 0, count: fftSize)
        self.fftWindow = [Float](repeating: 0, count: fftSize)
        self.fftWindowedParts = [Float](repeating: 0, count: fftSize)
        self.fftImagZeros = [Float](repeating: 0, count: fftSize)
        self.fftMagnitudesBuffer = [Float](repeating: 0, count: fftSize / 2)
        self.fftVisualMagnitudes = [Float](repeating: 0, count: 256)
        self.capturedBufferStorage = [Float](repeating: 0, count: 512)

        super.init()

        // Pre-compute Hann window once (never changes)
        vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        checkPermission()
    }


    // MARK: - Permission Handling

    /// Read the CURRENT system permission state into both flags.
    ///
    /// ⛔ #895 — `permissionDenied` USED TO BE WRITTEN ONLY BY THE REQUEST CALLBACK, so at
    /// launch it read `false` for a user who had denied the microphone in an earlier
    /// session: a flag that says "not denied" while the system says denied. Nothing caught
    /// it because the flag had ZERO readers repo-wide (the other `permissionDenied` hits are
    /// `CameraRPPGBioPublisher`'s, a different type). An unread flag cannot be observed to
    /// lie — which is why its first reader has to arrive together with its repair.
    ///
    /// ⭐ The shape is BORROWED, not invented: `CameraRPPGBioPublisher` derives its own
    /// `permissionDenied` straight from the authorization status. The camera adds
    /// `.restricted`; `AVAudioApplication.recordPermission` has no such case, so `.denied`
    /// is the whole of it here.
    ///
    /// ⚠️ On macOS/watchOS/tvOS `hasPermission` is hard-coded false and the state is simply
    /// UNKNOWN — `permissionDenied` stays false there on purpose. "Unknown" and "denied"
    /// are different, and a surface that says "access is off" on a platform that never asked
    /// would be inventing a fact.
    private func checkPermission() {
        #if os(macOS)
        hasPermission = false // macOS handles mic permission via system dialog on first use
        permissionDenied = false
        #elseif os(watchOS) || os(tvOS)
        hasPermission = false
        permissionDenied = false
        #else
        if #available(iOS 17.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            hasPermission = status == .granted
            permissionDenied = status == .denied
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                hasPermission = true
                permissionDenied = false
            case .denied:
                hasPermission = false
                permissionDenied = true
            case .undetermined:
                hasPermission = false
                permissionDenied = false
            @unknown default:
                hasPermission = false
                permissionDenied = false
            }
        }
        #endif
    }

    /// Request microphone permission from the user
    func requestPermission() {
        #if os(macOS) || os(watchOS) || os(tvOS)
        log.audio("Microphone permission request not supported on this platform", level: .warning)
        #else
        if #available(iOS 17.0, *) {
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                await MainActor.run {
                    self.hasPermission = granted
                    if granted {
                        log.audio("Microphone permission granted")
                        self.permissionDenied = false
                        // #825: a bare `upgradeToPlayAndRecord()` stood here (and in the
                        // legacy branch below) ON THE GRANT — an OWNERLESS raise of the
                        // shared session. The ownership Set cannot see it, so nothing
                        // ever lowered it: grant once, and the whole app could sit on
                        // `.playAndRecord` for the rest of the session while the user
                        // only PLAYS. Permission is consent, not use — every real mic
                        // use claims for itself (`startRecording`, `setInputMonitoring`,
                        // `MultiTrackRecorder`), each with a release on every exit.
                    } else {
                        log.audio("Microphone permission denied", level: .error)
                        self.permissionDenied = true
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                // Permission callback runs on arbitrary queue — DispatchQueue.main.async
                // avoids Swift 6 dispatch_assert_queue_fail
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    if granted {
                        log.audio("Microphone permission granted")
                        self?.permissionDenied = false
                        // #825: same removal as the iOS 17+ branch above — see there.
                    } else {
                        log.audio("Microphone permission denied", level: .error)
                        self?.permissionDenied = true
                    }
                }
            }
        }
        #endif
    }


    // MARK: - Recording Control

    /// Start recording audio from the microphone
    func startRecording() {
        // #895: re-read the SYSTEM before deciding. `checkPermission()` otherwise runs once,
        // in `init`, so a user who fixed the permission in Settings and came back was still
        // refused on the next tap and only got through on the one after — the request call
        // below happens to return the granted status immediately, which made the staleness
        // self-healing and therefore invisible. One property read, on a user gesture.
        checkPermission()
        guard hasPermission else {
            log.audio("⚠️ Cannot start recording: No microphone permission", level: .warning)
            requestPermission()
            return
        }
        // AU4 re-entry guard: a second startRecording() would overwrite `audioEngine`
        // while the previous engine is still running with its input tap installed —
        // leaking it (and its tap → processExtractedAudio) and contending for the input
        // node ("alles still" class, #22). One recorder at a time; stop before restart.
        guard !isRecording else {
            log.audio("MicrophoneManager: startRecording ignored — already recording")
            return
        }

        do {
            // #859b: the voice-timbre chain (VoiceCaptureController → here) was the
            // last diag-dark path that does INPUT work while the master engine runs —
            // category flip + own engine + inputNode tap, zero exported lines. Every
            // rung below lands in echoel_diag.log so a crash in this chain names its
            // step (the #854/#859 discipline; discrete user events, never tick-rate).
            EchoelCrashLog.breadcrumb("mic: start 1/3 — claiming record route")
            // The app's DEFAULT session is .playback (output only) so it never
            // drags other apps' Bluetooth audio down to HFP call quality. Recording
            // needs the mic, so upgrade to .playAndRecord HERE — the moment the user
            // actually records. (#825: `requestPermission` no longer upgrades at
            // grant time at all — this claim is the one that raises the route.)
            // .playAndRecord — not .record — keeps the synth output alive alongside
            // the mic.
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            if !AudioConfiguration.isSessionConfigured {
                try AudioConfiguration.configureAudioSession()
            }
            // #299: claim the route as an OWNER. The stop side used to lower it
            // unconditionally, which cut live input monitoring; now the route only comes down
            // when this recorder is the last holder.
            try AudioConfiguration.claimRecordRoute(.microphoneManager)
            #endif

            // Create and configure the audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                log.error("MicrophoneManager: failed to create AVAudioEngine", category: .audio)
                // #889: RELEASE BEFORE RETURNING. This exit and the one below `return` from
                // inside the `do`, so the `catch` at the bottom — the one #299 added — never
                // runs for them. Both are UNREACHABLE today and are fixed anyway, because the
                // hazard is a CLASS: `AVAudioEngine()` is non-failable, so this optional
                // cannot be nil, and the format guard below reads an input node assigned one
                // line earlier from a non-optional property. What makes them worth closing is
                // that a leak here is SILENT and STICKY — the owner set never empties, so
                // switching monitoring off afterwards finds a non-empty set and never returns
                // the session to `.playback`. That is the founder-visible A2DP-to-HFP
                // degradation, and it keeps the input bus up in the neighbourhood of the
                // `isInputConnToConverter` family.
                #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                try? AudioConfiguration.releaseRecordRoute(.microphoneManager)
                #endif
                return
            }

            EchoelCrashLog.breadcrumb("mic: start 2/3 — tapping input")
            inputNode = audioEngine.inputNode

            // Get the input format from the microphone
            let recordingFormat = inputNode?.outputFormat(forBus: 0)
            guard let format = recordingFormat else {
                // ⭐ #910 — THIS EXIT WAS SILENT, AND THE MARKER BELOW MADE THAT EXPENSIVE.
                // `log.error` is os_log, which never reaches the exported `echoel_diag.log`,
                // so this returned writing NOTHING while `mic: start 2/3` stood as the last
                // line. That was tolerable while `2/3`-last meant "one of three things"; it
                // is not now that the marker below makes `2/3`-last mean "died in the node or
                // format read". Its sibling one guard down has written `mic: start REFUSED`
                // since #890; this one now does too. Unnumbered, like every skip that ends
                // its ladder before any further rung (#907).
                EchoelCrashLog.breadcrumb("mic: start REFUSED — no input format from the node")
                log.error("MicrophoneManager: failed to get microphone input format", category: .audio)
                // #889, same reasoning as the guard above — see it for why an unreachable
                // exit is still closed.
                #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                try? AudioConfiguration.releaseRecordRoute(.microphoneManager)
                #endif
                return
            }

            // ⛔ #890 — THE NIL CHECK ABOVE IS NOT THE FAILURE THIS READ ACTUALLY HAS, and the
            // sibling path has known that since #823. Right after the record route is claimed
            // the input node can still hand back its PLACEHOLDER format — the I/O unit rebuilds
            // lazily on `start()` — and a placeholder is `0 Hz / 0 ch`, which is NOT nil. So it
            // walks past `guard let`, gets stored as `sampleRate`, is baked into the tap
            // closure as `capturedSampleRate`, and is handed to `installTap(format:)`.
            //
            // That last step is the one that kills the process: an invalid format raises an
            // ObjC exception, which no Swift `catch` sees — `AudioEngine.setInputMonitoring`
            // says exactly this at its own #823 fallback, and it is the signature of the
            // `isInputConnToConverter` family the diag ladder was built for. This chain is
            // reachable: Sound panel → Voice timbre → capture claims the route and reads the
            // format 28 lines later, inside that window.
            //
            // ⚠️ WHY THIS IS A HARD GUARD AND NOT #823's SESSION FALLBACK — the distinction is
            // the whole judgement here, so it is written down rather than left implicit. #823
            // substitutes a session-derived format for `connect(...)`, where a format that
            // matches the hardware is by definition acceptable. `installTap(onBus:format:)` is
            // a DIFFERENT contract: the format must match the BUS's own format, so handing it a
            // format the node did not report is not the proven fix being reused — it is that
            // fix extended into territory nobody here can test. Refusing to start is strictly
            // safe: it turns an uncatchable abort into a logged, recoverable no-start, and it
            // never lies about having captured anything.
            //
            // NEEDS-FOUNDER-VERIFY: open Sound panel → Voice timbre → capture immediately after
            // launch, twice in a row. If a take ever refuses with "input format not ready", the
            // log now says so instead of the app dying — and the numbers on that line say
            // whether the hardware was absent or merely late, which is what decides the
            // follow-up slice (a retry after `prepare()`, or nothing).
            // ⭐ #891 made this probe ANSWERABLE WITHOUT THE LOG: the caller used to sit on
            // "0 %" forever after a refusal, which on a phone is indistinguishable from a
            // hang. The row now returns to Capture and says "The microphone did not start".
            // So the founder's report is one of three, not two: it worked · it refused
            // visibly (that sentence appeared) · something else. Same ask, one place (#790).
            guard format.sampleRate > 0, format.channelCount > 0 else {
                // ⚠️ `let` IN BOTH ARMS, not a `var` declared outside the `#if`. On macOS the
                // iOS arm is removed at parse time, so an outer `var` is initialised once,
                // read twice and never written — `variable was never mutated`, and
                // `Package.swift` compiles with `-warnings-as-errors`. Neither CI gate would
                // have caught it (both build for the iOS simulator only); the command that
                // would is `swift build`, which CLAUDE.md's SESSION START ritual prescribes.
                // This is also the only place in `Sources/` that wanted that shape — no
                // precedent to lean on, so it takes the plain one.
                #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                let session = AVAudioSession.sharedInstance()
                let sessionDetail = """
                    session \(session.sampleRate) Hz/\(session.inputNumberOfChannels) ch, \
                    inputAvailable \(session.isInputAvailable)
                    """
                #else
                let sessionDetail = "session unavailable on this platform"
                #endif
                EchoelCrashLog.breadcrumb("""
                    mic: start REFUSED — input format not ready \
                    (node \(format.sampleRate) Hz/\(format.channelCount) ch, \
                    \(sessionDetail)) — #890
                    """)
                log.error("""
                    MicrophoneManager: input node reported a placeholder format \
                    (\(format.sampleRate) Hz, \(format.channelCount) ch) — refusing to tap
                    """, category: .audio)
                // ⚠️ NIL BOTH REFS BEFORE RETURNING, and this is not tidiness. `stopRecording`'s
                // ⚠️ TRAP note below states an invariant this exit would otherwise falsify:
                // "the already-stored `inputNode?` property … is non-nil only when a tap was
                // installed". `inputNode` is assigned well ABOVE this guard, so a refusal would
                // leave it non-nil with NO tap — and that note exists precisely to license a
                // future symmetry fix that uses `inputNode?` as the "was a tap installed"
                // proxy. Following it against this state would call `removeTap` on a
                // never-started engine, which the same note names as the
                // `isInputConnToConverter` family. A comment with a false premise is worse
                // than none (#167's lesson), so the state is corrected rather than the note.
                // ⚠️ `self.` IS REQUIRED HERE AND IS NOT STYLE. The guard 60 lines up is
                // `guard let audioEngine = audioEngine`, which binds a LOCAL `let` that
                // shadows the property for the rest of this scope — a bare `audioEngine = nil`
                // assigns to that constant and does not compile ("cannot assign to value:
                // 'audioEngine' is a 'let' constant"). It cost a red `Xcode Compile Check`,
                // because none of the text-level checks available here can see a type error;
                // CI is the only compiler in this repo. `inputNode` is not shadowed, but it
                // takes the same prefix so the pair reads as one intent.
                self.audioEngine = nil
                self.inputNode = nil
                #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                try? AudioConfiguration.releaseRecordRoute(.microphoneManager)
                #endif
                return
            }

            // Store sample rate for frequency calculation
            sampleRate = format.sampleRate

            // Setup FFT
            complexDFT = EchoelComplexDFT(size: fftSize)

            // Install a tap to capture audio data — dispatch off the audio render thread
            // Capture sampleRate locally to avoid reading @MainActor property from Sendable closure
            let capturedSampleRate = sampleRate
            // Tap runs on audio thread — do NOT access @MainActor self in outer closure.
            // nonisolated(unsafe) avoids Swift 6 actor isolation check on audio thread.
            nonisolated(unsafe) weak var weakSelf = self
            // ⭐ #910 — the same split as `AudioEngine`'s, and the STRONGER half of the two.
            // `mic: start 2/3` is the last line before THREE things: the `inputNode` access,
            // the `outputFormat` read, and this `installTap`. `installTap(format:)` is the one
            // call in either file whose contract mismatch raises an ObjC exception nothing can
            // catch, and #890's comment already names it as the likeliest abort —
            // `isInputConnToConverter` is an assertion about connecting the input bus to a
            // CONVERTER, which is what installing a tap WITH A FORMAT does. With this line,
            // `2/3` last ⇒ the two reads; this line last ⇒ the tap install.
            //
            // ⚠️ THE OTHER SIDE OF THE SPLIT IS NOT CLEAN, and #910 raises the cost of that:
            // the `guard let format = recordingFormat else` exit above writes NOTHING to the
            // exported log (only `log.error`, which never reaches `echoel_diag.log`). It is
            // documented unreachable (#889) — but `2/3` last is now being read as "died in the
            // node/format read", so a silent exit there would be read as a crash. Its sibling
            // one guard down writes `mic: start REFUSED`; this one should too, and does not.
            //
            // ⚠️ Unnumbered, so the `mic: start` ladder stays 1..3. ⛔ NOT because "older logs
            // still read" — the first draft said that and it is false in the other direction:
            // this ladder DID ship in v429, and that log carried no `mic:` line at all. The
            // reason is that `total` is a completeness contract, and a positional marker is
            // not a step of a fixed-length sequence.
            EchoelCrashLog.breadcrumb("mic: start — installing the tap now")
            inputNode?.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { @Sendable buffer, _ in
                // Extract all buffer data synchronously while memory is valid
                // AVAudioPCMBuffer is non-Sendable — its memory is reused after this closure returns
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return }
                let channelDataPtr = channelData.pointee
                // Note: Array allocation in installTap is acceptable — this is NOT the render block.
                // The tap runs on a separate I/O thread with more tolerance than internalRenderBlock.
                let samples = Array(UnsafeBufferPointer(start: channelDataPtr, count: frameLength))
                // DispatchQueue.main.async bypasses Swift concurrency runtime entirely —
                // Task { @MainActor } crashes on audio thread (dispatch_assert_queue_fail)
                DispatchQueue.main.async {
                    weakSelf?.processExtractedAudio(samples, frameLength: frameLength, sampleRate: capturedSampleRate)
                }
            }

            // #860b — the #860 rule reaches here too (reviewer C): `prepare()` is an
            // AVFAudio graph call and it sat AHEAD of the rung, so a death inside it
            // logged `mic: start 2/3` and read as "never reached the start". Wording
            // UNCHANGED while moving — a guard anchors on this exact literal (#655/#656).
            EchoelCrashLog.breadcrumb("mic: start 3/3 — starting capture engine")
            audioEngine.prepare()
            try audioEngine.start()

            self.isRecording = true

            EchoelCrashLog.breadcrumb("mic: capture running")
            log.audio("🎙️ Recording started with FFT enabled")

        } catch {
            EchoelCrashLog.breadcrumb("mic: start FAILED (\(error.localizedDescription))")
            log.audio("❌ Failed to start recording: \(error.localizedDescription)", level: .error)
            self.isRecording = false

            // #900 — THE THROWING EXIT LEFT ITS HALF-BUILT GRAPH BEHIND, and the honest
            // severity is smaller than it sounds. The `stopRecording()` TRAP note (#877)
            // already weighed this exact state and calls it harmless: the tap dies with the
            // engine, and `startRecording()` always builds a FRESH `AVAudioEngine`. What
            // #891 CHANGED is who cleans up. Before it, the user's unavoidable cancel ran
            // `stopRecording()` and that nilled all three; since #891 the abort path returns
            // without one. Lifetime, not a crash path.
            //
            // ⛔ #901 — "an FFT scratch allocation … until the next start" stood here and BOTH
            // halves were wrong, in the direction that under-sells the repair. `EchoelComplexDFT`
            // wraps a `vDSP_DFT_zop_CreateSetup` HANDLE, destroyed by `vDSP_DFT_DestroySetup` in
            // its own `deinit` — this returns a vDSP setup, not just memory. And the two
            // lifetimes differ: the ENGINE is replaced by the next attempt (`AVAudioEngine()`
            // near the top of this `do`), while `complexDFT` is assigned only PAST the
            // placeholder-format guard (#890), so a run of format refusals would have kept the
            // old setup alive indefinitely.
            //
            // ⚠️ AND THIS IS AN UNRUNGED AVFAudio DEALLOCATION, exactly the kind `stopRecording()`
            // warns about above its own `audioEngine = nil`: dropping the last strong reference
            // runs `AVAudioEngine.deinit` — here on an engine that still has a tap installed —
            // and no rung stands in front of it. So in a diag log, silence AFTER
            // `mic: start FAILED` is NOT automatically the route release two blocks below; it can
            // be this line. Attribute it to the deallocation first.
            //
            // ⚠️ THE TAP IS DELIBERATELY NOT REMOVED, and that is the whole discipline of
            // this block. Only `audioEngine.start()` can throw after the tap is installed,
            // so the engine here is NEVER running — and `stopRecording()` removes the tap
            // ONLY under `engine.isRunning` for exactly that reason: touching `inputNode`
            // on a dead engine is the `isInputConnToConverter` family, seven device logs
            // deep and still without a named trigger. Dropping the reference is safe;
            // reaching into the node is not.
            self.audioEngine = nil
            self.inputNode = nil
            self.complexDFT = nil
            // ⭐ #299 Nachlese — THE THROWING EXIT THAT CLAIMED WITHOUT RELEASING, and the
            // sentence that let it through was in the design note: "a Set is idempotent in both
            // directions, which makes the failure paths safe to write as a plain release". A Set
            // makes a DUPLICATE release safe. It does nothing about a MISSING one — that leaks
            // exactly like the refcount the note rejects. Note also that `claimRecordRoute` at
            // the top of this `do` can itself throw and land HERE, so both a failed
            // `audioEngine.start()` and a failed session upgrade strand `.microphoneManager` in
            // the owner set: monitoring off afterwards would then find a non-empty set and never
            // return the route to `.playback`. The other two owners avoid this by catching their
            // claim locally; this one propagates, which is why it needs the release here.
            //
            // ⛔ #299 WROTE "THE ONE REACHABLE EXIT" AND THAT WAS TOO STRONG (#889). It was the
            // only THROWING one. Two further exits claim and leave without releasing — the two
            // `guard … else { return }` blocks above — and a `return` from inside a `do` never
            // reaches this `catch`. Both are unreachable today (their optionals were just
            // assigned from non-failable sources), so #299 fixed the live bug correctly; the
            // superlative is what would have stopped the next reader from looking. Both are
            // closed as of #889. THE LESSON, and it is why the wording is corrected rather than
            // the count bumped: "the one X" is a claim about the WHOLE function, and it ages the
            // moment anyone adds an exit — while "the throwing one" stays true forever.
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            try? AudioConfiguration.releaseRecordRoute(.microphoneManager)
            #endif
        }
    }

    /// #877: the three states rung 1 must distinguish. `engine?.isRunning == true`
    /// collapsed the first two, and the first is by far the most common — see the
    /// ⛔ block inside `stopRecording()` for why that mattered.
    ///
    /// ⚠️ Reading `isRunning` costs an ObjC dispatch into AVFAudio (which takes the
    /// engine's own lock), so this is main-actor teardown code ONLY. It must never be
    /// called from a tap block or a render path.
    private static func engineState(_ engine: AVAudioEngine?) -> String {
        guard let engine else { return "engine: none" }
        return engine.isRunning ? "engine: running" : "engine: stopped"
    }

    /// Stop recording audio
    func stopRecording() {
        // #876: this teardown carried ONE rung for a multi-step tear-down, so a death
        // anywhere inside it wrote that same line and then silence — and the silence
        // could not say WHICH step died. `engine.inputNode` is the node the recurring
        // `isInputConnToConverter` abort is NAMED after, so it gets a rung of its own.
        // Ladder law (#862b): a rung stands BEFORE its call, never after.
        //
        // ⚠️ THE LADDER IS NOT EXHAUSTIVE, and saying so is the point (the enumeration
        // lesson): dropping `audioEngine` to nil deallocates an AVAudioEngine, and that
        // deinit is AVFAudio work with no rung in front of it. Silence between rung 2
        // and rung 3 therefore covers the deallocation as well as the nil-outs — read
        // it as "somewhere in teardown", not as "in the route release".
        // ⛔ #877 — TWO SELF-CONTRADICTIONS OF #876's OWN RUNG, both found by the
        // audio-thread reviewer, both about the LADDER lying rather than the audio.
        //
        // (1) #876 hoisted `let engine = audioEngine` to FUNCTION scope so the rung could
        //     report the state. That extra strong reference moves the AVAudioEngine's
        //     DEALLOCATION past rung 3 (under -Onone certainly; under -O the optimizer
        //     MAY sink the release to last use, so the point becomes build-dependent) —
        //     while the comment three lines above told the reader to attribute silence
        //     there to the route release. A ladder whose prose mis-attributes silence is
        //     worse than no ladder. The state is read INLINE now; the strong reference
        //     dies exactly where it always did, at `audioEngine = nil` below, which makes
        //     the "not exhaustive" note above true again instead of inverted.
        //
        // (2) `running: \(engine?.isRunning == true)` printed `false` for BOTH "no engine
        //     at all" and "engine present but stopped" — the two cases a reader must tell
        //     apart. The dominant caller is `AudioEngine.stop(reason:)`, which tears the
        //     mic down on EVERY master stop, and there the mic engine is usually nil and
        //     no teardown happens at all. Collapsing those made the common no-op look
        //     identical to the interesting case. Three states, three words.
        EchoelCrashLog.breadcrumb(
            "mic: stop 1/3 — stopping capture engine (\(Self.engineState(audioEngine)))")
        // Safely stop the audio engine.
        //
        // ⚠️ TRAP FOR THE NEXT SESSION (#877, audio-thread reviewer) — this repo removes
        // taps UNCONDITIONALLY everywhere else (`MultiTrackRecorder`, `RetroCapture`,
        // which documents its removal as idempotent); this is the one site that gates
        // removal on `isRunning`.
        //
        // ⛔ #901 — THE SCENARIO THIS NOTE NAMED IS UNREACHABLE AT THIS SITE SINCE #900, and a
        // "do not touch" note with a false premise is worse than none (#167): the next session
        // cannot disprove it. It read "a `start()` that THREW leaves a tapped, non-running
        // engine whose tap is never removed" — true until #900, which made that `catch` drop
        // the engine itself, so `stopRecording()` never meets it any more. The GUIDANCE below
        // survives untouched, and one half of it got STRONGER: `inputNode?` is now an even more
        // reliable "was a tap installed" signal, because a thrown start nils it too. What still
        // reaches the `isRunning` branch is an engine stopped by an INTERRUPTION or a
        // media-services reset while `isRecording` is still true — which is why the three-state
        // rung above keeps "engine: stopped".
        //
        // If you ever make the removal unconditional, do NOT hoist
        // `engine.inputNode.removeTap(onBus: 0)` out of this guard: touching `inputNode`
        // on an engine that never started, while the session may no longer be
        // `.playAndRecord`, IS the `isInputConnToConverter` family. Use the already-stored
        // `inputNode?` property instead — it is non-nil only when a tap was installed.
        // Separate slice, and device-unproven either way.
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            EchoelCrashLog.breadcrumb("mic: stop 2/3 — removing input tap")
            engine.inputNode.removeTap(onBus: 0)
        }

        audioEngine = nil
        inputNode = nil

        // Release FFT wrapper
        complexDFT = nil

        // AU4: return the SHARED session to the app's default .playback WITHOUT
        // deactivating it. The master output engine owns the process-wide session —
        // the old `setActive(false)` here tore it down under the master and cut ALL
        // app audio ("alles still" class, #22). The symmetric inverse of the
        // start-side `upgradeToPlayAndRecord` keeps output alive + restores A2DP.
        //
        // #299: released as an OWNER, not lowered outright. This unconditional downgrade was
        // the one place that DID return the route — and because it was unconditional it also
        // yanked it away from input monitoring running at the same time.
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        // Rung 3 sits INSIDE the platform guard on purpose: on a platform without an
        // AVAudioSession there is no route to release, and a rung that announces a step
        // which never runs is the same lie as a rung that trails its call.
        EchoelCrashLog.breadcrumb("mic: stop 3/3 — releasing record route")
        do {
            try AudioConfiguration.releaseRecordRoute(.microphoneManager)
        } catch {
            log.audio("Failed to downgrade audio session after recording: \(error.localizedDescription)", level: .warning)
        }
        #endif

        self.isRecording = false
        self.audioLevel = 0.0
        self.frequency = 0.0
        self.currentPitch = 0.0

        log.audio("⏹️ Recording stopped")
    }


    // MARK: - Audio Processing with FFT

    /// EchoelVoice #592b: while a voice capture runs, every extracted sample block is
    /// ALSO handed here (main thread — this rides the existing per-buffer hop, adding
    /// zero new thread crossings; the per-buffer hop itself is trap 2 of
    /// `scratchpads/PLAN_ECHOEL_VOICE.md`, pre-existing and unchanged by this slice).
    /// Set by `VoiceCaptureController` for the duration of a capture, nil otherwise.
    var captureSampleSink: (([Float], Double) -> Void)?

    /// Process pre-extracted audio samples with FFT for frequency detection
    /// Called with data copied synchronously from AVAudioPCMBuffer while memory was valid
    private func processExtractedAudio(_ samples: [Float], frameLength: Int, sampleRate: Double) {
        captureSampleSink?(samples, sampleRate)
        // Calculate RMS (amplitude/volume) from copied samples
        var sumSquares: Float = 0.0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_measqv(base, 1, &sumSquares, vDSP_Length(frameLength))
        }
        let rms = sqrt(sumSquares)

        // Normalize to 0-1 range with better sensitivity
        let normalizedLevel = min(rms * 15.0, 1.0)

        // Capture audio buffer for waveform visualization (last 512 samples)
        let bufferSampleCount = min(512, frameLength)
        let capturedBuffer = Array(samples.prefix(bufferSampleCount))

        // Perform FFT for frequency detection and get magnitudes
        let (detectedFrequency, magnitudes) = samples.withUnsafeBufferPointer { ptr -> (Float, [Float]) in
            guard let base = ptr.baseAddress else { return (0, []) }
            return performFFT(on: base, frameLength: frameLength, sampleRate: sampleRate)
        }

        // Pitch detection disabled (soundscape refactor)
        let detectedPitch: Float = 0

        // Smooth audio level changes
        self.audioLevel = self.audioLevel * 0.7 + normalizedLevel * 0.3

        // Smooth frequency changes (only update if significantly different)
        if detectedFrequency > 50 { // Ignore very low frequencies (likely noise)
            self.frequency = self.frequency * 0.8 + detectedFrequency * 0.2
        }

        // Smooth pitch changes (YIN is more robust than FFT for voice)
        if detectedPitch > 0 {
            self.currentPitch = self.currentPitch * 0.8 + detectedPitch * 0.2
        } else {
            // Decay pitch to zero if no pitch detected
            self.currentPitch *= 0.9
        }

        // Update audio buffer and FFT magnitudes for visualizations
        self.audioBuffer = capturedBuffer
        self.fftMagnitudes = magnitudes
    }

    /// Perform FFT to detect fundamental frequency and return magnitudes
    /// Uses pre-allocated buffers (fftRealParts, fftWindowedParts, etc.) to avoid
    /// per-callback heap allocation on the processing queue.
    private func performFFT(on data: UnsafePointer<Float>, frameLength: Int, sampleRate: Double) -> (frequency: Float, magnitudes: [Float]) {
        guard let dft = complexDFT else { return (0, []) }

        // Zero-fill pre-allocated buffer, then copy audio data
        memset(&fftRealParts, 0, fftSize * MemoryLayout<Float>.size)
        let copyLength = min(frameLength, fftSize)
        memcpy(&fftRealParts, data, copyLength * MemoryLayout<Float>.size)

        // Apply pre-computed Hann window to reduce spectral leakage
        vDSP_vmul(fftRealParts, 1, fftWindow, 1, &fftWindowedParts, 1, vDSP_Length(fftSize))

        // Perform FFT via EchoelComplexDFT (handles overlapping access safety internally)
        let result = dft.forward(real: fftWindowedParts, imag: fftImagZeros)
        let realParts = result.real
        let imagParts = result.imag

        // Calculate magnitudes (power spectrum) into pre-allocated buffer
        let halfSize = fftSize / 2
        for i in 0..<halfSize {
            fftMagnitudesBuffer[i] = sqrt(realParts[i] * realParts[i] + imagParts[i] * imagParts[i])
        }

        // Downsample magnitudes for visualization (256 bins for spectral mode)
        let visualBins = 256
        let binRatio = Swift.max(1, halfSize / visualBins)
        for i in 0..<visualBins {
            let startIdx = i * binRatio
            let endIdx = min(startIdx + binRatio, halfSize)
            guard startIdx < halfSize else { break }
            var sum: Float = 0
            for j in startIdx..<endIdx {
                sum += fftMagnitudesBuffer[j]
            }
            fftVisualMagnitudes[i] = sum / Float(binRatio)
        }

        // Find peak frequency (ignore DC component at index 0)
        guard halfSize > 1 else { return (0, Array(fftVisualMagnitudes)) }
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0

        let searchBuffer = Array(fftMagnitudesBuffer[1...])
        vDSP_maxvi(searchBuffer, 1, &maxMagnitude, &maxIndex, vDSP_Length(halfSize - 1))
        maxIndex += 1 // Adjust for skipping index 0

        // Convert bin index to frequency
        let frequency = Float(maxIndex) * Float(sampleRate) / Float(fftSize)

        // Return copy of visual magnitudes for UI (must be independent of mutable buffer)
        let visualResult = Array(fftVisualMagnitudes)

        // Only return frequencies in audible/useful range
        if frequency > 50 && frequency < 2000 && maxMagnitude > 0.01 {
            return (frequency, visualResult)
        }

        return (0.0, visualResult)
    }


    // MARK: - Cleanup

    /// Clean up when the object is destroyed
    deinit {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
    }
}

// MARK: - Settings Utility

/// Open iOS Settings app to allow the user to re-enable denied permissions.
@MainActor
func openAppSettings() {
    #if os(iOS)
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
    #endif
}
#endif
