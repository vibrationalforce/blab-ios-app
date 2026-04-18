#if canImport(AVFoundation)
import AVFoundation
import Accelerate
import Observation

/// Mastering + export for a completed improvisation session.
/// Takes the raw .caf from RetroCapture, applies LUFS normalization,
/// and exports a release-ready file (WAV/AAC) ready for sharing.
///
/// Usage:
///   let exporter = SingleExport()
///   try await exporter.export(sourceURL: cafURL, targetLUFS: -14, format: .aac)
///   // → returns URL to finished file
@MainActor @Observable
final class SingleExport {

    // MARK: - Export format

    enum OutputFormat: CaseIterable, Identifiable {
        case wav, aac

        var id: String { label }

        var label: String {
            switch self {
            case .wav: return "WAV (lossless)"
            case .aac: return "AAC (streaming)"
            }
        }

        var fileExtension: String {
            switch self {
            case .wav: return "wav"
            case .aac: return "m4a"
            }
        }

        var avFileType: AVFileType {
            switch self {
            case .wav: return .wav
            case .aac: return .m4a
            }
        }
    }

    // MARK: - State

    enum ExportState: Equatable {
        case idle
        case analyzing
        case exporting(progress: Float)
        case done(URL)
        case error(String)

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }

        var exportedURL: URL? {
            if case .done(let url) = self { return url }
            return nil
        }
    }

    private(set) var exportState: ExportState = .idle
    var outputFormat: OutputFormat = .aac
    var targetLUFS: Float = -14

    // MARK: - Export

    func export(sourceURL: URL) async {
        guard exportState == .idle else { return }
        exportState = .analyzing
        log.log(.info, category: .audio, "SingleExport: analyzing \(sourceURL.lastPathComponent)")

        do {
            let outputURL = try makeOutputURL(sourceURL: sourceURL)
            let gainDB = try await measureLUFS(sourceURL: sourceURL)
            let normalizeGain = targetLUFS - gainDB    // positive = boost, negative = cut
            let clampedGain = Swift.min(Swift.max(normalizeGain, -12), 12)

            exportState = .exporting(progress: 0)
            log.log(.info, category: .audio, "SingleExport: gain \(String(format: "%.1f", clampedGain))dB → \(outputFormat.label)")

            try await renderWithGain(sourceURL: sourceURL, outputURL: outputURL, gainDB: clampedGain)
            exportState = .done(outputURL)
            log.log(.info, category: .audio, "SingleExport complete → \(outputURL.lastPathComponent)")
        } catch {
            exportState = .error(error.localizedDescription)
            log.log(.error, category: .audio, "SingleExport failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        exportState = .idle
    }

    // MARK: - LUFS measurement (BS.1770 approximation via RMS)

    private func measureLUFS(sourceURL: URL) async throws -> Float {
        let asset = AVAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack
        }
        _ = track   // confirm audio track present

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: outputSettings)
        reader.add(readerOutput)
        guard reader.startReading() else {
            throw ExportError.cannotReadSource
        }

        var sumOfSquares: Double = 0
        var sampleCount: Int = 0

        while let buffer = readerOutput.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                        lengthAtOffsetOut: &lengthAtOffset,
                                        totalLengthOut: &totalLength,
                                        dataPointerOut: &dataPointer)
            guard let ptr = dataPointer else { continue }
            let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: totalLength / 4)
            let count = totalLength / 4
            var rms: Float = 0
            vDSP_measqv(floatPtr, 1, &rms, vDSP_Length(count))
            sumOfSquares += Double(rms) * Double(count)
            sampleCount += count
        }

        guard sampleCount > 0 else { throw ExportError.emptyAudio }
        let rmsOverall = Float(sqrt(sumOfSquares / Double(sampleCount)))
        guard rmsOverall > 0.000001 else { return -60 }
        let dBFS = 20 * log10f(rmsOverall)
        return dBFS - 0.1   // BS.1770 K-weighting approximation
    }

    // MARK: - Render with gain

    private func renderWithGain(sourceURL: URL, outputURL: URL, gainDB: Float) async throws {
        let asset = AVAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack
        }

        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)
        let inputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: inputSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: outputFormat.avFileType)
        let outputSettings = makeOutputSettings()
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard reader.startReading() else { throw ExportError.cannotReadSource }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let linearGain = pow(10, gainDB / 20)
        let durationSeconds = CMTimeGetSeconds(duration)

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.echoelmusic.export")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }

                    // Apply gain in-place on the PCM data
                    if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        var lengthAtOffset = 0
                        var totalLength = 0
                        var dataPointer: UnsafeMutablePointer<Int8>?
                        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                                    lengthAtOffsetOut: &lengthAtOffset,
                                                    totalLengthOut: &totalLength,
                                                    dataPointerOut: &dataPointer)
                        if let ptr = dataPointer {
                            let floatPtr = UnsafeMutableRawPointer(ptr).bindMemory(to: Float.self, capacity: totalLength / 4)
                            var gain = linearGain
                            vDSP_vsmul(floatPtr, 1, &gain, floatPtr, 1, vDSP_Length(totalLength / 4))
                        }
                    }

                    // Update progress
                    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    let progress = durationSeconds > 0 ? Float(pts / durationSeconds) : 0
                    Task { @MainActor [weak self] in
                        if case .exporting = self?.exportState {
                            self?.exportState = .exporting(progress: Swift.min(progress, 0.99))
                        }
                    }

                    writerInput.append(sampleBuffer)
                }
            }
        }
    }

    // MARK: - Output settings

    private func makeOutputSettings() -> [String: Any] {
        switch outputFormat {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
            ]
        }
    }

    // MARK: - Output URL

    private func makeOutputURL(sourceURL: URL) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exports = docs.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let filename = "\(basename)_master.\(outputFormat.fileExtension)"
        return exports.appendingPathComponent(filename)
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case noAudioTrack, cannotReadSource, emptyAudio

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:    return "No audio track found in recording"
            case .cannotReadSource: return "Cannot read source recording"
            case .emptyAudio:      return "Recording appears to be silent"
            }
        }
    }
}
#endif
