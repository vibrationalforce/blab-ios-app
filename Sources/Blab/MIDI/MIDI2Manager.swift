import Foundation
import CoreMIDI
import Combine

/// MIDI 2.0 Manager with Universal MIDI Packet (UMP) support
///
/// **Features:**
/// - MIDI 2.0 UMP packet encoding/decoding
/// - Virtual MIDI 2.0 source creation
/// - 32-bit parameter resolution
/// - Per-note controllers (PNC)
/// - Backwards compatible with MIDI 1.0
///
/// **Usage:**
/// ```swift
/// let midi2 = MIDI2Manager()
/// try await midi2.initialize()
///
/// // Send MIDI 2.0 note
/// midi2.sendNoteOn(channel: 0, note: 60, velocity: 0.8)
///
/// // Send per-note controller
/// midi2.sendPerNoteController(channel: 0, note: 60, controller: .brightness, value: 0.5)
/// ```
@MainActor
class MIDI2Manager: ObservableObject {

    // MARK: - Published State

    @Published var isInitialized: Bool = false
    @Published var connectedEndpoints: [MIDIEndpointRef] = []
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var midiClient: MIDIClientRef = 0
    private var virtualSource: MIDIEndpointRef = 0
    private var outputPort: MIDIPortRef = 0

    // Active notes tracking (for per-note controllers)
    private var activeNotes: Set<NoteIdentifier> = []

    private struct NoteIdentifier: Hashable {
        let channel: UInt8
        let note: UInt8
    }

    // MARK: - Initialization

    init() {}

    /// Initialize MIDI 2.0 system
    func initialize() async throws {
        guard !isInitialized else { return }

        do {
            // Create MIDI client
            var client: MIDIClientRef = 0
            let clientStatus = MIDIClientCreateWithBlock("BLAB_MIDI2_Client" as CFString, &client) { notification in
                // Handle MIDI notifications
                self.handleMIDINotification(notification)
            }

            guard clientStatus == noErr else {
                throw MIDI2Error.clientCreationFailed(Int(clientStatus))
            }

            midiClient = client

            // Create virtual MIDI 2.0 source
            var source: MIDIEndpointRef = 0
            let sourceStatus = MIDISourceCreateWithProtocol(
                midiClient,
                "BLAB MIDI 2.0 Output" as CFString,
                ._2_0,  // MIDI 2.0 protocol
                &source
            )

            guard sourceStatus == noErr else {
                throw MIDI2Error.sourceCreationFailed(Int(sourceStatus))
            }

            virtualSource = source

            // Create output port
            var port: MIDIPortRef = 0
            let portStatus = MIDIOutputPortCreate(
                midiClient,
                "BLAB_Output" as CFString,
                &port
            )

            guard portStatus == noErr else {
                throw MIDI2Error.portCreationFailed(Int(portStatus))
            }

            outputPort = port

            isInitialized = true
            print("✅ MIDI 2.0 initialized (UMP protocol)")

        } catch {
            errorMessage = "MIDI 2.0 initialization failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Cleanup MIDI resources
    func cleanup() {
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
            virtualSource = 0
        }

        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
        }

        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }

