import Foundation
import AVFoundation
import Combine

/// Manages audio looping functionality with tempo-sync and quantization
/// Supports loop recording, overdubbing, and playback
@MainActor
class LoopEngine: ObservableObject {

    // MARK: - Published Properties

    /// Is currently recording a loop
    @Published var isRecordingLoop: Bool = false

    /// Is currently playing loops
    @Published var isPlayingLoops: Bool = false

    /// Current loop position (0.0 to 1.0)
    @Published var loopPosition: Double = 0.0

    /// Active loops
    @Published var loops: [Loop] = []

    /// Current tempo (BPM)
    @Published var tempo: Double = 120.0

    /// Time signature
    @Published var timeSignature: TimeSignature = TimeSignature(beats: 4, noteValue: 4)

    /// Metronome enabled
    @Published var metronomeEnabled: Bool = false


    // MARK: - Loop Model

    struct Loop: Identifiable, Codable {
        let id: UUID
        var name: String
        var audioURL: URL?
        var duration: TimeInterval
        var bars: Int
        var volume: Float
        var pan: Float
        var isMuted: Bool
        var isSoloed: Bool
        var startTime: TimeInterval
        var color: LoopColor

        enum LoopColor: String, Codable, CaseIterable {
            case red, orange, yellow, green, cyan, blue, purple, pink

            var color: Color {
                switch self {
                case .red: return .red
                case .orange: return .orange
                case .yellow: return .yellow
                case .green: return .green
                case .cyan: return .cyan
                case .blue: return .blue
                case .purple: return .purple
                case .pink: return .pink
                }
            }
        }

        init(
            name: String = "Loop",
            bars: Int = 4,
            volume: Float = 1.0,
            color: LoopColor = .cyan
        ) {
            self.id = UUID()
            self.name = name
            self.bars = bars
            self.volume = volume
            self.pan = 0.0
            self.isMuted = false
            self.isSoloed = false
            self.startTime = 0.0
            self.color = color
            self.duration = 0.0
        }
    }


    // MARK: - Private Properties

    /// Audio engine for loop playback
    private var audioEngine: AVAudioEngine?

    /// Audio players for each loop
    private var players: [UUID: AVAudioPlayerNode] = [:]

    /// Timer for loop position updates
    private var timer: Timer?

    /// Current loop start time
    private var loopStartTime: Date?

    /// Recording buffer
    private var recordingBuffer: AVAudioPCMBuffer?

    /// Quantization enabled (snap to bar boundaries)
    private var quantizeEnabled: Bool = true

    /// Loop directory
    private let loopsDirectory: URL


    // MARK: - Initialization

    init() {
        // Setup loops directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.loopsDirectory = documentsPath.appendingPathComponent("Loops", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: loopsDirectory, withIntermediateDirectories: true)

        print("🔄 Loop engine initialized")
    }


    // MARK: - Loop Recording

    /// Start recording a new loop
    func startLoopRecording(bars: Int = 4) {
        guard !isRecordingLoop else { return }

        let loop = Loop(
            name: "Loop \(loops.count + 1)",
            bars: bars,
            color: Loop.LoopColor.allCases.randomElement() ?? .cyan
        )

        loops.append(loop)
        isRecordingLoop = true
        loopStartTime = Date()

        print("🔴 Started loop recording: \(loop.name) (\(bars) bars)")
    }

    /// Stop recording current loop
    func stopLoopRecording() {
        guard isRecordingLoop else { return }

        isRecordingLoop = false

        // Calculate actual duration
        if let startTime = loopStartTime,
           let lastLoopIndex = loops.indices.last {

            let duration = Date().timeIntervalSince(startTime)

            // Quantize to nearest bar if enabled
            let barDuration = barDurationSeconds()
            let quantizedDuration = quantizeEnabled
                ? round(duration / barDuration) * barDuration
                : duration

            loops[lastLoopIndex].duration = quantizedDuration

            print("⏹️ Stopped loop recording: \(quantizedDuration)s")
        }

        loopStartTime = nil
    }


    // MARK: - Loop Playback

    /// Start playing all loops
    func startPlayback() {
        guard !isPlayingLoops else { return }

        isPlayingLoops = true
        loopStartTime = Date()

        // Start position timer
        startTimer()

        print("▶️ Started loop playback")
    }

