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

    private nonisolated func handleMIDIEvents(_ eventList: UnsafePointer<MIDIEventList>) {
        let list = eventList.pointee
        var packet = list.packet

        for _ in 0..<list.numPackets {
            let words = Mirror(reflecting: packet.words).children.compactMap { $0.value as? UInt32 }
            let wordCount = Int(packet.wordCount)

            if wordCount >= 1 {
                let word0 = words[0]
                let messageType = (word0 >> 28) & 0xF
                let channel = Int((word0 >> 16) & 0xF)

                switch messageType {
                case 0x2: // MIDI 1.0 Channel Voice (legacy)
                    let status = (word0 >> 16) & 0xFF
                    let data1 = Int((word0 >> 8) & 0x7F)
                    let data2 = Float(word0 & 0x7F) / 127.0

                    switch status & 0xF0 {
                    case 0x90: // Note On
                        if data2 > 0 {
                            Task { @MainActor [weak self] in
                                self?.lastNote = data1
                                self?.lastVelocity = data2
                                self?.onNoteOn?(data1, data2, channel)
                            }
                        } else {
                            Task { @MainActor [weak self] in
                                self?.onNoteOff?(data1, channel)
                            }
                        }
                    case 0x80: // Note Off
                        Task { @MainActor [weak self] in
                            self?.onNoteOff?(data1, channel)
                        }
                    case 0xB0: // CC
                        Task { @MainActor [weak self] in
                            self?.onCC?(data1, data2, channel)
                        }
                    case 0xE0: // Pitch Bend
                        let bendValue = Float(Int(data1) | (Int(word0 & 0x7F) << 7) - 8192) / 8192.0
                        Task { @MainActor [weak self] in
                            self?.onPitchBend?(bendValue, channel)
                        }
                    default: break
                    }

                case 0x4: // MIDI 2.0 Channel Voice
                    guard wordCount >= 2 else { break }
                    let word1 = words[1]
                    let statusNibble = (word0 >> 20) & 0xF

                    switch statusNibble {
                    case 0x9: // Note On (MIDI 2.0: 16-bit velocity in word1)
                        let note = Int((word0 >> 8) & 0x7F)
                        let velocity = Float(word1 >> 16) / 65535.0
                        Task { @MainActor [weak self] in
                            self?.lastNote = note
                            self?.lastVelocity = velocity
                            self?.onNoteOn?(note, velocity, channel)
                        }
                    case 0x8: // Note Off (MIDI 2.0)
                        let note = Int((word0 >> 8) & 0x7F)
                        Task { @MainActor [weak self] in
                            self?.onNoteOff?(note, channel)
                        }
                    case 0xB: // CC (MIDI 2.0: 32-bit value in word1)
                        let cc = Int((word0 >> 8) & 0x7F)
                        let value = Float(word1) / Float(UInt32.max)
                        Task { @MainActor [weak self] in
                            self?.onCC?(cc, value, channel)
                        }
                    case 0xE: // Pitch Bend (MIDI 2.0: 32-bit in word1)
                        let bend = Float(Int32(bitPattern: word1)) / Float(Int32.max)
                        Task { @MainActor [weak self] in
                            self?.onPitchBend?(bend, channel)
                        }
                    default: break
                    }

                default: break
                }
            }

            packet = MIDIEventPacketNext(&packet).pointee
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
