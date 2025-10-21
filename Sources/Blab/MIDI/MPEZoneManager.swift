import Foundation
import CoreMIDI
import Combine

/// MPE (MIDI Polyphonic Expression) Zone Manager
///
/// **MPE Overview:**
/// - Each note gets its own MIDI channel for independent expression
/// - Lower zone: Channels 1-15 (Master channel 1 or 16)
/// - Upper zone: Typically not used in BLAB (could use channels 16-31 with MIDI 2.0)
/// - Voice allocation: Round-robin or priority-based
/// - Per-note pitch bend, pressure, timbre control
///
/// **Compatible with:**
/// - Roli Seaboard
/// - Haken Continuum
/// - LinnStrument
/// - Expressive E Osmose
/// - Any MPE-compatible synth/DAW
///
/// **Usage:**
/// ```swift
/// let mpe = MPEZoneManager(midi2Manager: midi2)
/// let voice = mpe.allocateVoice(note: 60, velocity: 0.8)
/// mpe.setVoicePitchBend(voice: voice, bend: 0.5)
/// mpe.setVoiceBrightness(voice: voice, brightness: 0.7)
/// mpe.deallocateVoice(voice: voice)
/// ```
@MainActor
class MPEZoneManager: ObservableObject {

    // MARK: - Published State

    @Published var activeVoices: [MPEVoice] = []
    @Published var voiceCount: Int = 0
    @Published var voiceAllocationMode: VoiceAllocationMode = .roundRobin

    // MARK: - MPE Voice Model

    struct MPEVoice: Identifiable {
        let id: UUID
        let channel: UInt8    // MIDI channel (1-15 for lower zone)
        let note: UInt8       // MIDI note number
        let velocity: Float   // Initial velocity
        let timestamp: Date   // When voice was allocated

        // Current expression state
        var pitchBend: Float = 0.0      // -1.0 to +1.0
        var pressure: Float = 0.0       // 0.0 to 1.0 (aftertouch)
        var brightness: Float = 0.5     // 0.0 to 1.0 (CC 74)
        var timbre: Float = 0.5         // 0.0 to 1.0 (CC 71)
    }

    // MARK: - Configuration

    enum VoiceAllocationMode {
        case roundRobin      // Cycle through channels
        case leastRecent     // Steal least recently used
        case lowestNote      // Steal lowest note
        case highestNote     // Steal highest note
    }

    /// Number of member channels (1-15, excluding master channel 16)
    let maxVoices: Int = 15

    /// Master channel (0-based, so channel 16 = index 15)
    let masterChannel: UInt8 = 15

    // MARK: - Private Properties

    private let midi2Manager: MIDI2Manager
    private var nextChannelIndex: UInt8 = 0
    private var voices: [UUID: MPEVoice] = [:]

    // MARK: - Initialization

    init(midi2Manager: MIDI2Manager) {
        self.midi2Manager = midi2Manager
    }

    // MARK: - Voice Allocation

    /// Allocate a voice for a new note
    /// - Parameters:
    ///   - note: MIDI note number (0-127)
    ///   - velocity: Velocity (0.0-1.0)
    /// - Returns: Allocated voice, or nil if allocation failed
    func allocateVoice(note: UInt8, velocity: Float) -> MPEVoice? {
        // Check if we have available channels
        if voices.count >= maxVoices {
            // Need to steal a voice
            guard let stolenVoice = selectVoiceToSteal() else {
                print("⚠️ MPE: Failed to steal voice")
                return nil
            }

            // Release stolen voice
            deallocateVoice(voice: stolenVoice)
        }

        // Find available channel
        guard let channel = findAvailableChannel() else {
            print("⚠️ MPE: No available channel")
            return nil
        }

        // Create voice
        let voice = MPEVoice(
            id: UUID(),
            channel: channel,
            note: note,
            velocity: velocity,
            timestamp: Date()
        )

        // Store voice
        voices[voice.id] = voice
        updatePublishedState()

        // Send MIDI 2.0 Note On
        midi2Manager.sendNoteOn(channel: channel, note: note, velocity: velocity)

        print("[MPE] Allocated voice: Note \(note) on channel \(channel + 1)")

        return voice
    }

    /// Deallocate a voice
    func deallocateVoice(voice: MPEVoice) {
        // Send Note Off
        midi2Manager.sendNoteOff(channel: voice.channel, note: voice.note)

        // Remove from tracking
        voices.removeValue(forKey: voice.id)
        updatePublishedState()

        print("[MPE] Deallocated voice: Note \(voice.note) from channel \(voice.channel + 1)")
    }

    /// Find next available channel
    private func findAvailableChannel() -> UInt8? {
        let usedChannels = Set(voices.values.map { $0.channel })

        // Channels 0-14 (MIDI 1-15)
        for channel: UInt8 in 0..<UInt8(maxVoices) {
            if !usedChannels.contains(channel) {
                return channel
            }
        }

        return nil
    }

    /// Select a voice to steal based on allocation mode
    private func selectVoiceToSteal() -> MPEVoice? {
        guard !voices.isEmpty else { return nil }

        switch voiceAllocationMode {
        case .roundRobin:
            // Steal the oldest voice
            return voices.values.min { $0.timestamp < $1.timestamp }

        case .leastRecent:
            return voices.values.min { $0.timestamp < $1.timestamp }

        case .lowestNote:
            return voices.values.min { $0.note < $1.note }

        case .highestNote:
            return voices.values.max { $0.note < $1.note }
        }
    }

    // MARK: - Voice Expression Control

