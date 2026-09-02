// MultiTrackRecorder.swift
// Echoel — Multi-track recorder for microphone audio captured in sync with
// the beat playing on AudioEngine.masterMixer.
//
// Captures the mic (engine.inputNode) to a .caf file while the beat/synth play
// on the master graph, so a take lines up with the backing track. The tap
// callback follows the RetroCapture pattern: it captures raw pointers only
// (never self), and writes via AVAudioFile.write on the tap's serial queue.

#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Observation

/// Multi-track recorder for capturing microphone audio synchronously with
/// the beat playing on `AudioEngine.masterMixer`.
///
/// Concurrency: `@MainActor` control plane. The `inputNode` tap callback uses
/// raw-pointer capture (`nonisolated(unsafe)`) per the SamplerVoice /
/// RetroCapture pattern — it never touches `self`.
@MainActor
@Observable
public final class MultiTrackRecorder {

    // MARK: - Observed state

    /// True while a recording is in progress.
    public private(set) var isRecording: Bool = false

    /// Seconds since `startRecording()` was last called. Reset on stop.
    public private(set) var recordingSeconds: Double = 0

    /// URLs of finished recording files, newest appended on each stop.
    public private(set) var trackURLs: [URL] = []

    /// Last error surfaced by `startRecording()`, for UI feedback.
    public private(set) var lastError: MultiTrackRecorderError?

    /// Round-trip latency measured at the moment the last take started, so the
    /// mix stage can align the recording to the beat (correct for whatever route
    /// is connected — wired, USB, or Bluetooth). Zero on macOS (HAL).
    public private(set) var lastCompensation: LatencyCompensation = .init()

    // MARK: - Internal

    @ObservationIgnored private weak var engine: AVAudioEngine?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var currentURL: URL?

    /// Tap-thread state (raw pointers — never capture self in the callback).
    @ObservationIgnored nonisolated(unsafe) private let activeFile: UnsafeMutablePointer<AVAudioFile?>
    @ObservationIgnored nonisolated(unsafe) private let isActive: UnsafeMutablePointer<Bool>

    /// The node a tap is currently installed on. Held `nonisolated(unsafe)` so
    /// `deinit` can remove the tap BEFORE freeing the pointers the tap reads —
    /// closing the dealloc-while-recording use-after-free window.
    @ObservationIgnored nonisolated(unsafe) private weak var tappedNode: AVAudioNode?

    // MARK: - Init / deinit

    public init() {
        activeFile = .allocate(capacity: 1)
        activeFile.initialize(to: nil)
        isActive = .allocate(capacity: 1)
        isActive.initialize(to: false)
    }

    deinit {
        // Order matters: close the gate, detach the tap (no further callbacks),
        // THEN free the pointers the callback dereferences.
        isActive.pointee = false
        tappedNode?.removeTap(onBus: 0)
        activeFile.deinitialize(count: 1)
        activeFile.deallocate()
        isActive.deinitialize(count: 1)
        isActive.deallocate()
    }

    // MARK: - Setup

