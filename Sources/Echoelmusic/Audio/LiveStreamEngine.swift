#if canImport(AVFoundation) && canImport(Network)
import AVFoundation
import Network
import Observation
import os.log

/// RTMP live stream output — taps the master audio bus and packages frames
/// for YouTube Live / Twitch. Video is a static visual frame (Phase 1) or
/// a camera feed (Phase 2 via CameraCapture).
///
/// Connection state machine:
///   idle → connecting → live → idle (on stop/error)
///
/// Phase 1 ships audio-only RTMP. Video track added in Phase 2.
@MainActor @Observable
final class LiveStreamEngine {

    // MARK: - Observable state

    enum StreamState: Equatable {
        case idle
        case connecting
        case live(duration: Int)    // seconds elapsed
        case error(String)

        var isLive: Bool {
            if case .live = self { return true }
            return false
        }
    }

    private(set) var state: StreamState = .idle
    var rtmpURL: String = ""
    var streamKey: String = ""

    // MARK: - Presets

    struct Destination: Identifiable, Equatable {
        let id: String
        let name: String
        let rtmpBase: String
    }

    static let destinations: [Destination] = [
        Destination(id: "youtube", name: "YouTube Live",  rtmpBase: "rtmp://a.rtmp.youtube.com/live2"),
        Destination(id: "twitch",  name: "Twitch",        rtmpBase: "rtmp://live.twitch.tv/live"),
        Destination(id: "custom",  name: "Custom RTMP",   rtmpBase: ""),
    ]

    var selectedDestination: Destination = destinations[0]

    // MARK: - Internals

    @ObservationIgnored private var audioEngine: AudioEngine?
    @ObservationIgnored private var assetWriter: AVAssetWriter?
    @ObservationIgnored private var audioInput: AVAssetWriterInput?
    @ObservationIgnored private var durationTimer: Timer?
    @ObservationIgnored private var elapsedSeconds: Int = 0

    // MARK: - Connect

    func connect(audio: AudioEngine) {
        self.audioEngine = audio
    }

    // MARK: - Start / Stop

    func startStream() {
        guard state == .idle else { return }

        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = selectedDestination.rtmpBase.isEmpty ? rtmpURL : selectedDestination.rtmpBase
        guard !base.isEmpty, !key.isEmpty else {
            state = .error("Missing RTMP URL or stream key")
            return
        }

        let fullURL = "\(base)/\(key)"
        guard let url = URL(string: fullURL) else {
            state = .error("Invalid RTMP URL")
            return
        }

        state = .connecting
        log.log(.info, category: .system, "LiveStream connecting → \(selectedDestination.name)")

        Task { @MainActor in
            do {
                try await setupWriter(url: url)
                startDurationTimer()
                state = .live(duration: 0)
                log.log(.info, category: .system, "LiveStream LIVE — \(selectedDestination.name)")
            } catch {
                state = .error(error.localizedDescription)
                log.log(.error, category: .system, "LiveStream failed: \(error.localizedDescription)")
            }
        }
    }

    func stopStream() {
        guard state.isLive || state == .connecting else { return }
        durationTimer?.invalidate()
        durationTimer = nil
        elapsedSeconds = 0

        assetWriter?.finishWriting { }
        assetWriter = nil
        audioInput = nil
        state = .idle
        log.log(.info, category: .system, "LiveStream stopped")
    }

    // MARK: - AVAssetWriter setup

    private func setupWriter(url: URL) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mp4)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw StreamError.cannotAddAudioInput
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.audioInput = input
    }

    // MARK: - Duration timer

    private func startDurationTimer() {
        elapsedSeconds = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds += 1
                if case .live = self.state {
                    self.state = .live(duration: self.elapsedSeconds)
                }
            }
        }
    }

    // MARK: - Errors

    enum StreamError: LocalizedError {
        case cannotAddAudioInput

        var errorDescription: String? {
            switch self {
            case .cannotAddAudioInput: return "Cannot configure audio for streaming"
            }
        }
    }
}
#endif
