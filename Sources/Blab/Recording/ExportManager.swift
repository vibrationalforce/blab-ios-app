import Foundation
import AVFoundation

/// Manages export of recording sessions to various formats
/// Handles audio mixdown, bio-data export, and format conversion
@MainActor
class ExportManager {

    // MARK: - Export Formats

    enum ExportFormat {
        case wav
        case m4a
        case aiff
        case caf

        var fileExtension: String {
            switch self {
            case .wav: return "wav"
            case .m4a: return "m4a"
            case .aiff: return "aiff"
            case .caf: return "caf"
            }
        }

        var audioFormatID: AudioFormatID {
            switch self {
            case .wav: return kAudioFormatLinearPCM
            case .m4a: return kAudioFormatMPEG4AAC
            case .aiff: return kAudioFormatLinearPCM
            case .caf: return kAudioFormatAppleLossless
            }
        }

        var fileType: AVFileType {
            switch self {
            case .wav: return .wav
            case .m4a: return .m4a
            case .aiff: return .aiff
            case .caf: return .caf
            }
        }
    }

    enum BioDataFormat {
        case json
        case csv

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            }
        }
    }


    // MARK: - Export Methods

    /// Export session audio to file
    /// - Parameters:
    ///   - session: Session to export
    ///   - format: Audio format
    ///   - outputURL: Destination URL (optional, will generate if nil)
    /// - Returns: URL of exported file
    func exportAudio(
        session: Session,
        format: ExportFormat = .wav,
        outputURL: URL? = nil
    ) async throws -> URL {
        // Determine output URL
        let exportURL = outputURL ?? defaultExportURL(for: session, format: format)

        // If session has multiple tracks, mix them down
        if session.tracks.count > 1 {
            try await mixdownTracks(session: session, outputURL: exportURL, format: format)
        } else if let track = session.tracks.first, let trackURL = track.url {
            // Single track - just convert format
            try await convertAudioFormat(inputURL: trackURL, outputURL: exportURL, format: format)
        } else {
            throw RecordingError.fileNotFound
        }

        print("📤 Exported audio: \(exportURL.lastPathComponent)")
        return exportURL
    }

    /// Export bio-data to file
    /// - Parameters:
    ///   - session: Session to export
    ///   - format: Bio-data format
    ///   - outputURL: Destination URL (optional)
    /// - Returns: URL of exported file
    func exportBioData(
        session: Session,
        format: BioDataFormat = .json,
        outputURL: URL? = nil
    ) throws -> URL {
        let exportURL = outputURL ?? defaultBioDataURL(for: session, format: format)

        switch format {
        case .json:
            try exportBioDataJSON(session: session, outputURL: exportURL)
        case .csv:
            try exportBioDataCSV(session: session, outputURL: exportURL)
        }

        print("📤 Exported bio-data: \(exportURL.lastPathComponent)")
        return exportURL
    }

    /// Export complete session package (audio + bio-data + metadata)
    /// - Parameters:
    ///   - session: Session to export
    ///   - outputDirectory: Destination directory
    /// - Returns: URL of exported directory
    func exportSessionPackage(
        session: Session,
        outputDirectory: URL? = nil
    ) async throws -> URL {
        let packageURL = outputDirectory ?? defaultPackageURL(for: session)

        // Create package directory
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        // Export audio
        let audioURL = packageURL.appendingPathComponent("audio.wav")
        _ = try await exportAudio(session: session, format: .wav, outputURL: audioURL)

        // Export bio-data
        let bioDataURL = packageURL.appendingPathComponent("biodata.json")
        _ = try exportBioData(session: session, format: .json, outputURL: bioDataURL)

        // Export session metadata
        let metadataURL = packageURL.appendingPathComponent("session.json")
        try exportSessionMetadata(session: session, outputURL: metadataURL)

        // Copy individual tracks
        let tracksDir = packageURL.appendingPathComponent("tracks", isDirectory: true)
        try FileManager.default.createDirectory(at: tracksDir, withIntermediateDirectories: true)

        for track in session.tracks {
            if let trackURL = track.url {
                let destURL = tracksDir.appendingPathComponent("\(track.name).\(ExportFormat.caf.fileExtension)")
                try FileManager.default.copyItem(at: trackURL, to: destURL)
            }
        }

        print("📦 Exported session package: \(packageURL.lastPathComponent)")
        return packageURL
    }


    // MARK: - Audio Processing

    /// Mix multiple tracks into single audio file
    private func mixdownTracks(
        session: Session,
        outputURL: URL,
        format: ExportFormat
    ) async throws {
        let composition = AVMutableComposition()

        // Add each track to composition
        for track in session.tracks where !track.isMuted {
            guard let trackURL = track.url else { continue }

            let asset = AVURLAsset(url: trackURL)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }

            let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )

            let duration = try await assetTrack.load(.timeRange).duration

            try compositionTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: assetTrack,
                at: .zero
            )

            // Apply volume and pan
            compositionTrack?.preferredVolume = track.volume
        }

        // Export mixed composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecordingError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = format.fileType

        await exportSession.export()

        if let error = exportSession.error {
            throw RecordingError.exportFailed(error.localizedDescription)
        }
    }

    /// Convert audio file format
    private func convertAudioFormat(
        inputURL: URL,
        outputURL: URL,
        format: ExportFormat
    ) async throws {
        let asset = AVURLAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecordingError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = format.fileType

        await exportSession.export()

        if let error = exportSession.error {
            throw RecordingError.exportFailed(error.localizedDescription)
        }
    }


    // MARK: - Bio-Data Export

    /// Export bio-data as JSON
    private func exportBioDataJSON(session: Session, outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(session.bioData)
        try data.write(to: outputURL)
    }

    /// Export bio-data as CSV
    private func exportBioDataCSV(session: Session, outputURL: URL) throws {
        var csv = "Timestamp,HRV,HeartRate,Coherence,AudioLevel,Frequency\n"

        for dataPoint in session.bioData {
            csv += "\(dataPoint.timestamp),"
            csv += "\(dataPoint.hrv),"
            csv += "\(dataPoint.heartRate),"
            csv += "\(dataPoint.coherence),"
            csv += "\(dataPoint.audioLevel),"
            csv += "\(dataPoint.frequency)\n"
        }

        try csv.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// Export session metadata as JSON
    private func exportSessionMetadata(session: Session, outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Create metadata structure
        let metadata: [String: Any] = [
            "id": session.id.uuidString,
            "name": session.name,
            "duration": session.duration,
            "tempo": session.tempo,
            "timeSignature": [
                "beats": session.timeSignature.beats,
                "noteValue": session.timeSignature.noteValue
            ],
            "trackCount": session.tracks.count,
            "bioDataPointCount": session.bioData.count,
            "averageHRV": session.averageHRV,
            "averageHeartRate": session.averageHeartRate,
            "averageCoherence": session.averageCoherence,
            "createdAt": ISO8601DateFormatter().string(from: session.createdAt),
            "modifiedAt": ISO8601DateFormatter().string(from: session.modifiedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputURL)
    }


    // MARK: - URL Helpers

    /// Generate default export URL for audio
    private func defaultExportURL(for session: Session, format: ExportFormat) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDir = documentsPath.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let filename = "\(session.name)_\(dateString()).\(format.fileExtension)"
        return exportsDir.appendingPathComponent(filename)
    }

    /// Generate default export URL for bio-data
    private func defaultBioDataURL(for session: Session, format: BioDataFormat) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDir = documentsPath.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let filename = "\(session.name)_biodata_\(dateString()).\(format.fileExtension)"
        return exportsDir.appendingPathComponent(filename)
    }

    /// Generate default package URL
    private func defaultPackageURL(for session: Session) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDir = documentsPath.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let packageName = "\(session.name)_\(dateString())"
        return exportsDir.appendingPathComponent(packageName, isDirectory: true)
    }

    /// Generate timestamp string for filenames
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}


// MARK: - Share Sheet Helper

#if os(iOS)
import UIKit

extension ExportManager {
    /// Present iOS share sheet for exported file
    func shareFile(url: URL, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        viewController.present(activityVC, animated: true)
    }
}
#endif
