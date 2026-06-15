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
                    self.session.startRunning()
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

    // MARK: - Exposure Lock (call after ~2s for stable PPG baseline)

    /// Lock camera exposure to prevent auto-gain from corrupting PPG signal
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

    // MARK: - Stop

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
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