    /// Captures a weak reference to the audio engine. Call once after the
    /// engine graph is prepared.
    public func prepareForRecording(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Request microphone permission ahead of time (e.g. when the Record UI
    /// first appears). Returns the granted state.
    @discardableResult
    public func requestPermission() async -> Bool {
        #if os(iOS)
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }

    // MARK: - Recording control

    /// Start recording the microphone input to a new `.caf` file. Validates
    /// permission and engine readiness; on failure sets `lastError` and returns.
    public func startRecording() {
        guard !isRecording else { return }
        lastError = nil

        guard let engine, engine.isRunning else {
            lastError = .engineNotReady
            log.log(.error, category: .audio, "MultiTrackRecorder: engine not ready")
            return
        }

        // ⚠️ #982 REGISTERED, NOT FIXED — the platform guard here is NARROWER than ONE
        // sibling's, and ⛔ the first version of this note (2026-09-02) named the wrong
        // counterpart. Measured (audit 2026-09-02, evening): the record-route OWNER
        // `AudioConfiguration.claimRecordRoute/releaseRecordRoute` sits inside `#if !os(macOS)`;
        // `MicrophoneManager` wraps its six calls in
        // `#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)`; `AudioEngine` wraps its SIX
        // (`.inputMonitoring` — the monitor toggle, `#if os(iOS)` at the head of
        // `setInputMonitoring`) and this type its four in a bare `#if os(iOS)`. Three owners,
        // three spellings of "a platform that has an AVAudioSession". Re-derive with
        // `git grep -n "RecordRoute(" -- Sources` and read each call's enclosing `#if`.
        // ⛔ The retracted sentence said "on visionOS the recorder would claim nothing while
        // the MONITOR still raises and lowers the category" — false: the monitor path is
        // compiled out there exactly like this one. Only `MicrophoneManager` would still claim.
        // It costs nothing TODAY: the ship target is `TARGETED_DEVICE_FAMILY "1"` and this type
        // is doorless behind `FeatureFlags.audioLaneRecording` (#204). Widening ANY of the bare
        // guards is a BEHAVIOUR change on a platform nobody here can build or run (the Xcode
        // gate compiles the iOS device SDK only), so it is written down rather than guessed at —
        // and if it is ever done, it is done for `AudioEngine` and this type TOGETHER.
        // Whoever ships a visionOS target widens all four in one commit.
        #if os(iOS)
        guard AVAudioApplication.shared.recordPermission == .granted else {
            lastError = .permissionDenied
            // Ask now so the next attempt can succeed.
            AVAudioApplication.requestRecordPermission { _ in }
            log.log(.error, category: .audio, "MultiTrackRecorder: microphone permission not granted")
            return
        }
        // The default session is .playback (so we never pull other apps' Bluetooth
        // audio to HFP). Recording needs the input hardware — upgrade to
        // .playAndRecord now, BEFORE reading inputNode's format (under .playback it
        // reports sampleRate 0 and the guard below would bail).
        // #981 — THE THIRD CLAIM SITE, AND THE ONLY ONE THAT DID NOT CHECK FIRST.
        // `AudioConfiguration.swift` already documented that there are three; two of them
        // (`MicrophoneManager` and, since #975, `AudioEngine.rearmInputMonitoring`) guard with
        // exactly this `if !isSessionConfigured` before claiming, and this one did not.
        //
        // WHAT THE ASYMMETRY COSTS, measured at the release side rather than guessed: the claim
        // raises the category through `upgradeToPlayAndRecord()` whether or not the session was
        // ever configured, but the matching release runs `downgradeToPlaybackAfterRecording()`,
        // which writes `recordingRouteNeeded = false` and THEN hits
        // `guard isSessionConfigured else { … return }`. So a take started on an unconfigured
        // session raises `.playAndRecord` and can never lower it again — the session sits there
        // with NOBODY holding it, which is the founder-visible A2DP→HFP degradation that file
        // names at that guard. All THREE release sites in this file hit the same wall.
        //
        // ⛔ #982 — TWO CORRECTIONS TO #981'S OWN COMMENT, BOTH FOUND BY THE REVIEWER.
        // (a) It said "all FOUR release sites". There are THREE, and
        //     `RecordRouteOwnershipTests.testTheMultiTrackRecorderClaimsAndReleasesTheRoute`
        //     PINS exactly three in the blocking bundle — a fabricated count eleven lines from
        //     a guard that holds the true one, inside the commit whose thesis is that an
        //     incomplete enumeration is this repo's recorded failure mode.
        // (b) It said the guard is the downgrade's FIRST statement. `recordingRouteNeeded = false`
        //     precedes it, and that write is what makes the stranded state STICKY: afterwards the
        //     flag says "no record route needed" while the category is still `.playAndRecord`, so
        //     a later reconfigure will not re-raise anything. Being exact about that ordering is
        //     the difference between "stuck until next use" and "stuck".
        //
        // ⚠️ HONEST SCOPE: this cannot bite a user TODAY. `startRecording()` is doorless —
        // `FeatureFlags.audioLaneRecording` is never handed to `UserDefaults.register(defaults:)`
        // so it resolves to false, and `RecordController.arm()` has no production caller (#204).
        // The repair is for the day that door comes back, when the person opening it will have
        // no reason to suspect the third site behaves differently from the other two.
        // ⚠️ IT REFUSES — it does NOT reconfigure, and that is the one place this site must
        // differ from its two siblings. Both of them may safely call `configureAudioSession()`
        // because no engine is running when they do: `MicrophoneManager` calls it BEFORE it
        // creates its `AVAudioEngine`, and `AudioEngine.rearmInputMonitoring` calls it AFTER
        // `masterEngine.stop()`. Here the engine is RUNNING — `guard let engine, engine.isRunning`
        // is the check three statements up — and `configureAudioSession()` does
        // `setPreferredSampleRate(48000)` and `setActive(true)` at its rungs 2/4 and 4/4.
        // Changing the hardware rate under a running engine is exactly the class behind the
        // founder's `isInputConnToConverter` abort (v10.79.435). Copying the sibling pattern
        // here would have been pattern-matching, not engineering.
        //
        // ⛔ #982 — #981 CLAIMED THIS BRANCH IS UNREACHABLE. IT IS NOT, AND THE STATE IT NEEDS
        // IS THE EXACT DEVICE STATE THIS WHOLE LINE OF WORK EXISTS FOR. `prepareGraph()` CATCHES
        // a thrown `configureAudioSession()`, writes the `session: configure FAILED` breadcrumb
        // and CONTINUES — `graphPrepared` is already latched, `setupMasterEngine()` runs anyway.
        // So `isSessionConfigured == false` with a built, startable master engine, and `start()`
        // only reconfigures if `masterEngine.start()` THROWS. That is the founder's v10.79.435
        // state, described by that same catch block in `AudioEngine`. "The shipped graph
        // configures it, therefore this cannot happen" is the identical reasoning #860b already
        // retracted about that very method.
        //
        // ⚠️ SO THE REFUSAL HAS A REAL COST, NAMED HERE INSTEAD OF DENIED: on such a device the
        // recorder cannot record at all, and nothing routine clears the state — only a fault
        // path (`start()` after a throw, or a media-services reset) calls
        // `configureAudioSession()` again. It is still the right trade, because the alternative
        // is a hardware-rate change under a LIVE graph, which is a worse failure than a refused
        // take and hits the whole app rather than one doorless feature. Stopping and restarting
        // the engine the way `rearmInputMonitoring` does would be a third option; this type does
        // not own the engine it was handed, so that is a different decision and its own slice.
        if !AudioConfiguration.isSessionConfigured {
            lastError = .sessionNotConfigured
            log.log(.error, category: .audio,
                    "MultiTrackRecorder: refusing to claim the record route — the audio session "
                    + "was never configured, and reconfiguring it under a running engine is not "
                    + "safe here")
            return
        }
        // #299: CLAIM. Nothing here ever lowered the route again — a single take left the
        // whole system on `.playAndRecord`, and with it every other app's Bluetooth headset on
        // the HFP mono call codec, for the rest of the app's life.
        do { try AudioConfiguration.claimRecordRoute(.multiTrackRecorder) }
        catch { log.log(.error, category: .audio, "MultiTrackRecorder: session upgrade failed \(error)") }
        #endif

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = .engineNotReady
            log.log(.error, category: .audio, "MultiTrackRecorder: invalid input format")
            #if os(iOS)
            try? AudioConfiguration.releaseRecordRoute(.multiTrackRecorder)   // #299 failure path
            #endif
            return
        }

        do {
            let url = try makeRecordingURL()
            let file = try AVAudioFile(forWriting: url,
                                       settings: format.settings,
                                       commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            currentURL = url

            let filePtr = activeFile
            let activePtr = isActive

            // ⚠️ SECOND CLAIMANT ON THIS BUS (#595 reviewer, for the #204 door slice):
            // `AudioEngine.setInputMonitoring(true)` also taps `inputNode` bus 0 (the
            // feedback-notch spectrum tap). Today the two cannot collide — this path is
            // doorless and flag-gated off (#204). Whoever opens the door MUST make
            // recording and input monitoring mutually exclusive on this bus (or share
            // one tap): this `removeTap` silently kills the monitor's tap (its
            // `monitorTapInstalled` flag stays true, the notch then reads a frozen
            // window), and monitoring-OFF removes THIS tap mid-take. Mirror note at
            // the monitor's `installTap` site in AudioEngine.
            input.removeTap(onBus: 0) // idempotent
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
                guard activePtr.pointee, let f = filePtr.pointee else { return }
                do { try f.write(from: buffer) }
                catch { log.log(.error, category: .audio, "MultiTrackRecorder write error: \(error.localizedDescription)") }
            }
            tappedNode = input

            activeFile.pointee = file
            isActive.pointee = true
            isRecording = true
            recordingSeconds = 0
            // Capture the live round-trip latency for this route so the take can
            // be aligned to the beat later (Bluetooth ≈ 150–250 ms, wired ≈ low).
            #if !os(macOS)
            lastCompensation = LatencyCompensation.current()
            #endif

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recordingSeconds += 1 }
            }

            log.log(.info, category: .audio,
                    "MultiTrackRecorder started → \(url.lastPathComponent) (\(Int(format.sampleRate))Hz \(format.channelCount)ch)")
        } catch {
            lastError = .fileCreationFailed
            log.log(.error, category: .audio, "MultiTrackRecorder: failed to start — \(error.localizedDescription)")
            #if os(iOS)
            try? AudioConfiguration.releaseRecordRoute(.multiTrackRecorder)   // #299 failure path
            #endif
        }
    }

    /// Stop recording, finalize the file, and return all finished URLs.
    @discardableResult
    public func stopRecording() async -> [URL] {
        guard isRecording else { return trackURLs }

        isActive.pointee = false
        engine?.inputNode.removeTap(onBus: 0)
        tappedNode = nil
        timer?.invalidate()
        timer = nil

        // Release the AVAudioFile so ARC flushes/closes it off the tap path.
        let closedFile = activeFile.pointee
        activeFile.pointee = nil
        isRecording = false

        // #299: hand the mic back. This method never did — a take left the shared session on
        // `.playAndRecord` forever. Released as an OWNER so a running input monitor keeps it.
        #if os(iOS)
        do { try AudioConfiguration.releaseRecordRoute(.multiTrackRecorder) }
        catch { log.log(.error, category: .audio, "MultiTrackRecorder: session downgrade failed \(error)") }
        #endif

        if let url = currentURL {
            trackURLs.append(url)
            log.log(.info, category: .audio,
                    "MultiTrackRecorder stopped — \(Int(recordingSeconds))s saved to \(url.lastPathComponent)")
        }
        currentURL = nil
        _ = closedFile
        return trackURLs
    }

    // MARK: - Helpers

    private func makeRecordingURL() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("echoel_mic_\(ts).caf")
    }
}

