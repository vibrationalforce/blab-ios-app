#if canImport(AVFoundation)
import Foundation
import AVFoundation
import Observation

/// Fuses multiple bio sources (Apple Watch, Camera rPPG, Oura Ring)
/// into a single BioSnapshot with confidence-weighted merging.
///
/// Priority: Apple Watch > Camera rPPG > Oura (daily) > Fallback
@MainActor @Observable
final class BioSourceManager {

    // MARK: - Output

    /// Best available bio snapshot (merged from all active sources)
    var snapshot: BioSnapshot = BioSnapshot()

    /// Which source is currently primary
    var primarySource: BioDataSource = .fallback

    /// Confidence in current data (0 = simulated, 1 = real-time wearable)
    var confidence: Double = 0.0

    // MARK: - Sources

    private let bioEngine = EchoelBioEngine.shared
    private var cameraAnalyzer: CameraAnalyzer?
    private let ouraClient = OuraRingClient.shared
    private var cameraCapture: CameraCapture?

    /// Whether camera pulse detection is active
    var isCameraActive: Bool = false

    /// Timestamp of last confirmed real-time update from primary source
    private var lastRealUpdateTime: TimeInterval = 0

    // MARK: - Lifecycle

    func startStreaming() {
        bioEngine.startStreaming()
        updatePrimarySource()
    }

    func stopStreaming() {
        bioEngine.stopStreaming()
        stopCamera()
    }

    /// Start camera-based pulse detection (finger on lens + torch)
    func startCamera() {
        guard cameraAnalyzer == nil else { return }
        let analyzer = CameraAnalyzer()

        let capture = CameraCapture()
        capture.onFrame = { [weak analyzer] pixelBuffer in
            // Extract RGB averages on capture thread (safe — pixel buffer is valid here)
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            // Quick center-region average (every 8th pixel for speed)
            let regionX = width / 4, regionY = height / 4
            let regionW = width / 2, regionH = height / 2
            var totalR: Float = 0, totalG: Float = 0, totalB: Float = 0, count: Float = 0

            for y in stride(from: regionY, to: regionY + regionH, by: 8) {
                let row = base.advanced(by: y * bytesPerRow)
                for x in stride(from: regionX, to: regionX + regionW, by: 8) {
                    let pixel = row.advanced(by: x * 4)
                    totalB += Float(pixel.load(fromByteOffset: 0, as: UInt8.self))
                    totalG += Float(pixel.load(fromByteOffset: 1, as: UInt8.self))
                    totalR += Float(pixel.load(fromByteOffset: 2, as: UInt8.self))
                    count += 1
                }
            }

            guard count > 0 else { return }
            let avgR = totalR / count / 255.0
            let avgG = totalG / count / 255.0
            let avgB = totalB / count / 255.0

            // Dispatch results to MainActor for CameraAnalyzer
            Task { @MainActor [weak analyzer] in
                analyzer?.processExtractedRGB(avgR: avgR, avgG: avgG, avgB: avgB)
            }
        }

        cameraAnalyzer = analyzer
        cameraCapture = capture

        Task { [weak self] in
            do {
                try await capture.start()
                await MainActor.run { [weak self] in
                    self?.enableTorch(true)
                    analyzer.startPulseDetection()
                }
                log.log(.info, category: .biofeedback, "Camera rPPG started — waiting for frames")
                // Wait 500ms for session to deliver first frames before claiming active
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run { [weak self] in
                    self?.isCameraActive = true
                }
                log.log(.info, category: .biofeedback, "Camera rPPG active — frames flowing")
                // Lock exposure after 2s for stable PPG baseline
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                capture.lockExposure()
            } catch {
                log.log(.error, category: .biofeedback, "Camera start failed: \(error.localizedDescription)")
                await MainActor.run { [weak self] in
                    self?.cameraAnalyzer = nil
                    self?.cameraCapture = nil
                    self?.isCameraActive = false
                }
            }
        }
    }

    func stopCamera() {
        enableTorch(false)
        cameraCapture?.stop()
        cameraCapture = nil
        cameraAnalyzer?.stopPulseDetection()
        cameraAnalyzer = nil
        isCameraActive = false
    }

    /// Enable/disable camera torch for rPPG pulse illumination
    private func enableTorch(_ on: Bool) {
        #if canImport(AVFoundation) && !os(macOS)
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            if on { try device.setTorchModeOn(level: 0.5) } // Half brightness
            device.unlockForConfiguration()
        } catch {
            log.log(.warning, category: .biofeedback, "Torch control failed: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Fusion

    /// Call at 60Hz from SoundscapeEngine update loop
    func update() {
        updatePrimarySource()

        // Start with HealthKit data (Apple Watch)
        var merged = bioEngine.snapshot

        // Layer camera rPPG data if available and HealthKit isn't streaming real data
        if let camera = cameraAnalyzer, camera.isFingerDetected {
            let cameraHR = camera.heartRate
            let cameraHRV = camera.hrvRMSSD

            if bioEngine.dataSource == .fallback {
                // No Apple Watch — camera is primary
                if cameraHR > 0 {
                    merged.heartRate = cameraHR
                    merged.source = .camera
                }
                if cameraHRV > 0 {
                    merged.hrvNormalized = (cameraHRV / 100.0).clamped(to: 0...1)
                }
            }
            // If Apple Watch IS connected, camera data is ignored (Watch is more accurate)
        }

        // Layer Oura daily data (sleep/readiness affects coherence baseline)
        if ouraClient.authState == .authenticated {
            let oura = ouraClient.snapshot
            // Oura readiness adjusts coherence baseline
            if oura.readinessScore > 0 {
                let readinessBoost = Double(oura.readinessScore) / 100.0 * 0.1
                merged.coherence = (merged.coherence + readinessBoost).clamped(to: 0...1)
            }
            // Oura resting HR as reference (not real-time)
            if oura.restingHR > 0 && bioEngine.dataSource == .fallback && cameraAnalyzer == nil {
                merged.heartRate = Double(oura.restingHR)
                merged.source = .ouraRing
            }
        }

        // Calculate confidence with staleness decay
        let now = ProcessInfo.processInfo.systemUptime
        switch merged.source {
        case .healthKit, .appleWatch, .chestStrap:
            lastRealUpdateTime = now
            confidence = 1.0
        case .camera:
            let camConf = cameraAnalyzer?.bpmConfidence ?? 0
            if camConf > 0 { lastRealUpdateTime = now }
            confidence = camConf
        case .ouraRing:
            confidence = 0.3 // Daily aggregate, not real-time
        case .fallback:
            // Decay confidence if real source was recently active but now gone
            let staleSeconds = now - lastRealUpdateTime
            confidence = lastRealUpdateTime > 0 ? max(0, 1.0 - staleSeconds / 10.0) : 0.0
        default:
            confidence = 0.5
        }

        snapshot = merged
        primarySource = merged.source
    }

    private func updatePrimarySource() {
        if bioEngine.dataSource != .fallback {
            primarySource = bioEngine.dataSource
        } else if isCameraActive, let cam = cameraAnalyzer, cam.isFingerDetected {
            primarySource = .camera
        } else if ouraClient.authState == .authenticated {
            primarySource = .ouraRing
        } else {
            primarySource = .fallback
        }
    }
}

// MARK: - CameraAnalyzer Convenience

private extension CameraAnalyzer {
    var heartRate: Double { estimatedBPM }
    var hrvRMSSD: Double { rmssd }
    func startCapture() { startPulseDetection() }
    func stopCapture() { stopPulseDetection() }
}
#endif
