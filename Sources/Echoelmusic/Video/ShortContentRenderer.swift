#if canImport(AVFoundation) && canImport(CoreGraphics)
import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import Observation

/// Renders a short-form video clip (15/30/60s) combining the soundscape audio
/// with an animated waveform + bio data overlay. Output: 9:16 MP4 for TikTok/Reels/Shorts.
///
/// Audio source: RetroCapture ring buffer (existing recorded CAF file)
/// Video: CGContext frames drawn at 30fps — waveform bars + HR/coherence overlay
@MainActor @Observable
final class ShortContentRenderer {

    // MARK: - State

    enum RendererState: Equatable {
        case idle
        case rendering(progress: Double)
        case done(url: URL)
        case error(String)

        static func == (lhs: RendererState, rhs: RendererState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.done(let a), .done(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            case (.rendering(let a), .rendering(let b)): return a == b
            default: return false
            }
        }
    }

    private(set) var rendererState: RendererState = .idle

    // MARK: - Video config

    private let videoWidth  = 720
    private let videoHeight = 1280
    private let fps: Int    = 30

    // MARK: - Public entry point

    /// Render a short clip from a recorded audio file with bio data overlay.
    ///
    /// - Parameters:
    ///   - duration: Clip length in seconds (15, 30, or 60)
    ///   - audioURL: Source audio file (from RetroCapture.lastURL)
    ///   - heartRate: Current HR to display (BPM integer)
    ///   - coherence: Current coherence 0-1
    ///   - hasBio: Whether live bio data is available
    ///   - waveformSamples: RMS bins from RetroCapture (200 values)
    func render(
        duration: Int,
        audioURL: URL,
        heartRate: Int,
        coherence: Double,
        hasBio: Bool,
        waveformSamples: [Float]
    ) async {
        guard rendererState == .idle else { return }
        rendererState = .rendering(progress: 0)

        do {
            let url = try await buildVideo(
                duration: duration,
                audioURL: audioURL,
                heartRate: heartRate,
                coherence: coherence,
                hasBio: hasBio,
                waveformSamples: waveformSamples
            )
            rendererState = .done(url: url)
        } catch {
            rendererState = .error(error.localizedDescription)
        }
    }

    func reset() { rendererState = .idle }

    // MARK: - Core Render Pipeline

    private func buildVideo(
        duration: Int,
        audioURL: URL,
        heartRate: Int,
        coherence: Double,
        hasBio: Bool,
        waveformSamples: [Float]
    ) async throws -> URL {
        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("echoelmusic_\(Int(Date().timeIntervalSince1970)).mp4")

        // Clean up any previous temp file
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // --- Video track ---
        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:  3_500_000,
                AVVideoProfileLevelKey:    AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String:           videoWidth,
            kCVPixelBufferHeightKey as String:          videoHeight
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )
        guard writer.canAdd(videoInput) else { throw RendererError.writerSetupFailed }
        writer.add(videoInput)

        // --- Audio track (passthrough from RetroCapture CAF) ---
        let audioAsset   = AVURLAsset(url: audioURL)
        let audioTracks  = try await audioAsset.loadTracks(withMediaType: .audio)
        var audioReader: AVAssetReader?
        var audioInput:  AVAssetWriterInput?

