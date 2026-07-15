#if canImport(CoreMIDI)
import Foundation
import CoreMIDI

/// Minimal CoreMIDI input receiver for MIDI 2.0, MPE, and standard MIDI.
/// Receives note on/off, CC, pitch bend from any connected MIDI device.
/// Audio-thread safe callbacks via closures.
@MainActor @Observable
final class MIDIInput {

    // MARK: - State

    var isConnected: Bool = false
    var deviceName: String = "No Device"
    var lastNote: Int = 0
    var lastVelocity: Float = 0

    // MARK: - Callbacks (set by the app's synth wiring via EngineBus/controllerEvents)

    /// Note on: (note 0-127, velocity 0-1, channel 0-15)
    var onNoteOn: ((Int, Float, Int) -> Void)?
    /// Note off: (note 0-127, channel 0-15)
    var onNoteOff: ((Int, Int) -> Void)?
    /// CC: (cc number, value 0-1, channel 0-15)
    var onCC: ((Int, Float, Int) -> Void)?
    /// Pitch bend: (value -1 to +1, channel 0-15)
    var onPitchBend: ((Float, Int) -> Void)?

    // MARK: - CoreMIDI

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0

    /// H10 (#30): the receive-thread → main-actor batch queue. Immutable +
    /// Sendable, so the nonisolated receive callback may touch it. See
    /// MIDIEventParse.swift for the flood/FIFO rationale.
    private let inQueue = MIDIInEventQueue()

    // MARK: - Init

    init() {
        setupMIDI()
    }

    // MARK: - Setup

    private func setupMIDI() {
        // Create MIDI client
        let status = MIDIClientCreateWithBlock("Echoelmusic" as CFString, &midiClient) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }
        guard status == noErr else {
            log.log(.warning, category: .system, "MIDI: Failed to create client (\(status))")
            return
        }

        // Create input port
        let portStatus = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Echoelmusic Input" as CFString,
            ._2_0,  // MIDI 2.0 protocol (backwards compatible with 1.0)
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEvents(eventList)
        }

        guard portStatus == noErr else {
            log.log(.warning, category: .system, "MIDI: Failed to create input port (\(portStatus))")
            return
        }

        // Enable RTP-MIDI (Apple network MIDI) BEFORE connecting sources, so the
        // network session shows up as a CoreMIDI source and gets connected below.
        enableNetworkMIDI()

        // Connect to all existing sources
        connectAllSources()
        log.log(.info, category: .system, "MIDI: Input ready (MIDI 2.0 + MPE + network)")
    }

    /// Turn on Apple network MIDI (RTP-MIDI, RFC 6295) via CoreMIDI's built-in
    /// session — a Tier-1 open standard, no external dependency. The device then
    /// advertises `_apple-midi._udp` (declared in Info.plist NSBonjourServices)
    /// and accepts wireless MIDI from a Mac's network session, rtpMIDI, etc.
    /// Connecting peers are picked up by `connectAllSources()` + the MIDI
    /// setup-changed notification. iOS-only API.
    private func enableNetworkMIDI() {
        #if os(iOS)
        let session = MIDINetworkSession.default()
        session.isEnabled = true
        session.connectionPolicy = .anyone
        log.log(.info, category: .system, "MIDI: network session enabled (RTP-MIDI)")
        #endif
    }

    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, source, nil)
        }
        isConnected = sourceCount > 0
        if let firstSource = (0..<sourceCount).first.map({ MIDIGetSource($0) }) {
            deviceName = getMIDIDeviceName(firstSource) ?? "MIDI Device"
        }
        log.log(.info, category: .system, "MIDI: Connected to \(sourceCount) source(s)")
    }

    // MARK: - MIDI Event Processing

    /// H10 (#30, audit): the old version reflected over `packet.words` with
    /// `Mirror` (allocation per packet on the CoreMIDI receive thread) and
    /// spawned one `Task { @MainActor }` PER EVENT — main-executor flood under
    /// a dense MPE stream, and no FIFO guarantee across separate tasks (a
    /// note-off could overtake its note-on → hung note). Now: allocation-free
    /// word reads → pure parse → batch queue → AT MOST ONE drain task per
    /// burst (order preserved, latency unchanged at one main-actor hop).
    /// As before, only the FIRST message of a packet is consumed (multi-
    /// message UMP packets were never split here — unchanged, documented).
    private nonisolated func handleMIDIEvents(_ eventList: UnsafePointer<MIDIEventList>) {
        var needDrain = false

        // Iterate packets over the ORIGINAL buffer (review MEDIUM, pre-existing
        // UB): the old `MIDIEventPacketNext(&localCopy)` computed the next
        // packet's address relative to a stack copy — for numPackets > 1 that
        // read past the copy's storage. `unsafeSequence()` walks CoreMIDI's own
        // variable-length list in place.
        for packetPtr in eventList.unsafeSequence() {
            let wordCount = Int(packetPtr.pointee.wordCount)
            if wordCount >= 1 {
                let (word0, word1): (UInt32, UInt32?) = withUnsafeBytes(of: packetPtr.pointee.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    return (words[0], wordCount >= 2 ? words[1] : nil)
                }
                if let event = MIDIEventParse.event(word0: word0, word1: word1) {
                    if inQueue.push(event) { needDrain = true }
                }
            }
        }

        if needDrain {
            Task { @MainActor [weak self] in
                self?.drainIncoming()
            }
        }
    }

    /// Main actor: empty the batch queue in FIFO order and dispatch to the
    /// existing callbacks (same signatures/behavior as the per-event tasks).
    private func drainIncoming() {
        let (events, dropped) = inQueue.drain()
        if dropped > 0 {
            log.log(.warning, category: .system,
                    "MIDI: input burst overflow — dropped \(dropped) event(s)")
        }
        for event in events {
            switch event {
            case .noteOn(let note, let velocity, let channel):
                lastNote = note
                lastVelocity = velocity
                onNoteOn?(note, velocity, channel)
            case .noteOff(let note, let channel):
                onNoteOff?(note, channel)
            case .cc(let number, let value, let channel):
                onCC?(number, value, channel)
            case .pitchBend(let value, let channel):
                onPitchBend?(value, channel)
            }
        }
    }

    // MARK: - Notifications

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged:
            connectAllSources()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func getMIDIDeviceName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return name?.takeRetainedValue() as String?
    }
}
#endif