/// Errors thrown / surfaced by `MultiTrackRecorder`.
public enum MultiTrackRecorderError: Error, Sendable {
    /// User has not granted microphone permission.
    case permissionDenied
    /// Audio engine reference is nil or not running.
    case engineNotReady
    /// Not enough free disk space to start a recording (<200 MB target).
    /// ⛔ #982 (reviewer, adjacent finding): this case has ZERO writers — `git grep` finds the
    /// declaration and nothing that assigns it. The doc promises a check that does not exist, so
    /// a caller reading this enum learns about a safeguard the recorder does not have. NOT
    /// deleted, because the check is the right thing to build and the case is where it lands;
    /// named here so nobody plans around it. Pre-existing, older than this slice.
    case diskSpaceLow
    /// `AVAudioFile(forWriting:)` failed.
    case fileCreationFailed
    /// The shared audio session had never been configured, so the record route was NOT claimed
    /// (#981). Distinct from `engineNotReady` on purpose: the engine check runs earlier and had
    /// already passed, so reusing that case would have put a wrong label on a user-visible
    /// failure — the defect class this file's siblings spent two cycles removing. Nothing
    /// switches exhaustively on this enum, so adding a case is safe.
    case sessionNotConfigured
}

// MARK: - AudioTakeRecording (task #13, PLAN_AUDIO_LANE_RECORDING_2026-07-21.md)

/// Lets `RecordController` drive this recorder without importing AVFoundation
/// itself. `stop()` reads `recordingSeconds` BEFORE it would be reset by a
/// future `startRecording()` — safe here since nothing else calls
/// `startRecording()` again until this `stop()` returns.
extension MultiTrackRecorder: AudioTakeRecording {
    public func start() { startRecording() }

    public func stop() async -> (url: URL, seconds: Double)? {
        // `startRecording()` fails silently on a bad permission/engine/file state
        // (sets `lastError`, never flips `isRecording`) — without this guard,
        // `stopRecording()`'s `guard isRecording else { return trackURLs }` would
        // hand back a PRIOR take's URL (trackURLs accumulates across the whole
        // session), attaching the wrong audio file to this take.
        guard isRecording else { return nil }
        let seconds = recordingSeconds
        guard let url = await stopRecording().last else { return nil }
        return (url, seconds)
    }
}
#endif
