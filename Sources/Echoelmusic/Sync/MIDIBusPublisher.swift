//
//  MIDIBusPublisher.swift
//  Echoelmusic — EchoelSync module
//
//  Bridges CoreMIDI input (via MIDIInput) onto EngineBus.controllerEvents.
//  MIDIInput parses MIDI 1.0 + MIDI 2.0 channel-voice messages into
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
//    channel pressure      → .channelPressure (MPE's PRESS dimension, #939)
//
//  MPE master vs. member channel disambiguation and RPN 6,6 zone detection
//  are still NOT available here — tracked as the MPE-completeness follow-up.
//
//  ⭐ #939 STRUCK "and channelPressure" FROM THE LINE ABOVE. The dimension is
//  parsed (`MIDIEventParse`, both protocols), carried (`MIDIInput
//  .onChannelPressure`) and consumed (`BioReactiveSynthVoice` →
//  `EchoelDDSP.expressionGain`, a master-gain multiply in the render block).
//  ⚠️ THREE DIMENSIONS ARE NOT MPE INPUT EITHER: no zone is detected, no member
//  channel is distinguished, and `channel` is carried here and read by nobody.
//  (This said "ONE dimension of three … `.slide`/`.airCC` still land in one
//  `break`" until #942 sounded Slide. The count moved three times; the two
//  clauses above never did, which is why they are the claim.) Store text,
//  website and `ContentPipeline/CLAIMS.md` stay untouched.
//
//  ⛔ THIS BLOCK SAID "intentionally NOT wired in this first cycle", AND THAT
//  IS THE WRONG LAYER (#770). It reads as a gap in THIS file, so a session
//  picking up the follow-up would open this class looking for a callback to
//  attach — and find nothing to attach. Measured in
//  `MIDIEventParse.event(word0:word1:)`: Channel Pressure (0xD0 in the MIDI 1.0
//  branch, 0xD in the MIDI 2.0 branch) has **no case in either switch** and
//  falls to `default: return nil`; `MIDIInEvent` has no case to carry it.
//  The byte is never parsed, so there is no callback that could ever fire.
//  The follow-up starts in `MIDIEventParse` + `MIDIInEvent` + `MIDIInput`,
//  and only THEN reaches this file. A "not wired yet" note that points at the
//  wrong file costs the next session the same search twice.
//
//  ⛔ AND THE LINE ABOVE SAID "MIDIInput already parses … + MPE wire format".
//  Parsing the bytes an MPE controller happens to send — per-channel notes,
//  bend, CC 74 — is not parsing MPE: no zone is detected and no member channel
//  is distinguished. ("and the Press dimension never arrives at all" stood here
//  until #939 parsed it and #942 sounded Slide beside it; the two clauses that
//  remain are the ones no dimension can retire.) The consumer
//  half of the same claim is pinned by
//  `Tests/CISmoke/TheMPEInputHasNoZonesTests.swift`; #770 added the
//  producer half. MPE **out** is real and shipped (#713) and is a different
//  code path (`MPEExpression` / `UMPEncoder`) — do not "correct" that one.
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

    /// ⚠️ `@ObservationIgnored` SINCE #939, and the reason is a rate change this slice caused.
    /// Notes fire this a few times a second; MPE channel pressure streams at hundreds of
    /// messages per second per channel, so a tracked write here becomes a fifth hot producer of
    /// the class `CLAUDE.md` catalogues under #919/#928 — a 10 Hz+ `@Observable` write that
    /// tears down an open `.menu` Picker in any ancestor that reads it. It has ZERO readers
    /// today (`git grep lastEventTimestamp -- Sources`), so nothing changes now; this is
    /// insurance against the future header tile that shows "last MIDI event" and freezes the
    /// app while a keyboard is being pressed.
    @ObservationIgnored
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
        midi.onChannelPressure = nil   // #939 — or press keeps publishing after stop()
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
        // #939 — Press reaches the bus. NOT thru-echoed and NOT record-teed, unlike notes:
        // `MIDIOutput` has no channel-pressure send, and the take format carries notes, so
        // adding either would be a second, unmeasured claim in the same slice.
        midi.onChannelPressure = { [weak self] pressure, channel in
            self?.publish(ControllerEvent(
                timestamp: CFAbsoluteTimeGetCurrent(),
                kind: .channelPressure,
                channel: UInt8(clamping: channel),
                note: 0,
                value: pressure,
                auxCC: 0
            ))
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
        // ⚠️ #950 — THIS STREAM IS PUBLISHED AND NOTHING CONSUMES IT, measured: `.airCC`
        // reaches exactly one consumer, `BioReactiveSynthVoice.apply(controller:)`, where it
        // is `case .airCC: break`. Two costs, both written down elsewhere in this repo:
        // `bus.controllerEvents` is a 128-deep DROP-NEWEST ring whose own doc says "a rejected
        // `.noteOff` strands its `.noteOn`". ⭐ #951 REMOVED THE SECOND, LARGER HALF: this note
        // used to add that `EngineBus.publish(controller:)` spawns a `Task { @MainActor }` PER
        // EVENT (the 10.76.48 shape, costing on every message and not only at overflow) — that
        // is now coalesced to one wake-up per batch. The QUEUE-SLOT half stands, and it is the
        // weaker of the two: it needs a real overflow, ~1280 messages/s.
        //
        // NOT changed here, deliberately. Dropping the stream is one line, but air-CC input is
        // documented as ARRIVING in seven prose sites (README, `docs/architecture.html` ×4,
        // `docs/overview.html`, and `TheMPEInputHasNoZonesTests` claim 10b), so it narrows a
        // documented wire — a value call, not an engineering one. ⭐ The deeper fix that #950
        // pointed at here IS SHIPPED (#951): the per-event Task is coalesced, which cost no
        // documented capability and helps every message type. What is left of #950's finding
        // is only the queue-slot half. See the DEAD-ENDS row in
        // `scratchpads/HARNESS_LEDGER.md`.
        //
        // NEEDS-FOUNDER-VERIFY: Wind-/Breath-Controller anschließen (CC 21–31). Soll Echoel
        // diese Nachrichten weiter ENTGEGENNEHMEN, obwohl heute nichts sie hört — oder sollen
        // sie später eine Stimme bewegen (dann bleibt die Leitung und bekommt einen
        // Verbraucher), oder gar nicht mehr ankommen (dann fällt diese Zeile und sieben
        // Prosa-Stellen mit ihr)?
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
