import Foundation
import SwiftUI
import Observation

/// Coordinates a timed audio capture and produces a ShareLink.
/// Uses RetroCapture for audio. Capture = audio only (visual is always live).
@MainActor @Observable
final class MomentCapture {

    enum CaptureState: Equatable {
        case idle
        case recording(elapsed: TimeInterval)
        case processing
        case done(URL)
        case error(String)

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }
    }

    private(set) var state: CaptureState = .idle
    var maxDuration: TimeInterval = 60

    @ObservationIgnored private weak var retroCapture: RetroCapture?
    @ObservationIgnored private weak var singleExport: SingleExport?
    @ObservationIgnored private var elapsedTimer: Timer?
    @ObservationIgnored private var elapsed: TimeInterval = 0

    func connect(retroCapture: RetroCapture, singleExport: SingleExport) {
        self.retroCapture = retroCapture
        self.singleExport = singleExport
    }

    func startCapture() {
        guard case .idle = state else { return }
        retroCapture?.startRecording()
        elapsed = 0
        state = .recording(elapsed: 0)
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed += 0.25
                if case .recording = self.state {
                    self.state = .recording(elapsed: self.elapsed)
                }
                if self.elapsed >= self.maxDuration {
                    self.stopCapture()
                }
            }
        }
        log.log(.info, category: .audio, "MomentCapture: recording started")
    }

    func stopCapture() {
        guard case .recording = state else { return }
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        state = .processing

        retroCapture?.stopRecording { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                await self.masterAndFinish(sourceURL: url)
            }
        }
    }

    func reset() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsed = 0
        retroCapture?.stopRecording()
        singleExport?.reset()
        state = .idle
    }

    // MARK: - Private

    private func masterAndFinish(sourceURL: URL) async {
        guard let exporter = singleExport else {
            state = .done(sourceURL)
            return
        }
        exporter.reset()
        await exporter.export(sourceURL: sourceURL)
        switch exporter.exportState {
        case .done(let url):
            state = .done(url)
            log.log(.info, category: .audio, "MomentCapture: export done → \(url.lastPathComponent)")
        case .error(let msg):
            state = .error(msg)
        default:
            state = .done(sourceURL)
        }
    }
}
