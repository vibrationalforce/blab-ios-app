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
        log.audio("   Total Latency: \((audioSession.inputLatency + audioSession.outputLatency + audioSession.ioBufferDuration) * 1000) ms")
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
    /// three callers and the downgrade had ONE: `MicrophoneManager.stopRecording`. So input
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
    /// claim and a double release are both harmless — which is what makes the failure paths
    /// safe to write as a plain release.
    enum RecordRouteOwner: String, CaseIterable, Sendable {
        case inputMonitoring
        case microphoneManager
        case multiTrackRecorder
    }

    /// `nonisolated(unsafe)` for the same reason — and with the same honest caveat — as
    /// `isSessionConfigured` and `recordingRouteNeeded` above: every real caller is
    /// `@MainActor`, but two of `MicrophoneManager`'s permission callbacks land in a
    /// `DispatchQueue.main.async` closure that Swift 6 does not treat as isolated, and adding
    /// `@MainActor` here would change their isolation rather than this file's behaviour.
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

    /// Read-only view for tests and diagnostics.
    static var recordRouteHolders: Set<RecordRouteOwner> { recordRouteOwners }

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
        let audioSession = AVAudioSession.sharedInstance()
        let inputLatency = audioSession.inputLatency
        let outputLatency = audioSession.outputLatency
        let ioBufferDuration = audioSession.ioBufferDuration

        return inputLatency + outputLatency + ioBufferDuration
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

    /// Get latency statistics
    static func latencyStats() -> String {
        let totalLatency = measureLatency() * 1000  // Convert to ms
        #if os(macOS)
        return """
        🎵 Audio Latency Statistics (macOS HAL):
           Buffer: \(currentBufferSize) frames
           Estimated Latency: \(String(format: "%.2f", totalLatency)) ms
        """
        #else
        let audioSession = AVAudioSession.sharedInstance()
        return """
        🎵 Audio Latency Statistics:
           Sample Rate: \(audioSession.sampleRate) Hz
           IO Buffer: \(audioSession.ioBufferDuration * 1000) ms (\(currentBufferSize) frames)
           Input Latency: \(audioSession.inputLatency * 1000) ms
           Output Latency: \(audioSession.outputLatency * 1000) ms
           Total Latency: \(String(format: "%.2f", totalLatency)) ms
           Target: < 5.0 ms
           Status: \(totalLatency < 5.0 ? "✅ EXCELLENT" : totalLatency < 10.0 ? "⚠️  GOOD" : "❌ NEEDS OPTIMIZATION")
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