        if let srcTrack = audioTracks.first {
            let readerSettings: [String: Any] = [
                AVFormatIDKey:            kAudioFormatLinearPCM,
                AVSampleRateKey:          48000,
                AVNumberOfChannelsKey:    2,
                AVLinearPCMBitDepthKey:   32,
                AVLinearPCMIsFloatKey:    true,
                AVLinearPCMIsNonInterleaved: false
            ]
            let assetReader = try AVAssetReader(asset: audioAsset)
            let readerOutput = AVAssetReaderTrackOutput(track: srcTrack, outputSettings: readerSettings)
            guard assetReader.canAdd(readerOutput) else { throw RendererError.audioSetupFailed }
            assetReader.add(readerOutput)

            // Trim audio to requested duration
            let trimEnd = CMTime(seconds: Double(duration), preferredTimescale: 48000)
            let trimStart = max(
                CMTime.zero,
                CMTimeSubtract(try await audioAsset.load(.duration), trimEnd)
            )
            assetReader.timeRange = CMTimeRange(start: trimStart, duration: trimEnd)

            let writerSettings: [String: Any] = [
                AVFormatIDKey:          kAudioFormatMPEG4AAC,
                AVSampleRateKey:        48000,
                AVNumberOfChannelsKey:  2,
                AVEncoderBitRateKey:    128_000
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            ai.expectsMediaDataInRealTime = false
            guard writer.canAdd(ai) else { throw RendererError.writerSetupFailed }
            writer.add(ai)

            audioReader = assetReader
            audioInput  = ai
        }

        // --- Start writing ---
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        audioReader?.startReading()

        // Write video frames
        let totalFrames = duration * fps
        let timeScale   = CMTimeScale(fps)

        for frameIdx in 0..<totalFrames {
            // Update progress on main actor
            let progress = Double(frameIdx) / Double(totalFrames)
            rendererState = .rendering(progress: progress)

            // Wait until writer is ready
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            let pixelBuffer = try makePixelBuffer(
                frameIndex:      frameIdx,
                totalFrames:     totalFrames,
                heartRate:       heartRate,
                coherence:       coherence,
                hasBio:          hasBio,
                waveformSamples: waveformSamples
            )
            let pts = CMTime(value: CMTimeValue(frameIdx), timescale: timeScale)
            adaptor.append(pixelBuffer, withPresentationTime: pts)
        }
        videoInput.markAsFinished()

        // Write audio samples
        if let ai = audioInput, let reader = audioReader,
           let readerOutput = reader.outputs.first as? AVAssetReaderTrackOutput {
            while reader.status == .reading {
                while !ai.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
                if let sample = readerOutput.copyNextSampleBuffer() {
                    ai.append(sample)
                } else {
                    break
                }
            }
        }
        audioInput?.markAsFinished()

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? RendererError.writeFailed
        }
        return outputURL
    }

    // MARK: - Frame Generation

    private func makePixelBuffer(
        frameIndex: Int,
        totalFrames: Int,
        heartRate: Int,
        coherence: Double,
        hasBio: Bool,
        waveformSamples: [Float]
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey:       true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            videoWidth, videoHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw RendererError.pixelBufferFailed
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pb),
            width:            videoWidth,
            height:           videoHeight,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pb),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedFirst.rawValue |
                              CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw RendererError.contextFailed
        }

        let t = CGFloat(frameIndex) / CGFloat(max(totalFrames - 1, 1))
        drawFrame(ctx: ctx, t: t, heartRate: heartRate, coherence: coherence, hasBio: hasBio, samples: waveformSamples)

        return pb
    }

    // MARK: - Drawing

    private func drawFrame(
        ctx: CGContext,
        t: CGFloat,
        heartRate: Int,
        coherence: Double,
        hasBio: Bool,
        samples: [Float]
    ) {
        let W = CGFloat(videoWidth)
        let H = CGFloat(videoHeight)

        // Black background
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Waveform: centered band of bars
        drawWaveform(ctx: ctx, width: W, height: H, t: t, samples: samples, coherence: coherence)

        // Bio overlay: HR + coherence dot
        if hasBio {
            drawBioOverlay(ctx: ctx, width: W, height: H, heartRate: heartRate, coherence: coherence)
        }

        // Subtle branding at bottom
        drawBranding(ctx: ctx, width: W, height: H)
    }

    private func drawWaveform(ctx: CGContext, width W: CGFloat, height H: CGFloat, t: CGFloat, samples: [Float], coherence: Double) {
        guard !samples.isEmpty else { return }

        let displayCount = min(samples.count, 60)
        let barW   = W * 0.65 / CGFloat(displayCount)
        let gap    = barW * 0.35
        let totalW = CGFloat(displayCount) * (barW + gap)
        let startX = (W - totalW) / 2
        let centerY = H * 0.50

        // Max bar height scales with coherence (calm = taller, flowing bars)
        let maxH = H * (0.10 + coherence * 0.12)

        // Slow oscillation tied to time position for organic feel
        let phase = t * CGFloat.pi * 6

        for i in 0..<displayCount {
            let srcIdx = i * samples.count / displayCount
            let base = CGFloat(samples[srcIdx])
            // Subtle per-bar animation (avoid strobe — max 3Hz visual movement)
            let anim = sin(phase + CGFloat(i) * 0.25) * 0.06
            let amp  = min(max(base + CGFloat(anim), 0.02), 1.0)
            let bH   = max(amp * maxH, 2)

            let x = startX + CGFloat(i) * (barW + gap)
            let y = centerY - bH / 2

            let opacity = CGFloat(0.20 + amp * 0.50)
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: opacity)

            // Rounded rect bars
            let rect = CGRect(x: x, y: y, width: barW, height: bH)
            let path = CGPath(roundedRect: rect, cornerWidth: barW * 0.3, cornerHeight: barW * 0.3, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    private func drawBioOverlay(ctx: CGContext, width W: CGFloat, height H: CGFloat, heartRate: Int, coherence: Double) {
        // Coherence dot
        let dotX = W / 2
        let dotY = H * 0.72
        let dotR = CGFloat(5 + coherence * 4)
        let dotAlpha = CGFloat(0.4 + coherence * 0.5)
        let dotColor: (CGFloat, CGFloat, CGFloat) = coherence > 0.6 ? (0.4, 0.9, 0.5) : coherence > 0.3 ? (0.9, 0.8, 0.3) : (0.9, 0.4, 0.3)
        ctx.setFillColor(red: dotColor.0, green: dotColor.1, blue: dotColor.2, alpha: dotAlpha)
        ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))

        // HR number (large, light)
        drawText(
            ctx: ctx,
            text: "\(heartRate)",
            fontName: "HelveticaNeue-UltraLight",
            size: 96,
            alpha: 0.80,
            centerX: W / 2,
            y: H * 0.74
        )
        // "BPM" label
        drawText(
            ctx: ctx,
            text: "BPM",
            fontName: "HelveticaNeue",
            size: 13,
            alpha: 0.28,
            centerX: W / 2,
            y: H * 0.74 - 36
        )
    }

    private func drawBranding(ctx: CGContext, width W: CGFloat, height H: CGFloat) {
        drawText(
            ctx: ctx,
            text: "Echoelmusic",
            fontName: "HelveticaNeue-Light",
            size: 16,
            alpha: 0.18,
            centerX: W / 2,
            y: H * 0.06
        )
    }

    private func drawText(ctx: CGContext, text: String, fontName: String, size: CGFloat, alpha: CGFloat, centerX: CGFloat, y: CGFloat) {
        let font  = CTFontCreateWithName(fontName as CFString, size, nil)
        let color = CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let as_ = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(as_)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: centerX - bounds.width / 2, y: y)
        CTLineDraw(line, ctx)
    }
}

// MARK: - Errors

enum RendererError: LocalizedError {
    case writerSetupFailed
    case audioSetupFailed
    case pixelBufferFailed
    case contextFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writerSetupFailed: return "Video writer setup failed"
        case .audioSetupFailed:  return "Audio reader setup failed"
        case .pixelBufferFailed: return "Pixel buffer allocation failed"
        case .contextFailed:     return "Graphics context creation failed"
        case .writeFailed:       return "Video file write failed"
        }
    }
}
#endif
