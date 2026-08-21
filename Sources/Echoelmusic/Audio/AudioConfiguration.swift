#if canImport(AVFoundation)
import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit          // applicationState — the interruption-resume foreground gate
#endif

/// Audio configuration constants and optimization settings
/// Target: < 5ms latency for real-time performance
enum AudioConfiguration {

    // MARK: - Sample Rate

    /// Preferred sample rate (48 kHz for pro audio)
    static let preferredSampleRate: Double = 48000.0

    /// Float version for DSP APIs that require Float
    static let preferredSampleRateFloat: Float = 48000.0

    /// Fallback sample rate if 48kHz unavailable
    static let fallbackSampleRate: Double = 44100.0

    // MARK: - Default BPM

    /// Default tempo (120 BPM industry standard)
    static let defaultBPM: Double = 120.0

    /// Float version for DSP APIs
    static let defaultBPMFloat: Float = 120.0


    // MARK: - Buffer Configuration

    /// Ultra-low latency buffer size (128 frames)
    /// At 48kHz: 128/48000 = 2.67ms latency
    static let ultraLowLatencyBufferSize: AVAudioFrameCount = 128

    /// Low latency buffer size (256 frames)
    /// At 48kHz: 256/48000 = 5.33ms latency
    static let lowLatencyBufferSize: AVAudioFrameCount = 256

    /// Normal buffer size (512 frames) - better for battery
    /// At 48kHz: 512/48000 = 10.67ms latency
    static let normalBufferSize: AVAudioFrameCount = 512

    /// Current buffer size (defaults to the 512-frame / 10.67 ms "normal" buffer).
    /// Audio thread + main thread access — nonisolated(unsafe) because writes are
    /// always followed by a full session reconfiguration (memory barrier).
    ///
    /// Was `lowLatencyBufferSize` (256 / 5.33 ms): too tight a render deadline for the
    /// polyphonic additive synth under dense chords → underruns heard as dropouts /
    /// crackle ("Aussetzer / Kratzen", 10.76.49). 512 doubles the deadline to 10.67 ms,
    /// still well inside the app's <15 ms latency FAIL line. `LatencyMode.low` can still
    /// opt back into 256 on capable hardware.
    nonisolated(unsafe) static var currentBufferSize: AVAudioFrameCount = normalBufferSize

    /// Calculate IO buffer duration for AVAudioSession
    static func ioBufferDuration(for sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0 else { return Double(currentBufferSize) / preferredSampleRate }
        return Double(currentBufferSize) / sampleRate
    }


    // MARK: - Audio Format

