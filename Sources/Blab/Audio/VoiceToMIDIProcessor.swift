import Foundation
import Combine

/// Converts voice and multi-input spectral data into expressive MIDI events. The
/// processor listens to `MicrophoneManager.channelMetrics` and adapts the
/// mapping based on instrument profiles.
@MainActor
final class VoiceToMIDIProcessor: ObservableObject {
    struct InstrumentProfile {
        let name: String
        let frequencyRange: ClosedRange<Float>
        let velocityCurve: Float
        let octaveBias: Int
        let minVelocity: Float
        let detectionThreshold: Float

        static let voice = InstrumentProfile(
            name: "Voice",
            frequencyRange: 80...1_000,
            velocityCurve: 0.85,
            octaveBias: 0,
            minVelocity: 0.2,
            detectionThreshold: 0.04
        )

        static let external = InstrumentProfile(
            name: "External",
            frequencyRange: 40...4_000,
            velocityCurve: 0.7,
            octaveBias: -1,
            minVelocity: 0.1,
            detectionThreshold: 0.02
        )
    }

    private struct ActiveVoice {
        let note: UInt8
        let channel: UInt8
        var velocity: Float
        var timestamp: Date
    }

    private let microphoneManager: MicrophoneManager
    private let midiManager: MIDI2Manager
    private let mpeManager: MPEZoneManager?

    private var cancellables = Set<AnyCancellable>()
    private var profiles: [UUID: InstrumentProfile] = [:]
    private var activeVoices: [UUID: ActiveVoice] = [:]
    private var channelAssignments: [UUID: UInt8] = [:]

    init(
        microphoneManager: MicrophoneManager,
        midiManager: MIDI2Manager,
        mpeManager: MPEZoneManager? = nil
    ) {
        self.microphoneManager = microphoneManager
        self.midiManager = midiManager
        self.mpeManager = mpeManager

        microphoneManager.$channelMetrics
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.handleMetricsUpdate(metrics)
            }
            .store(in: &cancellables)
    }

    func registerProfile(_ profile: InstrumentProfile, for channelID: UUID) {
        profiles[channelID] = profile
    }

    private func handleMetricsUpdate(_ metrics: [MicrophoneManager.ChannelMetrics]) {
        for metric in metrics {
            let profile = profiles[metric.id] ?? defaultProfile(for: metric.kind)
            guard metric.amplitude >= profile.detectionThreshold else {
                if activeVoices[metric.id] != nil {
                    sendNoteOff(for: metric.id)
                }
                continue
            }

            guard metric.frequency > 0 else { continue }
            guard let midi = frequencyToMIDINote(metric.frequency, profile: profile) else { continue }

            let velocity = max(profile.minVelocity, pow(metric.amplitude, profile.velocityCurve))
            let channel = channelAssignments[metric.id] ?? 0

            if var voice = activeVoices[metric.id] {
                if abs(Float(voice.note) - midi) >= 0.51 {
                    sendNoteOff(for: metric.id)
                    sendNoteOn(for: metric.id, note: UInt8(clamping: Int(round(midi))), velocity: velocity, channel: channel)
                } else {
                    updatePerNoteControllers(note: voice.note, velocity: velocity, clarity: metric.clarity, channel: channel)
                    voice.velocity = velocity
                    voice.timestamp = Date()
                    activeVoices[metric.id] = voice
                }
            } else {
                sendNoteOn(for: metric.id, note: UInt8(clamping: Int(round(midi))), velocity: velocity, channel: channel)
            }
        }
    }

    private func defaultProfile(for kind: AudioGraph.InputKind) -> InstrumentProfile {
        switch kind {
        case .microphone:
            return .voice
        case .external:
            return .external
        case .virtualInstrument:
            return InstrumentProfile(
                name: "Instrument",
                frequencyRange: 40...8_000,
                velocityCurve: 0.6,
                octaveBias: 0,
                minVelocity: 0.1,
                detectionThreshold: 0.01
            )
        }
    }

    private func frequencyToMIDINote(_ frequency: Float, profile: InstrumentProfile) -> Float? {
        guard profile.frequencyRange.contains(frequency) else { return nil }
        let midi = 69 + 12 * log2(frequency / 440)
        let octaveAdjusted = midi + Float(profile.octaveBias * 12)
        return min(127, max(0, octaveAdjusted))
    }

    private func sendNoteOn(for channelID: UUID, note: UInt8, velocity: Float, channel: UInt8) {
        if let mpe = mpeManager, let voice = mpe.allocateVoice(note: note, velocity: velocity) {
            channelAssignments[channelID] = voice.channel
            activeVoices[channelID] = ActiveVoice(note: voice.note, channel: voice.channel, velocity: velocity, timestamp: Date())
            mpe.setVoicePressure(voice: voice, pressure: velocity)
        } else {
            midiManager.sendNoteOn(channel: channel, note: note, velocity: velocity)
            channelAssignments[channelID] = channel
            activeVoices[channelID] = ActiveVoice(note: note, channel: channel, velocity: velocity, timestamp: Date())
        }
    }

    private func sendNoteOff(for channelID: UUID) {
        guard let voice = activeVoices[channelID] else { return }
        if let mpe = mpeManager, let mpeVoice = mpe.getVoiceByNote(note: voice.note) {
            mpe.deallocateVoice(voice: mpeVoice)
        } else {
            midiManager.sendNoteOff(channel: voice.channel, note: voice.note, velocity: 0)
        }
        activeVoices.removeValue(forKey: channelID)
    }

    private func updatePerNoteControllers(note: UInt8, velocity: Float, clarity: Float, channel: UInt8) {
        midiManager.sendPerNotePitchBend(channel: channel, note: note, bend: (clarity * 2) - 1)
        midiManager.sendPerNoteController(channel: channel, note: note, controller: .brightness, value: clarity)
        midiManager.sendPerNoteController(channel: channel, note: note, controller: .timbre, value: min(1, velocity + clarity * 0.5))
    }
}
