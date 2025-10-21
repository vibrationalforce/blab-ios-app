import Foundation
import AVFoundation
import Combine
import Accelerate

/// Manages multi-track audio recording with bio-signal integration
/// Coordinates recording, playback, and real-time monitoring
@MainActor
class RecordingEngine: ObservableObject {

    // MARK: - Published Properties

    /// Current session being recorded/played
    @Published var currentSession: Session?

    /// Is currently recording
    @Published var isRecording: Bool = false

    /// Is currently playing back
    @Published var isPlaying: Bool = false

    /// Current playback/recording position (seconds)
    @Published var currentTime: TimeInterval = 0.0

    /// Recording level (0.0 - 1.0)
    @Published var recordingLevel: Float = 0.0

    /// Real-time waveform data for current recording
    @Published var recordingWaveform: [Float] = []

    /// Current track being recorded
    @Published var currentTrackID: UUID?


    // MARK: - Private Properties

    /// Audio engine for recording/playback
    private var audioEngine: AVAudioEngine?

    /// Input node for recording
    private var inputNode: AVAudioInputNode?

    /// Audio file for current recording
    private var audioFile: AVAudioFile?

    /// Timer for position updates
    private var timer: Timer?

    /// Waveform buffer for real-time display (max 1000 samples)
    private var waveformBuffer: [Float] = []

    /// Reference to main audio engine for audio routing
    private weak var mainAudioEngine: AudioEngine?

    /// Directory for storing session files
    private let sessionsDirectory: URL

    /// Maximum recording duration (seconds)
    private let maxDuration: TimeInterval = 3600 // 1 hour

    /// Audio format for recording
    private let recordingFormat: AVAudioFormat


    // MARK: - Initialization

    init() {
        // Setup sessions directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.sessionsDirectory = documentsPath.appendingPathComponent("Sessions", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        // Setup recording format (48kHz, stereo, float32)
        self.recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        )!