    /// Stop playing loops
    func stopPlayback() {
        isPlayingLoops = false
        loopPosition = 0.0
        stopTimer()

        print("⏹️ Stopped loop playback")
    }

    /// Toggle playback
    func togglePlayback() {
        if isPlayingLoops {
            stopPlayback()
        } else {
            startPlayback()
        }
    }


    // MARK: - Loop Management

    /// Delete loop
    func deleteLoop(_ loopID: UUID) {
        loops.removeAll { $0.id == loopID }

        // Delete audio file
        if let player = players[loopID] {
            player.stop()
            players.removeValue(forKey: loopID)
        }

        print("🗑️ Deleted loop")
    }

    /// Mute/unmute loop
    func setLoopMuted(_ loopID: UUID, muted: Bool) {
        if let index = loops.firstIndex(where: { $0.id == loopID }) {
            loops[index].isMuted = muted
        }
    }

    /// Solo loop
    func setLoopSoloed(_ loopID: UUID, soloed: Bool) {
        if let index = loops.firstIndex(where: { $0.id == loopID }) {
            loops[index].isSoloed = soloed
        }
    }

    /// Set loop volume
    func setLoopVolume(_ loopID: UUID, volume: Float) {
        if let index = loops.firstIndex(where: { $0.id == loopID }) {
            loops[index].volume = max(0, min(1, volume))
        }
    }

    /// Set loop pan
    func setLoopPan(_ loopID: UUID, pan: Float) {
        if let index = loops.firstIndex(where: { $0.id == loopID }) {
            loops[index].pan = max(-1, min(1, pan))
        }
    }

    /// Clear all loops
    func clearAllLoops() {
        stopPlayback()
        loops.removeAll()
        players.removeAll()

        print("🗑️ Cleared all loops")
    }


    // MARK: - Tempo & Timing

    /// Set tempo (BPM)
    func setTempo(_ bpm: Double) {
        tempo = max(40, min(240, bpm))
    }

    /// Set time signature
    func setTimeSignature(beats: Int, noteValue: Int) {
        timeSignature = TimeSignature(beats: beats, noteValue: noteValue)
    }

    /// Calculate bar duration in seconds
    func barDurationSeconds() -> TimeInterval {
        let beatsPerBar = Double(timeSignature.beats)
        let secondsPerBeat = 60.0 / tempo
        return beatsPerBar * secondsPerBeat
    }

    /// Calculate beat duration in seconds
    func beatDurationSeconds() -> TimeInterval {
        return 60.0 / tempo
    }

    /// Get current beat position (0-based within loop)
    func currentBeat() -> Int {
        let beatDuration = beatDurationSeconds()
        let beatsPerBar = Double(timeSignature.beats)

        if let startTime = loopStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let totalBeats = Int(elapsed / beatDuration)
            return totalBeats % Int(beatsPerBar)
        }

        return 0
    }


    // MARK: - Metronome

    /// Toggle metronome
    func toggleMetronome() {
        metronomeEnabled.toggle()

        if metronomeEnabled {
            print("🎵 Metronome enabled")
        } else {
            print("🎵 Metronome disabled")
        }
    }


    // MARK: - Private Helpers

    /// Start position update timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
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

    /// Update loop position
    private func updatePosition() {
        guard isPlayingLoops, let startTime = loopStartTime else {
            loopPosition = 0.0
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let longestLoop = loops.map { $0.duration }.max() ?? 1.0

        if longestLoop > 0 {
            loopPosition = (elapsed.truncatingRemainder(dividingBy: longestLoop)) / longestLoop
        }
    }


    // MARK: - Save/Load

    /// Save loops to disk
    func saveLoops() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(loops)
        let saveURL = loopsDirectory.appendingPathComponent("loops.json")
        try data.write(to: saveURL)

        print("💾 Saved \(loops.count) loops")
    }

    /// Load loops from disk
    func loadLoops() throws {
        let loadURL = loopsDirectory.appendingPathComponent("loops.json")
        let data = try Data(contentsOf: loadURL)

        let decoder = JSONDecoder()
        loops = try decoder.decode([Loop].self, from: data)

        print("📂 Loaded \(loops.count) loops")
    }
}


// MARK: - Extensions

extension LoopEngine.Loop {
    /// Human-readable duration string
    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Bars and beats display
    var barsDisplay: String {
        return "\(bars) bars"
    }
}
