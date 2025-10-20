import Foundation

/// Recording session containing multiple tracks and settings
struct Session: Identifiable, Codable {
    let id: UUID
    var name: String
    var tracks: [Track]
    var tempo: Double
    var timeSignature: TimeSignature
    var duration: TimeInterval
    var createdAt: Date
    var modifiedAt: Date
    var bioData: [BioDataPoint]
    var metadata: SessionMetadata


    // MARK: - Initialization

    init(name: String, tempo: Double = 120.0) {
        self.id = UUID()
        self.name = name
        self.tracks = []
        self.tempo = tempo
        self.timeSignature = TimeSignature(numerator: 4, denominator: 4)
        self.duration = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.bioData = []
        self.metadata = SessionMetadata()
    }


    // MARK: - Track Management

    mutating func addTrack(_ track: Track) {
        tracks.append(track)
        modifiedAt = Date()
    }

    mutating func removeTrack(id: UUID) {
        tracks.removeAll { $0.id == id }
        modifiedAt = Date()
    }

    mutating func updateTrack(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
            modifiedAt = Date()
        }
    }


    // MARK: - Bio Data Management

    mutating func addBioDataPoint(_ point: BioDataPoint) {
        bioData.append(point)
    }

    mutating func clearBioData() {
        bioData.removeAll()
    }


    // MARK: - Session Statistics

    var averageHRV: Double {
        guard !bioData.isEmpty else { return 0 }
        let sum = bioData.reduce(0.0) { $0 + $1.hrv }
        return sum / Double(bioData.count)
    }

    var averageHeartRate: Double {
        guard !bioData.isEmpty else { return 60 }
        let sum = bioData.reduce(0.0) { $0 + $1.heartRate }
        return sum / Double(bioData.count)
    }

    var averageCoherence: Double {
        guard !bioData.isEmpty else { return 50 }
        let sum = bioData.reduce(0.0) { $0 + $1.coherence }
        return sum / Double(bioData.count)
    }


    // MARK: - File Management

    /// Get session directory URL
    func getSessionDirectory() -> URL {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        return documentsPath
            .appendingPathComponent("Sessions")
            .appendingPathComponent(id.uuidString)
    }

    /// Create session directory
    func createSessionDirectory() throws {
        let sessionDir = getSessionDirectory()
        try FileManager.default.createDirectory(
            at: sessionDir,
            withIntermediateDirectories: true
        )
    }

    /// Save session to disk
    func save() throws {
        try createSessionDirectory()

        let sessionFile = getSessionDirectory()
            .appendingPathComponent("session.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(self)
        try data.write(to: sessionFile)

        print("💾 Session saved: \(name)")
    }

    /// Load session from disk
    static func load(id: UUID) throws -> Session {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let sessionFile = documentsPath
            .appendingPathComponent("Sessions")
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("session.json")

        let data = try Data(contentsOf: sessionFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(Session.self, from: data)
    }
}


// MARK: - Supporting Types

/// Time signature (e.g., 4/4, 3/4)
struct TimeSignature: Codable {
    var numerator: Int
    var denominator: Int

    var description: String {
        "\(numerator)/\(denominator)"
    }
}

/// Bio-data point captured during session
struct BioDataPoint: Codable {
    var timestamp: TimeInterval
    var hrv: Double
    var heartRate: Double
    var coherence: Double
    var audioLevel: Float
    var frequency: Float

    init(
        timestamp: TimeInterval,
        hrv: Double,
        heartRate: Double,
        coherence: Double,
        audioLevel: Float,
        frequency: Float
    ) {
        self.timestamp = timestamp
        self.hrv = hrv
        self.heartRate = heartRate
        self.coherence = coherence
        self.audioLevel = audioLevel
        self.frequency = frequency
    }
}

/// Session metadata
struct SessionMetadata: Codable {
    var tags: [String]
    var genre: String?
    var mood: String?
    var notes: String?

    init(
        tags: [String] = [],
        genre: String? = nil,
        mood: String? = nil,
        notes: String? = nil
    ) {
        self.tags = tags
        self.genre = genre
        self.mood = mood
        self.notes = notes
    }
}


// MARK: - Session Templates

extension Session {
    /// Create meditation session template
    static func meditationTemplate() -> Session {
        var session = Session(name: "Meditation Session", tempo: 60)
        session.addTrack(.binauralTrack())
        session.metadata.genre = "Meditation"
        session.metadata.mood = "Calm"
        return session
    }

    /// Create healing session template
    static func healingTemplate() -> Session {
        var session = Session(name: "Healing Session", tempo: 72)
        session.addTrack(.voiceTrack())
        session.addTrack(.binauralTrack())
        session.metadata.genre = "Healing"
        session.metadata.mood = "Peaceful"
        return session
    }

    /// Create creative session template
    static func creativeTemplate() -> Session {
        var session = Session(name: "Creative Session", tempo: 120)
        session.addTrack(.voiceTrack())
        session.addTrack(.binauralTrack())
        session.addTrack(.spatialTrack())
        session.metadata.genre = "Experimental"
        session.metadata.mood = "Inspired"
        return session
    }
}
