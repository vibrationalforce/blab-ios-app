// MultiTrackRecorder.swift
// Echoel — Multi-track recorder for microphone audio captured in sync with
// the beat playing on AudioEngine.masterMixer.
//
// Status: SKELETON (W2-C1, dormant). Not referenced from anywhere — adding
// this file does not change runtime behavior. Wire-up follows in:
//   W2-C2: state-machine tests
//   W2-C3: AVAudioEngine.inputNode tap → .caf writer
//   W2-C4: beat-stem recording delegated to RetroCapture
//   W2-C5: RecordTab UI (REC button + permission flow + level meter)
//   W2-C6: A/V sync verification + drift logging
//
// See scratchpads/PLAN_W2_RECORDER.md for the full plan.

#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Observation

/// Multi-track recorder for capturing microphone audio synchronously with
/// the beat playing on `AudioEngine.masterMixer`.
///
/// Concurrency: `@MainActor`. Tap callbacks (added in W2-C3) will use raw
/// pointer capture per the SamplerVoice / RetroCapture pattern.
@MainActor
@Observable
public final class MultiTrackRecorder {

    // MARK: - Observed state

    /// True while a recording is in progress.
    public private(set) var isRecording: Bool = false

    /// Seconds since `startRecording()` was last called. Reset on stop.
    public private(set) var recordingSeconds: Double = 0

    /// URLs of finished recording files, populated by `stopRecording()`.
    public private(set) var trackURLs: [URL] = []

    // MARK: - Internal

    @ObservationIgnored private weak var engine: AVAudioEngine?

    // MARK: - Init

    public init() {}

    // MARK: - Public API (skeleton)

    /// Captures a weak reference to the audio engine and prepares recording.
    /// W2-C3 will additionally validate microphone permission and free disk
    /// space.
    public func prepareForRecording(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Starts recording. W2-C3 will install the `inputNode` tap that writes
    /// mic frames to a `.caf` file on disk.
    public func startRecording() {
        // Skeleton — no-op until W2-C3.
    }

    /// Stops recording and returns the list of finished file URLs. W2-C3 will
    /// finalize the in-flight `AVAudioFile`s and append their URLs.
    public func stopRecording() async -> [URL] {
        return trackURLs
    }
}

/// Errors thrown by `MultiTrackRecorder` once the wire-up cycles add real logic.
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
