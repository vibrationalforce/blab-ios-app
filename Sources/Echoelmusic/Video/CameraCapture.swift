#if canImport(AVFoundation)
import Foundation
import AVFoundation

/// Minimal AVCaptureSession for rPPG pulse detection.
/// Captures low-resolution video frames from the back camera.
/// Delivers pixel buffers via callback for CameraAnalyzer processing.
final class CameraCapture: NSObject, @unchecked Sendable {

    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.echoelmusic.camera.capture", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "com.echoelmusic.camera.session")

    /// Called for each captured frame (on captureQueue — NOT main thread)
    nonisolated(unsafe) var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - Resilience (frame-stall watchdog + session-error recovery)
    /// Wall-clock of the last delivered frame. Written on captureQueue, read on the
    /// watchdog (sessionQueue); a CFAbsoluteTime is atomic-width so the small race is
    /// benign for a stall detector. Device logs showed the capture session silently
    /// stop delivering frames for ~68 s mid-session (thermal/resource contention with
    /// the audio+Metal pipeline) with no runtime-error — only a watchdog catches that.
    nonisolated(unsafe) private var lastFrameTime: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastRestartTime: CFAbsoluteTime = 0
    private var watchdog: DispatchSourceTimer?
    private var sessionObservers: [NSObjectProtocol] = []

    /// Whether the session is running
    var isRunning: Bool { session.isRunning }

    // MARK: - Start

    func start() async throws {
        // 1. Request camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraCaptureError.permissionDenied }
        } else if status == .denied || status == .restricted {
            throw CameraCaptureError.permissionDenied
        }