    /// Set pitch bend for a specific voice
    /// - Parameters:
    ///   - voice: Voice to control
    ///   - bend: Pitch bend (-1.0 to +1.0, center = 0.0)
    func setVoicePitchBend(voice: MPEVoice, bend: Float) {
        guard var updatedVoice = voices[voice.id] else { return }

        updatedVoice.pitchBend = bend
        voices[voice.id] = updatedVoice

        // Send per-note pitch bend (MIDI 2.0)
        midi2Manager.sendPerNotePitchBend(
            channel: voice.channel,
            note: voice.note,
            bend: bend
        )

        updatePublishedState()
    }

    /// Set pressure (aftertouch) for a specific voice
    func setVoicePressure(voice: MPEVoice, pressure: Float) {
        guard var updatedVoice = voices[voice.id] else { return }

        updatedVoice.pressure = pressure
        voices[voice.id] = updatedVoice

        // Send channel pressure for this voice's channel
        midi2Manager.sendChannelPressure(channel: voice.channel, pressure: pressure)

        updatePublishedState()
    }

    /// Set brightness (CC 74) for a specific voice
    func setVoiceBrightness(voice: MPEVoice, brightness: Float) {
        guard var updatedVoice = voices[voice.id] else { return }

        updatedVoice.brightness = brightness
        voices[voice.id] = updatedVoice

        // Send per-note controller
        midi2Manager.sendPerNoteController(
            channel: voice.channel,
            note: voice.note,
            controller: .sound4Cutoff,
            value: brightness
        )

        updatePublishedState()
    }

    /// Set timbre (CC 71) for a specific voice
    func setVoiceTimbre(voice: MPEVoice, timbre: Float) {
        guard var updatedVoice = voices[voice.id] else { return }

        updatedVoice.timbre = timbre
        voices[voice.id] = updatedVoice

        // Send per-note controller
        midi2Manager.sendPerNoteController(
            channel: voice.channel,
            note: voice.note,
            controller: .sound2Brightness,
            value: timbre
        )

        updatePublishedState()
    }

    // MARK: - Master Channel Control

    /// Send control change on master channel (affects all voices)
    func sendMasterControlChange(controller: UInt8, value: Float) {
        midi2Manager.sendControlChange(
            channel: masterChannel,
            controller: controller,
            value: value
        )
    }

    // MARK: - State Management

    private func updatePublishedState() {
        activeVoices = Array(voices.values).sorted { $0.timestamp < $1.timestamp }
        voiceCount = voices.count
    }

    /// Get voice by ID
    func getVoice(id: UUID) -> MPEVoice? {
        voices[id]
    }

    /// Get voice by note number
    func getVoiceByNote(note: UInt8) -> MPEVoice? {
        voices.values.first { $0.note == note }
    }

    /// Release all voices
    func releaseAllVoices() {
        for voice in voices.values {
            midi2Manager.sendNoteOff(channel: voice.channel, note: voice.note)
        }

        voices.removeAll()
        updatePublishedState()

        print("[MPE] Released all voices")
    }

    // MARK: - MPE Configuration Messages

    /// Send MPE Configuration Message (RPN)
    /// This configures the receiving device for MPE mode
    func sendMPEConfiguration(memberChannels: UInt8 = 15) {
        // MPE Configuration is done via RPN (Registered Parameter Number)
        // RPN 0 (MSB=0, LSB=0) = Pitch Bend Sensitivity
        // For MPE: Set number of member channels

        let channel = masterChannel

        // RPN MSB (CC 101) = 0
        midi2Manager.sendControlChange(channel: channel, controller: 101, value: 0.0)

        // RPN LSB (CC 100) = 6 (MPE Configuration)
        midi2Manager.sendControlChange(channel: channel, controller: 100, value: 6.0 / 127.0)

        // Data Entry MSB (CC 6) = Number of member channels
        let normalizedChannels = Float(memberChannels) / 127.0
        midi2Manager.sendControlChange(channel: channel, controller: 6, value: normalizedChannels)

        // Data Entry LSB (CC 38) = 0
        midi2Manager.sendControlChange(channel: channel, controller: 38, value: 0.0)

        print("[MPE] Sent configuration: \(memberChannels) member channels")
    }

    /// Send MPE pitch bend range configuration
    func setPitchBendRange(semitones: UInt8 = 48) {
        let channel = masterChannel

        // RPN MSB (CC 101) = 0
        midi2Manager.sendControlChange(channel: channel, controller: 101, value: 0.0)

        // RPN LSB (CC 100) = 0 (Pitch Bend Sensitivity)
        midi2Manager.sendControlChange(channel: channel, controller: 100, value: 0.0)

        // Data Entry MSB (CC 6) = Semitones
        let normalizedSemitones = Float(semitones) / 127.0
        midi2Manager.sendControlChange(channel: channel, controller: 6, value: normalizedSemitones)

        // Data Entry LSB (CC 38) = 0
        midi2Manager.sendControlChange(channel: channel, controller: 38, value: 0.0)

        print("[MPE] Set pitch bend range: ±\(semitones) semitones")
    }
}

// MARK: - Voice Statistics

extension MPEZoneManager {

    /// Get statistics about voice usage
    var statistics: VoiceStatistics {
        VoiceStatistics(
            activeVoices: voiceCount,
            maxVoices: maxVoices,
            availableVoices: maxVoices - voiceCount,
            oldestVoiceAge: oldestVoiceAge,
            newestVoiceAge: newestVoiceAge
        )
    }

    struct VoiceStatistics {
        let activeVoices: Int
        let maxVoices: Int
        let availableVoices: Int
        let oldestVoiceAge: TimeInterval?
        let newestVoiceAge: TimeInterval?
    }

    private var oldestVoiceAge: TimeInterval? {
        guard let oldest = voices.values.min(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        return Date().timeIntervalSince(oldest.timestamp)
    }

    private var newestVoiceAge: TimeInterval? {
        guard let newest = voices.values.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        return Date().timeIntervalSince(newest.timestamp)
    }
}
