import Foundation

/// Export metadata that accompanies audio renders. Designed to be compatible
/// with schema.org music releases while remaining simple to serialize.
struct BlabMetadata: Codable {
    let id: UUID
    let title: String
    let bpm: Double
    let emotion: String
    let instruments: [String]
    let spatial: String
    let date: Date
    let duration: TimeInterval
    let coherence: Double

    init(id: UUID = UUID(), title: String, bpm: Double, emotion: String, instruments: [String], spatial: String, date: Date = Date(), duration: TimeInterval, coherence: Double) {
        self.id = id
        self.title = title
        self.bpm = bpm
        self.emotion = emotion
        self.instruments = instruments
        self.spatial = spatial
        self.date = date
        self.duration = duration
        self.coherence = coherence
    }

    static func from(session: Session, bioVector: BioSignalProvider.NormalizedVector?) -> BlabMetadata {
        let emotion = bioVector?.emotion.label ?? session.metadata.mood ?? "Unknown"
        let coherence = bioVector?.coherence ?? session.averageCoherence
        let instruments = session.tracks.map { $0.name }
        let spatialDescription = instruments.contains { $0.lowercased().contains("spatial") } ? "3D" : "Stereo"

        return BlabMetadata(
            id: session.id,
            title: session.name,
            bpm: session.tempo,
            emotion: emotion,
            instruments: instruments,
            spatial: spatialDescription,
            date: session.modifiedAt,
            duration: session.duration,
            coherence: coherence
        )
    }
}
