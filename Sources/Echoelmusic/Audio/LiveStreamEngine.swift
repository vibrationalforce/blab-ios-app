#if canImport(AVFoundation)
import AVFoundation
import Observation
import os.log

/// Video + audio recording for live streaming.
///
/// Records H.264 (720p) + AAC to a local .mp4 file ready to upload
/// to YouTube Live / Twitch. Camera video + device mic audio.
///
/// State machine: idle → connecting → live(duration) → done(URL) → idle
@MainActor @Observable
final class LiveStreamEngine: NSObject {

    // MARK: - Observable state

    enum StreamState: Equatable {
        case idle
        case connecting
        case live(duration: Int)
        case done(URL)
        case error(String)

        var isLive: Bool {
            if case .live = self { return true }
            return false
        }

        var doneURL: URL? {
            if case .done(let url) = self { return url }
            return nil
        }
    }

    private(set) var state: StreamState = .idle
    var streamKey: String = ""
    var cameraEnabled: Bool = true

    // MARK: - Destinations (for UI labelling — actual upload is manual via ShareLink)

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

    // MARK: - Capture

    @ObservationIgnored private let captureSession  = AVCaptureSession()
    @ObservationIgnored private let captureQueue    = DispatchQueue(label: "com.echoelmusic.stream.capture",
                                                                    qos: .userInitiated)
    // MARK: - Writer

    @ObservationIgnored private var assetWriter:    AVAssetWriter?
    @ObservationIgnored private var videoInput:     AVAssetWriterInput?
    @ObservationIgnored private var audioInput:     AVAssetWriterInput?
    @ObservationIgnored private var videoAdaptor:   AVAssetWriterInputPixelBufferAdaptor?
    @ObservationIgnored private var sessionStarted: Bool = false
    @ObservationIgnored private var firstAudioPTS:  CMTime = .invalid
    @ObservationIgnored private var outputURL:      URL?

    // MARK: - Timer

    @ObservationIgnored private var durationTimer:  Timer?
    @ObservationIgnored private var elapsedSeconds: Int = 0

    // MARK: - Start / Stop

    func startStream() {
        guard state == .idle else { return }
        state = .connecting
        log.log(.info, category: .system, "LiveStream: setting up capture + writer")

        Task { @MainActor in
            do {
                let url = try makeOutputURL()
                outputURL = url
                try await requestPermissions()
                try setupCapture()
                try setupWriter(url: url)
                captureSession.startRunning()
                startDurationTimer()
                state = .live(duration: 0)
                log.log(.info, category: .system, "LiveStream LIVE → \(url.lastPathComponent)")
            } catch {
                teardown()
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

        captureSession.stopRunning()

        guard let writer = assetWriter, writer.status == .writing else {
            teardown()
            state = .idle
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let url = outputURL
        writer.finishWriting { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.teardown()
                if let url {
                    self.state = .done(url)
                    log.log(.info, category: .system, "LiveStream saved → \(url.lastPathComponent)")
                } else {
                    self.state = .idle
                }
            }
        }
    }

    func resetAfterDone() {
        state = .idle
    }

    // MARK: - Permissions

    private func requestPermissions() async throws {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw StreamError.cameraPermissionDenied
            }
        } else if videoStatus == .denied {
            throw StreamError.cameraPermissionDenied
        }

        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw StreamError.micPermissionDenied
            }
        } else if audioStatus == .denied {
            throw StreamError.micPermissionDenied
        }
    }

    // MARK: - Capture setup

    private func setupCapture() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // Video input
        if cameraEnabled {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video, position: .front)
                              ?? AVCaptureDevice.default(for: .video) else {
                throw StreamError.noCameraAvailable
            }
            let videoIn = try AVCaptureDeviceInput(device: camera)
            guard captureSession.canAddInput(videoIn) else { throw StreamError.cannotConfigureCapture }
            captureSession.addInput(videoIn)

            let videoOut = AVCaptureVideoDataOutput()
            videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                        kCVPixelFormatType_32BGRA]
            videoOut.alwaysDiscardsLateVideoFrames = true
            videoOut.setSampleBufferDelegate(self, queue: captureQueue)
            guard captureSession.canAddOutput(videoOut) else { throw StreamError.cannotConfigureCapture }
            captureSession.addOutput(videoOut)

            // Lock to portrait orientation
            if let conn = videoOut.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
            }
        }

        // Audio input (device mic)
        if let mic = AVCaptureDevice.default(for: .audio) {
            let audioIn = try AVCaptureDeviceInput(device: mic)
            if captureSession.canAddInput(audioIn) {
                captureSession.addInput(audioIn)
            }
            let audioOut = AVCaptureAudioDataOutput()
            audioOut.setSampleBufferDelegate(self, queue: captureQueue)
            if captureSession.canAddOutput(audioOut) {
                captureSession.addOutput(audioOut)
            }
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Writer setup

    private func setupWriter(url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Video — H.264 720p
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        // Audio — AAC 192kbps
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        if cameraEnabled { guard writer.canAdd(vInput) else { throw StreamError.cannotConfigureCapture } }
        guard writer.canAdd(aInput) else { throw StreamError.cannotConfigureCapture }

        if cameraEnabled { writer.add(vInput) }
        writer.add(aInput)
        writer.startWriting()

        self.assetWriter = writer
        self.videoInput  = vInput
        self.audioInput  = aInput
        self.videoAdaptor = adaptor
        self.sessionStarted = false
        self.firstAudioPTS  = .invalid
    }

    // MARK: - Output URL

    private func makeOutputURL() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("Stream", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("echoel_stream_\(ts).mp4")
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

    // MARK: - Teardown

    private func teardown() {
        assetWriter  = nil
        videoInput   = nil
        audioInput   = nil
        videoAdaptor = nil
        outputURL    = nil
        sessionStarted = false
        firstAudioPTS  = .invalid
    }

    // MARK: - Errors

    enum StreamError: LocalizedError {
        case cameraPermissionDenied, micPermissionDenied
        case noCameraAvailable, cannotConfigureCapture

        var errorDescription: String? {
            switch self {
            case .cameraPermissionDenied: return "Camera access required for video stream"
            case .micPermissionDenied:    return "Microphone access required for audio"
            case .noCameraAvailable:      return "No camera found on this device"
            case .cannotConfigureCapture: return "Cannot configure capture session"
            }
        }
    }
}

// MARK: - AVCaptureSampleBufferDelegate

extension LiveStreamEngine: AVCaptureVideoDataOutputSampleBufferDelegate,
                             AVCaptureAudioDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let writer = assetWriter, writer.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if output is AVCaptureVideoDataOutput {
            guard let vInput = videoInput, vInput.isReadyForMoreMediaData,
                  let adaptor = videoAdaptor,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
            }
            adaptor.append(pixelBuffer, withPresentationTime: pts)

        } else {
            guard let aInput = audioInput, aInput.isReadyForMoreMediaData else { return }
            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
            }
            aInput.append(sampleBuffer)
        }
    }
}
#endif
