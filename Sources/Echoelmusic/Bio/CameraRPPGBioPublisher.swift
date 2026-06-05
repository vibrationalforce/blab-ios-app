//
//  CameraRPPGBioPublisher.swift
//  Echoelmusic — Bio
//
//  Wires the dormant camera rPPG path into the live EngineBus: drives
//  CameraCapture → CameraAnalyzer (finger-on-lens photoplethysmography) and
//  publishes a BioSampleFrame(source: .cameraPPG) at ~1 Hz when a confident
//  pulse is detected. Opt-in (camera + torch), so it is started explicitly by
//  the UI, never auto-run.
//
//  Concurrency: CameraCapture (@unchecked Sendable) delivers CVPixelBuffers on
//  its own capture queue and drives CameraAnalyzer there — mirroring the
//  established pattern in CameraCapture (nonisolated(unsafe) onFrame). The 1 Hz
//  publish loop reads the analyzer's latest scalar results on the main actor;
//  those are atomic-width numeric reads of a continuously-updated estimate
//  (display/publish values), hence the nonisolated(unsafe) annotation.
//
//  RUNTIME NOTE: pulse detection can only be verified on a real device (camera,
//  torch, a finger/face). This file is compile-verified; behaviour is device-checked.
//

#if canImport(AVFoundation) && canImport(Observation)
import Foundation
import Observation

@MainActor
@Observable
public final class CameraRPPGBioPublisher {

    public private(set) var isRunning = false

    @ObservationIgnored nonisolated(unsafe) private let capture = CameraCapture()
    @ObservationIgnored nonisolated(unsafe) private let analyzer = CameraAnalyzer()
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var publishTask: Task<Void, Never>?

    public init() {}

    /// Start the camera, drive the analyzer from captured frames, and publish
    /// confident pulse estimates to the bus. No-op if already running.
    public func start(publishing bus: EngineBus) async {
        guard !isRunning else { return }
        self.bus = bus
        analyzer.startPulseDetection()

        let analyzer = self.analyzer
        capture.onFrame = { pixelBuffer in
            analyzer.analyzePixelBuffer(pixelBuffer)
        }

        do {
            try await capture.start()
        } catch {
            log.log(.warning, category: .biofeedback, "Camera rPPG failed to start: \(error.localizedDescription)")
            capture.onFrame = nil
            analyzer.stopPulseDetection()
            return
        }

        isRunning = true
        publishTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRunning, let bus = self.bus else { break }
                let bpm = self.analyzer.estimatedBPM
                guard bpm > 0, self.analyzer.bpmConfidence >= 0.4 else { continue }
                let hrv = Float(min(max(self.analyzer.rmssd / 200.0, 0), 1))
                let quality = Float(min(max(self.analyzer.signalQuality, 0), 1))
                bus.publish(bio: BioSampleFrame(
                    timestamp: CFAbsoluteTimeGetCurrent(),
                    heartRateBPM: Float(bpm),
                    hrvNormalized: hrv,
                    breathRate: 0,
                    breathPhase: 0,
                    coherence: quality,
                    motionEnergy: 0,
                    source: .cameraPPG
                ))
            }
        }
    }

    public func stop() {
        publishTask?.cancel()
        publishTask = nil
        capture.stop()
        capture.onFrame = nil
        analyzer.stopPulseDetection()
        isRunning = false
    }
}
#endif
