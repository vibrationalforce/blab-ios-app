import Foundation
import AVFoundation

/// Represents a single audio track in a recording session
struct Track: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: URL?
    var duration: TimeInterval
    var volume: Float
    var pan: Float
    var isMuted: Bool
    var isSoloed: Bool
    var effects: [String]  // Node IDs
    var waveformData: [Float]?
    var createdAt: Date
    var modifiedAt: Date

    // MARK: - Track Type

    var type: TrackType

    enum TrackType: String, Codable {
        case audio = "Audio"
        case voice = "Voice"
        case binaural = "Binaural"
        case spatial = "Spatial"
        case master = "Master"
    }


    // MARK: - Initialization

    init(
        name: String,
        type: TrackType = .audio,
        volume: Float = 0.8,
        pan: Float = 0.0
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.url = nil
        self.duration = 0
        self.volume = volume
        self.pan = pan
        self.isMuted = false
        self.isSoloed = false
        self.effects = []
        self.waveformData = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
    }


    // MARK: - Audio File Management

    /// Set audio file URL for this track
    mutating func setAudioFile(_ url: URL) {
        self.url = url
        self.modifiedAt = Date()

        // Get duration from file
        if let asset = try? AVAudioFile(forReading: url) {
            self.duration = Double(asset.length) / asset.fileFormat.sampleRate
        }
    }

    /// Generate waveform data for visualization
    mutating func generateWaveform(samples: Int = 100) {
        guard let url = url else { return }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ) else { return }

            try file.read(into: buffer)

            // Sample buffer for waveform
            guard let channelData = buffer.floatChannelData?[0] else { return }

            var waveform: [Float] = []
            let samplesPerPoint = Int(frameCount) / samples

            for i in 0..<samples {
                let startIndex = i * samplesPerPoint
                let endIndex = min(startIndex + samplesPerPoint, Int(frameCount))

                var sum: Float = 0
                for j in startIndex..<endIndex {
                    sum += abs(channelData[j])
                }

                let average = sum / Float(endIndex - startIndex)
                waveform.append(average)
            }

            self.waveformData = waveform

        } catch {
            print("❌ Failed to generate waveform: \(error)")
        }
    }


    // MARK: - Effects Management

    mutating func addEffect(_ nodeID: String) {
        effects.append(nodeID)
        modifiedAt = Date()
    }

    mutating func removeEffect(_ nodeID: String) {
        effects.removeAll { $0 == nodeID }
        modifiedAt = Date()
    }


    // MARK: - Playback State

    var isPlaying: Bool = false


    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, name, url, duration, volume, pan
        case isMuted, isSoloed, effects, waveformData
        case createdAt, modifiedAt, type
    }
}


// MARK: - Track Presets

extension Track {
    /// Create voice track preset
    static func voiceTrack() -> Track {
        var track = Track(name: "Voice", type: .voice)
        track.volume = 0.9
        return track
    }

    /// Create binaural beats track
    static func binauralTrack() -> Track {
        var track = Track(name: "Binaural Beats", type: .binaural)
        track.volume = 0.3
        return track
    }

    /// Create spatial audio track
    static func spatialTrack() -> Track {
        var track = Track(name: "Spatial", type: .spatial)
        track.volume = 0.7
        return track
    }

    /// Create master mix track
    static func masterTrack() -> Track {
        var track = Track(name: "Master", type: .master)
        track.volume = 1.0
        return track
    }
}