    /// Standard audio format for processing
    /// 32-bit float, interleaved, stereo
    static func standardFormat(sampleRate: Double = preferredSampleRate) -> AVAudioFormat? {
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: true
        )
    }

    /// Non-interleaved format for DSP operations
    static func dspFormat(sampleRate: Double = preferredSampleRate) -> AVAudioFormat? {
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )
    }


    // MARK: - Audio Session Configuration

    /// Whether the audio session has been successfully configured at least once.
    /// Written once during startup, read from multiple threads thereafter.
    nonisolated(unsafe) private(set) static var isSessionConfigured = false

    /// True once a mic-input feature (record / input monitoring) has upgraded the
    /// session to `.playAndRecord`. `configureAudioSession()` re-runs on a latency
    /// change and after a media-services reset; without this flag those re-runs
    /// would silently drop an ACTIVE recording back to `.playback`. When set, a
    /// reconfigure re-applies the record route instead.
    nonisolated(unsafe) private(set) static var recordingRouteNeeded = false

    /// Configure audio session for real-time performance.
    ///
    /// DEFAULT is `.playback` (output only) — NOT `.playAndRecord`. This is the
    /// single most important choice for "Echoel must not degrade the sound of
    /// other apps running in parallel" (founder, 2026-07-09):
    ///   • `.playAndRecord` signals "I need the mic", which makes iOS route a
    ///     connected Bluetooth headset to HFP (the 8/16 kHz mono call codec)
    ///     for the WHOLE system — every parallel app (Spotify, Apple Music,
    ///     YouTube) suddenly plays through that tinny mono route. `.playback`
    ///     keeps the high-quality A2DP stereo codec for everyone.
    ///   • We do NOT request `.allowBluetooth` (HFP) here — only
    ///     `.allowBluetoothA2DP` — so nothing can pull the shared route down to
    ///     call quality while Echoel is merely playing.
    ///   • `.mixWithOthers` lets Echoel layer on top of another app's audio
    ///     instead of interrupting it. No `.defaultToSpeaker` (that is a record-
    ///     mode routing concern) and no `.duckOthers` (we never duck others).
    ///
    /// The mic is engaged ONLY on an explicit user action (record / input
    /// monitoring), which calls `upgradeToPlayAndRecord()` at that moment. So
    /// the costly `.playAndRecord` route — and any HFP downgrade — happens only
    /// while actually recording, never during normal bio-generative playback.
    static func configureAudioSession() throws {
        #if os(macOS)
        // macOS uses HAL (Hardware Abstraction Layer), not AVAudioSession
        isSessionConfigured = true
        log.audio("Audio session: macOS HAL (no AVAudioSession)")
        return
        #else
        let audioSession = AVAudioSession.sharedInstance()

        if recordingRouteNeeded {
            // A recording/monitoring session is active — a reconfigure must keep the
            // record route, not revert to .playback and cut the mic.
            try audioSession.setCategory(.playAndRecord, mode: .default,
                                         options: recordOptions)
        } else {
            // Output-only, A2DP-quality, mixes with other apps. Use .default mode
            // (NOT .measurement — that disables Bluetooth codec negotiation and can
            // silence/disconnect A2DP headphones).
            try audioSession.setCategory(.playback, mode: .default,
                                         options: [.allowBluetoothA2DP, .mixWithOthers])
        }

        // Set preferred sample rate
        try audioSession.setPreferredSampleRate(preferredSampleRate)

        // Set preferred IO buffer duration (target latency)
        let bufferDuration = ioBufferDuration(for: preferredSampleRate)
        try audioSession.setPreferredIOBufferDuration(bufferDuration)

        // Activate session
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        isSessionConfigured = true

        log.audio("🎵 Audio Session Configured:")
        log.audio("   Category: \(audioSession.category.rawValue)")
        log.audio("   Sample Rate: \(audioSession.sampleRate) Hz")
        log.audio("   IO Buffer Duration: \(audioSession.ioBufferDuration * 1000) ms")
        log.audio("   Input Latency: \(audioSession.inputLatency * 1000) ms")
        log.audio("   Output Latency: \(audioSession.outputLatency * 1000) ms")
        // ⛔ #664: #663 claimed "the sum had FOUR spellings … all four now route through one
        // function". There were THREE, and this one — the oldest — was not among the two it
        // folded. It added the terms raw (so `nan`-capable) and called the result "Total",
        // the exact word #654 replaced with `floor=` because it claimed the round trip and
        // was not. A claim of completeness is worth checking BEFORE it is written down.
        let latencyFloorMs = latencyFloorSeconds(ioBufferSeconds: audioSession.ioBufferDuration,
                                                 inputSeconds: audioSession.inputLatency,
                                                 outputSeconds: audioSession.outputLatency,
                                                 inputAvailable: !audioSession.currentRoute.inputs.isEmpty) * 1000
        log.audio("   Latency floor: \(latencyFloorMs) ms")
        #endif // !os(macOS)
    }


    #if !os(macOS)
    /// Record-mode options. `.allowBluetooth` (HFP) is here — and ONLY here — so a
    /// Bluetooth mic works while recording; that route is call-quality, which is why
    /// we never request it for plain `.playback`. `.mixWithOthers` keeps other apps
    /// audible even while we record.
    private static let recordOptions: AVAudioSession.CategoryOptions =
        [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
    #endif

    // MARK: - Who is holding the record route (#299)

    /// The three features that can put the SHARED session on `.playAndRecord`.
    ///
    /// ⭐ WHY A SET AND NOT A COUNTER, AND WHY IT EXISTS AT ALL. Before #299 the upgrade had
    /// FIVE call sites across three features (`AudioEngine` 1, `MultiTrackRecorder` 1,
    /// `MicrophoneManager` 3 — one in `startRecording`, two in `requestPermission`) and the
    /// downgrade had ONE: `MicrophoneManager.stopRecording`. ("Three callers" stood here and
    /// counted FEATURES while silently dropping the two permission sites that the same doc
    /// discusses as the exception.) So input
    /// monitoring and `MultiTrackRecorder` could each raise the route and NEVER lower it — turn
    /// monitoring off and the whole system stayed on `.playAndRecord`, which is what pulls every
    /// OTHER app's Bluetooth headset down to the HFP mono call codec (see
    /// `configureAudioSession`'s doc: that downgrade is the single thing this file exists to
    /// avoid). Meanwhile the one downgrade that DID exist was unconditional, so stopping the mic
    /// recorder yanked the route out from under live monitoring.
    ///
    /// A refcount was considered and rejected: `AudioEngine.setInputMonitoring` has two failure
    /// paths that return AFTER the upgrade, and an unbalanced increment on either leaks the
    /// route forever with no way to notice. A set is idempotent in both directions — a double
    /// claim and a double release are both harmless.
    ///
    /// ⚠️ AND THAT IS THE WHOLE OF WHAT IT BUYS. The first version of this note continued
    /// "…which is what makes the failure paths safe to write as a plain release" — an
    /// overstatement that the same commit then paid for: `MicrophoneManager.startRecording`'s
    /// `catch` claimed and never released, and a Set does nothing whatsoever about a MISSING
    /// release. It leaks exactly like the refcount this argument rejects. The Set removes ONE
    /// failure mode (double-release / double-claim); every claim still needs a release on
    /// every exit, and that is what `RecordRouteOwnershipTests` counts per file.
    enum RecordRouteOwner: String, CaseIterable, Sendable {
        case inputMonitoring
        case microphoneManager
        case multiTrackRecorder
    }

    /// `nonisolated(unsafe)`, matching `isSessionConfigured` and `recordingRouteNeeded` above.
    ///
    /// ⛔ The first version justified this with "two of `MicrophoneManager`'s permission
    /// callbacks land in a `DispatchQueue.main.async` closure … and `@MainActor` here would
    /// change their isolation" — FALSE in both halves. There is ONE such closure (the other is
    /// `await MainActor.run`, which IS isolated), and neither callback touches this set at all:
    /// they call `upgradeToPlayAndRecord()`, which writes `recordingRouteNeeded`. Every one of
    /// the seven real claim/release sites lives in a `@MainActor` type, so `@MainActor` here
    /// would have compiled.
    ///
    /// The real reason is consistency of OWNERSHIP, not of compilation: the two flags above
    /// genuinely ARE written from that non-isolated path (via `upgradeToPlayAndRecord`), and
    /// `claim`/`release` must stay callable from exactly where those two functions are — so
    /// isolating only the newest of the three would split the file's discipline for no gain.
    nonisolated(unsafe) private static var recordRouteOwners: Set<RecordRouteOwner> = []

    /// Register `owner` as needing the mic and raise the shared session to `.playAndRecord`.
    ///
    /// The registration happens BEFORE the upgrade can throw, deliberately: over-holding the
    /// route costs other apps their A2DP codec, while under-holding it cuts a live recording.
    /// Of the two, the first is the recoverable one.
    static func claimRecordRoute(_ owner: RecordRouteOwner) throws {
        recordRouteOwners.insert(owner)
        try upgradeToPlayAndRecord()
    }

    /// Drop `owner`'s claim and, only when NOBODY is left holding the mic, return the shared
    /// session to `.playback`. Safe to call when `owner` never claimed.
    /// - Returns: `true` when this call actually lowered the route.
    @discardableResult
    static func releaseRecordRoute(_ owner: RecordRouteOwner) throws -> Bool {
        recordRouteOwners.remove(owner)
        guard recordRouteOwners.isEmpty else { return false }
        try downgradeToPlaybackAfterRecording()
        return true
    }

    // ⛔ A `recordRouteHolders` read-only accessor stood here "for tests and diagnostics" and
    // had ZERO consumers — the test file that was supposed to use it explains at length why it
    // deliberately does not (process-wide static state makes a runtime emptiness check
    // order-dependent). Deleted rather than left: an unused accessor added "for tests" is this
    // repo's doorless pattern in miniature, and the engineering rules ban dead code outright.

    /// Upgrade audio session from .playback to .playAndRecord when the user actually
    /// records or monitors the mic. No-op if already using .playAndRecord.
    ///
    /// ⚠️ PREFER `claimRecordRoute(_:)`. Calling this directly raises the route with no owner,
    /// so the next release by anyone else lowers it again. That is correct ONLY where the
    /// upgrade is speculative — `MicrophoneManager.requestPermission`, which upgrades on the
    /// permission grant itself, before any recording exists to own it.
    static func upgradeToPlayAndRecord() throws {
        #if os(macOS)
        return
        #else
        recordingRouteNeeded = true      // so a reconfigure re-applies the record route
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category != .playAndRecord else { return }

        try audioSession.setCategory(.playAndRecord, mode: .default, options: recordOptions)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        log.audio("Audio session upgraded to .playAndRecord")
        #endif
    }

    /// Symmetric inverse of `upgradeToPlayAndRecord`: when the last mic feature stops,
    /// return the SHARED session to the app's default `.playback` (output-only, A2DP
    /// quality) WITHOUT deactivating it. The master playback engine OWNS the
    /// process-wide session — a full `setActive(false)` on mic-stop cut its output
    /// route, the "alles still" class (#22, AU4). This keeps the session live on the
    /// default category and clears `recordingRouteNeeded` so a later latency
    /// reconfigure stays on `.playback`. No-op on macOS / unconfigured / already
    /// `.playback`. The playback options mirror `configureAudioSession` exactly.
    ///
    /// ⚠️ PREFER `releaseRecordRoute(_:)`. This method is unconditional — it lowers the route
    /// even if another feature is still reading the mic, which is exactly how stopping the mic
    /// recorder used to cut live input monitoring (#299).
    static func downgradeToPlaybackAfterRecording() throws {
        #if os(macOS)
        return
        #else
        recordingRouteNeeded = false
        guard isSessionConfigured else { return }
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category != .playback else { return }
        try audioSession.setCategory(.playback, mode: .default,
                                     options: [.allowBluetoothA2DP, .mixWithOthers])
        // Deliberately NO setActive(false): the master output engine still needs the
        // session live — deactivating it here is exactly the silence bug this fixes.
        log.audio("Audio session downgraded to .playback (mic stopped)")
        #endif
    }

    // MARK: - Latency Modes

    enum LatencyMode {
        case ultraLow   // 128 frames (~2.7ms @ 48kHz) - max CPU usage
        case low        // 256 frames (~5.3ms @ 48kHz) - balanced
        case normal     // 512 frames (~10.7ms @ 48kHz) - battery friendly

        var bufferSize: AVAudioFrameCount {
            switch self {
            case .ultraLow: return AudioConfiguration.ultraLowLatencyBufferSize
            case .low: return AudioConfiguration.lowLatencyBufferSize
            case .normal: return AudioConfiguration.normalBufferSize
            }
        }

        var description: String {
            switch self {
            case .ultraLow: return "Ultra-Low (~2.7ms)"
            case .low: return "Low (~5.3ms)"
            case .normal: return "Normal (~10.7ms)"
            }
        }
    }

    /// Set latency mode and reconfigure audio session
    static func setLatencyMode(_ mode: LatencyMode) throws {
        currentBufferSize = mode.bufferSize
        #if !os(macOS)
        try configureAudioSession()
        #endif
        log.audio("🎵 Latency mode set to: \(mode.description)")
    }


    // MARK: - Thread Priority

    /// Set real-time audio thread priority
    static func setAudioThreadPriority() {
        // Get current thread
        var threadTimeConstraintPolicy = thread_time_constraint_policy()

        // Audio thread constraints (48kHz, 256 frames)
        let sampleRate = preferredSampleRate
        let bufferSize = currentBufferSize

        // Period: time for one buffer in nanoseconds
        let period = UInt32((Double(bufferSize) / sampleRate) * 1_000_000_000)

        // Computation: 75% of period
        let computation = UInt32(Double(period) * 0.75)

        // Constraint: 95% of period
        let constraint = UInt32(Double(period) * 0.95)

        threadTimeConstraintPolicy.period = period
        threadTimeConstraintPolicy.computation = computation
        threadTimeConstraintPolicy.constraint = constraint
        threadTimeConstraintPolicy.preemptible = 0  // Not preemptible

        // Apply policy
        var policyCount = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size
        )

        // mach_thread_self() returns a send right that the caller owns and must
        // release, otherwise every call leaks a port reference. Capture it once,
        // use it, then deallocate.
        let machThread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, machThread) }

        let result = withUnsafeMutablePointer(to: &threadTimeConstraintPolicy) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(policyCount)) {
                thread_policy_set(
                    machThread,
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    $0,
                    policyCount
                )
            }
        }

        if result == KERN_SUCCESS {
            log.audio("✅ Real-time audio thread priority set")
        } else {
            log.audio("⚠️  Failed to set audio thread priority: \(result)", level: .warning)
        }
    }


    // MARK: - Performance Monitoring

    /// Measure actual audio latency
    static func measureLatency() -> TimeInterval {
        #if os(macOS)
        return Double(currentBufferSize) / preferredSampleRate
        #else
        // #663 — routed through the SHARED sum. This was the last unfiltered spelling of
        // "in + out + one buffer" in this file: it added the three terms raw, so a session
        // queried mid-teardown made `latencyStats()` print `nan`. Behaviour on a healthy
        // session is unchanged (`inputAvailable: true` keeps the input term), and a
        // non-finite part is now dropped instead of poisoning the result.
        // ⚠️ It still differs from the picker in ONE way, deliberately: this returns a
        // TimeInterval with no way to say the sum was partial. Callers that show a number to
        // a human must use `latencySnapshot()`, which carries `complete` — and #664 had to
        // apply that rule to `latencyStats()`, the one caller #663 left violating it.
        // ⛔ #664: `inputAvailable` was hardcoded `true` here while the real value was
        // computed 400 lines below. On `.playback` (no input route) that re-asserts the exact
        // claim #654 retracted — "measured at zero" for a term never measured. Numerically
        // harmless today because iOS reports 0 there, which is why it survived review once.
        let audioSession = AVAudioSession.sharedInstance()
        return latencyFloorSeconds(ioBufferSeconds: audioSession.ioBufferDuration,
                                   inputSeconds: audioSession.inputLatency,
                                   outputSeconds: audioSession.outputLatency,
                                   inputAvailable: !audioSession.currentRoute.inputs.isEmpty)
        #endif
    }

    // MARK: - Audio Interruption Handling

    /// Callback invoked when audio session should resume after interruption
    nonisolated(unsafe) static var onInterruptionResume: (() -> Void)?

    /// Callback invoked when audio session is interrupted (phone call, Siri, etc.)
    nonisolated(unsafe) static var onInterruptionBegan: (() -> Void)?

    /// Callback invoked when audio output device becomes unavailable (headphones unplugged).
    /// Apple HIG requires pausing playback to prevent unexpected speaker output.
    nonisolated(unsafe) static var onRouteDeviceLost: (() -> Void)?

    /// The OS tore down and rebuilt the media daemon. DISTINCT from an interruption on
    /// purpose: an interruption pauses a graph that is still valid, so resuming it is a
    /// bare `AVAudioEngine.start()`. A media-services reset invalidates the audio objects
    /// underneath, which takes every TAP with it — so the owner has to redo the whole
    /// start path (tap reinstall, recorder prepare, meter timer), not just start the
    /// engine. This hook used to be `onInterruptionResume`, and that difference is
    /// exactly what got lost.
    ///
    /// ⚠️ IT HAS TWO CALLERS SINCE #585, and the name only describes the first. What the owner
    /// installs here is "the graph needs a full, de-bounced restart" — the 300 ms settle, the
    /// capped retry, the `degraded` surface, the tap reinstall. The second caller is the
    /// `.ended` branch of `handleInterruption` below, whose `setActive(true)` can throw: that
    /// path used to log the failure and return, leaving a paused graph with nothing scheduled
    /// to rescue it. Redoing the taps there is harmless; giving up there was not. Renaming the
    /// hook to match is a separate, purely cosmetic slice.
    nonisolated(unsafe) static var onMediaServicesReset: (() -> Void)?

    /// Whether interruption handlers have already been registered (prevents duplicate observers)
    nonisolated(unsafe) private static var interruptionHandlersRegistered = false

    /// Stored observer tokens to prevent leaks
    nonisolated(unsafe) private static var observerTokens: [Any] = []

    /// Register for audio session interruption and route change notifications.
    /// Call once during app startup after configureAudioSession().
    static func registerInterruptionHandlers() {
        #if os(macOS)
        log.audio("Audio interruption handlers: N/A on macOS")
        return
        #else
        guard !interruptionHandlersRegistered else {
            log.audio("Audio interruption handlers already registered — skipping")
            return
        }
        interruptionHandlersRegistered = true

        let interruptionToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleAudioInterruption(notification)
        }

        let routeChangeToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleRouteChange(notification)
        }

        let mediaResetToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { _ in
            handleMediaServicesReset()
        }

        observerTokens = [interruptionToken, routeChangeToken, mediaResetToken]

        log.audio("Audio interruption handlers registered")
        #endif // !os(macOS)
    }

    #if !os(macOS)
    private static func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            log.audio("Audio session interrupted (phone call, Siri, etc.)", level: .warning)
            onInterruptionBegan?()

        case .ended:
            // `.shouldResume` used to gate the whole resume, and an absent options key hit
            // an early `return`. That is correct etiquette for a media PLAYER; for a live
            // instrument it can mean silence for the rest of the session, because the two
            // interruptions this app actually meets — Siri and a Clock alarm banner — leave
            // it FOREGROUND and `.inactive`, so nothing else restarts it: the scene-phase
            // resume is gated on having been backgrounded, and `onInterruptionBegan` has
            // already set `isRunning = false`. iOS usually does attach `.shouldResume` for
            // those, so the old code usually worked — the exposure is the tail where the
            // hint is withheld or the key is absent.
            //
            // But "always resume" is the WRONG answer for the other half of that tail, and
            // review caught me shipping it: while BACKGROUNDED, `.shouldResume` withheld is
            // iOS saying "someone else owns playback now". `setActive(true)` on a
            // `.playback` category does not politely throw in that situation — it succeeds
            // and INTERRUPTS the other app. With `UIBackgroundModes: audio` declared, that
            // is Echoel silencing the user's music from the background. Exactly the F2
            // hazard this same change codified in `AudioEngine.shouldSelfHeal`, on the path
            // the predicate does not cover.
            //
            // So: in the FOREGROUND the hint is advisory and we always resume (that is the
            // stage case, and the user is looking at the instrument). In the BACKGROUND the
            // hint is authoritative and we stand down.
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            #if canImport(UIKit)
            // `assumeIsolated` rather than a plain read: this func is `nonisolated`, and
            // `UIApplication.shared` is main-actor state, so a direct read is a strict-
            // concurrency violation even though it happens to be correct here. The
            // precondition IS met — the observer is registered with `queue: .main`
            // (see `registerInterruptionHandlers`) — and `assumeIsolated` is the way to
            // say so to the compiler instead of to a comment. A `Task { @MainActor }`
            // (the pattern used in `CameraCapture` for its breadcrumb) is not available
            // to us: the value is needed synchronously, before the resume decision.
            let foreground = MainActor.assumeIsolated {
                UIApplication.shared.applicationState == .active
            }
            #else
            let foreground = true
            #endif
            guard options.contains(.shouldResume) || foreground else {
                log.audio("Interruption ended without .shouldResume while backgrounded "
                          + "— standing down so another app keeps the session")
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                log.audio("Audio session resumed after interruption"
                          + (options.contains(.shouldResume) ? "" : " (no shouldResume hint — foreground, resumed anyway)"))
                onInterruptionResume?()
            } catch {
                log.audio("Failed to reactivate audio session: \(error)", level: .error)
                // ⛔ #585 — THIS BRANCH USED TO END HERE, and ending here is a dead end. The
                // session did not come back, `wasInterrupted` is still set, the graph is still
                // paused, and nothing was scheduled to try again: the app sits silent until the
                // user relaunches it. One log line for a state the user experiences as a broken
                // instrument.
                //
                // The recovery hook already does everything this needs and nothing it does not —
                // a 300 ms settle (the session is often refusing because the route is mid-change),
                // a capped retry, and, when the cap is reached, the `degraded` surface that
                // `AudioDegradedRow` now renders. Redoing the taps on the way is harmless.
                //
                // ⚠️ THE ORDER OF THESE TWO SLICES IS NOT COSMETIC: without a reader for
                // `degraded`, this line would only move the silence from "no retry at all" to
                // "three retries, then the same silence". The affordance has to exist first.
                onMediaServicesReset?()
            }

        @unknown default:
            break
        }
    }

    private static func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            log.audio("Audio device disconnected (headphones removed) — pausing playback", level: .warning)
            onRouteDeviceLost?()
        case .newDeviceAvailable:
            log.audio("New audio device connected")
        case .categoryChange:
            log.audio("Audio category changed")
        default:
            break
        }
    }

    private static func handleMediaServicesReset() {
        log.audio("Media services were reset - reinitializing audio", level: .warning)
        do {
            try configureAudioSession()
            // NOT `onInterruptionResume` — see the hook's doc comment. That closure does a
            // bare `masterEngine.start()`, which is right for a paused-but-valid graph and
            // wrong here: the reset invalidated the objects the tap was installed on, so
            // resuming that way brings the engine back with RetroCapture's tap silently
            // gone. The pre-roll ring then stops filling and "keep last loop" hands the
            // user 30 seconds of silence, with nothing anywhere reporting a problem.
            onMediaServicesReset?()
        } catch {
            log.audio("Failed to reconfigure audio after media services reset: \(error)", level: .error)
        }
    }
    #endif // !os(macOS)

    /// Hardware in + ONE buffer period + hardware out, skipping any part that could not be
    /// measured.
    ///
    /// #663. This sum had THREE spellings in this file before #416 was applied to it, and only
    /// the one inside `latencyLine` filtered non-finite values before adding. ⛔ #663 wrote
    /// "FOUR … all four now route through one function" and folded TWO; the third — the
    /// `Total Latency:` line in `configureAudioSession` — it never touched, so the sentence
    /// was wrong in the count AND in the completeness. #664 folds it. It is `floor`,
    /// never `total`: a lower bound on what the ear hears, not the round trip. An unmeasurable
    /// part is DROPPED rather than counted as zero — the caller learns that from
    /// `LatencyReadout.complete`, never from a number that quietly shrank.
    static func latencyFloorSeconds(ioBufferSeconds: Double,
                                    inputSeconds: Double,
                                    outputSeconds: Double,
                                    inputAvailable: Bool) -> Double {
        var parts: [Double] = [ioBufferSeconds, outputSeconds]
        if inputAvailable { parts.append(inputSeconds) }
        return parts.filter { $0.isFinite && $0 >= 0 }.reduce(0, +)
    }

    /// What the route can CARRY. A different question from how long it takes, and the picker
    /// could not answer it until #670.
    ///
    /// ⭐ WHY THIS EXISTS. The founder asked (2026-08-20) for "Interface per Kabel und auch per
    /// Bluetooth … alle Latenzen und Kombinationen optimiert für Sessions". Two warnings in
    /// `AudioInputPickerView` already cover the Bluetooth DELAY (~150–250 ms). Neither covers
    /// the effect that actually ruins a take: once the mic is claimed, `recordOptions` carries
    /// `.allowBluetooth` (HFP), and iOS then pulls the WHOLE shared route — the music, not just
    /// the mic — down to the mono call codec. A player hears his own instrument turn into a
    /// telephone and has no number on screen that says why, because no LATENCY number can.
    ///
    /// ⚠️ Two cases, not one, and they must never print the same sentence: `.telephony` is what
    /// iOS NAMED, `.telephonySuspected` is what we INFERRED. #654 exists because this file once
    /// rendered "could not measure" and "measured zero" identically.
    /// ⚠️ Deliberately NOT `: String`. A raw value nothing reads is speculative surface, and
    /// the one place it would have gone — the log line — is where this slice decided NOT to add
    /// a field (`sr=` and `route=` already carry the evidence). Add it WITH its reader or not.
    enum RouteCodec: Sendable, Equatable {
        /// Nothing in the route says call mode.
        case wideband
        /// DEFINITIVE: an HFP port is in the route. iOS named it; nothing is being guessed.
        case telephony
        /// CORROBORATING ONLY: a Bluetooth output plus a sample rate that only call mode uses.
        /// A wideband codec can also run low in theory — hence "looks like", never "is".
        case telephonySuspected

        /// The one sentence the numbers cannot carry. `nil` when there is nothing to say, so a
        /// caller renders no row at all rather than a reassuring "all good" line nobody asked for.
        var note: String? {
            switch self {
            case .wideband:
                return nil
            case .telephony:
                return "Bluetooth is in call mode: mono and band-limited — the music too, not "
                     + "only the mic. A cable, or the iPhone mic as input, keeps full bandwidth."
            case .telephonySuspected:
                return "This looks like Bluetooth call mode (mono, band-limited). Check which "
                     + "input is selected; a cable keeps full bandwidth."
            }
        }
    }

    /// `AVAudioSessionPortBluetoothHFP`'s raw value.
    ///
    /// ⚠️ A STRING literal on purpose, so `routeCodec` stays a pure function a test can drive
    /// without a live session. The typo that a literal invites is closed at the other end:
    /// `TheBluetoothCodecReachesTheScreenTests` asserts the AVFoundation constant still equals
    /// this exact text, so a rename in iOS turns the guard red instead of the verdict silent.
    static let hfpPortType = "BluetoothHFP"

    /// Raw values of `AVAudioSessionPortBluetoothA2DP` and `AVAudioSessionPortBluetoothLE` —
    /// pinned by the same guard, for the same reason.
    static let bluetoothOutputPortTypes = ["BluetoothA2DPOutput", "BluetoothLE"]

    /// The highest rate any hands-free profile runs (8 · 16 · 24 kHz). Above it, a Bluetooth
    /// route is carrying real bandwidth and there is nothing to warn about.
    static let telephonyCeilingHz: Double = 24_000

    /// The verdict, as a pure function of what the route reported.
    ///
    /// Deliberately NOT a new field in the log line: `latencyLine` already prints `sr=` and
    /// `route=`, which together ARE the evidence, and a third round of call-site churn on a
    /// signature that broke the bundle twice (#666/#667) is not worth a convenience.
    static func routeCodec(outputPortTypes: [String], sampleRate: Double) -> RouteCodec {
        if outputPortTypes.contains(hfpPortType) { return .telephony }
        let bluetooth = outputPortTypes.contains { bluetoothOutputPortTypes.contains($0) }
        // A session queried mid-route-change answers with 0 or NaN. Neither is evidence of a
        // call codec, and treating them as such would put a red warning on a healthy cable.
        guard bluetooth, sampleRate.isFinite, sampleRate > 0, sampleRate <= telephonyCeilingHz
        else { return .wideband }
        return .telephonySuspected
    }

    /// The same measurement `latencyBreadcrumb` writes to `echoel_diag.log`, as NUMBERS.
    ///
    /// #663. The founder asked for "alle Latenzen und Kombinationen optimiert für Sessions".
    /// A log line answers that only after an export; a readout answers it while he is choosing
    /// the route. Both read ONE gathering (`currentSessionLatency`) and ONE sum
    /// (`latencyFloorSeconds`), so the screen and the file can never disagree — which is the
    /// whole reason this is a split and not a second implementation (#416).
    ///
    /// ⚠️ `inputMilliseconds` is OPTIONAL on purpose. "no input route" and "input measured at
    /// zero" are different facts, and #654 exists because this file once printed both as 0.0.
    struct LatencyReadout: Sendable, Equatable {
        let floorMilliseconds: Double
        /// Every part is OPTIONAL, and that is the #654 lesson applied rather than quoted:
        /// `nil` means "this session could not answer", never "the hardware costs nothing".
        /// `inputMilliseconds` is additionally `nil` when there is no input route at all.
        let bufferMilliseconds: Double?
        let inputMilliseconds: Double?
        let outputMilliseconds: Double?
        let route: String
        /// `false` when any part above is `nil`, so `floorMilliseconds` is a PARTIAL sum.
        /// A caller that shows the floor without showing this is publishing a number that
        /// silently shrank.
        let complete: Bool
        /// What the route can CARRY, alongside what it costs (#670). No default, deliberately:
        /// a defaulted field appears in no diff and no call site has to think about it
        /// (#431/#440/#443) — and this one is the difference between a session and a phone call.
        let codec: RouteCodec

        /// The headline number. Carries a `+` when the sum is PARTIAL, because a floor that
        /// silently dropped an unmeasurable part is worse than one that says so (#654).
        ///
        /// #663: this lives on the readout, not in the view, so it is reachable by a test and
        /// so a second surface cannot invent a second spelling of the same number (#416).
        var floorText: String {
            let value = String(format: "%.1f", floorMilliseconds)
            return complete ? value + " ms" : value + "+ ms"
        }

        /// `in 1.5 · buffer 5.0 · out 2.5 ms · Built-In Microphone→Speaker`, with `—` for any
        /// part the session could not answer.
        var breakdownText: String {
            func part(_ name: String, _ value: Double?) -> String {
                guard let value else { return name + " —" }
                return name + " " + String(format: "%.1f", value)
            }
            let parts = [part("in", inputMilliseconds),
                         part("buffer", bufferMilliseconds),
                         part("out", outputMilliseconds)].joined(separator: " · ")
            return parts + " ms · " + route
        }
    }

    /// ⚠️ Never call from a render block — like `latencyBreadcrumb` this touches
    /// `AVAudioSession` and allocates (`String`). It does NOT write a file, which is the only
    /// difference; that is not enough to make it audio-thread safe.
    /// ⛔ #664: this warning was missing here, and the one on `latencyBreadcrumb` had been
    /// silently re-parented onto a plain value type by #663's insertion — a doc block appended
    /// with no blank line adopts the declaration BELOW it, not the one it was written for. In
    /// a repo whose first hard rule is the audio-thread ban, a "never call from a render block"
    /// notice sitting on a struct that touches nothing is worse than no notice at all.
    static func latencySnapshot() -> LatencyReadout {
        let v = currentSessionLatency()
        func ms(_ seconds: Double) -> Double? {
            guard seconds.isFinite, seconds >= 0 else { return nil }
            return seconds * 1000
        }
        let buf = ms(v.ioBufferSeconds)
        let out = ms(v.outputSeconds)
        let input = v.inputAvailable ? ms(v.inputSeconds) : nil
        let floor = latencyFloorSeconds(ioBufferSeconds: v.ioBufferSeconds,
                                        inputSeconds: v.inputSeconds,
                                        outputSeconds: v.outputSeconds,
                                        inputAvailable: v.inputAvailable)
        return LatencyReadout(floorMilliseconds: floor * 1000,
                              bufferMilliseconds: buf,
                              inputMilliseconds: input,
                              outputMilliseconds: out,
                              route: sanitisedRoute(v.route),
                              complete: buf != nil && out != nil && input != nil,
                              codec: routeCodec(outputPortTypes: v.outputPortTypes,
                                                sampleRate: v.sampleRate))
    }

    /// ONE line about what the session GRANTED, shaped for the EXPORTABLE log.
    ///
    /// ⭐ #653 — WHY THIS EXISTS, AND IT IS THE #650 HOLE ONE LAYER UP. `latencyStats()`
    /// below has exactly ONE caller (`AudioEngine.prepareGraph`), and it writes to
    /// `log.audio` — `os_log` plus a write-only in-memory ring. Neither sink reaches
    /// `echoel_diag.log`, the file the founder exports.
    ///
    /// ⛔ #654 — AND #653 SHIPPED A NUMBER THAT LIED IN FOUR WAYS. Recorded in full,
    /// because every one of them is the same failure: a measurement carries more authority
    /// than prose, so an over-claiming figure is worse than no figure at all.
    ///
    /// 1. **`total=` claimed to be the round trip and was not.** It is `in + out + one`
    ///    buffer period — hardware latency plus a single buffer. The app-observable round
    ///    trip needs at least TWO (one to fill the input buffer before the render callback
    ///    runs, one to drain the output buffer it fills), and the monitor chain's own nodes
    ///    are on top of that. Renamed `floor=`, which is what it always was.
    /// 2. **It said nothing about the PITCH STAGE, while being addressed to `monitor on`.**
    ///    The monitor chain is `input → notchEQ → [voiceTunePitch] → monitorMixer`, and
    ///    `AVAudioUnitTimePitch` is a phase vocoder with real algorithmic delay.
    ///    `AudioInputPickerView` already warns in prose — "The pitch stage adds a little
    ///    latency to the monitor only" — so a number that omits it CONTRADICTS the app's own
    ///    UI on the same feature, and the number wins. `tune=on|off` now states whether the
    ///    stage is in the chain. ⚠️ A MEASURED figure for it is deliberately NOT printed:
    ///    `auAudioUnit.latency` has zero precedent in this repo and returns 0 for a node
    ///    that is attached but not initialised — and this whole retraction exists because a
    ///    fabricated 0 is worse than an honest absence. Reading it is its own slice, gated
    ///    on someone verifying the value on a device.
    /// 3. **The session CATEGORY was missing, and it decides the number.** `start` is
    ///    measured under `.playback` + `.allowBluetoothA2DP`; `monitor on` under
    ///    `.playAndRecord` + `recordOptions`, which includes `.allowBluetooth` — the HFP
    ///    mono call codec — and `.defaultToSpeaker`. Two lines with the same stem, adjacent
    ///    in one file, described incomparable regimes with no field to tell them apart, in a
    ///    line whose stated purpose is comparability. `cat=` closes it. (It also corrects the
    ///    #653 commit body: "~150–250 ms on A2DP" names a regime that CANNOT exist while
    ///    monitoring is on.)
    /// 4. **`in=0.0` was a fabrication on the most common path.** At `prepareGraph` the
    ///    session is `.playback` unless a record route is needed, so there is no input and
    ///    `inputLatency` is 0 — finite and non-negative, so the `?` mechanism could not see
    ///    it, and the founder read "input latency measured at zero". `inputAvailable` now
    ///    distinguishes "no input configured" (`n/a`) from "measured as zero".
    ///
    /// PURE on purpose: no `AVAudioSession` read, so a guard can drive it. The live reader
    /// is `latencyBreadcrumb(reason:tuneStage:insertMilliseconds:)`.
    ///
    /// Milliseconds with one decimal: the interesting range spans 3 ms (wired, small buffer)
    /// to 250 ms (Bluetooth), and a second decimal would suggest a precision the session's
    /// own estimates do not have.
    static func latencyLine(reason: String,
                            category: String,
                            sampleRate: Double,
                            ioBufferSeconds: Double,
                            inputSeconds: Double,
                            outputSeconds: Double,
                            inputAvailable: Bool,
                            tuneStage: Bool?,
                            insertMilliseconds: [(String, Double)],
                            route: String) -> String {
        // Non-finite or negative values are an edge case at this boundary, not an
        // impossibility — a session queried mid-teardown can answer with anything, and a
        // route rebuild is exactly when this line fires. A line reading "floor=nanms" looks
        // like a parse bug in the log rather than a session that had no answer.
        var incomplete = false
        func ms(_ seconds: Double) -> String {
            guard seconds.isFinite, seconds >= 0 else {
                incomplete = true
                return "?"
            }
            return String(format: "%.1f", seconds * 1000)
        }
        let bufText = ms(ioBufferSeconds)
        // "no input route" and "input measured at zero" are DIFFERENT facts and #654 exists
        // because printing both as 0.0 told the founder the second when it was the first.
        let inText: String
        if inputAvailable {
            inText = ms(inputSeconds)
        } else {
            inText = "n/a"
            incomplete = true
        }
        let outText = ms(outputSeconds)
        let floorSeconds = latencyFloorSeconds(ioBufferSeconds: ioBufferSeconds,
                                               inputSeconds: inputSeconds,
                                               outputSeconds: outputSeconds,
                                               inputAvailable: inputAvailable)
        let rate = sampleRate.isFinite && sampleRate > 0
            ? String(format: "%.0f", sampleRate) : "?"
        // `floor`, never `total`: hardware in + out + ONE buffer period. It is a lower
        // bound on what the ear hears, not the round trip — see retraction 1 above.
        var line = "latency: \(reason) cat=\(category) sr=\(rate) buf=\(bufText) "
        line += "in=\(inText) out=\(outText) floor=\(String(format: "%.1f", floorSeconds * 1000))ms"
        if incomplete { line += " partial" }
        if let tuneStage { line += tuneStage ? " tune=on" : " tune=off" }
        // #666. What the graph's OWN nodes report, verbatim, with no interpretation and no
        // arithmetic — it is deliberately NOT added into `floor=`.
        //
        // ⛔ THIS IS THE SLICE #654 REGISTERED AND GATED, and the gate is the reason for the
        // shape. #654 refused to print a measured pitch-stage figure because
        // `auAudioUnit.latency` "has zero precedent in this repo and returns 0 for a node that
        // is attached but not initialised — a fabricated 0 is worse than an honest absence",
        // and it said reading it is "its own slice, gated on someone verifying the value on a
        // device". That gate cannot be passed by reasoning; it needs one observation.
        //
        // ⭐ SO THIS DOES NOT SHOW A USER ANYTHING. It writes the raw AU-reported value into
        // the log the founder already exports, labelled by node, so the NEXT log he sends
        // answers "does this AU report a real number or a 0?" without a special probe. If the
        // answer is 0 the log says `notch=0.0` and we have learned that fact; nothing on
        // screen has claimed a latency the chain does not have. An observation is not a claim,
        // and keeping the two apart is what the whole #653–#665 chain was about.
        if !insertMilliseconds.isEmpty {
            let stages = insertMilliseconds
                .map { "\($0.0)=" + (($0.1.isFinite && $0.1 >= 0)
                                     ? String(format: "%.2f", $0.1) : "?") }
                .joined(separator: ",")
            line += " inserts[\(stages)]ms"
        }
        return line + " route=\(sanitisedRoute(route))"
    }

    /// Port names come from the USER's paired hardware ("Michael's AirPods"), so this is the
    /// first externally controlled string this repo writes into the diagnostics file.
    ///
    /// ⛔ #654 — AND THAT FILE HAS A SUBSTRING TRIGGER. `EchoelCrashLog.looksLikeUnseenCrash`
    /// returns true for ANY log containing `crashMarker`, which is the bare word "CRASH". A
    /// paired device whose name contains it would make every later launch auto-open the crash
    /// sheet on a session that never crashed. Low likelihood, trivially avoided, and the kind
    /// of hole that is impossible to diagnose from the outside once it happens.
    ///
    /// Also bounded in length: `currentLog()` reads the whole file into one `String` for the
    /// share sheet, and a route name is not worth an unbounded contribution to that.
    static func sanitisedRoute(_ route: String) -> String {
        let masked = route.replacingOccurrences(of: EchoelCrashLog.crashMarker,
                                                with: "C-R-A-S-H")
        let flattened = masked.replacingOccurrences(of: "\n", with: " ")
        return flattened.count <= 80 ? flattened : String(flattened.prefix(80)) + "…"
    }

    /// One gathering of the platform's latency facts, so the log line and the on-screen
    /// readout can never drift apart (#663). Everything platform-specific lives HERE; both
    /// consumers are platform-free below it.
    private struct SessionLatencyValues {
        let category: String
        let sampleRate: Double
        let ioBufferSeconds: Double
        let inputSeconds: Double
        let outputSeconds: Double
        let inputAvailable: Bool
        let route: String
        /// Raw `portType` values of the OUTPUT ports, for `routeCodec`. Raw values rather than
        /// `AVAudioSession.Port` so everything below this gathering stays platform-free — the
        /// same split that lets the log line and the screen share one source (#663).
        let outputPortTypes: [String]
    }

    private static func currentSessionLatency() -> SessionLatencyValues {
        #if os(macOS)
        // ⛔ #654: an earlier version passed `inputSeconds: 0, outputSeconds: 0` here and
        // printed "in=0.0 out=0.0" — a claim of zero hardware latency on a platform this
        // file cannot measure. Both are declared unavailable instead.
        return SessionLatencyValues(category: "macOS-HAL",
                                    sampleRate: preferredSampleRate,
                                    ioBufferSeconds: Double(currentBufferSize) / preferredSampleRate,
                                    inputSeconds: .nan,
                                    outputSeconds: .nan,
                                    inputAvailable: false,
                                    route: "macOS HAL",
                                    // Not "no Bluetooth" — this file cannot classify a HAL
                                    // route, and an empty list resolves to `.wideband`, which
                                    // renders NO claim at all. Silence, not a reassurance.
                                    outputPortTypes: [])
        #else
        let session = AVAudioSession.sharedInstance()
        let current = session.currentRoute
        // Port NAMES, not the classifier's latency CLASS. In a founder log "Built-In
        // Microphone → HI-X25BT" answers "which combination was this?" immediately, where
        // "high" would only repeat what the number already says. Multiple ports on one side
        // are real (a split route) and are joined rather than truncated.
        let ins = current.inputs.map(\.portName).joined(separator: "+")
        let outs = current.outputs.map(\.portName).joined(separator: "+")
        // Hoisted rather than interpolated inline: #287 took the bundle red on "unable to
        // type-check in reasonable time" for exactly this shape — a ternary inside a string
        // interpolation inside an argument list. Plain `let`s cost nothing.
        let inName = ins.isEmpty ? "none" : ins
        let outName = outs.isEmpty ? "none" : outs
        return SessionLatencyValues(category: session.category.rawValue,
                                    sampleRate: session.sampleRate,
                                    ioBufferSeconds: session.ioBufferDuration,
                                    inputSeconds: session.inputLatency,
                                    outputSeconds: session.outputLatency,
                                    inputAvailable: !current.inputs.isEmpty,
                                    route: inName + "→" + outName,
                                    outputPortTypes: current.outputs.map(\.portType.rawValue))
        #endif
    }

    /// Read the live session and emit the #653 line. Never call from a render block — this
    /// touches `AVAudioSession`, allocates, and ends in a blocking `write(2)`.
    ///
    /// ⚠️ `tuneStage` has NO default (#431/#440/#443): a defaulted argument that no call site
    /// writes appears in no diff, and the whole point of the field is that each caller states
    /// whether the pitch stage is in the chain it is describing. `nil` means "this line is not
    /// about the monitor chain" and omits the field entirely.
    static func latencyBreadcrumb(reason: String,
                                  tuneStage: Bool?,
                                  insertMilliseconds: [(String, Double)]) {
        let v = currentSessionLatency()
        EchoelCrashLog.breadcrumb(latencyLine(reason: reason,
                                              category: v.category,
                                              sampleRate: v.sampleRate,
                                              ioBufferSeconds: v.ioBufferSeconds,
                                              inputSeconds: v.inputSeconds,
                                              outputSeconds: v.outputSeconds,
                                              inputAvailable: v.inputAvailable,
                                              tuneStage: tuneStage,
                                              insertMilliseconds: insertMilliseconds,
                                              route: v.route))
    }

    /// Get latency statistics
    static func latencyStats() -> String {
        // ⛔ #664 — #663 INTRODUCED THE RULE AND THEN BROKE IT AT ITS ONLY CALL SITE.
        // Folding `measureLatency()` onto the shared sum made it DROP a non-finite term. That
        // is right for the sum and wrong here: before the fold a torn-down session printed
        // `nan ms` with `❌ NEEDS OPTIMIZATION` (obviously broken); after it, the same session
        // printed a plausible `7.50 ms` with `⚠️ GOOD` — a favourable verdict on a
        // measurement that never happened. #663's own doc says "callers that show a number to
        // a human must use `latencySnapshot()`, which carries `complete`", and this is the
        // caller it was written about.
        let readout = latencySnapshot()
        let totalLatency = readout.floorMilliseconds
        // Hoisted, not interpolated: #287 took the bundle red on a ternary chain inside a
        // string interpolation inside an argument list.
        let verdict: String
        if !readout.complete {
            verdict = "⚠️  PARTIAL — a term could not be measured, the floor is a lower bound"
        } else if totalLatency < 5.0 {
            verdict = "✅ EXCELLENT"
        } else if totalLatency < 10.0 {
            verdict = "⚠️  GOOD"
        } else {
            verdict = "❌ NEEDS OPTIMIZATION"
        }
        #if os(macOS)
        return """
        🎵 Audio Latency Statistics (macOS HAL):
           Buffer: \(currentBufferSize) frames
           Latency floor: \(readout.floorText)
           Status: \(verdict)
        """
        #else
        // `floor`, never `total`: hardware in + out + ONE buffer period is a lower bound on
        // what the ear hears, not the round trip (#654's retraction, applied here too — this
        // report said `Total Latency` for its whole life).
        return """
        🎵 Audio Latency Statistics:
           Route: \(readout.route)
           \(readout.breakdownText)
           Latency floor: \(readout.floorText)
           Target: < 5.0 ms
           Status: \(verdict)
        """
        #endif
    }
}

// MARK: - Audio-Safe Unfair Lock

/// Heap-allocated `os_unfair_lock` wrapper with NSLock-compatible API.
///
/// Unlike NSLock, `os_unfair_lock`:
/// - Has **priority inheritance** (prevents priority inversion on audio thread)
/// - Has **zero ObjC dispatch overhead** (pure C syscall)
/// - Is **orders of magnitude faster** in the uncontended case
///
/// Use this for all audio-thread synchronization instead of NSLock.
/// The class wrapper ensures stable memory address (os_unfair_lock is a value
/// type and must not be moved in memory after first use).
final class AudioUnfairLock: @unchecked Sendable {
    private var _lock = os_unfair_lock_s()

    @inline(__always)
    func lock() {
        os_unfair_lock_lock(&_lock)
    }

    @inline(__always)
    func unlock() {
        os_unfair_lock_unlock(&_lock)
    }

    /// Non-blocking try-lock for audio thread — returns `true` if lock acquired.
    @inline(__always)
    func `try`() -> Bool {
        os_unfair_lock_trylock(&_lock)
    }
}
#endif
