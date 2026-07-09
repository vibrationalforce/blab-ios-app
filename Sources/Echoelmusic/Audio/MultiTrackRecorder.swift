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
        do { try AudioConfiguration.upgradeToPlayAndRecord() }
        catch { log.log(.error, category: .audio, "MultiTrackRecorder: session upgrade failed \(error)") }
        #endif

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = .engineNotReady
            log.log(.error, category: .audio, "MultiTrackRecorder: invalid input format")
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
    case diskSpaceLow
    /// `AVAudioFile(forWriting:)` failed.
    case fileCreationFailed
}
#endif
