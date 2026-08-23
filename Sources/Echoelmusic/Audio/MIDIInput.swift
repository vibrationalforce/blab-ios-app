#if canImport(CoreMIDI)
import Foundation
import CoreMIDI

/// Minimal CoreMIDI input receiver for MIDI 1.0 and MIDI 2.0 channel-voice
/// messages. Receives note on/off, CC and pitch bend from any connected MIDI
/// device. Audio-thread safe callbacks via closures.
///
/// ⛔ THIS LINE SAID "for MIDI 2.0, MPE, and standard MIDI" AND THE MPE HALF IS
/// FALSE (#770) — the seventh surface of one claim #548 first struck, and the
/// first one that is neither prose a founder reads nor a label a player reads.
/// #766 found the sixth (the routing screen's SOURCE port, then still named
/// "MIDI / MPE In"); every surface enumerated before it was prose, and this one
/// sits one layer under the UI, in the engine's own doc comment and in the
/// `os_log` line at the end of `setupMIDI()`. **A capability claim has as many
/// surfaces as somebody enumerates**, and when every checked surface shares one
/// GATTUNG the enumeration is the thing that was incomplete.
///
/// MEASURED, not inferred: `MIDIEventParse.event(word0:word1:)` decodes exactly
/// four things in either protocol — Note On (0x90 / 0x9), Note Off (0x80 / 0x8),
/// CC (0xB0 / 0xB) and Pitch Bend (0xE0 / 0xE). **Channel Pressure (0xD0 / 0xD)
/// has no case and falls to `default: return nil`**, and `MIDIInEvent` has no
/// case to carry it. Channel pressure is MPE's Press dimension, so this receiver
/// cannot deliver it — not "not wired yet", but structurally absent one layer
/// below any wiring. Zone detection (RPN 6,6) and master-vs-member channel
/// disambiguation are likewise nowhere in this file.
///
/// What IS true and must not be over-corrected away: MPE traffic on the wire
/// still ARRIVES here as ordinary per-channel notes, bend and CC 74 — that is
/// why `MIDIEventParse`'s own header talks about a dense MPE stream flooding the
/// executor, and why `MIDIBusPublisher` can map CC 74 to `.slide`. Parsing the
/// bytes an MPE controller happens to send is not supporting MPE. MPE **out** is
/// real and shipped (#713); only the input half is the claim being retracted.
/// Guard: `Tests/CISmoke/TheMPEDimensionsReachNoVoiceTests.swift`.
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
        // FIRST, before anything that can fail. The preference must be applied even if
        // the MIDI client or input port cannot be created, because it now also carries a
        // DISABLE: `MIDINetworkSession.default().isEnabled` is persisted by CoreMIDI
        // across launches, so a user upgrading from a build that armed it would keep an
        // armed inbound listener while the new UI reads OFF. Downstream of the two
        // `guard … else { return }`s below this would fail OPEN — under the old
        // enable-only code that same position was harmless (failure meant "never
        // enabled"), which is exactly why the ordering had to move when the meaning
        // flipped. It does not depend on the client or the port. (#187, review 11a2076.)
        Self.applyNetworkSessionPreference()

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

        // (The RTP-MIDI preference was applied at the top of this function, before the
        // failure guards — so if it is ON, the network session is already a CoreMIDI
        // source by the time `connectAllSources()` runs.)
        // Connect to all existing sources
        connectAllSources()
        log.log(.info, category: .system, "MIDI: Input ready (MIDI 1.0 + 2.0 notes/CC/bend + network)")
    }

    /// Bring Apple network MIDI (RTP-MIDI, RFC 6295) in line with the user's
    /// preference — a Tier-1 open standard, no external dependency. When ON, the
    /// device advertises `_apple-midi._udp` (declared in Info.plist
    /// NSBonjourServices) and accepts wireless MIDI from a Mac's network session,
    /// rtpMIDI, etc.; connecting peers are picked up by `connectAllSources()` plus
    /// the MIDI setup-changed notification. iOS-only API.
    ///
    /// **STATIC ON PURPOSE (#187).** `MIDINetworkSession.default()` is a process
    /// singleton, so per-instance state would be a lie: two `MIDIInput`s would each
    /// believe they own a switch that is really one switch. The preference lives in
    /// `UserDefaults` and this function is the ONE place that reads it and acts. The
    /// routing UI calls exactly this after writing the key, and `setupMIDI()` calls
    /// it at launch (FIRST, before any failure guard) — one code path, so the toggle and
    /// the live session agree by construction rather than by two implementations happening
    /// to match.
    ///
    /// It used to be `enableNetworkMIDI()`, called unconditionally with
    /// `connectionPolicy = .anyone`: from launch, on every install, the instrument
    /// accepted a MIDI session from ANY host on the LAN, with no control anywhere in
    /// the app and no mention in the local-network usage string. Outbound MIDI/OSC is
    /// something you point at a destination; this ACCEPTS. Those are different
    /// consent, and only one of them was ever asked for.
    static func applyNetworkSessionPreference() {
        #if os(iOS)
        // `bool(forKey:)` is right here (unlike the play-surface level, where an unset
        // key had to fall back to 1.0): the canonical default IS false, and that is
        // exactly what `bool(forKey:)` returns for an unwritten key.
        let enabled = UserDefaults.standard.bool(forKey: StudioDefaultKeys.networkMIDI.key)
        let session = MIDINetworkSession.default()
        if enabled {
            // Set the policy alongside, so an enable never lands with a stale policy
            // from a previous session.
            session.connectionPolicy = .anyone
            session.isEnabled = true
        } else {
            // Drop established peers EXPLICITLY, then disable. `isEnabled = false`
            // should tear the session down on its own, but "should" is not good enough
            // for the off state of a network listener: if a Mac is mid-session when the
            // performer flips the switch, the honest behaviour is that the connection
            // ends. Removing first also means the peer list cannot survive as state that
            // a later enable silently reuses. Harmless when there are no connections.
            for connection in session.connections() { session.removeConnection(connection) }
            session.isEnabled = false
        }
        log.log(.info, category: .system,
                "MIDI: network session \(enabled ? "enabled" : "disabled") (RTP-MIDI, #187)")
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
