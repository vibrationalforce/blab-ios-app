import Foundation
import Combine

/// Core timeline engine used by the Blab sequencer UI. It manages tempo
/// automation, per-track swing, and MIDI clock generation so that audio, visual,
/// and biofeedback subsystems can stay in sync.
@MainActor
final class SequencerCore: ObservableObject {
    struct Event: Identifiable, Codable {
        enum EventType: String, Codable {
            case midiNote
            case automation
            case controlChange
        }

        let id: UUID
        var startBeat: Double
        var duration: Double
        var type: EventType
        var payload: [String: Double]

        init(startBeat: Double, duration: Double, type: EventType, payload: [String: Double]) {
            self.id = UUID()
            self.startBeat = startBeat
            self.duration = duration
            self.type = type
            self.payload = payload
        }
    }

    struct Track: Identifiable, Codable {
        let id: UUID
        var name: String
        var isMuted: Bool
        var swing: Double
        var automation: [AutomationPoint]
        var events: [Event]

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.isMuted = false
            self.swing = 0
            self.automation = []
            self.events = []
        }
    }

    struct AutomationPoint: Codable {
        var beat: Double
        var value: Double
        var curve: Curve

        enum Curve: String, Codable {
            case linear
            case easeIn
            case easeOut
            case exponential
        }
    }

    struct ClockState {
        var bpm: Double
        var timeSignature: TimeSignature
        var transportPosition: Double
        var isPlaying: Bool
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var clock: ClockState

    private var clockTimer: AnyCancellable?
    private let clockQueue = DispatchQueue(label: "com.blab.sequencer", qos: .userInteractive)
    private let midiClockPublisher = PassthroughSubject<Double, Never>()

    var midiClock: AnyPublisher<Double, Never> {
        midiClockPublisher.eraseToAnyPublisher()
    }

    init(initialBPM: Double = 120, timeSignature: TimeSignature = TimeSignature(beats: 4, noteValue: 4)) {
        clock = ClockState(bpm: initialBPM, timeSignature: timeSignature, transportPosition: 0, isPlaying: false)
    }

    func addTrack(named name: String) {
        tracks.append(Track(name: name))
    }

    func addEvent(_ event: Event, to trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].events.append(event)
        tracks[index].events.sort { $0.startBeat < $1.startBeat }
    }

    func removeEvent(eventID: UUID, from trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].events.removeAll { $0.id == eventID }
    }

    func recordAutomation(value: Double, at beat: Double, for trackID: UUID, curve: AutomationPoint.Curve = .linear) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let point = AutomationPoint(beat: beat, value: value, curve: curve)
        tracks[index].automation.append(point)
        tracks[index].automation.sort { $0.beat < $1.beat }
    }

    func setSwing(_ value: Double, for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].swing = max(-0.5, min(0.5, value))
    }

    func updateClock(bpm: Double? = nil, timeSignature: TimeSignature? = nil) {
        if let bpm { clock.bpm = bpm }
        if let timeSignature { clock.timeSignature = timeSignature }
    }

    func start() {
        guard !clock.isPlaying else { return }
        clock.isPlaying = true
        scheduleClock()
    }

    func stop() {
        clock.isPlaying = false
        clockTimer?.cancel()
        clockTimer = nil
    }

    private func scheduleClock() {
        clockTimer?.cancel()
        let interval = 60.0 / (clock.bpm * 24) // MIDI clock ticks (24 PPQN)

        clockTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard clock.isPlaying else { return }
        clock.transportPosition += 1 / 24.0
        midiClockPublisher.send(clock.transportPosition)
    }
}