        print("📁 Recording engine initialized")
        print("   Sessions directory: \(sessionsDirectory.path)")
    }


    // MARK: - Audio Engine Connection

    /// Connect to main audio engine for audio routing
    func connectAudioEngine(_ audioEngine: AudioEngine) {
        self.mainAudioEngine = audioEngine
        print("🔌 Connected to main audio engine")
    }


    // MARK: - Session Management

    /// Create new recording session
    func createSession(name: String, template: Session.SessionTemplate = .custom) -> Session {
        var session: Session

        switch template {
        case .meditation:
            session = Session.meditationTemplate()
        case .healing:
            session = Session.healingTemplate()
        case .creative:
            session = Session.creativeTemplate()
        case .custom:
            session = Session(name: name)
        }

        session.name = name
        currentSession = session

        print("🎵 Created session: \(name)")
        return session
    }

    /// Load existing session
    func loadSession(id: UUID) throws {
        let session = try Session.load(id: id)
        currentSession = session
        print("📂 Loaded session: \(session.name)")
    }

    /// Save current session
    func saveSession() throws {
        guard let session = currentSession else {
            throw RecordingError.noActiveSession
        }

        try session.save()
        print("💾 Saved session: \(session.name)")
    }


    // MARK: - Recording Control

    /// Start recording a new track
    func startRecording(trackType: Track.TrackType = .audio) throws {
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }

        guard var session = currentSession else {
            throw RecordingError.noActiveSession
        }

        // Create new track
        var track = Track(
            name: "Track \(session.tracks.count + 1)",
            type: trackType
        )

        // Setup audio file for recording
        let trackURL = trackFileURL(sessionID: session.id, trackID: track.id)
        audioFile = try AVAudioFile(
            forWriting: trackURL,
            settings: recordingFormat.settings,
            commonFormat: recordingFormat.commonFormat,
            interleaved: recordingFormat.isInterleaved
        )

        track.url = trackURL
        currentTrackID = track.id

        // Add track to session
        session.tracks.append(track)
        currentSession = session

        // Setup audio engine for recording
        try setupAudioRecording()

        isRecording = true
        currentTime = 0.0
        waveformBuffer.removeAll()
        recordingWaveform.removeAll()

        // Start timer for position updates
        startTimer()

        print("🔴 Started recording: \(track.name)")
    }

    /// Setup audio engine tap for recording
    private func setupAudioRecording() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        inputNode = engine.inputNode
        guard let input = inputNode else { return }

        let inputFormat = input.outputFormat(forBus: 0)

        // Install tap to capture audio data
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            Task { @MainActor [weak self] in
                self?.processRecordingBuffer(buffer)
            }
        }

        try engine.start()
        print("🎙️ Audio recording engine started")
    }

    /// Process incoming audio buffer during recording
    private func processRecordingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channelDataValue = channelData.pointee

        // Calculate RMS for level meter
        var sum: Float = 0.0
        vDSP_sve(channelDataValue, 1, &sum, vDSP_Length(frameLength))

        var sumSquares: Float = 0.0
        vDSP_svesq(channelDataValue, 1, &sumSquares, vDSP_Length(frameLength))

        let rms = sqrt(sumSquares / Float(frameLength))
        recordingLevel = min(rms * 10.0, 1.0) // Normalize and clamp

        // Write to audio file
        if let file = audioFile {
            try? file.write(from: buffer)
        }

        // Update waveform buffer for real-time display
        updateWaveformBuffer(channelDataValue, frameLength: frameLength)
    }

    /// Update waveform buffer for real-time visualization
    private func updateWaveformBuffer(_ data: UnsafePointer<Float>, frameLength: Int) {
        // Downsample to max 1000 points
        let maxPoints = 1000
        let stride = max(1, frameLength / maxPoints)

        for i in stride(from: 0, to: frameLength, by: stride) {
            if waveformBuffer.count >= maxPoints {
                waveformBuffer.removeFirst()
            }
            waveformBuffer.append(data[i])
        }

        // Update published waveform
        recordingWaveform = waveformBuffer
    }

    /// Stop recording current track
    func stopRecording() throws {
        guard isRecording else { return }

        // Stop audio engine
        if let engine = audioEngine, let input = inputNode {
            input.removeTap(onBus: 0)
            engine.stop()
        }

        isRecording = false
        stopTimer()

        // Update track duration
        if var session = currentSession,
           let lastTrackIndex = session.tracks.indices.last,
           let url = session.tracks[lastTrackIndex].url {

            session.tracks[lastTrackIndex].duration = currentTime
            session.duration = max(session.duration, currentTime)

            // Generate waveform for visualization
            session.tracks[lastTrackIndex].generateWaveform()

            currentSession = session
        }

        audioFile = nil
        audioEngine = nil
        inputNode = nil
        currentTime = 0.0
        recordingLevel = 0.0
        currentTrackID = nil

        print("⏹️ Stopped recording")
    }


    // MARK: - Playback Control

    /// Start playback of current session
    func startPlayback() throws {
        guard !isPlaying else {
            throw RecordingError.alreadyPlaying
        }

        guard let session = currentSession else {
            throw RecordingError.noActiveSession
        }

        isPlaying = true
        startTimer()

        print("▶️ Started playback: \(session.name)")
    }

    /// Stop playback
    func stopPlayback() {
        isPlaying = false
        stopTimer()
        currentTime = 0.0

        print("⏹️ Stopped playback")
    }

    /// Pause playback
    func pausePlayback() {
        isPlaying = false
        stopTimer()

        print("⏸️ Paused playback at \(currentTime)s")
    }

    /// Seek to position
    func seek(to time: TimeInterval) {
        guard let session = currentSession else { return }

        currentTime = max(0, min(time, session.duration))
        print("⏩ Seeked to \(currentTime)s")
    }


    // MARK: - Track Management

    /// Add bio-data point to current session
    func addBioDataPoint(
        hrv: Double,
        heartRate: Double,
        coherence: Double,
        audioLevel: Float,
        frequency: Float
    ) {
        guard var session = currentSession, isRecording else { return }

        let dataPoint = BioDataPoint(
            timestamp: currentTime,
            hrv: hrv,
            heartRate: heartRate,
            coherence: coherence,
            audioLevel: audioLevel,
            frequency: frequency
        )

        session.bioData.append(dataPoint)
        currentSession = session
    }

    /// Mute/unmute track
    func setTrackMuted(_ trackID: UUID, muted: Bool) {
        guard var session = currentSession else { return }

        if let index = session.tracks.firstIndex(where: { $0.id == trackID }) {
            session.tracks[index].isMuted = muted
            currentSession = session
        }
    }

    /// Solo track
    func setTrackSoloed(_ trackID: UUID, soloed: Bool) {
        guard var session = currentSession else { return }

        if let index = session.tracks.firstIndex(where: { $0.id == trackID }) {
            session.tracks[index].isSoloed = soloed
            currentSession = session
        }
    }

    /// Set track volume
    func setTrackVolume(_ trackID: UUID, volume: Float) {
        guard var session = currentSession else { return }

        if let index = session.tracks.firstIndex(where: { $0.id == trackID }) {
            session.tracks[index].volume = max(0, min(1, volume))
            currentSession = session
        }
    }

    /// Set track pan
    func setTrackPan(_ trackID: UUID, pan: Float) {
        guard var session = currentSession else { return }

        if let index = session.tracks.firstIndex(where: { $0.id == trackID }) {
            session.tracks[index].pan = max(-1, min(1, pan))
            currentSession = session
        }
    }

    /// Delete track
    func deleteTrack(_ trackID: UUID) throws {
        guard var session = currentSession else {
            throw RecordingError.noActiveSession
        }

        guard let index = session.tracks.firstIndex(where: { $0.id == trackID }) else {
            throw RecordingError.trackNotFound
        }

        // Delete audio file
        if let url = session.tracks[index].url {
            try? FileManager.default.removeItem(at: url)
        }

        session.tracks.remove(at: index)
        currentSession = session

        print("🗑️ Deleted track")
    }


    // MARK: - Private Helpers

    /// Start position update timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }
    }

    /// Stop position update timer
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Update playback/recording position
    private func updatePosition() {
        guard isRecording || isPlaying else { return }

        currentTime += 0.1

        // Stop at max duration
        if currentTime >= maxDuration && isRecording {
            try? stopRecording()
        }

        // Stop at session end
        if let session = currentSession, currentTime >= session.duration && isPlaying {
            stopPlayback()
        }
    }

    /// Generate track file URL
    private func trackFileURL(sessionID: UUID, trackID: UUID) -> URL {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        return sessionDir.appendingPathComponent("\(trackID.uuidString).caf")
    }
}


// MARK: - Recording Errors

enum RecordingError: LocalizedError {
    case noActiveSession
    case alreadyRecording
    case alreadyPlaying
    case trackNotFound
    case fileNotFound
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active recording session"
        case .alreadyRecording:
            return "Already recording"
        case .alreadyPlaying:
            return "Already playing"
        case .trackNotFound:
            return "Track not found"
        case .fileNotFound:
            return "Audio file not found"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}