        // 2. Configure and start on background thread (required by Apple)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraCaptureError.configurationFailed)
                    return
                }
                do {
                    try self.configureSession()
                    self.installSessionObservers()
                    self.session.startRunning()
                    self.lastFrameTime = CFAbsoluteTimeGetCurrent()   // grace from start
                    self.startWatchdog()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        log.log(.info, category: .biofeedback, "CameraCapture started")
    }

    private func configureSession() throws {
        // CRITICAL: do NOT let the capture session touch the app's AVAudioSession.
        // It defaults to true, which reconfigures/deactivates the shared audio
        // session out from under the running AVAudioEngine → render-thread crash
        // the instant the camera starts (the classic "camera kills audio" device
        // crash). We capture video only, so it never needs to manage audio.
        session.automaticallyConfiguresApplicationAudioSession = false

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .low

        // Find back camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraCaptureError.noCamera
        }

        // Configure device: continuous auto-exposure initially, locked after stabilization
        try device.lockForConfiguration()
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        // Prefer lower frame rate for consistent timing (15–30 fps range)
        if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
            let targetFPS = min(30.0, range.maxFrameRate)
            let duration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
        device.unlockForConfiguration()

        // Input
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraCaptureError.configurationFailed
        }
        session.addInput(input)

        // Output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw CameraCaptureError.configurationFailed
        }
        session.addOutput(output)
    }

    // MARK: - Torch (finger-PPG illumination)

    /// Drive the torch on the SESSION's own running device (reliable), not a
    /// separate `AVCaptureDevice.default(for:)` lookup that can race the session.
    /// Finger-on-lens PPG has no red-channel pulse without it.
    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
                  device.hasTorch else {
                log.log(.warning, category: .biofeedback, "Torch unavailable on capture device")
                return
            }
            do {
                try device.lockForConfiguration()
                if on {
                    let level = min(0.6, AVCaptureDevice.maxAvailableTorchLevel)
                    try device.setTorchModeOn(level: level)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                log.log(.info, category: .biofeedback,
                        "Torch \(on ? "on" : "off"), active=\(device.isTorchActive)")
            } catch {
                log.log(.warning, category: .biofeedback, "Torch control failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Exposure Lock (call after ~2s for stable PPG baseline)

    /// Lock camera exposure to prevent auto-gain from corrupting PPG signal.
    /// IMPORTANT: only call this once the finger is actually covering the torch-lit
    /// lens — locking against a dim, finger-less scene freezes a high-gain exposure
    /// that then SATURATES (R≈0.82) when the bright fingertip arrives, swamping the
    /// tiny pulsatile AC so no pulse ever locks (device-log root cause, 2026-06-23).
    func lockExposure() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
                  device.isExposureModeSupported(.locked) else { return }
            try? device.lockForConfiguration()
            device.exposureMode = .locked
            device.unlockForConfiguration()
        }
    }

    /// Hand exposure back to continuous auto so it can re-settle to the current
    /// scene before a fresh `lockExposure()` — used to recover from a saturated
    /// lock (e.g. exposure was frozen before the finger arrived, or a re-grip).
    func unlockExposure() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
                  device.isExposureModeSupported(.continuousAutoExposure) else { return }
            try? device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        }
    }

    // MARK: - Resilience

    /// Observe AVCaptureSession runtime errors + interruptions and recover. Extract
    /// only Sendable values inside each notification block, then hop to sessionQueue
    /// (Notification itself is non-Sendable, so it must not cross the boundary).
    private func installSessionObservers() {
        let nc = NotificationCenter.default
        let rt = nc.addObserver(forName: .AVCaptureSessionRuntimeError, object: session,
                                queue: nil) { [weak self] note in
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            self?.sessionQueue.async { self?.recoverFromError(code) }
        }
        let intr = nc.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session,
                                  queue: nil) { note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            log.log(.warning, category: .biofeedback, "Camera session interrupted (reason \(reason))")
        }
        let ended = nc.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session,
                                   queue: nil) { [weak self] _ in
            self?.sessionQueue.async {
                guard let self, !self.session.isRunning else { return }
                self.session.startRunning()
                self.lastFrameTime = CFAbsoluteTimeGetCurrent()
                log.log(.info, category: .biofeedback, "Camera session resumed after interruption")
            }
        }
        sessionObservers = [rt, intr, ended]
    }

    /// On a runtime error (notably `.mediaServicesWereReset`) restart the session.
    private func recoverFromError(_ code: AVError.Code?) {
        log.log(.warning, category: .biofeedback, "Camera runtime error (\(code.map(String.init(describing:)) ?? "unknown")) — restarting")
        if !session.isRunning { session.startRunning() }
        lastFrameTime = CFAbsoluteTimeGetCurrent()
    }

    /// Watchdog: if the session is running but no frame has arrived for >4 s, the
    /// capture pipeline has silently stalled (device log: ~68 s freeze, no error) —
    /// kick it with a stop/start. Cooldown-guarded so it can never thrash.
    private func startWatchdog() {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self, self.session.isRunning else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastFrameTime > 4.0,        // frames stopped
                  now - self.lastRestartTime > 6.0 else { return }   // restart cooldown
            self.lastRestartTime = now
            log.log(.warning, category: .biofeedback,
                    "Camera stalled \(String(format: "%.1f", now - self.lastFrameTime))s — restarting session")
            self.session.stopRunning()
            self.session.startRunning()
            self.lastFrameTime = CFAbsoluteTimeGetCurrent()   // grace after kick
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: - Stop

    func stop() {
        // All watchdog/observer state is mutated on sessionQueue (start + stop), so
        // tear it down there too — keeps access serialized, no data race.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.watchdog?.cancel()
            self.watchdog = nil
            for o in self.sessionObservers { NotificationCenter.default.removeObserver(o) }
            self.sessionObservers = []
            self.session.stopRunning()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
        }
        log.log(.info, category: .biofeedback, "CameraCapture stopped")
    }
}

// MARK: - Frame Delivery

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = CFAbsoluteTimeGetCurrent()   // watchdog heartbeat
        onFrame?(pixelBuffer)
    }
}

// MARK: - Errors

enum CameraCaptureError: Error, LocalizedError {
    case permissionDenied
    case noCamera
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .noCamera: return "No camera available"
        case .configurationFailed: return "Camera configuration failed"
        }
    }
}
#endif
