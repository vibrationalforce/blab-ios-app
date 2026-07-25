//
//  MIDIBusPublisher.swift
//  Echoelmusic — EchoelSync module
//
//  Bridges CoreMIDI input (via MIDIInput) onto EngineBus.controllerEvents.
//  MIDIInput already parses MIDI 1.0 + MIDI 2.0 + MPE wire format into
//  normalized [0..1] / [-1..1] closure callbacks (onNoteOn, onNoteOff,
//  onCC, onPitchBend). This class wires those callbacks to publish
//  ControllerEvent onto the bus, source-tagged by MIDI message kind:
//
//    note on / off         → .noteOn / .noteOff
//    CC 74                 → .slide   (MPE per-note timbre)
//    CC 21..31             → .airCC   (master prompt §3 air dimensions)
//    other CCs             → dropped for now; extend ControllerEvent
//                            Kind enum when a consumer needs them
//    pitch bend            → .pitchBend (range already normalized to [-1..1])
//
//  MPE master vs. member channel disambiguation, RPN 6,6 zone detection,
//  and channelPressure are intentionally NOT wired in this first cycle —
//  they're tracked as the MPE-completeness follow-up.
//

#if canImport(CoreMIDI)
import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class MIDIBusPublisher {

    public private(set) var isPublishing = false

    public private(set) var lastEventTimestamp: TimeInterval = 0

    @ObservationIgnored
    private let midi: MIDIInput

    @ObservationIgnored
    private weak var bus: EngineBus?

    /// Optional MIDI-out for thru: when `thruEnabled` (a midi.in → midi.out patchbay
    /// route), incoming external notes are echoed straight to MIDI out (router mode).
    @ObservationIgnored
    private weak var midiOut: MIDIOutput?
    /// Set from the patchbay (midi.in → midi.out route). Off by default.
    public var thruEnabled = false

    /// Record-system tee (B): when a take is running the RecordController installs
    /// these so every external MIDI note is captured into the armed lane. nil ⇒ not
    /// recording (zero overhead). Invoked on @MainActor alongside the existing publish.
    @ObservationIgnored public var onRecordNoteOn: ((_ note: Int, _ velocity: Float) -> Void)?
    @ObservationIgnored public var onRecordNoteOff: ((_ note: Int) -> Void)?

    init(midi: MIDIInput) {
        self.midi = midi
    }

    public func start(publishing bus: EngineBus, midiOut: MIDIOutput? = nil) {
        guard !isPublishing else { return }
        self.bus = bus
        self.midiOut = midiOut
        wireCallbacks()
        isPublishing = true
    }

    public func stop() {
        midi.onNoteOn = nil
        midi.onNoteOff = nil
        midi.onCC = nil
        midi.onPitchBend = nil
        isPublishing = false
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        midi.onNoteOn = { [weak self] note, velocity, channel in
            guard let self else { return }
            // Thru: echo external notes straight to MIDI out (router mode).
            if self.thruEnabled { self.midiOut?.noteOn(pitch: note, velocity: velocity) }
            // Record tee: capture into the armed lane's take (no-op unless recording).
            self.onRecordNoteOn?(note, velocity)
            // Built-in voice via the bus — the external keyboard plays Echoel's voice.
            self.publish(ControllerEvent(
                timestamp: CFAbsoluteTimeGetCurrent(),
                kind: .noteOn,
                channel: UInt8(clamping: channel),
                note: UInt8(clamping: note),
                value: velocity,
                auxCC: 0
            ))
        }
        midi.onNoteOff = { [weak self] note, channel in
            guard let self else { return }
            if self.thruEnabled { self.midiOut?.noteOff(pitch: note) }
            self.onRecordNoteOff?(note)   // record tee (no-op unless recording)
            // Note-off always reaches the bus so the built-in voice can't stick.
            self.publish(ControllerEvent(
                timestamp: CFAbsoluteTimeGetCurrent(),
                kind: .noteOff,
                channel: UInt8(clamping: channel),
                note: UInt8(clamping: note),
                value: 0,
                auxCC: 0
            ))
        }
        midi.onCC = { [weak self] cc, value, channel in
            self?.publishCC(cc: cc, value: value, channel: channel)
        }
        midi.onPitchBend = { [weak self] bend, channel in
            self?.publish(ControllerEvent(
                timestamp: CFAbsoluteTimeGetCurrent(),
                kind: .pitchBend,
                channel: UInt8(clamping: channel),
                note: 0,
                value: bend,
                auxCC: 0
            ))
        }
    }

    private func publishCC(cc: Int, value: Float, channel: Int) {
        let kind: ControllerEvent.Kind
        switch cc {
        case 74:        kind = .slide
        case 21...31:   kind = .airCC
        default:        return  // unmapped CCs dropped this cycle
        }
        publish(ControllerEvent(
            timestamp: CFAbsoluteTimeGetCurrent(),
            kind: kind,
            channel: UInt8(clamping: channel),
            note: 0,
            value: value,
            auxCC: UInt8(clamping: cc)
        ))
    }

    private func publish(_ event: ControllerEvent) {
        bus?.publish(controller: event)
        lastEventTimestamp = event.timestamp
    }
}
#endif