        isInitialized = false
        activeNotes.removeAll()
        print("🛑 MIDI 2.0 cleaned up")
    }

    // MARK: - MIDI Notification Handling

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        let notif = notification.pointee

        switch notif.messageID {
        case .msgSetupChanged:
            print("[MIDI2] Setup changed")
            // Rescan endpoints
            scanEndpoints()

        case .msgObjectAdded:
            print("[MIDI2] Object added")
            scanEndpoints()

        case .msgObjectRemoved:
            print("[MIDI2] Object removed")
            scanEndpoints()

        case .msgPropertyChanged:
            break  // Ignore property changes

        default:
            break
        }
    }

    /// Scan for available MIDI endpoints
    private func scanEndpoints() {
        var endpoints: [MIDIEndpointRef] = []

        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let endpoint = MIDIGetDestination(i)
            if endpoint != 0 {
                endpoints.append(endpoint)
            }
        }

        Task { @MainActor in
            self.connectedEndpoints = endpoints
        }
    }

    // MARK: - Note On/Off

    /// Send MIDI 2.0 Note On
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: Velocity (0.0-1.0)
    func sendNoteOn(channel: UInt8, note: UInt8, velocity: Float) {
        guard isInitialized else {
            print("⚠️ MIDI 2.0 not initialized")
            return
        }

        let packet = UMPPacket64.noteOn(channel: channel, note: note, velocity: velocity)
        sendUMPPacket(packet)

        // Track active note
        activeNotes.insert(NoteIdentifier(channel: channel, note: note))
    }

    /// Send MIDI 2.0 Note Off
    func sendNoteOff(channel: UInt8, note: UInt8, velocity: Float = 0.0) {
        guard isInitialized else { return }

        let packet = UMPPacket64.noteOff(channel: channel, note: note, velocity: velocity)
        sendUMPPacket(packet)

        // Remove from active notes
        activeNotes.remove(NoteIdentifier(channel: channel, note: note))
    }

    // MARK: - Per-Note Controllers

    /// Send Per-Note Controller (MIDI 2.0 exclusive)
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - controller: Controller type
    ///   - value: Controller value (0.0-1.0)
    func sendPerNoteController(channel: UInt8, note: UInt8,
                               controller: PerNoteController, value: Float) {
        guard isInitialized else { return }

        // Check if note is active
        let noteId = NoteIdentifier(channel: channel, note: note)
        guard activeNotes.contains(noteId) else {
            print("⚠️ Per-note controller sent for inactive note \(note) on channel \(channel)")
            return
        }

        let packet = UMPPacket64.perNoteController(
            channel: channel,
            note: note,
            controller: controller,
            value: value
        )

        sendUMPPacket(packet)
    }

    /// Send Per-Note Pitch Bend (MIDI 2.0)
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - bend: Pitch bend (-1.0 to +1.0, center = 0.0)
    func sendPerNotePitchBend(channel: UInt8, note: UInt8, bend: Float) {
        guard isInitialized else { return }

        let noteId = NoteIdentifier(channel: channel, note: note)
        guard activeNotes.contains(noteId) else {
            print("⚠️ Per-note pitch bend sent for inactive note \(note)")
            return
        }

        let packet = UMPPacket64.perNotePitchBend(channel: channel, note: note, bend: bend)
        sendUMPPacket(packet)
    }

    // MARK: - Channel Messages

    /// Send Channel Pressure (Aftertouch)
    func sendChannelPressure(channel: UInt8, pressure: Float) {
        guard isInitialized else { return }

        let packet = UMPPacket64.channelPressure(channel: channel, pressure: pressure)
        sendUMPPacket(packet)
    }

    /// Send Control Change (MIDI 2.0 32-bit resolution)
    func sendControlChange(channel: UInt8, controller: UInt8, value: Float) {
        guard isInitialized else { return }

        let packet = UMPPacket64.controlChange(channel: channel, controller: controller, value: value)
        sendUMPPacket(packet)
    }

    // MARK: - UMP Packet Sending

    /// Send a 64-bit UMP packet
    private func sendUMPPacket(_ packet: UMPPacket64) {
        guard virtualSource != 0 else {
            print("⚠️ Virtual source not created")
            return
        }

        var packetList = MIDIEventList()
        packetList.protocol = ._2_0
        packetList.numPackets = 1

        // Create MIDIEventPacket for UMP
        withUnsafeMutablePointer(to: &packetList.packet) { packetPtr in
            packetPtr.pointee.timeStamp = 0  // Send immediately
            packetPtr.pointee.wordCount = 2  // 64-bit packet = 2 words

            // Copy packet bytes
            let bytes = packet.bytes
            withUnsafeMutableBytes(of: &packetPtr.pointee.words) { wordsPtr in
                for (index, byte) in bytes.enumerated() {
                    wordsPtr[index] = byte
                }
            }
        }

        // Send via virtual source
        let status = MIDIReceivedEventList(virtualSource, &packetList)
        if status != noErr {
            print("⚠️ Failed to send UMP packet: \(status)")
        }
    }

    // MARK: - Utility

    /// Get info about connected MIDI 2.0 endpoints
    func getEndpointInfo() -> [String] {
        var info: [String] = []

        for endpoint in connectedEndpoints {
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)

            if let nameStr = name?.takeRetainedValue() as String? {
                info.append(nameStr)
            }
        }

        return info
    }

    /// Check if note is currently active
    func isNoteActive(channel: UInt8, note: UInt8) -> Bool {
        activeNotes.contains(NoteIdentifier(channel: channel, note: note))
    }

    /// Get count of active notes
    var activeNoteCount: Int {
        activeNotes.count
    }

    deinit {
        cleanup()
    }
}

// MARK: - Errors

enum MIDI2Error: Error, LocalizedError {
    case clientCreationFailed(Int)
    case sourceCreationFailed(Int)
    case portCreationFailed(Int)
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .clientCreationFailed(let code):
            return "MIDI client creation failed with code \(code)"
        case .sourceCreationFailed(let code):
            return "MIDI source creation failed with code \(code)"
        case .portCreationFailed(let code):
            return "MIDI port creation failed with code \(code)"
        case .notInitialized:
            return "MIDI 2.0 not initialized"
        }
    }
}
