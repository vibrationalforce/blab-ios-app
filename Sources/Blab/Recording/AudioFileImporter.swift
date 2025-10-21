import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Handles importing audio files into sessions
@MainActor
class AudioFileImporter: ObservableObject {

    // MARK: - Published Properties

    @Published var isImporting: Bool = false
    @Published var importProgress: Double = 0.0
    @Published var importError: String?

    // MARK: - Supported Formats

    static let supportedFormats: [UTType] = [
        .audio,
        .mp3,
        .wav,
        .aiff,
        .m4a
    ]

    // MARK: - Import Methods

    /// Import audio file and add to session as new track
    func importAudioFile(from url: URL, to session: inout Session, trackName: String? = nil) async throws -> Track {
        isImporting = true
        importProgress = 0.0
        importError = nil

        defer {
            isImporting = false
            importProgress = 0.0
        }

        // Validate file
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.fileNotFound
        }

        // Check file size (max 100MB)
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        guard fileSize < 100_000_000 else {
            throw ImportError.fileTooLarge
        }

        importProgress = 0.1

        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat

        guard format.sampleRate > 0 else {
            throw ImportError.invalidFormat
        }

        importProgress = 0.3

        // Create destination URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionDir = documentsPath.appendingPathComponent("Sessions/\(session.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let trackID = UUID()
        let destURL = sessionDir.appendingPathComponent("\(trackID.uuidString).caf")

        importProgress = 0.5

        // Convert to app format (48kHz, stereo, float32)
        try await convertAudioFile(from: url, to: destURL, format: audioFile.processingFormat)

        importProgress = 0.8

        // Create track
        var track = Track(
            name: trackName ?? url.deletingPathExtension().lastPathComponent,
            type: .audio
        )
        track.url = destURL
        track.duration = Double(audioFile.length) / format.sampleRate

        // Generate waveform
        track.generateWaveform()

        importProgress = 1.0

        print("📥 Imported audio file: \(track.name)")
        return track
    }

    /// Convert audio file to app format
    private func convertAudioFile(from sourceURL: URL, to destURL: URL, format sourceFormat: AVAudioFormat) async throws {
        let sourceFile = try AVAudioFile(forReading: sourceURL)

        // Create destination format (48kHz, stereo, float32)
        guard let destFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ) else {
            throw ImportError.conversionFailed
        }

        let destFile = try AVAudioFile(
            forWriting: destURL,
            settings: destFormat.settings,
            commonFormat: destFormat.commonFormat,
            interleaved: destFormat.isInterleaved
        )

        // Create converter
        guard let converter = AVAudioConverter(from: sourceFormat, to: destFormat) else {
            throw ImportError.conversionFailed
        }

        // Convert in chunks
        let bufferSize: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: bufferSize) else {
            throw ImportError.conversionFailed
        }

        while sourceFile.framePosition < sourceFile.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(sourceFile.length - sourceFile.framePosition))
            inputBuffer.frameLength = framesToRead

            try sourceFile.read(into: inputBuffer)

            // Convert buffer
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: bufferSize) else {
                throw ImportError.conversionFailed
            }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let error = error {
                throw ImportError.conversionFailed
            }

            // Write to destination
            try destFile.write(from: outputBuffer)

            // Update progress
            let progress = 0.5 + (Double(sourceFile.framePosition) / Double(sourceFile.length)) * 0.3
            await MainActor.run {
                self.importProgress = progress
            }
        }
    }

    /// Import multiple files at once
    func importMultipleFiles(urls: [URL], to session: inout Session) async throws -> [Track] {
        var importedTracks: [Track] = []

        for (index, url) in urls.enumerated() {
            do {
                let track = try await importAudioFile(from: url, to: &session)
                importedTracks.append(track)

                // Update overall progress
                let overallProgress = Double(index + 1) / Double(urls.count)
                importProgress = overallProgress
            } catch {
                print("❌ Failed to import \(url.lastPathComponent): \(error)")
                // Continue with other files
            }
        }

        return importedTracks
    }

    /// Validate audio file before import
    func validateAudioFile(url: URL) -> Bool {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat

            // Check sample rate
            guard format.sampleRate >= 44100 else { return false }

            // Check duration (max 1 hour)
            let duration = Double(audioFile.length) / format.sampleRate
            guard duration <= 3600 else { return false }

            return true
        } catch {
            return false
        }
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case fileNotFound
    case fileTooLarge
    case invalidFormat
    case conversionFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .fileTooLarge:
            return "File size exceeds 100MB limit"
        case .invalidFormat:
            return "Invalid audio format"
        case .conversionFailed:
            return "Failed to convert audio file"
        case .unsupportedFormat:
            return "Unsupported audio format"
        }
    }
}

// MARK: - SwiftUI Document Picker Helper

#if os(iOS)
import SwiftUI

struct AudioFilePicker: UIViewControllerRepresentable {
    @Binding var selectedURLs: [URL]
    var allowsMultipleSelection: Bool = false

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: AudioFileImporter.supportedFormats,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioFilePicker

        init(_ parent: AudioFilePicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.selectedURLs = urls
        }
    }
}
#endif
