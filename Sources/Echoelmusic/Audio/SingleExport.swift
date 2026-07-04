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

    // Bar-aligned loop trim (audit C6/C7). When `trimLengthSeconds` is set, ONLY
    // the window [duration − trimFromEnd − length, +length] of the source is
    // measured AND rendered — the exact loop, cut from the end of the capture
    // (window math: StudioCalculator.loopTrimWindow). Falls back to an unaligned
    // end cut, then to the untrimmed file, when the capture is too short.
    var trimLengthSeconds: Double?
    var trimFromEndSeconds: Double = 0
    /// Micro fade at the trimmed edges — kills residual seam ticks without an
    /// audible dip (~4 ms). Applied only when a trim window is active.
    var edgeFadeSeconds: Double = 0

    // MARK: - Export

    func export(sourceURL: URL) async {
        guard exportState == .idle else { return }
        exportState = .analyzing
        log.log(.info, category: .audio, "SingleExport: analyzing \(sourceURL.lastPathComponent)")

        do {
            let outputURL = try makeOutputURL(sourceURL: sourceURL)
            let timeRange = try await resolveTrimRange(sourceURL: sourceURL)
            let gainDB = try await measureLUFS(sourceURL: sourceURL, timeRange: timeRange)
            let normalizeGain = targetLUFS - gainDB    // positive = boost, negative = cut
            let clampedGain = Swift.min(Swift.max(normalizeGain, -12), 12)

            exportState = .exporting(progress: 0)
            log.log(.info, category: .audio, "SingleExport: gain \(String(format: "%.1f", clampedGain))dB → \(outputFormat.label)")

            try await renderWithGain(sourceURL: sourceURL, outputURL: outputURL,
                                     gainDB: clampedGain, timeRange: timeRange)
            exportState = .done(outputURL)
            log.log(.info, category: .audio, "SingleExport complete → \(outputURL.lastPathComponent)")
        } catch {
            exportState = .error(error.localizedDescription)
            log.log(.error, category: .audio, "SingleExport failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        exportState = .idle
        trimLengthSeconds = nil
        trimFromEndSeconds = 0
        edgeFadeSeconds = 0
    }

    /// The CMTimeRange to read, honouring the loop-trim window. nil = whole file.
    private func resolveTrimRange(sourceURL: URL) async throws -> CMTimeRange? {
        guard let length = trimLengthSeconds else { return nil }
        let asset = AVAsset(url: sourceURL)
        let fileDuration = CMTimeGetSeconds(try await asset.load(.duration))
        // Bar-aligned first; unaligned end cut second; untrimmed as the last resort
        // (an untrimmed export is today's behaviour — never fail the whole export
        // just because the capture came up short).
        let window = StudioCalculator.loopTrimWindow(fileDuration: fileDuration,
                                                     loopSeconds: length,
                                                     secondsSinceBarStart: trimFromEndSeconds)
            ?? StudioCalculator.loopTrimWindow(fileDuration: fileDuration,
                                               loopSeconds: length,
                                               secondsSinceBarStart: 0)
        guard let window else {
            log.log(.error, category: .audio,
                    "SingleExport: capture (\(String(format: "%.2f", fileDuration))s) shorter than loop — exporting untrimmed")
            return nil
        }
        let scale: CMTimeScale = 44_100
        return CMTimeRange(start: CMTime(seconds: window.start, preferredTimescale: scale),
                           duration: CMTime(seconds: window.duration, preferredTimescale: scale))
    }

    // MARK: - LUFS measurement (BS.1770 approximation via RMS)

    private func measureLUFS(sourceURL: URL, timeRange: CMTimeRange?) async throws -> Float {
        let asset = AVAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack
        }
        _ = track   // confirm audio track present

        let reader = try AVAssetReader(asset: asset)
        // Measure ONLY the loop window (C6): normalising against audio outside the
        // final cut would set the wrong gain for what actually ships in the file.
        if let timeRange { reader.timeRange = timeRange }
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
            // Walk the block by offset: only `lengthAtOffset` bytes are guaranteed
            // contiguous at each returned pointer; `totalLength` may span multiple
            // segments, so reading totalLength/4 from one pointer would over-read a
            // segmented buffer. LPCM reader output is normally single-segment, so
            // this loops once in the common case.
            var offset = 0
            var totalLength = 0
            repeat {
                var lengthAtOffset = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: offset,
                                            lengthAtOffsetOut: &lengthAtOffset,
                                            totalLengthOut: &totalLength,
                                            dataPointerOut: &dataPointer)
                guard let ptr = dataPointer, lengthAtOffset >= 4 else { break }
                let count = lengthAtOffset / 4
                let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: count)
                var rms: Float = 0
                vDSP_measqv(floatPtr, 1, &rms, vDSP_Length(count))
                sumOfSquares += Double(rms) * Double(count)
                sampleCount += count
                offset += lengthAtOffset
            } while offset < totalLength
        }

        guard sampleCount > 0 else { throw ExportError.emptyAudio }
        let rmsOverall = Float(sqrt(sumOfSquares / Double(sampleCount)))
        guard rmsOverall > 0.000001 else { return -60 }
        let dBFS = 20 * log10f(rmsOverall)
        return dBFS - 0.1   // BS.1770 K-weighting approximation
    }

    // MARK: - Render with gain

    private func renderWithGain(sourceURL: URL, outputURL: URL, gainDB: Float,
                                timeRange: CMTimeRange?) async throws {
        let asset = AVAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack
        }

        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)
        // Render ONLY the loop window (C6/C7): the output file is exactly one
        // bar-aligned loop, so it sits on the DAW grid and loops seamlessly.
        if let timeRange { reader.timeRange = timeRange }
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
        // With a trim window the reader delivers buffers stamped at their ORIGINAL
        // source times — the session must start at the window start or every
        // sample would be offset (silence at the head, tail cut off).
        writer.startSession(atSourceTime: timeRange?.start ?? .zero)

        let linearGain = pow(10, gainDB / 20)
        let windowStartSeconds = timeRange.map { CMTimeGetSeconds($0.start) } ?? 0
        let durationSeconds = timeRange.map { CMTimeGetSeconds($0.duration) }
            ?? CMTimeGetSeconds(duration)
        // Micro edge fades (loop seam safety): frame counts at the 44.1 kHz LPCM
        // reader rate, applied over interleaved stereo. Only the first/last
        // buffers ever intersect the fade zones, so the per-sample loop is cheap.
        let totalFrames = Int(durationSeconds * 44_100)
        let fadeFrames = edgeFadeSeconds > 0 ? Int(edgeFadeSeconds * 44_100) : 0
        var framesWritten = 0

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.echoelmusic.export")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }

                    let bufferFrames = CMSampleBufferGetNumSamples(sampleBuffer)
                    let bufferStartFrame = framesWritten

                    // Apply gain in-place on the PCM data
                    if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        // Walk segments by offset — applying gain to totalLength/4 from
                        // a single pointer would be an out-of-bounds WRITE on a
                        // segmented block. Loops once for the usual single-segment buffer.
                        var offset = 0
                        var totalLength = 0
                        var segmentStartFloat = 0
                        repeat {
                            var lengthAtOffset = 0
                            var dataPointer: UnsafeMutablePointer<Int8>?
                            CMBlockBufferGetDataPointer(blockBuffer, atOffset: offset,
                                                        lengthAtOffsetOut: &lengthAtOffset,
                                                        totalLengthOut: &totalLength,
                                                        dataPointerOut: &dataPointer)
                            guard let ptr = dataPointer, lengthAtOffset >= 4 else { break }
                            let n = lengthAtOffset / 4
                            let floatPtr = UnsafeMutableRawPointer(ptr).bindMemory(to: Float.self, capacity: n)
                            var gain = linearGain
                            vDSP_vsmul(floatPtr, 1, &gain, floatPtr, 1, vDSP_Length(n))

                            // Edge fades — interleaved stereo: float i belongs to
                            // frame (bufferStartFrame + (segmentStartFloat + i) / 2).
                            if fadeFrames > 0 {
                                let segStartFrame = bufferStartFrame + segmentStartFloat / 2
                                let segEndFrame = bufferStartFrame + (segmentStartFloat + n) / 2
                                if segStartFrame < fadeFrames || segEndFrame > totalFrames - fadeFrames {
                                    for i in 0..<n {
                                        let frame = bufferStartFrame + (segmentStartFloat + i) / 2
                                        var g: Float = 1
                                        if frame < fadeFrames {
                                            g = Float(frame) / Float(fadeFrames)
                                        }
                                        let fromEnd = totalFrames - 1 - frame
                                        if fromEnd < fadeFrames {
                                            g = Swift.min(g, Float(Swift.max(fromEnd, 0)) / Float(fadeFrames))
                                        }
                                        if g < 1 { floatPtr[i] *= g }
                                    }
                                }
                            }
                            segmentStartFloat += n
                            offset += lengthAtOffset
                        } while offset < totalLength
                    }
                    framesWritten = bufferStartFrame + bufferFrames

                    // Update progress (relative to the trimmed window when set)
                    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    let progress = durationSeconds > 0
                        ? Float((pts - windowStartSeconds) / durationSeconds) : 0
                    Task { @MainActor [weak self] in
                        if case .exporting = self?.exportState {
                            self?.exportState = .exporting(progress: Swift.min(Swift.max(progress, 0), 0.99))
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
                // AVAssetWriterInput requires ALL four AVLinearPCM* keys when any is
                // present; omitting this throws NSInvalidArgumentException at init.
                AVLinearPCMIsNonInterleaved: false,
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
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ExportError.noDocumentsDirectory
        }
        let exports = docs.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let filename = "\(basename)_master.\(outputFormat.fileExtension)"
        return exports.appendingPathComponent(filename)
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case noAudioTrack, cannotReadSource, emptyAudio, noDocumentsDirectory

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:    return "No audio track found in recording"
            case .cannotReadSource: return "Cannot read source recording"
            case .emptyAudio:      return "Recording appears to be silent"
            case .noDocumentsDirectory: return "Cannot locate the documents directory"
            }
        }
    }
}
#endif
